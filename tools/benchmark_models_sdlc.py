import urllib.request
import json
import os
import time
import sys

OPENROUTER_KEY = os.environ.get('OPENROUTER_API_KEY')
RAZR1_URL = "http://100.114.9.28:1234/v1/chat/completions"

MODELS = [
    {"name": "razr1_gemma_4_e4b", "type": "local", "model_id": "google/gemma-4-e4b"},
    {"name": "qwen2.5_coder_32b", "type": "openrouter", "model_id": "qwen/qwen-2.5-coder-32b-instruct"},
    {"name": "qwen2.5_7b", "type": "openrouter", "model_id": "qwen/qwen-2.5-7b-instruct"},
    {"name": "deepseek_r1", "type": "openrouter", "model_id": "deepseek/deepseek-r1-0528"},
    {"name": "codestral_2508", "type": "openrouter", "model_id": "mistralai/codestral-2508"},
]

PROMPTS = [
    {
        "domain": "lean4",
        "description": "Lean 4 Theorem: n + 0 = n",
        "prompt": "Write a complete, valid Lean 4 theorem and proof showing that for all n : Nat, n + 0 = n. Output only the Lean 4 code."
    },
    {
        "domain": "ocaml",
        "description": "OCaml sum_even with List.fold_left",
        "prompt": "Write an OCaml function `sum_even : int list -> int` that filters even numbers and sums them using List.fold_left. Output only valid OCaml code."
    },
    {
        "domain": "gleam",
        "description": "Gleam safe_divide Result(Int, String)",
        "prompt": "Write a Gleam function with full types `pub fn safe_divide(a: Int, b: Int) -> Result(Int, String)` that returns Error(\"div_by_zero\") when b == 0, else Ok(a / b). Output only valid Gleam code."
    },
    {
        "domain": "sre_sdlc",
        "description": "SRE Incident Schema & Triad Policy",
        "prompt": "Write a minimal valid JSON object schema for an SRE incident report containing fields: incident_id (uuid string), severity (enum P0, P1, P2, P3), affected_service (string), mttr_seconds (integer >= 0). Output only the raw JSON schema."
    }
]

def query_model(target, prompt):
    start = time.time()
    payload = {
        "model": target["model_id"],
        "messages": [
            {"role": "system", "content": "You are an expert in Lean 4 formal verification, OCaml, Gleam, and SRE. Be concise and emit correct code."},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 400,
        "temperature": 0.1
    }
    
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
                "X-Title": "UOS Model Benchmark"
            },
            data=json.dumps(payload).encode("utf-8")
        )
        
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            elapsed = time.time() - start
            data = json.loads(resp.read().decode("utf-8"))
            msg = data.get("choices", [{}])[0].get("message", {})
            content = msg.get("content", "")
            reasoning = msg.get("reasoning_content", "") or msg.get("reasoning", "")
            usage = data.get("usage", {})
            return {
                "ok": True,
                "elapsed": elapsed,
                "content": content,
                "reasoning": reasoning,
                "usage": usage
            }
    except Exception as e:
        return {
            "ok": False,
            "elapsed": time.time() - start,
            "error": str(e)
        }

def evaluate_lean4(code):
    # Check syntax indicators
    has_thm = "theorem" in code or "example" in code
    has_nat = "Nat" in code or "n + 0" in code
    has_proof = "rfl" in code or "simp" in code or "omega" in code or "Nat.add_zero" in code or "rw" in code
    valid = has_thm and has_nat and has_proof
    return valid, f"thm={has_thm}, nat={has_nat}, proof={has_proof}"

def evaluate_ocaml(code):
    has_fn = "let " in code or "sum_even" in code
    has_fold = "fold_left" in code
    has_mod = "mod 2" in code or "= 0" in code or "filter" in code
    valid = has_fn and has_fold and has_mod
    return valid, f"fn={has_fn}, fold={has_fold}, mod={has_mod}"

