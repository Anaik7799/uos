# Reference adapter: capture one frozen-reference trace.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# This file is not harness tooling. It is the thinnest possible driver for the
# *measured system*: the frozen Hermes reference is Python, its request shaping
# lives on a method that must be instantiated and called, and no amount of OCaml
# can execute it. It is committed rather than run ad hoc so that the capture is
# reviewable and reproducible, which is the whole point of pinning the traces.
#
# It is deliberately dumb. It makes no decisions, holds no expectations, and
# knows nothing about the OCaml candidate. It reads a scenario as JSON on stdin,
# calls the reference, and writes the result as JSON on stdout. Every judgement
# about what the result means -- normalization, comparison, digesting, storage --
# happens in OCaml, so this cannot quietly become the place where parity is
# decided.
#
# Invoked only by hermes_harness/reference_capture.ml, which supplies the
# interpreter, sets PYTHONPATH to the frozen snapshot, imposes a timeout, and
# validates everything that comes back.

import json
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

    try:
        transport = ChatCompletionsTransport()
        params = scenario.get("params", {})
        
        if "max_tokens" in params and "max_tokens_param_fn" not in params:
            try:
                from agent.auxiliary_client import auxiliary_max_tokens_param
                def _max_tokens_fn(val):
                    return auxiliary_max_tokens_param(val, model=scenario["model"])
                params["max_tokens_param_fn"] = _max_tokens_fn
            except ImportError:
                params["max_tokens_param_fn"] = lambda x: {"max_tokens": x}

        kwargs = transport.build_kwargs(
            model=scenario["model"],
            messages=scenario["messages"],
            tools=scenario.get("tools"),
            **params,
        )
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    # default=str keeps a non-serialisable value visible as text rather than
    # collapsing the whole capture; the OCaml side sees it and can reject.
    print(json.dumps({"trace": kwargs}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
