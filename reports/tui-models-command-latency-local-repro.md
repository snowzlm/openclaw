# TUI `/models` command latency local reproduction

## Target

Latest upstream main at local analysis start:

- Repo: openclaw/openclaw
- Branch under test: `upstream/main`
- Local branch: `analysis/models-command-latency`
- Reproduction script: `scripts/repro/tui-models-command-latency.ts`

## Finding

The TUI `/models` handler awaits `client.listModels()` before producing any user-visible feedback. If model listing is slow, the command appears frozen: no overlay, no status/system message, and no render request occurs until the model list promise resolves.

## Local command

```bash
REPRO_MODELS_LIST_DELAY_MS=2000 REPRO_MODELS_OBSERVATION_MS=500 pnpm exec tsx scripts/repro/tui-models-command-latency.ts
```

## Local result

```json
{
  "reproduced": true,
  "delayMs": 2000,
  "observationMs": 500,
  "listModelsStartedAfterMs": 1,
  "listModelsResolvedAfterMs": 2002,
  "firstFeedbackAfterMs": 2002,
  "preResolveFeedbackCalls": [],
  "allCalls": [
    { "name": "openOverlay", "afterMs": 2002 },
    { "name": "tui.requestRender", "afterMs": 2003 },
    { "name": "tui.requestRender", "afterMs": 2003 }
  ]
}
```

## Interpretation

With a 2s model-list delay and a 500ms observation window, the command starts `listModels()` almost immediately but emits zero visible feedback before the slow operation resolves. The first render/overlay occurs only after `listModels()` completes.

This reproduces the user-visible symptom: `/models` appears unresponsive during slow model catalog/auth/listing paths.
