---
name: resource-preflight
description: Use when adding a resource check to a Hermes-harness operation (a capture, a comparison, a verify) that writes temp/disk, writes the evidence store, or reads the frozen reference — or when an operation could hit ENOSPC, a missing tool, or a read-only store mid-run and you want it to refuse up front instead.
---

# Resource Preflight

The evidence chain already refuses to record what it did not verify. A resource
preflight extends that discipline to resources: **nothing is consumed that was
not checked**, and a resource that is unknown or insufficient fails closed with
a fractal diagnostic — never a raw crash.

Use `Resource_envelope` (`modules/hermes_harness/resource_envelope.ml`). Do not roll a
new check; declare the operation's envelope and gate on it.

## Mandatory: this toolchain is OCaml, end to end

No Python — not in the check, not in a shell heredoc parsing `df`. Free space
comes from `df` invoked as a declared oracle (there is no `statvfs` binding);
its output is parsed and validated in OCaml. Adding an oracle means adding it to
`Ocaml_only_guard.permitted_external_tools` with its absent-case behaviour.

## The five properties that make a preflight real (not decoration)

A first-cut design almost always misses at least the first three. These are the
whole point:

1. **Split the pure decision from the IO.** `evaluate : resource -> observation
   -> check` is pure; `observe : resource -> observation` is the only thing that
   touches the world, and it **never raises**. This is what makes "fails closed
   under exhaustion" a unit test instead of a staged outage: exhaustion is an
   `observation` value you pass in.

2. **Fail closed on unknown.** If a resource's state cannot be determined — `df`
   errors, a path is absent, a query throws — the observation is `Unknown` and
   the check is **unmet**. Never assume "probably fine". `observe` catches every
   exception and returns `Unknown reason`.

3. **Margin AND an absolute floor.** A space check is met only when
   `available >= needed *. (1. +. margin)` **and** `available - needed >=
   floor_bytes` (512 MiB). The floor is not redundant with the margin: a
   percentage alone is satisfied by a large denominator while almost nothing is
   free — the tmpfs that motivated this failed at 99% full. The floor is the
   backstop the percentage is not.

4. **Classify the shortfall correctly (R5/R13).** A resource shortfall is
   `Blocks_credit`, never `Denies_credit`, and its origin is Environment
   (disk/temp/tool), Control (the store the harness must write), or Evidence (a
   moved reference) — **never Implementation**. A missing resource proves
   nothing about the candidate, so it can never touch parity credit. Each maps
   to an `HZ-RES-*` hazard, all with `realises_h1 = false`.

5. **Check cheaply; don't duplicate the digest.** `Frozen_reference` is a
   presence-and-non-empty gate, not a re-digest — `Inventory` does the
   cryptographic pin. A preflight that is slow won't be run.

## Declaring an envelope and gating an operation

```ocaml
let envelope =
  Resource_envelope.
    [ Frozen_reference { root = reference_root };
      Disk_space { path = root; bytes_needed = 64 * 1024 * 1024; margin = default_margin };
      Temp_space { bytes_needed = 32 * 1024 * 1024; margin = default_margin };
      Writable state_directory ]
in
let checks = Resource_envelope.preflight envelope in
if not (Resource_envelope.satisfied checks) then begin
  Printf.eprintf "preflight refused: %d of %d resources unavailable\n\n"
    (List.length (Resource_envelope.unmet_checks checks)) (List.length checks);
  List.iter (fun d -> prerr_endline (Fractal_diagnostic.render d))
    (Resource_envelope.to_diagnostics checks);
  exit 1
end;
Printf.printf "preflight: %d resources satisfied\n" (List.length checks);
(* ... the operation, only now ... *)
```

Gate **before** the operation touches anything — before it scans the reference,
opens the store, or spawns a capture. `modules/hermes_harness/compare_reference_traces.ml` is the
worked reference.

## Quick reference — which resource

| Resource | Use for | Origin when unmet | Hazard |
|---|---|---|---|
| `Temp_space` | an op that writes transient trees ($TMPDIR/​/tmp) | Environment | HZ-RES-TEMP |
| `Disk_space {path}` | fixtures, the evidence DB, `_build` on the project disk | Environment | HZ-RES-DISK |
| `Binary {name; env_var}` | an oracle the op needs (interpreter, gospel, z3) | Environment | HZ-RES-BIN |
| `Writable path` | the evidence store / a dir receipts are written to | Control | HZ-RES-DB |
| `Frozen_reference {root}` | the snapshot the op measures against | Evidence | HZ-RES-REF |

Don't add a resource nothing consumes. A file-descriptor check for a sequential
operation is theatre — `ulimit -n` is huge and there's nothing to exhaust. Add
it when real fan-out exists, and `log` what a bounded check skipped.

## Testing (R7) — the chaos layer is the proof

Unit-test `evaluate` at the exact margin and floor byte-boundaries (met at
`needed*(1+margin)`; unmet one byte under; met at `needed + floor`; unmet one
byte under the floor). The **chaos layer must drive the real environment**: an
impossible need on the real disk yields Blocked, a missing path and a read-only
dir fail closed rather than crash. A check you cannot make fail in a test is a
check nobody has confirmed works. See `test_resource_envelope.ml` (92 checks).

## An honest limit: advisory, not a guarantee

Space can vanish between the check and the write (TOCTOU), and the temp
filesystem is shared. The preflight catches the *standing* condition — "already
near-full when we start" — and turns a silent mid-write ENOSPC into a loud
refusal with a cause. It does **not** replace correct error handling on the
write path: the incident that motivated it was ENOSPC surfacing as a lost
command result, and that propagation bug must be fixed regardless. The margin
and floor absorb the race; they do not eliminate it.

## Common mistakes

- **Percentage margin, no floor.** Passes at 99% full. Add the absolute floor.
- **Assuming availability when the query fails.** `df` erroring must be
  `Unknown` → unmet, not "proceed".
- **Letting `observe` raise.** Then the operation crashes instead of refusing.
  Catch everything; return `Unknown`.
- **Marking a shortfall `Denies_credit` / Implementation.** That records a
  resource gap as a candidate defect — the exact confusion R5 forbids.
- **Re-digesting the frozen reference in the preflight.** Slow; that's
  `Inventory`'s job. Presence only.

## Cross-references

- Rule **R13** (`docs/hermes/mandatory-rules.md`): resources checked before use.
- **R5**: only Implementation origin may deny credit.
- `Fractal_countermeasures`: the response to each `HZ-RES-*` (automatic only
  when it cannot itself cause harm — e.g. redirect `TMPDIR`; never auto-delete).
- Design + status: `docs/hermes/specs/2026-08-08-fractal-resource-envelope-preflight.md`.
