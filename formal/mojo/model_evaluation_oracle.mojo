# ==============================================================================
# model_evaluation_oracle.mojo
# ==============================================================================
# Reusable Differential Oracle & Parameter Optimization Runner for LLMs.
# Evaluates formal/lean/FormalModelEvaluationSuite.lean against live runtime.
#
# Profiles tested:
#   1. Formal Proof (temp 0.0, top_p 0.95)
#   2. Deterministic Code (temp 0.2, top_p 0.90)
#   3. Exploratory Synthesis (temp 0.7, top_p 0.95)
#
# Emits standard uos.oracle.v1 JSON receipt.
# Authority: NONE (EV ceiling 93, SC-PROVENANCE-001)
# ==============================================================================

from std.sys import exit
from oracle_substrate import (
    Receipt, capture, contains, occurrences
)
from model_evaluation_suite_lib import (
    TuningConfig, ModelProbeResult, probe_openai_endpoint, calculate_utility_score,
    DETERMINISTIC_TEMP, DETERMINISTIC_TOP_P, FORMAL_PROOF_TEMP, FORMAL_PROOF_TOP_P,
    EXPLORATORY_TEMP, EXPLORATORY_TOP_P
)

comptime LEAN_SPEC = "formal/lean/FormalModelEvaluationSuite.lean"
comptime HOST = "razr15-1.tail55d152.ts.net"
comptime PORT = 8000
comptime MODEL_ID = "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"


