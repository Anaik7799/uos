# Reference adapter: sanitize Gemini tool parameters over a list of schemas.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# A dumb driver: reads a list of parameter schemas, runs the frozen
# agent.gemini_schema.sanitize_gemini_tool_parameters on each, serialises results
# positionally. Logging disabled before the frozen import (L-10). This is the
# self-contained pure core of the gemini adapter (imports only math, no httpx).
# Makes no parity decision; comparison stays in OCaml. Invoked only by
# reference_capture.ml.

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
        from agent.gemini_schema import sanitize_gemini_tool_parameters
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    try:
        params = scenario.get("params", {})
        results = [sanitize_gemini_tool_parameters(schema) for schema in params.get("schemas", [])]
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    print(json.dumps({"trace": {"results": results}}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
