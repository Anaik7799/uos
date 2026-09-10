#!/usr/bin/env python3
"""
[C3I-SIL6-MSTS] UOS Telegram Message & Response Monitor via OpenRouter Gemma 4
Monitors inbound Telegram messages and outbound cybernetic responses,
evaluating correctness, completeness, and adherence to UOS ground truth using google/gemma-4-31b-it.
"""

import os
import sys
import json
import time
import urllib.request
import urllib.error
from typing import Dict, Any, List

OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
PRIMARY_MODEL = "google/gemma-4-26b-a4b-it"
FALLBACK_MODEL = "google/gemma-4-31b-it"

UOS_GROUND_TRUTH = """
UOS Ground Truth Architecture & Command Registry:
The Unified Operational System (UOS) Telegram Cybernetic Cockpit provides 48 operational directives across 4 domains:

Domain A (Foundational SRE & Cluster Governance - 13 directives):
/status, /storage, /plan, /cockpit, /approval, /andon, /zk, /wiki, /checklist, /dark, /zigvm, /help, /start

Domain B (Advanced SRE & Autonomous Disaster Recovery - 11 directives):
/resuscitate, /chaos, /repro, /merge, /bisect, /escalate, /rotate-keys, /mesh, /migrate, /adr, /blast-radius

Domain C (Creative Cybernetics & FinOps Resource Optimization - 12 directives):
/pacing, /whatif, /rack-cv, /acoustic, /rewind, /postmortem, /finops, /eco-schedule, /radar, /canvas, /lockbox, /export-audit

Domain D (Team Collaboration & Multi-Party Voice Cybernetics - 12 directives):
/sidecar, /voice-roll-call, /babel, /whiteboard, /socratic, /handover, /pair-voice, /exec-brief, /commitments, /acoustic-hud, /retro, /gameday

Key System Invariants:
1. HARD_DENIED_SYSTEM_OS_SERIAL = "[REDACTED_SYSTEM_OS_SERIAL]" (NVMe Bay 0 cannot be wiped or pulled).
2. Sa-Plan canonical authority in var/sa-plan/uos.sqlite3 (SC-SA-PLAN-001, SC-JIDOKA-001).
3. 2oo3 multi-party constitutional quorum required for mutating operations.
4. Zero-Muda Purity (0 Bevy, 0 Graphite, pure BEAM OTP 29 & Hermes OCaml).
"""

import subprocess

def call_gemma4(prompt: str, model: str = PRIMARY_MODEL) -> Dict[str, Any]:
    if not OPENROUTER_API_KEY:
        raise ValueError("OPENROUTER_API_KEY is not set in environment")
    
    url = "https://openrouter.ai/api/v1/chat/completions"
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": f"You are the authoritative UOS Quality & Correctness Evaluator powered by Gemma 4.\n"
                           f"Evaluate Telegram conversations with the UOS Cockpit Bot (@c3i_talk_bot).\n"
                           f"Use this Ground Truth Reference:\n{UOS_GROUND_TRUTH}\n"
                           f"Provide your evaluation in structured JSON format with fields: "
                           f"understanding_summary, correctness_score (0-100), completeness_score (0-100), "
                           f"verdict ('PASS', 'MARGINAL', 'FAIL'), discrepancies (list), analysis, recommended_response."
            },
            {
                "role": "user",
                "content": prompt
            }
        ],
        "temperature": 0.1,
        "max_tokens": 1500
    }
    
    cmd = [
        "curl", "-s", "-4", "--max-time", "20",
        "-X", "POST", url,
        "-H", f"Authorization: Bearer {OPENROUTER_API_KEY}",
        "-H", "Content-Type: application/json",
        "-H", "HTTP-Referer: http://nas-1.tail55d152.ts.net:4100",
        "-H", "X-Title: UOS-Telegram-Gemma4-Monitor",
        "-d", json.dumps(payload)
    ]
    
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        if model != FALLBACK_MODEL:
            print(f"[Warn] Curl failed with code {res.returncode}, falling back to {FALLBACK_MODEL}...")
            return call_gemma4(prompt, model=FALLBACK_MODEL)
        raise RuntimeError(f"Curl failed: {res.stderr}")
    
    try:
        res_json = json.loads(res.stdout)
        if "choices" in res_json and len(res_json["choices"]) > 0:
            content = res_json["choices"][0]["message"]["content"]
            return {
                "raw_content": content,
                "model": res_json.get("model", model),
                "usage": res_json.get("usage", {})
            }
        else:
            if model != FALLBACK_MODEL:
                print(f"[Warn] OpenRouter error ({res.stdout}), falling back to {FALLBACK_MODEL}...")
                return call_gemma4(prompt, model=FALLBACK_MODEL)
            raise RuntimeError(f"OpenRouter response error: {res.stdout}")
    except Exception as e:
        if model != FALLBACK_MODEL:
            print(f"[Warn] JSON parse failed ({e}), falling back to {FALLBACK_MODEL}...")
            return call_gemma4(prompt, model=FALLBACK_MODEL)
        raise

