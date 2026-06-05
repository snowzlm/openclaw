#!/usr/bin/env tsx
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import {
  buildOpenAIResponsesParams,
  testing as openAITransportTesting,
} from "../../src/agents/openai-transport-stream.js";
import { processResponsesStream } from "../../src/llm/providers/openai-responses-shared.js";
import type { AssistantMessage, Model, ToolResultMessage } from "../../src/llm/types.js";
import { createAssistantMessageEventStream } from "../../src/llm/utils/event-stream.js";

const head = spawnSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).stdout.trim();

const ZERO_USAGE = {
  input: 0,
  output: 0,
  cacheRead: 0,
  cacheWrite: 0,
  totalTokens: 0,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
} as const;

function model(
  api: "openai-responses" | "openai-chatgpt-responses" = "openai-responses",
): Model<any> {
  return {
    id: "gpt-5.5",
    name: "gpt-5.5",
    api,
    provider: "openai",
    baseUrl: "https://api.openai.com/v1",
    reasoning: true,
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 128_000,
    maxTokens: 4096,
  };
}

function customStorelessModel(): Model<any> {
  return {
    ...model("openai-responses"),
    provider: "custom-openai-responses",
    baseUrl: "https://custom.example.invalid/v1",
    compat: { supportsStore: false, supportsPromptCacheKey: false },
  } as Model<any>;
}

function assistant(
  content: AssistantMessage["content"],
  api: "openai-responses" | "openai-chatgpt-responses" = "openai-responses",
): AssistantMessage {
  return {
    role: "assistant",
    api,
    provider: "openai",
    model: "gpt-5.5",
    usage: ZERO_USAGE,
    stopReason: "stop",
    timestamp: 1,
    content,
  };
}

function hasOwn(obj: unknown, key: string): boolean {
  return Boolean(obj && typeof obj === "object" && Object.prototype.hasOwnProperty.call(obj, key));
}

function messageInputItems(params: unknown): Array<Record<string, unknown>> {
  const input = (params as { input?: unknown[] }).input;
  return Array.isArray(input)
    ? (input.filter((x) => x && typeof x === "object") as Array<Record<string, unknown>>)
    : [];
}

const results: Array<{
  issue: number;
  title: string;
  fidelity: string;
  reproduced: boolean;
  classification: string;
  evidence: Record<string, unknown>;
}> = [];

// #89728: real builder path. This should reproduce current-main bug.
{
  const params = buildOpenAIResponsesParams(
    customStorelessModel(),
    {
      systemPrompt: "system",
      messages: [
        assistant([
          {
            type: "thinking",
            thinking: "internal",
            thinkingSignature: JSON.stringify({ type: "reasoning", id: "rs_prior", summary: [] }),
          },
          {
            type: "text",
            text: "Checking.",
            textSignature: JSON.stringify({ v: 1, id: "msg_prior", phase: "commentary" }),
          },
          { type: "toolCall", id: "call_abc|fc_prior", name: "lookup", arguments: { q: "x" } },
        ]),
        {
          role: "toolResult",
          toolCallId: "call_abc|fc_prior",
          toolName: "lookup",
          content: [{ type: "text", text: "ok" }],
          isError: false,
          timestamp: 2,
        } satisfies ToolResultMessage,
      ],
      tools: [],
    } as never,
    { sessionId: "repro-89728" },
  );
  const input = messageInputItems(params);
  const replayedIds = input.filter(
    (item) =>
      ["reasoning", "message", "function_call"].includes(String(item.type)) && hasOwn(item, "id"),
  );
  results.push({
    issue: 89728,
    title: "storeless custom openai-responses replays prior item ids",
    fidelity: "real buildOpenAIResponsesParams code path",
    reproduced: replayedIds.length > 0,
    classification:
      replayedIds.length > 0 ? "same-root/code-path-repro" : "not-reproduced-after-upstream-change",
    evidence: {
      store: (params as { store?: unknown }).store,
      replayedIds,
      inputTypes: input.map((item) => item.type),
      expected:
        "storeless custom provider should omit prior Responses item ids while preserving call_id",
    },
  });
}

