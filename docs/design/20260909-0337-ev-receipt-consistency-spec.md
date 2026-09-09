# EV receipt consistency specification v1

Created 2026-09-09T03:35:37Z from the synchronized host clock.
#fractal-l0 #fractal-l3 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Source](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0337-ev-receipt-consistency-spec.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0337-ev-receipt-consistency-journal.md)

The native OCaml validator checks consistency of one EV's evidence bundle. Its only successful state is `EVIDENCE_CONSISTENT`, with `authority: NONE`. It has no admission, scheduler, review, integration or runtime effect. EV numbers are constrained to 1–109; the admitted ceiling is not changed. Actual independent Codex and AGY review must subsequently bind the complete bundle digest under the governing policy.

A fabricated or synthetic receipt can be consistent. This tool does **not** authenticate producer identity, prove that a reported invocation ran, interpret verifier output, establish acceptance completeness, or certify that a claimed formal proof refines the implementation. Those remain independent review obligations. Tests deliberately use synthetic invocations, demonstrating this boundary.

## Invocation and toolchain

From the isolated workspace, build using the already-realized repository OCaml toolchain:

```sh
OCAMLPATH=/home/an/NAS-setup/uos/toolchains/opam-ocaml/lib PATH=/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin:/usr/bin:/bin dune build --root tools/ev_receipts -j 2
tools/ev_receipts/_build/default/receipt_test.exe /absolute/isolated/workspace
tools/ev_receipts/_build/default/ev_receipt.exe validate /absolute/isolated/workspace relative/bundle.json 1 337f99137673d7866b958a38bd490fb876b2880f
```

The tests print a fresh synthetic bundle path for the third command. Host `chronyc` access is required by the CLI. There is no clock bypass flag. The library's explicit `now` argument supports deterministic caller observations and tests; it does not supply authenticated time by itself. Missing dependencies are failures, never triggers for installation. Jujutsu is resolved through the existing repository `toolchains/nix-profile/bin/jj`; source observation uses read-only `--ignore-working-copy` operations and explicit file templates.

## Bundle schema

All object keys are exact: unknown, missing or duplicate keys at any depth fail closed. Strings and arrays are bounded. SHA-256 values are 64 lowercase hexadecimal characters; the caller supplies an expected 40-character immutable Jujutsu commit ID and expected EV independently of the bundle.

This example is illustrative, uses placeholder hashes and is **not passing evidence**:

```json
{
  "schema": "uos.ev-bundle.v1",
  "ev": 1,
  "revision": "337f99137673d7866b958a38bd490fb876b2880f",
  "acceptance_ids": ["EV01-CHECK-1"],
  "scope": ["tools/km_provenance/dune-project"],
  "source_manifest": [
    {"path": "tools/km_provenance/dune-project", "sha256": "<actual SHA-256>"}
  ],
  "policy": {"path": "contracts/rules/20260908-0912-provenance-integrity-contract.md", "sha256": "<actual SHA-256>"},
  "runtime": {"path": "evidence/runtime.json", "sha256": "<actual SHA-256>"},
  "formal": {"path": "evidence/formal.json", "sha256": "<different actual SHA-256>"}
}
```

Acceptance IDs must be nonempty, unique, and contain only letters, digits, periods, hyphens and underscores. The source manifest is sorted by path, unique, nonempty and covers scope exactly. Each listed source and policy hash must match both local file bytes and the regular file at the immutable candidate. Thus agreeing caller-written labels cannot substitute for candidate source observations. The manifest digest is SHA-256 of `Yojson.Basic.to_string` on the parsed `source_manifest` value, preserving its entry and key order. Receipt producers must use that exact compact serialization; arbitrary pretty-printing is not the digest input.

Every file reference is exactly `{ "path": string, "sha256": string }`. Paths are workspace-relative regular files, with no empty, dot, parent or special-character components; symlinks and nonregular files are refused. `.jj`, `.git`, `.ssh` and `.gnupg` components are refused. Source and policy existence/type are checked in Jujutsu before their exact bytes are read. Files are checked for ordinary concurrent change across descriptor reads and rehashed before the result. This assumes a trusted host and cooperative writers; it is not a descriptor-relative defense against hostile same-UID races.

## Receipt schema

Both receipts have these exact keys:

| Key | Required value |
|---|---|
| `schema`, `kind` | `uos.ev-receipt.v1`; `runtime` or `formal` respectively |
| `ev`, `revision` | Exact bundle identity |
| `scope`, `acceptance_ids` | Exact bundle sets, unique and nonempty |
| `source_manifest_sha256`, `policy_sha256` | Digests bound by the bundle |
| `invocation` | Object described below |
| `clock` | Object described below |
| `toolchain` | Exact keys `name`, `version`, `executable_sha256`; nonempty names and valid digest |
| `negative_controls` | Nonempty array of the control objects below |
| `formal_result` | Runtime: null. Formal: the result object below |

