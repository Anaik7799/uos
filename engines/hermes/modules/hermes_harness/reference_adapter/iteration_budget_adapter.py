# Reference adapter: replay an iteration-budget operation sequence.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# Like the other adapters, this is not harness tooling: it is the thinnest
# possible driver for the *measured system*. The frozen reference's iteration
# budget is a Python class (agent/iteration_budget.py) whose consume/refund
# behaviour can only be observed by running it. It makes no decisions, holds no
# expectations, and knows nothing about the OCaml candidate: it reads a scenario
# on stdin, drives IterationBudget, and writes the observed state on stdout.
# Normalization, comparison, digesting and storage all happen in OCaml.
#
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
        from agent.iteration_budget import IterationBudget
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    try:
        params = scenario.get("params", {})
        max_total = params["max_total"]
        operations = params.get("operations", [])
        budget = IterationBudget(max_total)
        consumes = []
        for op in operations:
            if op == "consume":
                consumes.append(budget.consume())
            elif op == "refund":
                budget.refund()
            else:
                print(json.dumps({"error": f"unknown operation: {op!r}"}))
                return 4
        trace = {
            "max_total": budget.max_total,
            "used": budget.used,
            "remaining": budget.remaining,
            "consumes": consumes,
        }
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    print(json.dumps({"trace": trace}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
