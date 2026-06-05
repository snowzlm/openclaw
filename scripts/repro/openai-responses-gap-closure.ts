#!/usr/bin/env tsx
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import { createSlackMonitorContext } from "../../extensions/slack/src/monitor/context.js";
import {
  buildOpenAIResponsesParams,
  testing as openAITransportTesting,
} from "../../src/agents/openai-transport-stream.js";
import { processResponsesStream } from "../../src/llm/providers/openai-responses-shared.js";
import type { AssistantMessage, Model, ToolResultMessage } from "../../src/llm/types.js";
import { createAssistantMessageEventStream } from "../../src/llm/utils/event-stream.js";
import { extractAssistantVisibleText } from "../../src/shared/chat-message-content.js";

const head = spawnSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).stdout.trim();
const ZERO_USAGE = {
  input: 0,
  output: 0,
  cacheRead: 0,
  cacheWrite: 0,
  totalTokens: 0,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
} as const;

type Decision = "keep-formal" | "keep-narrow" | "remove-formal";

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
    contextWindow: 128000,
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
function items(params: unknown): Array<Record<string, unknown>> {
  const input = (params as { input?: unknown[] }).input;
  return Array.isArray(input)
    ? (input.filter((x) => x && typeof x === "object") as Array<Record<string, unknown>>)
    : [];
}
function hasReplayId(item: Record<string, unknown>) {
  return (
    ["reasoning", "message", "function_call"].includes(String(item.type)) &&
    typeof item.id === "string"
  );
}
function stripReplayIdsForStorelessPatch(
  input: Array<Record<string, unknown>>,
): Array<Record<string, unknown>> {
  return input.map((item) => {
    if (!hasReplayId(item)) return item;
    const { id: _id, ...rest } = item;
    return rest;
  });
}
function slackBaseParams() {
  return {
    cfg: {} as any,
    accountId: "default",
    botToken: "token",
    app: { client: {} } as any,
    runtime: {} as any,
    botUserId: "B1",
    botId: "B1",
    teamId: "T1",
    apiAppId: "A1",
    historyLimit: 0,
    sessionScope: "per-sender" as const,
    mainKey: "main",
    dmEnabled: true,
    dmPolicy: "open" as const,
    allowFrom: [],
    allowNameMatching: false,
    groupDmEnabled: true,
    groupDmChannels: [],
    defaultRequireMention: true,
    groupPolicy: "open" as const,
    useAccessGroups: false,
    reactionMode: "off" as const,
    reactionAllowlist: [],
    replyToMode: "off" as const,
    slashCommand: {
      enabled: false,
      name: "openclaw",
      sessionPrefix: "slack:slash",
      ephemeral: true,
    },
    textLimit: 4000,
    ackReactionScope: "group-mentions",
    typingReaction: "",
    mediaMaxBytes: 1,
    threadHistoryScope: "thread" as const,
    threadInheritParent: false,
    threadRequireExplicitMention: false,
    removeAckAfterReply: false,
  };
}

const results: Array<{
  issue: number;
  decision: Decision;
  summary: string;
  evidence: Record<string, unknown>;
}> = [];

// #89728: before/after patch simulation.
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
            textSignature: JSON.stringify({ v: 1, id: "msg_prior", phase: "final_answer" }),
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
    { sessionId: "gap-89728" },
  );
  const input = items(params);
  const beforeReplayIds = input.filter(hasReplayId);
  const patched = stripReplayIdsForStorelessPatch(input);
  const afterReplayIds = patched.filter(hasReplayId);
  const functionCallIds = patched
    .filter((item) => item.type === "function_call" && typeof item.call_id === "string")
    .map((item) => item.call_id);
  const outputCallIds = patched
    .filter((item) => item.type === "function_call_output" && typeof item.call_id === "string")
    .map((item) => item.call_id);
  const callIdsPreserved =
    functionCallIds.length > 0 && functionCallIds.every((id) => outputCallIds.includes(id));
  results.push({
    issue: 89728,
    decision:
      beforeReplayIds.length > 0 && afterReplayIds.length === 0 && callIdsPreserved
        ? "keep-formal"
        : "remove-formal",
    summary:
      "before/after patch simulation confirms replay ids can be stripped for storeless custom providers while preserving call_id pairing",
    evidence: {
      beforeReplayIds,
      afterReplayIds,
      callIdsPreserved,
      functionCallIds,
      outputCallIds,
      inputTypes: input.map((i) => i.type),
    },
  });
}