def evaluate_interaction(user_msg: str, bot_resp: str, sender: str = "@Avi", msg_id: int = 0) -> Dict[str, Any]:
    prompt = f"""
Evaluate the following Telegram interaction:
- Sender: {sender} (Message ID: {msg_id})
- Inbound User Message: "{user_msg}"
- Outbound Bot Response:
\"\"\"
{bot_resp}
\"\"\"

Carefully evaluate:
1. Did the bot understand the specific intent of the user?
2. If the user asked "what are the commands supported", did the response provide the actual full list of 48 directives across all 4 domains (A, B, C, D), or only a partial/truncated subset?
3. If the user asked "is this the full list", did the bot answer directly (e.g. clarify that 13 was only a subset and 48 total commands exist), or did it repeat a canned response?
4. Is the information technically accurate according to UOS specifications?
5. Rate correctness (0-100), completeness (0-100), and assign verdict PASS/MARGINAL/FAIL.
"""
    result = call_gemma4(prompt)
    return result

def main():
    print("================================================================================")
    print("🛡️  UOS TELEGRAM MESSAGE & RESPONSE MONITOR (OPENROUTER GEMMA 4)")
    print(f"    Evaluator Model: {PRIMARY_MODEL}")
    print("================================================================================")
    
    interactions = [
        {
            "id": 2156,
            "sender": "@Avi",
            "time": "2026-09-10 06:35:25",
            "inbound": "what are the commands supported",
            "response": """🌟 *AGY Sovereign Agent Synthesis* (Google DeepMind Antigravity)
👑 *Role:* Sovereign Cognitive Architect & Swarm Coordinator | `#fractal-l5`

Greetings, @Avi! Your inquiry has been processed through the **UOS Gleam 4-Phase OODA Substrate**.

• *Query Received:* "what are the commands supported"
• *Cognitive Authority:* `worker-agy` (Tri-Sovereign Governance)
• *Execution Paradigm:* In-Process Pure BEAM (Zero Subprocess Muda)

### 🧠 Cognitive Reasoning & State Assessment
The system has verified active invariants across all 10 fractal layers ($L_0 \dots L_9$). Zero drift detected. Lyapunov convergence $\dot{V} \le 0$ confirmed across mesh actors.

### ⚡ Live Native NIF Substrate Evidence
• *Cluster Health (`c3i_nif:system_health`):* `{"status":"ok","interface":"wisp","port":4100,"version":"1.0.0","container_count":16,"healthy_count":16,"threat_level":"nominal","ooda_phase":"observe","dark_cockpit_mode":"dark","zenoh_connected":true,"quorum_healthy":true}`
• *Sa-Plan Ledger (`c3i_nif:plan_status`):* `{"active":0,"pending":1,"completed":3176,"blocked":0,"total":3177}`
• *Hardware NVMe Interlock:* `HARD_DENIED_SYSTEM_OS_SERIAL = 25503L801736` (Locked)
• *Zero-Muda Purity:* 0 Bevy, 0 Graphite, 100% Pure BEAM & Hermes OCaml

### 🧭 Sovereign Command Navigation
You can issue direct commands anytime:
• `/status` - Live cluster telemetry & service health
• `/plan` - Current active & pending Sa-plan tasks
• `/search <query>` - Deep search across tasks & knowledge
• `/immune` - Chaos immunity & antibody defense status
• `/fmea` - Failure modes & reliability metrics
• `/ha` - High availability cluster election & lease TTL
• `/zenoh` - Zenoh mesh topics and endpoints
• `/verify` - Formal Gospel contracts & SIL validation
• `/km` - Knowledge management provenance & Shannon entropy
• `/wiki [topic]` - Hermes living wiki transclusion lookup
• `/zk [adr]` - Architectural decision records (ADR-001..ADR-099)
• `/zigvm` - Deterministic sandbox execution
• `/cockpit` - Full Tailscale FQDN web dashboard directory

🔗 [Cockpit Dashboard](http://nas-1.tail55d152.ts.net:4100/) | [Planning](http://nas-1.tail55d152.ts.net:4100/planning) | [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) | [ZK MOC](http://nas-1.tail55d152.ts.net:4100/zk)"""
        },
        {
            "id": 2158,
            "sender": "@Avi",
            "time": "2026-09-10 06:36:42",
            "inbound": "is this the full list",
            "response": """🌟 *AGY Sovereign Agent Synthesis* (Google DeepMind Antigravity)
👑 *Role:* Sovereign Cognitive Architect & Swarm Coordinator | `#fractal-l5`

Greetings, @Avi! Your inquiry has been processed through the **UOS Gleam 4-Phase OODA Substrate**.

• *Query Received:* "is this the full list"
• *Cognitive Authority:* `worker-agy` (Tri-Sovereign Governance)
• *Execution Paradigm:* In-Process Pure BEAM (Zero Subprocess Muda)

### 🧠 Cognitive Reasoning & State Assessment
The system has verified active invariants across all 10 fractal layers ($L_0 \dots L_9$). Zero drift detected. Lyapunov convergence $\dot{V} \le 0$ confirmed across mesh actors.

### ⚡ Live Native NIF Substrate Evidence
• *Cluster Health (`c3i_nif:system_health`):* `{"status":"ok","interface":"wisp","port":4100,"version":"1.0.0","container_count":16,"healthy_count":16,"threat_level":"nominal","ooda_phase":"observe","dark_cockpit_mode":"dark","zenoh_connected":true,"quorum_healthy":true,"last_updated_ms":1789015003389}`
• *Sa-Plan Ledger (`c3i_nif:plan_status`):* `{"active":0,"pending":1,"completed":3176,"blocked":0,"total":3177}`
• *Hardware NVMe Interlock:* `HARD_DENIED_SYSTEM_OS_SERIAL = 25503L801736` (Locked)
• *Zero-Muda Purity:* 0 Bevy, 0 Graphite, 100% Pure BEAM & Hermes OCaml

### 🧭 Sovereign Command Navigation
You can issue direct commands anytime:
• `/status` - Live cluster telemetry & service health
• `/plan` - Current active & pending Sa-plan tasks
• `/search <query>` - Deep search across tasks & knowledge
• `/immune` - Chaos immunity & antibody defense status
• `/fmea` - Failure modes & reliability metrics
• `/ha` - High availability cluster election & lease TTL
• `/zenoh` - Zenoh mesh topics and endpoints
• `/verify` - Formal Gospel contracts & SIL validation
• `/km` - Knowledge management provenance & Shannon entropy
• `/wiki [topic]` - Hermes living wiki transclusion lookup
• `/zk [adr]` - Architectural decision records (ADR-001..ADR-099)
• `/zigvm` - Deterministic sandbox execution
• `/cockpit` - Full Tailscale FQDN web dashboard directory

🔗 [Cockpit Dashboard](http://nas-1.tail55d152.ts.net:4100/) | [Planning](http://nas-1.tail55d152.ts.net:4100/planning) | [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) | [ZK MOC](http://nas-1.tail55d152.ts.net:4100/zk)"""
        },
        {
            "id": 2154,
            "sender": "@Avi",
            "time": "2026-09-09 23:41:32",
            "inbound": "Does system have homeostasis",
            "response": """🌟 *AGY Sovereign Agent Synthesis* (Google DeepMind Antigravity)
👑 *Role:* Sovereign Cognitive Architect & Swarm Coordinator | `#fractal-l5`

Greetings, @Avi! Your inquiry has been processed through the **UOS Gleam 4-Phase OODA Substrate**.

• *Query Received:* "Does system have homeostasis"
• *Cognitive Authority:* `worker-agy` (Tri-Sovereign Governance)
• *Execution Paradigm:* In-Process Pure BEAM (Zero Subprocess Muda)

### 🧠 Cognitive Reasoning & State Assessment
The system has verified active invariants across all 10 fractal layers ($L_0 \dots L_9$). Zero drift detected. Lyapunov convergence $\dot{V} \le 0$ confirmed across mesh actors.

### ⚡ Live Native NIF Substrate Evidence
• *Cluster Health (`c3i_nif:system_health`):* `{"status":"ok","interface":"wisp","port":4100,"version":"1.0.0","container_count":16,"healthy_count":16,"threat_level":"nominal","ooda_phase":"observe","dark_cockpit_mode":"dark","zenoh_connected":true,"quorum_healthy":true}`
• *Sa-Plan Ledger (`c3i_nif:plan_status`):* `{"active":0,"pending":1,"completed":3176,"blocked":0,"total":3177}`
• *Hardware NVMe Interlock:* `HARD_DENIED_SYSTEM_OS_SERIAL = 25503L801736` (Locked)
• *Zero-Muda Purity:* 0 Bevy, 0 Graphite, 100% Pure BEAM & Hermes OCaml"""
        }
    ]
    
    evaluations = []
    for item in interactions:
        print(f"\nEvaluating Msg {item['id']} from {item['sender']}: '{item['inbound']}'...")
        eval_res = evaluate_interaction(
            user_msg=item["inbound"],
            bot_resp=item["response"],
            sender=item["sender"],
            msg_id=item["id"]
        )
        evaluations.append({
            "interaction": item,
            "evaluation": eval_res
        })
        print(f" -> Completed evaluation with {eval_res['model']}")
        print(f" -> Response Snippet:\n{eval_res['raw_content'][:300]}...\n")
        time.sleep(1)
        
    out_file = "/home/an/NAS-setup/uos/var/telegram/gemma4_evaluations.json"
    os.makedirs(os.path.dirname(out_file), exist_ok=True)
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(evaluations, f, indent=2)
    print(f"✅ All evaluations saved to {out_file}")

if __name__ == "__main__":
    main()
