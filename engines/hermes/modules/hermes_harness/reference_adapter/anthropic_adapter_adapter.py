# Reference adapter: exercise the frozen Anthropic shaping functions.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# A dumb driver: it reads a list of calls, each naming one of three frozen pure
# functions and its argument, runs it, and serialises the results positionally.
# Makes no parity decision; comparison stays in OCaml. Invoked only by
# hermes_harness/reference_capture.ml.
#
# The frozen convert_tools_to_anthropic emits a logger.warning on a duplicate
# tool name; in this environment that handler writes to stdout and would corrupt
# the pure-JSON contract. Logging is DISABLED before the frozen import so the
# warning never emits -- a log side-effect is not part of the trace, and the
# return value (which still dedups) is unchanged.

import json
import logging
import sys

logging.disable(logging.CRITICAL)


def main() -> int:
    try:
        scenario = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as error:
        print(json.dumps({"error": f"unreadable scenario: {error}"}))
        return 2

    try:
        from agent.anthropic_adapter import (
            convert_tools_to_anthropic,
            normalize_model_name,
            _sanitize_tool_id,
        )
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    try:
        params = scenario.get("params", {})
        results = []
        for call in params.get("calls", []):
            fn = call.get("function")
            if fn == "convert_tools_to_anthropic":
                results.append(convert_tools_to_anthropic(call.get("tools")))
            elif fn == "normalize_model_name":
                results.append(normalize_model_name(call.get("model")))
            elif fn == "sanitize_tool_id":
                results.append(_sanitize_tool_id(call.get("tool_id")))
            else:
                results.append(None)
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    print(json.dumps({"trace": {"results": results}}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
