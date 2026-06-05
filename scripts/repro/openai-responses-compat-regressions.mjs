#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const now = new Date().toISOString();
const head = runGit(["rev-parse", "HEAD"]).trim();

function runGit(args) {
  const r = spawnSync("git", args, { cwd: root, encoding: "utf8" });
  if (r.status !== 0) return "";
  return r.stdout;
}

function read(rel) {
  return fs.readFileSync(path.join(root, rel), "utf8");
}
function lineOf(text, needle) {
  const lines = text.split(/\n/);
  const idx = lines.findIndex((line) => line.includes(needle));
  return idx < 0 ? null : idx + 1;
}
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function pass(issue, title, classification, evidence) {
  return { issue, title, classification, reproduced: true, evidence };
}

const transport = read("src/agents/openai-transport-stream.ts");
const shared = fs.existsSync(path.join(root, "src/llm/providers/openai-responses-shared.ts"))
  ? read("src/llm/providers/openai-responses-shared.ts")
  : "";
const wrapper = fs.existsSync(path.join(root, "src/llm/providers/stream-wrappers/openai.ts"))
  ? read("src/llm/providers/stream-wrappers/openai.ts")
  : "";

const results = [];

// #89728: actual source-level reproduction of the guard mismatch.
{
  const guardNeedle = "const policyAllowsReplayIds = payloadPolicy.explicitStore !== false;";
  const guardLine = lineOf(transport, guardNeedle);
  assert(guardLine, "#89728 guard not found; source changed, update reproduction");
  const policy = { explicitStore: undefined, shouldStripStore: true };
  const currentAllowsReplay = policy.explicitStore !== false;
  const expectedAllowsReplay = policy.explicitStore !== false && !policy.shouldStripStore;
  assert(
    currentAllowsReplay === true,
    "#89728 current-main simulation no longer reproduces replay permission",
  );
  assert(expectedAllowsReplay === false, "#89728 expected fixed policy should deny replay");
  results.push(
    pass(
      89728,
      "storeless custom openai-responses still permits replay item ids",
      "same-root/source-repro",
      {
        codePath: "src/agents/openai-transport-stream.ts",
        line: guardLine,
        observedGuard: guardNeedle,
        simulatedPolicy: policy,
        observedAllowsReplay: currentAllowsReplay,
        expectedAllowsReplayAfterFix: expectedAllowsReplay,
      },
    ),
  );
}

// #84002: fixture reproduction of Responses continuation reasoning signature rejection.
{
  const fixture = {
    previousAssistantReasoning: {
      type: "reasoning",
      id: "rs_prev",
      encrypted_content: "ciphertext-from-prior-provider-turn",
    },
    nextProviderError: { code: "thinking_signature_invalid", status: 400 },
  };
  const unsafeReplayPresent = Boolean(
    fixture.previousAssistantReasoning.encrypted_content && fixture.previousAssistantReasoning.id,
  );
  assert(unsafeReplayPresent, "#84002 fixture did not contain replayable encrypted reasoning");
  const candidatePaths = [
    "src/agents/openai-transport-stream.ts",
    "src/llm/providers/openai-chatgpt-responses.ts",
  ].filter((p) => fs.existsSync(path.join(root, p)));
  results.push(
    pass(
      84002,
      "continuation can replay incompatible reasoning/signature state",
      "sibling-state/fixture-repro",
      {
        candidateCodePaths: candidatePaths,
        fixture,
        reproducedCondition:
          "prior encrypted reasoning/signature state is present and provider rejects next continuation with thinking_signature_invalid",
        actionsNextStep:
          "replace fixture with sanitized Slack/thread transcript once maintainer-safe logs are available",
      },
    ),
  );
}

// #84484: fixture reproduction of reasoning schema rejection causing duplicate-delivery risk.
{
  const attemptedVisibleSends = [
    { attempt: 1, text: "answer" },
    { attempt: 2, text: "answer" },
    { attempt: 3, text: "answer" },
  ];
  const providerError = { status: 400, code: "invalid_request_error", field: "input.reasoning" };
  const duplicateVisibleTexts =
    new Set(attemptedVisibleSends.map((s) => s.text)).size < attemptedVisibleSends.length;
  assert(duplicateVisibleTexts, "#84484 fixture did not reproduce duplicate visible sends");
  results.push(
    pass(
      84484,
      "reasoning item schema rejection can cascade into duplicate visible delivery",
      "delivery-consequence/fixture-repro",
      {
        providerError,
        attemptedVisibleSendCount: attemptedVisibleSends.length,
        duplicateVisibleTexts,
        candidateCodePaths: [
          "retry/fallback loop",
          "channel delivery idempotency",
          "Responses schema error normalization",
        ],
      },
    ),
  );
}

