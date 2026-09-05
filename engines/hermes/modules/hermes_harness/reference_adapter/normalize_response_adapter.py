# Reference adapter: capture one frozen-reference RESPONSE-DECODING trace.
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml),
# on the same terms as build_kwargs_adapter.py: the thinnest possible driver for
# the measured system, making no decisions and knowing nothing about the OCaml
# candidate. It reads a scenario on stdin, calls the reference decoder, and
# writes the result on stdout. The OCaml harness normalizes, compares, digests
# and stores; nothing here decides parity.
#
# The reference normalize_response uses attribute access (response.choices[0].
# message.tool_calls[i].function.name, getattr for optional fields), so a
# provider response is presented to it as a recursive attribute view over the
# input JSON. This is a mechanical transform, not interpretation: no field is
# defaulted, renamed or invented. It faithfully covers responses whose fields
# are plain JSON; it does NOT reproduce pydantic model_extra / model_dump, so a
# response that relies on those is out of scope for this adapter (and would need
# the real SDK). That boundary is stated so it cannot be mistaken for coverage.

import json
import sys


class Obj:
    """Present a JSON object as attribute access, faithful to the SDK contract.

    The reference reads optional fields (msg.tool_calls, msg.reasoning, ...) that
    the openai SDK model always exposes as None when absent. A missing field is
    therefore None here too. The one exception is pydantic internals
    (model_extra, model_dump): the reference probes them with hasattr, and this
    is not a pydantic object, so they must be genuinely absent -- returning None
    for them would change which branch the reference takes.
    """

    def __init__(self, mapping):
        for key, value in mapping.items():
            setattr(self, key, as_attr(value))

    def __getattr__(self, name):  # only called when the attribute is missing
        if name.startswith("model_") or name.startswith("__"):
            raise AttributeError(name)
        return None


def as_attr(value):
    if isinstance(value, dict):
        return Obj(value)
    if isinstance(value, list):
        return [as_attr(item) for item in value]
    return value


def serialize_tool_call(tc):
    out = {"id": tc.id, "name": tc.name, "arguments": tc.arguments}
    if tc.provider_data is not None:
        out["provider_data"] = tc.provider_data
    return out


def main() -> int:
    try:
        scenario = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as error:
        print(json.dumps({"error": f"unreadable scenario: {error}"}))
        return 2

    # The provider response is carried in params.response.
    response_json = (scenario.get("params") or {}).get("response")
    if response_json is None:
        print(json.dumps({"error": "scenario has no params.response"}))
        return 2

    try:
        from agent.transports.chat_completions import ChatCompletionsTransport
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"error": f"reference import failed: {error!r}"}))
        return 3

    try:
        transport = ChatCompletionsTransport()
        normalized = transport.normalize_response(as_attr(response_json))
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"error": f"reference raised: {error!r}"}))
        return 4

    # Serialize the NormalizedResponse to the canonical contract schema. This is
    # the reference contract: content, finish_reason, tool_calls, usage,
    # reasoning. Fields the reference leaves None are omitted so the candidate is
    # compared against what the reference actually produced.
    trace = {
        "content": normalized.content,
        "finish_reason": normalized.finish_reason,
    }
    if normalized.tool_calls is not None:
        trace["tool_calls"] = [serialize_tool_call(tc) for tc in normalized.tool_calls]
    if normalized.usage is not None:
        trace["usage"] = {
            "prompt_tokens": normalized.usage.prompt_tokens,
            "completion_tokens": normalized.usage.completion_tokens,
            "total_tokens": normalized.usage.total_tokens,
        }
    if normalized.reasoning is not None:
        trace["reasoning"] = normalized.reasoning

    print(json.dumps({"trace": trace}, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
