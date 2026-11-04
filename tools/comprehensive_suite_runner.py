import urllib.request
import json
import os
import time

OPENROUTER_KEY = os.environ.get('OPENROUTER_API_KEY')
RAZR1_URL = "http://100.114.9.28:1234/v1/chat/completions"

# Comprehensive test suite covering all 5 core engineering domains
SUITE = [
    # 1. Lean 4 Formal Verification (Induction & Structure)
    {
        "id": "lean4_induction",
        "domain": "Lean 4",
        "prompt": "Write a complete, valid Lean 4 theorem and proof showing: theorem add_zero (n : Nat) : n + 0 = n. Use standard Lean 4 syntax with ':= by rw [Nat.add_zero]' or induction. Output only the Lean 4 code.",
        "validator": lambda c: ("theorem" in c or "example" in c) and "Nat" in c and ("rw" in c or "induction" in c or "rfl" in c or "simp" in c)
    },
    {
        "id": "lean4_inductive_type",
        "domain": "Lean 4",
        "prompt": "Write a Lean 4 inductive type representing a binary tree of integers and a function that counts the nodes. Output only the Lean 4 code.",
        "validator": lambda c: "inductive" in c and "Tree" in c and "def" in c
    },

    # 2. OCaml Functional & Algebraic Verification
    {
        "id": "ocaml_algebraic",
        "domain": "OCaml",
        "prompt": "Write an OCaml module with type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree and a function val size : 'a tree -> int. Output only valid OCaml code.",
        "validator": lambda c: "type" in c and "tree" in c and "Leaf" in c and "Node" in c and "let rec size" in c
    },
    {
        "id": "ocaml_fold",
        "domain": "OCaml",
        "prompt": "Write an OCaml function sum_even : int list -> int that filters even numbers and sums them using List.fold_left. Output only valid OCaml code.",
        "validator": lambda c: "let " in c and "fold_left" in c and ("mod 2 = 0" in c or "mod 2 == 0" in c or "x mod 2" in c)
    },

    # 3. Gleam Functional Architecture & Strict Types
    {
        "id": "gleam_safe_divide",
        "domain": "Gleam",
        "prompt": "Write a Gleam function with full types `pub fn safe_divide(a: Int, b: Int) -> Result(Int, String)` that uses `case b` to return Error(\"div_by_zero\") when b is 0, else Ok(a / b). Output only valid Gleam code.",
        "validator": lambda c: "pub fn safe_divide" in c and "Result(Int, String)" in c and "case b" in c and "Error(\"div_by_zero\")" in c and "Ok(" in c
    },
    {
        "id": "gleam_custom_type",
        "domain": "Gleam",
        "prompt": "Write a Gleam custom type `pub type Status { Idle Active Paused }` and a function `pub fn to_string(status: Status) -> String` that pattern matches over it. Output only valid Gleam code.",
        "validator": lambda c: "pub type Status" in c and "Idle" in c and "Active" in c and "case" in c and "-> String" in c
    },

    # 4. Software Engineering & AI-Enabled SDLC
    {
        "id": "sdlc_poka_yoke",
        "domain": "SDLC",
        "prompt": "Write a TypeScript interface for an immutable Pull Request Review containing: pr_id (number), reviewer (string), verdict ('approve' | 'request_changes' | 'comment'), and sha256 (string). Output only the TypeScript interface.",
        "validator": lambda c: "interface" in c and "pr_id" in c and "reviewer" in c and "verdict" in c and "sha256" in c
    },

    # 5. SRE Telemetry & Chaos Engineering
    {
        "id": "sre_circuit_breaker",
        "domain": "SRE",
        "prompt": "Write a clean JSON schema for an SRE circuit breaker configuration with fields: service_name (string), failure_threshold_pct (number), recovery_timeout_ms (integer), and fallback_enabled (boolean). Output only raw JSON.",
        "validator": lambda c: "service_name" in c and "failure_threshold_pct" in c and "recovery_timeout_ms" in c and "fallback_enabled" in c
    }
]

