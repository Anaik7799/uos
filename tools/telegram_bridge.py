#!/usr/bin/env python3
"""
UOS Telegram Bridge (SC-ZENOH-005, SC-ZMOF-001)
Bridges Telegram Bot API with C3I / Indrajaal Zenoh mesh.
"""

import os
import sys
import json
import time
import sqlite3
import argparse
import urllib.request
import urllib.parse
import urllib.error

SMRITI_DB = "/home/an/dev/ver/c3i/data/smriti/Smriti.db"
ZENOH_REST = os.environ.get("ZENOH_REST_ENDPOINT", "http://127.0.0.1:8080")

def get_preference(key: str) -> str:
    if os.path.exists(SMRITI_DB):
        try:
            conn = sqlite3.connect(f"file:{SMRITI_DB}?mode=ro", uri=True)
            cursor = conn.cursor()
            cursor.execute("SELECT value FROM UserPreferences WHERE key = ?;", (key,))
            row = cursor.fetchone()
            conn.close()
            if row and row[0]:
                return str(row[0]).strip()
        except Exception as e:
            pass
    return os.environ.get(key.upper(), "")

def set_preference(key: str, value: str):
    if os.path.exists(SMRITI_DB):
        try:
            conn = sqlite3.connect(SMRITI_DB)
            cursor = conn.cursor()
            cursor.execute("INSERT OR REPLACE INTO UserPreferences (key, value, category) VALUES (?, ?, ?);", (key, str(value), "infra_state"))
            conn.commit()
            conn.close()
        except Exception:
            pass

def zenoh_put(key: str, payload_str: str) -> bool:
    try:
        url = f"{ZENOH_REST}/{key}"
        req = urllib.request.Request(url, data=payload_str.encode("utf-8"), method="PUT")
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=3) as resp:
            return resp.status in (200, 201)
    except Exception as e:
        return False

def telegram_api(token: str, method: str, params: dict = None) -> dict:
    url = f"https://api.telegram.org/bot{token}/{method}"
    if params:
        data = urllib.parse.urlencode(params).encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST")
    else:
        req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        return {"ok": False, "error": str(e)}

def poll_once(token: str, default_chat: str):
    offset_str = get_preference("telegram_poll_offset")
    try:
        offset = int(offset_str) if offset_str else -1
    except ValueError:
        offset = -1

    res = telegram_api(token, "getUpdates", {"offset": offset, "timeout": 2})
    if not res.get("ok"):
        print(f"[telegram-bridge] getUpdates failed: {res.get("error")}")
        return

    updates = res.get("result", [])
    print(f"[telegram-bridge] Received {len(updates)} update(s)")
    for update in updates:
        up_id = update.get("update_id")
        if up_id is not None:
            new_offset = up_id + 1
            set_preference("telegram_poll_offset", str(new_offset))

        msg = update.get("message") or update.get("channel_post")
        if not msg:
            continue

        chat_id = msg.get("chat", {}).get("id")
        text = msg.get("text", "")
        user = msg.get("from", {}).get("username") or msg.get("from", {}).get("first_name", "unknown")

        print(f"[telegram-bridge] Inbound message from {user} ({chat_id}): {text}")

        # Publish to Zenoh
        intent_payload = json.dumps({
            "id": f"tg-{up_id}",
            "source": "telegram",
            "user": user,
            "chat_id": chat_id,
            "text": text,
            "timestamp_ms": int(time.time() * 1000)
        })

        zenoh_put("indrajaal/l5/cog/intent/req", intent_payload)
        zenoh_put("c3i/a2a/telegram/inbound", intent_payload)

def main():
    parser = argparse.ArgumentParser(description="UOS Telegram Bridge")
    parser.add_argument("--once", action="store_true", help="Run a single poll cycle")
    parser.add_argument("--send", type=str, help="Send a message to default chat")
    parser.add_argument("--daemon", action="store_true", help="Run continuous loop")
    args = parser.parse_args()

    token = get_preference("telegram_token")
    chat_id = get_preference("telegram_chat_id")

    if not token:
        print("[!] No telegram_token found in Smriti.db or TELEGRAM_TOKEN env")
        sys.exit(1)

    me = telegram_api(token, "getMe")
    if not me.get("ok"):
        print(f"[!] Invalid bot token or connection failed: {me}")
        sys.exit(1)

    bot_info = me.get("result", {})
    print(f"📡 Telegram Bridge connected as @{bot_info.get("username")} (ID: {bot_info.get("id")})")
    print(f"   Default chat target: {chat_id}")
    print(f"   Zenoh REST: {ZENOH_REST}")

    if args.send:
        res = telegram_api(token, "sendMessage", {"chat_id": chat_id, "text": args.send})
        print(f"[send] Result: ok={res.get("ok")}, msg_id={res.get("result", {}).get("message_id")}")
        return

    if args.once:
        poll_once(token, chat_id)
        return

    if args.daemon:
        print("🚀 Starting Telegram Bridge daemon loop...")
        while True:
            try:
                poll_once(token, chat_id)
            except Exception as e:
                print(f"[!] Error in poll loop: {e}")
            time.sleep(2)

if __name__ == "__main__":
    main()
