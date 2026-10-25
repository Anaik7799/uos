---
name: ocaml-scripting
description: Use when creating, modifying, or running project-based scripting tools and helper tasks. Mandates using OCaml (standalone or Dune-managed) with Bos for all scripting usecases, establishing algebraic structures, standard operating procedures, and strict type-safety over shell scripts.
---

# OCaml Scripting Skill

Use this skill whenever you need to create, modify, or execute scripts, automation tasks, or CLI helper tools in the project. This codebase enforces an **OCaml-only scripting mandate** to guarantee type safety, compile-time validation, and uniform architectural standards. Shell scripts, Python scripts, and other external script engines are strictly prohibited.

*Context Update:* The scripting program (7 phases, layers L0–L9) landed **217 standalone OCaml scripts under `scripts/` plus 55 dune-linked harness support modules** (measured 2026-08-02; `ls scripts/*.ml | wc -l` is ground truth). They span Jidoka build-halting, Zettelkasten Dung semantics, `git bisect` orchestration, and SMT logic checking. The 55 phase-7 harness modules are now REAL + honest (DIVERGENCE 682): **11 law-carrying enforcement guards** (wired into the default gate / `--check-guards` — e.g. `db_integrity_checker`, `formal_proof_staleness_guard`, `wiki_gate_coupling_prover`, `stratum_c_quarantine_auditor`, + 7 promotions) + **44 report-only** completions — 0 dead stubs. A report-only module may STILL never be described as "enforcing" or "proving" anything (the binding rule); promote report-only → law-carrying only via a law-carrying slice.

## Required Reads

Before implementing or running any script, read:
1. `docs/OCAML_SCRIPTING_SOP.md` (The complete standard operating procedure for scripting)
2. `AGENTS.md` §"Harness & Scripting Rule" (the binding OCaml-Only Scripting Mandate and prohibited languages)
3. `SAFETY_ANALYSIS.md` §11 (CTRL-OCAML-SCRIPT / CTRL-HARNESS-MOD, UCA-SCRIPT-1..4 constraints: quota bounds, atomic swaps, fail-fast, report-only gate isolation)

## Pinned Toolchain

- The project compiler is exactly OCaml 5.5.0 in the repository-local switch.
- `scripts/setup_ocaml_550.ml --install` is the only standing dependency/pin
  setup path; `--check` verifies compiler identity, package closure, pin
  presence, clean dependency trees, and expected Git tree hashes.
- Compatibility transforms live under `vendor/ocaml-5.5-patches/`; never edit
  ignored `third_party/` pins without updating the tracked patch and expected
  tree hash in the same change.
- The PPX domain is ppxlib 0.38, the Jane Street v0.18 preview closure,
  ppx_deriving 6.1.3, ppx_deriving_yojson from its pinned OCaml-5.5-compatible
  source revision, js_of_ocaml-ppx 6.4.1, and the patched Bisect PPX.
  Bonsai/Bonsai_web/Virtual_dom `v0.18~preview.130.106+341` and Dream `dev` are
  admitted on OCaml 5.5.0 through exact source pins and tracked patches.
  Microsoft Playwright v1.59.0 is retained as a source-only, tree-verified
  implementation/docs oracle matching the direct OCaml binding and driver.
  Interactive browser code is authored in OCaml and compiled to generated
  JavaScript with js_of_ocaml; Dream/backend/database code remains native OCaml.

---

## 1. The Algebra of Scripting

Every script is modeled as an algebraic state transformer over the execution context.

### Signature (The Script Interface)
Let $S$ be the type representing the OS system state (file system, process list, environment variables).
A script is a function:
$$\text{Script} : \text{Args} \to S \to \text{Result}(S \times \text{ExitCode}, \text{Error})$$

Where:
* **Args**: List of command-line strings (`string list`).
* **ExitCode**: Standard Unix exit code (`int` where $0$ is success, non-zero is failure).
* **Result**: Built-in OCaml `result` type carrying the modified system state or a descriptive error.

### Semantic Domain
The semantic domain $\mathcal{D}$ of a script is the set of all deterministic mutations on the filesystem and environment. We denote the behavior of a script $\text{Script}$ with inputs $A \in \text{Args}$ as:
$$\text{denote}(\text{Script}, A) = f : S \to S \times \text{ExitCode}$$

### Laws of Scripting
Every script written in OCaml must satisfy these fundamental algebraic laws:

