#!/usr/bin/env node
// Manual, secretless, actual CLI/Gateway exploration; not a receipt-injection test.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import http from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { setTimeout as delay } from "node:timers/promises";

const pluginSpec = "@martian-engineering/lossless-claw@1.1.1";
const root = await mkdtemp(path.join(os.tmpdir(), "openclaw-admission-runtime-"));
const state = path.join(root, "state");
const home = path.join(root, "home");
const workspace = path.join(root, "workspace");
await Promise.all([state, home, workspace].map((dir) => mkdir(dir, { recursive: true })));
const env = {
  PATH: process.env.PATH,
  HOME: home,
  CI: "true",
  COREPACK_ENABLE_DOWNLOAD_PROMPT: "0",
  LANG: "C.UTF-8",
  OPENCLAW_STATE_DIR: state,
  OPENCLAW_CONFIG_PATH: path.join(state, "openclaw.json"),
  OPENCLAW_SKIP_CHANNELS: "1",
  OPENCLAW_SKIP_CRON: "1",
  OPENCLAW_SKIP_CANVAS_HOST: "1",
  OPENCLAW_SKIP_BROWSER_CONTROL_SERVER: "1",
  OPENCLAW_GATEWAY_TOKEN: "admission-cloud-test-only-token",
  VLLM_API_KEY: "admission-cloud-test-only-key",
  OPENCLAW_DISABLE_COMPILE_CACHE: "1",
};
let gateway;
let gatewayOutput = "";
let providerCalls = 0;
let stage = "initialize";
const results = [];
const diagnosticPattern =
  /context-engine transcript target changed before provider dispatch \{"agentIdMatches":(?:true|false),"sessionIdMatches":(?:true|false),"sessionKeyMatches":(?:true|false),"storePathMatches":(?:true|false)\}/gu;