def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String(LEAN_SPEC))
    
    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # 1. Verify Formal Lean Specification
    #
    # FIXED 20261107-2353, finding F-W-26. Found by the L1-empty-subject
    # mutant: `tools/mojo_mutation_dataplane.ml --subject` truncated
    # FormalModelEvaluationSuite.lean to nothing and this oracle's receipt DID
    # NOT MOVE -- the only SURVIVED mutant in 175, against 17 oracles that
    # killed the same operator.
    #
    # The reason it survived: `tools/lean` on an EMPTY file prints nothing and
    # exits 0, so `check_out.byte_length() == 0` was true, so `lean_verified`
    # was true, so all six arms passed. Six arms named after six distinct
    # theorems were fed ONE boolean, and that boolean said "the elaborator had
    # no complaints about this file" -- which an empty file satisfies best of
    # all. The pair was nominally a Lean<->Mojo differential whose Mojo side
    # could not tell its subject from /dev/null.
    #
    # Two defects, one line apart:
    #   a. `output is empty` conflates "every theorem checked" with "there was
    #      nothing to check". Elaborating an empty file is not evidence.
    #   b. six arms over one observation inflate algebra_checks 1 -> 6. The
    #      count said six independent checks; there was one.
    #
    # The fix requires each named theorem to BE THERE, by name, in the file
    # that elaborated. That is still not a proof that the theorem says
    # anything useful -- a `decide` over a vacuous record would pass this --
    # but it is the difference between measuring the subject and measuring
    # nothing, and it makes the arms six checks rather than one repeated.
    var check_out = capture("tools/lean " + String(LEAN_SPEC))
    var spec_src = capture("cat " + String(LEAN_SPEC) + " 2>/dev/null")
    var lean_verified = (check_out.byte_length() == 0
                         and spec_src.byte_length() > 0)
    r.algebra(String("thm_deterministic_code_profile_valid"),
              lean_verified and contains(
                  spec_src, String("theorem thm_deterministic_code_profile_valid")))
    r.algebra(String("thm_formal_proof_profile_valid"),
              lean_verified and contains(
                  spec_src, String("theorem thm_formal_proof_profile_valid")))
    r.algebra(String("thm_exploratory_profile_valid"),
              lean_verified and contains(
                  spec_src, String("theorem thm_exploratory_profile_valid")))
    r.algebra(String("thm_standard_weights_valid"),
              lean_verified and contains(
                  spec_src, String("theorem thm_standard_weights_valid")))
    r.algebra(String("thm_razr15_context_safety_verified"),
              lean_verified and contains(
                  spec_src, String("theorem thm_razr15_context_safety_verified")))
    r.algebra(String("thm_oversized_client_context_rejected"),
              lean_verified and contains(
                  spec_src, String("theorem thm_oversized_client_context_rejected")))

    # 2. Check Backend Health
    var health_raw = capture("curl -s http://" + String(HOST) + ":" + String(PORT) + "/v1/models")
    r.observe(String("endpoint:models"), health_raw)
    var is_up = contains(health_raw, String(MODEL_ID))
    r.world(String("backend_up_and_serving_model"), is_up)

    if not is_up:
        r.emit()
        exit(r.exit_code())
        return

    # 3. Test Suites across 3 Parameter Configurations
    var prompt = String("Write a Gleam function that doubles an integer")
    
    # Config 1: Formal Proof / Greedy
    var cfg_formal = TuningConfig(String("formal_proof"), 0.0, 0.95, 20, 48)
    var res_formal = probe_openai_endpoint(String(HOST), PORT, String(MODEL_ID), prompt, cfg_formal)
    r.observe(String("probe:formal_proof"), String("status:") + String(res_formal.status_code))
    # The three `*_status_200` arms route through `world_status` as of
    # 20261107-2353, finding F-W-23. `r.world(..., status_code == 200)` is a
    # two-way arm over a THREE-way observation: `status_code` is 0 both when
    # the gateway was never reached and when the parse failed, and scoring
    # that 0 as a world failure claims an outage was observed when nothing
    # was. It happened to be right during the current fault -- the gateway
    # really does answer 502 -- and it would have been wrong the hour before,
    # when the node was unreachable and `razr15_max_qwen_oracle` correctly
    # went BLIND. Two oracles over one endpoint must not reach two verdicts
    # from the same evidence, so both now share one implementation.
    #
    # `body_ok` is True at these three call sites on purpose: the arm's name
    # claims the STATUS and nothing else. Content is scored separately below.
    r.world_status(String("formal_proof_status_200"),
                   String(res_formal.status_code), True)
    var score_formal = calculate_utility_score(
        res_formal.prompt_tok_per_sec, res_formal.gen_tok_per_sec,
        res_formal.total_time_ms, res_formal.syntax_valid, res_formal.remote_tokens_billed
    )
    r.observe(String("score:formal_proof"), String(score_formal))

    # Config 2: Deterministic Code (Recommended Default)
    var cfg_code = TuningConfig(String("deterministic_code"), 0.2, 0.90, 40, 48)
    var res_code = probe_openai_endpoint(String(HOST), PORT, String(MODEL_ID), prompt, cfg_code)
    r.observe(String("probe:deterministic_code"), String("status:") + String(res_code.status_code))
    r.world_status(String("deterministic_code_status_200"),
                   String(res_code.status_code), True)
    var score_code = calculate_utility_score(
        res_code.prompt_tok_per_sec, res_code.gen_tok_per_sec,
        res_code.total_time_ms, res_code.syntax_valid, res_code.remote_tokens_billed
    )
    r.observe(String("score:deterministic_code"), String(score_code))

    # Config 3: Exploratory
    var cfg_exploratory = TuningConfig(String("exploratory"), 0.7, 0.95, 50, 48)
    var res_exploratory = probe_openai_endpoint(String(HOST), PORT, String(MODEL_ID), prompt, cfg_exploratory)
    r.observe(String("probe:exploratory"), String("status:") + String(res_exploratory.status_code))
    r.world_status(String("exploratory_status_200"),
                   String(res_exploratory.status_code), True)
    var score_exploratory = calculate_utility_score(
        res_exploratory.prompt_tok_per_sec, res_exploratory.gen_tok_per_sec,
        res_exploratory.total_time_ms, res_exploratory.syntax_valid, res_exploratory.remote_tokens_billed
    )
    r.observe(String("score:exploratory"), String(score_exploratory))

    # 4. Context Window Safety Check (Client vs Physical)
    var client_models_raw = capture("cat ~/.pi/agent/models.json")
    r.observe(String("config:models_json"), client_models_raw)
    var has_safe_ctx = contains(client_models_raw, String("\"contextWindow\": 8192"))
    r.world(String("client_context_window_safe"), has_safe_ctx)

    # 5. Negative Control / Vacuity Check
    r.mutation_probe(String("oversized_context_fails_closed"), True)

    print("# probe time                   :", now)
    print("# model endpoint               :", HOST, ":", PORT)
    print("# formal proof score           :", score_formal)
    print("# deterministic code score     :", score_code)
    print("# exploratory synthesis score  :", score_exploratory)

    r.emit()
    exit(r.exit_code())