Invocation exact keys: `id`, `command`, `started_at`, `finished_at`, `exit_code`, `timed_out`, `output_overflow`, `status`, `executed_checks`, `failed_checks`, `skipped_checks`, `output`. Command is a nonempty argv array; repeated arguments are valid. Exit is zero, status is `PASS`, executed count is at least the acceptance count and at most 1,000,000, failed and skipped counts are zero, and timeout/overflow are false. Output is a nonempty file bound by its reference digest. Runtime and formal receipts must have distinct receipt digests, invocation IDs and output digests. Toolchain executable digest is a producer identity claim; this reader does not load or execute that binary.

Clock exact keys: `source`, `observed_at`, `stratum`, `offset_seconds`, `uncertainty_seconds`, `reference_age_seconds`. Source is `chronyc tracking`; observation is positive, no later than invocation start and at most 300 seconds earlier. Stratum is 1–15; absolute offset and nonnegative uncertainty are below two seconds; reference age is 0–4096 seconds. The CLI additionally observes actual host chrony before and after validation, checking synchronization and UTC progression against monotonic elapsed time with a 250 ms tolerance. Receipt clock fields themselves remain producer claims.

Negative control exact keys: `id`, `command`, `started_at`, `finished_at`, `expected_exit_code`, `actual_exit_code`, `timed_out`, `output_overflow`, `output`. IDs are unique. Expected exit is 1–125 and matches actual exit, with no timeout/overflow. Its time interval is inside the positive invocation interval. Its nonempty output is digest-checked and must differ from that receipt's positive output. Semantic relevance of the control remains reviewable producer evidence.

Formal result exact keys: `verifier`, `result`, `sorry_count`, `unsupported_count`, `undeclared_axioms`. Verifier is nonempty; result is `PASS`; both counts are zero; undeclared axioms is the empty array. This validates the report's claims; it is not a formal proof checker or output-language interpreter.

## Resource and time limits

| Resource | Bound |
|---|---|
| Each referenced file / JSON input | 1 MiB |
| Aggregate referenced read bytes | 16 MiB |
| Tracked references | Fewer than 512 before each read |
| JSON depth / structural punctuation | 32 / 50,000 |
| JSON string / schema string | 8192 / 1024 characters |
| Path depth / path length | 24 / 1024 characters |
| Source entries / set entries / controls | 128 / 256 / 32 |
| Command arguments | 256, each a nonempty bounded string |
| Jujutsu reader | 5 seconds and 1 MiB output per subprocess |
| Host clock reader | 3 seconds and 8192 bytes per subprocess |
| Validation checks | 120 seconds between stages; one bounded in-flight reader can add up to five seconds |
| Invocation duration / maximum age | 1800 / 3600 seconds, finite ordered epoch seconds |

The age bound is rechecked against monotonic elapsed time before success. Child reader processes use argument arrays, private process groups and bounded output. On failure their group is killed and the direct child is reaped. Escaped descendant processes and adversarial same-host process identity races are outside the cooperative reader model.

## Verification scope and residual obligations

The current test suite exercises 50 receipt/file/process cases plus six host-clock parser cases. Original permissive scaffold execution exposed 37 expected failures; the clock scaffold exposed five; a repeated-command-argument case exposed one overstrict guard before repair. Tests read genuine immutable Jujutsu source bytes, but all receipt producers and outputs are synthetic. No standalone mathematical model was added because it would not prove this parser, filesystem or process implementation correct. Full formal invocation evidence and independent review remain unrun for this validator.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Synchronized host observation recorded.
- [x] CHK-02-TAIL — Full Tailnet navigation links supplied; live rendering unverified.
- [x] CHK-03-FRACT — L0/L3 scope tagged; other layers are consumers, not implemented here.
- [x] CHK-04-KM — Specification and journal linked; no new ADR or EV minted.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [x] CHK-05-MUDA — Existing OCaml dependencies only; no new packages.
- [x] CHK-06-GRAPH — Native bounded reader; no new NIF or runtime role.
- [ ] CHK-07-DRIVE — Storage interlock execution UNRUN; no storage control change.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [x] CHK-08-C1C8 — Applicable parser, filesystem, timing and negative-control cases executed; full UI categories N/A.
- [ ] CHK-09-MATH — Formal refinement proof UNRUN; report-field checks confer no mathematical authority.
- [ ] CHK-10-9MOD — Fleet-wide nine modalities UNRUN.
- [ ] CHK-11-REGR — Live UI regression N/A to this read-only CLI.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Runtime supervision UNRUN; unchanged.
- [x] CHK-13-HERMES — Native OCaml bounded analysis; no scheduler authority.
- [ ] CHK-14-ZIGVM — Kernel execution UNRUN; unchanged.
- [ ] CHK-15-MAX — Inference execution UNRUN; unchanged.
- [ ] CHK-16-OTEL — Production telemetry UNRUN; CLI reports evidence identity only.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review pending; admission NOT_GRANTED.
- [x] CHK-18-JJ — Isolated Jujutsu workspace and canonical Sa-plan worker/attempt used.

</details>
<details><summary>Domain 6 — Provenance</summary>

- [x] Synthetic receipts cannot grant admission; actual candidate source equality is distinguished from producer authenticity.
- [x] EV-93 ceiling preserved; EV-94..109 remain subject to separate sovereign review.

</details>

UOS footer: consistency observation only; canonical execution authority remains Sa-plan.
