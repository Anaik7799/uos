# ==============================================================================
# model_evaluation_suite_lib.mojo
# ==============================================================================
# Reusable Mojo 1.0 Library for Model Evaluation, Hyperparameter Calibration,
# Live Empirical Probing, and Dual-Plane Benchmark Verification.
#
# Mirrors formal/lean/FormalModelEvaluationSuite.lean:
#   - Lean owns the symbolic algebra, bounds, and decidable proofs.
#   - Mojo owns the empirical execution, HTTP probing, and multi-criteria utility.
#
# Authority: NONE (EV ceiling 93, EV-94..109 NOT_ADMITTED, SC-PROVENANCE-001)
# Zero Python rule enforced: pure Mojo standard library + system tools.
# ==============================================================================

from std.sys import exit
from oracle_substrate import (
    Receipt, capture, contains, json_has, json_int, occurrences, shell_quote
)

# UNMEASURED sentinel for `ModelProbeResult.remote_tokens_billed`, added
# 20261108-0702 with finding F-W-25. 0 CANNOT serve as the default for this
# field: 0 is also the one value the zero-burn invariant of
# SC-MODEL-ROLE-TWIN-001 §1.4 wants to confirm, so a field that defaults to 0
# and is never written reports a PASS on an invariant nobody measured. -1 is
# outside the domain of a token count, so it cannot be mistaken for evidence,
# and the companion `remote_billed_measured` flag means no reader has to
# recognise the sentinel to stay correct.
comptime REMOTE_BILLED_UNMEASURED = -1

# Standard Profile Constants (scaled x100 to match Lean representation)
comptime DETERMINISTIC_TEMP = 20   # 0.20
comptime DETERMINISTIC_TOP_P = 90  # 0.90
comptime FORMAL_PROOF_TEMP = 0     # 0.00
comptime FORMAL_PROOF_TOP_P = 95   # 0.95
comptime EXPLORATORY_TEMP = 70     # 0.70
comptime EXPLORATORY_TOP_P = 95    # 0.95


struct TuningConfig:
    var name: String
    var temp: Float64
    var top_p: Float64
    var top_k: Int
    var max_tokens: Int

    def __init__(out self, name: String, temp: Float64, top_p: Float64, top_k: Int, max_tokens: Int):
        self.name = name
        self.temp = temp
        self.top_p = top_p
        self.top_k = top_k
        self.max_tokens = max_tokens


struct ModelProbeResult:
    var status_code: Int
    var prompt_tok_per_sec: Float64
    var gen_tok_per_sec: Float64
    var total_time_ms: Int
    var syntax_valid: Bool
    var response_text: String
    var remote_tokens_billed: Int
    var remote_billed_measured: Bool

    def __init__(out self):
        self.status_code = 0
        self.prompt_tok_per_sec = 0.0
        self.gen_tok_per_sec = 0.0
        self.total_time_ms = 0
        self.syntax_valid = False
        self.response_text = ""
        self.remote_tokens_billed = REMOTE_BILLED_UNMEASURED
        self.remote_billed_measured = False


