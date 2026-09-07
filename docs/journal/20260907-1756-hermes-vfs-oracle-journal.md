# 20260907-1756- Journal: Hermes OCaml Reference Oracle for the ZigVM File Primitive Algebra

`#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5` `#fractal-l6` `#fractal-l7` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#oracle` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-hermes-vfs-oracle-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-hermes-vfs-oracle-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Clock**: host `2026-09-07T18:24:42Z` (chrony stratum 3). **Sa-plan**: plan `uos/agentic-infra-checklist/20260907-1722`, task `t6-vfs-ocaml-oracle` (P2, score 324), preflight `PREFLIGHT_PASS` after one record repair (FMEA interval floor), worker `claude-fable-5.1-session-019m7SjJ`.  
**Source under specification**: `engines/zigvm/src/prim_file.zig` (669 lines, 22 public functions, 10 in-file tests). **Oracle**: `engines/hermes/modules/hermes_vfs_oracle/` (`vfs_oracle.mli`, `vfs_oracle.ml`, `test_vfs_oracle.ml`, `dune`).

## 1. Scope & Trigger
Operator asked whether `prim_file.zig` can be converted to OCaml, then said "continue". Decision recorded in the previous reply: not as a replacement (the VFS belongs to ZigVM by policy), but as a Hermes reference oracle under the ADD-04 homomorphism discipline. Scope: new Hermes module and tests; one executed row added to `tools/uos selfcheck-vfs`. ZigVM unchanged.

## 2. Pre-State Assessment
LAW-VFS-08 (path jail) was found not implemented in ZigVM by t3 and had no executable specification anywhere. Hermes declared `ctypes` and `ctypes.foreign` but no module used `Foreign.foreign`. No ZigVM binary or Zig toolchain is present on this host, so a live differential run was not possible.

## 3. Execution Detail
1. Mirrored the algebra: ten-constructor total error type and `error_of_unix` mapping (EXDEV and ELOOP, the `openat2` jail refusals, map to `Eacces`); modes; `file_info` with the Zig owner-write access rule; bounded `read_file` (`Too_large` above the cap); sorted `list_dir`; positioned `pread`/`pwrite`; `handle_size`, `truncate_handle` (any failure is `Ebadf`, as in Zig), `sync_handle`; `rename`, `make_dir`, `delete`, `delete_dir`; `read_link_info` (never follows) and `read_file_info`; `makedev`.
2. Bindings through `ctypes.foreign` with `check_errno`: `openat`, `openat2` via `syscall(437)` with an `open_how` struct and `RESOLVE_BENEATH`, `renameat`, `mkdirat`, `unlinkat`, `pread`, `pwrite`. No C stubs. `lstat`/`stat` come from `O_PATH` descriptors plus `Unix.fstat`, avoiding struct layouts. Directory listing enumerates through the descriptor.
3. Jail: every path opens beneath the root with `openat2(RESOLVE_BENEATH)`; mutating operations first open the parent directory beneath the root and act on the basename, so a symlinked parent cannot carry an effect outside. A normalized-`openat` fallback exists for kernels without `openat2` and reports itself; this host used the kernel-enforced strategy.
4. Tests: laws 01, 02, 03, 05, 07, 08 executed; 04 is static (library list); 06 is skipped with a printed reason (it is a sa-plan lease law, not a file primitive); plus positioned-I/O, append-at-size, stat projection, `makedev` and fd-identity checks. Output uses the sa-plan `ok LAW` shape.
5. Mutants: the `RESOLVE_BENEATH` flag was zeroed, and separately the read cap was multiplied by 1000; each was built and run, then the original restored, rebuilt and re-run (section 7). A first attempt at the second mutant removed the cap entirely and did not compile (unused variable is an error under this dune profile), which was caught and redone.
6. `tools/uos selfcheck-vfs` gained an executed row `ORACLE-SPEC` that runs the oracle suite (floor 12 ok lines).