def evaluate_gleam(code):
    has_fn = "pub fn safe_divide" in code or "fn safe_divide" in code
    has_res = "Result(Int, String)" in code or "Result(Int," in code
    # Gleam strictly forbids Result<T, E>
    no_angle_brackets = "<" not in code and ">" not in code
    has_error = "Error(\"div_by_zero\")" in code
    has_ok = "Ok(" in code
    valid = has_fn and has_res and no_angle_brackets and has_error and has_ok
    return valid, f"fn={has_fn}, res_type={has_res}, gleam_syntax={no_angle_brackets}, err={has_error}"

def evaluate_sre(code):
    try:
        # strip markdown codeblocks if any
        cleaned = code.strip()
        if cleaned.startswith("```"):
            lines = cleaned.split("\n")
            cleaned = "\n".join(lines[1:-1] if lines[-1].strip().startswith("```") else lines[1:])
        parsed = json.loads(cleaned)
        has_id = "incident_id" in str(parsed)
        has_sev = "severity" in str(parsed)
        has_svc = "affected_service" in str(parsed)
        has_mttr = "mttr_seconds" in str(parsed)
        valid = has_id and has_sev and has_svc and has_mttr
        return valid, f"json_valid=True, id={has_id}, sev={has_sev}, svc={has_svc}, mttr={has_mttr}"
    except Exception as e:
        return False, f"json_parse_err={str(e)}"

def run_benchmarks():
    results = {}
    print(f"{'Target Model':<25} | {'Lean 4':<10} | {'OCaml':<10} | {'Gleam':<10} | {'SRE/SDLC':<10} | {'Avg Latency':<12}")
    print("-" * 85)
    
    for target in MODELS:
        name = target["name"]
        results[name] = {"scores": {}, "latencies": [], "outputs": {}}
        
        for p in PROMPTS:
            domain = p["domain"]
            res = query_model(target, p["prompt"])
            if not res["ok"]:
                results[name]["scores"][domain] = (False, f"Error: {res.get('error')}")
                results[name]["latencies"].append(res["elapsed"])
                continue
                
            code = res["content"]
            results[name]["latencies"].append(res["elapsed"])
            results[name]["outputs"][domain] = code
            
            if domain == "lean4":
                score = evaluate_lean4(code)
            elif domain == "ocaml":
                score = evaluate_ocaml(code)
            elif domain == "gleam":
                score = evaluate_gleam(code)
            elif domain == "sre_sdlc":
                score = evaluate_sre(code)
            else:
                score = (False, "unknown domain")
                
            results[name]["scores"][domain] = score
            time.sleep(0.5) # gentle pacing
            
        avg_lat = sum(results[name]["latencies"]) / max(1, len(results[name]["latencies"]))
        l4 = "PASS" if results[name]["scores"].get("lean4", (False,))[0] else "FAIL"
        oc = "PASS" if results[name]["scores"].get("ocaml", (False,))[0] else "FAIL"
        gl = "PASS" if results[name]["scores"].get("gleam", (False,))[0] else "FAIL"
        sre = "PASS" if results[name]["scores"].get("sre_sdlc", (False,))[0] else "FAIL"
        print(f"{name:<25} | {l4:<10} | {oc:<10} | {gl:<10} | {sre:<10} | {avg_lat:6.2f}s")
        
    # Save full details
    with open("/home/an/NAS-setup/uos/var/benchmarks/20261104-model-benchmark-results.json", "w") as f:
        # Convert tuples for json
        serializable = {}
        for m, d in results.items():
            serializable[m] = {
                "scores": {k: [v[0], v[1]] for k, v in d["scores"].items()},
                "latencies": d["latencies"],
                "outputs": d["outputs"]
            }
        json.dump(serializable, f, indent=2)
    print("\nBenchmark details written to var/benchmarks/20261104-model-benchmark-results.json")

if __name__ == "__main__":
    run_benchmarks()