def calculate_utility_score(
    prompt_tps: Float64,
    gen_tps: Float64,
    latency_ms: Int,
    syntax_valid: Bool,
    remote_billed: Int,
    remote_billed_measured: Bool
) -> Int:
    """Computes integer utility score [0..1000] aligned with Lean computeUtilityScore.

    `remote_billed_measured` added 20261108-0702, finding F-W-25.
    `ModelProbeResult.remote_tokens_billed` was declared, initialised to 0,
    read here three times, and NEVER ASSIGNED anywhere in the tree. So
    `c_score = 100 if remote_billed == 0` was `c_score = 100`, unconditionally,
    on every probe that has ever run -- including probes that never reached a
    server. That arm nominally scores the zero-burn invariant of
    SC-MODEL-ROLE-TWIN-001 §1.4 (`remote_tokens_billed = 0`), and it scored it
    with a constant: an assertion that cannot fail is not evidence
    (INV-FALSIFY).

    The honest reading needs three states, not two -- billed-zero,
    billed-nonzero, and never-measured -- so the flag is a separate parameter
    rather than a magic value, and the credit is awarded only on the first.
    An unmeasured cost is NOT a zero cost, exactly as an unmeasured latency is
    not an instantaneous one (F-W-22, same file, same week).

    Proved as THM_COST_01..04 in formal/lean/FormalModelEvaluationSuite.lean,
    with THM_COST_03 as the control that matters: a MEASURED zero still earns
    full credit, so this change cannot be mistaken for a blanket penalty.
    """
    var t_score = Int((prompt_tps + gen_tps * 2.0) * 35.0 / 10.0)
    var l_score = 0
    if latency_ms < 2000 and latency_ms > 0:
        l_score = Int(Float64(2000 - latency_ms) * 25.0 / 20.0)
    var s_score = 300 if syntax_valid else 0
    var c_score = 100 if (remote_billed_measured and remote_billed == 0) else 0
    return t_score + l_score + s_score + c_score


