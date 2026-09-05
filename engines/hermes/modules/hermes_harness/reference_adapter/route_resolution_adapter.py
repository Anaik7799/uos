# Reference adapter: resolve the fallback route chain for a list of configs.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# A dumb driver for the measured system: it reads a list of config mappings, runs
# the frozen hermes_cli.fallback_config.get_fallback_chain on each, and serialises
# the resolved chains positionally. Makes no parity decision; comparison and
# storage stay in OCaml. Invoked only by hermes_harness/reference_capture.ml.

import json
import sys


def main() -> int:
    try:
        scenario = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as error:
        print(json.dumps({"error": f"unreadable scenario: {error}"}))
        return 2

    try:
        from hermes_cli.fallback_config import get_fallback_chain
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    try:
        params = scenario.get("params", {})
        configs = params.get("configs", [])
        results = [get_fallback_chain(config) for config in configs]
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    print(json.dumps({"trace": {"results": results}}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