CANDIDATES = [
    {"name": "razr1: gemma-4-e4b (Local Current)", "type": "local", "model_id": "google/gemma-4-e4b"},
    {"name": "OpenRouter: Qwen2.5-Coder-32B", "type": "openrouter", "model_id": "qwen/qwen-2.5-coder-32b-instruct"},
    {"name": "OpenRouter: Qwen2.5-7B-Instruct", "type": "openrouter", "model_id": "qwen/qwen-2.5-7b-instruct"},
    {"name": "OpenRouter: DeepSeek-R1-0528", "type": "openrouter", "model_id": "deepseek/deepseek-r1-0528"},
    {"name": "OpenRouter: Codestral-2508", "type": "openrouter", "model_id": "mistralai/codestral-2508"}
]

def run_test(target, test_case):
    payload = {
        "model": target["model_id"],
        "messages": [
            {"role": "system", "content": "You are a master of Lean 4 formal verification, OCaml, Gleam, SDLC, and SRE. Be strictly correct with syntax."},
            {"role": "user", "content": test_case["prompt"]}
        ],
        "max_tokens": 400,
        "temperature": 0.1
    }
    
    start = time.time()
    if target["type"] == "local":
        req = urllib.request.Request(
            RAZR1_URL,
            headers={"Content-Type": "application/json"},
            data=json.dumps(payload).encode("utf-8")
        )
    else:
        req = urllib.request.Request(
            "https://openrouter.ai/api/v1/chat/completions",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {OPENROUTER_KEY}",
                "HTTP-Referer": "https://uos.tailnet",
                "X-Title": "UOS Model Benchmark Matrix"
            },
            data=json.dumps(payload).encode("utf-8")
        )
        
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            dur = time.time() - start
            data = json.loads(resp.read().decode("utf-8"))
            msg = data.get("choices", [{}])[0].get("message", {})
            content = msg.get("content", "")
            valid = test_case["validator"](content)
            return {"ok": True, "dur": dur, "valid": valid, "content": content}
    except Exception as e:
        return {"ok": False, "dur": time.time() - start, "valid": False, "err": str(e)}

def main():
    print(f"\n{'Model':<38} | {'Lean 4':<8} | {'OCaml':<8} | {'Gleam':<8} | {'SDLC':<8} | {'SRE':<8} | {'Score':<8} | {'Lat':<7}")
    print("-" * 105)
    
    results = {}
    for c in CANDIDATES:
        scores = {}
        latencies = []
        domain_counts = {"Lean 4": [0,0], "OCaml": [0,0], "Gleam": [0,0], "SDLC": [0,0], "SRE": [0,0]}
        
        for t in SUITE:
            res = run_test(c, t)
            domain = t["domain"]
            domain_counts[domain][1] += 1
            latencies.append(res["dur"])
            if res.get("valid", False):
                domain_counts[domain][0] += 1
            time.sleep(0.3)
            
        total_pass = sum(v[0] for v in domain_counts.values())
        total_tests = len(SUITE)
        avg_lat = sum(latencies) / len(latencies)
        
        l4 = f"{domain_counts['Lean 4'][0]}/{domain_counts['Lean 4'][1]}"
        oc = f"{domain_counts['OCaml'][0]}/{domain_counts['OCaml'][1]}"
        gl = f"{domain_counts['Gleam'][0]}/{domain_counts['Gleam'][1]}"
        sd = f"{domain_counts['SDLC'][0]}/{domain_counts['SDLC'][1]}"
        sr = f"{domain_counts['SRE'][0]}/{domain_counts['SRE'][1]}"
        pct = f"{(total_pass/total_tests)*100:.0f}%"
        
        print(f"{c['name']:<38} | {l4:<8} | {oc:<8} | {gl:<8} | {sd:<8} | {sr:<8} | {pct:<8} | {avg_lat:4.2f}s")
        results[c["name"]] = {"domains": domain_counts, "pct": pct, "avg_lat": avg_lat}

    with open("/home/an/NAS-setup/uos/var/benchmarks/20261104-comprehensive-suite-results.json", "w") as f:
        json.dump(results, f, indent=2)

if __name__ == "__main__":
    main()
