---
id: 14c8a3bc-2b87-76a0-e8bf-10f88f4de731
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# SIL-6 Zero-Trust RETE Gate Salience Hierarchy and Fail-Closed Emergency Precedence

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260904-150201-sil-6-zero-trust-rete-gate-salience-hierarchy-and-fail-closed-emergency-precedence.md](http://nas-1.tail55d152.ts.net:4100/zk/20260904-150201-sil-6-zero-trust-rete-gate-salience-hierarchy-and-fail-closed-emergency-precedence.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


# SIL-6 Zero-Trust RETE Gate Salience Hierarchy and Fail-Closed Emergency Precedence

## 1. Salience Hierarchy & Zero-Trust Discipline
The OCaml production-rules substrate (`c3i_ocaml_bridge.ml`) implements an immutable salience hierarchy governing all control actions:

```text
Salience 100: SIL6_EmergencyStop_Gate   -> Immediate fail-closed halt on e_stop=true
Salience  95: SIL6_Watchdog_Gate        -> Failsafe trigger on watchdog_alive=false
Salience  90: Cascade_Apoptosis_Gate    -> Controlled container cull on high_drift=true
Salience  85: Parity_Divergence_Gate    -> Rejection on OCaml/ZigVM parity breach
Salience  50: SC_Mesh_Running_Check     -> Precondition verification mesh_running=true
Salience  10: OODA_Nominal_Advisory     -> Diagnostic nominal active tag insertion
```

## 2. Fail-Closed Invariants
1. **Emergency Precedence**: Salience 100 rules evaluate before any other rule, overriding even missing secondary attributes. If `e_stop=true` is present, the gate rejects unconditionally.
2. **Typed Closed Fact Schema**: Every fact passed to `ocaml_rete_eval` is validated by `validate_rete_kvs`. Any unknown key or non-boolean value rejects with `FAIL_CLOSED: unknown_key` or `FAIL_CLOSED: invalid_value`.
3. **C-ABI Byte Safety**: Ingress binary strings are checked with `memchr(bin.data, 0, bin.size)` in `get_string_or_binary` in `c3i_ocaml_nif.c`. Embedded NUL characters cannot truncate payloads or mask emergency assertions.
4. **Multicore Domain Lock Safety**: In-process calls use `caml_c_thread_register()`, `caml_acquire_runtime_system()`, and pop local roots with `CAMLdrop` before releasing the domain lock, eliminating GC memory corruption.

## 3. Implementation Anchors
- OCaml Rules Substrate: `NAS-setup/c3i/lib/cepaf_gleam/native/ocaml_nif/c3i_ocaml_bridge.ml` (L215–L397)
- C-ABI Erlang NIF: `NAS-setup/c3i/lib/cepaf_gleam/native/ocaml_nif/c3i_ocaml_nif.c` (L55–L149)
- Gleam Safe Gateway: `NAS-setup/c3i/lib/cepaf_gleam/src/cepaf_gleam/c3i/ocaml_nif.gleam` (L51–L70)
- Test Regressions: `NAS-setup/c3i/lib/cepaf_gleam/test/c3i_ocaml_nif_test.gleam`

#rete #zero-trust #sil6 #salience #ocaml #fail-closed #safety-gate

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
