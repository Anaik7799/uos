# Comprehensive Prompt: UOS Telegram Command Execution via Antigravity (AGY)

**Task ID**: `UOS-TELEGRAM-AGY-EXEC-001`  
**Target Subsystems**: `tools/telegram_client.ml` (OCaml Edge) + `apps/cepaf_gleam` (Cognitive Worker) + Antigravity CLI (`/home/an/.local/bin/agy`)  
**Criticality**: DAL-B / SIL-6 / Sovereign Autonomous Operations  
**Compliance**: `SC-ZENOH-005`, `SC-ZMOF-001`, `SC-JIDOKA-001`, `SC-SATYA-001`, `SC-CHECKLIST-001`  

---

## 1. System Context & Objective

You are the Lead Systems Architect & Autonomous Agent Engineer for the **Unified Operational System (UOS)** and **C3I Cybernetic Mesh**.

### Objective
Implement end-to-end capability enabling the human operator to submit **any command via Telegram** (`@c3i_talk_bot`) and have **Antigravity (`agy`)** execute the command on the host environment, streaming or returning verified execution results, status codes, and outputs back to Telegram with zero-muda efficiency, mathematical rigor, and strict security isolation.

---

## 2. Technical Architecture & Control Loop

```text
+----------------------------------------------------------------------------------------------------+
|                         TELEGRAM -> AGY COMMAND EXECUTION CONTROL LOOP                             |
|                                                                                                    |
|  [ Authorized Operator Telegram Client ]                                                           |
|             │                                                                                      |
|             │ 1. Inbound Command: /sh <cmd>, /agy <task>, or direct command                       |
|             ▼                                                                                      |
|  +──────────────────────────────────────────────────────────────────────────────────────────────+  |
|  | OCaml Inbound Edge Transport (tools/telegram_client.ml)                                      |  |
|  | • Fast Acknowledgment: Instant reaction (⚡ / ⏳) & "typing" action                             |  |
|  | • Ingress Validation: HMAC signature check, NUL byte trap (-2)                               |  |
|  | • Zenoh Publisher: Injects intent into indrajaal/l5/cog/intent/req                             |  |
|  +──────────────────────────────┬───────────────────────────────────────────────────────────────+  |
|                                 │                                                                  |
|                                 ▼ (Zenoh REST/TCP)                                                 |
|  +──────────────────────────────────────────────────────────────────────────────────────────────+  |
|  | UOS Pure Gleam Cognitive Worker (apps/cepaf_gleam - BEAM OTP 29 Root Supervisor)             |  |
|  | • Authorization Gate: Strictly check chat_id against Smriti.db (telegram_chat_id)            |  |
|  | • Safety Interlock: Block mutations to HARD_DENIED_SYSTEM_OS_SERIAL ("25503L801736")           |  |
|  | • Intent Classifier & Execution Router:                                                       |  |
|  |    ├─ Direct Shell Mode (/sh, /exec, /run): Executes bash command under timeout              |  |
|  |    └─ Agentic Task Mode (/agy, conversational): Invokes agy -p "<task>" --dangerously...    |  |
|  +──────────────────────────────┬───────────────────────────────────────────────────────────────+  |
|                                 │                                                                  |
|                                 ▼                                                                  |
|  +──────────────────────────────────────────────────────────────────────────────────────────────+  |
|  | Execution Substrate                                                                          |  |
|  | • Antigravity CLI (/home/an/.local/bin/agy) in print/headless mode with tool permissions     |  |
|  | • Captured stdout, stderr, exit code, and execution duration (ms)                           |  |
|  +──────────────────────────────┬───────────────────────────────────────────────────────────────+  |
|                                 │                                                                  |
|                                 ▼                                                                  |
|  +──────────────────────────────────────────────────────────────────────────────────────────────+  |
|  | Outbound Egress Pipeline                                                                     |  |
|  | • Egress Redaction: Strip exposed API tokens/secrets via egress_redactor.gleam               |  |
|  | • Output Formatter: Monospace markdown code fencing, ANSI strip, status badge                 |  |
|  | • Chunking Engine: Pure Gleam chunk_text (<= 4096 bytes per message)                         |  |
|  | • Delivery: Published to c3i/a2a/telegram/outbound or delivered via HTTPS API                 |  |
|  +──────────────────────────────────────────────────────────────────────────────────────────────+  |
+----------------------------------------------------------------------------------------------------+
```

---

## 3. Detailed Functional Requirements

### 3.1 Two Execution Modes
1. **Direct Shell Execution (`/sh <cmd>`, `/exec <cmd>`, `/run <cmd>`)**:
   - Executes arbitrary shell commands on the host (e.g. `/sh git status`, `/sh podman ps`, `/sh uptime`, `/sh systemctl --user status c3i-gleam-server`).
   - Executes with a default synchronous timeout (e.g., 30 seconds).
   - Captures combined `stdout` and `stderr`, exit code, and wall-clock execution duration in ms.
   - Formats the response in clean Telegram Markdown:
     ```markdown
     ⚡ *Shell Command Completed* `(exit: 0, 142ms)`
     *Command:* `git status -s`
     ```
     M lib/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam
     ```
     ```

