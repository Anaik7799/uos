# Reference adapter: evaluate the frozen Retry-After parser over a value list.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# A dumb driver for the measured system: it reads a list of JSON values, runs the
# frozen agent.retry_utils.parse_retry_after_seconds on each, and serialises the
# results positionally (JSON object keys must be strings, and distinct values like
# 5 and "5" would collide as keys -- positional pairing keeps them distinct).
# Makes no parity decision; comparison and storage stay in OCaml. Invoked only by
# hermes_harness/reference_capture.ml.

import json
import sys


def main() -> int:
    try:
        scenario = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as error:
        print(json.dumps({"error": f"unreadable scenario: {error}"}))
        return 2

    try:
        from agent.retry_utils import parse_retry_after_seconds
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    try:
        params = scenario.get("params", {})
        values = params.get("values", [])
        results = [parse_retry_after_seconds(value) for value in values]
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    print(json.dumps({"trace": {"results": results}}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
