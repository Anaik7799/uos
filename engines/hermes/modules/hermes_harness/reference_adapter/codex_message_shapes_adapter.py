# Reference adapter: exercise the frozen Codex Responses message-shaping trio.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# A dumb driver: reads a list of ops, each naming one of three frozen pure
# functions and its arguments, runs it, serialises the results positionally.
# Logging is disabled before the frozen import (L-10: a log side-effect on stdout
# would corrupt the pure-JSON contract; it is not part of the trace). Makes no
# parity decision; comparison stays in OCaml. Invoked only by reference_capture.ml.

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
        from agent.codex_responses_adapter import (
            _chat_content_to_responses_parts,
            _normalize_responses_message_status,
            _summarize_user_message_for_log,
        )
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    try:
        params = scenario.get("params", {})
        results = []
        for op in params.get("ops", []):
            kind = op.get("op")
            # role/sep/default are KEYWORD-ONLY in the frozen signatures (verified
            # against the source: def f(content, *, role="user")).
            if kind == "content_parts":
                results.append(
                    _chat_content_to_responses_parts(op.get("content"), role=op.get("role", "user"))
                )
            elif kind == "message_status":
                results.append(_normalize_responses_message_status(op.get("value")))
            elif kind == "summarize":
                results.append(
                    _summarize_user_message_for_log(op.get("content"), sep=op.get("sep", " "))
                )
            else:
                results.append(None)
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    print(json.dumps({"trace": {"results": results}}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
