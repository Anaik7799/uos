---
name: fractal-workspace-audit
description: Use when executing, auditing, or diagnosing workspace-wide L0-L9 fractal layers, developer environment tools, editor boots, and STPA/FMEA safety matrices using declarative Rete-UL rule engines and Notty terminal user interfaces.
---

# Fractal Workspace & Safety Audit Skill

Use this skill whenever you need to execute, audit, troubleshoot, or repair the repository's operational environment, editor configurations, or STPA/FMEA safety compliance logs. The repository mandates using a declarative, forward-chaining rule system (embedded Rete-UL) for all local environment audits to prevent regressions and maintain total architectural homeostasis.

---

## 1. Core Objectives & Scope

The audit engine runs checks across the 9 Fractal Layers defined by the workspace specifications:

*   **L0 (Toolchain & Editors)**: Verifies the existence of critical binaries (`zig`, `opam`, `dune`) and ensures all major editors boot cleanly with correct layer syntax.
*   **L0 (Repository Boundaries)**: Restricts non-Zig files in `src/` and non-OCaml files in `scripts/` to enforce clean language boundaries.
*   **L1 (SDLC Artifacts)**: Checks that all 10 mandated documentation files exist and carry canonical, verbatim build-gate references.
*   **L2 (STPA Safety)**: Inspects safety analyses, ensuring that unsafe control actions (UCAs) are properly traced under STAMP constraints.
*   **L4 (FMEA Mitigations)**: Evaluates risk models, checking that failure modes are paired with explicit mitigation strategies.
*   **L7 (Fixture Mirrors)**: Confirms byte-for-byte matching between VM and repository representation fixtures.
*   **L9 (SQLite Gate)**: Assures that a valid, cryptographically verified green-stamp run exists for the current HEAD commit hash in SQLite.

Database access must go through the harness or authored OCaml code. This audit
uses the pinned OCaml `Sqlite3` binding in-process and must never discover or
invoke an external database client.

---

## 2. Command Reference

### Standard Run (Normal Notty TUI mode)
To see an animated live-updating TUI with a progress bar and status radar:
```bash
./scripts/fractal_workspace_audit.ml
```

### Clean Mode (Only prints final convergence/deviation outcomes)
Ideal for CI/CD pipelines or clean scripts integrations:
```bash
./scripts/fractal_workspace_audit.ml --mode normal
```

### Detailed Logging Mode (OTel Spans and Traceparents)
```bash
./scripts/fractal_workspace_audit.ml --mode logging
```

### Forensic Debug Mode (Dumps Rete Working Memory Facts)
```bash
./scripts/fractal_workspace_audit.ml --mode verbose
```

### Auto-Repair Configuration Mode
Idempotently creates missing editor configuration directories and repairs the Spacemacs parenthesis alignment:
```bash
./scripts/fractal_workspace_audit.ml --setup
```

---

## 3. Custom Rule Architecture

### Working Memory Facts Projection
Facts are projected into working memory in the OODA Observe phase:
```ocaml
(* Example Fact Definition *)
type fact = {
  fact_kind : string;
  attrs : (string * Value.t) list;
}
```

### Writing a Declarative Rule
Rules match on pattern sequences and execute fail-closed verification functions:
```ocaml
let rules_set = [
  {
    name = "L0 Toolchain: Core developer tools must be found in PATH";
    patterns = [
      {
        pat_kind = "ToolchainTool";
        conds = [FieldCmp ("status", Neq, Value.String "FOUND")];
        bind_name = Some "tool"
      }
    ];
    action = (fun _ facts ->
      let tool = List.assoc "tool" facts in
      let name = List.assoc "name" tool.attrs in
      Error ("Missing core toolchain tool: " ^ Value.to_string name)
    )
  }
]
```

---

## 4. Maintenance SOP (Ecosystem Porting)

Because the script runs on bleeding-edge compiler switches (OCaml 5.5.0+), standard library record updates can break legacy TUI libraries.
- If OCaml stdlib `Format.formatter_out_functions` adds/removes fields, you must pull `notty`'s source under `third_party/notty_pkg/src/notty.ml` and patch its constructors.
- For OCaml 5.5.0, we injected `; out_width = (fun _s ~pos:_ ~len -> len)` directly into `formatter_of_out_functions` instantiation records.