// #84002: real builder path: same-model encrypted reasoning can be replayed into next request.
{
  const params = buildOpenAIResponsesParams(
    model("openai-responses"),
    {
      systemPrompt: "system",
      messages: [
        assistant([
          {
            type: "thinking",
            thinking: "",
            thinkingSignature: JSON.stringify({
              type: "reasoning",
              id: "rs_prev",
              encrypted_content: "ciphertext",
            }),
            openclawReasoningReplay:
              openAITransportTesting.buildOpenAIResponsesReasoningReplayMetadata(
                model("openai-responses"),
                { sessionId: "repro-84002" },
              ),
          } as never,
          {
            type: "text",
            text: "Prior answer.",
            textSignature: JSON.stringify({ v: 1, id: "msg_prev", phase: "final_answer" }),
          },
        ]),
        { role: "user", content: "continue", timestamp: 2 },
      ],
      tools: [],
    } as never,
    { sessionId: "repro-84002" },
  );
  const input = messageInputItems(params);
  const encryptedReasoning = input.find(
    (item) => item.type === "reasoning" && typeof item.encrypted_content === "string",
  );
  results.push({
    issue: 84002,
    title: "continuation can serialize encrypted reasoning state into next request",
    fidelity: "real buildOpenAIResponsesParams code path",
    reproduced: Boolean(encryptedReasoning),
    classification: encryptedReasoning
      ? "sibling-state/code-path-repro"
      : "not-reproduced-with-constructed-continuation",
    evidence: {
      encryptedReasoning,
      inputTypes: input.map((item) => item.type),
      providerErrorShapeFromIssue: { status: 400, code: "thinking_signature_invalid" },
    },
  });
}

// #84484: real builder path: assistant message id can be replayed without adjacent reasoning item.
{
  const params = buildOpenAIResponsesParams(
    model("openai-responses"),
    {
      systemPrompt: "system",
      messages: [
        assistant([{ type: "text", text: "Prior answer without reasoning block." }]),
        { role: "user", content: "next", timestamp: 2 },
      ],
      tools: [],
    } as never,
    { sessionId: "repro-84484", replayResponsesItemIds: true },
  );
  const input = messageInputItems(params);
  const replayedMessage = input.find(
    (item) => item.type === "message" && typeof item.id === "string",
  );
  const hasReasoning = input.some((item) => item.type === "reasoning");
  results.push({
    issue: 84484,
    title: "message item id can be replayed without required reasoning pair",
    fidelity: "real buildOpenAIResponsesParams code path",
    reproduced: Boolean(replayedMessage && !hasReasoning),
    classification:
      replayedMessage && !hasReasoning
        ? "delivery-consequence/code-path-serializer-risk"
        : "not-reproduced-with-constructed-message",
    evidence: {
      replayedMessage,
      hasReasoning,
      inputTypes: input.map((item) => item.type),
      providerErrorShapeFromIssue:
        "Item 'msg_...' of type 'message' was provided without its required 'reasoning' item",
    },
  });
}

// #89531: real processResponsesStream path: multiple message items with final_answer produce multiple text blocks.
{
  const out = assistant([], "openai-responses");
  const stream = createAssistantMessageEventStream();
  const pushed: unknown[] = [];
  const originalPush = stream.push.bind(stream);
  (stream as unknown as { push: (event: unknown) => void }).push = (event: unknown) => {
    pushed.push(event);
    originalPush(event as never);
  };
  async function* events() {
    for (const item of [
      { id: "msg_a", phase: "final_answer", text: "A" },
      { id: "msg_b", phase: "final_answer", text: "AB" },
      { id: "msg_c", phase: "final_answer", text: "ABC" },
    ]) {
      yield {
        type: "response.output_item.added",
        item: {
          type: "message",
          id: item.id,
          role: "assistant",
          content: [],
          status: "in_progress",
          phase: item.phase,
        },
      } as never;
      yield {
        type: "response.content_part.added",
        part: { type: "output_text", text: "", annotations: [] },
      } as never;
      yield { type: "response.output_text.delta", delta: item.text } as never;
      yield {
        type: "response.output_item.done",
        item: {
          type: "message",
          id: item.id,
          role: "assistant",
          content: [{ type: "output_text", text: item.text, annotations: [] }],
          status: "completed",
          phase: item.phase,
        },
      } as never;
    }
    yield {
      type: "response.completed",
      response: {
        id: "resp_89531",
        status: "completed",
        usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 },
      },
    } as never;
  }
  await processResponsesStream(events(), out, stream, model("openai-responses"));
  const finalBlocks = out.content.filter(
    (block) =>
      block.type === "text" && JSON.parse(block.textSignature ?? "{}").phase === "final_answer",
  );
  results.push({
    issue: 89531,
    title: "multiple final_answer stream items become multiple final_answer blocks",
    fidelity: "real processResponsesStream code path",
    reproduced: finalBlocks.length > 1,
    classification:
      finalBlocks.length > 1
        ? "sibling-stream-normalization/code-path-repro"
        : "not-reproduced-after-stream-dedup",
    evidence: {
      finalAnswerBlockCount: finalBlocks.length,
      finalAnswerTexts: finalBlocks.map((block) => (block.type === "text" ? block.text : "")),
      pushedEventTypes: pushed.map((event) => (event as { type?: string }).type).filter(Boolean),
      expectedFixedFinalAnswerBlockCount: 1,
    },
  });
}

