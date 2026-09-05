# zigvm

**A BEAM (Erlang/OTP) virtual machine written in Zig, built end-to-end with Algebra-Driven Design.**

zigvm is an implementation of the Erlang/OTP virtual machine — terms, garbage collection, bytecode loading, instruction dispatch, BIFs, bit-syntax, the external term format, ETS, and more — where **correctness is a proof obligation, not an aspiration**. Every subsystem is specified as an *algebra* (a signature, a set of laws, and a semantic domain), implemented twice, and glued by property tests at every representation boundary.

The VM is pure Zig under [`src/`](src/); an OCaml verification-and-conformance harness lives under [`harness/`](harness/).

---

## The idea

A virtual machine is a stack of **representation changes**, each of which must preserve meaning:

```
terms → tagged words → GC-relocated words → serialized bytes
programs → bytecode → dispatched execution
```

So correctness is expressed as **one semantic domain per subsystem** plus a **homomorphism law at every boundary**. Each subsystem is built in the Algebra-Driven Design style:

- an **oracle** encoding — obviously correct, initial, slow;
- a **final** encoding — efficient, the one that actually runs;
- **twin-seeded homomorphism property tests** proving the two agree observationally.

Concretely: copying GC is specified entirely by `denote(after) == denote(before)`; threaded dispatch is admitted only by *differential equality* against the interpreter; a bitstring is a bit-vector whose packed and boolean-slice encodings must slice bit-for-bit identically. Laws are named after the algebraic property they assert — homomorphism, monoid, round-trip, total order, idempotence, rejection — and observe **behaviour, never pointer identity**.

Every module's doc-comment *is* its specification: signature, semantic domain, oracle/final encodings, laws, and scope limits, in that shape.

---

## Status

The 14 foundational milestones are complete. The active program is **[`OTP30_PARITY_PLAN.md`](OTP30_PARITY_PLAN.md)** — epoch series E0–E9 driving toward full functional, performance, and scalability equivalence with a pinned **OTP 30-rc** release, governed by a conformance protocol (totality ledgers, differential corpora, ratcheted baselines).

| | State |
|---|---|
| **Law suite** | 329 property/law tests, green (`All N tests passed.`, exit 0) |
| **Opcode ledger** | 126 EQ · 65 justified · **0 UNTESTED** / 191 — 100% classified |
| **BIF ledger** | 182 EQ · 371 justified · **0 UNTESTED** / 553 — 100% classified |
| **Epoch E1** (ISA totality) | ✅ complete |
| **Epoch E2** (BIF/NIF totality) | ✅ complete — bif ledger 100% classified, baseline accepted |
| **Epoch E3** (runtime semantics) | 🚧 in progress — Phase A (bitstrings: term kind, ETF `BIT_BINARY_EXT`, bit-syntax match + construct) complete |

*Classified* means every opcode and BIF the pinned runtime knows is either **implemented and proven equivalent (EQ)** or **explicitly deferred with a bounding justification (EQUIV)** — never silently missing. Deferrals are epoch-charter-bounded and audited in [`DIVERGENCE_LOG.md`](DIVERGENCE_LOG.md).

---

## Build & verify

Prerequisites: opam and the externally supplied Zig 0.16 toolchain.

```sh
# Create the exact compiler switch and seed the Bos-based OCaml bootstrap.
opam switch create . ocaml-base-compiler.5.5.0
opam install bos.0.3.0

# Reproduce patched pins, every project PPX, development tools, and libraries.
scripts/setup_ocaml_550.ml --install
scripts/setup_ocaml_550.ml --check
```

Set `ZIGVM_ZIG` to the Zig 0.16 executable when it is not already on `PATH`.
No Python or shell bootstrap script is part of the repository.

The **canonical verification gate** — the single accepted completion evidence — runs the language-boundary checks, artifact inventory, doc checks, fixture-mirror checks, and the full Zig law suite:

```sh
opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD"
```

A green run prints `All N tests passed.`, exits 0, and logs state/events/artifacts to SQLite at `harness/state/zigvm_harness.sqlite3`.

Useful partial modes: `--check-only` (skip the Zig suite), `--check-docs`, `--check-fixtures`, `--verify-otp --gen-ledgers` (regenerate the conformance ledgers), `--run-erl-corpus` (differential Erlang corpus), `--conformance` (end-to-end conformance run).

The OCaml 5.5 web stack uses the tracked Bonsai/Bonsai_web/Virtual_dom preview
and Dream `dev`. Build and run the read-only operations UI with:

```sh
opam exec -- dune build harness/ui_web/main.bc.js harness/zigvm_web.exe
ZIGVM_DREAM_PORT=8090 opam exec -- dune exec ./harness/zigvm_web.exe
```

Open `http://127.0.0.1:8090/bonsai`. Dream reads the ledger only through the
OCaml harness `Db` actor; no browser or external database client is involved.

