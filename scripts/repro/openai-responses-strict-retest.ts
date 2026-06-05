#!/usr/bin/env tsx
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import { buildOpenAIResponsesParams } from "../../src/agents/openai-transport-stream.js";
import { convertResponsesMessages } from "../../src/llm/providers/openai-responses-shared.js";
import type { AssistantMessage, Context, Model, ToolResultMessage } from "../../src/llm/types.js";

const head = spawnSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).stdout.trim();
const ZERO_USAGE = {
  input: 0,
  output: 0,
  cacheRead: 0,
  cacheWrite: 0,
  totalTokens: 0,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
} as const;

function model(): Model<any> {
  return {
    id: "gpt-5.5",
    name: "gpt-5.5",
    api: "openai-responses",
    provider: "strict-provider",
    baseUrl: "https://strict.example.invalid/v1",
    reasoning: true,
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 128000,
    maxTokens: 4096,
  };
}
function assistant(content: AssistantMessage["content"]): AssistantMessage {
  return {
    role: "assistant",
    api: "openai-responses",
    provider: "strict-provider",
    model: "gpt-5.5",
    usage: ZERO_USAGE,
    stopReason: "stop",
    timestamp: 1,
    content,
  };
}
function items(value: unknown): Array<Record<string, unknown>> {
  const input = (value as { input?: unknown[] }).input ?? value;
  return Array.isArray(input)
    ? (input.filter((x) => x && typeof x === "object") as Array<Record<string, unknown>>)
    : [];
}
function nullContent(items: Array<Record<string, unknown>>) {
  return items.filter(
    (item) => Object.prototype.hasOwnProperty.call(item, "content") && item.content === null,
  );
}
function recordAttempt(name: string, fn: () => unknown) {
  try {
    const output = fn();
    const inputItems = items(output);
    return { name, threw: false, nullContentItems: nullContent(inputItems), inputItems };
  } catch (error) {
    return { name, threw: true, error: error instanceof Error ? error.message : String(error) };
  }
}

const attempts = [
  recordAttempt("builder-empty-tool-result", () =>
    buildOpenAIResponsesParams(
      model(),
      {
        systemPrompt: "system",
        messages: [
          assistant([{ type: "toolCall", id: "call_empty|fc_empty", name: "noop", arguments: {} }]),
          {
            role: "toolResult",
            toolCallId: "call_empty|fc_empty",
            toolName: "noop",
            content: [],
            isError: false,
            timestamp: 2,
          } satisfies ToolResultMessage,
          { role: "user", content: "continue", timestamp: 3 },
        ],
        tools: [],
      } as never,
      { sessionId: "retest-90094-empty-tool-result" },
    ),
  ),
  recordAttempt("builder-text-tool-result", () =>
    buildOpenAIResponsesParams(
      model(),
      {
        systemPrompt: "system",
        messages: [
          assistant([{ type: "toolCall", id: "call_text|fc_text", name: "noop", arguments: {} }]),
          {
            role: "toolResult",
            toolCallId: "call_text|fc_text",
            toolName: "noop",
            content: [{ type: "text", text: "" }],
            isError: false,
            timestamp: 2,
          } satisfies ToolResultMessage,
          { role: "user", content: "continue", timestamp: 3 },
        ],
        tools: [],
      } as never,
      { sessionId: "retest-90094-text-tool-result" },
    ),
  ),
  recordAttempt("shared-convert-empty-tool-result", () =>
    convertResponsesMessages(
      model(),
      {
        systemPrompt: "system",
        messages: [
          assistant([
            { type: "toolCall", id: "call_shared|fc_shared", name: "noop", arguments: {} },
          ]),
          {
            role: "toolResult",
            toolCallId: "call_shared|fc_shared",
            toolName: "noop",
            content: [],
            isError: false,
            timestamp: 2,
          } satisfies ToolResultMessage,
          { role: "user", content: "continue", timestamp: 3 },
        ],
        tools: [],
      } as Context,
      new Set(["strict-provider"]),
      { replayResponsesItemIds: true },
    ),
  ),
  recordAttempt("builder-malformed-user-null-content", () =>
    buildOpenAIResponsesParams(
      model(),
      {
        systemPrompt: "system",
        messages: [{ role: "user", content: null, timestamp: 1 } as never],
        tools: [],
      } as never,
      { sessionId: "retest-90094-malformed-user-null" },
    ),
  ),
  recordAttempt("builder-malformed-assistant-null-content", () =>
    buildOpenAIResponsesParams(
      model(),
      {
        systemPrompt: "system",
        messages: [
          { ...assistant([]), content: null } as never,
          { role: "user", content: "continue", timestamp: 2 },
        ],
        tools: [],
      } as never,
      { sessionId: "retest-90094-malformed-assistant-null" },
    ),
  ),
];

const report = {
  generatedAt: new Date().toISOString(),
  head,
  issue: 90094,
  mode: "strict-repeat-codepath-retest",
  attempts,
  reproduced: attempts.some(
    (a) =>
      !a.threw &&
      Array.isArray((a as any).nullContentItems) &&
      (a as any).nullContentItems.length > 0,
  ),
  conclusion:
    "No tested real serializer path emitted content:null. Malformed null message content throws before serialization rather than producing a provider payload. Remove #90094 from formal direct-reproduction claims unless exact session-history shape is obtained.",
};
fs.mkdirSync("artifacts/repro", { recursive: true });
fs.writeFileSync(
  "artifacts/repro/openai-responses-90094-strict-retest.json",
  `${JSON.stringify(report, null, 2)}\n`,
);
fs.writeFileSync("artifacts/repro/openai-responses-90094-strict-retest.md", render(report));
console.log(JSON.stringify(report, null, 2));

function render(data: typeof report): string {
  return [
    "# #90094 strict repeat code-path retest",
    "",
    `- generatedAt: ${data.generatedAt}`,
    `- head: ${data.head}`,
    `- reproduced: ${data.reproduced}`,
    "",
    "## Conclusion",
    "",
    data.conclusion,
    "",
    "## Attempts",
    "",
    ...data.attempts.flatMap((a) => [
      `### ${a.name}`,
      "",
      "```json",
      JSON.stringify(a, null, 2),
      "```",
      "",
    ]),
  ].join("\n");
}
