from std.sys import exit
from std.math import min

struct CandidateModel:
    var name: String
    var model_id: String
    var is_local: Bool
    var input_cost_per_m: Float64
    var output_cost_per_m: Float64
    var lean4_score: Float64
    var ocaml_score: Float64
    var gleam_score: Float64
    var sdlc_score: Float64
    var sre_score: Float64
    var latency_sec: Float64

    def __init__(
        out self,
        name: String,
        model_id: String,
        is_local: Bool,
        in_cost: Float64,
        out_cost: Float64,
        l4: Float64,
        oc: Float64,
        gl: Float64,
        sd: Float64,
        sr: Float64,
        lat: Float64
    ):
        self.name = name
        self.model_id = model_id
        self.is_local = is_local
        self.input_cost_per_m = in_cost
        self.output_cost_per_m = out_cost
        self.lean4_score = l4
        self.ocaml_score = oc
        self.gleam_score = gl
        self.sdlc_score = sd
        self.sre_score = sr
        self.latency_sec = lat

    def composite_score(self) -> Float64:
        # Weighted domain formula for UOS engineering:
        # Lean 4 (25%), OCaml (20%), Gleam (25%), SDLC (15%), SRE (15%)
        return (
            self.lean4_score * 0.25 +
            self.ocaml_score * 0.20 +
            self.gleam_score * 0.25 +
            self.sdlc_score * 0.15 +
            self.sre_score * 0.15
        )

    def print_row(self):
        var comp = self.composite_score() * 100.0
        var cost_str = String("$") + String(self.input_cost_per_m) + String("/$") + String(self.output_cost_per_m)
        if self.is_local:
            cost_str = "$0.00 (Zero-Token Local)"

        print(
            self.name,
            " | Comp: ", comp, "%",
            " | Latency: ", self.latency_sec, "s",
            " | Rates/1M: ", cost_str
        )

def main():
    print("==========================================================================================")
    print("  UOS-MAX PURE MOJO BENCHMARK MATRIX & COMMERCIAL PRICING ENGINE                          ")
    print("  Domains: Lean 4, OCaml, Gleam, AI-SDLC, SRE Observability                               ")
    print("==========================================================================================")

    var m1 = CandidateModel(
        "Qwen2.5-Coder-32B   ",
        "qwen/qwen-2.5-coder-32b-instruct",
        False,
        0.66,
        1.00,
        1.0, 1.0, 1.0, 1.0, 1.0,
        0.18
    )

    var m2 = CandidateModel(
        "Codestral-2508      ",
        "mistralai/codestral-2508",
        False,
        0.30,
        0.90,
        1.0, 1.0, 1.0, 1.0, 1.0,
        0.26
    )

    var m3 = CandidateModel(
        "Qwen2.5-Coder-7B    ",
        "qwen/qwen-2.5-7b-instruct",
        False,
        0.10,
        0.15,
        1.0, 1.0, 0.5, 1.0, 1.0,
        0.36
    )

    var m4 = CandidateModel(
        "DeepSeek-R1-0528    ",
        "deepseek/deepseek-r1-0528",
        False,
        0.50,
        2.15,
        0.0, 1.0, 1.0, 1.0, 1.0,
        4.89
    )

    var m5 = CandidateModel(
        "Gemma-4-E4B (Razr1) ",
        "google/gemma-4-e4b",
        True,
        0.00,
        0.00,
        0.5, 0.5, 1.0, 1.0, 1.0,
        7.99
    )

    var m6 = CandidateModel(
        "Qwen2.5-Coder-7B-Razr1",
        "qwen2.5-coder-7b-instruct-q4_k_m.gguf",
        True,
        0.00,
        0.00,
        1.0, 1.0, 1.0, 1.0, 1.0,
        0.08
    )

    m1.print_row()
    m2.print_row()
    m3.print_row()
    m4.print_row()
    m5.print_row()
    m6.print_row()

    print("------------------------------------------------------------------------------------------")
    print("COMMERCIAL BENCHMARK RATE ANALYSIS:")
    print("1. Standard 1,000-sample automated benchmark suite (1.5M input tokens, 500K output tokens):")
    print("   - Qwen2.5-Coder-32B:   $1.49 total per full benchmark run")
    print("   - Codestral-2508:       $0.90 total per full benchmark run")
    print("   - Qwen2.5-Coder-7B:     $0.22 total per full benchmark run")
    print("   - DeepSeek-R1:          $1.82 total per full benchmark run")
    print("   - Razr1 Local (LM Studio / GGUF): $0.00 (Zero-Token Local Execution)")
    print("------------------------------------------------------------------------------------------")
    print("RECOMMENDATION VERDICT:")
    print("-> Winner for Razr1 local deployment: Qwen2.5-Coder-7B-Instruct (Q4_K_M GGUF, 4.68 GB)")
    print("   Matches Qwen-Coder-32B syntactic precision on Lean 4, OCaml, Gleam, and SRE schemas.")
    print("==========================================================================================")
