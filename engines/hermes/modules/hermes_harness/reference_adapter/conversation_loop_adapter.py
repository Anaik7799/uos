# Reference adapter: replay conversation-loop send-path units.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# The thinnest possible driver for the measured system: the frozen
# _canonicalize_api_tool_calls and _get_continuation_prompt in
# agent/conversation_loop.py can only be observed by running them. It reads
# labeled cases on stdin, applies the frozen unit, and writes the observed
# output on stdout. It makes no parity decision and knows nothing about the
# OCaml candidate; normalization, comparison, digesting and storage all
# happen in OCaml.
#
# Output discipline is fd-level for the same reason as the hygiene adapter:
# module import prints diagnostics and the harness merges child stderr into
# the trace channel.
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
    unit = params.get("unit", "")

    try:
        if unit == "canonical_args":
            from agent.conversation_loop import _canonicalize_api_tool_calls as frozen_unit
        elif unit == "continuation_prompt":
            from agent.conversation_loop import _get_continuation_prompt as frozen_unit
        else:
            emit({"error": f"unknown unit: {unit!r}"})
            return 2
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        emit({"error": f"reference import failed: {error!r}"})
        return 3

    try:
        cases = params.get("cases", [])
        results = {}
        for case in cases:
            label = case["label"]
            if unit == "canonical_args":
                # The frozen pass mutates the list in place; deep-copy so each
                # case observes a fresh input, as the send path hands it the
                # per-call clone.
                messages = copy.deepcopy(case.get("messages", []))
                frozen_unit(messages)
                results[label] = messages
            else:
                results[label] = frozen_unit(
                    case.get("is_partial_stub", False),
                    case.get("dropped_tools") or None,
                )
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        emit({"error": f"reference raised: {error!r}"})
        return 4

    emit({"trace": {"results": results}})
    return 0


if __name__ == "__main__":
    sys.exit(main())
