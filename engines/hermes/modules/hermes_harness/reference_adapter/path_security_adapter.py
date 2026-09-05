# Reference adapter: evaluate the frozen path-safety predicate over a list of paths.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# A dumb driver for the measured system: it reads a list of path strings, runs the
# frozen tools/path_security.has_traversal_component on each, and serialises the
# path -> bool map. Makes no parity decision; comparison and storage stay in OCaml.
# Invoked only by hermes_harness/reference_capture.ml.

import json
import sys


def main() -> int:
    try:
        scenario = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as error:
        print(json.dumps({"error": f"unreadable scenario: {error}"}))
        return 2

    try:
        from tools.path_security import has_traversal_component
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    try:
        params = scenario.get("params", {})
        paths = params.get("paths", [])
        results = {path: has_traversal_component(path) for path in paths}
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    print(json.dumps({"trace": {"results": results}}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
