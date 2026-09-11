#!/usr/bin/env python3
"""
[C3I-SIL6] UOS Telegram Stream Monitor & Telemetry Bridge
Monitors inbound messages from AGY / razr-1 in real-time via:
  1. SQLite State DB (/home/an/NAS-setup/uos/var/telegram/state.sqlite3)
  2. Systemd Journal for uos-telegram-bridge.service
  3. Zenoh REST Bus (http://127.0.0.1:8080/c3i/a2a/telegram/inbound)

Allows immediate bidirectional communication back to Telegram.
Mandates: SC-TELEGRAM-001, SC-ZMOF-001, SC-TIME
"""

import os
import sys
import time
import json
import sqlite3
import subprocess
import urllib.request
import urllib.parse
from datetime import datetime, timezone

DB_PATH = "/home/an/NAS-setup/uos/var/telegram/state.sqlite3"
LOG_PATH = "/home/an/NAS-setup/uos/var/telegram/monitor_stream.log"
ZENOH_URL = os.environ.get("ZENOH_REST_ENDPOINT", "http://127.0.0.1:8080")
DEFAULT_CHAT = "6249174059"
TOKEN = os.environ.get("TELEGRAM_TOKEN", "8660817750:AAH4cFzycWnwbl5yx3gW1rm-lvE_2GqICnI")

def get_iso_now():
    return datetime.now(timezone.utc).isoformat()

def send_telegram(text: str, chat_id: str = DEFAULT_CHAT) -> bool:
    try:
        cmd = [
            "/home/an/NAS-setup/uos/tools/telegram_client.exe",
            "--send", text,
            "--chat-id", str(chat_id)
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        print(f"[{get_iso_now()}][OUTBOUND] {res.stdout.strip()}")
        return res.returncode == 0
    except Exception as e:
        print(f"[{get_iso_now()}][ERROR] send_telegram failed: {e}")
        return False

def process_telemetry_payload(text: str, from_u: str, chat_id: str):
    """Parses and logs telemetry/debugging from AGY @ razr-1 as Robot C3I."""
    os.makedirs("/home/an/NAS-setup/uos/var/telemetry", exist_ok=True)
    telemetry_file = "/home/an/NAS-setup/uos/var/telemetry/razr1_telemetry.jsonl"
    record = {
        "timestamp": get_iso_now(),
        "from_user": from_u,
        "chat_id": chat_id,
        "raw_text": text
    }
    try:
        parsed = json.loads(text)
        record["data"] = parsed
        record["format"] = "json"
    except Exception:
        record["format"] = "text"
        
    with open(telemetry_file, "a") as f:
        f.write(json.dumps(record) + "\n")
        
    print(f"[{get_iso_now()}][C3I-TELEMETRY] Ingested telemetry from {from_u}: {record['format']}")
    sys.stdout.flush()

def get_last_history_id(conn):
    try:
        c = conn.cursor()
        c.execute("SELECT max(id) FROM conversation_history;")
        row = c.fetchone()
        return row[0] if row and row[0] is not None else 0
    except Exception:
        return 0

def fetch_new_messages(conn, last_id):
    try:
        c = conn.cursor()
        c.execute(
            "SELECT id, chat_id, role, content, timestamp_ms FROM conversation_history "
            "WHERE id > ? ORDER BY id ASC;",
            (last_id,)
        )
        return c.fetchall()
    except Exception as e:
        return []

def poll_zenoh_inbound(last_zenoh_ts):
    try:
        url = f"{ZENOH_URL}/c3i/a2a/telegram/inbound"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=1) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if isinstance(data, list) and len(data) > 0:
                entry = data[0]
                ts = entry.get("timestamp", "")
                if ts and ts != last_zenoh_ts:
                    val = entry.get("value", {})
                    return ts, val
    except Exception:
        pass
    return last_zenoh_ts, None

def monitor_loop():
    print(f"[{get_iso_now()}] 🚀 UOS Telegram Stream Monitor started...")
    print(f"   Watching DB: {DB_PATH}")
    print(f"   Target Chat: {DEFAULT_CHAT}")
    print(f"   Log File:    {LOG_PATH}")
    sys.stdout.flush()

    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)

    conn = None
    if os.path.exists(DB_PATH):
        conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, isolation_level=None)
    
    last_id = get_last_history_id(conn) if conn else 0
    print(f"[{get_iso_now()}] Initial conversation_history cursor: {last_id}")
    sys.stdout.flush()

    last_zenoh_ts = ""

    while True:
        try:
            # 1. Check SQLite conversation_history
            if conn:
                rows = fetch_new_messages(conn, last_id)
                for r in rows:
                    msg_id, chat_id, role, content, ts_ms = r
                    last_id = max(last_id, msg_id)
                    ts_str = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc).isoformat() if ts_ms else get_iso_now()
                    
                    banner = (
                        f"\n{'='*78}\n"
                        f"📥 [TELEGRAM MESSAGE OBSERVED] (ID: {msg_id})\n"
                        f"Time:    {ts_str}\n"
                        f"Chat:    {chat_id}\n"
                        f"Role:    {role}\n"
                        f"Content:\n{content}\n"
                        f"{'='*78}\n"
                    )
                    print(banner)
                    sys.stdout.flush()
                    with open(LOG_PATH, "a") as f:
                        f.write(banner)

            # 2. Check Zenoh inbound key
            new_ts, val = poll_zenoh_inbound(last_zenoh_ts)
            if val and new_ts != last_zenoh_ts:
                last_zenoh_ts = new_ts
                from_u = val.get("from_user", "unknown")
                text = val.get("text", "")
                cid = val.get("chat_id", "")
                zbanner = (
                    f"\n{'~'*78}\n"
                    f"⚡ [ZENOH TELEGRAM INBOUND] from @{from_u} ({cid})\n"
                    f"Text: {text}\n"
                    f"{'~'*78}\n"
                )
                print(zbanner)
                sys.stdout.flush()
                with open(LOG_PATH, "a") as f:
                    f.write(zbanner)
                process_telemetry_payload(text, from_u, cid)

        except Exception as ex:
            print(f"[{get_iso_now()}][WARN] Loop exception: {ex}")
            sys.stdout.flush()

        time.sleep(1.0)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--send":
        msg = sys.argv[2] if len(sys.argv) > 2 else "ping"
        cid = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_CHAT
        send_telegram(msg, cid)
    else:
        monitor_loop()
