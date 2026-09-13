#!/usr/bin/env python3
"""
[C3I-SIL6-MSTS] UOS TRI-LANGUAGE ZENOH & ETS STATE RUNNER (MODULAR MAX / MOJO TIER)
STAMP: SC-GLM-UI-001, SC-ZMOF-001, SC-COG-001, SC-COG-MAX-001, CHK-07-DRIVE

Enforces cross-language state sharing and consensus between Gleam (BEAM),
OCaml (Hermes), and Mojo/Python (MAX SIMD) via Zenoh pub/sub mesh (8080/7447)
and BEAM ETS (port 4100).
"""

import sys
import json
import urllib.request
import urllib.parse

HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"
ZENOH_BASE = "http://127.0.0.1:8080"
GLEAM_WISP_BASE = "http://127.0.0.1:4100"

def assert_storage_safety(payload_str: str):
    """Safety interlock check (CHK-07-DRIVE): Ensure root OS NVMe drive serial is protected."""
    if HARD_DENIED_SYSTEM_OS_SERIAL in payload_str:
        raise PermissionError(f"HARD_DENIED: root OS NVMe drive {HARD_DENIED_SYSTEM_OS_SERIAL} locked against mutation")

def http_get(url: str) -> str:
    assert_storage_safety(url)
    req = urllib.request.Request(url, headers={"User-Agent": "UOS-MAX-Mojo-Runner/1.0"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        return resp.read().decode("utf-8")

def http_put(url: str, body: str) -> str:
    assert_storage_safety(url)
    assert_storage_safety(body)
    data = body.encode("utf-8")
    req = urllib.request.Request(url, data=data, method="PUT", headers={
        "Content-Type": "text/plain",
        "User-Agent": "UOS-MAX-Mojo-Runner/1.0"
    })
    with urllib.request.urlopen(req, timeout=5) as resp:
        return resp.read().decode("utf-8")

def publish_zenoh_state(key: str, value: str):
    url = f"{ZENOH_BASE}/c3i/a2a/ets/{key}"
    print(f"[MOJO-MAX] Publishing to Zenoh: {url} -> {value}")
    resp = http_put(url, value)
    print(f"[MOJO-MAX] Zenoh publish response: {resp}")
    return True

def get_zenoh_state(key: str):
    url = f"{ZENOH_BASE}/c3i/a2a/ets/{key}"
    return http_get(url)

def put_ets_state(key: str, value: str):
    encoded_key = urllib.parse.quote(key)
    encoded_val = urllib.parse.quote(value)
    url = f"{GLEAM_WISP_BASE}/api/v1/ets/put?key={encoded_key}&val={encoded_val}"
    print(f"[MOJO-MAX] Putting to BEAM ETS via Wisp: {url}")
    resp = http_get(url)
    print(f"[MOJO-MAX] Wisp ETS put response: {resp.strip()}")
    return True

def get_ets_state(key: str):
    url = f"{GLEAM_WISP_BASE}/api/v1/ets/{urllib.parse.quote(key)}"
    return http_get(url)

def get_tri_language_state():
    url = f"{GLEAM_WISP_BASE}/api/v1/state/tri_language"
    return http_get(url)

def run_test():
    print("=" * 60)
    print("[MOJO-MAX] Starting Tri-Language Zenoh & ETS Test...")
    print("=" * 60)

    mojo_payload = "MOJO_MAX_SIMD_RANKER_ACTIVE"

    # 1. Publish Mojo state to Zenoh mesh
    publish_zenoh_state("mojo_state", mojo_payload)

    # 2. Put Mojo state into BEAM ETS
    put_ets_state("mojo_state", mojo_payload)

    # 3. Read back from Zenoh
    zenoh_val = get_zenoh_state("mojo_state")
    print(f"[MOJO-MAX] Readback from Zenoh: {zenoh_val.strip()}")
    assert mojo_payload in zenoh_val, f"Expected {mojo_payload} in Zenoh response"

    # 4. Read back from ETS
    ets_val = get_ets_state("mojo_state")
    print(f"[MOJO-MAX] Readback from ETS: {ets_val.strip()}")
    ets_json = json.loads(ets_val)
    assert ets_json.get("value") == mojo_payload, f"Expected {mojo_payload} in ETS response"

    # 5. Read Gleam state from ETS
    gleam_val = get_ets_state("gleam_state")
    print(f"[MOJO-MAX] Observed Gleam state in ETS: {gleam_val.strip()}")
    gleam_json = json.loads(gleam_val)
    assert gleam_json.get("value") == "GLEAM_OTP29_SUPERVISOR_ACTIVE"

    # 6. Read OCaml state from ETS
    ocaml_val = get_ets_state("ocaml_state")
    print(f"[MOJO-MAX] Observed OCaml state in ETS: {ocaml_val.strip()}")
    ocaml_json = json.loads(ocaml_val)
    assert ocaml_json.get("value") == "OCAML_HERMES_ORACLE_ACTIVE"

    # 7. Check full tri-language convergence
    tri_summary_str = get_tri_language_state()
    print(f"[MOJO-MAX] Tri-Language State Summary: {tri_summary_str.strip()}")
    tri_json = json.loads(tri_summary_str)

    assert tri_json.get("gleam_state") == "GLEAM_OTP29_SUPERVISOR_ACTIVE", "Gleam state mismatch"
    assert tri_json.get("ocaml_state") == "OCAML_HERMES_ORACLE_ACTIVE", "OCaml state mismatch"
    assert tri_json.get("mojo_state") == "MOJO_MAX_SIMD_RANKER_ACTIVE", "Mojo state mismatch"
    assert tri_json.get("is_converged") is True, f"Tri-language mesh expected is_converged=True, got {tri_json.get('is_converged')}"

    print("=" * 60)
    print("[MOJO-MAX] FULL TRI-LANGUAGE CONVERGENCE VERIFIED!")
    print(f"[MOJO-MAX] Gleam (BEAM): {tri_json.get('gleam_state')}")
    print(f"[MOJO-MAX] OCaml (Hermes): {tri_json.get('ocaml_state')}")
    print(f"[MOJO-MAX] Mojo/Python (MAX): {tri_json.get('mojo_state')}")
    print(f"[MOJO-MAX] Convergence: {tri_json.get('is_converged')}")
    print(f"[MOJO-MAX] Total ETS Entries: {tri_json.get('ets_entry_count')}")
    print("=" * 60)

if __name__ == "__main__":
    try:
        run_test()
        sys.exit(0)
    except Exception as e:
        print(f"[MOJO-MAX] Test failed with exception: {e}", file=sys.stderr)
        sys.exit(1)
