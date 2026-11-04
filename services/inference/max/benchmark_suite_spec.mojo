from std.sys import exit

struct BenchmarkSuite:
    var domain_names: List[String]
    var weights: List[Float64]

    def __init__(out self):
        self.domain_names = List[String]()
        self.weights = List[Float64]()
        
        self.domain_names.append("Lean 4 Formal Verification")
        self.weights.append(0.25)
        
        self.domain_names.append("OCaml Algebraic Laws & Contracts")
        self.weights.append(0.20)
        
        self.domain_names.append("Gleam Type System & POODAVR")
        self.weights.append(0.25)
        
        self.domain_names.append("AI-SDLC Architectural Synthesis")
        self.weights.append(0.15)
        
        self.domain_names.append("SRE Observability & Telemetry")
        self.weights.append(0.15)

    def print_plan(self):
        print("==========================================================================================")
        print("  UOS REFINED BENCHMARK SUITE SPECIFICATION (100% MOJO 1.0.0 ENGINE)                      ")
        print("==========================================================================================")
        print("Domain Allocations & Weights:")
        for i in range(len(self.domain_names)):
            print("  - [Domain ", i + 1, "]: ", self.domain_names[i], " (Weight: ", self.weights[i] * 100.0, "%)")
        print("------------------------------------------------------------------------------------------")
        print("Scoring Criteria per Candidate Output:")
        print("  1. Syntactic Soundness (Zero compilation/parsing errors in target language compiler)")
        print("  2. Semantic Closure    (No hallucinations, unprovable sorry/axioms, or untyped casts)")
        print("  3. Latency & Token Economy (Time-to-first-token < 500ms, token rate > 40 tok/s)")
        print("  4. Zero-Muda Invariant (Zero Bevy/Graphite dependencies, pure functional primitives)")
        print("==========================================================================================")

def main():
    var suite = BenchmarkSuite()
    suite.print_plan()
