---
id: f01f820a-b222-86f3-6fdf-ae3d85837d21
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# Source-Backed Operational Catalogue and Living Ontology Traceability

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260904-150206-source-backed-operational-catalogue-and-living-ontology-traceability.md](http://nas-1.tail55d152.ts.net:4100/zk/20260904-150206-source-backed-operational-catalogue-and-living-ontology-traceability.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


# Source-Backed Operational Catalogue and Living Ontology Traceability

## 1. Zero-Muda Traceability Principle
Every architectural claim and operational capability in the Unified Operational System (UOS) must be bidirectionally traceable:
- **Top-Down Traceability**: From high-level STPA requirements (UCA-01..UCA-54) and formal specifications (Allium v3, Quint, Lean 4) down to exact lines of source code and AST nodes.
- **Bottom-Up Verification**: From low-level C-ABI NIF functions, dirty scheduler bindings, and SQLite WAL pages up to machine-checked proof certificates and passing test suites.

## 2. Eleven-Layer Census (L0 through L10)
The living ontology model classifies all system entities into 11 discrete fractal layers:
- `L0`: Physical host and external toolchain boundaries (Nix portable, Erlang OTP 27, OCaml 5.5.0 switch, GCC).
- `L1`: Authoritative persistent evidence artifacts (`evidence_store.sqlite`, `c3i_ocaml_nif.so`).
- `L2`: Core executing subsystems (CEPAF Gleam, OCaml bridge, ZigVM, Zenoh router, Sutra).
- `L3`: Version-controlled source code modules (`.c`, `.ml`, `.gleam`, `.zig`).
- `L4`: Features and exposed operational surfaces (MCP 36 tools, REST HTTP APIs, MoZ tools).
- `L5`: Data structures, working memory, and state models (Two-Lattice STM, RETE WM, Gospel ASTs).
- `L6`: Callable operations and STPA control actions (CA-1..CA-50, FFI wrappers).
- `L7`: Synthetic test generators and test corpus (`stpa_envelope`, `stpa_fmea_injector`, 9,767 tests).
- `L8`: Fault mitigations, mutation testing, and FMEA injection containment.
- `L9`: Automated formal judges and mathematical verification suites (Rocq, Quint, Lean 4, Gospel).
- `L10`: Zero-trust governance, production-rule gates, and immutable audit ledgers.

## 3. Mirror Synchronicity
To prevent drift, the entire design and audit trail is mirrored byte-for-byte with identical SHA-256 digests across all 5 workspace repositories:
- `NAS-setup/docs/design/`
- `NAS-setup/c3i/docs/design/`
- `NAS-setup/harness-bionic/docs/design/`
- `dev/ver/zigvm/docs/design/`
- `dev/ver/c3i/docs/design/`

#operational-catalogue #living-ontology #traceability #stpa #dal-a #zero-muda

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
