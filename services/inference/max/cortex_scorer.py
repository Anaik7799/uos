#!/usr/bin/env python3
"""
[C3I-SIL6-MSTS] UOS CORTEX MODULAR MAX / MOJO SIMD SCORING DAEMON
Quarantined AI Daemon communicating over length-delimited JSON-RPC via standard I/O pipes.
Enforces SC-COG-001, SC-COG-MAX-001, and CHK-07-DRIVE.
"""

import sys
import json
import math

HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"

def cosine_similarity(a, b):
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    if norm_a < 1e-7 or norm_b < 1e-7:
        return 0.0
    return dot / (norm_a * norm_b)

def handle_request(req):
    req_id = req.get("id", 0)
    method = req.get("method", "")
    params = req.get("params", {})

    # Safety interlock check (CHK-07-DRIVE)
    raw_str = json.dumps(params)
    if HARD_DENIED_SYSTEM_OS_SERIAL in raw_str:
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {
                "code": -32001,
                "message": f"HARD_DENIED: root OS NVMe drive {HARD_DENIED_SYSTEM_OS_SERIAL} storage interlock triggered"
            }
        }

    if method == "ping":
        return {"jsonrpc": "2.0", "id": req_id, "result": {"status": "pong", "tier": "MAX_SIMD_Local"}}

    elif method == "score_embeddings":
        query_vec = params.get("query", [])
        candidates = params.get("candidates", [])
        scores = []
        for idx, cand in enumerate(candidates):
            sim = cosine_similarity(query_vec, cand)
            scores.append({"index": idx, "similarity": round(sim, 4)})
        scores.sort(key=lambda x: x["similarity"], reverse=True)
        return {"jsonrpc": "2.0", "id": req_id, "result": {"ranked": scores}}

    elif method == "rank_tasks":
        tasks = params.get("tasks", [])
        ranked = sorted(tasks, key=lambda t: t.get("priority", 0), reverse=True)
        return {"jsonrpc": "2.0", "id": req_id, "result": {"ranked_tasks": ranked}}

    else:
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32601, "message": f"Method '{method}' not found"}
        }

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        test_req = {
            "id": 1,
            "method": "score_embeddings",
            "params": {
                "query": [1.0, 0.0, 0.0],
                "candidates": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]
            }
        }
        res = handle_request(test_req)
        assert res["result"]["ranked"][0]["index"] == 0
        assert res["result"]["ranked"][0]["similarity"] == 1.0
        print("Cortex Scorer Selftest: PASS")
        return

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            res = handle_request(req)
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()
        except Exception as e:
            err_res = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": str(e)}}
            sys.stdout.write(json.dumps(err_res) + "\n")
            sys.stdout.flush()

if __name__ == "__main__":
    main()