2. **Autonomous Agent Execution (`/agy <prompt>` or freeform commands)**:
   - For complex coding, debugging, or system tasks (e.g., `/agy diagnose why c3i-page-watcher failed and restart it`, `/agy inspect active tasks in smriti.db and summarize them`).
   - Invokes the Antigravity CLI binary non-interactively:
     ```bash
     /home/an/.local/bin/agy -p "<prompt>" --dangerously-skip-permissions
     ```
   - Automatically passes workspace context (`/home/an/NAS-setup/uos`, `/home/an/NAS-setup/c3i`, etc.).
   - Captures the agent's full synthesis and output.

### 3.2 Long-Running Asynchronous Execution
- If a command or agent task takes longer than 2 seconds:
  - Immediately send an initial acknowledgment message or edit status: `⏳ [AGY Working] Executing command...`
  - While processing, emit periodic Telegram chat actions (`sendChatAction: typing`) every 4 seconds so the operator sees live activity.
  - Deliver the final output once complete.

### 3.3 Security, Authorization & Safety Interlocks (SIL-6 Compliance)
1. **Operator Authentication**:
   - Every inbound command MUST verify that `chat_id == authorized_chat_id` (queried from `Smriti.db` UserPreferences or environment `TELEGRAM_CHAT_ID`, e.g. `6249174059`).
   - If unauthorized, reject immediately without execution:
     ```markdown
     🛑 *Unauthorized Access Denied*
     Sender `@<username>` (`<chat_id>`) is not authorized to execute host commands.
     Security audit logged to `Smriti.db`.
     ```
2. **Hardware Storage Enclave Guard**:
   - Any shell command attempting to touch, partition, format, or mount root OS disk serial `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` must be rejected fail-closed with error `ERR_NVME_INTERLOCK_VIOLATION`.
3. **Secret Redaction**:
   - Filter all outputs through `egress_redactor.gleam` to sanitize Telegram bot tokens, GCP credentials, and SSH private keys before sending.
4. **Message Chunking**:
   - Output must be split safely across 4096-byte boundaries without breaking Markdown code fences.

---

## 4. Implementation Steps & Deliverables

### Step 1: Update Gleam Cognitive Worker Directives
Modify `apps/cepaf_gleam/src/cepaf_gleam/harness/cognitive_worker.gleam` and `telegram.gleam`:
- Add handlers for `/sh`, `/exec`, `/run`:
  - Validate authorized operator chat ID.
  - Execute via `cepaf_gleam_ffi:os_cmd/1` with timeout wrapper.
  - Format output and handle exit codes cleanly.
- Enhance `/agy` directive:
  - Execute `/home/an/.local/bin/agy -p "<prompt>" --dangerously-skip-permissions`.
  - Handle streaming/long execution without blocking BEAM actor mailboxes (using `spawn_task` or async actor pattern).

### Step 2: Enhance Telegram Edge Client (`tools/telegram_client.ml`)
- Ensure immediate acknowledgment reactions (`⚡` on command receipt).
- Ensure chat action `typing` is emitted during task processing.
- Verify `telegram_client.exe --exec-cmd` supports testing both direct shell and `/agy` commands.

### Step 3: Test Suite & Verification
1. **Unit Tests** (`apps/cepaf_gleam/test/telegram_cmd_exec_test.gleam`):
   - Test command parsing for `/sh`, `/exec`, `/run`, `/agy`.
   - Test authorization reject on unauthorized chat IDs.
   - Test output chunking on >4096 byte outputs.
   - Test secret redaction on command outputs.
2. **End-to-End Simulation**:
   - Run `tools/telegram_client.exe --exec-cmd "/sh echo hello_uos"` and assert expected response.
   - Run `tools/telegram_client.exe --exec-cmd "/sh uptime"`.
   - Run `tools/telegram_client.exe --exec-cmd "/agy who are you"`.
3. **Formal Invariant Check**:
   - Ensure zero Gleam compile errors or warnings.
   - Verify `systemctl --user status uos-cognitive-worker` and `uos-telegram-bridge` remain healthy.

---

## 5. Acceptance Criteria
- [ ] Any shell command sent via Telegram prefixed with `/sh`, `/exec`, or `/run` executes on the host and replies within Telegram.
- [ ] Any agentic task sent via `/agy <prompt>` invokes Antigravity CLI and returns the agent's work/findings.
- [ ] Unauthorized Telegram accounts cannot run commands (strictly rejected).
- [ ] Outputs larger than 4,096 bytes are automatically chunked and delivered in sequence.
- [ ] Tokens and credentials in outputs are redacted before reaching Telegram.
- [ ] All tests pass cleanly (`gleam test`).
