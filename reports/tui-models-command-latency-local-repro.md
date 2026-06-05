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

## GitHub Actions reproduction

- Workflow: `Reproduce TUI /models command latency`
- Branch: `snowzlm/openclaw:analysis/models-command-latency`
- Head SHA: `561faa38af21dc9903b989f3b862bd342d0becef`
- Run: https://github.com/snowzlm/openclaw/actions/runs/27028034880
- Job: https://github.com/snowzlm/openclaw/actions/runs/27028034880/job/79772932518
- Conclusion: `success`

GitHub-hosted runner output:

```json
{
  "reproduced": true,
  "delayMs": 2000,
  "observationMs": 500,
  "listModelsStartedAfterMs": 1,
  "listModelsResolvedAfterMs": 2003,
  "firstFeedbackAfterMs": 2003,
  "preResolveFeedbackCalls": []
}
```

The successful Actions run means the repro detected the bug in a real GitHub-hosted Ubuntu + Node 24 environment, not only on the local checkout.