// #84002: keep only Responses encrypted reasoning hazard; remove Slack empty-session routing claim.
{
  const reasoningModel = model("openai-responses");
  const params = buildOpenAIResponsesParams(
    reasoningModel,
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
              openAITransportTesting.buildOpenAIResponsesReasoningReplayMetadata(reasoningModel, {
                sessionId: "gap-84002",
              }),
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
    { sessionId: "gap-84002" },
  );
  const encryptedReasoning = items(params).find(
    (item) => item.type === "reasoning" && typeof item.encrypted_content === "string",
  );
  const slackCtx = createSlackMonitorContext(slackBaseParams());
  const topLevel = slackCtx.resolveSlackSystemEventSessionKey({
    channelId: "C123",
    channelType: "channel",
  });
  const thread = slackCtx.resolveSlackSystemEventSessionKey({
    channelId: "C123",
    channelType: "channel",
    threadTs: "111.222",
  });
  const slackEmptyMainReproduced = thread === "agent:main:main" || thread === "main";
  results.push({
    issue: 84002,
    decision: encryptedReasoning ? "keep-narrow" : "remove-formal",
    summary:
      "encrypted reasoning continuation hazard is reproduced; Slack empty-session routing is not reproduced and must be removed from formal description",
    evidence: {
      encryptedReasoning,
      slackRoutingProbe: { topLevel, thread, slackEmptyMainReproduced },
      removeDescription: [
        "Slack follow-up routed into empty/main session",
        "sessions_history/list empty loop",
      ],
    },
  });
}

// #84484: keep schema precondition only; remove duplicate Discord delivery unless a real delivery path is added.
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
    { sessionId: "gap-84484", replayResponsesItemIds: true },
  );
  const input = items(params);
  const replayedMessageWithoutReasoning =
    input.some((item) => item.type === "message" && typeof item.id === "string") &&
    !input.some((item) => item.type === "reasoning");
  // Delivery-level duplicate is intentionally not inferred from this serializer precondition.
  const duplicateDeliveryReproduced = false;
  results.push({
    issue: 84484,
    decision: replayedMessageWithoutReasoning ? "keep-narrow" : "remove-formal",
    summary:
      "provider schema precondition is reproduced; Discord duplicate delivery remains unreproduced and must be removed from formal description",
    evidence: {
      replayedMessageWithoutReasoning,
      duplicateDeliveryReproduced,
      input,
      removeDescription: ["3-5 duplicate Discord visible sends", "retry cascade sends duplicates"],
    },
  });
}

// #89531: stream parser + visible projection.
{
  const out = assistant([], "openai-responses");
  const stream = createAssistantMessageEventStream();
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
        id: "resp_gap_89531",
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
  const visibleProjection = extractAssistantVisibleText(out);
  results.push({
    issue: 89531,
    decision:
      finalBlocks.length > 1 && visibleProjection === "A\nAB\nABC"
        ? "keep-formal"
        : "remove-formal",
    summary:
      "multiple final_answer stream items survive into visible-text projection as repeated incremental content",
    evidence: {
      finalBlockCount: finalBlocks.length,
      finalTexts: finalBlocks.map((b) => (b.type === "text" ? b.text : "")),
      visibleProjection,
      expectedFixedVisibleProjection: "ABC",
    },
  });
}

// #90570: expanded Azure-style validator over actual payload.
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
    { sessionId: "gap-90570" },
  );
  const input = items(params);
  const allowedTypes = new Set([
    "message",
    "reasoning",
    "function_call",
    "function_call_output",
    "item_reference",
  ]);
  const errors: string[] = [];
  input.forEach((item, index) => {
    if (!allowedTypes.has(String(item.type)))
      errors.push(`input[${index}].type invalid: ${JSON.stringify(item.type)}`);
    if (Object.prototype.hasOwnProperty.call(item, "content") && item.content === null)
      errors.push(`input[${index}].content invalid: null`);
    if (
      item.type === "message" &&
      !["user", "assistant", "developer", "system"].includes(String(item.role))
    )
      errors.push(`input[${index}].role invalid: ${JSON.stringify(item.role)}`);
    if (item.type === "function_call" && typeof item.call_id !== "string")
      errors.push(`input[${index}].call_id missing`);
  });
  results.push({
    issue: 90570,
    decision: errors.some((e) => e.includes('type invalid: ""')) ? "keep-formal" : "remove-formal",
    summary:
      "expanded Azure-style validator rejects the actual code-path payload with empty item type",
    evidence: { errors, inputTypes: input.map((item) => item.type), input },
  });
}

const report = { generatedAt: new Date().toISOString(), head, mode: "gap-closure-retest", results };
fs.mkdirSync("artifacts/repro", { recursive: true });
fs.writeFileSync(
  "artifacts/repro/openai-responses-gap-closure.json",
  `${JSON.stringify(report, null, 2)}\n`,
);
fs.writeFileSync("artifacts/repro/openai-responses-gap-closure.md", render(report));
console.log(JSON.stringify(report, null, 2));

function render(data: typeof report): string {
  const lines = [
    "# OpenAI Responses gap closure retest",
    "",
    `- generatedAt: ${data.generatedAt}`,
    `- head: ${data.head}`,
    "",
  ];
  for (const r of data.results) {
    lines.push(`## #${r.issue}`);
    lines.push("");
    lines.push(`- decision: ${r.decision}`);
    lines.push(`- summary: ${r.summary}`);
    lines.push("");
    lines.push("```json");
    lines.push(JSON.stringify(r.evidence, null, 2));
    lines.push("```");
    lines.push("");
  }
  return lines.join("\n");
}
