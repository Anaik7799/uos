# Reference adapter: record which frozen source files execute during request shaping.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# Like the other adapters, this is a dumb driver for the measured system, not
# harness logic. It runs the frozen reference's build_kwargs under sys.settrace
# (stdlib -- there is no coverage.py in the reference env) and emits the set of
# frozen-relative .py files that had a function called. Every judgement about what
# that means -- mapping executed files to capability anchors, reporting coverage --
# stays in OCaml (Runtime_coverage). Invoked only by reference_capture.ml.

import json
import os
import sys


def main() -> int:
    try:
        scenario = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as error:
        print(json.dumps({"error": f"unreadable scenario: {error}"}))
        return 2

    try:
        from agent.transports.chat_completions import ChatCompletionsTransport
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    # reference_capture sets PYTHONPATH to the frozen root (a single entry, with
    # inherited PYTHONPATH stripped). Python records absolute co_filenames for
    # imported modules, so we compare against the ABSOLUTE frozen root -- a
    # relative PYTHONPATH would never prefix-match and would silently drop
    # everything.
    raw_root = (os.environ.get("PYTHONPATH", "") or "").split(os.pathsep)[0]
    ref_root = os.path.abspath(raw_root).rstrip("/") if raw_root else ""
    executed: set[str] = set()

    def tracer(frame, event, _arg):
        # 'call' fires on every function entry; recording co_filename and
        # returning None captures every executed file without line-tracing.
        if event == "call":
            executed.add(frame.f_code.co_filename)
        return None

    try:
        transport = ChatCompletionsTransport()
        sys.settrace(tracer)
        try:
            transport.build_kwargs(
                model=scenario["model"],
                messages=scenario["messages"],
                tools=scenario.get("tools"),
                **scenario.get("params", {}),
            )
        finally:
            sys.settrace(None)
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        sys.settrace(None)
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    prefix = ref_root + "/" if ref_root else ""
    relative = []
    for path in executed:
        absolute = os.path.abspath(path)
        if prefix and absolute.startswith(prefix) and absolute.endswith(".py"):
            relative.append(absolute[len(prefix):])
    print(json.dumps({"trace": {"executed": sorted(set(relative))}}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