1. **Composition Homomorphism (Sequential Composition)**:
   For any two sequential scripting actions $P$ and $Q$:
   $$\text{denote}(P ; Q) = \text{denote}(Q) \circ \text{denote}(P)$$
   In code, this is enforced by monadic sequencing via `Result.bind` (or `let*` operators) in `Bos`.

2. **Idempotence of Setup / Guard Actions**:
   Any action $E$ that establishes a prerequisite state (such as directory creation, configuration writing) must be idempotent:
   $$\text{denote}(E ; E) = \text{denote}(E)$$
   In code: `OS.Dir.create` (which acts like `mkdir -p`) must not fail or modify the state if the directory already exists.

3. **Totality & Fail-Fast (Short-Circuit Law)**:
   For any sequence of steps $A_1 ; A_2 ; \dots ; A_n$, if any action $A_i$ results in an `Error`:
   $$\text{denote}(A_1 ; \dots ; A_i ; \dots ; A_n) = \text{Error}$$
   The script must abort instantly on the first error to avoid corrupting the system state. No dynamic recovery is allowed unless specifically specified by the algebraic signature. Never use bare `try ... with _ -> ()` to swallow system errors.

---

## 2. Standard Operating Procedures (SOP)

### Workflow A: Standing standalone scripts (Temporary / Disposable Helpers)
For single-file, lightweight scripts (like those in `scripts/`):
1. File extension must be `.ml` (e.g., `scripts/my_helper.ml`).
2. The file must start with the following canonical shebang:
   ```ocaml
   #!/usr/bin/env -S opam exec -- ocaml
   #use "topfind";;
   #require "bos.setup";;
   (* Optional: #require "sqlite3";; *)
   ```
3. Use `Bos` and standard OCaml `Sys`/`Filename`/`Unix` libraries for system configuration and file manipulation. **Do NOT use `shexp`** as it is not in the pinned opam environment.
4. Provide strict argument parsing. For anything beyond 2 arguments, use `Cmdliner`.
5. Script outputs must be documented with `@agent_intent` and `@laws`.

### Workflow B: Dune-managed helper tasks (Repository Integrations / Canonical Helpers)
For complex, multi-module scripts, Z3 solvers, AST parsers, or performance-sensitive tasks:
1. Define the scripting tool as a `.ml` file within `harness/`.
2. Register the dependencies in `harness/dune` within the `zigvm_harness_support` library.
3. These modules are evaluated natively during `opam exec -- dune build ./harness/zigvm_harness.exe`.

---

## 3. Idiomatic Code Patterns

### Bos Pattern (Safe OS manipulation with Results)
```ocaml
open Bos

let create_and_write_file path content =
  let open OS.Result.Infix in
  OS.Dir.create (Fpath.parent path) >>= fun _ ->
  OS.File.write path content

let run () =
  let file_path = Fpath.v "/tmp/build_stamp.txt" in
  match create_and_write_file file_path "VERSION=1.0.0" with
  | Ok () -> OS.Result.ok 0
  | Error (`Msg err) ->
      Printf.eprintf "Fatal: %s\n" err;
      OS.Result.ok 1
```

---

## 4. Operational Directives

- **NO BASH, PYTHON, OR NODE.JS:** Any scripting task must be written in OCaml. If you encounter an existing script written in another language, you must rewrite it in OCaml under this standard before extending its features.
- **HARNESS/OCAML DATABASE ACCESS ONLY:** Database access must go through the harness or authored OCaml code. Use the shared `Db` actor for harness operations or the pinned `Sqlite3` binding in standalone OCaml; never shell an external database client or use another language binding.
- **WEB DATA BOUNDARY:** Bonsai browser code never opens or mutates SQLite.
  Dream calls a typed native-OCaml read model, which reaches the database only
  through the shared `Db` actor. Keep browser output generated and routes
  read-only unless a separately safety-scoped control path is designed.
- **ZERO LEAKS:** Native-compiled scripts must compile cleanly without warnings (`-w @A-4-29-40-41-42-44-45-48-58`).
- **ERROR WRAPPING:** Never swallow OCaml exceptions; catch them and lift them into `result` types or `Bos` logging frameworks.
- **VERIFICATION GATES:** If a script modifies the workspace configuration, run the canonical verification gate to ensure correctness:
  ```bash
  opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD"
  ```
