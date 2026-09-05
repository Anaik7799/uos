# Reference adapter: replay the frozen strict-API tool_call sanitizer.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# The thinnest possible driver for the measured system: the frozen
# AIAgent._sanitize_tool_calls_for_strict_api (run_agent.py:7249) is a static
# method whose strip set is model-gated; its behaviour can only be observed by
# running it. It reads labeled cases on stdin, applies the frozen method to
# each message, and writes the observed messages on stdout. It makes no parity
# decision and knows nothing about the OCaml candidate; normalization,
# comparison, digesting and storage all happen in OCaml.
#
# Output discipline: importing run_agent executes module-level code that
# prints diagnostics (state-db linkage lines), and the harness merges the
# child's stderr into the same capture file as stdout. The trace channel must
# carry exactly one JSON object, so BOTH file descriptors are pointed at
# /dev/null at the fd level for the whole run (a sys.stdout swap cannot cover
# fd-level or stderr writes) and the trace is written to a saved duplicate of
# the original stdout at the end. Diverting I/O alters nothing the method
# computes.
#
# Invoked only by hermes_harness/reference_capture.ml.

import copy
import json
import os
import sys


def main() -> int:
    real_stdout = os.fdopen(os.dup(1), "w")
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
    os.close(devnull)

    def emit(payload: dict) -> None:
        print(json.dumps(payload, sort_keys=True, default=str), file=real_stdout)
        real_stdout.flush()

    try:
        scenario = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as error:
        emit({"error": f"unreadable scenario: {error}"})
        return 2

    params = scenario.get("params", {})
    unit = params.get("unit", "strict_strip")

    try:
        if unit == "list_repairs":
            from agent.agent_runtime_helpers import sanitize_api_messages as frozen_unit
        elif unit == "surrogates":
            from agent.message_sanitization import _sanitize_surrogates as frozen_unit
        else:
            from run_agent import AIAgent

            def frozen_unit(messages, model=None):
                return [
                    AIAgent._sanitize_tool_calls_for_strict_api(msg, model=model)
                    for msg in messages
                ]
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        emit({"error": f"reference import failed: {error!r}"})
        return 3

    try:
        cases = params.get("cases", [])
        results = {}
        for case in cases:
            label = case["label"]
            if unit == "surrogates":
                # A lone surrogate cannot arrive as JSON bytes (that is the
                # unit's whole reason to exist), so the case declares parts:
                # literal runs and code points, materialized here via chr().
                text = "".join(
                    part["lit"] if "lit" in part else chr(part["cp"])
                    for part in case.get("parts", [])
                )
                results[label] = frozen_unit(text)
                continue
            # The frozen strict-strip method mutates api_msg in place and the
            # list unit rebuilds structurally; deep-copy so each case observes
            # a fresh input, exactly as the request loop hands per-call copies.
            messages = copy.deepcopy(case.get("messages", []))
            if unit == "list_repairs":
                results[label] = frozen_unit(messages)
            else:
                results[label] = frozen_unit(messages, model=case.get("model"))
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        emit({"error": f"reference raised: {error!r}"})
        return 4

    emit({"trace": {"results": results}})
    return 0


if __name__ == "__main__":
    sys.exit(main())