function sanitized(text) {
  return text
    .replaceAll(root, "<isolated-test-state>")
    .replaceAll(process.cwd(), "<test-checkout>")
    .replaceAll(env.OPENCLAW_GATEWAY_TOKEN, "<test-token>")
    .replaceAll(env.VLLM_API_KEY, "<test-key>");
}
function record(value) {
  results.push(value);
  console.log(JSON.stringify(value));
}
async function cli(args, { allowFailure = false, timeoutMs = 180_000 } = {}) {
  const child = spawn("pnpm", ["openclaw", ...args], { env, stdio: ["ignore", "pipe", "pipe"] });
  let output = "";
  child.stdout.on("data", (chunk) => {
    output += chunk;
  });
  child.stderr.on("data", (chunk) => {
    output += chunk;
  });
  const timer = setTimeout(() => child.kill("SIGTERM"), timeoutMs);
  const forceTimer = setTimeout(() => child.kill("SIGKILL"), timeoutMs + 15_000);
  const [code, signal] = await once(child, "exit");
  clearTimeout(timer);
  clearTimeout(forceTimer);
  for (const diagnostic of output.match(diagnosticPattern) ?? []) record({ stage, diagnostic });
  if (!allowFailure && code !== 0)
    throw new Error(
      `CLI ${args[0]} exit=${code} signal=${signal}: ${sanitized(output.slice(-6000))}`,
    );
  return { code, output };
}
function parseJson(output) {
  // pnpm and plugin diagnostics can precede the CLI's JSON envelope.
  for (let i = 0; i < output.length; i++) {
    if (output[i] !== "{" && output[i] !== "[") continue;
    try {
      return JSON.parse(output.slice(i).trim());
    } catch {
      /* Find the complete JSON envelope. */
    }
  }
  throw new Error(`No CLI JSON envelope: ${sanitized(output.slice(-2000))}`);
}
async function freePort() {
  const server = net.createServer();
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}
// Real HTTP provider adapter exercised, but this endpoint is a stub, not inference.
const provider = http.createServer(async (request, response) => {
  let text = "";
  for await (const chunk of request) text += chunk;
  if (request.url === "/v1/models") {
    response.setHeader("content-type", "application/json");
    response.end(
      JSON.stringify({ object: "list", data: [{ id: "admission-fixture", object: "model" }] }),
    );
    return;
  }
  if (request.url !== "/v1/chat/completions") {
    response.writeHead(404);
    response.end();
    return;
  }
  const body = JSON.parse(text);
  providerCalls++;
  const base = {
    id: `fixture-${providerCalls}`,
    object: "chat.completion.chunk",
    created: 1,
    model: "admission-fixture",
  };
  if (body.stream) {
    response.writeHead(200, { "content-type": "text/event-stream" });
    const chunk = (delta, finish_reason = null) =>
      response.write(
        `data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta, finish_reason }] })}\n\n`,
      );
    chunk({ role: "assistant", content: "isolated-runtime-ok" });
    chunk({}, "stop");
    response.end("data: [DONE]\n\n");
  } else {
    response.setHeader("content-type", "application/json");
    response.end(
      JSON.stringify({
        ...base,
        object: "chat.completion",
        choices: [
          {
            index: 0,
            message: { role: "assistant", content: "isolated-runtime-ok" },
            finish_reason: "stop",
          },
        ],
        usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
      }),
    );
  }
});
provider.listen(0, "127.0.0.1");
await once(provider, "listening");
const providerPort = provider.address().port;
const gatewayPort = await freePort();
const model = "vllm/admission-fixture";
const config = {
  gateway: {
    mode: "local",
    bind: "loopback",
    port: gatewayPort,
    auth: { mode: "token", token: env.OPENCLAW_GATEWAY_TOKEN },
    controlUi: { enabled: false },
    tailscale: { mode: "off" },
  },
  discovery: { mdns: { mode: "off" } },
  update: { checkOnStart: false },
  browser: { enabled: false },
  agents: {
    ownership: "explicit",
    defaults: {
      systemAgent: { agentId: "main" },
      workspace,
      skipBootstrap: true,
      model: { primary: model },
      utilityModel: model,
      heartbeat: { every: "0m" },
      thinkingDefault: "off",
      modelPolicy: { allow: [model] },
    },
    entries: {
      main: { workspace },
      auxiliary: { workspace: path.join(root, "auxiliary-workspace") },
    },
  },
  // Supported fixed locator explores per-agent ownership with prior persisted history.
  session: { store: path.join(root, "shared", "sessions.json") },
  models: {
    mode: "merge",
    providers: {
      vllm: {
        baseUrl: `http://127.0.0.1:${providerPort}/v1`,
        apiKey: env.VLLM_API_KEY,
        api: "openai-completions",
        agentRuntime: { id: "openclaw" },
        request: { allowPrivateNetwork: true },
        models: [
          {
            id: "admission-fixture",
            name: "Disclosed HTTP stub",
            reasoning: false,
            input: ["text"],
            contextWindow: 128000,
            maxTokens: 128,
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          },
        ],
      },
    },
  },
  tools: { deny: ["*"] },
  plugins: { enabled: true, allow: ["vllm"], entries: { vllm: { enabled: true } } },
};
await mkdir(config.agents.entries.auxiliary.workspace, { recursive: true });
await writeFile(env.OPENCLAW_CONFIG_PATH, `${JSON.stringify(config, null, 2)}\n`);
async function rpc(method, params = {}) {
  const result = await cli([
    "gateway",
    "call",
    method,
    "--port",
    String(gatewayPort),
    "--params",
    JSON.stringify(params),
    "--json",
    "--timeout",
    "120000",
  ]);
  return parseJson(result.output);
}
async function stopGateway() {
  if (!gateway || gateway.exitCode !== null || gateway.signalCode !== null) return;
  const exited = once(gateway, "exit");
  gateway.kill("SIGTERM");
  const force = setTimeout(() => gateway.kill("SIGKILL"), 30_000);
  await exited;
  clearTimeout(force);
}
async function startGateway() {
  gateway = spawn("pnpm", ["openclaw", "gateway", "run"], {
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  gateway.stdout.on("data", (chunk) => {
    gatewayOutput += chunk;
  });
  gateway.stderr.on("data", (chunk) => {
    gatewayOutput += chunk;
  });
  for (let i = 0; i < 120; i++) {
    if (gateway.exitCode !== null)
      throw new Error(`Gateway exit=${gateway.exitCode}: ${sanitized(gatewayOutput.slice(-6000))}`);
    try {
      const response = await fetch(`http://127.0.0.1:${gatewayPort}/readyz`, {
        signal: AbortSignal.timeout(2000),
      });
      if (response.ok) return;
    } catch {
      /* Wait for actual process readiness. */
    }
    await delay(1000);
  }
  throw new Error(`Gateway readiness deadline: ${sanitized(gatewayOutput.slice(-6000))}`);
}
async function turn(name, key, agentId = "main") {
  stage = name;
  const before = providerCalls;
  const result = await cli(
    [
      "agent",
      "--agent",
      agentId,
      "--session-key",
      key,
      "--message",
      "Reply with the fixture acknowledgement.",
      "--json",
      "--timeout",
      "60",
    ],
    { allowFailure: true },
  );
  const diagnostic = result.output.match(diagnosticPattern);
  const envelope = parseJson(result.output);
  const calls = providerCalls - before;
  record({
    scenario: name,
    exitCode: result.code,
    providerCalls: calls,
    diagnostic: diagnostic?.[0] ?? null,
    outcome: envelope.status ?? (result.code === 0 ? "completed" : "error"),
  });
  if (diagnostic) {
    assert.equal(calls, 0, "Organic ownership rejection must precede provider request");
    return;
  }
  assert.equal(result.code, 0, `${name}: ${sanitized(result.output.slice(-4000))}`);
  assert.ok(calls > 0, `${name}: provider adapter was not reached`);
  assert.ok(result.output.includes("isolated-runtime-ok"), `${name}: stub acknowledgement missing`);
}
async function sqliteCounts() {
  const found = [];
  async function walk(dir) {
    for (const item of await readdir(dir, { withFileTypes: true })) {
      const file = path.join(dir, item.name);
      if (item.isDirectory()) await walk(file);
      else if (item.name.endsWith(".sqlite") || item.name === "lcm.db") found.push(file);
    }
  }
  await walk(state);
  const counts = [];
  for (const file of found) {
    const db = new DatabaseSync(file, { readOnly: true });
    try {
      const tables = db
        .prepare("SELECT name FROM sqlite_master WHERE type='table'")
        .all()
        .map((row) => row.name);
      for (const table of [
        "context_engine_turn_outbox",
        "messages",
        "conversations",
        "turn_advancements",
      ]) {
        if (tables.includes(table))
          counts.push({
            layer: file.endsWith("lcm.db") ? "lossless" : "core",
            table,
            count: db.prepare(`SELECT COUNT(*) AS n FROM "${table}"`).get().n,
          });
      }
    } finally {
      db.close();
    }
  }
  record({ durableReadOnlyCounts: counts });
  assert.ok(
    counts.some((row) => row.layer === "lossless" && row.table === "messages" && row.count > 0),
    "No actual lossless-claw ingestion evidence",
  );
  assert.ok(
    counts.some(
      (row) => row.layer === "lossless" && row.table === "turn_advancements" && row.count > 0,
    ),
    "No actual durable commitTurn evidence; a fallback run is not proof",
  );
}
try {
  record({
    setup: "actual source-built CLI/Gateway",
    plugin: pluginSpec,
    provider: "loopback HTTP stub; no inference",
    state: "fresh isolated temporary state",
    receipts: "production-generated only; no monkeypatches",
  });
  stage = "plugin-install";
  await cli([
    "plugins",
    "install",
    pluginSpec,
    // This reviewed, pinned npm source is authorized only in ephemeral test state.
    "--force",
    "--pin",
    "--accept-capabilities",
    "--acknowledge-install-policy-warning",
  ]);
  const installed = JSON.parse(await readFile(env.OPENCLAW_CONFIG_PATH, "utf8"));
  installed.plugins.allow = [
    ...new Set([...(installed.plugins.allow ?? []), "vllm", "lossless-claw"]),
  ];
  installed.plugins.slots = { ...installed.plugins.slots, contextEngine: "lossless-claw" };
  installed.plugins.entries["lossless-claw"] = {
    ...installed.plugins.entries["lossless-claw"],
    enabled: true,
    config: { databasePath: path.join(state, "lcm.db") },
  };
  await writeFile(env.OPENCLAW_CONFIG_PATH, `${JSON.stringify(installed, null, 2)}\n`);
  stage = "plugin-inspect";
  const inspect = await cli(["plugins", "inspect", "lossless-claw", "--runtime", "--json"]);
  record({
    pluginRegistered: inspect.code === 0,
    durableDeclaration: "atomic-idempotent-v1 with commitTurn (published plugin 1.1.1)",
  });
  stage = "gateway-start";
  await startGateway();
  await turn("fresh", "agent:main:admission-runtime");
  await turn("persisted-history", "agent:main:admission-runtime");
  await turn("supplied-uppercase-key", "AGENT:MAIN:ADMISSION-RUNTIME");
  await turn("auxiliary-fixed-store", "agent:auxiliary:admission-runtime", "auxiliary");
  stage = "create-parent-linked";
  await rpc("sessions.create", {
    key: "agent:main:admission-child",
    agentId: "main",
    parentSessionKey: "agent:main:admission-runtime",
    spawnDepth: 1,
  });
  await turn("parent-linked-public-create", "agent:main:admission-child");
  stage = "public-reset";
  await rpc("sessions.reset", { key: "agent:main:admission-runtime", reason: "reset" });
  await turn("after-public-reset", "agent:main:admission-runtime");
  stage = "restart-owned-test-gateway";
  await stopGateway();
  await startGateway();
  await turn("after-restart-persisted-history", "agent:main:admission-runtime");
  stage = "read-only-evidence";
  await stopGateway();
  await sqliteCounts();
  const diagnostics = gatewayOutput.match(diagnosticPattern) ?? [];
  record({
    organicRejections: results.filter((row) => row.diagnostic).length,
    gatewayDiagnostics: [...new Set(diagnostics)],
    totalProviderCalls: providerCalls,
    incidentRootCause: "unknown; this exploration is not an incident reproduction",
  });
} catch (error) {
  record({
    blockedAt: stage,
    error: sanitized(error instanceof Error ? error.message : String(error)),
    incidentRootCause: "unknown",
  });
  process.exitCode = 1;
} finally {
  await stopGateway();
  await new Promise((resolve) => provider.close(resolve));
  // Runner teardown disposes state; no databases/config/transcripts are uploaded.
  if (process.env.GITHUB_STEP_SUMMARY) {
    await writeFile(
      process.env.GITHUB_STEP_SUMMARY,
      `## Actual isolated runtime exploration\n\n\`\`\`json\n${JSON.stringify(results, null, 2)}\n\`\`\`\n`,
      { flag: "a" },
    );
  }
}
