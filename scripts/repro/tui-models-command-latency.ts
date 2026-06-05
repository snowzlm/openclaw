// Reproduces the TUI `/models` perceived-freeze behavior on latest main.
// The command waits for client.listModels() before rendering any user-visible
// feedback, so a slow model catalog/auth path leaves the TUI looking stuck.
import { performance } from "node:perf_hooks";
import { createCommandHandlers } from "../../src/tui/tui-command-handlers.js";

type Call = { atMs: number; name: string; args: unknown[] };

function wait(ms: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

function spy(calls: Call[], name: string) {
  return (...args: unknown[]) => {
    calls.push({ atMs: performance.now(), name, args });
  };
}

async function main() {
  const delayMs = Number(process.env.REPRO_MODELS_LIST_DELAY_MS ?? "2000");
  const observationMs = Number(process.env.REPRO_MODELS_OBSERVATION_MS ?? "500");
  const startedAt = performance.now();
  const calls: Call[] = [];
  let listModelsStartedAt = 0;
  let listModelsResolvedAt = 0;

  const state = {
    currentAgentId: "main",
    currentSessionKey: "agent:main:main",
    currentSessionId: null,
    activeChatRunId: null,
    pendingOptimisticUserMessage: false,
    pendingChatRunId: null,
    activityStatus: "idle",
    isConnected: true,
    sessionInfo: {},
  };

  const client = {
    sendChat: async () => ({ runId: "run-1" }),
    getGatewayStatus: async () => ({}),
    listSessions: async () => ({ sessions: [] }),
    listModels: async () => {
      listModelsStartedAt = performance.now();
      await wait(delayMs);
      listModelsResolvedAt = performance.now();
      return [
        {
          provider: "openai",
          id: "gpt-4o-mini",
          name: "GPT-4o mini",
        },
      ];
    },
    patchSession: async () => ({}),
    resetSession: async () => ({ ok: true }),
    runGoalCommand: async () => ({ text: "Goal" }),
  };

  const { handleCommand } = createCommandHandlers({
    client: client as never,
    chatLog: {
      addUser: spy(calls, "chatLog.addUser"),
      addSystem: spy(calls, "chatLog.addSystem"),
      clearTools: spy(calls, "chatLog.clearTools"),
      reserveAssistantSlot: spy(calls, "chatLog.reserveAssistantSlot"),
    } as never,
    tui: { requestRender: spy(calls, "tui.requestRender") } as never,
    opts: {},
    state: state as never,
    deliverDefault: false,
    openOverlay: spy(calls, "openOverlay") as never,
    closeOverlay: spy(calls, "closeOverlay") as never,
    refreshSessionInfo: async () => undefined,
    loadHistory: async () => undefined,
    setSession: async () => undefined,
    setEmptySession: async () => undefined,
    refreshAgents: async () => undefined,
    abortActive: async () => undefined,
    setActivityStatus: spy(calls, "setActivityStatus") as never,
    formatSessionKey: () => "main",
    applySessionInfoFromPatch: spy(calls, "applySessionInfoFromPatch") as never,
    applySessionMutationResult: spy(calls, "applySessionMutationResult") as never,
    noteLocalRunId: spy(calls, "noteLocalRunId") as never,
    noteLocalBtwRunId: spy(calls, "noteLocalBtwRunId") as never,
    forgetLocalRunId: spy(calls, "forgetLocalRunId") as never,
    forgetLocalBtwRunId: spy(calls, "forgetLocalBtwRunId") as never,
    consumeCompletedRunForPendingSend: () => false,
    flushPendingHistoryRefreshIfIdle: () => undefined,
    requestExit: spy(calls, "requestExit") as never,
  });

  const commandPromise = handleCommand("/models");
  await Promise.resolve();
  await wait(observationMs);

  const preResolveCalls = calls.filter(
    (call) => call.atMs < listModelsResolvedAt || listModelsResolvedAt === 0,
  );
  const preResolveFeedbackCalls = preResolveCalls.filter((call) =>
    ["tui.requestRender", "chatLog.addSystem", "openOverlay", "setActivityStatus"].includes(
      call.name,
    ),
  );

  await commandPromise;

  const result = {
    reproduced: preResolveFeedbackCalls.length === 0,
    delayMs,
    observationMs,
    listModelsStartedAfterMs: Math.round(listModelsStartedAt - startedAt),
    listModelsResolvedAfterMs: Math.round(listModelsResolvedAt - startedAt),
    firstFeedbackAfterMs:
      calls
        .filter((call) =>
          ["tui.requestRender", "chatLog.addSystem", "openOverlay", "setActivityStatus"].includes(
            call.name,
          ),
        )
        .map((call) => Math.round(call.atMs - startedAt))[0] ?? null,
    preResolveFeedbackCalls: preResolveFeedbackCalls.map((call) => call.name),
    allCalls: calls.map((call) => ({
      name: call.name,
      afterMs: Math.round(call.atMs - startedAt),
    })),
  };

  console.log(JSON.stringify(result, null, 2));

  if (!result.reproduced) {
    throw new Error(
      "Expected /models to provide no user-visible feedback before slow listModels resolves",
    );
  }
}

await main();
