"""Bounded MAX graph inference, isolated behind the ecology OTP worker.

The request supplies its own linear model. No trained model or generative
intelligence is implied. JSON is framed with a four-byte big-endian length.
"""
import hashlib
import json
import math
import os
import struct
import sys
import time

MAX_FRAME = 65536
MAX_DIM = 128


class InvalidRequest(ValueError):
    """Caller-local refusal; it must not stop the shared MAX service."""


def infer(request):
    if not isinstance(request, dict) or request.get("operation") != "linear_softmax":
        raise InvalidRequest("operation must be linear_softmax")
    if set(request) != {"operation", "features", "weights", "bias"}:
        raise InvalidRequest("unexpected or missing request fields")
    features, weights, bias = request["features"], request["weights"], request["bias"]
    if not isinstance(features, list) or not 1 <= len(features) <= MAX_DIM:
        raise InvalidRequest("features must have 1..128 entries")
    if not isinstance(bias, list) or not 2 <= len(bias) <= MAX_DIM:
        raise InvalidRequest("bias must have 2..128 entries")
    if not isinstance(weights, list) or len(weights) != len(features):
        raise InvalidRequest("weights must have one row per feature")
    if any(not isinstance(row, list) or len(row) != len(bias) for row in weights):
        raise InvalidRequest("weights must have one column per class")
    values = features + bias + [v for row in weights for v in row]
    if any(isinstance(v, bool) or not isinstance(v, (int, float))
           or not math.isfinite(v) or abs(v) > 1e6 for v in values):
        raise InvalidRequest("values must be finite numbers of magnitude <= 1000000")

    # Import and execute the real installed MAX engine; never use a Python
    # arithmetic fallback when the engine/compiler is unavailable.
    # Bound this isolated process before MAX creates its CPU device. The pinned
    # runtime initializes CPU() before InferenceSession and rejects overriding
    # its thread options later, so constrain CPU affinity at the OS boundary.
    cpus = sorted(os.sched_getaffinity(0))
    os.sched_setaffinity(0, set(cpus[:2]))
    import numpy as np
    from max.driver import CPU, Buffer, __version__
    from max.dtype import DType
    from max.engine import InferenceSession
    from max.graph import DeviceRef, Graph, TensorType, ops

    session = InferenceSession(devices=[CPU()])
    device = DeviceRef.CPU()
    types = [TensorType(DType.float32, (1, len(features)), device=device),
             TensorType(DType.float32, (len(features), len(bias)), device=device),
             TensorType(DType.float32, (len(bias),), device=device)]
    started = time.monotonic_ns()
    with Graph("uos_ecology_linear_softmax", input_types=types) as graph:
        x, w, b = (v.tensor for v in graph.inputs)
        graph.output(ops.softmax(ops.matmul(x, w) + b))
    model = session.load(graph)
    inputs = [np.asarray([features], dtype=np.float32),
              np.asarray(weights, dtype=np.float32), np.asarray(bias, dtype=np.float32)]
    result = model.execute(*(Buffer.from_numpy(v) for v in inputs))[0]
    probabilities = result.to_numpy()[0].tolist()
    if not all(math.isfinite(v) for v in probabilities) or abs(sum(probabilities) - 1.0) > 1e-5:
        raise ValueError("MAX returned invalid probabilities")
    identity = json.dumps({"weights": weights, "bias": bias}, sort_keys=True,
                          separators=(",", ":"), allow_nan=False).encode()
    return {"backend": "modular_max_graph", "operation": "linear_softmax",
            "device": "CPU", "engine_version": __version__, "model_source": "request_supplied",
            "model_sha256": hashlib.sha256(identity).hexdigest(),
            "probabilities": probabilities,
            "class_index": max(range(len(probabilities)), key=probabilities.__getitem__),
            "elapsed_us": (time.monotonic_ns() - started) // 1000,
            "application_admitted": False}


def read_exact(length):
    data = bytearray()
    while len(data) < length:
        chunk = sys.stdin.buffer.read(length - len(data))
        if not chunk:
            raise InvalidRequest("truncated frame")
        data.extend(chunk)
    return bytes(data)


def main():
    # Exactly one request per supervised process bounds model compilation/cache
    # residency. OTP owns deadlines and process-group cleanup.
    try:
        size = struct.unpack(">I", read_exact(4))[0]
        if not 1 <= size <= MAX_FRAME:
            raise InvalidRequest("frame bound exceeded")
        request = json.loads(read_exact(size), parse_constant=lambda _: (_ for _ in ()).throw(InvalidRequest("nonfinite JSON")))
        response = {"ok": True, "result": infer(request)}
    except (InvalidRequest, json.JSONDecodeError, UnicodeDecodeError) as exc:
        response = {"ok": False, "error": "invalid_request: " + str(exc)[:300]}
    except Exception as exc:
        response = {"ok": False, "error": "backend_failure: " + type(exc).__name__ + ": " + str(exc)[:300]}
    body = json.dumps(response, separators=(",", ":"), allow_nan=False).encode()
    sys.stdout.buffer.write(struct.pack(">I", len(body)) + body)
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    main()
