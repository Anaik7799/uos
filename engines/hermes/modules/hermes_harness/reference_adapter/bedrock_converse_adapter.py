# Reference adapter: shape OpenAI kwargs into a Bedrock Converse request.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# A dumb driver: reads a list of cases, runs the frozen
# agent.bedrock_adapter.build_converse_kwargs on each, serialises results
# positionally. NEUTRALIZATION: agent/bedrock_adapter.py runs
# tools.lazy_deps.ensure('provider.bedrock') at import, which could attempt a
# network install of boto3; HERMES_DISABLE_LAZY_INSTALLS=1 is set BEFORE the
# import (the whole ensure() is try/except-wrapped, and boto3 is genuinely absent,
# so import and all calls still succeed). Logging disabled (L-10). Makes no parity
# decision; comparison stays in OCaml. Invoked only by reference_capture.ml.

import json
import logging
import os
import sys

os.environ["HERMES_DISABLE_LAZY_INSTALLS"] = "1"
os.environ.pop("HERMES_LAZY_INSTALL_TARGET", None)
logging.disable(logging.CRITICAL)


def main() -> int:
    try:
        scenario = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as error:
        print(json.dumps({"error": f"unreadable scenario: {error}"}))
        return 2

    try:
        from agent.bedrock_adapter import build_converse_kwargs
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    try:
        params = scenario.get("params", {})
        results = []
        for case in params.get("cases", []):
            results.append(
                build_converse_kwargs(
                    case["model"],
                    case.get("messages", []),
                    tools=case.get("tools"),
                    max_tokens=case.get("max_tokens", 4096),
                    temperature=case.get("temperature"),
                    top_p=case.get("top_p"),
                    stop_sequences=case.get("stop_sequences"),
                    guardrail_config=case.get("guardrail_config"),
                )
            )
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    print(json.dumps({"trace": {"results": results}}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
