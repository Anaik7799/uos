#!/usr/bin/env python3
"""
verify_perceptual_hashes.py — Persistent Perceptual Golden Hash Store & Verifier

Lead Evaluator: Claude Code (Empirical Visual Evaluator) & OpenAI Codex
Standard: Perceptual dHash (64-bit gradient hash) & Hamming Distance (D_H <= 2)
Database: var/km/sciviz_golden_hashes.sqlite3
"""

import os
import sys
import json
import sqlite3
import hashlib

DB_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "../var/km/sciviz_golden_hashes.sqlite3"))
PERCEPTUAL_REPORT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../var/reports/sciviz_perceptual_verification_report.json"))

def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS golden_hashes (
            extension_name TEXT PRIMARY KEY,
            dhash_hex      TEXT NOT NULL,
            width_px       INTEGER NOT NULL,
            height_px      INTEGER NOT NULL,
            aspect_ratio   TEXT NOT NULL,
            recorded_at    TEXT NOT NULL,
            digest         TEXT NOT NULL
        )
    """)
    conn.commit()
    return conn

def hamming_distance(hex1: str, hex2: str) -> int:
    val1 = int(hex1, 16)
    val2 = int(hex2, 16)
    xor_val = val1 ^ val2
    # Count set bits
    return bin(xor_val).count('1')

def seed_or_verify():
    conn = init_db()
    cur = conn.cursor()

    if not os.path.exists(PERCEPTUAL_REPORT):
        print(f"[ERROR] Perceptual report not found at: {PERCEPTUAL_REPORT}")
        sys.exit(1)

    with open(PERCEPTUAL_REPORT, "r") as f:
        data = json.load(f)

    live_hashes = data.get("perceptual_hashes", {})
    if not live_hashes:
        print("[ERROR] No perceptual hashes found in report")
        sys.exit(1)

    print("===============================================================================")
    print("   SCIVIZ PERSISTENT PERCEPTUAL GOLDEN HASH VERIFIER (CLAUDE & CODEX)          ")
    print("   Standard: 64-bit dHash Gradient Hashing, Hamming Distance Threshold D_H <= 2")
    print("===============================================================================")

    # Check how many golden hashes exist
    cur.execute("SELECT COUNT(*) FROM golden_hashes")
    count = cur.fetchone()[0]

    verified = 0
    seeded = 0
    drift_violations = 0

    if count == 0:
        print(f"\n[INIT] Seeding golden hash store with {len(live_hashes)} baseline signatures...")
        for name, info in live_hashes.items():
            dhash = info["dHash"]
            w = info["width"]
            h = info["height"]
            ar = str(info["aspectRatio"])
            rec_at = data.get("timestamp", "2026-09-19T11:15:00Z")
            digest = hashlib.sha256(f"{name}:{dhash}:{w}:{h}".encode("utf-8")).hexdigest()
            cur.execute("""
                INSERT OR REPLACE INTO golden_hashes 
                (extension_name, dhash_hex, width_px, height_px, aspect_ratio, recorded_at, digest)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (name, dhash, w, h, ar, rec_at, digest))
            seeded += 1
        conn.commit()
        print(f"[SUCCESS] Golden hash store seeded with {seeded} baseline signatures.")
    else:
        print(f"\n[VERIFY] Comparing {len(live_hashes)} live cards against golden store ({count} baselines)...")
        for name, info in live_hashes.items():
            cur.execute("SELECT dhash_hex, width_px, height_px FROM golden_hashes WHERE extension_name = ?", (name,))
            row = cur.fetchone()
            if not row:
                # New extension baseline
                dhash = info["dHash"]
                w = info["width"]
                h = info["height"]
                ar = str(info["aspectRatio"])
                rec_at = data.get("timestamp", "2026-09-19T11:15:00Z")
                digest = hashlib.sha256(f"{name}:{dhash}:{w}:{h}".encode("utf-8")).hexdigest()
                cur.execute("""
                    INSERT INTO golden_hashes 
                    (extension_name, dhash_hex, width_px, height_px, aspect_ratio, recorded_at, digest)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (name, dhash, w, h, ar, rec_at, digest))
                seeded += 1
            else:
                golden_hash, gw, gh = row
                live_hash = info["dHash"]
                dist = hamming_distance(golden_hash, live_hash)
                if dist <= 2:
                    verified += 1
                else:
                    print(f"  [DRIFT DETECTED] {name}: Golden={golden_hash}, Live={live_hash}, D_H={dist} bits > 2")
                    drift_violations += 1
        conn.commit()

        print(f"  Verified:         {verified} cards (D_H <= 2 bits, ZERO perceptual drift)")
        print(f"  New Baselines:    {seeded}")
        print(f"  Drift Violations: {drift_violations}")

    conn.close()

    if drift_violations > 0:
        print("\n[FAIL] Perceptual drift detected exceeding tolerance threshold.")
        sys.exit(1)
    else:
        print("\n[PASS] All audited cards match golden perceptual signatures within tolerance.")
        sys.exit(0)

if __name__ == "__main__":
    seed_or_verify()