def probe_openai_endpoint(
    fqdn: String,
    port: Int,
    model_id: String,
    prompt: String,
    cfg: TuningConfig
) -> ModelProbeResult:
    """Executes a live empirical probe against an OpenAI-compatible endpoint."""
    var res = ModelProbeResult()
    var url = "http://" + fqdn + ":" + String(port) + "/v1/chat/completions"
    
    var q = "\""
    var payload = "{" + q + "model" + q + ":" + q + model_id + q + "," + q + "messages" + q + ":[{" + q + "role" + q + ":" + q + "user" + q + "," + q + "content" + q + ":" + q + prompt + q + "}]," + q + "temperature" + q + ":" + String(cfg.temp) + "," + q + "top_p" + q + ":" + String(cfg.top_p) + "," + q + "max_tokens" + q + ":" + String(cfg.max_tokens) + "}"
    
    # `--max-time 150` and the matching 150 s capture bound, 20261107-2353,
    # finding F-W-23. This probe carried no curl deadline and inherited the
    # 20 s default, so against razr15-1:8000 -- which answers a definite 502
    # after 120.1 s -- it read empty and parsed status 0 on every single run.
    # The three `*_status_200` arms then scored that 0 as a world failure,
    # i.e. claimed to have observed an outage they had not waited to see,
    # while `razr15_max_qwen_oracle` called the same endpoint BLIND. Both
    # numbers must exceed the gateway's own 120 s backend timeout or the
    # answer is unreachable regardless of how the verdict is computed.
    # `%{time_total}` added 20261108-0702 alongside finding F-W-25. The
    # latency term had the SAME defect as the cost term and it survived the
    # F-W-22 fix, which only aligned the two sides' arithmetic at
    # latency_ms = 0 and never asked why 0 was arriving. `total_time_ms` is
    # parsed below from a key named `"total_time_ms"`, and NO endpoint in this
    # system emits that key: razr15-1:8000 reports its round-trip as
    # `uos_max_meta.latency_ms` and the llama.cpp backend reports component
    # times under `timings`. Observed 20261108-0702Z, a 5323-byte healthy
    # gateway response containing `"latency_ms": 299.95` and no
    # `total_time_ms` anywhere. So `l_score` was 0 on every probe, healthy or
    # not -- a quarter of the nominal weight permanently dark.
    #
    # curl's own `%{time_total}` is used rather than the server's self-report
    # because it is the client-observed round-trip, it exists for every
    # response including error responses, and it cannot be omitted by a
    # gateway that forgets to enrich. The server's figure is still read below
    # when present, and the two disagreeing is itself informative.
    var cmd = "curl -s --max-time 150 -w '\n%{time_total}\n%{http_code}' -X POST " + url + " -H 'Content-Type: application/json' -d " + shell_quote(payload)
    var raw = capture(cmd, 150)

    if raw.byte_length() == 0:
        return res^

    var lines = String(raw).split("\n")
    # `>= 2`, NOT `>= 3`. `capture()` strips the captured output, so a
    # response with an EMPTY body arrives as "<time>\n<code>" -- two lines,
    # not three, because the leading blank line is stripped away. A `>= 3`
    # guard would skip parsing for exactly that case and leave status_code at
    # 0, which `world_status` reads as "no status obtained" and scores BLIND.
    # That would silently recreate the F-W-23 defect from the other side: a
    # definite `200 with an empty body` reported as unobservability. Two
    # trailing `-w` fields are always present whenever curl answered at all,
    # so two lines is the real floor, and `range(len(lines) - 2)` below
    # correctly yields an empty body for that case.
    if len(lines) >= 2:
        try:
            res.status_code = Int(String(String(lines[len(lines)-1]).strip()))
        except:
            res.status_code = 0
        try:
            # Seconds as a decimal; scaled to whole ms to match the Lean
            # model, which is Nat-typed and carries no fractional latency.
            res.total_time_ms = Int(
                Float64(String(String(lines[len(lines)-2]).strip())) * 1000.0)
        except:
            res.total_time_ms = 0

    # The two trailing `-w` fields are dropped, and the remainder is rejoined
    # with newlines rather than concatenated bare: a multi-line body
    # concatenated without separators merges the last token of one line into
    # the first of the next, which a key lookup then cannot find.
    var body = ""
    for i in range(len(lines) - 2):
        if i > 0:
            body += "\n"
        body += String(lines[i])

    res.response_text = body

    # The real zero-burn measurement, finding F-W-25. razr15-1:8000 reports
    # this field in `uos_max_meta` (and again in `holonic_8pillar`), so the
    # value the invariant needs was being served all along and discarded.
    # Presence is asked separately from value because `json_int` reserves -1
    # for absence and a cost of 0 is the very case under test, so value alone
    # cannot distinguish "measured zero" from "no such field".
    if json_has(body, String("remote_tokens_billed")):
        var billed = json_int(body, String("remote_tokens_billed"))
        if billed >= 0:
            res.remote_tokens_billed = billed
            res.remote_billed_measured = True

    # Extract timings if present in llama.cpp / MAX format
    var key_prompt = q + "prompt_per_second" + q + ":"
    if contains(body, key_prompt):
        var parts = body.split(key_prompt)
        if len(parts) > 1:
            var val_str = parts[1].split(",")[0].split("}")[0].strip()
            try:
                res.prompt_tok_per_sec = Float64(val_str)
            except:
                pass
                
    var key_predicted = q + "predicted_per_second" + q + ":"
    if contains(body, key_predicted):
        var parts = body.split(key_predicted)
        if len(parts) > 1:
            var val_str = parts[1].split(",")[0].split("}")[0].strip()
            try:
                res.gen_tok_per_sec = Float64(val_str)
            except:
                pass

    # Retained as a FALLBACK only, and guarded on `total_time_ms == 0` as of
    # 20261108-0702 so it cannot overwrite the client-observed round-trip
    # measured above. No current endpoint emits this key (see the `-w` note),
    # but an endpoint that starts emitting it must not silently displace the
    # measurement that is always available with one that is sometimes.
    var key_time = q + "total_time_ms" + q + ":"
    if res.total_time_ms == 0 and contains(body, key_time):
        var parts = body.split(key_time)
        if len(parts) > 1:
            var val_str = String(String(parts[1].split(",")[0].split("}")[0]).strip())
            try:
                res.total_time_ms = Int(Float64(val_str))
            except:
                pass
                
    # Basic check for syntax completion / structure
    if contains(body, "fn ") or contains(body, "pub fn") or contains(body, "def ") or contains(body, "import "):
        res.syntax_valid = True
        
    return res^
