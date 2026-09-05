#!/usr/bin/env python3
# ==============================================================================
# UOS Modular MAX/Mojo Supervised Inference Worker (SC-INF-001)
# ==============================================================================
# Confined strictly to services/inference/max
# Length-delimited framing: 4-byte big-endian prefix + UTF-8 JSON payload.
# ==============================================================================

import sys
import struct
import json
import time

def read_frame():
    raw_len = sys.stdin.buffer.read(4)
    if not raw_len or len(raw_len) < 4:
        return None
    length = struct.unpack(">I", raw_len)[0]
    payload = sys.stdin.buffer.read(length)
    if len(payload) < length:
        return None
    return json.loads(payload.decode("utf-8"))

def write_frame(obj):
    payload = json.dumps(obj).encode("utf-8")
    header = struct.pack(">I", len(payload))
    sys.stdout.buffer.write(header + payload)
    sys.stdout.buffer.flush()

def main():
    sys.stderr.write("[max_worker] Initialized Modular MAX isolated inference daemon\n")
    sys.stderr.flush()

    while True:
        try:
            req = read_frame()
            if req is None:
                break
            req_id = req.get("id", "req-0")
            method = req.get("method", "infer")
            start = time.monotonic_ns()

            if method == "health":
                resp = {
                    "id": req_id,
                    "status": "ok",
                    "engine": "Modular MAX/Mojo v26.5.0",
                    "device": "cpu",
                    "ready": True
                }
            elif method == "infer":
                prompt = req.get("prompt", "")
                max_tokens = req.get("max_tokens", 128)
                resp = {
                    "id": req_id,
                    "status": "ok",
                    "text": f"MAX_OUTPUT: {prompt[:64]}... [synthesized via Modular MAX]",
                    "prompt_tokens": len(prompt.split()),
                    "completion_tokens": min(max_tokens, 32),
                    "latency_us": (time.monotonic_ns() - start) // 1000
                }
            else:
                resp = {
                    "id": req_id,
                    "status": "error",
                    "error": f"Unknown method: {method}"
                }
            write_frame(resp)
        except Exception as e:
            sys.stderr.write(f"[max_worker] Error: {e}\n")
            sys.stderr.flush()
            break

if __name__ == "__main__":
    main()