// #90094: try canonical serializer paths and explicitly report whether content:null is emitted.
{
  const params = buildOpenAIResponsesParams(
    model("openai-responses"),
    {
      systemPrompt: "system",
      messages: [
        assistant([{ type: "toolCall", id: "call_null|fc_null", name: "noop", arguments: {} }]),
        {
          role: "toolResult",
          toolCallId: "call_null|fc_null",
          toolName: "noop",
          content: [],
          isError: false,
          timestamp: 2,
        } satisfies ToolResultMessage,
        { role: "user", content: "continue", timestamp: 3 },
      ],
      tools: [],
    } as never,
    { sessionId: "repro-90094" },
  );
  const input = messageInputItems(params);
  const nullContentItems = input.filter((item) => hasOwn(item, "content") && item.content === null);
  results.push({
    issue: 90094,
    title: "strict provider rejects content:null",
    fidelity: "real buildOpenAIResponsesParams canonical serializer probe",
    reproduced: nullContentItems.length > 0,
    classification:
      nullContentItems.length > 0
        ? "sibling-serializer/code-path-repro"
        : "not-reproduced-on-canonical-serializer-probe",
    evidence: {
      nullContentItems,
      input,
      note: "Canonical tool-call/tool-result serializer probe did not emit content:null if reproduced=false; issue likely needs captured session-history shape for direct code-path reproduction.",
    },
  });
}

// #90570: real builder path can pass through invalid item type from persisted reasoning signature.
{
  const params = buildOpenAIResponsesParams(
    model("openai-responses"),
    {
      systemPrompt: "system",
      messages: [
        assistant([
          {
            type: "thinking",
            thinking: "",
            thinkingSignature: JSON.stringify({ type: "", encrypted_content: "ciphertext" }),
          },
          {
            type: "text",
            text: "after invalid item",
            textSignature: JSON.stringify({ v: 1, id: "msg_after_invalid" }),
          },
        ]),
        { role: "user", content: "next", timestamp: 2 },
      ],
      tools: [],
    } as never,
    { sessionId: "repro-90570" },
  );
  const input = messageInputItems(params);
  const emptyTypeItems = input.filter((item) => item.type === "");
  results.push({
    issue: 90570,
    title: "Azure-style strict schema rejects empty Responses item type",
    fidelity:
      "real buildOpenAIResponsesParams code path with persisted invalid reasoning signature",
    reproduced: emptyTypeItems.length > 0,
    classification:
      emptyTypeItems.length > 0
        ? "sibling-strict-provider/code-path-repro"
        : "not-reproduced-after-signature-sanitization",
    evidence: {
      emptyTypeItems,
      inputTypes: input.map((item) => item.type),
      azureStyleValidatorErrors: emptyTypeItems.map(
        (_, index) => `input[${index}].type invalid: ""`,
      ),
    },
  });
}

const report = {
  generatedAt: new Date().toISOString(),
  repository: "openclaw/openclaw",
  head,
  mode: "direct-openclaw-codepath-secondary-reproduction",
  results,
};

fs.mkdirSync("artifacts/repro", { recursive: true });
fs.writeFileSync(
  "artifacts/repro/openai-responses-codepath-regressions.json",
  `${JSON.stringify(report, null, 2)}\n`,
);
fs.writeFileSync("artifacts/repro/openai-responses-codepath-regressions.md", render(report));
console.log(JSON.stringify(report, null, 2));

function render(data: typeof report): string {
  const lines = [
    "# OpenAI Responses direct code-path secondary reproduction report",
    "",
    `- generatedAt: ${data.generatedAt}`,
    `- head: ${data.head}`,
    `- mode: ${data.mode}`,
    "",
  ];
  for (const result of data.results) {
    lines.push(`## #${result.issue} ${result.title}`);
    lines.push("");
    lines.push(`- fidelity: ${result.fidelity}`);
    lines.push(`- classification: ${result.classification}`);
    lines.push(`- reproduced: ${result.reproduced}`);
    lines.push("");
    lines.push("```json");
    lines.push(JSON.stringify(result.evidence, null, 2));
    lines.push("```");
    lines.push("");
  }
  return lines.join("\n");
}