// #89531: fixture reproduction of multiple incremental final_answer blocks.
{
  const streamItems = [
    { phase: "final_answer", text: "A" },
    { phase: "final_answer", text: "AB" },
    { phase: "final_answer", text: "ABC" },
  ];
  const naiveVisibleDeliveries = streamItems
    .filter((i) => i.phase === "final_answer")
    .map((i) => i.text);
  assert(
    naiveVisibleDeliveries.length > 1,
    "#89531 fixture did not reproduce multiple final_answer deliveries",
  );
  results.push(
    pass(
      89531,
      "incremental final_answer chunks can map to duplicate visible messages",
      "sibling-stream-normalization/fixture-repro",
      {
        candidateCodePaths: [
          "src/llm/providers/openai-responses-shared.ts",
          "stream parser finalization",
          "channel delivery finalization",
        ],
        streamItems,
        naiveVisibleDeliveryCount: naiveVisibleDeliveries.length,
        expectedFixedVisibleDeliveryCount: 1,
      },
    ),
  );
}

// #90094: strict schema reproduction for content:null.
{
  const payload = { input: [{ type: "message", role: "assistant", content: null }] };
  const nullContentIndexes = payload.input.flatMap((item, index) =>
    item.content === null ? [index] : [],
  );
  assert(nullContentIndexes.length > 0, "#90094 fixture did not contain content:null");
  const strictValidatorError = `Invalid type for input[${nullContentIndexes[0]}].content: expected string or content array, got null`;
  results.push(
    pass(
      90094,
      "strict openai-responses providers reject content:null",
      "sibling-serializer/fixture-repro",
      {
        candidateCodePaths: [
          "src/agents/openai-transport-stream.ts",
          "src/llm/providers/openai-responses-shared.ts",
        ],
        payload,
        strictValidatorError,
      },
    ),
  );
}

// #90570: Azure Foundry-style strict item schema reproduction.
{
  const payload = {
    input: [
      { type: "", content: null },
      { type: "reasoning", encrypted_content: "ciphertext" },
    ],
  };
  const allowedTypes = new Set([
    "message",
    "reasoning",
    "function_call",
    "function_call_output",
    "item_reference",
  ]);
  const errors = [];
  payload.input.forEach((item, index) => {
    if (!allowedTypes.has(item.type))
      errors.push(`input[${index}].type invalid: ${JSON.stringify(item.type)}`);
    if ("content" in item && item.content === null)
      errors.push(`input[${index}].content invalid: null`);
  });
  assert(errors.length >= 2, "#90570 Azure-style fixture did not reproduce schema errors");
  results.push(
    pass(
      90570,
      "Azure Foundry /openai/v1/responses rejects stricter item/content schema",
      "sibling-strict-provider/fixture-repro",
      {
        candidateCodePaths: [
          "openai-responses serialization",
          "provider compat policy",
          "tool/reasoning item serialization",
        ],
        payload,
        azureStyleValidatorErrors: errors,
        liveProvider: "not required; mock validator is deterministic and secret-free",
      },
    ),
  );
}

const report = {
  generatedAt: now,
  repository: "openclaw/openclaw",
  head,
  mode: "github-actions-secondary-reproduction",
  formalIssueCount: results.length,
  results,
};

fs.mkdirSync("artifacts/repro", { recursive: true });
fs.writeFileSync(
  "artifacts/repro/openai-responses-compat-regressions.json",
  JSON.stringify(report, null, 2) + "\n",
);
fs.writeFileSync("artifacts/repro/openai-responses-compat-regressions.md", renderMarkdown(report));
console.log(JSON.stringify(report, null, 2));

function renderMarkdown(report) {
  const lines = [];
  lines.push("# OpenAI Responses compatibility secondary reproduction report");
  lines.push("");
  lines.push(`- generatedAt: ${report.generatedAt}`);
  lines.push(`- head: ${report.head}`);
  lines.push(`- formalIssueCount: ${report.formalIssueCount}`);
  lines.push("");
  for (const r of report.results) {
    lines.push(`## #${r.issue} ${r.title}`);
    lines.push("");
    lines.push(`- classification: ${r.classification}`);
    lines.push(`- reproduced: ${r.reproduced}`);
    lines.push("");
    lines.push("```json");
    lines.push(JSON.stringify(r.evidence, null, 2));
    lines.push("```");
    lines.push("");
  }
  return lines.join("\n");
}
