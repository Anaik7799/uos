# 04 — Add a Gospel contract (L3)

Goal: a new candidate `.mli` carries a checkable Gospel specification and is
registered in the contract catalog. A contract is an **obligation, not
evidence** — it never grants parity credit (that still needs L4–L6).

## Substitution table

| Placeholder | Meaning | Example |
|---|---|---|
| `⟨CANDIDATE⟩` | candidate module | `gemini_schema` |
| `⟨CAP⟩` | capability key | `model_routing.gemini_adapter` |
| `⟨LAW⟩` | UPPER-KEBAB law name | `GEMINI-TOOL-SCHEMA-SANITIZATION` |

## Steps

### 1. Write the specification into the `.mli`

ACTION: In `hermes_harness/⟨CANDIDATE⟩.mli`, add `(*@ ... *)` annotations under
the `val` declarations. Copy the style from an existing green contract
(`gemini_schema.mli`, `bedrock_converse.mli`). Rules that prevent the known
lint failures:

- Only types Gospel can resolve. For `Yojson.Safe.t` use the stub type in
  `hermes_harness/gospel_stubs/` (strictly weaker than the real type — it can
  only cause a false rejection, never a false acceptance).
- Keep clauses first-order and total: `requires`/`ensures` over the declared
  arguments; no OCaml expressions Gospel's parser rejects (check an existing
  file for the accepted subset).
- One law per exported behavior; name the central one `⟨LAW⟩`.

### 2. Lint it

ACTION: run the gospel check the harness uses:
`dune exec hermes_harness/hermes_harness_gospel_check.exe` (the runner reads
`HERMES_GOSPEL` if the binary is not on PATH).

VERIFY: the runner reports the `.mli` as checked, exit 0.
IF-FAIL `Syntax error` / `Symbol not found in scope` / `No module with name`:
the type or expression is outside Gospel's subset — use the stub type or
simplify the clause. Do NOT delete the spec to pass; do NOT weaken it to a
tautology (a vacuous spec is worse than none).
IF-FAIL because the `gospel` binary is missing: this is **Blocked
(Environment)** — report it; never mark the contract checked.

### 3. Register in the catalog

ACTION: In `hermes_harness/contract_catalog.ml`, append to `all` (keep the
existing order — dependency order, newest last):

```ocaml
{ id = "⟨CAP⟩.⟨short_behavior⟩";
  capability_key = "⟨CAP⟩";
  interface = "hermes_harness/⟨CANDIDATE⟩.mli";
  law = "⟨LAW⟩" };
```

VERIFY: `dune exec hermes_harness/test_contract_catalog.exe` → `failed: 0`
(it checks ids unique, interfaces exist on disk, capability keys resolve).

### 4. Re-run the battery slice

ACTION: `dune exec hermes_harness/test_parity_compare.exe` and the gospel check
once more (a catalog entry pointing at an unlinted file must never land).

VERIFY: both green.

## What NOT to do

- Never register a contract whose interface file does not exist yet ("I'll add
  it next commit") — the catalog test will fail and the honest order is
  interface → spec → lint → register.
- Never mark a capability's contract as satisfying parity anywhere. L3 is an
  obligation; the dashboards count it separately from Verified.
