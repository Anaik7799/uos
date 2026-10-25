---
name: pi-prompt
description: Send a prompt to Pi-mono's multi-provider LLM engine. Pi supports 15 providers and publishes all events to Zenoh topics via C3I bridge extension.
---

# Pi Prompt — Multi-Provider LLM via Pi-mono (Zenoh-integrated)

Send a prompt to Pi-mono's multi-provider LLM engine. Pi supports 15 providers and publishes all events to Zenoh topics via C3I bridge extension.

## Usage
```
/pi-prompt <your question or task>
```

## Implementation

Execute Pi in one-shot mode with stdin from /dev/null (prevents hang):

```bash
export GOOGLE_API_KEY=${GOOGLE_API_KEY:-$GEMINI_API_KEY}
node /home/an/dev/ver/c3i/sub-projects/pi-mono/packages/coding-agent/dist/cli.js \
  --provider google --model gemini-2.5-flash \
  --print '$ARGUMENTS' </dev/null 2>&1 | grep -v "Loaded environment\|Warning\|ooda\|anthropic.*API\|Both GOOGLE"
```

After getting the response, present it to the user with a note: "Pi (Gemini 2.5 Flash) says:"

## How it works (Zenoh integration)

Every Pi invocation (even one-shot) loads the C3I bridge extension which:
1. Publishes `PiRunStarted` to `indrajaal/pi/events` via Zenoh HTTP proxy
2. Publishes inference tier selection to `indrajaal/pi/inference`
3. Publishes tool calls (if any) to `indrajaal/pi/tools`
4. Publishes `PiRunFinished` to `indrajaal/pi/events`
5. Records session metrics to smriti.db

## Alternative providers

If user requests a specific provider, change `--provider` and `--model`:
- `--provider ollama --model gemma3` — local, offline, private
- `--provider openrouter --model google/gemini-2.5-flash-preview` — OpenRouter proxy
- `--provider groq --model llama-3.3-70b-versatile` — Groq LPU (fast, free tier)

## Gleam script alternative

```bash
cd /home/an/dev/ver/c3i/sub-projects/scripts-gleam
gleam run -m scripts/pi/daemon -- prompt '$ARGUMENTS'
```

## When to use
- Second opinion from a different LLM (cross-model verification)
- Web search capabilities Pi has that Claude doesn't
- Local/offline inference (Ollama) for privacy-sensitive queries
- Cost-free inference (Google, Groq free tiers)
- Multi-model comparison for critical decisions