Browser automation and responsive verification are direct OCaml only. Generate
the complete protocol ontology, run its binding-totality laws, and exercise the
mobile-first viewport matrix with:

```sh
opam exec -- dune exec ./harness/zigvm_playwright_ontology.exe
opam exec -- dune exec ./harness/test_playwright_controller.exe
opam exec -- dune exec ./harness/zigvm_playwright.exe -- \
  --url http://127.0.0.1:8090/bonsai \
  --engine chromium \
  --executable /path/to/chromium \
  --artifacts /tmp/zigvm-playwright
```

The controller, driver acquisition, process supervision, protocol operations,
observations, OODA verdicts, and teardown are authored in OCaml. The Node
driver and browser are external Playwright runtime dependencies; no project
shell, Python, JavaScript, TypeScript, or Playwright CLI controller is used.
The same ontology command also inventories the complete pinned Microsoft
Playwright v1.59.0 source/docs checkout: 3,089 artifacts, 231 documentation
assets, and 41 package manifests. `scripts/setup_ocaml_550.ml --install`
reconstructs that source-only checkout and `--check` verifies its Git tree.

---

## Architecture

[`ARCHITECTURE.md`](ARCHITECTURE.md) explains the design in full; [`CODEBASE_MAP.md`](CODEBASE_MAP.md) maps the erts source surface onto subsystems S1–S33. The code is organised in three strata:

- **Stratum A — algebraic core.** Pure, law-governed domains (terms, maps, binaries, bitstrings, hashing, patterns, instructions, ETS, match specs) get the full oracle + final + homomorphism treatment.
- **Stratum B — engines.** Schedulers, GC machinery, dispatch, loaders, ports — verified *against* Stratum A by trace/differential equivalence.
- **Stratum C — substrate.** Allocators and OS glue — quarantined; no Stratum-A law may depend on it.

31 Zig modules (~23.6k lines) aggregate through [`src/vm_all.zig`](src/vm_all.zig), which pulls every module's tests. The dependency spine runs terms → maps/binaries/hashing → patterns/mailbox → instructions → processes/scheduling/GC → loading/dispatch/distribution.

### Boundaries (mechanically enforced by the gate)

- `src/` is **Zig-only**; the only non-Zig files are embedded fixtures.
- `harness/` is **OCaml-only**, built with Dune, packaged with opam; runtime state lives only under `harness/state/` as SQLite.
- The harness may *execute* the Zig toolchain but never reimplements VM semantics outside Zig.

---

## Repository map

| Path | What it is |
|---|---|
| [`src/`](src/) | The VM — pure Zig, one module per subsystem, each doc-comment a spec |
| [`harness/`](harness/) | OCaml verification + conformance harness (the gate lives here) |
| [`docs/PLAYWRIGHT_OCAML_ONTOLOGY.md`](docs/PLAYWRIGHT_OCAML_ONTOLOGY.md) | Complete direct-OCaml Playwright control, data-flow, runtime, and verification ontology |
| [`fixtures/`](fixtures/) | Vendored `.beam`/`.bin` test vectors + Erlang corpus/printer fixtures |
| [`OTP30_PARITY_PLAN.md`](OTP30_PARITY_PLAN.md) | The active program: epochs E0–E9 toward OTP 30-rc parity |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) · [`CODEBASE_MAP.md`](CODEBASE_MAP.md) | Design + subsystem map |
| [`DIVERGENCE_LOG.md`](DIVERGENCE_LOG.md) | The audited ledger of intentional, bounded divergences from OTP |
| [`AGENTS.md`](AGENTS.md) · [`CLAUDE.md`](CLAUDE.md) | The binding rulebook and working conventions |
| [`SAFETY_ANALYSIS.md`](SAFETY_ANALYSIS.md) · [`SDLC_SRE_PROCESS.md`](SDLC_SRE_PROCESS.md) | STPA/UCA/FMEA safety constraints and lifecycle process |

---

## The working loop

Every behavioural change follows the same mandatory loop (see [`AGENTS.md`](AGENTS.md) and the `algebraic-fractal-structures` skill):

1. Write the **semantic domain** before code; identify the oracle and final encodings.
2. Name **laws** after algebraic properties; observational equality only.
3. Seeded generators that echo their seed on failure; bounded drivers (a hang is a failed law); exhaustive switches; explicit heap ownership; zero leaks (proven by `std.testing.allocator`).
4. Plant **≥2 mutants** per landed change and record them in `MUTATION_LOG.md` (kill, or justify as equivalent).
5. Sync the docs; finish with a **green gate**.

The result is a VM where the tests don't merely exercise the code — they *pin the meaning* of every representation, and the meaning is preserved by construction.

---

*Built with [Claude Code](https://claude.com/claude-code).*