## 4. Root Cause Analysis
Not a defect fix; the gap was the absence of an executable specification for the seam's laws, which let two ratification records mark an unimplemented law as PASS.

## 5. Fix Taxonomy
Evidence infrastructure (OCaml oracle plus tests) and a gate row. No runtime change.

## 6. Patterns & Anti-Patterns Discovered
Pattern: an oracle that implements the law the implementation lacks makes the differential disagreement the deliverable rather than a surprise. Pattern: `O_PATH` plus `fstat` gives `lstat` semantics without binding `struct stat`. Caveat recorded in code: `EXDEV` from a cross-device `renameat` would also map to `Eacces`; within one root that cannot occur.

## 7. Verification Matrix
| Check | Result |
|---|---|
| `dune build modules/hermes_vfs_oracle` | clean, first attempt |
| `dune build @modules/hermes_vfs_oracle/runtest` | 12 laws ok, 0 failed, 1 skipped with reason; jail strategy `openat2 RESOLVE_BENEATH` |
| Mutant: `resolve_beneath = 0x00` | killed: VFS-02 and VFS-08 report `not ok` (escape via symlink and via `..` both succeed), 10 ok, 2 failed |
| Mutant: read cap multiplied by 1000 | killed: VFS-07 reports `not ok` (the over-cap read returns content instead of `Too_large`), 11 ok, 1 failed |
| Restore | file byte-identical to the original; rebuilt; 12 ok |
| `tools/uos` tests | 31 passed, 0 failed |
| `tools/uos selfcheck-vfs` | 8/9 (FAIL by design): ORACLE-SPEC PASS with exit 0 and 12 ok lines; LAW-VFS-08 still `[UNRUN]` for ZigVM |
| Differential run against ZigVM | `UNRUN`: no Zig toolchain or built VM on this host |

## 8. Files Modified
| File | Change |
|---|---|
| `engines/hermes/modules/hermes_vfs_oracle/dune` | New |
| `engines/hermes/modules/hermes_vfs_oracle/vfs_oracle.mli` | New |
| `engines/hermes/modules/hermes_vfs_oracle/vfs_oracle.ml` | New |
| `engines/hermes/modules/hermes_vfs_oracle/test_vfs_oracle.ml` | New |
| `tools/uos/src/main.gleam`, `tools/uos/test/gate_verdict_test.gleam` | ORACLE-SPEC row |

## 9. Architectural Observations
The seam's algebra is small and total, which is why a faithful oracle fit in about 330 lines. The same bindings show what the Zig jail must do: `openat2` with `RESOLVE_BENEATH` for opens, and parent-beneath resolution for mutations. That is the specification the ZigVM task should implement.

## 10. Remaining Gaps
Implement the jail in `prim_file.zig`; build a ZigVM driver so the differential (same vectors, both sides) can run; cover `tzOffsetAt` (host TZif parsing) which the oracle does not model; annotate the nonconformant wiki and ADR-046 records in a new ZK note.

## 11. Metrics Summary
| Metric | Value |
|---|---|
| Functions mirrored | 22 of 22 |
| Laws executed / static / skipped | 6 / 1 / 1, plus 5 supporting checks |
| Mutants planted and killed | 2 |
| Oracle source | about 330 lines OCaml plus 60 lines interface |

## 12. STAMP & Constitutional Alignment
Hazard H-1: an oracle with wrong semantics would certify a defect. Controls: laws mirror the Zig doc-comments line by line, error mapping is total and tested, and two mutants were shown to be killed. The oracle is never linked into a runtime path (Hermes evidence stratum). No new dependency beyond libraries Hermes already declares. Work under a claimed sa-plan lease with a passing preflight; no Git inside UOS.

## 13. Conclusion
The file primitive algebra now has an executable specification in Hermes that passes all its laws, including the jail ZigVM lacks. The next ZigVM task has a precise target and a test to hit.

---
**Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) · **Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md) · **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md)  
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
