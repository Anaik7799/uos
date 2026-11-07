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
    Receipt, capture, contains, json_int, occurrences, shell_quote
)

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

    def __init__(out self):
        self.status_code = 0
        self.prompt_tok_per_sec = 0.0
        self.gen_tok_per_sec = 0.0
        self.total_time_ms = 0
        self.syntax_valid = False
        self.response_text = ""
        self.remote_tokens_billed = 0


def calculate_utility_score(
    prompt_tps: Float64,
    gen_tps: Float64,
    latency_ms: Int,
    syntax_valid: Bool,
    remote_billed: Int
) -> Int:
    """Computes integer utility score [0..1000] aligned with Lean computeUtilityScore."""
    var t_score = Int((prompt_tps + gen_tps * 2.0) * 35.0 / 10.0)
    var l_score = 0
    if latency_ms < 2000 and latency_ms > 0:
        l_score = Int(Float64(2000 - latency_ms) * 25.0 / 20.0)
    var s_score = 300 if syntax_valid else 0
    var c_score = 100 if remote_billed == 0 else 0
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
    var cmd = "curl -s --max-time 150 -w '\n%{http_code}' -X POST " + url + " -H 'Content-Type: application/json' -d " + shell_quote(payload)
    var raw = capture(cmd, 150)
    
    if raw.byte_length() == 0:
        return res^
        
    var lines = String(raw).split("\n")
    if len(lines) >= 2:
        try:
            res.status_code = Int(lines[len(lines)-1].strip())
        except:
            res.status_code = 0
            
    var body = ""
    for i in range(len(lines) - 1):
        body += lines[i]
        
    res.response_text = body
    
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

    var key_time = q + "total_time_ms" + q + ":"
    if contains(body, key_time):
        var parts = body.split(key_time)
        if len(parts) > 1:
            var val_str = parts[1].split(",")[0].split("}")[0].strip()
            try:
                res.total_time_ms = Int(Float64(val_str))
            except:
                pass
                
    # Basic check for syntax completion / structure
    if contains(body, "fn ") or contains(body, "pub fn") or contains(body, "def ") or contains(body, "import "):
        res.syntax_valid = True
        
    return res^
