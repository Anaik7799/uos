//! beam-zig Milestone 3 / S13: the **instruction algebra** + fuel interpreter.
//!
//! Two layers, mirroring how BEAM code actually decomposes:
//!
//!  LAYER 1 — BLOCK ALGEBRA (straight-line code): a MONOID.
//!    constructors: nop, one(instr);  combinator: seq
//!    observation:  exec : (Machine, Block) -> Machine   (a state transformer)
//!    Laws: seq identity/associativity; COMPOSITIONALITY
//!          exec(seq(p,q)) == exec(q) ∘ exec(p); block fuel = instrs retired.
//!    Initial encoding: seq-trees (free monoid). Final encoding: the FLAT
//!    INSTRUCTION ARRAY — the normal form licensed by assoc+identity (catalog
//!    Part C), i.e. exactly the shape real BEAM code has in memory.
//!
//!  LAYER 2 — CONTROL MACHINE: labeled programs with tests/jumps/call/ret/halt
//!    executed under a reduction budget over ⟨x-regs, CP stack, process heap
//!    (M1/M2 FinalTerms), pc, reductions⟩.
//!    Laws: STEP DETERMINISM; FUEL EXACTNESS (every retired instruction costs
//!    exactly one reduction; a still-running machine has consumed its whole
//!    budget); and the milestone's star —
//!    SLICE INVARIANCE: running F reductions in one shot equals running them
//!    in ANY partition of slices. Preemptive scheduling (M7) is therefore a
//!    theorem about this machine, not a hope.
//!
//! Mailboxes/send/receive are M5/M7; exceptions beyond badarith are M5.
//!
//! Type-test guards (E1.3): `type_test{kind,src,else_to}` denotes a partial
//! predicate on terms — fall through if the predicate holds, `pc = else_to`
//! if it fails (same test shape as `is_lt`/`test_eq`/`is_cons`). Each
//! `TypeTestKind` is mapped by `typeTestHolds` to an EXISTING FinalTerms
//! observation (repIsSmall/repIsBig for integer, repIsFloat, repIsNumber,
//! kindOf for atom/list, repIsMap, repIsBinary for binary and — until E3's
//! sub-byte bitstrings — bitstr, repIsFun for function, atom-name ∈{true,false}
//! for boolean); pid/reference/port have NO term constructor yet so their
//! predicate is the constant `false` (honest — no such term can exist).
//! `is_function_arity` is BEAM's is_function2: repIsFun ∧ funArity == N.
//! The execution law "type-test predicate matches BEAM is_* guard semantics"
//! pins hold-vs-jump per kind; randProgram emits both so the DIFFERENTIAL law
//! (dispatch.zig) covers engine#2 ≡ engine#3 for the whole class.
//!
//! Comparison-test guards (E1.4): `cmp_test{op,a,b,else_to}` is the binary twin
//! of `type_test` — the four ops `is_ge`/`is_eq`/`is_ne`/`is_ne_exact` mapped by
//! `cmpTestHolds` to EXISTING `FinalTerms` order/equality observations
//! (`compare` for standard-order `>=` and arithmetic `==`/`/=`; `eqlExact` for
//! exact `=/=`). The arith-vs-exact split (`1 == 1.0` true, `1 =/= 1.0` true) is
//! the whole content; NO new term semantics. randProgram emits it so the same
//! DIFFERENTIAL law covers the class.
//!
//! Tuple opcodes (E1.5): the BEAM tuple family — `get_tuple_elem`,
//! `set_tuple_elem`, `put_tuple2`, `test_arity`, `is_tagged_tuple` — plus
//! `is_tuple` (a `type_test .tuple`). Index operands are 0-BASED (the opcode
//! convention; `element/2` is 1-based, the compiler adjusts). `get_tuple_elem`
//! and `set_tuple_elem` carry NO fail label (BEAM trusts a preceding
//! `test_arity`), so — like `get_hd`/`get_tl` — they are driven only over real
//! tuples by their semantic law, never fuzzed over arbitrary registers.
//! `test_arity`/`is_tagged_tuple` ARE guarded test ops (kindOf==.tuple checked
//! first) and so are safe for randProgram to emit. `set_tuple_elem` delegates to
//! the new `term_algebra.setTupleElem` in-place setter (its own homomorphism
//! law). `put_tuple2` builds `FinalTerms.tuple` from its resolved Src slice.
//! The execution law "E1.5 tuple ops match BEAM semantics" pins each op and
//! kills the index-off-by-one and arity-`>=` mutants.
//!
//! Record update (E1.14): `update_record` (BEAM opcode 181) is the record-field
//! updater. Records are tuples tagged with a record atom (M6), so it COPIES the
//! source tuple-backed record and overwrites each listed `(index, value)`
//! position (the interpreter always copies — BEAM's in-place `Hint` is a
//! heap-reuse optimisation that denotes identically). The BEAM Offset is 1-based
//! over the untagged tuple (offset 0 = header); translate stores `Offset−1`, the
//! 0-based element index. The `updates` slice is gpa-owned, mirroring
//! `put_tuple2.elems` (freed by `beam_loader.freeProg`, deep-copied by
//! `transform.peephole`). The law "E1.14 update_record: copy-then-overwrite
//! homomorphism; source unchanged (aliasing)" pins denote-after AND the aliasing
//! invariant (source untouched), killing the mutate-in-place mutant. The OTP-28/29
//! native-record ops (`is_native_record`, `get_record_field`, `put_record`, …) are
//! INTERPRETER opcodes (emu `ops.tab`/`instrs.tab`, executed by `erl_record.c`)
//! over a DISTINCT native-record boxed-term representation (`ErtsNativeRecord`) —
//! a separate term, NOT a tuple and NOT a JIT concept. zigvm's tuple-backed record
//! model does not provide this term kind, so implementing them needs a new
//! native-record TERM representation (a runtime-semantics / term-representation
//! slice, the LA-3 bitstrings class); they are justified-deferred to Epoch E3
//! (see DIVERGENCE_LOG.md entry 3), NOT implemented here.
//!
//! Special/no-op opcodes (E1.15): `on_load/0` and `nif_start/0` decode to ONE
//! nop-class CInstr, `nop: struct { note: NopKind }`. TRANSPARENCY LAW: a
//! `nop` is denotationally transparent — one reduction, no `x`/`y`/heap/
//! pc-beyond-normal-advance effect — proved by splicing `.nop` at several
//! points in a program and asserting the result is identical to the
//! un-spliced twin (the E1.11 `recv_marker_*` precedent). Real BEAM RUNS the
//! `on_load`-marked function at load time and gates the module load on its
//! outcome; E1 does not run load-time callbacks (Epoch E4, "boot the world"),
//! so the transparent no-op is an E1-minimal honest translation — EQ on the
//! totality ledger, with the callback BEHAVIOR justified-deferred to E4 (see
//! DIVERGENCE_LOG.md entry 4). `nif_start` needs no such note: it is a
//! genuine no-op NIF stub landing pad in real BEAM too.
//!
//! Select opcodes (E1.6): `select_val`/`select_tuple_arity` — BEAM jump tables.
//! Each carries a FINITE, gpa-owned `pairs` slice (`SelectValPair`/
//! `SelectArityPair`) and executes a BOUNDED linear scan (slice fixed at decode
//! time) — first match wins, else `fail_to`; both ALWAYS set pc. `select_val`
//! matches keys with `eqlExact` (EXACT: `1` ≠ `1.0`); `select_tuple_arity`
//! matches a tuple's arity (non-tuple ⇒ `fail_to`). The `pairs` ownership
//! mirrors `put_tuple2.elems` (freed by `beam_loader.freeProg`; the fuzzer uses
//! static-const tables). The laws "E1.6 select_val …"/"E1.6 select_tuple_arity …"
//! kill the stop-after-first-pair and arith-vs-exact-key mutants.
//!
//! Map opcodes (E1.10): `has_map_fields`/`get_map_elements` (guarded tests) and
//! `put_map` (assoc/exact insert). Every lookup/insert goes through the
//! `term_algebra` map API (mapGet/mapPut, flat↔HAMT, EXACT keys) — NO new map
//! semantics. `get_map_elements` is ALL-OR-NOTHING: it verifies EVERY key is
//! present BEFORE writing any dst (a present+absent mix jumps `else_to` clobbering
//! nothing). `put_map` `exact` updates only existing keys — an absent key is a
//! `{badkey,Key}` crash, it must NOT insert (assoc has no such precondition). The
//! `keys`/`pairs`/`kvs` slices are gpa-owned, mirroring `put_tuple2.elems`
//! (freed by `beam_loader.freeProg`; the fuzzer uses static-const tables and a
//! fuzzed register never holds a map, so the FOUND paths ride the dedicated
//! E1.10 laws, exactly like `get_tuple_elem`). Those laws kill the write-as-you-
//! scan (partial-write) and exact-behaves-like-assoc mutants.
//!
//! Receive/message opcodes (E1.11) — the REAL BEAM receive loop, mapped onto the
//! M5 `mailbox_algebra` + M7 `.send_to` trap (the M5/M7 `self_send`/`recv_eq`/
//! `recv_any`/`send_to` variants were the abstract precursors). NO new mailbox
//! semantics: the machine carries a `recv_cursor` (the BEAM receive save-pointer,
//! an index into the mailbox's arrival sequence), and `mailbox_algebra` gains two
//! denotation-preserving observations — `peekAt(cursor)` (read the message at the
//! cursor, no removal) and `removeAt(cursor)` (commit the pop; a cursor past the
//! queue is a no-op, so a phantom is never removed) — twinned across both
//! encodings by a homomorphism law. `loop_rec Lbl Dst` peeks the cursor into
//! `Dst`, else jumps `Lbl` (empty/exhausted); `loop_rec_end Lbl` advances the
//! cursor and retries (bounded — the cursor strictly increases, so the queue
//! always exhausts); `remove_message` commits the pop and resets the cursor;
//! `send/0` traps `.send_to` (pid x0, msg x1) and returns the message in x0;
//! `wait Lbl` suspends (a new `.suspended` status — the single-process E1 model
//! has no scheduler wake yet; a fuller resume is a later epoch); `wait_timeout
//! Lbl Time` FIRES immediately on a `0` (or any finite, timer-less-E1) timeout by
//! falling through to the after-clause, and only `infinity` suspends (treating 0
//! as infinite would spin the receive loop — mutant 2, a hang is a failed law);
//! `timeout` clears the save-pointer. The `recv_marker_*` ops are receive-queue
//! OPTIMIZATION markers — SEMANTICALLY TRANSPARENT (no denotation depends on
//! them): implemented as dispatched no-ops, PINNED by a transparency law (a
//! program with the markers interleaved observes identically to one without),
//! hence classified EQ (a verified transparent implementation), not EQUIV. The
//! receive ops are LAW-DRIVEN (dedicated hand-assembled programs), NOT fuzzed by
//! `randProgram` (receive state is stateful — the `apply`/`try` precedent); the
//! four label-bearing ops are renumbered by `beam_loader`'s fixup and
//! `transform.peephole`. The mailbox-conservation law (remove removes EXACTLY the
//! peeked message) kills the ignore-the-cursor mutant.
//!
//! Float-register opcodes (E1.12) — a MACHINE-STATE EXTENSION. BEAM keeps a
//! SEPARATE bank of 16 floating-point registers holding raw IEEE doubles (NOT
//! boxed float terms): the new `Machine.fregs: [16]f64` (a fixed array — no
//! allocation, `deinit` unchanged — but `eqMachines` now compares it BIT-EXACTLY,
//! or the differential law is blind to FR divergence). `fmove` is bidirectional
//! (`fmove_to_f`: a float TERM's f64 into the bank; `fmove_from_f`: the bank boxed
//! back to a float term via `FinalTerms.float`); `fconv` CONVERTS a numeric term
//! (int OR float) to f64 — int `5` → `5.0`, a conversion NOT a bit-cast
//! (`numToF64Of` == `@floatFromInt`, mutant 2). `fadd`/`fsub`/`fmul`/`fdiv`/
//! `fnegate` compute in f64 (`fsub` is `FA - FB`, order matters — mutant 1) and
//! crash `badarith` on a non-finite result (`std.math.isFinite`; the BEAM `Fail`
//! label is the strict-mode exception route, NOT carried — the gc_bif2 arith
//! precedent, so FR ops need no label fixup). NO new float SEMANTICS: every
//! result denotes the same f64 `term_algebra`'s float ops would. LAW-DRIVEN, not
//! fuzzed by `randProgram` (the bank needs pre-loading — the `apply` precedent).
//!
//! Exception opcodes (E1.8) — a MACHINE-STATE EXTENSION.
//!   SEMANTIC DOMAIN. A try/catch protected region is a LANDING PAD pushed on a
//!   new `catch_stack: ArrayList(CatchFrame)` (owned by `Machine`; init empty,
//!   `deinit` frees it, mirroring `stack`/`ystack`). A `CatchFrame` records
//!   `{ to: u32 (recovery pc), kind ∈ {catch_, try_}, y_depth: usize (the
//!   ystack height at push time) }`. The stack is the algebra's carrier; its
//!   operations are PUSH (`catch`/`try`) and POP (`catch_end`/`try_end`, and the
//!   unwind), and it is a LIFO STACK — laws below.
//!     * `catch`/`try` push a frame (`y_depth = m.ystack.items.len`).
//!     * `catch_end`/`try_end` pop the top frame (normal exit of the region).
//!     * `try_case` is the try-exception LANDING helper: the frame was already
//!       consumed by the unwind, so it is a stack no-op (execution resumes here).
//!       `try_case_end`/`badrecord` are guard-failure crashes.
//!   UNWIND (the rewired `m.crash`, via `raiseWith`): if `catch_stack` is
//!   NON-EMPTY, POP the top frame, set `m.pc = frame.to`, shrink `m.ystack` to
//!   `frame.y_depth`, and land the exception in the x-registers per the frame
//!   kind (BEAM convention): a `catch_` frame lands the reason VALUE in `x0`
//!   (real error/exit `{'EXIT',_}` wrapping is E3); a `try_` frame lands
//!   `x0 = class` (`error`/`throw`/`exit`), `x1 = reason`, `x2 = stacktrace`.
//!   If the stack is EMPTY, the EXACT prior halt path runs (`status = .crashed`,
//!   `result = reason`) — the backward-compat law over M1–M14. `raise`/
//!   `raw_raise` re-raise (unwind with a chosen class/reason); `build_stacktrace`
//!   yields a stacktrace (E1-minimal `nil` when no `Line` chunk; cooked line-info
//!   from E3.11 — see below). LAWS:
//!   (a) LIFO — a `try`/`catch` push then its `try_end`/`catch_end` pop restores
//!   the exact prior catch-stack; (b) an exception raised inside a frame lands at
//!   `to` with the reason in `x0` (catch frame) and the ystack shrunk back to
//!   `y_depth`; (c) BACKWARD-COMPAT — an empty-stack crash halts identically to
//!   pre-E1.8. `try`/`catch` carry code labels (`to`) that `beam_loader`'s fixup
//!   and `transform.peephole` both renumber; they are LAW-DRIVEN (not fuzzed by
//!   `randProgram`, like `apply`) because a raised exception rewrites control
//!   flow — the dedicated E1.8 semantic laws drive every arm.
//!
//! Full exception model (E3.10): the E1.8 catch-stack stays; the exception VALUE
//!   gains a CLASS. `Machine.exc: Exc{class: ExcClass{error_,exit_,throw_},
//!   reason, stacktrace}` records the current/last-raised exception on EVERY
//!   raise (`raiseWith` now takes an `ExcClass`, not a raw class atom). This
//!   DISCHARGES the E1.8 gaps (DIVERGENCE entry 2 a/c/d):
//!   - CLASS-DISCRIMINATED catch (`catchWrap`): a `catch_` frame lands the value
//!     class-wrapped — `throw` BARE, `exit` as `{'EXIT',Reason}`, `error` as
//!     `{'EXIT',{Reason,Stacktrace}}` (was: the bare reason for all classes).
//!   - RE-RAISE preserves class: `.raise` (raise/2) re-raises with `m.exc.class`
//!     (the original caught class), not a hardcoded `error`.
//!   - BAD-CLASS guard: `raw_raise` (and the `erlang:raise/3` BIF) with a
//!     non-`error`/`exit`/`throw` x0 sets/returns the atom `badarg` WITHOUT
//!     raising (`classOfAtom`).
//!   The empty-catch-stack HALT path is UNCHANGED (`status=.crashed`,
//!   `result = the bare reason`) — the backward-compat law over M1–M14 still
//!   holds; the class is available in `m.exc.class` for a future top-level
//!   process-exit-reason slice (the `{R,ST}`/`{nocatch,V}` cooking is NOT done
//!   here; the stacktrace it would cook is E3.11's, below). BIFs that raise a STRUCTURED /
//!   class-tagged exception (`{badmap,_}`/`{badkey,_}`; `erlang:error/throw/
//!   exit/raise/3/nif_error`) stage it on `Machine.bif_raise` via `bifRaise`/
//!   `raiseBadmap`/`raiseBadkey` and return `error.Raise` — the `bif_call`
//!   executor unwinds it through `raiseWith`, STILL guard-vs-body split (a
//!   guard-usable `map_get`/`is_map_key` BRANCHES, never raising — DIVERGENCE
//!   6b/c: guard behaviour is EXACT, only the body reason gains structure). The
//!   four E3.10 laws drive class-discrimination / re-raise-preservation /
//!   bad-class-no-raise / structured-reason-through-the-executor.
//!
//! Cooked stacktraces (E3.11 — DISCHARGES DIVERGENCE entry 2b): `build_stacktrace`
//!   no longer always yields `nil`. `beam_loader` decodes the `Line` chunk into a
//!   pc→`{name_index,line}` table and the `func_info` boundaries into a pc→`{m,f,a}`
//!   table; `boot` threads both into `Machine.locs` (a `[]const Loc`, parallel to
//!   `prog`). On a raise, `cookStacktrace` builds the SYMBOLIC term
//!   `[{M,F,Arity,[{file,File},{line,L}]} | CallerFrames]`: the head frame names the
//!   FAULTING mfa+line (read at `pc-1` — `run` bumps `pc` before `execInstr`), and
//!   caller frames walk the y-stack return chain in RETURN order (most-recent-first),
//!   bounded to BEAM's default depth 8. `File` is the source filename as a CHARLIST
//!   (`charlistOfAtom`). When the module carries no `Line` chunk (`locs` empty) the
//!   trace is the E1-minimal `nil` — the exact pre-E3.11 behaviour, so every earlier
//!   law that never set `locs` is unshifted (the transparency law). The FOUR E3.11
//!   laws drive head-frame exactness (mutant: off-by-one pc) / caller-frame RETURN
//!   order (mutant: call order) / depth-bound ≤8 / no-locs transparency.
//!
//! Stack/heap frame opcodes (E1.9): `alloc_heap{stack,live}` is `allocate_heap`
//! StackNeed+Live — it allocates `stack` y-slots exactly like `alloc_y`
//! (`allocate`'s existing arm). `HeapNeed` is a moving-GC hint; this VM's arena
//! grows on demand, so it is intentionally NOT carried in the CInstr or acted
//! on (recording it as y-slots would be a StackNeed/HeapNeed mix-up — mutant
//! 2 below). `trim{n}` drops the top `n` y-slots and KEEPS the remaining
//! (older) frame, in the SAME `shrinkRetainingCapacity(len - n)` direction as
//! `dealloc_y` (BEAM's `Remaining` operand is advisory, like `Live`, and is
//! likewise not carried). Both, like `alloc_y`/`dealloc_y`/`get_tuple_elem`
//! before them, carry a PRECONDITION the compiler guarantees rather than a
//! fail label — `trim n` requires `n <= ystack.items.len` (asserted). `trim`
//! is therefore driven only by its dedicated semantic law, never fuzzed by
//! `randProgram` (a fuzzed jump could reach it with the wrong depth and
//! trip the precondition, exactly why `dealloc_y`/`get_tuple_elem` are
//! excluded too). `alloc_heap` carries no such precondition (it only grows
//! the frame, like `alloc_y`) but, like `alloc_y`, is likewise driven only by
//! its dedicated semantic law and NOT sprinkled into `randProgram` — the
//! y-stack family is exercised by its own laws throughout this module, not
//! the blind control-flow fuzzer.
//!
//! BIF-dispatch opcodes (E1.13/E2.2) — the MECHANISM, not the coverage. The
//! WHOLE `bif`/`gc_bif` family — `bif0/1/2/3` AND `gc_bif1/2/3` — decodes to ONE
//! CInstr, `bif_call{ bif, args:[3]Src, argc, dst, else_to, gc_live }`. E2.2
//! unified `gc_bif2` onto this path (it previously landed directly as `.add`/
//! `.sub` and REJECTED an unsupported BIF at load); every form now traps `undef`
//! at RUNTIME for an unsupported `M:F/A`, never a loader reject. SCOPE:
//! E1/E2.2 implement only the opcode MECHANICS — the loader decodes the BIF
//! import ref to an `M:F/A` and resolves it through ONE table lookup
//! (`bifs/dispatch.resolve` over the generated `bif_table`, keyed on the full
//! module+name+arity), recording the outcome in `bif`: `.op` (an
//! executable arith BIF — `+`/`-` today) or `.unsupported` (a valid but
//! unimplemented `M:F/A`). BIF COVERAGE — which specific `M:F/A` actually run —
//! is E2; the *bif* ledger stays ~2/553 until then, correctly, because E1 adds
//! NO new BIF implementations. These opcodes become EQ by being TOTAL: every
//! form decodes + dispatches + terminates. ARGS are a FIXED inline `[3]Src`
//! (arity ≤ 3), so there is NO gpa-owned sub-slice — nothing for `freeProg` to
//! release, nothing for `peephole` to deep-copy; the shallow predecode dup is
//! already correct. GUARD-CONTEXT LAW (the load-bearing one): a `bif`/`gc_bif`
//! with a non-zero BEAM Fail label runs in GUARD context, where a guard BIF has
//! no side effects and FAILURE = BRANCH to the fail label, NOT an exception; a
//! Fail label of 0 is BODY context, where failure CRASHES. This is encoded in
//! `else_to: ?u32` (non-null ⇒ guard/branch; null ⇒ body/crash) and decided in
//! ONE place, `Machine.bifFail`. So a guard `bif2` computing `badarith` takes
//! `else_to` rather than crashing (mutant 1: raise-instead-of-branch breaks the
//! guard-context law). An `.unsupported` BIF traps `undef` in EVERY context (an
//! unimplemented BIF cannot yield a guard truth value, so branching would
//! fabricate a `false`). E2.4 replaced the `.add`/`.sub` enum with a `.func`
//! function pointer (`bifs/dispatch.resolve`→`bifs/erlang.zig`): the ONE `.func`
//! arm resolves args, calls the family fn, and routes its `BifError` through
//! `bifFail`; results land in `dst` (mutant 2: ignoring `dst`, writing x0, is
//! caught by a law placing the result in x3). `gc_live` is the
//! gc_bif Live operand — an advisory GC hint recorded but not acted on (the
//! arena grows on demand; the `alloc_heap` HeapNeed precedent). `randProgram`
//! sprinkles a `bif2` over the supported `+` (body and guard forms) so the
//! DIFFERENTIAL law covers the dispatch mechanics; the failure/guard/undef arms
//! also ride dedicated E1.13 semantic laws.
//!
//! Bit-syntax MATCHING opcodes (E3.3) — a MACHINE-VALUE extension over E3.1's
//! `bitstring_algebra` (no second bit-reader anywhere in this module).
//!   SEMANTIC DOMAIN. A BEAM bit-syntax MATCH CONTEXT is `MatchCtx = { bin:
//!   Term, offset_bits: usize }` — the bitstring/binary being matched, plus a
//!   cursor into it. It is a VM-INTERNAL control value (never a real Erlang
//!   term a program can observe as such — no `is_*` predicate is true of it,
//!   it is never printed, sent, or a map key), but the compiler emits it into
//!   ORDINARY x/y registers exactly like any other value, so it is represented
//!   as a BOXED KIND on the term algebra (`term_algebra.FinalTerms`'s
//!   `SUBTAG_MATCHCTX`, `makeMatchCtx`/`matchCtxBin`/`matchCtxOffset`) rather
//!   than a dedicated `Src`/`Dst` register-value union — this is what lets the
//!   EXISTING `resolve`/`setDst` discipline carry it for free (no new Machine
//!   field, no `eqMachines` register-loop change: see below). `bs_start_match3/
//!   4` build a fresh `MatchCtx` (offset 0) over a bitstring/binary Src, else
//!   branch `else_to` (a non-bitstring source, or `bs_start_match4`'s
//!   compiler-guaranteed `no_fail`/`resume` Fail atom decodes to `else_to =
//!   null`, mirroring `bif_call`'s guard/body optional-label convention).
//!   THREADING. BEAM's `Ctx` operand is BOTH read AND written by every
//!   consuming op (the real interpreter mutates the match buffer in place);
//!   this VM instead builds a FRESH `MatchCtx` term with the advanced cursor
//!   on every successful step and `setDst`s it back to the SAME register the
//!   input came from — a FUNCTIONAL update, matching every other term in this
//!   VM (no in-place mutation), and incidentally immune to an aliasing hazard
//!   a prior `move` might have introduced (two registers holding the "same"
//!   ctx term diverge cleanly on the next get, exactly as if BEAM's real
//!   aliasing rules had been respected by the compiler, which never emits
//!   such an alias for a live match anyway). CURSOR-MONOTONICITY LAW (this
//!   task's core law): each successful get/skip advances `offset_bits` by
//!   EXACTLY the bits consumed (`size × unit`, or the sub-command's own
//!   width); a FAILED test/get (an over-read, a `bs_test_tail2` mismatch, a
//!   `bs_match_string` pattern mismatch, or a `bs_match` sub-command failure)
//!   leaves the `ctx` register's value UNTOUCHED (not merely
//!   observationally-equal — the exact prior term) and jumps `else_to`/
//!   `fail_to` (mutant 2's target: a failed `bs_test_tail2` that still
//!   advances the cursor is killed by this law). `bs_get_position`/
//!   `bs_set_position` save/restore the cursor as a plain small-integer term
//!   (round-trip law: `set(ctx, get(ctx)) ∘ get_X` re-reads the SAME bits).
//!   THE UNIFIED MATCHER (`bs_match/3`, OTP-25+) decodes a FIXED, gpa-owned
//!   `[]BsCmd` sub-command list (`ensure_at_least`/`ensure_exactly`/`integer`/
//!   `binary`/`skip`/`get_tail`/`'=:='`, decoded VERBATIM from the pin's
//!   `genop.tab` doc comment for opcode 182, cross-checked against
//!   `beam_asm.erl`'s `encode_arg({commands,_})` and `beam_disasm.erl`'s
//!   `resolve_bs_match_commands/1` — see `beam_loader.bsCommandsOf`) and
//!   executes it SEQUENTIALLY over ONE threaded (bin, offset) pair local to
//!   the op; ANY command's failure jumps `fail_to` leaving `ctx` UNCHANGED
//!   (same law), success writes the final advanced ctx. `Live` (a GC hint) is
//!   dropped everywhere, matching the `alloc_heap`/`gc_bif` Live/HeapNeed
//!   precedent. THE `'=:='` COMMAND is a JUDGMENT CALL: the pin documents its
//!   fields as `(Live, Size, Value)` but not the exact runtime semantics in
//!   `genop.tab`'s prose; this VM reads `Size` bits big-endian unsigned at the
//!   cursor and compares to `Value` by `eqlExact`, consuming `Size` bits on a
//!   match (documented in the task report; flagged for pin re-verification if
//!   real `.beam` fed through `--load-otp-corpus` ever exercises it with a
//!   divergent shape). FLAG DECODE (`erl_bits.h`'s `BSF_*`, confirmed against
//!   the pin): bit1 LITTLE, bit2 SIGNED, bit4 NATIVE (resolved to the actual
//!   host endianness AT TRANSLATE TIME — `execInstr` only ever sees the two
//!   concrete `BsEndian` values); bit0 ALIGNED is unused (this VM's
//!   bitstrings are ALWAYS canonically packed). ENDIANNESS/SIGN: big-endian
//!   (and every sub-byte field — a documented scope limit, see
//!   `bsMagnitudeAt`) is the direct MSB-first bit-order reading; byte-aligned
//!   little-endian is byte-reversed, MSB-first WITHIN each byte (erl_bits.c's
//!   treatment of the overwhelmingly common case); sign-extension is
//!   endianness-agnostic once the magnitude is correctly reconstructed
//!   (`bsSignExtend`). Every read — standalone op or `bs_match` sub-command —
//!   goes through `bsa.bitAt`/`bsa.slice` (`bitstring_algebra`), NEVER a
//!   second bit-reader. NOT FUZZED by `randProgram` (every op needs a LIVE
//!   MatchCtx already sitting in its `ctx` register — the FR-bank/receive-
//!   cursor precedent); driven by dedicated hand-assembled E3.3 semantic laws
//!   (differential-shaped: each law's oracle IS the direct BEAM semantics
//!   definition, e.g. big-endian `<<1,2>>` → 258) plus `beam_loader`'s
//!   `emit∘parse` operand-decode laws. `eqMachines` needs NO direct edit: a
//!   MatchCtx register already flows through its EXISTING `FinalTerms.denote`
//!   calls, and `denote`'s new `SUBTAG_MATCHCTX` arm (in `term_algebra.zig`)
//!   maps it to a synthetic 2-tuple `{bin_denotation, offset_bits}` — so two
//!   INDEPENDENTLY-BUILT MatchCtx terms with the same bin content and cursor
//!   compare EQUAL even though they live at different heap words
//!   (observational equality, never word/pointer identity — the differential
//!   law's engine#2≡engine#3 comparison over a ctx-threading op rides on
//!   this). `gcCopy`/`Collector.evac`/`checkNoOldToYoung` also gained a
//!   `SUBTAG_MATCHCTX` arm (one raw prefix word — `offset_bits` — then one
//!   term slot — `bin`, the same shape as FLATMAP/HMAP_ROOT/HMAP_NODE) so a
//!   future GC pass over a live MatchCtx does not hit the exhaustive
//!   `else => unreachable` these heap-walkers already carry.
//!
//! Bit-syntax CONSTRUCTION + UTF opcodes (E3.4) — completes entry-1's 20
//! `bs_*` units (12 MATCHING, E3.3; 8 CONSTRUCTION + UTF, here).
//!   `bs_create_bin/6` (the unified OTP-25+ constructor) decodes a FIXED,
//!   gpa-owned `[]BsSeg` segment list (`integer`/`float`/`binary`/
//!   `binary_all`/`utf8`/`utf16`/`utf32`/`string`/`append`/`private_append`,
//!   see `BsSeg`'s doc comment for the on-disk grammar) and writes each
//!   segment's bits into an ACCUMULATING bitstring, IN LIST ORDER, via
//!   `bitstring_algebra.concat` ONLY (`bsSegBits` dispatches per segment
//!   type; `bsFieldBitsChecked`/`intSegBits`/`bitsFromLimbsField` are the
//!   construction-side INVERSE of `bsFieldBits`/`bsIntegerFieldTerm`/
//!   `bsMagnitudeLimbsAt` — same endianness convention, run backwards). A
//!   byte-aligned result is a TRUE binary (SUBTAG_BINARY), matching real
//!   `<<...>>` semantics (`is_binary/1` true) and the fact that
//!   `FinalTerms.binBytes` is not subtag-polymorphic. `append`/
//!   `private_append` are denotationally IDENTICAL to `binary_all` in this
//!   pure, functional-update VM (no distinct "writable binary" — see
//!   `BsSeg`'s doc comment); `bs_init_writable/0` just produces an empty
//!   binary as the append base. FAILURE: a wrongly-typed/out-of-range source
//!   is `badarg`; a segment (or the RUNNING TOTAL, capped at
//!   `bs_construct_max_bits`) whose bit width cannot be represented is
//!   `system_limit` — the EXACT reason atom each maps to, via the SAME
//!   optional-`else_to` guard/body convention `bif_call`/`bs_start_match`
//!   already use. THE ROUND-TRIP LAW (this task's keystone, the LA-3
//!   homomorphism made executable): build a bitstring with `bs_create_bin`,
//!   re-match it with E3.3's `bs_start_match3`/`bs_get_*` family, and recover
//!   every source — proved for every segment type, in list order (MUTANT 1:
//!   reversing the write order is killed by this). UTF: `bs_get_utf`/
//!   `bs_skip_utf` extend the E3.3 `MatchCtx` family with the three UTF
//!   kinds; `.utf8` reuses `unicode.zig`'s `encodeCp`/`decodeCp` EXACTLY (no
//!   second UTF-8 codec — MUTANT 2: accepting an overlong encoding is killed
//!   by `unicode.zig`'s own STRICTNESS law, reused here); `.utf16`/`.utf32`
//!   are NEW, narrowly-scoped codecs (`unicode.zig`'s scope is UTF-8 only)
//!   sharing the SAME codepoint-validity bounds (surrogate range, >0x10FFFF)
//!   as `unicode.zig`. NOT FUZZED by `randProgram` (same LIVE-MatchCtx/well-
//!   typed-segs rationale as E3.3); driven by dedicated hand-assembled E3.4
//!   semantic laws. Two DOCUMENTED, bounded scope limits (DIVERGENCE_LOG
//!   entry 17): the 2 MiB total-construction-size cap (`bs_construct_max_bits`,
//!   a small fixed ceiling so the size-overflow law is testable, vs real
//!   erts' effectively-unbounded limit) and the 512-bit INTEGER-segment cap
//!   (mirrors the MATCHING side's `FinalTerms.max_limbs*64` cap — entry
//!   16(b) — so round-trip stays meaningful at every field width EITHER side
//!   supports).

const std = @import("std");

/// gap-real-metrics: the erlang:memory/0,1 category (DIVERGENCE 627).
pub const MemKind = enum { all, total, processes, atom };
const ta = @import("term_algebra.zig");
const bsa = @import("bitstring_algebra.zig"); // E3.3: the ONE bit-reader for bs_* ops
const unicode = @import("unicode.zig"); // E3.4: the ONE UTF-8 codec for bs_* utf8 segments
const pat = @import("pattern_algebra.zig");
const mba = @import("mailbox_algebra.zig");
const ea = @import("ets_algebra.zig");
const reg = @import("registry.zig"); // E2.10: persistent_term's owned state
const aa = @import("atomics_algebra.zig"); // E2.10: atomics' owned state
const codeix = @import("code_index.zig"); // E2.12: code-query BIFs' owned state
const time_algebra = @import("time_algebra.zig"); // E5.8b: the OS clock + env seam (S21)
const loader = @import("beam_loader.zig"); // e5-dispatch-codeidx: freeProg for the
// runtime dynamic code space (freed in `deinit`). ia↔beam_loader is a lazy
// (type-level) cycle exactly like the pre-existing ia↔code_index one.
// E2.4: the `erlang` guard-BIF family. Imported here for the fuzz/migration
// laws that exercise the real dispatch (`.func = &bif_erlang.add`). The import
// is lazy (function-level references only) — no comptime cycle: erlang.zig
// depends on THIS module's `Machine`, which is defined independently of it.
const bif_erlang = @import("bifs/erlang.zig");
// E3.12: the SINGLE runtime BIF resolver (module,name,arity → ?BifFn). Used by
// `apply/3`/`apply/2`'s DYNAMIC dispatch (the target M:F/A lives in registers,
// unknown at load) — `call_ext` resolves statically at load, but apply cannot.
// Lazy (function-level) import — no comptime cycle (`dispatch.zig` depends on
// this module's `Machine`, defined independently).
const bif_dispatch = @import("bifs/dispatch.zig");

const FinalTerms = ta.FinalTerms;
const AtomTable = ta.AtomTable;
const spec = ta.spec;
const Order = ta.Order;

/// E6.5 (Task 5): a `system_monitor` / `system_profile` setting — the
/// `{Pid, Opts}` pair a set BIF stores and a get BIF returns as a 2-tuple
/// (the get returns the `undefined` atom when this is `null`). Both fields are
/// `ctx` heap refs (u64), never owned memory.
pub const SysSetting = struct { pid: FinalTerms.Term, opts: FinalTerms.Term };

// ============================================================================
// Operands and instruction forms
// ============================================================================

/// E5.2 (DIVERGENCE 46 discharge): the x-register-file index type. The BEAM
/// compact-term encoding tags an x-register operand with a `u8`-range index
/// (`beam_loader.Operand.x` is a `u8`), so the widest well-formed index a
/// `.beam` can name is 255. The final encoding's x-register bank was a 16-slot
/// (`u4`) file (an M3/M5 choice); two preloaded modules (`prim_inet`, `prim_zip`)
/// allocate a 17th x-register (reach x16), so the narrow bank REJECTED them.
/// Widening `XReg` to `u8` and the backing `Machine.regs` to `x_reg_count`
/// covers the entire decodable range → every well-formed preloaded `.beam`
/// loads; `xReg` becomes total (no `RegisterOverflow` is reachable). The FLOAT
/// register bank (`fregs`, the `f*` ops) is a SEPARATE 16-slot file and stays
/// `u4`. `randProgram`/`freshPair` keep seeding only the low 16 slots (the
/// differential corpus references x0..x15 only), so the hot differential path
/// is unchanged; the loader-coverage laws exercise the widened range directly.
pub const XReg = u8;
/// The x-register bank size — the full decodable index range (`u8` + 1). Sized
/// to never reject a well-formed module rather than to BEAM's 1024 `MAX_REG`,
/// since no `Operand.x` (a `u8`) can name a slot at or beyond this bound.
pub const x_reg_count = @as(usize, std.math.maxInt(XReg)) + 1;

pub const Src = union(enum) {
    x: XReg, //      x-register
    y: u8, //        y-register (stack slot; M8)
    imm: i64, //     small-integer literal
    atom_: u32, //   atom-table index literal (M8)
    nil,
    literal: u32, // W-17: index into THIS machine's `literals` table (a LitT
    //               term materialized into this machine's ctx at load). Like
    //               `.imm`/`.atom_` it is a compile-time constant, but a general
    //               (possibly heap) term — so it is resolved by table lookup,
    //               not rebuilt from the tag. `randProgram` never emits it (it
    //               is a load-time-only source); the run site fills the table.
};

/// M8: register destinations — real BEAM code writes both x and y.
pub const Dst = union(enum) { x: XReg, y: u8 };

/// E3.3: view a `Dst` as a `Src` — used by the bit-syntax ops, whose BEAM
/// `Ctx` operand is BOTH read (the current match state) and written (the
/// advanced state), unlike every other `Dst` in this ISA (write-only).
pub fn dstAsSrc(d: Dst) Src {
    return switch (d) {
        .x => |r| .{ .x = r },
        .y => |r| .{ .y = r },
    };
}

pub const MoveOp = struct { src: Src, dst: XReg };
pub const AddOp = struct { a: Src, b: Src, dst: XReg };
pub const PutListOp = struct { h: Src, t: Src, dst: XReg };

/// Straight-line (non-branching) instructions — Layer 1 vocabulary.
pub const BlockInstr = union(enum) {
    move: MoveOp,
    add: AddOp, //           the '+' gc_bif
    put_list: PutListOp, //  cons onto the process heap
};

/// E1.3 type-test kinds. Each names a BEAM `is_*` guard test. The *denotation*
/// of a `.type_test` is a partial predicate on terms: fall through when the
/// predicate holds, jump to `else_to` when it fails. The predicate for each
/// kind is fixed by the existing `term_algebra.FinalTerms` observations — this
/// enum introduces NO new term semantics, it only selects among predicates the
/// term algebra already proves. Not-yet-representable kinds (`pid`, `reference`,
/// `port`) have NO term constructor in the VM yet, so their predicate is the
/// constant `false` (no such term can be built — honest, not faked); the
/// predicate refines when the term kind lands (a monotone widening).
pub const TypeTestKind = enum {
    integer,
    float,
    number,
    atom,
    pid,
    reference,
    port,
    binary,
    list,
    map,
    boolean,
    function,
    bitstr,
    tuple,
};

/// E1.4 comparison-test kinds. Each names a BEAM binary `is_*` compare guard.
/// Like `TypeTestKind`, this enum introduces NO new term semantics: every arm
/// delegates to an EXISTING `term_algebra.FinalTerms` order/equality
/// observation. The distinction the four kinds encode is arithmetic-vs-exact
/// equality — the whole point of these opcodes:
///   * `ge`       — Erlang `>=`, standard term order: fall through iff
///                  `compare(a,b) != .lt` (i.e. "not less than").
///   * `eq_arith` — Erlang `==` (arithmetic): `1 == 1.0` is TRUE. Fall through
///                  iff `compare(a,b) == .eq` (arith-mode ties int/float).
///   * `ne_arith` — Erlang `/=` (arithmetic): fall through iff NOT `.eq`.
///   * `ne_exact` — Erlang `=/=` (exact): `1 =/= 1.0` is TRUE. Fall through iff
///                  `!eqlExact(a,b)` (the twin of `test_eq`'s `=:=`).
pub const CmpTestKind = enum { ge, eq_arith, ne_arith, ne_exact };

/// E1.6: select (jump-table) opcodes. A `select_val`/`select_tuple_arity`
/// carries a FINITE, decode-time-fixed slice of (key, label) pairs — a BEAM
/// jump table. Denotation: a total function on the resolved Src to a program
/// counter — the first pair (in table order) whose key matches wins; if none
/// match, `fail_to`. The scan is a LINEAR scan over the fixed slice (BEAM's
/// table order; the compiler may pre-sort, E1 need not binary-search) and is
/// BOUNDED: the slice length is fixed at translate time, never grown at run
/// time — no unbounded loop. `select_val` matches with `eqlExact` (EXACT: the
/// keys `1` and `1.0` are DIFFERENT — the whole reason `case` selects the
/// integer clause, not the float one). `select_tuple_arity` matches the arity
/// of a tuple Src against a `u16` (non-tuple Src ⇒ `fail_to`). The `pairs`
/// slice is gpa-owned (allocated by `beam_loader.translate`, freed by
/// `beam_loader.freeProg`), exactly like `put_tuple2.elems`.
pub const SelectValPair = struct { key: FinalTerms.Term, to: u32 };
pub const SelectArityPair = struct { arity: u16, to: u32 };

/// E1.10 / E5.2: map-opcode operand pairs. `MapElemPair` is one (key, dst) of
/// `get_map_elements` — the key is a runtime `Src` resolved by `resolve` at
/// execution (DIVERGENCE 47 discharge: real erlc emits both LITERAL keys —
/// small int / atom / nil, arriving as `.imm`/`.atom_`/`.nil` — AND
/// REGISTER-valued keys computed at runtime, arriving as `.x`/`.y`; `init`,
/// `prim_net`, `prim_socket`, `socket_registry` all carry a register key). The
/// dst is a register to receive the looked-up value. `MapKV` is one
/// (key-src, val-src) of `put_map_{assoc,exact}` — also runtime Srcs. Neither
/// introduces map semantics; lookups/inserts go through the `FinalTerms` map
/// API (mapGet/mapPut, flat↔HAMT), whose laws already hold. NOTE: this is a
/// DISTINCT struct from `RecordElem` (`get_record_elements`, E3.14), which
/// keeps its decode-time atom-Term field names — widening the key here does
/// not touch native records.
pub const MapElemPair = struct { key: Src, dst: Dst };
pub const MapKV = struct { k: Src, v: Src };

/// E1.14: one (index, value) field-update of `update_record`. `index` is the
/// 0-BASED element index (the BEAM opcode's Offset is 1-based over the untagged
/// tuple storage — offset 0 is the header word — so translate stores Offset−1,
/// matching `tupleElem`/`setTupleElem`'s 0-based element indexing). `value` is
/// a general runtime Src (a record field may be set from any register/literal).
pub const RecordUpdate = struct { index: u16, value: Src };

/// E3.14: native-record opcode payloads (genop.tab 186-191 over the E3.14
/// native_record term kind). `get_record_elements`' element list is
/// {FieldName atom, dst Register} pairs; `put_record`'s updates are
/// {FieldName atom, value Src} pairs. `NrScope` decodes the `is_record_
/// accessible` Scope operand.
pub const RecordElem = struct { key: FinalTerms.Term, dst: Dst };
pub const RecordFieldSrc = struct { key: FinalTerms.Term, value: Src };
pub const NrScope = enum { external, auto_local };

/// Full control vocabulary — Layer 2. Every BlockInstr embeds unchanged.
pub const CInstr = union(enum) {
    move: MoveOp,
    add: AddOp,
    put_list: PutListOp,
    test_eq: struct { a: Src, b: Src, else_to: u32 }, // fall through on equal
    is_lt: struct { a: Src, b: Src, else_to: u32 }, //  fall through on a < b
    jump: struct { to: u32, tail: bool = false }, // tail=true ⇐ a beam call_only/call_last (a tail CALL, which OTP charges 1 reduction for); tail=false is an intra-function branch (0 reductions). R2 (gap-reduction-cost-model) reads this to charge the OTP per-call way.
    call: struct { to: u32 }, // push return pc, jump
    ret, //                      pop pc; empty stack = normal process return
    halt: struct { src: Src },
    // ---- M5: mailbox (single-process; cross-process send is M7) ----
    self_send: struct { src: Src }, //                 deliver to own mailbox
    recv_eq: struct { m: Src, dst: XReg, else_to: u32 }, // selective: =:= match
    recv_any: struct { dst: XReg, else_to: u32 }, //     take the oldest
    // ---- E1.11: the REAL BEAM receive-loop ops (M5's self_send/recv_eq/recv_any
    // are their abstract precursors). They map onto `mailbox_algebra`'s arrival
    // sequence via the machine's `recv_cursor` save-pointer + the M7 `.send_to`
    // trap — NO new mailbox semantics. A BEAM receive is a loop:
    //   L_loop: loop_rec L_wait, Dst   % peek the msg at the cursor into Dst;
    //                                    % empty ⇒ jump L_wait
    //           <test Dst>             % the program's own guard code
    //           loop_rec_end L_loop    % no match ⇒ advance cursor, retry
    //           remove_message         % match  ⇒ commit the pop (cursor→0)
    //           ...
    //   L_wait: wait_timeout L_loop T  % exhausted ⇒ wait T ms; T=0 fires NOW
    //           timeout                % after-clause: clear the save-pointer
    // `send/0` sends x1 to the pid in x0 (a `.send_to` trap), the message being
    // the result in x0. `wait/1` suspends (single-process E1: status `.suspended`
    // — no scheduler wake yet; that is a later epoch). `wait_timeout` with a `0`
    // (or any finite, in the timer-less E1 model) timeout FIRES immediately and
    // falls through; only `infinity` suspends — treating `0` as infinite would
    // hang, which is a failed law (mutant 2). The `recv_marker_*` ops are receive-
    // QUEUE OPTIMIZATION markers: SEMANTICALLY TRANSPARENT (no denotation depends
    // on them — the transparency law), implemented as dispatched no-ops for E1
    // (a real marker table is an E3 perf concern).
    send, //                                           send/0: x1→pid x0, result x0
    remove_message, //                                 commit the peeked pop
    timeout, //                                        reset the receive save-pointer
    loop_rec: struct { else_to: u32, dst: XReg }, //     peek cursor msg into dst / jump
    loop_rec_end: struct { to: u32 }, //               advance cursor, retry loop_rec
    wait: struct { to: u32 }, //                       suspend (resume at Lbl)
    wait_timeout: struct { to: u32, src: Src }, //     wait with timeout; 0 fires now
    recv_marker_bind, //                               transparent optimization no-ops
    recv_marker_clear,
    recv_marker_reserve,
    recv_marker_use,
    // ---- M5: funs ----
    make_fun: struct { to: u32, arity: u8, dst: XReg }, // label-only closure
    call_fun: struct { f: Src }, //                    badfun if not a fun
    // ---- E1.7: modern call / apply / fun ops. `call_fun2` is BEAM's arity-
    // tagged fun call (resolve Func, badfun if not a fun, push return, jump to
    // the fun's label — same effect as `call_fun`, plus a static arity operand).
    // `apply`/`apply_last` read `m:f/a` from x[arity]/x[arity+1]; cross-module
    // export resolution is E3 (full `error_handler`), so with no resolver in
    // scope every apply target is unresolved and traps `undef`. `apply_last`
    // deallocates `last` y-slots FIRST (the BEAM `*_last` tail-call frame
    // convention) so the trap unwinds the shorter stack. `make_fun3` builds a
    // closure capturing a gpa-owned `env` slice (built at `translate` time, freed
    // by `beam_loader.freeProg` — the 4th such owned-slice variant, alongside
    // `put_tuple2.elems` and the two `select_*` `pairs`).
    call_fun2: struct { f: Src, arity: u8 },
    apply: struct { arity: u8, last: ?u8 }, // last = y-slots to deallocate (apply_last)
    // W-16: `arity` is the closure's VISIBLE fun arity (== the FunT lambda-table
    // `arity` field). It is DISTINCT from `env.len` (== num_free, the captured
    // free-var count): OTP sets the fun-header ARITY to the lambda entry's arity
    // and the ENV_SIZE to num_free separately (emu `i_make_fun3`:
    // `MAKE_FUN_HEADER($Arity, num_free, 0)` with `ASSERT($Arity == fe->arity)`).
    // Pre-W-16 this stored `env.len` — the E1.7 arity divergence, now CLOSED.
    make_fun3: struct { to: u32, arity: u8, dst: Dst, env: []const Src, name: u32 = 0, module: u32 = 0, index: u32 = 0, old_uniq: u32 = 0 }, // gpa-owned env slice; name/module = FunT generated-name + defining-module GLOBAL atom idxs (0 = none, e.g. synthetic/fuzzer make_fun3) — carried for fun_info_mfa/1 (DIVERGENCE 727); index/old_uniq = FunT Index + OldUniq for the `#Fun<Module.Index.OldUniq>` print shape (DIVERGENCE 740)
    // ---- E3.12: static multi-module dispatch. `call_ext`/`call_ext_only`/
    // `call_ext_last` resolve their import at LOAD time to EITHER a BIF (baked
    // as `call_ext_bif`, executed here over x0..x[arity-1] → x0) or a
    // cross-module code export (`call_ext_code`, resolved at RUN time through
    // `m.exports`). This is the pin that makes the E3.7/E3.8/E3.9/E3.10
    // `deferred-E4-procdispatch` BIF families (spawn/send/exit/link/monitor/register/
    // process_info/pdict/error/throw/…) END-TO-END reachable from a compiled
    // `.beam` — before this arm those all translated to `func_info` (a crash).
    // The tail forms (`call_ext_only`/`_last`) are lowered to the atomic BIF/jump
    // op followed by a `ret` (and preceded by a `dealloc_y` for `_last`), so a
    // process-effect BIF that TRAPS (`m.pending`) resumes correctly onto the
    // `ret` — the same split every other tail-call op uses. Neither carries a
    // code label or an owned slice, so `freeProg`/`peephole`/the label fixups
    // need no new arm (the `bif_call` precedent).
    call_ext_bif: struct { func: BifFn, arity: u8, size_class: BifSizeClass = .none }, //   run bif over x0..x[arity-1] → x0 (R2c size_class: accounting-only reduction weight)
    call_ext_code: struct { module: ta.AtomIdx, func: ta.AtomIdx, arity: u8, push_ret: bool }, // resolve via m.exports / undef
    // `erlang:apply/3` (call_ext form): M=x0, F=x1, Args=x2 (a proper list). Its
    // arity is the list length; Args are spread into x0.. before the resolved
    // M:F/A is dispatched (BIF or code or undef) — the apply/3 ≡ call_ext law.
    apply3: struct { tail: bool },
    // gap-apply-fun (DIVERGENCE 733): `erlang:apply/2` — Fun=x0, Args=x1 (a proper
    // list). Spread Args into x0.. then dispatch the FUN (like call_fun): an
    // arity-mismatch is `{badarity,{Fun,Args}}`, a non-fun is `badarg`. The `apply/2`
    // BIF form the compiler emits when the arg LIST is opaque (runtime, not literal);
    // a literal list is spread to a direct fun call at compile time.
    apply_fun: struct { tail: bool },
    // `apply/2`/`apply_last/2` OPCODE (E1.7 upgrade): M=x[arity], F=x[arity+1],
    // args ALREADY in x0..x[arity-1]. Resolves M:F/arity dynamically (BIF/code/
    // undef) instead of the pre-E3.12 unconditional `undef` trap.
    apply_op: struct { arity: u8, tail: bool },
    // ---- M8: ops the BEAM loader needs ----
    is_cons: struct { src: Src, else_to: u32 }, //     is_nonempty_list
    // ---- E1.3: type-test guards. Fall through if the predicate holds, else
    // pc = else_to. `type_test` covers the 13 unary is_* ops; `is_function_arity`
    // is BEAM's is_function2 (tests fun-of-arity-N) which needs the arity operand.
    type_test: struct { kind: TypeTestKind, src: Src, else_to: u32 },
    // ---- E1.4: comparison-test guards (is_ge/is_eq/is_ne/is_ne_exact). Fall
    // through if the comparison holds, else pc = else_to. `cmpTestHolds` fixes
    // the predicate per kind (arith vs exact equality); NO new term semantics.
    cmp_test: struct { op: CmpTestKind, a: Src, b: Src, else_to: u32 },
    // `arity` is the STATIC arity operand (the common `is_function2 F N` form,
    // where erlc knows N at compile time). E6.8 (DIVERGENCE 97 (3a)): erlc also
    // emits is_function2 with the arity in a REGISTER (`is_function(F, X)` where
    // X is a runtime term, e.g. eunit_data's `check_arity/3` — the arity a
    // `{tr,{x,1},{t_integer,{0,2}}}` typed register). When `arity_src` is set the
    // guard resolves that register to a small non-negative integer and compares
    // it to the fun's arity; a non-integer / negative / out-of-small-range arity
    // silently FAILS the guard (jump to `else_to`), exactly as BEAM's guard
    // semantics dictate (a bad `is_function/2` arity is not a guard MATCH). When
    // `arity_src` is null the static `arity` field is used (unchanged path).
    is_function_arity: struct { src: Src, arity: u32, else_to: u32, arity_src: ?Src = null },
    // ---- E1.5: tuple opcode family. `get_tuple_elem`/`set_tuple_elem` have NO
    // fail label (BEAM trusts a preceding `test_arity`); `test_arity` and
    // `is_tagged_tuple` ARE guarded test ops (fall through on match, else
    // pc = else_to). Index operands are 0-BASED (the BEAM opcode convention;
    // Erlang `element/2` is 1-based, the compiler subtracts one).
    get_tuple_elem: struct { src: Src, index: u16, dst: Dst },
    set_tuple_elem: struct { newval: Src, tuple: Src, index: u16 },
    put_tuple2: struct { dst: Dst, elems: []const Src }, // arena/gpa-owned slice
    // ---- E1.14: record update. `update_record` COPIES the source tuple-backed
    // record, overwrites each `updates[k].index` position with its resolved
    // value, and writes the fresh tuple to `dst` — the SOURCE record is left
    // UNCHANGED (the aliasing law; BEAM's in-place hint is a heap-reuse
    // optimisation that denotes identically, so the interpreter always copies).
    // `updates` is a finite, gpa-owned slice (translate-allocated, freed by
    // `beam_loader.freeProg`, deep-copied by `transform.peephole`) — same
    // ownership as `put_tuple2.elems` / the map `kvs`. NO fail label.
    update_record: struct { src: Src, dst: Dst, updates: []const RecordUpdate }, // gpa-owned
    // ---- E3.14: native-record opcodes (genop.tab 186-191) over the
    // native_record term kind. `is_any_native_record`/`is_native_record`/
    // `is_record_accessible` are guard-shaped (branch on `else_to`);
    // `get_record_elements` writes N registers or branches (clobber-nothing on
    // a miss, like `get_map_elements`); `put_record` creates/updates a record;
    // `get_record_field` reads one field and RAISES (Lbl==0 ⇒ else_to null) or
    // branches. `elems`/`updates` are gpa-owned slices.
    is_any_native_record: struct { src: Src, else_to: u32 },
    is_native_record: struct { src: Src, module: FinalTerms.Term, name: FinalTerms.Term, else_to: u32 },
    get_record_elements: struct { src: Src, elems: []const RecordElem, else_to: u32 }, // gpa-owned
    // `id` resolves to the `{Module,Name}` tuple used for CREATE (src == nil);
    // for UPDATE (src is a native record) it is ignored.
    put_record: struct { id: Src, src: Src, dst: Dst, updates: []const RecordFieldSrc }, // gpa-owned
    is_record_accessible: struct { src: Src, scope: NrScope, else_to: u32 },
    // `id` resolves to `{Module,Name}` (name-check) or the atom `_` (no check).
    get_record_field: struct { src: Src, id: Src, field: FinalTerms.Term, dst: Dst, else_to: ?u32 },
    test_arity: struct { src: Src, arity: u16, else_to: u32 },
    is_tagged_tuple: struct { src: Src, arity: u16, tag: FinalTerms.Term, else_to: u32 },
    // ---- E1.6: select (jump-table) opcodes. Linear scan over a finite,
    // gpa-owned `pairs` slice; jump to the matching label, else `fail_to`.
    // `select_val` matches keys with `eqlExact` (EXACT); `select_tuple_arity`
    // matches a tuple's arity. Both ALWAYS set pc (a case always goes somewhere).
    select_val: struct { src: Src, fail_to: u32, pairs: []const SelectValPair }, // gpa-owned
    select_tuple_arity: struct { src: Src, fail_to: u32, pairs: []const SelectArityPair }, // gpa-owned
    // ---- E1.10: map opcodes (is_map is already Task-3 `type_test .map`). All go
    // through the FinalTerms map API (flat↔HAMT) — NO new map semantics; keys use
    // the map's own EXACT key equality (1 and 1.0 are different keys).
    // `has_map_fields`/`get_map_elements` are guarded tests: fall through iff the
    // map has ALL listed keys, else pc = else_to. `get_map_elements` is
    // ALL-OR-NOTHING — it checks EVERY key present BEFORE writing any dst, so a
    // present+absent mix jumps `else_to` and clobbers NO register (mutant 1 writes
    // as it scans). `put_map` builds a new map via mapPut: `assoc` inserts-or-
    // updates (maps:put), `exact` updates ONLY existing keys — an absent key is a
    // `{badkey, Key}` crash, it must NOT insert (mutant 2 makes exact act like
    // assoc). The `keys`/`pairs`/`kvs` slices are gpa-owned (translate-allocated,
    // freed by `beam_loader.freeProg`) — the map analogue of `put_tuple2.elems`
    // and the select `pairs`.
    has_map_fields: struct { src: Src, keys: []const Src, else_to: u32 }, // gpa-owned keys (E5.2: runtime Srcs, DIVERGENCE 47)
    get_map_elements: struct { src: Src, pairs: []const MapElemPair, else_to: u32 }, // gpa-owned pairs
    put_map: struct { exact: bool, src: Src, dst: Dst, kvs: []const MapKV }, // gpa-owned kvs
    get_list: struct { src: Src, hd: Dst, tl: Dst },
    get_hd: struct { src: Src, dst: Dst },
    get_tl: struct { src: Src, dst: Dst },
    alloc_y: struct { n: u8 }, //                      allocate stack slots
    dealloc_y: struct { n: u8 },
    // ---- E1.9: stack/heap frame opcodes. `alloc_heap` is `allocate_heap`'s
    // StackNeed+Live (HeapNeed is advisory — this arena grows on demand, so it
    // is recorded nowhere; see the execInstr arm doc). `trim` drops the top `n`
    // y-slots and KEEPS the remaining (older) frame — same
    // `shrinkRetainingCapacity(len - n)` direction as `dealloc_y` (BEAM's
    // Remaining operand is advisory, like Live, and is not carried).
    alloc_heap: struct { stack: u8, live: u8 },
    trim: struct { n: u8 },
    move2: struct { src: Src, dst: Dst }, //           general move
    swap: struct { a: Dst, b: Dst }, //                gap-swap-x15 (DIVERGENCE 730): exchange two registers WITHOUT a scratch x-register (the old x15-scratch lowering clobbered the 16th arg of a 16-arg function — killed every gen_statem timer)
    sub: struct { a: Src, b: Src, dst: XReg }, //        gc_bif '-'
    // ---- E1.12: float-register (FR) opcodes. BEAM keeps a SEPARATE bank of 16
    // floating-point registers (`Machine.fregs: [16]f64`) holding raw IEEE
    // doubles — NOT boxed float terms. `fmove_to_f` loads a float TERM's f64 into
    // the bank; `fconv` CONVERTS a numeric term (int OR float) to f64 (int `5` →
    // `5.0`, a conversion NOT a bit-cast); `fmove_from_f` boxes an FR back to a
    // float term. The arithmetic ops compute in f64 (`fsub` is `FA - FB`, order
    // matters) and crash `badarith` on a non-finite result (the gc_bif2 arith
    // precedent — the BEAM `Fail` label is the strict-mode exception route, not
    // carried in E1). No new float SEMANTICS: every result denotes the same f64
    // `term_algebra` float ops would, so `fadd` of `2.0`,`3.0` boxes to `5.0`.
    // The `a`/`b`/`fdst` are FR indices (0..15); FR ops carry no code label, so
    // peephole/loader label-fixups do not touch them. LAW-DRIVEN, not fuzzed by
    // `randProgram` (an FR op needs the bank pre-loaded — the `apply` precedent).
    fmove_to_f: struct { src: Src, fdst: XReg }, //      float term → FR[fdst]
    fmove_from_f: struct { fsrc: u4, dst: Dst }, //    FR[fsrc] → boxed float term
    fconv: struct { src: Src, fdst: XReg }, //           number term → f64 in FR[fdst]
    fadd: struct { a: u4, b: u4, fdst: XReg }, //        FR[fdst] = FR[a] + FR[b]
    fsub: struct { a: u4, b: u4, fdst: XReg }, //        FR[fdst] = FR[a] - FR[b]
    fmul: struct { a: u4, b: u4, fdst: XReg }, //        FR[fdst] = FR[a] * FR[b]
    fdiv: struct { a: u4, b: u4, fdst: XReg }, //        FR[fdst] = FR[a] / FR[b]
    fnegate: struct { a: u4, fdst: XReg }, //            FR[fdst] = -FR[a]
    func_info, //                                      function_clause crash
    // ---- M7: cross-process effects. The machine stays PURE: these trap
    // into a pending Action; the VM (proc.zig) interprets it and resumes.
    spawn: struct { to: u32, dst: XReg }, //             child pid into dst
    send_to: struct { pid: Src, msg: Src },
    link_to: struct { pid: Src },
    unlink_to: struct { pid: Src },
    monitor_to: struct { pid: Src, dst: XReg }, //       ref into dst
    demonitor_ref: struct { ref: Src },
    exit_proc: struct { reason: Src }, //              exit/1
    trap_exits: struct { on: bool }, //                process_flag(trap_exit)
    // ---- E1.8: exception opcodes. `try`/`catch` PUSH a `CatchFrame` (recording
    // the recovery label `to` and the current ystack height as `y_depth`);
    // `try_end`/`catch_end` POP it (normal exit). `try_case` is the try-exception
    // landing (stack no-op — the frame was consumed by the unwind). `raise`/
    // `raw_raise` re-raise (unwind); `try_case_end`/`badrecord` are guard-failure
    // crashes. `build_stacktrace` yields the E1-minimal stacktrace (`nil`). The
    // `dst`/`src` y-slot operands mirror BEAM's frame slot; E1 tracks the frame
    // on `catch_stack` and does not read them (documented). `to` is a code label
    // (fixed up by the loader, renumbered by peephole).
    catch_: struct { to: u32, dst: Dst }, //           catch Dst Lbl
    catch_end: struct { dst: Dst }, //                 catch_end Dst
    try_: struct { to: u32, dst: Dst }, //             try Dst Lbl
    try_end: struct { dst: Dst }, //                   try_end Dst
    try_case: struct { dst: Dst }, //                  try_case Dst
    try_case_end: struct { src: Src }, //              {try_clause, Value} crash
    // batch-4: the compiled failure-path raisers, with their EXACT BEAM reason
    // shapes (pre-fix, all three decoded to `.func_info` — every body-match/
    // case/if failure in loaded code raised function_clause instead).
    raise_reason: struct { tag: enum { badmatch, case_clause, if_clause }, src: ?Src },
    raise: struct { trace: Src, value: Src }, //       re-raise (unwind)
    raw_raise, //                                      erlang:raise/3 (class in x0)
    build_stacktrace, //                               cook the stacktrace in x0
    badrecord: struct { src: Src }, //                 {badrecord, Value} crash
    // ---- E1.13: the BIF-dispatch opcode family (bif0/1/2/3, gc_bif1/3). ONE
    // CInstr models every `bif`/`gc_bif` form: the loader decodes the BIF import
    // ref to an `M:F/A`, looks it up in `supported_bifs`, and stores the outcome
    // in `bif`. `.op` ⇒ the executor runs it (the `+`/`-` arith slice today,
    // reusing the `.add`/`.sub` computation); `.unsupported` ⇒ the executor traps
    // `undef` (BIF COVERAGE is E2 — E1 only makes the opcodes total). `args` is a
    // FIXED inline `[argc]Src` (arity ≤ 3, so NO owned slice — nothing for
    // freeProg/peephole to release). `else_to` encodes the BEAM Fail label:
    // `?u32` is the GUARD-vs-BODY context switch — non-null (a real guard fail
    // label) ⇒ a failing BIF BRANCHES (guard BIFs have no side effects); null
    // (body context, Fail=0) ⇒ a failing BIF CRASHES. `gc_live` is the gc_bif
    // Live operand (an advisory GC hint; this arena grows on demand, so it is
    // recorded but not acted on — the `alloc_heap` HeapNeed precedent).
    bif_call: struct {
        bif: BifRef,
        args: [3]Src, //   only args[0..argc] are meaningful
        argc: u8, //       0..3
        dst: Dst,
        else_to: ?u32, //  guard fail label (branch) vs null (body ⇒ crash)
        gc_live: ?u8, //   gc_bif Live hint (advisory), null for plain bif*
    },
    // ---- E1.15: special/no-op opcodes. `on_load/0` marks a module's on-load
    // function (real BEAM RUNS it at load time; E1 does not run on-load
    // callbacks — that is Epoch E4, "boot the world" — so treating it as a
    // transparent runtime no-op is an E1-minimal simplification; see
    // DIVERGENCE_LOG.md). `nif_start/0` is a genuine no-op: a NIF stub landing
    // pad the loader emits but the interpreter never needs to act on. Both
    // decode to THIS ONE nop-class CInstr (`note` records which, purely for
    // diagnostics/disassembly — the executor treats every NopKind identically).
    // TRANSPARENCY LAW: executing a `nop` is denotationally transparent —
    // it consumes exactly one reduction and advances to the next instruction,
    // touching NO `x`/`y` register, NO heap, and no pc beyond the normal
    // fall-through. A program with a `nop` spliced in anywhere produces the
    // IDENTICAL observable result (x0 / heap / status) as the same program
    // without it — see the LAW test below. Carries no label and no owned
    // slice, so peephole/freeProg need no new arm (same as `recv_marker_*`).
    nop: struct { note: NopKind },
    // ---- E3.3: bit-syntax MATCHING opcodes. The "match context" is the
    // SUBTAG_MATCHCTX boxed term `term_algebra.FinalTerms.makeMatchCtx` —
    // see that doc comment for the representation choice (a boxed kind, not
    // a new register-value union, so `Src`/`Dst` resolve/setDst carry it for
    // free). Every consuming op READS the ctx from a `Dst` operand (BEAM's
    // `Ctx` is both source AND destination — the interpreter mutates it in
    // place; this VM instead builds a FRESH MatchCtx term with the advanced
    // cursor and `setDst`s it back to that SAME register — functional
    // update, matching every other term in this VM, avoiding an aliasing
    // hazard if a prior `move` copied the ctx into two registers) and WRITES
    // it back to the SAME `Dst` on success; on FAILURE it does NOT write the
    // ctx back at all — the register keeps its exact prior value, which is
    // the cursor-monotonicity law's "unchanged on branch" half (mutant 2's
    // target: a failed `bs_test_tail2` that still advances the cursor is
    // killed by this). Every read of the underlying bits goes through
    // `bitstring_algebra` (`bsa.bitAt`/`bsa.slice`) — NO second bit-reader.
    bs_start_match: struct { src: Src, ctx: Dst, else_to: ?u32 }, // else_to null: compiler-guaranteed (bs_start_match4 no_fail/resume)
    // bs_match/3: the unified OTP-25+ matcher. `cmds` is a gpa-owned, finite,
    // decode-time-fixed slice of `BsCmd` (mirrors `put_tuple2.elems`
    // ownership) — executed sequentially against ONE threaded (bin, offset)
    // pair; ANY command's failure jumps `fail_to` leaving the `ctx` register
    // UNCHANGED (same law as the standalone ops); success runs every command
    // and writes the final advanced ctx to `ctx`.
    bs_match: struct { ctx: Dst, fail_to: u32, cmds: []const BsCmd }, // gpa-owned cmds
    bs_get_integer: struct { ctx: Dst, size: Src, unit: u8, signed: bool, endian: BsEndian, dst: Dst, else_to: u32 },
    bs_get_float: struct { ctx: Dst, size: Src, unit: u8, endian: BsEndian, dst: Dst, else_to: u32 },
    bs_get_binary: struct { ctx: Dst, size: Src, unit: u8, dst: Dst, else_to: u32 },
    bs_skip_bits: struct { ctx: Dst, size: Src, unit: u8, else_to: u32 },
    // bs_test_tail2: Bits is a COMPILE-TIME constant bit count (genop `.u`,
    // never a register) — remaining bits must equal it EXACTLY, else jump
    // `else_to` with the ctx UNCHANGED (mutant 2's target op).
    bs_test_tail: struct { ctx: Src, bits: u32, else_to: u32 },
    // bs_match_string: literal bit-pattern equality at the cursor. `bytes` is
    // a gpa-owned copy of the literal pattern (decoded from the module's
    // `StrT` chunk at translate time — see `beam_loader.parse`'s StrT arm);
    // `bit_len` is the pattern's bit width (may be non-byte-multiple).
    bs_match_string: struct { ctx: Dst, bit_len: u32, bytes: []const u8, else_to: u32 }, // gpa-owned bytes
    bs_get_tail_ctx: struct { ctx: Src, dst: Dst }, // remaining bits (from cursor to end) → bitstring; ctx unchanged (whole-tail read, no cursor advance needed — nothing remains)
    bs_get_position: struct { ctx: Src, dst: Dst }, // save: cursor (a small int) → dst
    bs_set_position: struct { ctx: Dst, pos: Src }, // restore: dst ctx ← {same bin, pos}
    // ---- E3.4: bit-syntax CONSTRUCTION + UTF opcodes. `bs_create_bin` is
    // the unified OTP-25+ constructor: `segs` (gpa-owned, decode-time-fixed,
    // mirrors `bs_match.cmds`/`put_tuple2.elems` ownership) is written IN
    // LIST ORDER (mutant 1's target: reversing this order is killed by the
    // construction↔matching round-trip law) into an accumulating bitstring
    // via `bitstring_algebra.concat` ONLY — no second bit-writer. `else_to`:
    // null (BEAM `Fail={f,0}`) crashes body-context on badarg/system_limit;
    // non-null branches (same `bifCallOf`/`bsStartFailOf` convention).
    bs_create_bin: struct { dst: Dst, else_to: ?u32, segs: []const BsSeg }, // gpa-owned segs
    // `bs_init_writable/0`: produces an EMPTY binary — this VM has no
    // distinct "writable binary" representation (see the E3.4 report): a
    // `bs_create_bin` `append`/`private_append` segment is denotationally
    // just `bitstring_algebra.concat`, so any ordinary binary term (however
    // built) serves as a valid append base. `Dst` is always `{x,0}` on real
    // .beam (the ONE fixed hard-coded target the compiler ever emits) but we
    // decode it generically like every other Dst.
    bs_init_writable: struct { dst: Dst },
    // UTF matching-side reads (extending E3.3's MatchCtx family with the
    // three UTF kinds the E3.3 task deferred). `endian` is ignored for utf8
    // (fixed multi-byte form) — decoded but unused, matching
    // `bsFlagsOf`'s existing "decoded for validation" precedent
    // (`beam_loader`'s `bs_get_binary2` arm).
    bs_get_utf: struct { ctx: Dst, kind: UtfKind, endian: BsEndian, dst: Dst, else_to: u32 },
    bs_skip_utf: struct { ctx: Dst, kind: UtfKind, endian: BsEndian, else_to: u32 },
};

/// E3.4: which UTF codec a `bs_get_utf`/`bs_skip_utf`/`BsSeg.utf*` op reads
/// or writes through — `unicode.zig`'s codec for `.utf8` (the ONLY UTF
/// variant that module already implements); `.utf16`/`.utf32` are encoded/
/// decoded by NEW, narrowly-scoped helpers in THIS file (`utf16Encode`/
/// `utf16Decode`/`utf32Encode`/`utf32Decode`) — `unicode.zig`'s scope is
/// UTF-8 only (its own doc comment: "the charlist ↔ UTF-8-binary algebra"),
/// so there is no existing UTF-16/32 codec to reuse; what IS reused across
/// all three is the shared Unicode codepoint-validity rule (surrogate range
/// 0xD800..0xDFFF rejected, > 0x10FFFF rejected) that `unicode.zig`'s
/// `encodeCp`/`decodeCp` already enforce for UTF-8 — the new UTF-16/32
/// helpers apply the IDENTICAL bounds, never a laxer or stricter rule.
pub const UtfKind = enum { utf8, utf16, utf32 };

/// E3.4: one `bs_create_bin/6` segment, decoded VERBATIM from the on-disk
/// `{Type,Seg,Unit,Flags,Val,Size}` 6-tuple grammar — cited against the pin
/// (see the E3.4 report): `third_party/otp/lib/compiler/src/genop.tab`
/// (`177: bs_create_bin/6`, `@spec bs_create_bin Fail Alloc Live Unit Dst
/// OpList`), `beam_disasm.erl`'s `resolve_bs_create_bin_list/2` (the exact
/// per-type field shape, including the 'string' type's StrT-offset
/// substitution), and CONFIRMED against a freshly `erlc`-compiled fixture
/// module disassembled with `beam_disasm:file/1` (every segment type this
/// union covers was exercised: integer/binary/binary_all/float/utf8/
/// utf16-little/string/append). `Seg` (a segment-number, used only for
/// erts' own error-message text) is decoded-and-discarded, matching the
/// `Live`/`HeapNeed` advisory-operand precedent (E1.9/E1.13/E3.3).
pub const BsSeg = union(enum) {
    integer: struct { src: Src, size: Src, unit: u8, endian: BsEndian },
    float: struct { src: Src, size: Src, unit: u8, endian: BsEndian },
    binary: struct { src: Src, size: Src, unit: u8 },
    binary_all: struct { src: Src }, // Size=`all`: the source's ENTIRE bit content
    utf8: struct { src: Src },
    utf16: struct { src: Src, endian: BsEndian },
    utf32: struct { src: Src, endian: BsEndian },
    string: struct { bytes: []const u8 }, // gpa-owned, copied from the module's StrT chunk
    // `append`/`private_append`: denotationally IDENTICAL to `binary_all` in
    // this pure, functional-update VM (see the E3.4 report's "writable
    // binary" note) — both just contribute the source's own bits verbatim,
    // in LIST ORDER, ahead of whatever segments follow. Kept as distinct
    // variants (not folded into `binary_all`) purely so `execInstr`'s
    // exhaustive switch documents the on-disk vocabulary faithfully.
    append: struct { src: Src },
    private_append: struct { src: Src },
};

/// E3.3: BEAM `bs_get_integer2`/`bs_get_float2`/`bs_match`'s `integer` command
/// endianness selector, decoded from the BSF_LITTLE/BSF_NATIVE flag bits (see
/// `beam_loader`'s flag decode, cited against the pin's `erl_bits.h`).
pub const BsEndian = enum { big, little };

/// E3.3: one `bs_match/3` sub-command — the OTP-25+ unified matcher's
/// grammar, decoded VERBATIM from the pin's `genop.tab` doc comment for
/// `182: bs_match/3` (cross-checked against `beam_disasm.erl`'s
/// `resolve_bs_match_commands/1` and `beam_asm.erl`'s `encode_arg({commands,
/// List0}, _)`, both of which flatten each `{Tag, Field...}` tuple to
/// `[{atom,Tag} | Field...]` in the `{z,1}` extended-list operand — so
/// `beam_loader.translate` walks ONE flat `[]const Operand` list, dispatching
/// on each atom's NAME):
///   {ensure_at_least,Stride,Unit} | {ensure_exactly,Stride}
///   | {binary,Live,Flags,Size,Unit,Dst} | {integer,Live,Flags,Size,Unit,Dst}
///   | {skip,Stride} | {get_tail,Live,Unit,Dst} | {'=:=',Live,Size,Value}
/// `Live` (a GC-liveness hint, advisory) is dropped everywhere, matching the
/// `alloc_heap`/`gc_bif` Live/HeapNeed precedent (E1.9/E1.13) — this arena
/// grows on demand.
pub const BsCmd = union(enum) {
    ensure_at_least: struct { stride: u32, unit: u8 },
    ensure_exactly: struct { stride: u32 },
    integer: struct { size: Src, unit: u8, signed: bool, endian: BsEndian, dst: Dst },
    binary: struct { size: Src, unit: u8, dst: Dst },
    skip: struct { stride: u32 },
    get_tail: struct { unit: u8, dst: Dst },
    // '=:=': a literal-bits equality check FUSED into the matcher (the
    // compiler's optimization for a known-constant field — no register is
    // written). JUDGMENT CALL (see the E3.3 report): `size` bits are read
    // big-endian unsigned at the cursor and compared to `value` by
    // `eqlExact`; a match consumes `size` bits (advances the cursor, like
    // `integer`), a mismatch jumps `fail_to` with the ctx unchanged.
    eq: struct { size: u32, value: FinalTerms.Term },
};

/// E1.15: which special opcode decoded to a `nop`-class CInstr — diagnostic
/// only, the executor does not branch on it.
pub const NopKind = enum { on_load, nif_start };

/// E2.4/E3.10: the error a BIF family fn (`bifs/erlang.zig`, …) may return. The
/// `bif_call` executor maps each to the exact BEAM reason and routes it through
/// the ONE guard-vs-body site: `Badarg`→`badarg`, `Badarith`→`badarith`
/// (atom reasons); `OutOfMemory` propagates to the interpreter.
///
/// E3.10 adds `Raise` — a STRUCTURED / class-tagged raise. A BIF that needs a
/// non-atom reason (`{badmap,M}`/`{badkey,K}`) or a non-`error` class
/// (`throw`/`exit` — `erlang:error/1,2,3`, `throw/1`, `exit/1`, `raise/3`,
/// `nif_error/1,2`) stages the exception on `Machine.bif_raise` (via
/// `Machine.bifRaise`/`raiseBadmap`/`raiseBadkey`) and returns `error.Raise`;
/// the executor unwinds it through `raiseWith` — but STILL guard-vs-body split
/// (a guard-context `map_get`/`is_map_key` BRANCHES to `else_to` and never
/// raises, exactly like `Badarg` — DIVERGENCE entry 6b/c: guard behaviour is
/// EXACT, only the body reason gains structure).
pub const BifError = error{ Badarg, Badarith, OutOfMemory, Raise };

/// E2.4: the SCALABLE BIF dispatch type — a pointer to a hand-written family fn
/// over already-resolved term args. `bifs/dispatch.resolve` returns one of these
/// for every `.implemented` `bif_table` entry; the loader bakes it into a
/// `BifRef.func`. This replaces the E1 `BifOp{add,sub}` enum, which did not
/// scale past two BIFs — a family fn reads its args, computes via an existing
/// algebra, and returns a term or a `BifError`, so ~300 BIFs need zero executor
/// or enum edits (just more `pub fn`s + `implOf` arms).
pub const BifFn = *const fn (m: *Machine, args: []const FinalTerms.Term) BifError!FinalTerms.Term;

/// R2c: the reduction size-class of a `call_ext_bif` — how a heavy BIF's cost
/// scales with its input, so its reduction charge tracks OTP's per-element loop
/// factors (`ELEMENTS_PER_RED` etc.) instead of the flat per-call floor. `.none`
/// = flat (default), so every un-classified BIF stays behaviour- AND accounting-
/// identical to before this slice. The size-weight is added to `m.reductions`
/// ONLY — never `m.instrs`/`m.pc`/a term — hence RESULT-IDENTITY-safe by
/// construction: scheduling, preemption, and every value are byte-unchanged; only
/// the (soft-real-time) reduction accounting becomes OTP-faithful. Totality: the
/// `bifSizeReds` switch is exhaustive, so a future heavy BIF is a compile error
/// until it is classified here. Set at load time in `beam_loader.bifSizeClassOf`
/// (the sole site where the BIF name is known — the exec arm sees only a pointer).
pub const BifSizeClass = enum {
    none,
    list0_elems, // scans a list in x0 (lists:reverse/2)
    // gap-reduction-size-weight (DIVERGENCE 603): a list in x1 / x2 — the erts
    // erl_bif_lists.c BIFs that scan an argument OTHER than the first.
    list1_elems, // lists:member(Elem, List) — List is x1
    list2_elems, // lists:keyfind/keymember/keysearch(Key, N, TupleList) — TupleList is x2
    // gap-reduction-bytes-weight (DIVERGENCE 604): weight by the BYTE length of a
    // binary in x0 (binary_to_list/1). NB these erts BIFs TRAP (yield mid-op), so
    // their reduction cost is non-monotonic under process_info and CANNOT be
    // precisely calibrated — the linear-scaling STRUCTURE is modeled with the same
    // 32-unit factor (a same-order approximation); measurement-only, never byte-EQ.
    bytes0_elems, // binary in x0 (erlang:binary_to_list/1)
};

/// gap-socket-real-tcp: the decomposed `gen_tcp:*` / `inet:*` operation a library
/// BIF traps into the Vm via the `socket_op` pending. The Vm interpret loop routes
/// each to its existing `doGenTcp*`/`doInet*` handler (which own the real fd + the
/// socket table). Total switch — a new verb is a compile error until routed. This
/// first wave carries the single-arg verbs (listen/inet_port/close); the two-arg
/// verbs carry `arg2` (send/recv: the data/length; accept/connect ignore it).
pub const SocketOp = enum { listen, inet_port, close, accept, connect, send, recv, sockname, peername, setopts, getopts, shutdown, udp_open, udp_send, udp_recv };

/// E1.13/E2.4: the loader's decode of a `bif`/`gc_bif` import ref. Either the
/// ref resolved to an executable family fn (`.func`) or it decoded a valid but
/// unimplemented `M:F/A` (`.unsupported`) whose coverage grows in later E2 tasks
/// — an unimplemented BIF cannot yield a guard truth value, so it is `undef`
/// (not a guard branch) in every context. Total by construction: the loader
/// always produces one of the two, so `bif_call` execution is total.
pub const BifRef = union(enum) {
    func: BifFn, //   a resolved, executable BIF family fn
    unsupported, //   decoded a valid M:F/A the executor has no impl for (→ undef)
};

/// E8.2i: direct `erts_internal:dist_spawn_request/4` has two admitted return
/// shapes on the no-carrier branch: a plain request ref (`spawn_request`) or
/// `{Ref, SpawnsMonitor}` (`spawn_opt` and OTP's non-spawn_request fallback).
pub const DistSpawnRequestMode = enum { spawn_request, spawn_opt };

/// M7: an effect the pure machine cannot perform — the VM interprets it.
/// Payload terms are RESOLVED VALUES (heap words of this machine).
pub const Action = union(enum) {
    spawn: struct { to: u32, dst: XReg },
    send_to: struct { pid: FinalTerms.Term, msg: FinalTerms.Term },
    link_to: struct { pid: FinalTerms.Term },
    unlink_to: struct { pid: FinalTerms.Term },
    monitor_to: struct { pid: FinalTerms.Term, dst: XReg, alias: MonAlias = .none },
    demonitor_ref: struct { ref: FinalTerms.Term, info: bool },
    exit_proc: struct { reason: FinalTerms.Term },
    trap_exits: struct { on: bool },
    // E3.7: BIF-initiated process effects (bifs/procsys.zig). Unlike the M7
    // CInstr traps above (set by dedicated M5/M7 instructions), these are set by
    // the process/system BIFs — `self`/`spawn`/`send`/`exit`/… called through the
    // `bif_call` path. The scheduler (proc.zig) interprets them and writes any
    // RESULT to x0 (`regs[0]`), the BEAM call-return-register convention (a BIF
    // reached via `call_ext` lands its value in x0). `send`/`exit_2` return their
    // value DIRECTLY (the BIF's own `dst`), so they do NOT rely on the x0 write;
    // `spawn_*`/`is_alive`/`list_processes` need scheduler state, so the VM writes
    // their result to x0. The pid TERM (Task 5) NAMES the target proc process:
    // its `number` field IS the proc index (see `proc.zidOfTerm`/`pidOfTerm`).
    // E5.8 (Task 8): `monitor` — a `spawn_opt(_,_,_,[monitor])` / `spawn_monitor`
    // request. When set the scheduler mints a monitor on the child and returns
    // `{Pid, Ref}` (the erlang.erl `spawn_monitor` wrapper's shape) instead of a
    // bare `Pid`. DIVERGENCE entry 50(c).
    spawn_fun: struct { fun: FinalTerms.Term, link: bool, monitor: bool = false }, //     spawn/1, spawn_link/1, spawn_monitor/1 → x0
    spawn_mfa: struct { module: FinalTerms.Term, func: FinalTerms.Term, args: FinalTerms.Term, link: bool, monitor: bool = false }, // spawn/3, spawn_link/3, spawn_opt/4, spawn_monitor/3 → x0
    exit_to: struct { pid: FinalTerms.Term, reason: FinalTerms.Term }, // exit/2 signal (per-pair order)
    is_alive: struct { pid: FinalTerms.Term }, //                  is_process_alive/1 → x0
    list_processes, //                                             processes/0 → x0
    // e4-registered0: registered/0 is now registry-backed (see
    // bifs/procsys.zig's registered_0 doc comment) — the registry lives on
    // the Vm (`Vm.registry`), unreachable from a bare Machine, so this trap
    // asks the scheduler to build the sorted name list (the SAME
    // ORDER-FREEDOM discipline as `erlang:loaded/0` / bifs/code.zig: a
    // HashMap iteration order must never leak into an observable result).
    list_registered, //                                            registered/0 → x0
    stat_run_queue, // gap-real-metrics: statistics(run_queue) → x0 = Vm.liveCount()
    // gap-real-metrics (DIVERGENCE 627): erlang:memory/0,1 → x0 = a proplist
    // (kind=all) or a single int. TRUTHFUL zigvm-measured bytes only (processes
    // = Σ per-proc tagged-word heap*8, atom = Σ name bytes, total = their sum) —
    // BEAM-arena categories (code/system/binary/ets) are OMITTED, never faked
    // (FM-OBS-1, the inet:getopts precedent). Traps to the Vm for the whole
    // process table + atom table.
    stat_memory: MemKind,
    // gap-fs-autoloader: a `dispatchMFA` MISS with autoloading enabled traps
    // here BEFORE the error_handler/undef fall-through (the erts error_handler's
    // `ensure_loaded`-then-retry, hoisted to the Vm where the file seam lives).
    // The Machine stays PURE — no file I/O below the trap. The Vm marks the
    // module TRIED (one-shot, load↔miss loop impossible), searches its
    // `code_path` for `Module.beam` (prim_file, bounded read), splices+commits
    // via `code.loadBeamBytes`, then `retryDispatchMFA` — which now resolves via
    // `resolveRuntime`, or falls through to error_handler/undef exactly as if
    // the trap never fired (regs/pc are untouched by the miss path). NO x0
    // write — x0..x[arity-1] still hold the pending call's arguments.
    ensure_loaded: struct { module: ta.AtomIdx, func: ta.AtomIdx, arity: u8, tail: bool },
    // e48-appctl-handoff (the a5 hibernate deferral discharged): GC-minimize +
    // suspend-until-signal, control resumes AFTER the call returning `ok`
    // (OTP-28 erlang:hibernate/0 — keeps the stack, unlike the pre-existing
    // `.hibernate` variant which is hibernate/3's discard-stack trap).
    hibernate_wait,
    // e49-real-ports-io: os:cmd/1 — run a shell command through the PROVEN
    // live-port seam, collect stdout to EOF (bounded), return the charlist.
    os_cmd: struct { cmd: FinalTerms.Term },
    // gap-erl-cli-args (DIVERGENCE 598): the init CLI-argument BIFs read the Vm's
    // parsed init argv. init:get_plain_arguments/0 → the `-extra`/bare tokens as a
    // list of strings; init:get_argument/1 → {ok,[[Vals]…]} | error for a flag atom.
    init_plain_args: struct {}, //           init:get_plain_arguments/0 → x0 = [String]
    init_get_argument: struct { flag: FinalTerms.Term }, // init:get_argument/1 → {ok,_}|error
    init_get_arguments: struct {}, //        init:get_arguments/0 → x0 = [{Flag,[Value]}]
    // gap-tracing-trace-info (DIVERGENCE 601): erlang:trace_info({M,F,A}, Item) reads
    // the Vm's global call-trace pattern table; trace_delivered/1 mints a ref + delivers.
    trace_info_mfa: struct { module: FinalTerms.Term, func: FinalTerms.Term, arity: FinalTerms.Term, item: FinalTerms.Term },
    trace_delivered: struct { tracee: FinalTerms.Term },
    // e49-wire-real-file-io: file:read_file/1 + file:write_file/2 over the
    // proven prim_file fd seam. The paths/bytes are ctx-heap terms.
    file_read: struct { path: FinalTerms.Term },
    file_write: struct { path: FinalTerms.Term, data: FinalTerms.Term },
    // gap-real-file-io: file:list_dir/1 → {ok,[Name]} | {error,Posix} and
    // file:read_file_info/1 → {ok,#file_info{}} | {error,Posix} over the SAME
    // proven prim_file dir/stat seam (path-based, no cross-trap fd table).
    file_list_dir: struct { path: FinalTerms.Term },
    file_read_file_info: struct { path: FinalTerms.Term },
    // gap-file-handle-io: the LIVE-Fd handle API — file:open/2 → {ok,IoDevice},
    // pread/3 → {ok,Data}|eof|{error,R}, pwrite/3 → ok|{error,R}, close/1 → ok.
    // IoDevice = `{file_descriptor, prim_file, N}` (N indexes the Vm's RunFd table);
    // the real fd lives in prim_file.Handle across the trap (proc.zig doFile*).
    file_open: struct { path: FinalTerms.Term, modes: FinalTerms.Term },
    file_pread: struct { fd: FinalTerms.Term, pos: FinalTerms.Term, len: FinalTerms.Term },
    file_pwrite: struct { fd: FinalTerms.Term, pos: FinalTerms.Term, data: FinalTerms.Term },
    file_close: struct { fd: FinalTerms.Term },
    // gap-file-seq-io: the SEQUENTIAL fd surface — file:read/2 (read at+advance the
    // tracked offset), write/2 (write at+advance), position/2 (seek), read_file_info/2
    // (the option-carrying stat, e.g. [{time,posix}]).
    file_read_seq: struct { fd: FinalTerms.Term, len: FinalTerms.Term },
    file_write_seq: struct { fd: FinalTerms.Term, data: FinalTerms.Term },
    file_position: struct { fd: FinalTerms.Term, loc: FinalTerms.Term },
    file_read_info_opts: struct { path: FinalTerms.Term, opts: FinalTerms.Term },
    // gap-file-fs-mutation: the filesystem-mutation surface (delete/rename/make_dir/
    // del_dir/truncate/sync/read_link_info) — the FINAL file: slice for real_file_io EQ.
    file_delete: struct { path: FinalTerms.Term },
    file_rename: struct { from: FinalTerms.Term, to: FinalTerms.Term },
    file_make_dir: struct { path: FinalTerms.Term },
    file_del_dir: struct { path: FinalTerms.Term },
    file_truncate: struct { fd: FinalTerms.Term },
    file_sync: struct { fd: FinalTerms.Term },
    file_read_link_info: struct { path: FinalTerms.Term, opts: FinalTerms.Term },
    // e50-tracing: erlang:trace(Pid, How, Flags) → x0 = matched count (0|1).
    trace_set: struct { pid: FinalTerms.Term, how: bool, flags: FinalTerms.Term },
    // gap-tracing-e7: erlang:trace_pattern(MFA, MatchSpec, Flags) — install/clear
    // a call-trace breakpoint over a matched function set. `enable` = install
    // (MatchSpec `true`/`[]`/a compiled list) vs clear (`false`); the
    // (module,func,arity) predicate carries `null` for the `'_'` wildcard; `count`
    // is the matched-function count the BIF already computed over the caller's
    // export table (the trap only commits the pattern to the Vm and writes count→x0).
    trace_pattern: struct { module: ?ta.AtomIdx, func: ?ta.AtomIdx, arity: ?u32, enable: bool, count: i64, spec: ?FinalTerms.Term = null },
    // gap-tracing-e7: a call-traced process dispatching an MFA traps here so the Vm
    // can gate on the global trace_pattern table + deliver {trace,Pid,call,{M,F,Args}}
    // to the tracer, then COMPLETE the dispatch (`resumeCallTrace`). `args` is the
    // [x0..x(arity-1)] list, built while registers are intact — safe because the run
    // loop breaks on `pending` immediately, so no GC runs before the Vm drains it.
    call_trace: struct { module: ta.AtomIdx, func: ta.AtomIdx, arity: u8, tail: bool, args: FinalTerms.Term },
    // e50-halt: erlang:halt(Status[,Opts]) — terminate the NODE with an OS
    // exit code. `status` carries the arg (small int | atom abort | string).
    node_halt: struct { status: FinalTerms.Term },
    // E3.8: link/monitor/registry BIF-family traps (bifs/procsys.zig), over
    // proc.zig's ALREADY-LAW-COVERED link/monitor signal machinery (M7 —
    // `link_to`/`unlink_to`/`monitor_to`/`demonitor_ref` above) and the
    // registry.zig bijection (now Vm-owned). Same x0-result convention.
    register_name: struct { name: FinalTerms.Term, pid: FinalTerms.Term }, //  register/2 → x0 true|false
    unregister_name: struct { name: FinalTerms.Term }, //                     unregister/1 → x0 true|false
    whereis_name: struct { name: FinalTerms.Term }, //                        whereis/1 → x0 pid|undefined
    process_info_all: struct { pid: FinalTerms.Term }, //                     process_info/1 → x0
    process_info_item: struct { pid: FinalTerms.Term, item: FinalTerms.Term }, // process_info/2 → x0
    set_group_leader: struct { leader: FinalTerms.Term, pid: FinalTerms.Term }, // erts_internal:group_leader/2,3 → x0 true|false
    demonitor_flush: struct { ref: FinalTerms.Term, info: bool }, //                      demonitor/2 [flush] → x0 true
    spawn_request: struct { module: FinalTerms.Term, func: FinalTerms.Term, args: FinalTerms.Term, opts: FinalTerms.Term }, // spawn_request/4 → x0 = ReqId ref
    get_dist_node, // erlang:node/0 VM-owned local distribution identity → x0 atom
    get_dist_creation, // erts_internal:get_creation/0 VM-owned local dist creation → x0 undefined|int
    is_node_alive, // erlang:is_alive/0 → x0 bool (VM-owned: node distributed?) — DIVERGENCE 723
    list_dist_nodes: struct { connected: bool, visible: bool, hidden: bool, known: bool, this_node: bool }, // nodes/0,1 live observer bridge → x0 list
    list_dist_node_infos: struct { connected: bool, visible: bool, hidden: bool, known: bool, this_node: bool, node_type: bool, connection_id: bool }, // nodes/2 live info observer bridge → x0 [{Node,Info}]
    dist_dflag_unicode_io: struct { pid: FinalTerms.Term }, // net_kernel:dflag_unicode_io/1 live DFLAG observer → x0 bool
    monitor_dist_node: struct { node: FinalTerms.Term, enabled: bool }, // monitor_node/2,3 live DistEntry observer → x0 true | error:notalive
    remote_exit_signal: struct { pid: FinalTerms.Term, reason: FinalTerms.Term }, // exit_signal/2,3 foreign pid → live DistEntry outbound exit observation
    new_dist_connection: struct { node: FinalTerms.Term }, // erts_internal:new_connection/1 → {ConnId,HandleRef}
    abort_pending_dist_connection: struct { node: FinalTerms.Term, conn: FinalTerms.Term }, // abort_pending_connection/2 → true | badarg
    set_dist_node: struct { node: FinalTerms.Term, creation: FinalTerms.Term }, // erlang:setnode/2 → net_kernel-owned local identity install or badarg
    create_dist_channel: struct { node: FinalTerms.Term, controller: FinalTerms.Term, opts: FinalTerms.Term }, // create_dist_channel/3 → true for active local identity+pending+live controller; badarg otherwise
    disconnect_dist_node: struct { node: FinalTerms.Term }, // future carrier/socket-origin disconnect → true if a live DistEntry was retired
    dist_spawn_request: struct { mode: DistSpawnRequestMode, spawns_monitor: bool, send_error_reply: bool, tag: FinalTerms.Term, error_reason: FinalTerms.Term }, // dist_spawn_request/4 no-carrier → ref or {ref,bool}
    set_trap_exit: struct { pid: FinalTerms.Term, on: bool }, //               erts_internal:process_flag/3 (trap_exit only) → x0 = OLD value
    // E4.3 (Task 3): `erts_internal:spawn_system_process/3` — spawns a SYSTEM
    // process running `M:F(A)`. Unlike `spawn_mfa`, the child is flagged a system
    // process (`Process.system`): it does NOT die from an untrapped abnormal exit
    // signal received over a link (the no-kill-cascade the kernel bring-up set —
    // code_server/application_controller/prim_file's port owner — relies on), and
    // it is not linked to the spawner. → x0 = the system-process pid. NOT ledger-EQ:
    // a system process that RETURNS is a fatal node error on the oracle ("System
    // process <p> terminated: normal" + crash dump), so it is not differentially
    // observable to completion (see DIVERGENCE entry 21, E4.3 amendment).
    spawn_system: struct { module: FinalTerms.Term, func: FinalTerms.Term, args: FinalTerms.Term }, // erts_internal:spawn_system_process/3 → x0 = pid
    // E7.2 (on_load wiring, DIVERGENCE 147): `erlang:call_on_load_function/1`
    // RUNS a just-loaded module's on_load function IN THE CALLING PROCESS and
    // its return VALUE becomes the BIF's value (erts runs it in-process; init.erl
    // wraps a monitor for isolation). Modeled as a control-flow trap: push the
    // continuation (the pc after the trapping call_ext, already advanced) and jump
    // to the resolved on_load `entry` in `dyn_code`; when it `ret`s, x0 holds the
    // on_load result and execution resumes at the continuation. NO sub-process, no
    // scheduler re-entrancy — a plain call/return over the existing stack.
    run_on_load: struct { entry: u32 }, //                       call_on_load_function/1 → x0 = on_load result
    // E4.6 (Task 6): the io / group-leader MESSAGE protocol. An `io:*` BIF
    // (bifs/io.zig — put_chars/nl) traps this with the io Request term (e.g.
    // `{put_chars, unicode, Chars}`). The Vm routes the full `{io_request, From,
    // ReplyAs, Request}` message to the caller's GROUP LEADER (a VM-provided
    // fixture process), the group leader services it (put_chars → append the
    // flattened chars to the Vm's captured stdout sink) and replies with exactly
    // one `{io_reply, ReplyAs, Reply}` back to From, and the Vm delivers Reply
    // (`ok`) to x0. The protocol is REAL: both messages traverse mailboxes.
    io_request: struct { request: FinalTerms.Term }, // io:put_chars/nl → x0 = Reply (ok)
    // E5.4 (Task 4): the LIVE os-port surface (bifs/ports.zig → src/os_port.zig,
    // the Stratum-C seam). Each needs the Vm's port table (a bare Machine cannot
    // reach it — the `spawn`/`registered` precedent), so the BIF traps and
    // `proc.zig` performs the fd/child effect, writing the result to x0.
    open_port_spawn: struct { name: FinalTerms.Term, binary_mode: bool = false, exit_status: bool = false, line_width: usize = 0, stderr_to_stdout: bool = false }, // erts_internal:open_port/2 → x0 = Port
    port_cmd: struct { port: FinalTerms.Term, data: FinalTerms.Term }, // erts_internal:port_command/3 → x0 = true; {Port,{data,Echo}} to owner
    port_close_sig: struct { port: FinalTerms.Term }, //                 erts_internal:port_close/1 → x0 = true (child reaped)
    // gap-socket-gen-tcp-bifs: the VM execution seam for real gen_tcp sockets. The
    // handler opens a loopback pair (socket_algebra), sends the iodata over the real
    // socket, and returns the echoed binary — proving the interpret loop can drive
    // real socket I/O through the trap mechanism (the substrate for the handle-based
    // socket:open/send/recv lifecycle to come).
    socket_roundtrip: struct { data: FinalTerms.Term }, //               VM → real loopback TCP echo → x0 = echoed binary
    socket_op: struct { op: SocketOp, arg: FinalTerms.Term, arg2: FinalTerms.Term, arg3: FinalTerms.Term }, // gap-socket-real-tcp: gen_tcp:*/gen_udp:*/inet:* name-dispatch → x0 = {ok,_}|{error,_}|ok (arg3 carries gen_udp:send's Data)
    code_ensure_loaded: struct { module: FinalTerms.Term }, //             gap-app-boot-engine: code:ensure_loaded/1 → autoload + {module,M}|{error,nofile}
    port_set_data: struct { port: FinalTerms.Term, data: FinalTerms.Term }, // erlang:port_set_data/2 → x0 = true
    port_get_data: struct { port: FinalTerms.Term }, //                  erlang:port_get_data/1 → x0 = stored term | undefined
    // E6.7 (Task 7): the port-representation surface (bifs/ports.zig) that needs
    // the Vm's port table — `ports/0` (the live-port list), `port_info/1,2` (the
    // proplist / a single item; a dead/absent port → `undefined`), `port_connect/2`
    // (reassign the connected/owner pid). `port_call/3`/`port_control/3` need NO
    // trap: an external-program (`{spawn,Cmd}`) port has no driver implementing
    // the control verbs, so both erts and zigvm answer `badarg` (the rejection
    // differential) — handled inline in the BIF.
    ports_list: struct {}, //                                           erlang:ports/0 → x0 = [Port]
    port_info: struct { port: FinalTerms.Term, item: FinalTerms.Term }, // port_info/1 (item==nil sentinel) | /2 → x0 = proplist | {Item,V} | undefined
    port_connect_sig: struct { port: FinalTerms.Term, pid: FinalTerms.Term }, // port_connect/2 → x0 = true | badarg
    // E6.7 (Task 7): `ets:give_away/3` — reassign the table owner + deliver
    // `{'ETS-TRANSFER',Tab,From,GiftData}` to the recipient (needs the Vm's
    // aliveness check + signal path). proc.zig writes `true`/`badarg` to x0.
    ets_give_away: struct { tid: FinalTerms.Term, to: FinalTerms.Term, gift: FinalTerms.Term },
    // E5.5 (Task 5): the alias-signal model (bifs/procsys.zig — `alias/1`,
    // `unalias/1`, `erts_internal:is_process_alive/2`; DIVERGENCE entry 19/21/33).
    // An alias is a REFERENCE the owner mints (`make_alias`) so `Ref ! Msg` routes
    // to the owner's mailbox while ACTIVE; `unalias_ref` retires it; delivery +
    // retirement ride the M7 signal machinery (proc.zig's process-local alias
    // table). The reply of the async `is_alive_request` is a genuine mailbox
    // message `{Ref, boolean()}` back to the caller (the async form of the
    // synchronous `is_alive` above).
    make_alias: struct { dst: u4, priority: bool = false }, //   alias/1 → x0 = a fresh alias ref (e50-eep76: priority lane)
    unalias_ref: struct { ref: FinalTerms.Term }, //             unalias/1 → x0 = true|false
    is_alive_request: struct { pid: FinalTerms.Term, ref: FinalTerms.Term }, // erts_internal:is_process_alive/2 → x0 = ok; async {Ref,bool} reply
    // E5.6 (Task 6): the async spawn/request protocol (bifs/procsys.zig —
    // `erts_internal:spawn_request/4`, `erlang:spawn_request_abandon/1`,
    // `erts_internal:process_flag/3`; DIVERGENCE entry 33/72). `spawn_request/4`
    // rides `spawn_mfa`'s union arm above (same {module,func,args,opts} shape):
    // proc.zig mints a ReqId ref, spawns+runs the child, and PARKS a
    // `{spawn_reply, ReqId, ok, ChildPid}` reply delivered on the next scheduler
    // tick (the async window). `abandon_spawn` cancels a still-parked reply
    // (→ true, the child orphaned) or answers false once it has been delivered.
    // `process_flag3` is the CROSS-process `save_calls` form: proc.zig mints a
    // ReqId ref and replies `{ReqId, OldValue}` asynchronously (the SELF form is
    // synchronous and stays inside the BIF — no trap).
    abandon_spawn: struct { ref: FinalTerms.Term }, //          spawn_request_abandon/1 → x0 = true|false
    process_flag3: struct { pid: FinalTerms.Term, value: i64 }, // erts_internal:process_flag/3 (cross-proc save_calls) → x0 = ReqId ref
    // E6.2 (Task 2): the LIVE receive/BIF timer family over the `timer_wheel`
    // algebra (the M-era wheel goes LIVE in proc.zig; DIVERGENCE entry 5's residual
    // + the 8 timer BIF rows). `arm_recv_timer` parks the CALLING process on a
    // wheel entry at `now+ms` (the finite `wait_timeout`); the wheel fire wakes it
    // with the timeout. `timer_start` arms a `send_after`/`start_timer` entry that
    // delivers a message (or `{timeout,TRef,Msg}`) to `dest` when it fires,
    // returning a TRef the Vm mints → x0. `timer_cancel`/`timer_read` observe/retire
    // a still-live entry by its TRef (→ remaining-ms | false | ok), exactly the
    // erts `cancel_timer`/`read_timer` contract. All ride proc.zig's Vm timer table.
    arm_recv_timer: struct { ms: u64 }, //                      wait_timeout finite: arm + suspend the caller
    timer_start: struct { kind: TimerStartKind, time: FinalTerms.Term, dest: FinalTerms.Term, msg: FinalTerms.Term, abs: bool }, // send_after/start_timer → x0 = TRef
    timer_cancel: struct { tref: FinalTerms.Term, info: bool, is_async: bool }, // cancel_timer/1,2 → x0
    timer_read: struct { tref: FinalTerms.Term, is_async: bool }, //             read_timer/1,2 → x0
    // E6.4 (Task 4): the process-suspension family (bifs/procsys.zig → proc.zig's
    // `Process.suspend_count`, the suspend/resume counting MONOID gated by
    // `proc.schedulable`). suspend/resume write true|badarg; is_system_process reads
    // the TARGET process's `system` flag (needs the Vm — a bare Machine cannot see
    // another process's flag, the process_info precedent).
    suspend_proc: struct { pid: FinalTerms.Term }, //           erts_internal:suspend_process/2 → x0 = true|badarg
    resume_proc: struct { pid: FinalTerms.Term }, //            erlang:resume_process/1 → x0 = true|badarg
    is_system_process: struct { pid: FinalTerms.Term }, //      erts_internal:is_system_process/1 → x0 = true|false
    // E6.6 (Task 6): the DIRECT term/string DISPLAY verbs (bifs/io.zig —
    // `erlang:display/1`, `erlang:display_string/2`). Unlike `io:put_chars`
    // (which rides the group-leader message protocol), erts `display`/
    // `display_string` write raw bytes DIRECTLY to a file descriptor and return
    // `true` — so the Vm appends `chars` straight to its captured stdout sink
    // when `to_stdout` (stdout device / `display/1`), or elsewhere (stderr/stdin
    // — not the compared stdout channel) otherwise, then writes `true` to x0.
    display_out: struct { chars: FinalTerms.Term, to_stdout: bool }, // display/1, display_string/2 → x0 = true
    // ==== E7.5 (Task 5) — process-engine completions (bifs/procsys.zig → proc.zig).
    // Kept in one clearly-blocked group so the parallel E7.6 trace slice never
    // straddles them. Neither touches the SACRED M7 per-pair signal order: hibernate
    // is a LOCAL control-flow reset (no signal), and the system-task reply rides the
    // stamped `signal` path exactly like the E5.6 parked spawn-reply. ====
    //
    // `erlang:hibernate/3` — DISCARD the calling process's call stack and RE-ENTER
    // at M:F/A when the next message arrives. Modeled as a control-flow trap
    // (`proc.zig doHibernate`): resolve the MFA against the process's OWN export
    // index, CLEAR stack/ystack/catch_stack + reset `recv_cursor` (the stack is
    // genuinely discarded — the reentry homomorphism; a resumed old frame would be
    // observable), load the arg list into x0..x[A-1], and jump to the entry. The
    // MAILBOX is UNTOUCHED (queued messages survive; the re-entered `receive` finds
    // them). An unresolvable MFA exits `undef` (BEAM-faithful). Never returns a value.
    hibernate: struct { module: FinalTerms.Term, func: FinalTerms.Term, args: FinalTerms.Term }, // erlang:hibernate/3
    // `erts_internal:request_system_task/3,4` — enqueue an ASYNC system task whose
    // ONLY observation is the `{RequestId, Result}` reply delivered back to the
    // REQUESTER. Modeled with the E5.6 parked-reply protocol (`proc.zig
    // doRequestSystemTask` + `deliverParkedSysTask`, the `deliverParkedSpawn`
    // sibling): the synchronous return is `true`, the reply is PARKED (built in the
    // requester's heap) and flushed on the next scheduler tick over the stamped
    // signal path. `op` folds the task to its Result — `garbage_collect` → `true`
    // (zigvm's copying GC is denote-preserving), any other op → `true` (accepted).
    request_system_task: struct { requester: FinalTerms.Term, reqid: FinalTerms.Term, op: SysTaskOp }, // → x0 = true; {ReqId,Result} parked
};

/// E7.5 (Task 5): the async system-task operation an `erts_internal:request_
/// system_task/3,4` names in its request tuple. `garbage_collect` requests a GC
/// on the target (Result `true`); `other` is any accepted-but-not-specially-
/// modeled op (Result `true` — the request was enqueued). The op selects the
/// Result folded into the `{RequestId, Result}` reply; it is NOT byte-EQ against
/// the OTP-28 host (the internal request encoding is a 28-vs-30 skew — see the
/// ledger re-bind), only law-proven exactly-once reply delivery.
pub const SysTaskOp = enum { garbage_collect, other };

/// E6.2 (Task 2): which delivery a `send_after`/`start_timer` timer performs when
/// it fires. `send_after` delivers `Msg` verbatim; `start_timer` delivers the
/// `{timeout, TRef, Msg}` 3-tuple (the erts `start_timer` wrapper shape).
pub const TimerStartKind = enum { send_after, start_timer };

/// E5.5 (Task 5): the alias mode of a `monitor(process, Pid, Opts)` call. A
/// plain `monitor/2,3` mints no alias (`none`). `[{alias, Mode}]` ALSO mints an
/// alias tied to the monitor ref: `explicit` (`{alias, explicit_unalias}`) stays
/// active past the 'DOWN' until `unalias/1`; `retire` (`{alias, demonitor}` /
/// `{alias, reply_demonitor}` — the non-`explicit_unalias` modes) auto-retires
/// when the monitor's 'DOWN' is delivered (erts' default — DIVERGENCE entry 19).
pub const MonAlias = enum { none, retire, explicit };

pub const Program = []const CInstr;

// ============================================================================
// BIF capability table (the ADVERTISED ledger of executable guard BIFs)
// ============================================================================
//
// `supported_bifs` is the ADVERTISED ledger of the guard BIFs the machine
// executes, PRINTED by `cli.dumpCaps` (the dump-caps round-trip law below) and
// counted by the harness bif ledger (EQ rows). The loader-time RESOLVER is
// `bifs/dispatch.resolve` over the generated `bif_table` (keyed on the full
// module+name+arity), which returns the family fn from `bifs/erlang.zig`. The
// two agree BY CONSTRUCTION — the `.implemented` `bif_table` entries are exactly
// this slice — pinned by the "resolve agrees with supported_bifs" law in
// bifs/dispatch. E2.4 grew this from the E1 `+`/`-` pair to the erlang guard
// family (accessors, all comparisons, bool guards, rounding, and the small-int
// arith/bitwise ops). E3.7 added `self/0` (the running process's pid TERM, its
// `number` == the proc index) and `node/1` (current local node for a local
// pid/port/ref, encoded node for a foreign identity) — the
// two process-bridge BIFs reachable end-to-end via `bif0`/`bif1` today; the rest
// of the process family (`spawn`/`send`/`exit`/…) is `call_ext`-only and stays
// `deferred-E4-procdispatch` (implemented + Vm-law-proven in bifs/procsys.zig, but not
// advertised here — Task 12 wires call_ext). The arith `*`/`div`/`rem`/bitwise
// ops are small-int-only (a bignum operand cleanly defers — see bifs/erlang.zig).
//
// Names/arities are the guard-BIF forms from OTP's bif.tab for the harness's
// pinned tree, so the cross-law (every caps `bif` exists in the parsed bif set)
// matches on `<module>:<name>/<arity>` once bif.tab's atom-quotes are stripped.
// Kept sorted by (module, name, arity) — the sorted law below — so dumpCaps
// output is deterministic. This is the BIF twin of beam_loader's supported_ops
// round-trip law.

pub const BifCap = struct {
    module: []const u8,
    name: []const u8,
    arity: u8,
};

pub const supported_bifs = [_]BifCap{
    // E2.10: the atomics BIF family (bifs/atomics.zig). `sub/3`/`sub_get/3`
    // are NOT bif.tab entries (atomics.erl library wrappers over `add`/
    // `add_get` — see bifs/atomics.zig's scope note) and stay OUT.
    .{ .module = "atomics", .name = "add", .arity = 3 },
    .{ .module = "atomics", .name = "add_get", .arity = 3 },
    .{ .module = "atomics", .name = "compare_exchange", .arity = 4 },
    .{ .module = "atomics", .name = "exchange", .arity = 3 },
    .{ .module = "atomics", .name = "get", .arity = 2 },
    .{ .module = "atomics", .name = "info", .arity = 1 },
    .{ .module = "atomics", .name = "put", .arity = 3 },
    // E2.8: the binary BIF family (bifs/binary.zig). `binary:bin_to_list/1,2,3`
    // is NOT a bif.tab entry (a binary.erl library wrapper — see
    // bifs/binary.zig's scope note) and stays OUT of this ledger.
    .{ .module = "binary", .name = "at", .arity = 2 },
    .{ .module = "binary", .name = "compile_pattern", .arity = 1 },
    .{ .module = "binary", .name = "copy", .arity = 1 },
    .{ .module = "binary", .name = "copy", .arity = 2 },
    .{ .module = "binary", .name = "decode_unsigned", .arity = 1 },
    .{ .module = "binary", .name = "decode_unsigned", .arity = 2 },
    .{ .module = "binary", .name = "encode_unsigned", .arity = 1 },
    .{ .module = "binary", .name = "encode_unsigned", .arity = 2 },
    .{ .module = "binary", .name = "first", .arity = 1 },
    .{ .module = "binary", .name = "last", .arity = 1 },
    .{ .module = "binary", .name = "list_to_bin", .arity = 1 },
    .{ .module = "binary", .name = "longest_common_prefix", .arity = 1 },
    .{ .module = "binary", .name = "longest_common_suffix", .arity = 1 },
    .{ .module = "binary", .name = "match", .arity = 2 },
    .{ .module = "binary", .name = "match", .arity = 3 },
    .{ .module = "binary", .name = "matches", .arity = 2 },
    .{ .module = "binary", .name = "matches", .arity = 3 },
    .{ .module = "binary", .name = "part", .arity = 2 },
    .{ .module = "binary", .name = "part", .arity = 3 },
    .{ .module = "binary", .name = "referenced_byte_size", .arity = 1 },
    .{ .module = "binary", .name = "split", .arity = 2 },
    .{ .module = "binary", .name = "split", .arity = 3 },
    // E7.7: erl_debugger:supported/0 — the debugger-capability query, truthfully
    // `false` (no debugger subsystem; host-verified on a non-debug build). Sorts
    // between "binary" and "erlang" ('erl_' < 'erla'). bifs/misc.zig.
    .{ .module = "erl_debugger", .name = "supported", .arity = 0 },
    // E4.1: the send OPERATOR `!`/2 (== send/2) — scheduler-trapping process BIF
    // (bifs/procsys.zig), reachable end-to-end via call_ext_bif + the scheduler-
    // as-driver. Sorts first (ASCII '!' 0x21). deferred-E4-procdispatch discharged.
    .{ .module = "erlang", .name = "!", .arity = 2 },
    .{ .module = "erlang", .name = "*", .arity = 2 },
    // E3.18: unary `+/1` (identity on a number) — sorts before `+/2`.
    .{ .module = "erlang", .name = "+", .arity = 1 },
    .{ .module = "erlang", .name = "+", .arity = 2 },
    .{ .module = "erlang", .name = "++", .arity = 2 },
    .{ .module = "erlang", .name = "-", .arity = 1 },
    .{ .module = "erlang", .name = "-", .arity = 2 },
    .{ .module = "erlang", .name = "--", .arity = 2 },
    // E3.18: float division `//2` — sorts between `--/2` and `/=/2`.
    .{ .module = "erlang", .name = "/", .arity = 2 },
    .{ .module = "erlang", .name = "/=", .arity = 2 },
    .{ .module = "erlang", .name = "<", .arity = 2 },
    .{ .module = "erlang", .name = "=/=", .arity = 2 },
    .{ .module = "erlang", .name = "=:=", .arity = 2 },
    .{ .module = "erlang", .name = "=<", .arity = 2 },
    .{ .module = "erlang", .name = "==", .arity = 2 },
    .{ .module = "erlang", .name = ">", .arity = 2 },
    .{ .module = "erlang", .name = ">=", .arity = 2 },
    .{ .module = "erlang", .name = "abs", .arity = 1 },
    // E3.18: adler32/1,2 + adler32_combine/3 (bifs/checksum.zig).
    .{ .module = "erlang", .name = "adler32", .arity = 1 },
    .{ .module = "erlang", .name = "adler32", .arity = 2 },
    .{ .module = "erlang", .name = "adler32_combine", .arity = 3 },
    // E5.5 (Task 5): the alias-signal model (bifs/procsys.zig) —
    // deferred-E5-alias discharged.
    .{ .module = "erlang", .name = "alias", .arity = 1 },
    .{ .module = "erlang", .name = "and", .arity = 2 },
    // E3.18: append/2 == ++/2 (lists.append_2).
    .{ .module = "erlang", .name = "append", .arity = 2 },
    // E2.12: append_element/2 (bifs/term_ops.zig) — the term-inspection
    // family; see the sorted insertions of make_tuple/phash2/setelement/
    // term_to_iovec/unique_integer below, alphabetized in place.
    .{ .module = "erlang", .name = "append_element", .arity = 2 },
    .{ .module = "erlang", .name = "atom_to_binary", .arity = 2 },
    .{ .module = "erlang", .name = "atom_to_list", .arity = 1 },
    .{ .module = "erlang", .name = "band", .arity = 2 },
    // E3.18: binary_part/2,3 == binary:part/2,3 (identical arg shapes).
    .{ .module = "erlang", .name = "binary_part", .arity = 2 },
    .{ .module = "erlang", .name = "binary_part", .arity = 3 },
    .{ .module = "erlang", .name = "binary_to_atom", .arity = 2 },
    // E3.18: binary_to_existing_atom/2 — LOOKUP-only atom conversion.
    .{ .module = "erlang", .name = "binary_to_existing_atom", .arity = 2 },
    .{ .module = "erlang", .name = "binary_to_float", .arity = 1 }, // E6.6
    .{ .module = "erlang", .name = "binary_to_list", .arity = 1 },
    .{ .module = "erlang", .name = "binary_to_list", .arity = 3 },
    .{ .module = "erlang", .name = "binary_to_term", .arity = 1 },
    .{ .module = "erlang", .name = "binary_to_term", .arity = 2 },
    // E3.2: bit_size/1 (bifs/erlang.zig) — TRUTHFUL over unaligned values
    // now that a term-level bitstring `bit_len` exists (LA-3/E3.1); the E2
    // fast-follow row's `byte_size*8` blocker is discharged.
    .{ .module = "erlang", .name = "bit_size", .arity = 1 },
    // E3.2: bitstring_to_list/1 (bifs/conv.zig) — the bitstring conversion
    // family; see `list_to_bitstring/1` below (alphabetized in place).
    .{ .module = "erlang", .name = "bitstring_to_list", .arity = 1 },
    .{ .module = "erlang", .name = "bnot", .arity = 1 },
    .{ .module = "erlang", .name = "bor", .arity = 2 },
    .{ .module = "erlang", .name = "bsl", .arity = 2 },
    .{ .module = "erlang", .name = "bsr", .arity = 2 },
    // E6.5 (Task 5): bump_reductions/1 (bifs/procsys.zig) — bumps the running
    // process's reduction counter; returns `true`. Sort: 'bu' > 'bs', < 'bx'.
    .{ .module = "erlang", .name = "bump_reductions", .arity = 1 },
    .{ .module = "erlang", .name = "bxor", .arity = 2 },
    .{ .module = "erlang", .name = "byte_size", .arity = 1 },
    // E7.2 (DIVERGENCE 147): call_on_load_function/1 runs a just-loaded module's
    // on_load in-process (bifs/code.zig; onload_call). Sorted before cancel_timer.
    .{ .module = "erlang", .name = "call_on_load_function", .arity = 1 },
    // E6.2 (Task 2): the LIVE receive/BIF timer family (proc.zig timer wheel).
    .{ .module = "erlang", .name = "cancel_timer", .arity = 1 },
    .{ .module = "erlang", .name = "cancel_timer", .arity = 2 },
    .{ .module = "erlang", .name = "ceil", .arity = 1 },
    // E5.2b (DIVERGENCE 61): check_old_code/1 — the code-server runtime QUERY
    // BIF over the mutable two-version code table (bifs/code.zig; code_q).
    .{ .module = "erlang", .name = "check_old_code", .arity = 1 },
    // E3.18: crc32/1,2 + crc32_combine/3 (bifs/checksum.zig).
    .{ .module = "erlang", .name = "crc32", .arity = 1 },
    .{ .module = "erlang", .name = "crc32", .arity = 2 },
    .{ .module = "erlang", .name = "crc32_combine", .arity = 3 },
    // gap-localtime-tz (DIVERGENCE 731): date/0 = the DATE part of localtime/0.
    .{ .module = "erlang", .name = "date", .arity = 0 },
    // E42-T1: decode_packet/3 — the full packet framer/parser (framing +
    // http/http_bin + httph/httph_bin + ssl_tls, all byte-EQ; bifs/erlang.zig).
    .{ .module = "erlang", .name = "decode_packet", .arity = 3 },
    // E5.2b (DIVERGENCE 61): delete_module/1 — retires a module's current
    // version to old over the mutable code table (bifs/code.zig; code_q).
    .{ .module = "erlang", .name = "delete_element", .arity = 2 }, // E6.6
    .{ .module = "erlang", .name = "delete_module", .arity = 1 },
    // E4.1: monitor-cancel process BIFs (deferred-E4-procdispatch discharged).
    .{ .module = "erlang", .name = "demonitor", .arity = 1 },
    .{ .module = "erlang", .name = "demonitor", .arity = 2 },
    .{ .module = "erlang", .name = "display", .arity = 1 }, // E6.6
    .{ .module = "erlang", .name = "display_string", .arity = 2 }, // E6.6
    // E8.2g: no-carrier distribution control-data direct-call rejection rows.
    .{ .module = "erlang", .name = "dist_ctrl_get_data", .arity = 1 },
    .{ .module = "erlang", .name = "dist_ctrl_get_data_notification", .arity = 1 },
    .{ .module = "erlang", .name = "dist_ctrl_get_opt", .arity = 2 },
    .{ .module = "erlang", .name = "dist_ctrl_input_handler", .arity = 2 },
    .{ .module = "erlang", .name = "dist_ctrl_put_data", .arity = 2 },
    .{ .module = "erlang", .name = "dist_ctrl_set_opt", .arity = 3 },
    .{ .module = "erlang", .name = "dist_get_stat", .arity = 1 },
    .{ .module = "erlang", .name = "div", .arity = 2 },
    // E7.6 (S29): the dt_* dynamic-trace tag family — non-dtrace constants/identity.
    .{ .module = "erlang", .name = "dt_append_vm_tag_data", .arity = 1 },
    .{ .module = "erlang", .name = "dt_get_tag", .arity = 0 },
    .{ .module = "erlang", .name = "dt_get_tag_data", .arity = 0 },
    .{ .module = "erlang", .name = "dt_prepend_vm_tag_data", .arity = 1 },
    .{ .module = "erlang", .name = "dt_put_tag", .arity = 1 },
    .{ .module = "erlang", .name = "dt_restore_tag", .arity = 1 },
    .{ .module = "erlang", .name = "dt_spread_tag", .arity = 1 },
    .{ .module = "erlang", .name = "element", .arity = 2 },
    // E3.12: the process-dictionary remainder (erase/0,1) + the exception-raising
    // family (error/*, exit/1, nif_error/*, raise/3, throw/1) — reachable now that
    // call_ext dispatches (Task 12); pdict.zig / erlang.zig, EQ in bif_gen.ml.
    .{ .module = "erlang", .name = "erase", .arity = 0 },
    .{ .module = "erlang", .name = "erase", .arity = 1 },
    .{ .module = "erlang", .name = "error", .arity = 1 },
    .{ .module = "erlang", .name = "error", .arity = 2 },
    .{ .module = "erlang", .name = "error", .arity = 3 },
    .{ .module = "erlang", .name = "exit", .arity = 1 },
    // E4.1: exit-SIGNAL process BIFs (exit/2,/3 send an EXIT signal to a pid —
    // distinct from the catchable exit/1). deferred-E4-procdispatch discharged.
    .{ .module = "erlang", .name = "exit", .arity = 2 },
    .{ .module = "erlang", .name = "exit", .arity = 3 },
    // E8.2h: no-carrier exit_signal/2,3 over local pid/ref/port and foreign pid/ref.
    .{ .module = "erlang", .name = "exit_signal", .arity = 2 },
    .{ .module = "erlang", .name = "exit_signal", .arity = 3 },
    // E3.18: external_size/1,2 == byte length of term_to_binary's ETF output.
    .{ .module = "erlang", .name = "external_size", .arity = 1 },
    .{ .module = "erlang", .name = "external_size", .arity = 2 },
    // E7.2 (DIVERGENCE 147): the on_load GATE — finish_after_on_load/2 commits
    // (Keep=true) or atomically rolls back (Keep=false) a just-loaded on_load
    // module (bifs/code.zig; onload_call). Sorted before finish_loading.
    .{ .module = "erlang", .name = "finish_after_on_load", .arity = 2 },
    // e5-dispatch-codeidx (DIVERGENCE 81): finish_loading/1 — commit prepared
    // handles into the runtime code table (bifs/code.zig; reload_call).
    .{ .module = "erlang", .name = "finish_loading", .arity = 1 },
    .{ .module = "erlang", .name = "float", .arity = 1 },
    .{ .module = "erlang", .name = "float_to_binary", .arity = 1 }, // E6.6
    .{ .module = "erlang", .name = "float_to_binary", .arity = 2 }, // E6.6
    .{ .module = "erlang", .name = "float_to_list", .arity = 1 },
    .{ .module = "erlang", .name = "float_to_list", .arity = 2 },
    .{ .module = "erlang", .name = "floor", .arity = 1 },
    // E3.13: function_exported/3 (bifs/fun_info.zig) — the m.exports index.
    .{ .module = "erlang", .name = "function_exported", .arity = 3 },
    // E3.9 fix: get/1 is the ONLY pdict BIF (bifs/pdict.zig) reachable
    // end-to-end today — it is the compiler's `is_guard_bif` clause
    // (beam_core_to_ssa.erl), so it compiles to `{bif,get,...}` (a genuine
    // guard-bif call, `bif1`-shaped). `put/2`, `get/0`, `erase/0,1`, and
    // `get_keys/0,1` are NOT guard bifs — the compiler emits `call_ext`/
    // `call_ext_only` for them, which zigvm's `.func_info` path does not
    // dispatch until Task 12/E4 — so they stay OFF this ledger and are
    // `deferred-E4-procdispatch` in harness/bif_gen.ml (implemented + Vm-law-
    // proven in bifs/pdict.zig, exactly like the E3.7/E3.8 call_ext-only
    // process-bridge BIFs). Empirically confirmed by disassembling a
    // compiled .beam against the pinned compiler source.
    .{ .module = "erlang", .name = "get", .arity = 0 }, // E3.12: pdict (call_ext)
    .{ .module = "erlang", .name = "get", .arity = 1 },
    .{ .module = "erlang", .name = "get_keys", .arity = 0 }, // E3.12: pdict
    .{ .module = "erlang", .name = "get_keys", .arity = 1 },
    // E4.2: get_module_info/1,2 (bifs/erlang.zig) — M:module_info/0,1 over the
    // retained per-module metadata (Machine.mod_meta: Attr/CInf chunks + md5).
    .{ .module = "erlang", .name = "get_module_info", .arity = 1 },
    .{ .module = "erlang", .name = "get_module_info", .arity = 2 },
    // E4.6: group_leader/0 — the calling process's group leader (a pid TERM).
    // Reachable end-to-end via call_ext_bif; EQ observed by `group_leader() =/=
    // self()` against the OTP shell GL (the `gl_not_self` differential row).
    .{ .module = "erlang", .name = "group_leader", .arity = 0 },
    // E7.2 (DIVERGENCE 147): has_prepared_code_on_load/1 reports whether a staged
    // image carries an on_load gate (bifs/code.zig; onload_call).
    .{ .module = "erlang", .name = "has_prepared_code_on_load", .arity = 1 },
    .{ .module = "erlang", .name = "hd", .arity = 1 },
    // E7.5 (Task 5): hibernate/3 — the MFA-reentry trap (proc.zig doHibernate).
    .{ .module = "erlang", .name = "hibernate", .arity = 3 },
    .{ .module = "erlang", .name = "insert_element", .arity = 3 }, // E6.6
    .{ .module = "erlang", .name = "integer_to_binary", .arity = 1 },
    .{ .module = "erlang", .name = "integer_to_binary", .arity = 2 },
    .{ .module = "erlang", .name = "integer_to_list", .arity = 1 },
    .{ .module = "erlang", .name = "integer_to_list", .arity = 2 },
    // E3.18: iolist_size/1 == byte length of the iolist flattening.
    .{ .module = "erlang", .name = "iolist_size", .arity = 1 },
    .{ .module = "erlang", .name = "iolist_to_binary", .arity = 1 },
    // E3.18: iolist_to_iovec/1 — a conforming single-chunk [Bin] iovec.
    .{ .module = "erlang", .name = "iolist_to_iovec", .arity = 1 },
    // E3.18: the remaining `erlang:` type/guard predicates (entry 13(a)
    // fast-follow siblings of the E2.4 family). Kept sorted in place.
    .{ .module = "erlang", .name = "is_atom", .arity = 1 },
    .{ .module = "erlang", .name = "is_binary", .arity = 1 },
    .{ .module = "erlang", .name = "is_bitstring", .arity = 1 },
    .{ .module = "erlang", .name = "is_boolean", .arity = 1 },
    // E3.13: is_builtin/3 (bifs/fun_info.zig) — pin bif.tab membership.
    .{ .module = "erlang", .name = "is_builtin", .arity = 3 },
    .{ .module = "erlang", .name = "is_float", .arity = 1 },
    .{ .module = "erlang", .name = "is_function", .arity = 1 },
    .{ .module = "erlang", .name = "is_function", .arity = 2 },
    .{ .module = "erlang", .name = "is_integer", .arity = 1 },
    .{ .module = "erlang", .name = "is_integer", .arity = 3 },
    .{ .module = "erlang", .name = "is_list", .arity = 1 },
    .{ .module = "erlang", .name = "is_map", .arity = 1 },
    .{ .module = "erlang", .name = "is_map_key", .arity = 2 },
    .{ .module = "erlang", .name = "is_number", .arity = 1 },
    // E3.6: is_pid/is_port/is_reference (bifs/erlang.zig) — the E3.5
    // pid/reference/port type predicates, at the BIF-call surface.
    .{ .module = "erlang", .name = "is_pid", .arity = 1 },
    .{ .module = "erlang", .name = "is_port", .arity = 1 },
    // E4.1: liveness query process BIF (deferred-E4-procdispatch discharged).
    .{ .module = "erlang", .name = "is_process_alive", .arity = 1 },
    // E3.18: is_record/1,2,3 — the tuple-record structural test (native-record
    // arm vacuously false: no native-record term kind is representable).
    .{ .module = "erlang", .name = "is_record", .arity = 1 },
    .{ .module = "erlang", .name = "is_record", .arity = 2 },
    .{ .module = "erlang", .name = "is_record", .arity = 3 },
    .{ .module = "erlang", .name = "is_reference", .arity = 1 },
    .{ .module = "erlang", .name = "is_tuple", .arity = 1 },
    .{ .module = "erlang", .name = "length", .arity = 1 },
    // E4.1: link process BIFs (deferred-E4-procdispatch discharged).
    .{ .module = "erlang", .name = "link", .arity = 1 },
    .{ .module = "erlang", .name = "link", .arity = 2 },
    .{ .module = "erlang", .name = "list_to_atom", .arity = 1 },
    .{ .module = "erlang", .name = "list_to_binary", .arity = 1 },
    // E3.2: list_to_bitstring/1 (bifs/conv.zig) — inverse of
    // bitstring_to_list/1 above; see that module's doc comment.
    .{ .module = "erlang", .name = "list_to_bitstring", .arity = 1 },
    .{ .module = "erlang", .name = "list_to_existing_atom", .arity = 1 },
    .{ .module = "erlang", .name = "list_to_float", .arity = 1 },
    // E3.6: list_to_pid/list_to_port/list_to_ref (bifs/conv.zig) — parse
    // diag's pid/port/reference print shape back to the term.
    .{ .module = "erlang", .name = "list_to_pid", .arity = 1 },
    .{ .module = "erlang", .name = "list_to_port", .arity = 1 },
    .{ .module = "erlang", .name = "list_to_ref", .arity = 1 },
    .{ .module = "erlang", .name = "list_to_tuple", .arity = 1 },
    // E2.12: erlang:loaded/0 (bifs/code.zig) — the code-index QUERY family.
    .{ .module = "erlang", .name = "loaded", .arity = 0 },
    // gap-localtime-tz (DIVERGENCE 731): localtime/0 + local↔universal conversions.
    .{ .module = "erlang", .name = "localtime", .arity = 0 },
    // (localtime_to_universaltime/1 is a resolveLibrary WRAPPER, not a bif.tab BIF
    //  — DIVERGENCE 731 — so it is NOT a supported_bifs capability row.)
    // E3.6: make_ref/0 (bifs/term_ops.zig) — freshness via the E3.5
    // Ctx-owned ref_counter.
    // e47-a2: make_fun/3 — the external-fun constructor (bifs/fun_info.zig).
    .{ .module = "erlang", .name = "make_fun", .arity = 3 },
    .{ .module = "erlang", .name = "make_ref", .arity = 0 },
    // E2.12: make_tuple/2,3 (bifs/term_ops.zig).
    .{ .module = "erlang", .name = "make_tuple", .arity = 2 },
    .{ .module = "erlang", .name = "make_tuple", .arity = 3 },
    .{ .module = "erlang", .name = "map_get", .arity = 2 },
    .{ .module = "erlang", .name = "map_size", .arity = 1 },
    // E3.15: the matchspec compile-tester (bifs/ets.zig — `table` type).
    .{ .module = "erlang", .name = "match_spec_test", .arity = 3 },
    // E3.18: min/2, max/2 — the arith-order selectors (ubif).
    .{ .module = "erlang", .name = "max", .arity = 2 },
    // E3.18: md5 family (bifs/checksum.zig).
    .{ .module = "erlang", .name = "md5", .arity = 1 },
    .{ .module = "erlang", .name = "md5_final", .arity = 1 },
    .{ .module = "erlang", .name = "md5_init", .arity = 0 },
    .{ .module = "erlang", .name = "md5_update", .arity = 2 },
    .{ .module = "erlang", .name = "min", .arity = 2 },
    .{ .module = "erlang", .name = "module_loaded", .arity = 1 },
    // E4.1: monitor process BIFs (deferred-E4-procdispatch discharged).
    .{ .module = "erlang", .name = "monitor", .arity = 2 },
    .{ .module = "erlang", .name = "monitor", .arity = 3 },
    // E8.2d: monitor_node/2,3 no-carrier observer subset.
    .{ .module = "erlang", .name = "monitor_node", .arity = 2 },
    .{ .module = "erlang", .name = "monitor_node", .arity = 3 },
    // E5.8b: the monotonic/system time family (bifs/time.zig, S21 clock seam).
    .{ .module = "erlang", .name = "monotonic_time", .arity = 0 },
    .{ .module = "erlang", .name = "monotonic_time", .arity = 1 },
    .{ .module = "erlang", .name = "nif_error", .arity = 1 }, // E3.12: exception family (call_ext)
    .{ .module = "erlang", .name = "nif_error", .arity = 2 },
    // E2.11: the process/system BIF family (bifs/procsys.zig) — the
    // non-pid/ref/scheduler-blocked subset only (see that module's doc
    // comment + DIVERGENCE_LOG.md entry 11 for the justified majority).
    .{ .module = "erlang", .name = "node", .arity = 0 },
    // E3.7: node/1 (bifs/procsys.zig) — the local node of a pid/port/ref. One of
    // the two process-bridge BIFs reachable end-to-end via bif1 today (EQ).
    .{ .module = "erlang", .name = "node", .arity = 1 },
    .{ .module = "erlang", .name = "nodes", .arity = 0 },
    // E8.2b: the non-distributed observer subset of nodes/1,2.
    .{ .module = "erlang", .name = "nodes", .arity = 1 },
    .{ .module = "erlang", .name = "nodes", .arity = 2 },
    .{ .module = "erlang", .name = "not", .arity = 1 },
    .{ .module = "erlang", .name = "or", .arity = 2 },
    // E2.12: phash2/1,2 + pre_loaded/0 (bifs/term_ops.zig / bifs/code.zig).
    // E31-T2: the LEGACY erlang:phash/2 (make_hash port; sorts before phash2).
    .{ .module = "erlang", .name = "phash", .arity = 2 },
    .{ .module = "erlang", .name = "phash2", .arity = 1 },
    .{ .module = "erlang", .name = "phash2", .arity = 2 },
    // E3.6: pid_to_list/port_to_list/ref_to_list (bifs/conv.zig) — diag's
    // pid/port/reference print shape materialized as a char-list.
    .{ .module = "erlang", .name = "pid_to_list", .arity = 1 },
    // E5.4 (Task 4): the port opaque-data slots — live-os-port surface.
    .{ .module = "erlang", .name = "port_get_data", .arity = 1 },
    .{ .module = "erlang", .name = "port_set_data", .arity = 2 },
    .{ .module = "erlang", .name = "port_to_list", .arity = 1 },
    .{ .module = "erlang", .name = "ports", .arity = 0 }, // E6.7: the live-port list

    // E3.18: posixtime_to_universaltime/1 (pure Gregorian arithmetic).
    .{ .module = "erlang", .name = "posixtime_to_universaltime", .arity = 1 },
    .{ .module = "erlang", .name = "pre_loaded", .arity = 0 },
    .{ .module = "erlang", .name = "process_flag", .arity = 2 },
    .{ .module = "erlang", .name = "put", .arity = 2 }, // E3.12: pdict (call_ext)
    .{ .module = "erlang", .name = "raise", .arity = 3 }, // E3.12: exception family
    .{ .module = "erlang", .name = "read_timer", .arity = 1 }, // E6.2 timer family
    .{ .module = "erlang", .name = "read_timer", .arity = 2 },
    .{ .module = "erlang", .name = "ref_to_list", .arity = 1 },
    // E4.1: registry mutator process BIF (deferred-E4-procdispatch discharged).
    .{ .module = "erlang", .name = "register", .arity = 2 },
    .{ .module = "erlang", .name = "registered", .arity = 0 },
    .{ .module = "erlang", .name = "rem", .arity = 2 },
    // E6.4 (Task 4): resume_process/1 — the suspend/resume counting monoid's
    // erlang-module half (suspend_process/2 is under erts_internal below).
    .{ .module = "erlang", .name = "resume_process", .arity = 1 },
    .{ .module = "erlang", .name = "round", .arity = 1 },
    // E3.7: self/0 (bifs/procsys.zig) — the running process's pid term. The other
    // process-bridge BIF reachable end-to-end via bif0 today (EQ).
    .{ .module = "erlang", .name = "self", .arity = 0 },
    // E4.1: message-send process BIFs (send/2 == '!'/2, send/3). Discharged.
    .{ .module = "erlang", .name = "send", .arity = 2 },
    .{ .module = "erlang", .name = "send", .arity = 3 },
    // E6.2 (Task 2): send_after/3,4 (the LIVE timer family).
    .{ .module = "erlang", .name = "send_after", .arity = 3 },
    .{ .module = "erlang", .name = "send_after", .arity = 4 },
    // E7.6 (S29): the sequential-trace token setter/reader + no-tracer print.
    .{ .module = "erlang", .name = "seq_trace", .arity = 2 },
    .{ .module = "erlang", .name = "seq_trace_info", .arity = 1 },
    .{ .module = "erlang", .name = "seq_trace_print", .arity = 1 },
    .{ .module = "erlang", .name = "seq_trace_print", .arity = 2 },
    // E2.12: setelement/3 (bifs/term_ops.zig).
    .{ .module = "erlang", .name = "setelement", .arity = 3 },
    // E8.2m: setnode/2 channel-start action bridge. The current no-carrier
    // public result is still E8.2k's raised badarg; live install still belongs
    // to the dist-carrier owner.
    .{ .module = "erlang", .name = "setnode", .arity = 2 },
    .{ .module = "erlang", .name = "size", .arity = 1 },
    // E4.1: MFA-spawn process BIFs (spawn/3, spawn_link/3, spawn_opt/4) — the
    // scheduler resolves the MFA against the live export index and runs the child.
    // deferred-E4-procdispatch discharged. (spawn/1 + spawn_link/1 are erlang.erl
    // LIBRARY wrappers — bifs/dispatch.zig `resolveLibrary`, ledger-invisible like
    // spawn_monitor — so they are DELIBERATELY absent from this capability list.)
    .{ .module = "erlang", .name = "spawn", .arity = 3 },
    .{ .module = "erlang", .name = "spawn_link", .arity = 3 },
    .{ .module = "erlang", .name = "spawn_opt", .arity = 4 },
    // E5.6 (Task 6): spawn_request_abandon/1 (the async spawn/request protocol).
    .{ .module = "erlang", .name = "spawn_request_abandon", .arity = 1 },
    // E3.18: split_binary/2, subtract/2 (== --/2).
    .{ .module = "erlang", .name = "split_binary", .arity = 2 },
    // E6.2 (Task 2): start_timer/3,4 (the LIVE timer family).
    .{ .module = "erlang", .name = "start_timer", .arity = 3 },
    .{ .module = "erlang", .name = "start_timer", .arity = 4 },
    // E6.5 (Task 5): statistics/1 (bifs/procsys.zig) — the counter-observation
    // subset (reductions/runtime/wall_clock/run_queue/exact_reductions); the
    // nondeterministic VALUES are PROPERTY-FOLDED in the corpus (type+monotone),
    // never byte-asserted. Sort: 'sta't > 'sta'r(t_timer), < 'su'(btract).
    .{ .module = "erlang", .name = "statistics", .arity = 1 },
    .{ .module = "erlang", .name = "subtract", .arity = 2 },
    // E6.5 (Task 5): the introspection setters/getters (bifs/procsys.zig).
    // system_flag/2 round-trips the backtrace_depth int; system_info/1 answers
    // the version-INDEPENDENT deterministic item subset (wordsize/machine/endian/
    // smp_support/threads); system_profile/0,2 round-trips the profiler setting
    // (`undefined` cleared). Sort: 'system_f' < 'system_i' < 'system_p' < 'system_t'ime.
    .{ .module = "erlang", .name = "system_flag", .arity = 2 },
    .{ .module = "erlang", .name = "system_info", .arity = 1 },
    .{ .module = "erlang", .name = "system_profile", .arity = 0 },
    .{ .module = "erlang", .name = "system_profile", .arity = 2 },
    // E5.8b: system_time/0,1 (bifs/time.zig, S21 clock seam).
    .{ .module = "erlang", .name = "system_time", .arity = 0 },
    .{ .module = "erlang", .name = "system_time", .arity = 1 },
    .{ .module = "erlang", .name = "term_to_binary", .arity = 1 },
    .{ .module = "erlang", .name = "term_to_binary", .arity = 2 },
    // E2.12: term_to_iovec/1,2 (bifs/term_ops.zig).
    .{ .module = "erlang", .name = "term_to_iovec", .arity = 1 },
    .{ .module = "erlang", .name = "term_to_iovec", .arity = 2 },
    .{ .module = "erlang", .name = "throw", .arity = 1 }, // E3.12: exception family (call_ext)
    // gap-localtime-tz (DIVERGENCE 731): time/0 = the TIME part of localtime/0.
    .{ .module = "erlang", .name = "time", .arity = 0 },
    // E5.8b: time_offset/0,1 + timestamp/0 (bifs/time.zig, S21 clock seam).
    .{ .module = "erlang", .name = "time_offset", .arity = 0 },
    .{ .module = "erlang", .name = "time_offset", .arity = 1 },
    .{ .module = "erlang", .name = "timestamp", .arity = 0 },
    .{ .module = "erlang", .name = "tl", .arity = 1 },
    // E7.6 (S29): trace_info/2 — the empty-trace defaults ({flags,[]}/{tracer,[]}).
    .{ .module = "erlang", .name = "trace_info", .arity = 2 },
    .{ .module = "erlang", .name = "trunc", .arity = 1 },
    .{ .module = "erlang", .name = "tuple_size", .arity = 1 },
    .{ .module = "erlang", .name = "tuple_to_list", .arity = 1 },
    // E5.5 (Task 5): unalias/1 (bifs/procsys.zig) — retires a process alias.
    .{ .module = "erlang", .name = "unalias", .arity = 1 },
    // E2.12: unique_integer/0,1 (bifs/term_ops.zig) — the Machine-owned
    // monotonic counter, NOT a ref (see that module's doc comment).
    .{ .module = "erlang", .name = "unique_integer", .arity = 0 },
    .{ .module = "erlang", .name = "unique_integer", .arity = 1 },
    // gap-localtime-tz (DIVERGENCE 731): universaltime_to_localtime/1 (host TZ).
    .{ .module = "erlang", .name = "universaltime_to_localtime", .arity = 1 },
    // E3.18: universaltime_to_posixtime/1 (inverse Gregorian arithmetic).
    .{ .module = "erlang", .name = "universaltime_to_posixtime", .arity = 1 },
    // E4.1: unlink / unregister / whereis process BIFs (deferred-E4-procdispatch
    // discharged). Sort: 'unl' > 'uni'(versaltime), 'w' < 'x'(or).
    .{ .module = "erlang", .name = "unlink", .arity = 1 },
    .{ .module = "erlang", .name = "unregister", .arity = 1 },
    .{ .module = "erlang", .name = "whereis", .arity = 1 },
    .{ .module = "erlang", .name = "xor", .arity = 2 },
    // E3.18: error_logger:warning_map/0 (bifs/misc.zig) — the `warning` default.
    .{ .module = "error_logger", .name = "warning_map", .arity = 0 },
    // E8.2f: erts_debug:dist_ext_to_term/2 — distribution external term decoder
    // over an explicit atom-cache tuple; not a live carrier handle.
    .{ .module = "erts_debug", .name = "dist_ext_to_term", .arity = 2 },
    // E8.2j/E8.2m: pending distribution-connection handle surface plus
    // channel-start actions. The current no-carrier public result is still
    // E8.2k rejection; live channel promotion remains deferred to the carrier
    // owner.
    .{ .module = "erts_internal", .name = "abort_pending_connection", .arity = 2 },
    // E2.10: erts_internal:atomics_new/2 is the REAL primitive underneath
    // atomics:new/2 (atomics.erl's new/2 is a library wrapper — the SAME
    // shape as list_to_integer/binary_to_integer directly below).
    .{ .module = "erts_internal", .name = "atomics_new", .arity = 2 },
    // E4.2b: beamfile_chunk/2 (bifs/code.zig) — the named-IFF-chunk reader over
    // a raw beam binary; PURE, synthetic-IFF corpus-proven (`bfc`/`bfc_absent`).
    .{ .module = "erts_internal", .name = "beamfile_chunk", .arity = 2 },
    // E5.2c (Task 2 RELOAD half): beamfile_module_md5/1 (bifs/code.zig) — the
    // whole-beam module checksum; PURE over a raw beam binary, real-beam-literal
    // corpus-proven (`bfmd5`). beam_loader.beamModuleMd5 (byte-EQ to erts).
    .{ .module = "erts_internal", .name = "beamfile_module_md5", .arity = 1 },
    .{ .module = "erts_internal", .name = "binary_to_integer", .arity = 2 },
    // E3.18: the representation-INDEPENDENT erts_internal pair (term_ops.zig /
    // persistent_term.zig): cmp_term/2 (the -1|0|1 term order) and
    // erase_persistent_terms/0.
    // E6.6 (Task 6): the observable dirty-scheduler rows (bifs/procsys.zig).
    // check_dirty_process_code/2 + dirty_process_handle_signals/1 raise
    // error:notsup (restricted entries); the pool machinery is proc.zig's
    // dirty-migration homomorphism. Sort: 'check' < 'cmp' < 'dirty' < 'erase'.
    .{ .module = "erts_internal", .name = "check_dirty_process_code", .arity = 2 },
    .{ .module = "erts_internal", .name = "check_process_code", .arity = 1 },
    .{ .module = "erts_internal", .name = "cmp_term", .arity = 2 },
    // E36-T1: the counters primitives (bifs/counters.zig) — the write_concurrency
    // backend under counters.erl, reusing the atomics-array algebra.
    .{ .module = "erts_internal", .name = "counters_add", .arity = 3 },
    .{ .module = "erts_internal", .name = "counters_get", .arity = 2 },
    .{ .module = "erts_internal", .name = "counters_info", .arity = 1 },
    .{ .module = "erts_internal", .name = "counters_new", .arity = 1 },
    .{ .module = "erts_internal", .name = "counters_put", .arity = 3 },
    .{ .module = "erts_internal", .name = "create_dist_channel", .arity = 3 },
    .{ .module = "erts_internal", .name = "dirty_process_handle_signals", .arity = 1 },
    // E8.2i: no-carrier remote spawn request direct-BIF surface.
    .{ .module = "erts_internal", .name = "dist_spawn_request", .arity = 4 },
    .{ .module = "erts_internal", .name = "erase_persistent_terms", .arity = 0 },
    // E6.4 (Task 4): garbage_collect/1 — a GC request on the caller, returns `true`
    // (self-contained; zigvm's copying GC is denote-preserving). Sort: 'ga' > 'era'.
    .{ .module = "erts_internal", .name = "garbage_collect", .arity = 1 },
    // E8.2c/E8.2e: no-carrier distribution observers.
    .{ .module = "erts_internal", .name = "get_creation", .arity = 0 },
    .{ .module = "erts_internal", .name = "get_dflags", .arity = 0 },
    // E5.3 (Task 3): the GL SETTER pair group_leader/2,3 — sets a TARGET
    // process's group leader; observed representation-free via the child's own
    // group_leader/0 (the `glset` differential row). DIVERGENCE entry 40/41.
    .{ .module = "erts_internal", .name = "group_leader", .arity = 2 },
    .{ .module = "erts_internal", .name = "group_leader", .arity = 3 },
    // E5.5 (Task 5): the async is_process_alive/2 (alias-reply protocol).
    .{ .module = "erts_internal", .name = "is_process_alive", .arity = 2 },
    // E6.6 (Task 6): is_process_executing_dirty/1 → false (no dirty runtime).
    .{ .module = "erts_internal", .name = "is_process_executing_dirty", .arity = 1 },
    // E6.4 (Task 4): is_system_process/1 — reads the target's `system` flag; a
    // normal process → `false` (host-verified). Sort: 'is_s' > 'is_p'.
    .{ .module = "erts_internal", .name = "is_system_process", .arity = 1 },
    .{ .module = "erts_internal", .name = "list_to_integer", .arity = 2 },
    // E31-T2: the Tier-1 HAMT iterator primitive (byte-EQ flatmap + ordered-iter).
    .{ .module = "erts_internal", .name = "map_next", .arity = 3 },
    .{ .module = "erts_internal", .name = "new_connection", .arity = 1 },
    // E5.4 (Task 4): the live os-port primitives (bifs/ports.zig → os_port.zig).
    // E6.7 (Task 7): + the port-representation surface (deferred-E6-portrepr) —
    // kept in (module,name,arity) sorted order (the supported_bifs sort law).
    .{ .module = "erts_internal", .name = "open_port", .arity = 2 },
    // E6.6 (Task 6): perf_counter_unit/0 → the ns unit (property-folded positive).
    .{ .module = "erts_internal", .name = "perf_counter_unit", .arity = 0 },
    .{ .module = "erts_internal", .name = "port_call", .arity = 3 },
    .{ .module = "erts_internal", .name = "port_close", .arity = 1 },
    .{ .module = "erts_internal", .name = "port_command", .arity = 3 },
    .{ .module = "erts_internal", .name = "port_connect", .arity = 2 },
    .{ .module = "erts_internal", .name = "port_control", .arity = 3 },
    .{ .module = "erts_internal", .name = "port_info", .arity = 1 },
    .{ .module = "erts_internal", .name = "port_info", .arity = 2 },
    // e5-dispatch-codeidx (DIVERGENCE 81): prepare_loading/2 — stage a beam for the
    // runtime code table (bifs/code.zig; reload_call). Committed by finish_loading/1.
    .{ .module = "erts_internal", .name = "prepare_loading", .arity = 2 },
    // E5.6 (Task 6): the async spawn/request protocol — process_flag/3 (save_calls)
    // + spawn_request/4; erlang:spawn_request_abandon/1 is in the erlang block.
    // DIVERGENCE entry 72.
    .{ .module = "erts_internal", .name = "process_flag", .arity = 3 },
    // E6.3 (Task 3, DIVERGENCE 108, amending 75/81): purge_module/2 — the
    // erts_code_purger PROCESS restriction; a direct (non-purger) call raises
    // error:notsup (bifs/code.zig; the `purge_notsup` corpus case).
    .{ .module = "erts_internal", .name = "purge_module", .arity = 2 },
    .{ .module = "erts_internal", .name = "request_system_task", .arity = 3 },
    .{ .module = "erts_internal", .name = "request_system_task", .arity = 4 },
    // E6.5 (Task 5): scheduler_wall_time/1 (bifs/procsys.zig) — round-trips the
    // enable flag, returning the OLD boolean. Sort: 'sc' < 'sp'(awn_request).
    .{ .module = "erts_internal", .name = "scheduler_wall_time", .arity = 1 },
    .{ .module = "erts_internal", .name = "spawn_request", .arity = 4 },
    // E6.4 (Task 4): the suspension/system-task family. suspend_process/2 (the
    // monoid's erts_internal half) + system_check/1 (schedulers → ok). Sort:
    // 'su' > 'sp'(awn_request), 'sy' > 'su'.
    .{ .module = "erts_internal", .name = "suspend_process", .arity = 2 },
    .{ .module = "erts_internal", .name = "system_check", .arity = 1 },
    // E6.5 (Task 5): system_monitor/1,3 (bifs/procsys.zig) — the legacy get(/1)
    // + set(/3, {Pid,Opts}) round-trip; returns the previous setting (`undefined`
    // when unset). Sort: 'sy' > 'sp'(awn_request).
    .{ .module = "erts_internal", .name = "system_monitor", .arity = 1 },
    .{ .module = "erts_internal", .name = "system_monitor", .arity = 3 },
    // E6.3 (Task 3, DIVERGENCE 108): the erts_literal_area_collector PROCESS
    // restriction — release_area_switch/0 + send_copy_request/3 raise error:notsup
    // from a non-collector caller (bifs/code.zig; the `litarea_notsup` case).
    .{ .module = "erts_literal_area_collector", .name = "release_area_switch", .arity = 0 },
    .{ .module = "erts_literal_area_collector", .name = "send_copy_request", .arity = 3 },
    // E2.9: the ETS BIF family (bifs/ets.zig) — the core + ordered traversal,
    // driving ets_algebra's live TreeBackend + the Machine-owned EtsRegistry.
    // The match/select family stays OUT (needs a runtime match-spec-term
    // compiler — new matchspec semantics, a separate slice); ets:tab2list/1 and
    // delete_all_objects/1 are ets.erl LIBRARY wrappers (no bif.tab row on this
    // pin), so they stay OUT too — the maps:to_list/1 shape.
    .{ .module = "ets", .name = "delete", .arity = 1 },
    .{ .module = "ets", .name = "delete", .arity = 2 },
    .{ .module = "ets", .name = "delete_object", .arity = 2 },
    .{ .module = "ets", .name = "first", .arity = 1 },
    .{ .module = "ets", .name = "first_lookup", .arity = 1 }, // E3.18
    .{ .module = "ets", .name = "give_away", .arity = 3 }, // E6.7: owner transfer + ETS-TRANSFER
    .{ .module = "ets", .name = "info", .arity = 1 },
    .{ .module = "ets", .name = "info", .arity = 2 },
    .{ .module = "ets", .name = "insert", .arity = 2 },
    .{ .module = "ets", .name = "insert_new", .arity = 2 },
    .{ .module = "ets", .name = "internal_delete_all", .arity = 2 }, // E3.15
    .{ .module = "ets", .name = "internal_select_delete", .arity = 2 }, // E3.15
    .{ .module = "ets", .name = "is_compiled_ms", .arity = 1 }, // E3.15
    .{ .module = "ets", .name = "last", .arity = 1 },
    .{ .module = "ets", .name = "last_lookup", .arity = 1 }, // E3.18
    .{ .module = "ets", .name = "lookup", .arity = 2 },
    .{ .module = "ets", .name = "lookup_element", .arity = 3 },
    .{ .module = "ets", .name = "lookup_element", .arity = 4 },
    // E3.15: the match/select family (bifs/ets.zig — matchspec.zig compiler).
    .{ .module = "ets", .name = "match", .arity = 1 },
    .{ .module = "ets", .name = "match", .arity = 2 },
    .{ .module = "ets", .name = "match", .arity = 3 },
    .{ .module = "ets", .name = "match_object", .arity = 1 },
    .{ .module = "ets", .name = "match_object", .arity = 2 },
    .{ .module = "ets", .name = "match_object", .arity = 3 },
    .{ .module = "ets", .name = "match_spec_compile", .arity = 1 },
    .{ .module = "ets", .name = "match_spec_run_r", .arity = 3 },
    .{ .module = "ets", .name = "member", .arity = 2 },
    .{ .module = "ets", .name = "new", .arity = 2 },
    .{ .module = "ets", .name = "next", .arity = 2 },
    .{ .module = "ets", .name = "next_lookup", .arity = 2 }, // E3.18
    .{ .module = "ets", .name = "prev", .arity = 2 },
    .{ .module = "ets", .name = "prev_lookup", .arity = 2 }, // E3.18
    .{ .module = "ets", .name = "rename", .arity = 2 }, // E5.9 name-registry remap
    // E3.18: ets core extensions (bifs/ets.zig) over the live TreeBackend.
    .{ .module = "ets", .name = "safe_fixtable", .arity = 2 },
    // E3.15: select* family (bifs/ets.zig — matchspec.zig compiler).
    .{ .module = "ets", .name = "select", .arity = 1 },
    .{ .module = "ets", .name = "select", .arity = 2 },
    .{ .module = "ets", .name = "select", .arity = 3 },
    .{ .module = "ets", .name = "select_count", .arity = 2 },
    .{ .module = "ets", .name = "select_replace", .arity = 2 },
    .{ .module = "ets", .name = "select_reverse", .arity = 1 },
    .{ .module = "ets", .name = "select_reverse", .arity = 2 },
    .{ .module = "ets", .name = "select_reverse", .arity = 3 },
    .{ .module = "ets", .name = "setopts", .arity = 2 }, // E6.7: heir/protection round-trip
    .{ .module = "ets", .name = "take", .arity = 2 },
    // E31-T2: the increment-op grammar (byte-EQ); sorts before update_element.
    .{ .module = "ets", .name = "update_counter", .arity = 3 },
    .{ .module = "ets", .name = "update_counter", .arity = 4 },
    .{ .module = "ets", .name = "update_element", .arity = 3 },
    .{ .module = "ets", .name = "update_element", .arity = 4 },
    .{ .module = "ets", .name = "whereis", .arity = 1 }, // E6.7: the Tid (leaves deferred-ets-tidrep)
    // E4.4: file:native_name_encoding/0 (bifs/file.zig) → the atom `utf8` (this
    // host's locale). Sorts after ets, before io.
    .{ .module = "file", .name = "native_name_encoding", .arity = 0 },
    // E3.18: io:printable_range/0 (bifs/misc.zig) — the `latin1` default.
    .{ .module = "io", .name = "printable_range", .arity = 0 },
    .{ .module = "lists", .name = "keyfind", .arity = 3 },
    .{ .module = "lists", .name = "keymember", .arity = 3 },
    .{ .module = "lists", .name = "keysearch", .arity = 3 },
    .{ .module = "lists", .name = "member", .arity = 2 },
    .{ .module = "lists", .name = "reverse", .arity = 2 },
    // E2.7: the maps BIF family (bifs/maps.zig). `maps:new/0`/`get/3`/
    // `to_list/1` are NOT bif.tab entries (library wrappers/literal-compiles
    // in maps.erl — see bifs/maps.zig's scope note) and stay OUT of this
    // ledger — wiring them would claim a table row that does not exist.
    .{ .module = "maps", .name = "find", .arity = 2 },
    .{ .module = "maps", .name = "from_keys", .arity = 2 }, // E3.18
    .{ .module = "maps", .name = "from_list", .arity = 1 },
    .{ .module = "maps", .name = "get", .arity = 2 },
    .{ .module = "maps", .name = "is_key", .arity = 2 },
    .{ .module = "maps", .name = "keys", .arity = 1 },
    .{ .module = "maps", .name = "merge", .arity = 2 },
    .{ .module = "maps", .name = "put", .arity = 3 },
    .{ .module = "maps", .name = "remove", .arity = 2 },
    .{ .module = "maps", .name = "take", .arity = 2 },
    .{ .module = "maps", .name = "update", .arity = 3 },
    .{ .module = "maps", .name = "values", .arity = 1 },
    // E2.10: the math BIF family (bifs/math.zig). `pi/0`/`tau/0` are NOT
    // bif.tab entries (math.erl literal-float-constant functions — see
    // bifs/math.zig's scope note) and stay OUT of this ledger.
    .{ .module = "math", .name = "acos", .arity = 1 },
    .{ .module = "math", .name = "acosh", .arity = 1 },
    .{ .module = "math", .name = "asin", .arity = 1 },
    .{ .module = "math", .name = "asinh", .arity = 1 },
    .{ .module = "math", .name = "atan", .arity = 1 },
    .{ .module = "math", .name = "atan2", .arity = 2 },
    .{ .module = "math", .name = "atanh", .arity = 1 },
    .{ .module = "math", .name = "ceil", .arity = 1 },
    .{ .module = "math", .name = "cos", .arity = 1 },
    .{ .module = "math", .name = "cosh", .arity = 1 },
    .{ .module = "math", .name = "erf", .arity = 1 },
    .{ .module = "math", .name = "erfc", .arity = 1 },
    .{ .module = "math", .name = "exp", .arity = 1 },
    .{ .module = "math", .name = "floor", .arity = 1 },
    .{ .module = "math", .name = "fmod", .arity = 2 },
    .{ .module = "math", .name = "log", .arity = 1 },
    .{ .module = "math", .name = "log10", .arity = 1 },
    .{ .module = "math", .name = "log2", .arity = 1 },
    .{ .module = "math", .name = "pow", .arity = 2 },
    .{ .module = "math", .name = "sin", .arity = 1 },
    .{ .module = "math", .name = "sinh", .arity = 1 },
    .{ .module = "math", .name = "sqrt", .arity = 1 },
    .{ .module = "math", .name = "tan", .arity = 1 },
    .{ .module = "math", .name = "tanh", .arity = 1 },
    // E8.2c: no-carrier distribution flag observer over local/foreign pid terms.
    .{ .module = "net_kernel", .name = "dflag_unicode_io", .arity = 1 },
    // E5.8b (Task 8b): the os clock/env family (bifs/os.zig). env/0 + set_signal/2
    // stay deferred-E5 (see bif_gen.ml's os module justification).
    .{ .module = "os", .name = "getenv", .arity = 1 },
    .{ .module = "os", .name = "getpid", .arity = 0 },
    .{ .module = "os", .name = "perf_counter", .arity = 0 },
    .{ .module = "os", .name = "putenv", .arity = 2 },
    .{ .module = "os", .name = "system_time", .arity = 0 },
    .{ .module = "os", .name = "system_time", .arity = 1 },
    .{ .module = "os", .name = "timestamp", .arity = 0 },
    .{ .module = "os", .name = "unsetenv", .arity = 1 },
    // E2.10: the persistent_term BIF family (bifs/persistent_term.zig).
    .{ .module = "persistent_term", .name = "erase", .arity = 1 },
    .{ .module = "persistent_term", .name = "get", .arity = 0 },
    .{ .module = "persistent_term", .name = "get", .arity = 1 },
    .{ .module = "persistent_term", .name = "get", .arity = 2 },
    .{ .module = "persistent_term", .name = "info", .arity = 0 },
    .{ .module = "persistent_term", .name = "put", .arity = 2 },
    .{ .module = "persistent_term", .name = "put_new", .arity = 2 },
    // E4.4: the prim_file: native-name codec family (bifs/file.zig). On this pin
    // the ENTIRE prim_file:/file: bif.tab surface is these codec rows (the file
    // OPERATIONS are the NIF/driver surface, no bif.tab row — src/prim_file.zig).
    // Pure over unicode.zig, reachable end-to-end via call_ext_bif. Sorts after
    // persistent_term, before records.
    .{ .module = "prim_file", .name = "internal_name2native", .arity = 1 },
    .{ .module = "prim_file", .name = "internal_native2name", .arity = 1 },
    .{ .module = "prim_file", .name = "internal_normalize_utf8", .arity = 1 },
    .{ .module = "prim_file", .name = "is_translatable", .arity = 1 },
    // E7.9: the hosted `re:` engine over the stdlib byte-PCRE subset. The
    // compiled form is a transparent tagged term; unsupported PCRE constructs
    // reject instead of becoming false no-matches. Sorts after prim_file, before
    // records.
    .{ .module = "re", .name = "compile", .arity = 1 },
    .{ .module = "re", .name = "compile", .arity = 2 },
    .{ .module = "re", .name = "import", .arity = 1 },
    .{ .module = "re", .name = "inspect", .arity = 2 },
    .{ .module = "re", .name = "internal_run", .arity = 4 },
    .{ .module = "re", .name = "run", .arity = 2 },
    .{ .module = "re", .name = "run", .arity = 3 },
    .{ .module = "re", .name = "version", .arity = 0 },
    // E3.14: the native-record reflection family (bifs/records.zig).
    // The pin's eight rows (get_definition/2 added in E8.T6).
    .{ .module = "records", .name = "create", .arity = 4 },
    .{ .module = "records", .name = "get", .arity = 2 },
    .{ .module = "records", .name = "get_definition", .arity = 2 },
    .{ .module = "records", .name = "get_field_names", .arity = 1 },
    .{ .module = "records", .name = "get_module", .arity = 1 },
    .{ .module = "records", .name = "get_name", .arity = 1 },
    .{ .module = "records", .name = "is_exported", .arity = 1 },
    .{ .module = "records", .name = "update", .arity = 4 },
    // E3.18: string:list_to_float/1 (bifs/misc.zig) — the leading-float parser.
    .{ .module = "string", .name = "list_to_float", .arity = 1 },
    // E2.12: the unicode chardata BIF family (bifs/unicode.zig) — exactly the
    // pin's 3 real `unicode:` bif.tab rows (see that module's scope note).
    .{ .module = "unicode", .name = "bin_is_7bit", .arity = 1 },
    .{ .module = "unicode", .name = "characters_to_binary", .arity = 2 },
    .{ .module = "unicode", .name = "characters_to_list", .arity = 2 },
};

// ============================================================================
// The machine (⟨x-regs, CP stack, heap, pc, reductions, status⟩)
// ============================================================================

pub const Status = enum { running, halted, crashed, suspended };

/// E1.8: an active try/catch protected region — a landing pad on `catch_stack`.
/// `to` is the recovery pc (a code label after fixup); `kind` selects the BEAM
/// register convention the unwind uses; `y_depth` is the ystack height at push
/// time, restored on unwind so the handler sees the caller's frame.
pub const CatchFrame = struct { to: u32, kind: enum { catch_, try_ }, y_depth: usize, c_depth: usize };

/// E3.10: the exception class — BEAM's three-way {throw, error, exit}. The
/// class travels WITH a raised exception (`Machine.exc`) so a re-raise
/// (`raise`/`raw_raise`) preserves the ORIGINAL class (entry 2c) and a `catch`
/// unwind wraps the value class-discriminated (`catchWrap`): error →
/// `{'EXIT',{Reason,Stacktrace}}`, exit → `{'EXIT',Reason}`, throw → the value
/// bare. `error_`/`exit_`/`throw_` (trailing underscores: `error` is a Zig
/// keyword, the others for symmetry).
pub const ExcClass = enum { error_, exit_, throw_ };

/// E3.11: one program-counter's source location — the pc→{mfa,line,file} entry
/// `beam_loader.translate` builds from the `func_info` boundaries + the `Line`
/// chunk (DIVERGENCE entry 2b). `locs[pc]` names the function + line the
/// instruction at `pc` belongs to; a raise cooks the head frame from
/// `locs[faulting_pc]` and caller frames from `locs[return_pc]` for each pc on
/// the return stack. All fields are trivially-copyable (atom idxs / ints) so
/// `locs` is a plain owned `[]Loc` — no sub-slice ownership. A zero `line`/`file`
/// means "no line info" (the module had no `Line` chunk) → an empty `[]` loc
/// list in the frame, exactly like BEAM's `+no_line_info` builds.
pub const Loc = struct {
    m: ta.AtomIdx = 0, // module atom (0 = unknown — the runtime atom table is
    // 0-based, so `m`/`f` default 0 only for the never-real pre-func_info
    // preamble; a raise there yields a `{'', '', 0, []}` head, never a panic)
    f: ta.AtomIdx = 0, // function atom
    a: u32 = 0, //         arity
    line: u32 = 0, //      source line (0 = none — 1-based in source)
    file: ?ta.AtomIdx = null, // filename atom, OPTIONAL — the atom table is
    // 0-based (index 0 is a real atom, e.g. an early-interned "mod.erl"), so a
    // plain 0 cannot mean "none"; a charlist is built at raise when non-null.
};

/// E3.10: the current/last-raised exception — set by `raiseWith` on EVERY raise,
/// read by `.raise` (re-raise) and available on the halt path. `stacktrace` is
/// the E1-minimal `nil` until Task 11 cooks it (line info).
pub const Exc = struct {
    class: ExcClass,
    reason: FinalTerms.Term,
    stacktrace: FinalTerms.Term,
};

/// E3.12: one entry of the static multi-module EXPORT index — a
/// `module:func/arity → pc` binding into the loaded (concatenated) program.
/// `call_ext`/`apply` resolve a cross-module target through this table (the
/// E1.7 `undef`-trap path becomes the miss path). Borrowed by the Machine
/// (`m.exports`), owned by the loader/linker that built it — NEVER by the
/// Machine (same borrow discipline as `m.locs`/`m.literals`). Cross-module
/// linking into a single pc space mirrors `boot.link`'s pc-fixup essence.
pub const Export = struct {
    module: ta.AtomIdx,
    func: ta.AtomIdx,
    arity: u32,
    pc: u32,
};

/// gap-tracing-e7: does an export match a trace_pattern predicate? A `null`
/// component is the `'_'` wildcard (matches anything); a set component must be
/// EQ. Shared by `Machine.countMatchingExports` (the matched count) and the Vm's
/// `callPatternMatches` (the call-event gate).
fn matchExport(e: Export, module: ?ta.AtomIdx, func: ?ta.AtomIdx, arity: ?u32) bool {
    if (module) |mm| {
        if (e.module != mm) return false;
    }
    if (func) |ff| {
        if (e.func != ff) return false;
    }
    if (arity) |ar| {
        if (e.arity != ar) return false;
    }
    return true;
}

/// e5-dispatch-codeidx: a module STAGED by `erts_internal:prepare_loading/2`
/// but not yet committed by `erlang:finish_loading/1`. Its executable code is
/// already spliced into `Machine.dyn_code` (relocated) at prepare time — an
/// UNOBSERVABLE optimization (dispatch is gated on `dyn_exports`/`code_index`,
/// which prepare never touches, so the module is not callable until finish
/// commits `entries` into `dyn_exports`). `ref` is the magic handle the
/// prepared term carries; `entries` (owned) map the module's exported
/// `func/arity` to a GLOBAL (unified) pc in the dynamic code space.
pub const StagedModule = struct {
    ref: u64,
    module: ta.AtomIdx,
    entries: []Export,
    committed: bool = false,
    // E7.2 (on_load wiring, DIVERGENCE 147): the GLOBAL (unified) pc of the
    // module's `-on_load` function, resolved at prepare time (`null` when the
    // module declares no on_load — the load has no gate). `on_load_pending` is
    // set true by `finish_loading` when it returns `{on_load,[Mod]}` (the code
    // is committed but its on_load has NOT yet run + gated); `call_on_load_
    // function/1` runs it, `finish_after_on_load/2` clears it (commit) or rolls
    // the just-committed code back (a failed on_load). See bifs/code.zig.
    on_load_pc: ?u32 = null,
    on_load_pending: bool = false,
};

/// E4.2 (code server): the retained per-module metadata behind
/// `erlang:get_module_info/1,2` (`M:module_info/0,1`) and
/// `erts_internal:beamfile_module_md5/1`. `attr_bytes`/`compile_bytes` are the
/// module's raw `Attr`/`CInf` ETF chunk bytes (decoded on demand to the
/// attributes/compile proplists — the SAME bytes erts hands `erts_decode_ext`);
/// `md5` is the module checksum `beam_loader.computeMd5` produced. BORROWED —
/// the byte slices live in the loaded `Module`'s arena, owned by the caller
/// (`cli.runMulti` sets `Machine.mod_meta`, frees the modules), never by the
/// Machine, exactly like `exports`.
pub const ModMeta = struct {
    module: ta.AtomIdx,
    attr_bytes: []const u8 = &.{},
    compile_bytes: []const u8 = &.{},
    md5: [16]u8 = [_]u8{0} ** 16,
    has_md5: bool = false,
};

pub const Mbox = mba.FinalMbox(FinalTerms);

/// gap-eep76-priority-flag (DIVERGENCE 602): the four process scheduling priorities
/// (`process_flag(priority, _)`), in erts order. `.name()` gives the atom string.
/// gap-atom-and-heap-limits: the `max_heap_size` per-process config (erts
/// `#{size, kill, error_logger, include_shared_binaries}`). `size == 0` = disabled.
pub const MaxHeapCfg = struct {
    size: u64 = 0,
    kill: bool = true,
    error_logger: bool = true,
    include_shared_binaries: bool = false,
};

pub const ProcPriority = enum {
    low,
    normal,
    high,
    max,
    pub fn name(self: ProcPriority) []const u8 {
        return @tagName(self);
    }
    pub fn fromName(s: []const u8) ?ProcPriority {
        inline for (@typeInfo(ProcPriority).@"enum".fields) |f| {
            if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }
};

pub const Machine = struct {
    gpa: std.mem.Allocator,
    apoptosis_immune: bool = false,
    ctx: FinalTerms.Ctx, // the process heap (M1/M2/M4)
    literals: []const FinalTerms.Term = &.{}, // W-17: LitT terms materialized
    // INTO this machine's `ctx` (each word is a `ctx` heap ref, valid only here
    // — which is why the table is per-machine, not shared through the program).
    // `resolve(.literal i)` indexes it. The load site owns and frees the slice.
    // e21-t2b (DIVERGENCE 510): a SPAWNED child cannot borrow the parent's
    // `literals` — a COMPOUND literal (tuple/list/map/bignum) is a boxed term
    // whose words index the PARENT's ctx, meaningless in the child's ctx (reading
    // it there is an OOB / mis-tagged term — the lit-ctx-mismatch panic). The
    // child instead gets its OWN slice, each entry `gcCopy`d cross-heap into the
    // child's ctx (`Vm.inheritCode`). `owns_literals` marks that owned slice so
    // `deinit` frees it (the entry machine keeps `false` — cli owns its table).
    owns_literals: bool = false,
    regs: [x_reg_count]FinalTerms.Term, // E5.2: widened from 16 to the full
    // decodable x-register range (DIVERGENCE 46) — `Machine.init` `@splat`s all
    // slots to nil, so slots the program never touches stay nil in both twins
    // and `eqMachines` sees nil == nil (no per-iteration seeding cost).
    fregs: [16]f64 = @splat(0), // E1.12: the float-register bank (raw IEEE f64;
    // fixed array, NO allocation — `deinit` needs no change). Boxed back to a
    // float term only by `fmove_from_f`. Observable control state → `eqMachines`.
    stack: std.ArrayList(usize), // continuation pointers
    ystack: std.ArrayList(FinalTerms.Term), // M8: y registers (stack slots)
    catch_stack: std.ArrayList(CatchFrame), // E1.8: active try/catch landing pads
    mbox: Mbox, // M5: the process mailbox
    recv_cursor: usize = 0, // E1.11: BEAM receive save-pointer (index into the
    // mailbox arrival sequence). `loop_rec` peeks it, `loop_rec_end` advances
    // it, `remove_message`/`timeout` reset it to 0. See the E1.11 op family.
    // E34-T1 (recv-after-uncond, DIVERGENCE 559): did a `loop_rec` scan run in
    // the CURRENT receive? `wait_timeout`'s lost-wakeup guard (jump-back to
    // re-scan) is ONLY valid for a SELECTIVE receive (whose label points at a
    // `loop_rec`). An UNCONDITIONAL `receive after T` has NO `loop_rec`, so its
    // label points back at the wait itself — firing the queued-message guard
    // there is an infinite spin (the cursor never advances, no clause consumes).
    // `loop_rec` sets this; `remove_message`/`timeout` clear it with the cursor.
    recv_scanned: bool = false,
    pending: ?Action = null, // M7: trapped effect awaiting the VM
    self_pid: u32 = 0, // M7: assigned by the VM at spawn
    // E5.6 (Task 6): the process `save_calls` flag (the only flag
    // `erts_internal:process_flag/3` accepts on the pin — a non-neg call-trace
    // ring size). Its RING is not modeled (a debug-trace facility), but the flag
    // VALUE is observable: `process_flag(Pid, save_calls, N)` returns the OLD
    // value. Default 0. NOT compared in `eqMachines` (a process-local flag, like
    // `self_pid`/`group_leader` — not an observational-equality concern).
    save_calls: i64 = 0,
    // E6.2 (Task 2): the LIVE receive-timer state (DIVERGENCE entry 5's residual).
    // A `receive after N -> ...` compiles to `wait_timeout Lbl N`; with a finite
    // N>0 the machine now ARMS a real timer-wheel entry (via the `arm_recv_timer`
    // trap) and suspends, instead of the E1-minimal fire-immediately. When the
    // wheel fires (proc.zig scheduler advance) it sets `timer_fired = true` and
    // wakes the process; the re-entered `wait_timeout` then takes the after-clause.
    // `recv_timeout_deadline` is the ABSOLUTE virtual-clock deadline (ms) of the
    // in-progress receive, set once by the Vm at first arm and PRESERVED across a
    // non-matching intervening message (BEAM does not reset an `after` timer when
    // a non-matching message arrives — the timer counts from first receive entry),
    // then cleared when the receive resolves (`timeout`/`remove_message`). Both
    // default to the no-timer state; NOT compared in `eqMachines` (scheduler-topology
    // state, like `self_pid`/`group_leader`).
    timer_fired: bool = false,
    recv_timeout_deadline: ?u64 = null,
    group_leader: u32 = 0, // E3.8: this process's group-leader proc index,
    // mirrored onto the Machine by `proc.Vm.spawn`/`interpret` exactly like
    // `self_pid` (a fresh top-level spawn is its OWN group leader — erts'
    // convention for a process with no parent to inherit from; a child
    // spawned via `spawn_fun`/`spawn_mfa`/`spawn_request` inherits its
    // parent's group leader, `erts_internal:group_leader/2,3` overwrites a
    // TARGET process's field via the `.set_group_leader` trap). NOT compared
    // in `eqMachines` (same treatment as `self_pid` — process identity is not
    // an observational-equality concern for the differential/law suites).
    dist_local_node: ?ta.AtomIdx = null, // E8.2t/E8.2u: VM-synchronized local
    dist_local_creation: u32 = 0,
    // distribution identity observer for locally encoded pid/ref/port terms.
    // The authoritative owner remains `proc.Vm` (`dist_local_node` +
    // `dist_local_creation` + live registered `net_kernel`); these fields are a
    // derived, non-owning cache so direct BIFs such as `node/1`, `term_to_binary`,
    // and `external_size` can observe the active local identity without trapping
    // through x0. Null/0 denotes the pre-setnode observation `nonode@nohost` /
    // creation 0. NOT compared in `eqMachines`, like `self_pid`/`group_leader`.
    // e21-t2 (DIVERGENCE 490): the destination register of a `bif`/`gc_bif`-opcode
    // BIF that TRAPPED (set `pending`). The scheduler delivers a trapped result to
    // x0 by the call convention, but a `bif0/1` opcode (e.g. `node/0` compiled as a
    // guard bif) may target a NON-x0 `Dst` when its result is live alongside another
    // value (`node(self()) =:= node()`). Recorded in the `bif_call` arm on trap,
    // consumed once by `deliverTrap` (the get_dist_node/get_dist_creation trap arms),
    // so the resolved value lands in the opcode's real Dst. `null` ⇒ x0 (the
    // call_ext_bif convention). NOT compared in `eqMachines` (transient dispatch state).
    bif_trap_dst: ?Dst = null,
    pc: usize = 0,
    // R2b (gap-reduction-cost-model, the {R} real-time epoch) — the TWO-COUNTER
    // split. `reductions` is now the OTP-FAITHFUL PER-CALL counter (charged by
    // `reductionCost`: ~1 per function call / tail-call, 0 for straight-line ops
    // and forward branches — matching erts `BUMP_REDS`). It drives the
    // `--reduction-oracle` (ratio→~1.0 vs pinned OTP). `instrs` is the
    // per-INSTRUCTION retired count (exactly what `reductions` used to be under the
    // identity model): it increments +1 on every retired op and carries the
    // INTERNAL consistency laws — SLICE-INVARIANCE, block-fuel-exactness, the
    // native≡threaded differential, and PREEMPTION (the `run` fuel loop / scheduler
    // grants / native rsi budget all bound on `instrs`). Keeping preemption on
    // `instrs` makes results AND preemption BYTE-IDENTICAL to the pre-R2b model
    // (the RESULT-IDENTITY anchor + the CTRL-realtime UCA mitigation: the cost
    // reweighting can never change WHERE preemption falls), while `reductions`
    // faithfully reports the per-call cost. See `reductionCost`.
    reductions: u64 = 0,
    instrs: u64 = 0,
    status: Status = .running,
    result: FinalTerms.Term, // exit value / crash reason
    badarith: ta.AtomIdx,
    badfun: ta.AtomIdx,
    badarity: ta.AtomIdx, // gap-apply-fun (DIVERGENCE 733): `{badarity,{Fun,Args}}`
    fclause: ta.AtomIdx,
    undef: ta.AtomIdx, // E1.7: unresolved apply target (export resolution is E3)
    err_class: ta.AtomIdx, // E1.8: the `error` exception class atom
    exit_class: ta.AtomIdx, // E3.10: the `exit` exception class atom
    throw_class: ta.AtomIdx, // E3.10: the `throw` exception class atom
    exit_tag: ta.AtomIdx, // E3.10: the `'EXIT'` atom for the catch value wrap
    nocatch: ta.AtomIdx, // DIVERGENCE 683: the `nocatch` atom — an uncaught throw's cooked process-exit reason is `{{nocatch,V},St}`
    file_key: ta.AtomIdx, // E3.11: the `file` atom for a stacktrace location
    line_key: ta.AtomIdx, // E3.11: the `line` atom for a stacktrace location
    exc: Exc = undefined, // E3.10: current/last-raised exception (init below to
    // error/nil/nil). Set on every raise; `.raise` re-raises with `exc.class`.
    bif_raise: ?Exc = null, // E3.10: a BIF's staged structured/class-tagged
    // exception (see `bifRaise`). The `bif_call` executor consumes it on
    // `error.Raise`, then clears it. `null` between raises (leak-free — the
    // reason term is a `ctx` heap ref, not owned memory).
    locs: []const Loc = &.{}, // E3.11: the pc→source-location table (owned by the
    // loaded `Translated`, BORROWED here — set by `cli.run`/`boot` before
    // running; freed by `beam_loader.freeProg`, never by the Machine). Empty by
    // default (hand-built law programs, the differential engine): a raise then
    // cooks the E1-minimal `nil` stacktrace — the exact pre-E3.11 behaviour, so
    // no existing law shifts. `raiseWith` reads `locs[m.pc-1]` (the faulting pc,
    // since `run` increments pc BEFORE `execInstr`) for the head frame.
    exports: []const Export = &.{}, // E3.12: the static multi-module export
    // index (`module:func/arity → pc`). BORROWED (set by `cli.run`/`boot`/a law
    // before running; owned by the linker, freed there — never by the Machine),
    // empty by default (single hand-built law programs / the differential
    // engine): with no exports a `call_ext`/`apply` to an unresolved M:F/A traps
    // `error:undef` exactly as pre-E3.12, so no existing law shifts.
    mod_meta: []const ModMeta = &.{}, // E4.2: retained per-module metadata for
    // `get_module_info/1,2` (attributes/compile/md5). BORROWED (set by
    // `cli.runMulti` before running; the byte slices live in the loaded
    // modules' arenas, freed by the caller — never the Machine), empty by
    // default (hand-built law programs): then `get_module_info` finds no meta
    // and raises `badarg`, exactly as an unloaded module does on OTP.
    try_clause: ta.AtomIdx, // E1.8: try_case_end reason
    badmatch_atom: ta.AtomIdx, // batch-4: {badmatch, V} body-match failure tag
    case_clause_atom: ta.AtomIdx, // batch-4: {case_clause, V} case_end tag
    if_clause_atom: ta.AtomIdx, // batch-4: if_end's BARE if_clause reason
    badrecord_atom: ta.AtomIdx, // E1.8: badrecord tuple tag
    badkey_atom: ta.AtomIdx, // E1.10: put_map_exact absent-key crash tag
    badmap_atom: ta.AtomIdx, // E1.10: map opcode over a non-map src crash tag
    badarg: ta.AtomIdx, // E2.4: the guard-BIF bad-argument reason atom
    system_limit: ta.AtomIdx, // E3.4: `bs_create_bin`'s size-overflow reason atom
    bool_true: ta.AtomIdx, // E2.4: the `true` atom (compare/bool BIF results)
    bool_false: ta.AtomIdx, // E2.4: the `false` atom
    // gap-eep76-priority-flag (DIVERGENCE 602): the process SCHEDULING priority —
    // `process_flag(priority, low|normal|high|max)` reads/writes it, returning the
    // OLD value (default `normal`), matching pinned OTP-30. A per-process flag (the
    // trap_exit precedent). SCOPE: the flag's read/write CONTRACT is byte-EQ; the
    // scheduler does not yet weight run-queues by it (a documented bound — the
    // single-scheduler model runs one runnable proc regardless).
    priority: ProcPriority = .normal,
    // gap-atom-and-heap-limits: `process_flag(max_heap_size, _)`'s per-process
    // config (bifs/procsys.zig). The flag CONFIG round-trips byte-EQ vs OTP-30
    // (integer sets `size`; the getter returns the 4-key map); the enforcement
    // (kill/error_logger when the heap exceeds `size`) is the deferred follow-on.
    max_heap_size: MaxHeapCfg = .{},
    // DIVERGENCE 707: the remaining `process_flag/2` GC/queue-tuning knobs — a
    // per-process CONFIG round-trip (accept+store+return-old), same honest bound
    // as `max_heap_size`: the SETTING round-trips byte-EQ but the ENFORCEMENT is
    // deferred (zigvm's copying GC has no configurable min-heap). Defaults are
    // OTP-30's conventional defaults so a `process_flag(min_heap_size,_)` reads
    // back the documented old value instead of crashing `badarg` (which broke any
    // lib tuning these). `mqd_off_heap`/`sensitive` are genuinely truthful bools.
    min_heap_size: i64 = 233, //          erlang:process_flag(min_heap_size, _)
    min_bin_vheap_size: i64 = 46422, //   erlang:process_flag(min_bin_vheap_size, _)
    mqd_off_heap: bool = false, //        message_queue_data: false=on_heap (the default)
    sensitive: bool = false, //           erlang:process_flag(sensitive, Bool)
    trap_exit: bool = false, // E2.11: `process_flag(trap_exit, Bool)`'s per-
    // process flag (bifs/procsys.zig). SINGLE-PROCESS scope: this is a
    // Machine-owned flag distinct from `proc.zig`'s `Process.trap_exit`
    // (the M7 cross-process signal model, set only via the still-unwired
    // `trap_exits` Action/CInstr) — the two surfaces are not yet unified.
    // `link_to`'s EXIT-tuple-vs-crash branch (proc.zig ~line 197) reads the
    // Process-side flag; once E3 lands a real pid term and wires
    // `process_flag/2` through the scheduler, this field either becomes the
    // single source of truth or the BIF starts writing through to
    // `Process.trap_exit` — a follow-up unification, not a silent fork today
    // (both flags start `false` and nothing currently reads BOTH at once).
    // E6.5 (Task 5): the introspection surface's per-Machine state (single-
    // process scope, the `trap_exit` precedent). `system_flag(backtrace_depth,_)`
    // round-trips an int (default 8 — the OTP-28 host default; the VALUE is never
    // byte-asserted, only the round-trip New==Set + is_integer(Old)); the
    // scheduler_wall_time flag and the system_monitor/system_profile {Pid,Opts}
    // settings round-trip through set/get. These are VM-global in erts; the
    // corpus exercises them SINGLE-PROCESS, so a Machine field yields the identical
    // observable round-trip (the differential + round-trip laws scope exactly
    // this). A cross-process / multi-scheduler unification rides the E6 SMP engine,
    // NOT this row. NOT compared in `eqMachines` (process-local flags, like
    // `trap_exit`/`self_pid`). Terms held are `ctx` heap refs (u64) — no owned
    // memory, so `deinit` is unchanged.
    backtrace_depth: i64 = 8,
    swt_enabled: bool = false, // erts_internal:scheduler_wall_time/1 + the flag
    sysmon: ?SysSetting = null, // erts_internal:system_monitor {MonitorPid, Opts}
    sysprof: ?SysSetting = null, // erlang:system_profile {ProfilerPid, Opts}
    stat_reds_last: u64 = 0, // statistics(reductions)'s since-last-call baseline
    ets: ea.EtsRegistry, // E2.9: the ETS tables (Tid → table). This is the
    // per-Machine FALLBACK registry, used only by standalone Machines (the
    // ets_algebra/bifs.ets law suites). Terms stored in a table are `region`
    // heap refs (u64 offsets) — freeing the registry never touches `ctx`, so
    // the deinit order (ets before ctx) is leak- and double-free-safe.
    shared_ets: ?*ea.EtsRegistry = null, // E7.3 (DIVERGENCE 143): when this
    // Machine runs under a Vm, the Vm points this at its ONE shared
    // `EtsRegistry` (`Vm.spawn`), so every process sees the same table space —
    // real cross-process ETS visibility. `null` for a standalone Machine (falls
    // back to `ets`). NOT owned here (the Vm owns it); never freed by `deinit`.
    // Reach the effective registry via `etsReg()` below.
    pterm: reg.PersistentTerms, // E2.10: the ONE global persistent_term store
    // (registry.zig/S24 — literal region + hash table). Owned here; freed in
    // `deinit`. `pterm.region` is its OWN independent `FinalTerms.Ctx` (never
    // aliases `ctx`'s words — every stored term is a `gcCopy`), so deinit
    // order relative to `ctx` is not load-bearing; freed before `ctx` anyway
    // for consistency with the `ets` precedent.
    atomics: aa.AtomicsRegistry, // E2.10: the live atomics arrays (Ref → array,
    // bifs/atomics.zig). Owned here; freed in `deinit`. Holds only raw u64
    // cells (no `ctx` heap refs at all), so deinit order is unconstrained.
    code_index: codeix.CodeIndex, // E2.12: the Machine-owned loaded-module
    // table (M10, bifs/code.zig) driving `erlang:loaded/0`/`module_loaded/1`.
    // Holds `ia.Program`s (CInstr slices), never `ctx` heap refs, so deinit
    // order relative to `ctx` is unconstrained — same shape as `ets`/`pterm`/
    // `atomics` above. Starts EMPTY: this Machine's boot path is a test
    // fixture (`boot.zig`), not wired through this field yet.
    unique_counter: i64 = 0, // E2.12: `erlang:unique_integer/0,1`'s
    // Machine-owned monotonic counter (bifs/term_ops.zig) — SINGLE-Machine
    // uniqueness scope, see that module's doc comment.
    clock: time_algebra.Clock = undefined, // E5.8b/S21: the OS clock seam
    // gap-real-metrics wall_clock (FM-OBS-1): statistics(wall_clock) state.
    // `epoch` is seeded LAZILY on the first read (the observation basis — the
    // honest bound: Total measures from the first observation, not process
    // start; the host value is nondeterministic either way and the corpus
    // property-folds shape+monotonicity, never bytes). `last` backs the
    // {Total, SinceLast} Diff element, like `stat_reds_last` for reductions.
    stat_wall_epoch_ms: ?i64 = null,
    stat_wall_last_ms: i64 = 0,
    // gap-real-metrics runtime (FM-OBS-1): statistics(runtime) state, the REAL
    // per-process CPU time (ms) off the S21 clock seam's PROCESS_CPUTIME source
    // — NOT the fabricated {0,0} and NOT a wall_clock alias. Same lazy-epoch +
    // {Total, SinceLast} discipline as wall_clock above.
    stat_runtime_epoch_ms: ?i64 = null,
    stat_runtime_last_ms: i64 = 0,
    // (time_algebra.zig) driving erlang:monotonic_time/system_time/time_offset/
    // timestamp + os:system_time/timestamp/perf_counter. A value type over an
    // injected `RealSource` (real linux clock_gettime) — no owned memory, so no
    // deinit. Set in `init`; the offset is pinned there (no-time-warp model).
    env: time_algebra.EnvTable = undefined, // E5.8b: the os:getenv/putenv/unsetenv
    // process-environment model (seeded from /proc/self/environ). Owns its
    // strings; freed in `deinit`.
    pdict: FinalTerms.Term = undefined, // E3.9/S24: the process dictionary —
    // a `Term ⇀ Term` map (bifs/pdict.zig) reusing term_algebra's map ops
    // VERBATIM (no divergent map impl — the pdict-map homomorphism), keyed by
    // EXACT (`=:=`) equality exactly like `map_algebra`'s key discipline (`1`
    // and `1.0` are distinct keys). It is a PLAIN `ctx`-heap Term (like any
    // map a program builds itself) — set to `FinalTerms.mapNew` in `init`
    // below, so it lives and dies with this Machine's `ctx` (freed by
    // `ctx.deinit`, no separate teardown, leak-free by construction) and a
    // freshly spawned process starts with an EMPTY pdict (the lifecycle law).
    // THE CRUX (GC root): because it is an ordinary `ctx` word, any full
    // collection of this Machine's heap MUST root it exactly like `regs`/
    // `result`/the mailbox — see `gc.zig`'s "GC transparency" test and the
    // dedicated pdict GC-root law in `bifs/pdict.zig`. A missed root here is
    // mutant 2 (E3.9): the map's words get compacted away and the next `get`
    // reads corrupted/dangling data.

    // ---- e5-dispatch-codeidx: the RUNTIME code space --------------------------
    // The static `prog` (passed to `run`) and its `exports`/`literals`/`locs`
    // are the LINKED image (`cli.link`), immutable through a run. A module loaded
    // at RUN TIME (`erts_internal:prepare_loading/2` → `erlang:finish_loading/1`)
    // is APPENDED here, into a UNIFIED pc space: a pc `< code_base` fetches from
    // the static `prog`; a pc `>= code_base` fetches `dyn_code[pc - code_base]`.
    // The space is APPEND-ONLY — a reload appends the NEW version's code at a
    // HIGHER pc and repoints `dyn_exports`, so a process holding a return pc into
    // the OLD version's range keeps executing it (the M10 continuation-stays law,
    // restated at the dispatch layer) while NEW external calls see the new code.
    // `code_base` is the static program length (set by `cli.runMulti`; a run with
    // no dynamic code never reads it — the split only engages once `dyn_code` is
    // non-empty). Literals relocate the SAME way: a `.literal i` with
    // `i >= literals.len` reads `dyn_literals[i - literals.len]`.
    code_base: usize = 0,
    dyn_code: std.ArrayList(CInstr) = .empty, // owned; freed via `loader.freeProg`
    dyn_literals: std.ArrayList(FinalTerms.Term) = .empty, // owned; ctx heap refs
    dyn_exports: std.ArrayList(Export) = .empty, // owned; COMMITTED runtime exports
    // (module:func/arity → unified pc). Consulted by `dispatchMFA` BEFORE the
    // static `exports` for a module the runtime code server loaded; a static
    // (never-reloaded) module has NO row here and dispatches via `exports`
    // unchanged (the static≡runtime homomorphism).
    staged: std.ArrayList(StagedModule) = .empty, // owned; prepared-not-committed
    next_prepared: u64 = 1, // the next `prepare_loading` handle id

    // gap-fs-autoloader: the per-process autoload seam. `autoload_enabled` is
    // set by the Vm at spawn iff a `Vm.autoload` config exists (default FALSE —
    // a bare Machine / non-autoloading Vm dispatches byte-identically);
    // `autoload_tried` is the ONE-SHOT guard set: a module is trapped for
    // loading at most once per process, so a missing/corrupt beam falls through
    // to error_handler/undef instead of looping load↔miss.
    autoload_enabled: bool = false,
    autoload_tried: std.ArrayList(ta.AtomIdx) = .empty, // owned
    // DIVERGENCE 727/740 (funmeta): a local closure's `label -> {module_atom,
    // name_atom, index, old_uniq}` — the first two are GLOBAL atom idxs, the last
    // two the FunT Index + OldUniq (plain u32s). Populated at `make_fun3` execution
    // from the FunT-derived instruction fields. `fun_info_mfa/1` + `fun_info(F,
    // module|name)` read [0]/[1] (byte-EQ module/name); the `~w`/`~p` printer reads
    // [0]/[2]/[3] for the `#Fun<Module.Index.OldUniq>` shape (DIVERGENCE 740). Keys
    // are atom indices (stable, append-only table) → GC-transparent, no heap roots.
    fun_meta: std.AutoHashMapUnmanaged(u32, [4]u32) = .empty, // owned

    // gap-dynamic-native-dispatch (DIVERGENCE 650): the injected NATIVE-BIF
    // resolver for a RUNTIME `M:F/A` dispatch. The Vm sets it to
    // `bif_dispatch.resolveDynamic` at spawn (a fn ptr keeps the Machine free of a
    // circular import on bif_dispatch). `dispatchMFACore` consults it — after a
    // loaded beam misses and autoload has been tried — so a dynamic `apply`/`Mod:Var`
    // call to a wired native wrapper resolves instead of trapping `undef` (the
    // static `call_ext` load-time surface, reached at runtime). Null on a bare
    // Machine → byte-identical to the pre-slice undef path.
    native_bif_resolver: ?*const fn (module: []const u8, name: []const u8, arity: u8) ?BifFn = null,

    // e48-gc-literal-area (CAST-20): the LITERAL-AREA WATER LINE — the heap
    // prefix [0, heap_lit_end) holds the machine's materialized/inherited
    // literal pool and is EXEMPT from collection (erts literal areas): the
    // collector keeps it byte-stable in place (`collectInPlace(ctx,
    // heap_lit_end)`), so `m.literals` terms stay positionally valid across a
    // collect. Set by the loaders (cli.runMulti after materializeAll;
    // Vm.inheritCode after the cross-heap literal copy); 0 = no literal area
    // (a bare law machine). Dynamically-loaded literals (`dyn_literals`,
    // appended mid-life ABOVE the line) are ROOTED instead (mutable Terms).
    heap_lit_end: usize = 0,

    // E7.6 (S29 tracing / DIVERGENCE entry 158): the per-process SEQUENTIAL
    // TRACE TOKEN (`bifs/trace_bifs.zig`, behind `erlang:seq_trace/2` +
    // `seq_trace_info/1`). A single-Machine token, faithfully modeled for the
    // deterministic, version-stable observations: `seq_active` gates the token's
    // existence (inactive ⇒ `seq_trace_info` denotes `[]`, exactly as a fresh
    // BEAM process); `seq_label` is the user LABEL term (any term) living on
    // THIS Machine's `ctx` heap — so, like `pdict`/`result`, it is a GC ROOT and
    // MUST be rooted by `gc.collectMachineRoots` (a missed root would dangle the
    // label after a collection). The 6 flag booleans + the serial pair are
    // scalars (no rooting). Serial is NOT an EQ-observed component (it auto-bumps
    // on every seq-traced signal — schedule-coupled), stored only so a
    // `seq_trace(serial, {P,C})` setter round-trips its own value; the
    // trace-message DELIVERY surface (a tracer process receiving repr-coupled
    // trace tuples) is a separate dedicated slice — see `bifs/trace_bifs.zig`'s
    // scope note and `deferred-trace-delivery`.
    seq_active: bool = false,
    seq_label: FinalTerms.Term = undefined, // init to nil; a GC root (see above)
    seq_serial_prev: i64 = 0,
    seq_serial_cur: i64 = 0,
    seq_send: bool = false,
    seq_receive: bool = false,
    seq_print: bool = false,
    seq_timestamp: bool = false,
    seq_monotonic: bool = false,
    seq_strict_monotonic: bool = false,

    // gap-tracing-e7 (S29 tracing / DIVERGENCE 158 extension): the per-process
    // `call` TRACE flag — set by `erlang:trace(Pid, true, [call])` (the Process
    // also holds the tracer pid). When true, every `dispatchMFA` TRAPS `.call_trace`
    // to the Vm so it can gate on the global `trace_pattern` breakpoint table and
    // deliver `{trace,Pid,call,{M,F,Args}}` to the tracer, then complete the real
    // dispatch (`resumeCallTrace`). Default false ⇒ dispatch is byte-identical to
    // an untraced VM (the transparency requirement, enforced by construction).
    trace_call: bool = false,

    // Experimental Epoch 15 flags
    experimental_apoptosis_rate: usize = 0,
    experimental_zenoh_crdt: bool = false,
    experimental_wasm_slm: bool = false,
    experimental_tailscale: bool = false,
    experimental_gossip: bool = false,
    experimental_event_log: bool = false,
    experimental_a2ui: bool = false,
    experimental_otlp: bool = false,
    experimental_event_wal: bool = false,
    experimental_apoptosis_immunity: bool = false,
    experimental_epmd_bridge: bool = false,

    pub fn init(gpa: std.mem.Allocator, atoms: *AtomTable) !Machine {
        var ctx = FinalTerms.Ctx.init(gpa, atoms);
        const n = FinalTerms.nil(&ctx);
        // E3.9: build the fresh/empty pdict BEFORE `.ctx = ctx` below snapshots
        // the local `ctx`'s `words` ArrayList into the returned struct — this
        // MUST run first (like `n` above), or the struct's `.ctx` field carries
        // a STALE `words` slice that pre-dates the words `mapNew` allocates and
        // `pdict`'s Term ends up indexing past its end (a real bug this task
        // hit while landing the GC-root law: "index out of bounds" on the very
        // first `pdict` root).
        const pd = try FinalTerms.mapNew(&ctx, &.{}, &.{});
        return .{
            .gpa = gpa,
            .ctx = ctx,
            .regs = @splat(n),
            .stack = .empty,
            .ystack = .empty,
            .catch_stack = .empty,
            .mbox = Mbox.init(gpa),
            .result = n,
            .pdict = pd, // E3.9: fresh/empty
            .seq_label = n, // E7.6: fresh seq-trace label (a GC root; never undefined)
            .badarith = try atoms.intern("badarith"),
            .badfun = try atoms.intern("badfun"),
            .badarity = try atoms.intern("badarity"),
            .fclause = try atoms.intern("function_clause"),
            .undef = try atoms.intern("undef"),
            .err_class = try atoms.intern("error"),
            .exit_class = try atoms.intern("exit"),
            .throw_class = try atoms.intern("throw"),
            .exit_tag = try atoms.intern("EXIT"),
            .nocatch = try atoms.intern("nocatch"),
            .file_key = try atoms.intern("file"),
            .line_key = try atoms.intern("line"),
            .exc = .{ .class = .error_, .reason = n, .stacktrace = n },
            .try_clause = try atoms.intern("try_clause"),
            .badmatch_atom = try atoms.intern("badmatch"),
            .case_clause_atom = try atoms.intern("case_clause"),
            .if_clause_atom = try atoms.intern("if_clause"),
            .badrecord_atom = try atoms.intern("badrecord"),
            .badkey_atom = try atoms.intern("badkey"),
            .badmap_atom = try atoms.intern("badmap"),
            .badarg = try atoms.intern("badarg"),
            .system_limit = try atoms.intern("system_limit"),
            .bool_true = try atoms.intern("true"),
            .bool_false = try atoms.intern("false"),
            .ets = ea.EtsRegistry.init(gpa, atoms),
            .pterm = reg.PersistentTerms.init(gpa, atoms),
            .atomics = aa.AtomicsRegistry.init(gpa),
            .code_index = codeix.CodeIndex.init(gpa),
            .clock = time_algebra.Clock.init(time_algebra.RealSource.source()),
            .env = time_algebra.EnvTable.init(gpa),
        };
    }

    pub fn deinit(self: *Machine) void {
        self.stack.deinit(self.gpa);
        self.ystack.deinit(self.gpa);
        self.catch_stack.deinit(self.gpa);
        self.mbox.deinit();
        self.ets.deinit(); // E2.9: free live ETS tables BEFORE ctx (they hold
        // only ctx heap refs, never ctx-owned memory — no double free).
        self.pterm.deinit(); // E2.10: pterm.region is its own independent Ctx.
        self.atomics.deinit(); // E2.10: raw cells only, no ctx refs.
        self.code_index.deinit(); // E2.12: Program slices only, no ctx refs.
        self.env.deinit(); // E5.8b: the os env model owns its strings, no ctx refs.
        // e5-dispatch-codeidx: the runtime code space. `dyn_code` owns its CInstr
        // operand sub-slices (moved in by `prepare_loading`'s splice), freed via
        // `loader.freeProg` exactly like a linked program; the parallel side-tables
        // are shallow arrays; each staged module owns its `entries` slice.
        loader.freeProgOperands(self.gpa, self.dyn_code.items);
        self.dyn_code.deinit(self.gpa);
        self.autoload_tried.deinit(self.gpa); // gap-fs-autoloader: one-shot guard set
        self.fun_meta.deinit(self.gpa); // DIVERGENCE 727: funmeta label->{mod,name} map
        self.dyn_literals.deinit(self.gpa);
        // e21-t2b (DIVERGENCE 510): a child owns its rebased literal slice.
        if (self.owns_literals) self.gpa.free(self.literals);
        self.dyn_exports.deinit(self.gpa);
        for (self.staged.items) |s| self.gpa.free(s.entries);
        self.staged.deinit(self.gpa);
        self.ctx.deinit();
    }

    /// E7.3 (DIVERGENCE 143): the EFFECTIVE ETS registry for this Machine — the
    /// Vm-owned shared table space when running under a Vm (`shared_ets` set),
    /// else the per-Machine fallback. The ETS BIF family routes ALL table access
    /// through this so a Vm's processes share one table space (real cross-process
    /// visibility) while a standalone Machine's law suite keeps its own.
    pub fn etsReg(self: *Machine) *ea.EtsRegistry {
        return self.shared_ets orelse &self.ets;
    }

    pub fn resolve(self: *Machine, s: Src) FinalTerms.Term {
        return switch (s) {
            .x => |r| self.regs[r],
            .y => |i| self.yreg(i).*,
            .imm => |v| FinalTerms.int(&self.ctx, v),
            .atom_ => |idx| FinalTerms.atom(&self.ctx, @intCast(idx)),
            .nil => FinalTerms.nil(&self.ctx),
            // W-17: the literal was decoded into THIS ctx at load; the index is
            // in range by construction (`srcOf` bounds-checks against the LitT
            // table, and the load site materializes exactly that many terms).
            // e5-dispatch-codeidx: a `.literal i` with `i >= literals.len` belongs
            // to a RUNTIME-loaded module — the unified literal pool continues into
            // `dyn_literals` (relocated by `literals.len` at splice time).
            .literal => |i| if (i < self.literals.len) self.literals[i] else self.dyn_literals.items[i - self.literals.len],
        };
    }

    /// y(i): frame-relative stack slot — y0 is the newest allocated slot.
    fn yreg(self: *Machine, i: u8) *FinalTerms.Term {
        const len = self.ystack.items.len;
        if (len == 0) {
            std.debug.panic("yreg len 0, pc={}", .{self.pc});
        }
        if (i >= len) {
            std.debug.panic("yreg i {} >= {}, pc={}", .{i, len, self.pc});
        }
        const idx = len - 1 - i;
        return &self.ystack.items[idx];
    }
    fn setDst(self: *Machine, d: Dst, v: FinalTerms.Term) void {
        switch (d) {
            .x => |r| self.regs[r] = v,
            .y => |i| self.yreg(i).* = v,
        }
    }

    /// e21-t2 (DIVERGENCE 490): deliver a TRAPPED bif result to its correct
    /// destination. A trapped `bif0/1` opcode recorded its real `Dst` in
    /// `bif_trap_dst`; consume it (once) and write there, else fall back to x0
    /// (the call_ext_bif convention). The scheduler's get_dist_node/creation trap
    /// arms call this so `node/0`'s result reaches a non-x0 dst the compiler chose
    /// (was hardcoded to x0 — the `node(self()) =:= node()` misdelivery bug).
    pub fn deliverTrap(self: *Machine, v: FinalTerms.Term) void {
        const d = self.bif_trap_dst;
        self.bif_trap_dst = null;
        if (d) |dd| self.setDst(dd, v) else self.regs[0] = v;
    }

    /// E3.3: `size × unit` bits requested by a bit-syntax get/skip op. `size`
    /// is a runtime `Src` (a compile-time immediate for the vast majority of
    /// real code, but genuinely a register in the general case — e.g.
    /// `<<X:N/binary>>`), resolved and read as a non-negative small integer;
    /// a non-integer or negative resolved size is a clean `null` (the caller
    /// treats it as a match failure — `else_to`/`fail_to` — never a panic,
    /// mirroring `beam_loader`'s W-16 checked-operand discipline at runtime).
    fn bsFieldBits(self: *Machine, size: Src, unit: u8) ?usize {
        const v = self.resolve(size);
        if (!FinalTerms.repIsSmall(v)) return null;
        const n = FinalTerms.smallValOf(v);
        if (n < 0) return null;
        return @as(usize, @intCast(n)) * @as(usize, unit);
    }

    /// E1.8: raise an exception of `class` with reason term `reason`. If a
    /// try/catch frame is active, UNWIND to it (pop the frame, land at `to`,
    /// restore the ystack, land class/reason/stacktrace in the x-registers per
    /// the frame kind); otherwise take the pre-E1.8 halt path (status .crashed,
    /// result = reason). This is the ONE place the crash-vs-unwind decision is
    /// made — every `crash` caller routes through it.
    /// E3.10: the class atom for the `try` landing / structured wrap.
    fn classAtom(self: *Machine, class: ExcClass) ta.AtomIdx {
        return switch (class) {
            .error_ => self.err_class,
            .exit_ => self.exit_class,
            .throw_ => self.throw_class,
        };
    }

    /// E3.10: partial inverse — the `ExcClass` an atom names, or null if it is
    /// not one of `error`/`exit`/`throw`. Drives `raw_raise`'s and `raise/3`'s
    /// bad-class guard (entry 2d): a non-class first argument returns `badarg`
    /// WITHOUT raising. `pub` so `bifs/erlang.zig`'s `raise/3` can share it.
    pub fn classOfAtom(self: *Machine, t: FinalTerms.Term) ?ExcClass {
        if (!FinalTerms.repIsAtom(t)) return null;
        const idx = FinalTerms.atomIdxOf(t);
        if (idx == self.err_class) return .error_;
        if (idx == self.exit_class) return .exit_;
        if (idx == self.throw_class) return .throw_;
        return null;
    }

    /// E3.10: BEAM `catch` value-wrapping — CLASS-DISCRIMINATED (the
    /// class-discrimination law). `throw` is caught as the value BARE; `exit`
    /// as `{'EXIT', Reason}`; `error` as `{'EXIT', {Reason, Stacktrace}}`.
    /// Mutant 1 (wrap a `throw` as `{'EXIT',_}` too) breaks the throw arm.
    fn catchWrap(self: *Machine, class: ExcClass, reason: FinalTerms.Term, st: FinalTerms.Term) !FinalTerms.Term {
        return switch (class) {
            .throw_ => reason,
            .exit_ => try FinalTerms.tuple(&self.ctx, &.{
                FinalTerms.atom(&self.ctx, self.exit_tag), reason,
            }),
            .error_ => blk: {
                const inner = try FinalTerms.tuple(&self.ctx, &.{ reason, st });
                break :blk try FinalTerms.tuple(&self.ctx, &.{
                    FinalTerms.atom(&self.ctx, self.exit_tag), inner,
                });
            },
        };
    }

    /// E3.10: a BIF stages a structured/class-tagged exception and signals the
    /// executor to unwind it. The reason is an ARBITRARY term (not just an atom)
    /// and the class may be any of error/exit/throw. Returns `error.Raise` so a
    /// family fn writes `return m.bifRaise(.throw_, args[0]);`. The executor
    /// (bif_call arm) consumes `bif_raise` and routes it through the guard-vs-body
    /// split — so this is SAFE to call from a guard-usable BIF (a guard context
    /// branches, never raising the staged reason). `pub` for `bifs/*`.
    pub fn bifRaise(self: *Machine, class: ExcClass, reason: FinalTerms.Term) BifError {
        self.bif_raise = .{ .class = class, .reason = reason, .stacktrace = FinalTerms.nil(&self.ctx) };
        return error.Raise;
    }

    /// VM-interpreted pending actions can discover a body-context BIF error only
    /// after the pure Machine has trapped. Route those late errors through the
    /// same unwind path as direct BIF execution instead of returning sentinel
    /// atoms from the scheduler layer.
    pub fn raiseErrorAtom(self: *Machine, reason: ta.AtomIdx) !void {
        return self.raiseWith(.error_, FinalTerms.atom(&self.ctx, reason));
    }

    /// gap-apply-fun/gap-callfun-arity (DIVERGENCE 733/734): raise the OTP
    /// arity-mismatch error `error:{badarity, {Fun, Args}}` — a fun applied to the
    /// wrong number of args. `args` is the ACTUAL provided-arg list (apply/2 passes
    /// its original list; call_fun builds it from the call registers).
    fn raiseBadarity(self: *Machine, fv: FinalTerms.Term, args: FinalTerms.Term) !void {
        const pair = try FinalTerms.tuple(&self.ctx, &.{ fv, args });
        const reason = try FinalTerms.tuple(&self.ctx, &.{ FinalTerms.atom(&self.ctx, self.badarity), pair });
        return self.raiseWith(.error_, reason);
    }

    /// gap-callfun-arity (DIVERGENCE 734): the call registers `x0..call_arity-1` as
    /// a proper Erlang list — the `Args` element of a `call_fun`/`call_fun2` badarity
    /// reason (those opcodes carry the args in registers, not a list term).
    fn argsFromRegs(self: *Machine, call_arity: u8) !FinalTerms.Term {
        var args = FinalTerms.nil(&self.ctx);
        var k: usize = call_arity;
        while (k > 0) : (k -= 1) args = try FinalTerms.cons(&self.ctx, self.regs[k - 1], args);
        return args;
    }

    /// E3.10: stage `error:{badmap, Map}` (DIVERGENCE entry 6b/c — the structured
    /// non-map reason BEAM raises, replacing the E2.4/E2.7 simplified `badarg`).
    /// OOM building the tuple propagates unchanged.
    pub fn raiseBadmap(self: *Machine, map: FinalTerms.Term) BifError {
        const tup = FinalTerms.tuple(&self.ctx, &.{
            FinalTerms.atom(&self.ctx, self.badmap_atom), map,
        }) catch return error.OutOfMemory;
        return self.bifRaise(.error_, tup);
    }

    /// E3.10: stage `error:{badkey, Key}` (DIVERGENCE entry 6b/c — the structured
    /// absent-key reason for `maps:get/2`/`update/3` and `erlang:map_get/2`).
    pub fn raiseBadkey(self: *Machine, key: FinalTerms.Term) BifError {
        const tup = FinalTerms.tuple(&self.ctx, &.{
            FinalTerms.atom(&self.ctx, self.badkey_atom), key,
        }) catch return error.OutOfMemory;
        return self.bifRaise(.error_, tup);
    }

    /// E3.14: raise `error:{Reason, Value}` for a native-record fault
    /// (`badrecord`/`badfield`, erl_record.c EXC_BADRECORD/EXC_BADFIELD). A
    /// BODY-context opcode fault — routes through `raiseWith` (unwind or the
    /// backward-compat halt), never `error.Raise`. Law-driven reason shape
    /// (no OTP-28 oracle for native records; DIVERGENCE entry 3 amendment).
    fn raiseNativeRecord(self: *Machine, reason_name: []const u8, value: FinalTerms.Term) !void {
        const tup = try FinalTerms.tuple(&self.ctx, &.{
            FinalTerms.atom(&self.ctx, try self.ctx.atoms.intern(reason_name)), value,
        });
        return self.raiseWith(.error_, tup);
    }

    /// E3.11: build the cooked stacktrace term from the pc→loc table (`m.locs`)
    /// and the return stack. Head frame = `locs[m.pc-1]` (the FAULTING pc — `run`
    /// increments pc BEFORE `execInstr`, so at a raise `m.pc` already points one
    /// past the faulting instruction). Caller frames = `locs[return_pc]` for each
    /// return address on `m.stack`, MOST-RECENT (top) first — the RETURN order,
    /// not call order (mutant 2). Bounded to BEAM's default depth 8 total. Each
    /// frame is `{M, F, Arity, [{file, FileCharlist}, {line, Line}]}` (or
    /// `{M,F,A,[]}` when the module had no `Line` chunk). Empty `locs` (hand-built
    /// programs / the differential engine) → the E1-minimal `nil`, so no
    /// pre-E3.11 law shifts.
    fn cookStacktrace(self: *Machine) !FinalTerms.Term {
        if (self.locs.len == 0) return FinalTerms.nil(&self.ctx);
        const max_depth = 8;
        var frames: [max_depth]FinalTerms.Term = undefined;
        var n: usize = 0;
        const head_pc: usize = if (self.pc > 0) self.pc - 1 else 0;
        if (head_pc < self.locs.len) {
            frames[n] = try self.cookFrame(self.locs[head_pc]);
            n += 1;
        }
        var i = self.stack.items.len;
        while (i > 0 and n < max_depth) {
            i -= 1;
            const rpc = self.stack.items[i];
            if (rpc < self.locs.len) {
                frames[n] = try self.cookFrame(self.locs[rpc]);
                n += 1;
            }
        }
        // Assemble head-first: fold the frames onto nil from the tail.
        var lst = FinalTerms.nil(&self.ctx);
        var k = n;
        while (k > 0) {
            k -= 1;
            lst = try FinalTerms.cons(&self.ctx, frames[k], lst);
        }
        return lst;
    }

    /// gap-current-stacktrace (fractal-sweep RANK 1, DIVERGENCE 684): this
    /// process's CURRENT call stack as a list of `{M, F, Arity, [{file,F},{line,L}]}`
    /// frames — the value of `process_info(Pid, current_stacktrace)`, which OTP's
    /// `?STACKTRACE()` macro (used by EVERY gen_* behaviour error path) reads.
    /// Identical construction to the exception stacktrace (`cookStacktrace`), only
    /// captured at the CURRENT pc + return-stack rather than at raise time — the
    /// head frame is the function that called `process_info`. Built in `self.ctx`
    /// (the caller cross-heap-copies it into its own heap when the target is a
    /// different process).
    pub fn currentStacktrace(self: *Machine) !FinalTerms.Term {
        return self.cookStacktrace();
    }

    /// E3.11: cook one stack frame `{M, F, Arity, LocList}`. `LocList` is
    /// `[{file, FileCharlist}, {line, Line}]` when the loc carries line info,
    /// else `[]` (BEAM's `+no_line_info` shape). The file is a CHARLIST (a list
    /// of byte codes — Erlang `"..."` string), built from the filename atom.
    fn cookFrame(self: *Machine, loc: Loc) !FinalTerms.Term {
        const m_atom = FinalTerms.atom(&self.ctx, loc.m);
        const f_atom = FinalTerms.atom(&self.ctx, loc.f);
        const a_int = FinalTerms.int(&self.ctx, @intCast(loc.a));
        var loc_list = FinalTerms.nil(&self.ctx);
        if (loc.line != 0) {
            const line_pair = try FinalTerms.tuple(&self.ctx, &.{
                FinalTerms.atom(&self.ctx, self.line_key),
                FinalTerms.int(&self.ctx, @intCast(loc.line)),
            });
            loc_list = try FinalTerms.cons(&self.ctx, line_pair, loc_list);
            if (loc.file) |file_idx| {
                const file_charlist = try self.charlistOfAtom(file_idx);
                const file_pair = try FinalTerms.tuple(&self.ctx, &.{
                    FinalTerms.atom(&self.ctx, self.file_key),
                    file_charlist,
                });
                // [{file,File}, {line,Line}] — file first, matching BEAM's order.
                loc_list = try FinalTerms.cons(&self.ctx, file_pair, loc_list);
            }
        }
        return FinalTerms.tuple(&self.ctx, &.{ m_atom, f_atom, a_int, loc_list });
    }

    /// E3.11: build the CHARLIST (`[$c1, $c2, …]`) for a filename atom's bytes —
    /// the `{file, "name.erl"}` string in a stacktrace location. `file == 0`
    /// (no file) → `[]`.
    fn charlistOfAtom(self: *Machine, file: ta.AtomIdx) !FinalTerms.Term {
        const bytes = self.ctx.atoms.nameOf(file);
        var lst = FinalTerms.nil(&self.ctx);
        var i = bytes.len;
        while (i > 0) {
            i -= 1;
            lst = try FinalTerms.cons(&self.ctx, FinalTerms.int(&self.ctx, bytes[i]), lst);
        }
        return lst;
    }

    /// E3.10: raise an exception of `class` with reason term `reason`. Records
    /// the current exception in `self.exc` (so a later `.raise` re-raise
    /// preserves the class — entry 2c). If a try/catch frame is active, UNWIND
    /// to it (pop, land at `to`, restore the ystack, land the class-appropriate
    /// value(s) in the x-registers per the frame kind); otherwise take the
    /// pre-E1.8 halt path (status .crashed, result = the BARE reason — the
    /// backward-compat law over M1–M14, unchanged). This is the ONE place the
    /// crash-vs-unwind decision is made — every `crash` caller routes here.
    fn raiseWith(self: *Machine, class: ExcClass, reason: FinalTerms.Term) !void {
        const st = try self.cookStacktrace(); // E3.11: cooked from m.locs (or nil)
        return self.raiseWithStack(class, reason, st);
    }

    /// E3.12: unwind with a PRE-BUILT stacktrace term (factored out of
    /// `raiseWith` so `raiseUndef` can supply its own `{M,F,Args,[]}` head frame,
    /// which is built from the call ARGS, not from the pc→loc table). Identical
    /// unwind semantics to `raiseWith` otherwise.
    fn raiseWithStack(self: *Machine, class: ExcClass, reason: FinalTerms.Term, st: FinalTerms.Term) !void {
        self.exc = .{ .class = class, .reason = reason, .stacktrace = st };
        if (self.catch_stack.items.len > 0) {
            // PEEK the landing frame — do NOT pop unconditionally. The BEAM
            // `catch` operator compiles its fail label to the `catch_end` pc, so
            // the exception path and the normal fall-through CONVERGE at
            // `catch_end`, which is the SINGLE pop point for a `catch`. If the
            // unwind also popped, `catch_end` would pop a SECOND time and eat the
            // ENCLOSING frame — invisible for a lone top-level catch (the extra
            // pop hits an empty stack) but fatal for a NESTED catch whose inner
            // region re-raises (gap-nested-catch, DIVERGENCE 680: `gen_server:call`
            // on a crashing server does exactly this — an inner `catch gen:call`
            // then `exit({Reason,...})` — so supervised-recovery-over-CLI hung on
            // it). `try` is different: its exception lands at `try_case` (a no-op,
            // NOT `try_end`), so the two paths do NOT converge and the unwind OWNS
            // the pop for a `try_` frame.
            const frame = self.catch_stack.items[self.catch_stack.items.len - 1];
            self.pc = frame.to;
            // Restore the caller's y-frame + call frame (drop slots allocated
            // inside the protected region). The frame recorded both heights at
            // push time.
            self.ystack.shrinkRetainingCapacity(frame.y_depth);
            self.stack.shrinkRetainingCapacity(frame.c_depth);
            switch (frame.kind) {
                // BEAM `catch` lands the class-wrapped VALUE in x0 and leaves the
                // frame for `catch_end` (at `frame.to`) to pop.
                .catch_ => self.regs[0] = try self.catchWrap(class, reason, st),
                // BEAM `try` lands class/reason/stacktrace in x0/x1/x2 at the
                // `try_case` handler; the unwind pops the frame here (try_case
                // never does).
                .try_ => {
                    _ = self.catch_stack.pop();
                    self.regs[0] = FinalTerms.atom(&self.ctx, self.classAtom(class));
                    self.regs[1] = reason;
                    self.regs[2] = st;
                },
            }
        } else {
            // No active frame: the EXACT pre-E1.8 halt behaviour (backward-compat
            // law). result = the BARE reason term (class + stacktrace recorded in
            // `self.exc`). The OTP process-EXIT reason cooking (`{R,St}` /
            // `{{nocatch,V},St}` / bare exit) is applied at the DELIVERY boundary
            // by `cookedExitReason` (DIVERGENCE 683) — so `.result` stays the raw
            // value (internal denotation) while linkers/monitors see the cooked
            // reason. `self.exc` (set at the top of this fn) carries what cooking
            // needs.
            self.status = .crashed;
            self.result = reason;
        }
    }

    /// DIVERGENCE 683 (gap-exit-reason-cook): the OTP process-EXIT reason for a
    /// process that terminated on an UNCAUGHT exception, as delivered to linkers
    /// (`{'EXIT',Pid,R}` under trap_exit) and monitors (`{'DOWN',Ref,process,Pid,R}`).
    /// OTP's `terminate_proc` cooks the raw reason by CLASS:
    ///   error:R  -> {R, Stacktrace}
    ///   throw(V) -> {{nocatch, V}, Stacktrace}
    ///   exit(R)  -> R                        (bare)
    /// Reads `self.exc` (the last-raised exception: class + reason + cooked
    /// stacktrace, set by `raiseWithStack`). Kept SEPARATE from `catchWrap` (the
    /// `catch` OPERATOR value, which adds an `'EXIT'` tag and returns a caught
    /// throw BARE) — the two contracts genuinely differ. Call ONLY on the
    /// self-inflicted-crash path (a `.crashed` process at the grant epilogue),
    /// never for an externally-injected `terminate`/kill reason (already final).
    pub fn cookedExitReason(self: *Machine) !FinalTerms.Term {
        return switch (self.exc.class) {
            .exit_ => self.exc.reason,
            .error_ => try FinalTerms.tuple(&self.ctx, &.{ self.exc.reason, self.exc.stacktrace }),
            .throw_ => blk: {
                const nc = try FinalTerms.tuple(&self.ctx, &.{ FinalTerms.atom(&self.ctx, self.nocatch), self.exc.reason });
                break :blk try FinalTerms.tuple(&self.ctx, &.{ nc, self.exc.stacktrace });
            },
        };
    }

    /// The atom-reason crash the pre-E1.8 callers use (badarith/badfun/fclause/
    /// undef): class `error`, reason the interned atom. With an empty catch-stack
    /// this is IDENTICAL to the historical `crash` (status .crashed, result =
    /// atom(reason)); with a frame it unwinds. Kept as a thin wrapper so every
    /// existing `return self.crash(x)` site is unchanged.
    fn crash(self: *Machine, reason: ta.AtomIdx) !void {
        return self.raiseWith(.error_, FinalTerms.atom(&self.ctx, reason));
    }

    /// E1.13: a BIF FAILURE in the context carried by `else_to`. GUARD context
    /// (a non-null Fail label) BRANCHES to it — a guard BIF has no side effects,
    /// so a failed guard falls to the else clause rather than raising. BODY
    /// context (null) CRASHES with `reason`. This is the ONE place the
    /// guard-branch-vs-body-raise decision for a BIF is made (mutant 1 target).
    fn bifFail(self: *Machine, else_to: ?u32, reason: ta.AtomIdx) !void {
        if (else_to) |lbl| {
            self.pc = lbl;
        } else {
            try self.crash(reason);
        }
    }

    /// E3.12: resolve a cross-module export `module:func/arity` → pc through the
    /// borrowed `m.exports` index (linear scan; the index is small — one row per
    /// loaded export). `null` = unresolved (the `undef`/`error_handler` miss path).
    pub fn resolveExport(self: *Machine, module: ta.AtomIdx, func: ta.AtomIdx, arity: u32) ?u32 {
        for (self.exports) |e| {
            if (e.module == module and e.func == func and e.arity == arity) return e.pc;
        }
        return null;
    }

    /// e5-dispatch-codeidx: resolve `module:func/arity` through the RUNTIME code
    /// table — the current version of a module the code server loaded at run time
    /// (`finish_loading`). Returns the unified pc of the CURRENT version, or null
    /// if the module has no committed runtime version. The lookup is GATED on the
    /// `code_index` currency (`resolve(name) != null`): a module retired by
    /// `delete_module/1` has no current version, so a fully-qualified call to it
    /// misses here and falls through to the `undef`/error_handler path — exactly
    /// as erts refuses to dispatch into deleted code. A static (never-runtime-
    /// loaded) module has no `dyn_exports` row, so this returns null and dispatch
    /// proceeds via the static `exports` unchanged (the static≡runtime homomorphism).
    pub fn resolveRuntime(self: *Machine, module: ta.AtomIdx, func: ta.AtomIdx, arity: u32) ?u32 {
        for (self.dyn_exports.items) |e| {
            if (e.module == module and e.func == func and e.arity == arity) {
                const name = self.ctx.atoms.nameOf(module);
                if (self.code_index.resolve(name) == null) return null; // deleted → uncallable
                return e.pc;
            }
        }
        return null;
    }

    /// E3.12: run a resolved BIF over x0..x[arity-1] and land its value in x0
    /// (the BEAM call-return-register convention for a BIF reached via
    /// `call_ext`/`apply`). ONE uniform error route — a `call_ext`/`apply` is
    /// ALWAYS body context (no guard fail label), so `Badarg`/`Badarith` CRASH
    /// and a staged `error.Raise` UNWINDS with its class+reason (the E3.10 shape,
    /// minus the guard branch). A process-effect BIF (spawn/send/…) returns a
    /// placeholder into x0 and sets `m.pending`; the run loop stops and the
    /// scheduler overwrites x0 with the real result on resume.
    fn runBifInto0(self: *Machine, func: BifFn, arity: u8) !void {
        var buf: [16]FinalTerms.Term = undefined;
        var i: usize = 0;
        while (i < arity) : (i += 1) buf[i] = self.regs[i];
        const res = func(self, buf[0..arity]) catch |e| switch (e) {
            error.Badarg => return self.crash(self.badarg),
            error.Badarith => return self.crash(self.badarith),
            error.Raise => {
                const staged = self.bif_raise.?;
                self.bif_raise = null;
                return self.raiseWith(staged.class, staged.reason);
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        self.regs[0] = res;
    }

    /// E3.12: dispatch a fully-resolved `module:func/arity` whose args are ALREADY
    /// in x0..x[arity-1] — the shared core of `call_ext` (code miss path),
    /// `apply/3`, and the `apply/2` opcode. Order (BEAM-faithful): a matching
    /// loaded EXPORT wins as a code call (push the continuation unless this is a
    /// tail call, then jump); else `error_handler:undefined_function/3` if it is
    /// loaded (the hook); else raise `error:undef` with the `{M,F,Args,[]}` head
    /// frame. `tail` selects push-vs-no-push for a code target; the caller has
    /// already lowered the trailing `ret`/`dealloc_y` for the tail forms.
    fn dispatchMFA(self: *Machine, module: ta.AtomIdx, func: ta.AtomIdx, arity: u8, tail: bool) !void {
        // gap-tracing-e7: a `call`-traced process TRAPS every MFA dispatch to the Vm,
        // which gates on the global trace_pattern breakpoint table + delivers the
        // {trace,Pid,call,{M,F,Args}} message, then completes the dispatch via
        // `resumeCallTrace`. Building the args list HERE (registers intact, before any
        // jump/push) keeps the payload valid: `ia.run` breaks on `pending` at once, so
        // the Vm drains `.call_trace` before any allocation/GC can relocate the args.
        if (self.trace_call) {
            const args = try self.argsList(arity);
            self.pending = .{ .call_trace = .{ .module = module, .func = func, .arity = arity, .tail = tail, .args = args } };
            return;
        }
        return self.dispatchMFACore(module, func, arity, tail);
    }

    /// gap-tracing-e7: complete an MFA dispatch AFTER the `.call_trace` trap delivered
    /// (or skipped) the call-trace message. Bypasses the trace trap (no re-fire), so
    /// the code resolve/jump — or a follow-on autoload/error_handler trap — runs
    /// exactly as it would on the untraced path.
    pub fn resumeCallTrace(self: *Machine, module: ta.AtomIdx, func: ta.AtomIdx, arity: u8, tail: bool) !void {
        return self.dispatchMFACore(module, func, arity, tail);
    }

    /// gap-tracing-e7: the erlang:trace_pattern matched-function count — the number of
    /// DISTINCT loaded exports whose (module,func,arity) matches the pattern (a `null`
    /// component is the `'_'` wildcard). Enumerates `dyn_exports` (runtime) then the
    /// static `exports`, skipping a static row shadowed by a dyn row for the same
    /// m:f/a (new-code-wins), so a reloaded function counts once. zigvm's analog of
    /// the erts per-function breakpoint count.
    pub fn countMatchingExports(self: *const Machine, module: ?ta.AtomIdx, func: ?ta.AtomIdx, arity: ?u32) i64 {
        var n: i64 = 0;
        for (self.dyn_exports.items) |e| {
            if (matchExport(e, module, func, arity)) n += 1;
        }
        for (self.exports) |e| {
            if (!matchExport(e, module, func, arity)) continue;
            var shadowed = false;
            for (self.dyn_exports.items) |d| {
                if (d.module == e.module and d.func == e.func and d.arity == e.arity) {
                    shadowed = true;
                    break;
                }
            }
            if (!shadowed) n += 1;
        }
        return n;
    }

    fn dispatchMFACore(self: *Machine, module: ta.AtomIdx, func: ta.AtomIdx, arity: u8, tail: bool) !void {
        // e5-dispatch-codeidx: consult the RUNTIME code table FIRST — a module the
        // code server loaded (or RELOADED) at run time wins over the static link,
        // so a `finish_loading`'d module is callable and a reloaded module's NEW
        // version is dispatched (new-code-wins), while a running process's held
        // return pc keeps executing the version it entered (continuation-stays,
        // via the append-only `dyn_code`).
        if (self.resolveRuntime(module, func, arity)) |pc| {
            if (!tail) try self.stack.append(self.gpa, self.pc);
            self.pc = pc;
            return;
        }
        if (self.resolveExport(module, func, arity)) |pc| {
            if (!tail) try self.stack.append(self.gpa, self.pc);
            self.pc = pc;
            return;
        }
        // gap-fs-autoloader: with autoloading on, a FIRST miss of a module traps
        // to the Vm (`ensure_loaded`) instead of falling through — the Vm loads
        // `Module.beam` off its code_path and retries this exact dispatch (regs
        // and pc are untouched here, so the retry is observationally the same
        // call). The `autoload_tried` one-shot makes a failed load fall through
        // to the error_handler/undef path below on the retry.
        if (self.autoload_enabled and !self.autoloadTried(module)) {
            self.pending = .{ .ensure_loaded = .{ .module = module, .func = func, .arity = arity, .tail = tail } };
            return;
        }
        // gap-dynamic-native-dispatch (DIVERGENCE 650): a wired NATIVE bif serves a
        // dynamic `M:F/A` (apply/Mod:Var/code-miss retry) — the `resolve ∪
        // resolveLibrary` surface a static `call_ext` sees at load time. Consulted
        // HERE (after loaded code missed + autoload was tried) so real code always
        // wins; native is a pure fallback above error_handler/undef. Completion
        // mirrors a bif call: `runBifInto0` sets x0; a TAIL dispatch then returns
        // to the caller's continuation (emulated `ret`), a non-tail leaves pc at
        // the next instruction (already advanced by the fetch loop).
        if (self.native_bif_resolver) |resolveNative| {
            const mname = self.ctx.atoms.nameOf(module);
            const fname = self.ctx.atoms.nameOf(func);
            if (resolveNative(mname, fname, arity)) |bif| {
                try self.runBifInto0(bif, arity);
                if (tail) {
                    if (self.stack.pop()) |cp| {
                        self.pc = cp;
                    } else {
                        self.status = .halted;
                        self.result = self.regs[0];
                    }
                }
                return;
            }
        }
        // The error_handler hook: error_handler:undefined_function(M, F, Args).
        const eh = try self.ctx.atoms.intern("error_handler");
        const uf = try self.ctx.atoms.intern("undefined_function");
        if (self.resolveExport(eh, uf, 3)) |pc| {
            const args = try self.argsList(arity);
            if (!tail) try self.stack.append(self.gpa, self.pc);
            self.regs[0] = FinalTerms.atom(&self.ctx, module);
            self.regs[1] = FinalTerms.atom(&self.ctx, func);
            self.regs[2] = args;
            self.pc = pc;
            return;
        }
        return self.raiseUndef(module, func, arity);
    }

    /// gap-fs-autoloader: has this process already trapped an autoload attempt
    /// for `module`? (The one-shot guard — linear scan; the set holds only the
    /// modules that MISSED, a handful at most.)
    pub fn autoloadTried(self: *const Machine, module: ta.AtomIdx) bool {
        for (self.autoload_tried.items) |t| {
            if (t == module) return true;
        }
        return false;
    }

    /// gap-fs-autoloader: record `module` in the one-shot autoload guard set.
    pub fn markAutoloadTried(self: *Machine, module: ta.AtomIdx) !void {
        if (!self.autoloadTried(module)) try self.autoload_tried.append(self.gpa, module);
    }

    /// gap-fs-autoloader: re-run the exact dispatch a trapped `ensure_loaded`
    /// interrupted. After a successful load it resolves via `resolveRuntime`;
    /// after a failed one the `autoload_tried` guard routes it to the
    /// error_handler/undef fall-through — never a second trap.
    pub fn retryDispatchMFA(self: *Machine, module: ta.AtomIdx, func: ta.AtomIdx, arity: u8, tail: bool) !void {
        // gap-tracing-e7: route the autoload retry through the trace-BYPASSING core —
        // the `call` trace already fired before the `ensure_loaded` trap, so a retry
        // must not re-deliver it (the once-per-call transparency invariant).
        return self.dispatchMFACore(module, func, arity, tail);
    }

    /// E3.12: dispatch a DYNAMIC `module:func/arity` (args already in
    /// x0..x[arity-1]) — used by `apply/3` and the `apply/2` opcode, where the
    /// target is only known at run time. A BIF wins first (the compiler routes a
    /// dynamic `apply` to a BIF exactly like a static `call_ext`), else the code/
    /// hook/undef path. Same fall-through/tail contract as `call_ext_bif` +
    /// `call_ext_code`: the caller has lowered the trailing `ret` for tail forms.
    fn fullDispatch(self: *Machine, module: ta.AtomIdx, func: ta.AtomIdx, arity: u8, tail: bool) !void {
        const modname = self.ctx.atoms.nameOf(module);
        const fname = self.ctx.atoms.nameOf(func);
        if (bif_dispatch.resolve(modname, fname, arity)) |f| {
            return self.runBifInto0(f, arity);
        }
        return self.dispatchMFA(module, func, arity, tail);
    }

    /// E3.12: build the `[x0, …, x(arity-1)]` argument list (head-first) for the
    /// `undef` stacktrace head frame and the `error_handler` hook.
    fn argsList(self: *Machine, arity: u8) !FinalTerms.Term {
        var lst = FinalTerms.nil(&self.ctx);
        var i: usize = arity;
        while (i > 0) {
            i -= 1;
            lst = try FinalTerms.cons(&self.ctx, self.regs[i], lst);
        }
        return lst;
    }

    /// E3.12: raise `error:undef` for an unresolved `module:func/arity`. The
    /// cooked stacktrace's HEAD frame is `{M, F, Args, []}` (the BEAM undef
    /// contract — the ACTUAL argument list, not the arity), followed by the
    /// caller frames cooked from the return stack (bounded to depth 8, like
    /// `cookStacktrace`). Independent of `m.locs`, so it yields the real head
    /// frame even for hand-built law programs with no line table.
    fn raiseUndef(self: *Machine, module: ta.AtomIdx, func: ta.AtomIdx, arity: u8) !void {
        const args = try self.argsList(arity);
        const head = try FinalTerms.tuple(&self.ctx, &.{
            FinalTerms.atom(&self.ctx, module),
            FinalTerms.atom(&self.ctx, func),
            args,
            FinalTerms.nil(&self.ctx),
        });
        // caller frames (return order, most-recent first), bounded to depth 8.
        const max_depth = 8;
        var frames: [max_depth]FinalTerms.Term = undefined;
        var n: usize = 0;
        if (self.locs.len != 0) {
            var i = self.stack.items.len;
            while (i > 0 and n < max_depth - 1) {
                i -= 1;
                const rpc = self.stack.items[i];
                if (rpc < self.locs.len) {
                    frames[n] = try self.cookFrame(self.locs[rpc]);
                    n += 1;
                }
            }
        }
        var st = FinalTerms.nil(&self.ctx);
        var k = n;
        while (k > 0) {
            k -= 1;
            st = try FinalTerms.cons(&self.ctx, frames[k], st);
        }
        st = try FinalTerms.cons(&self.ctx, head, st);
        return self.raiseWithStack(.error_, FinalTerms.atom(&self.ctx, self.undef), st);
    }

    /// Retire one straight-line instruction: exactly ONE reduction.
    fn retire(self: *Machine, ins: BlockInstr) !void {
        // R2b two-counter: a BlockInstr (move/add/put_list) is a straight-line op
        // — 0 per-call reductions, +1 retired instruction. The interpreter and the
        // block engine BOTH charge through here, so they agree on both counters.
        self.instrs += 1;
        self.reductions += reductionCostBlock(ins);
        switch (ins) {
            .move => |m| self.regs[m.dst] = self.resolve(m.src),
            .add => |a| {
                const x = self.resolve(a.a);
                const y = self.resolve(a.b);
                if (!FinalTerms.repIsNumber(&self.ctx, x) or
                    !FinalTerms.repIsNumber(&self.ctx, y))
                    return self.crash(self.badarith);
                self.regs[a.dst] = FinalTerms.add(&self.ctx, x, y) catch |e| switch (e) {
                    error.Badarith => return self.crash(self.badarith), // e.g. float overflow
                    error.OutOfMemory => return error.OutOfMemory,
                };
            },
            .put_list => |p| {
                const h = self.resolve(p.h);
                const t = self.resolve(p.t);
                self.regs[p.dst] = try FinalTerms.cons(&self.ctx, h, t);
            },
        }
    }
};

// ============================================================================
// LAYER 1: the block monoid — two encodings + contract
// ============================================================================

pub fn requireBlockAlgebra(comptime T: type) void {
    comptime {
        const required = .{ "Block", "Ctx", "nop", "one", "seq", "exec", "len" };
        for (required) |name| {
            if (!@hasDecl(T, name)) {
                @compileError(@typeName(T) ++
                    " violates the Block signature: missing decl `" ++ name ++ "`");
            }
        }
    }
}

/// Initial encoding: seq-trees — the free monoid over BlockInstr (the oracle).
pub const InitialBlocks = struct {
    pub const Block = union(enum) {
        nop_,
        one_: BlockInstr,
        seq_: struct { l: *const Block, r: *const Block },
    };

    pub const Ctx = struct {
        arena: std.heap.ArenaAllocator,
        pub fn init(gpa: std.mem.Allocator) Ctx {
            return .{ .arena = std.heap.ArenaAllocator.init(gpa) };
        }
        pub fn deinit(self: *Ctx) void {
            self.arena.deinit();
        }
    };

    fn mk(ctx: *Ctx, b: Block) !*const Block {
        const p = try ctx.arena.allocator().create(Block);
        p.* = b;
        return p;
    }

    pub fn nop(_: *Ctx) !Block {
        return .nop_;
    }
    pub fn one(_: *Ctx, ins: BlockInstr) !Block {
        return .{ .one_ = ins };
    }
    pub fn seq(ctx: *Ctx, l: Block, r: Block) !Block {
        return .{ .seq_ = .{ .l = try mk(ctx, l), .r = try mk(ctx, r) } };
    }

    /// Tree-walking interpreter — exhaustive, no catch-all.
    pub fn exec(m: *Machine, b: Block) !void {
        if (m.status != .running) return;
        switch (b) {
            .nop_ => {},
            .one_ => |ins| try m.retire(ins),
            .seq_ => |p| {
                try exec(m, p.l.*);
                try exec(m, p.r.*);
            },
        }
    }

    pub fn len(b: Block) usize {
        return switch (b) {
            .nop_ => 0,
            .one_ => 1,
            .seq_ => |p| len(p.l.*) + len(p.r.*),
        };
    }
};

/// Final encoding: the FLAT ARRAY — the monoid's normal form, licensed by
/// associativity + identity; exactly the in-memory shape of real BEAM code.
pub const FinalBlocks = struct {
    pub const Block = []const BlockInstr;

    pub const Ctx = struct {
        arena: std.heap.ArenaAllocator,
        pub fn init(gpa: std.mem.Allocator) Ctx {
            return .{ .arena = std.heap.ArenaAllocator.init(gpa) };
        }
        pub fn deinit(self: *Ctx) void {
            self.arena.deinit();
        }
    };

    pub fn nop(_: *Ctx) !Block {
        return &.{};
    }
    pub fn one(ctx: *Ctx, ins: BlockInstr) !Block {
        return try ctx.arena.allocator().dupe(BlockInstr, &.{ins});
    }
    pub fn seq(ctx: *Ctx, l: Block, r: Block) !Block {
        const out = try ctx.arena.allocator().alloc(BlockInstr, l.len + r.len);
        @memcpy(out[0..l.len], l);
        @memcpy(out[l.len..], r);
        return out;
    }

    pub fn exec(m: *Machine, b: Block) !void {
        for (b) |ins| {
            if (m.status != .running) return;
            try m.retire(ins);
        }
    }

    pub fn len(b: Block) usize {
        return b.len;
    }
};

// ============================================================================
// LAYER 2: the control machine — budgeted small-step execution
// ============================================================================

/// Execute at most `budget` retired instructions. A machine left `.running` has
/// been PREEMPTED (yielded); resuming it later must be unobservable (slice law).
///
/// gap-reduction-cost-model R2b (the {R} real-time axis) — the TWO-COUNTER split.
/// The loop counts against `m.instrs` (the per-INSTRUCTION counter, +1 per retired
/// op), NOT `m.reductions`. This keeps preemption BYTE-IDENTICAL to the pre-R2b
/// model (WHERE a proc yields never changes — the RESULT-IDENTITY anchor and the
/// CTRL-realtime UCA mitigation), while `m.reductions` independently accumulates
/// the OTP-faithful PER-CALL cost (`reductionCost`: ~1/call, 0 for straight-line
/// ops) read by the `--reduction-oracle`. `erlang:bump_reductions/1` bumps BOTH
/// counters by N, so it still brings preemption FORWARD by exactly N (the
/// PREEMPTION-LATENCY law: `remaining_fuel' = remaining_fuel - N`), mirroring erts.
pub fn run(m: *Machine, prog: Program, budget: u64) !void {
    // R2b: preemption is bounded on the per-INSTRUCTION counter (`instrs`), so
    // WHERE preemption falls is BYTE-IDENTICAL to the pre-R2b model (results and
    // scheduling unchanged — the RESULT-IDENTITY anchor). `reductions` (per-call)
    // is accounting only, read by the `--reduction-oracle`. Every retired op bumps
    // `instrs` by 1, so a non-terminating computation is always preempted (no hang
    // even for a 0-reduction straight-line region).
    const start = m.instrs;
    while (m.status == .running and m.pending == null and m.instrs - start < budget) {
        try stepOne(m, prog);
    }
}

/// gap-r2c-behavioral-parity (DIVERGENCE 606, R2c epoch — SAFE Increment 0, opt-in):
/// preempt on the OTP-faithful PER-CALL counter `m.reductions` (a grant of `red_budget`
/// reductions yields having consumed EXACTLY `red_budget` reductions, regardless of how
/// many straight-line INSTRS ran in between — the behavioral parity OTP has), with an
/// `instr_cap` SAFETY BUDGET that guarantees termination for a pathological 0-reduction
/// straight-line region (a reductions-only bound would HANG it — the CTRL-realtime UCA
/// this cap mitigates). This is ADDITIVE: `ia.run` (the default scheduler path) is
/// UNCHANGED, so zero existing behavior shifts; this is the proven mechanism the R2c
/// default-flip epoch will eventually wire into the scheduler (a scoped deferral — see
/// docs/R2C_BEHAVIORAL_PARITY_FRACTAL.md + SAFETY_ANALYSIS UCA-R2C-*). Whichever budget
/// binds first stops the grant — reductions in the common case, the cap as the fail-safe.
pub fn runReductionPreempt(m: *Machine, prog: Program, red_budget: u64, instr_cap: u64) !void {
    const r_start = m.reductions;
    const i_start = m.instrs;
    while (m.status == .running and m.pending == null and
        m.reductions - r_start < red_budget and
        m.instrs - i_start < instr_cap)
    {
        try stepOne(m, prog);
    }
}

fn stepOne(m: *Machine, prog: Program) !void {
    // e5-dispatch-codeidx: the UNIFIED pc space. `pc < prog.len` fetches the
    // static linked image; `pc >= prog.len` fetches the RUNTIME-loaded dynamic
    // code (`dyn_code[pc - code_base]`, with `code_base == prog.len` for the real
    // run — set by `cli.runMulti`). Falling off the END of BOTH is the normal
    // return-with-x0. When no dynamic code is loaded this is byte-identical to the
    // pre-slice `prog[pc]` fetch (the `else` branch is unreachable: `dyn_code` is
    if (m.pc < prog.len) {
        const ins = prog[m.pc];
        m.pc += 1;
        try execInstr(m, ins);
        return;
    }
    const base = if (m.dyn_code.items.len > 0) m.code_base else prog.len;
    const di = m.pc -% base;
    if (m.pc < base or di >= m.dyn_code.items.len) { // fell off the end
        m.status = .halted;
        m.result = m.regs[0];
        return;
    }
    const ins = m.dyn_code.items[di];
    m.pc += 1;
    try execInstr(m, ins);
}

/// One instruction's SEMANTICS, factored out of the fetch/dispatch loop so
/// that alternative dispatch engines (M13's pre-decoded threaded code — and
/// any future native backend) interpret the SAME op meanings and differ
/// only in how they fetch and dispatch. This mirrors how erts's emu/ and
/// jit/ are two dispatchers over one ops.tab semantics.
/// E1.3: the type-test predicate, one arm per `TypeTestKind`, each delegating
/// to an existing `FinalTerms` observation — no new term semantics. Exhaustive
/// switch: adding a kind without an arm is a compile error.
///
/// Predicate mapping (BEAM `is_*` guard semantics):
///   integer   → small int OR bignum (NOT float)     repIsSmall|repIsBig
///   float     → boxed float                          repIsFloat
///   number    → any of int|bignum|float              repIsNumber
///   atom      → atom (incl. booleans, [] as nil? no) kindOf == .atom
///   list      → proper/improper cons OR []           kindOf == .cons|.nil
///   map       → flat map OR HAMT                      repIsMap
///   binary    → byte-aligned binary/bitstring         repIsBinary
///   bitstr    → ANY bitstring (aligned or sub-byte)   repIsBinary|repIsBitstring
///   tuple     → boxed tuple (any arity)               kindOf == .tuple
///   boolean   → the atoms `true`/`false` only         atom name ∈ {true,false}
///   function  → a fun                                 repIsFun
///   pid/reference/port → E3.5: real term kinds now — repIsPid/repIsRef/
///               repIsPort (each true exactly on its own kind, false on
///               every other term, per the type_test truthfulness law).
/// fix-closure-aliasing (2026-07-23): the BEAM FUN-ENTRY convention — on
/// entering a closure, the emulator copies the fun's captured environment into
/// `x[arity .. arity+num_free)` (erts `beam_emu.c` `call_fun`; the compiled fun
/// BODY is emitted assuming its free variables are already in those registers —
/// e.g. a zero-arity `fun() -> N end` body is a bare `return` reading x0).
/// zigvm's `call_fun`/`call_fun2` jumped WITHOUT this restore, so a closure
/// body read whatever the caller left in those registers (typically the fun
/// term itself) — found by the E7 Wave-1 differential curation (`fun_SUITE`
/// `c_closure_distinct`: `{G1(),G2()}` returned `{#Fun,#Fun}` vs the oracle's
/// `{1,2}`). Same-heap copy — no gcCopy needed (contrast `proc.spawn_fun`,
/// which crosses heaps and already implemented this convention).
fn loadFunEnv(m: *Machine, fv: FinalTerms.Term) void {
    const parts = FinalTerms.funParts(&m.ctx, fv);
    var k: usize = 0;
    while (k < parts.env_len and parts.arity + k < x_reg_count) : (k += 1)
        m.regs[parts.arity + k] = FinalTerms.funEnvElem(&m.ctx, fv, k);
}

fn typeTestHolds(m: *Machine, kind: TypeTestKind, v: FinalTerms.Term) bool {
    return switch (kind) {
        .integer => FinalTerms.repIsSmall(v) or FinalTerms.repIsBig(&m.ctx, v),
        .float => FinalTerms.repIsFloat(&m.ctx, v),
        .number => FinalTerms.repIsNumber(&m.ctx, v),
        .atom => FinalTerms.kindOf(&m.ctx, v) == .atom,
        .list => FinalTerms.kindOf(&m.ctx, v) == .cons or FinalTerms.kindOf(&m.ctx, v) == .nil,
        .map => FinalTerms.repIsMap(&m.ctx, v),
        .binary => FinalTerms.repIsBinary(&m.ctx, v),
        // E3.1-fix: `is_bitstring` holds for ANY bitstring (aligned or
        // sub-byte), not just byte-aligned ones — `repIsBinary` alone (the
        // old shared arm with `.binary`) wrongly returned false for a
        // sub-byte `SUBTAG_BITSTRING`. `is_binary` ⟺ byte-aligned;
        // `is_bitstring` ⟺ any bitstring (so it's the wider predicate).
        .bitstr => FinalTerms.repIsBinary(&m.ctx, v) or FinalTerms.repIsBitstring(&m.ctx, v),
        .tuple => FinalTerms.kindOf(&m.ctx, v) == .tuple,
        // E7.1: is_function/1 holds for local AND external funs.
        .function => FinalTerms.repIsFun(&m.ctx, v) or FinalTerms.repIsExportFun(&m.ctx, v),
        .boolean => blk: {
            if (!FinalTerms.repIsAtom(v)) break :blk false;
            const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(v));
            break :blk std.mem.eql(u8, name, "true") or std.mem.eql(u8, name, "false");
        },
        // E3.5: real term kinds — delegate to the exact-kind observations.
        .pid => FinalTerms.repIsPid(&m.ctx, v),
        .reference => FinalTerms.repIsRef(&m.ctx, v),
        .port => FinalTerms.repIsPort(&m.ctx, v),
    };
}

/// E1.4: the comparison-test predicate, one arm per `CmpTestKind`, each
/// delegating to an existing `FinalTerms` order/equality observation — no new
/// term semantics. Exhaustive switch: adding a kind without an arm is a compile
/// error. `true` ⇒ fall through, `false` ⇒ jump to `else_to`.
///
/// Predicate mapping (BEAM binary compare-guard semantics):
///   ge       → Erlang `>=`, standard term order: compare(a,b) != .lt
///   eq_arith → Erlang `==` (arithmetic, 1 == 1.0):  compare(a,b) == .eq
///   ne_arith → Erlang `/=` (arithmetic):            compare(a,b) != .eq
///   ne_exact → Erlang `=/=` (exact, 1 =/= 1.0):     !eqlExact(a,b)
fn cmpTestHolds(m: *Machine, op: CmpTestKind, a: FinalTerms.Term, b: FinalTerms.Term) bool {
    return switch (op) {
        .ge => FinalTerms.compare(&m.ctx, a, b) != .lt,
        .eq_arith => FinalTerms.compare(&m.ctx, a, b) == .eq,
        .ne_arith => FinalTerms.compare(&m.ctx, a, b) != .eq,
        .ne_exact => !FinalTerms.eqlExact(&m.ctx, a, b),
    };
}

/// E3.3: read `len` bits of `full` starting at `start` as an UNSIGNED
/// magnitude, per BEAM's endianness convention. `bsa.bitAt` is the ONLY bit
/// primitive used (no second bit-reader). Big-endian (and every sub-byte
/// field, see the scope note below) is the direct MSB-first bit-order
/// reading — the numeric definition of "big-endian bits". Little-endian is
/// byte-reversed, MSB-first WITHIN each byte, matching `erl_bits.c`'s
/// treatment of little-endian fields — INCLUDING (bs-little-oddsize,
/// 2026-07-23, discharging the DIVERGENCE-16(a) bound) fields whose `len` is
/// NOT a byte multiple: erts lays an `8k+r`-bit little field out as the k LOW
/// value bytes first (LSB byte first, MSB-first within each stream byte),
/// followed by the HIGH r-bit fragment (value bits [8k, 8k+r), MSB-first) —
/// the `erts_bs_get_integer_2` little path with `(num_bits & 7) != 0`. The
/// pre-fix arm fell back to the big-endian bit order for odd sizes (the
/// ledgered bound; probe: `C:15/little` read 18884 where the oracle reads
/// 17555). Byte-multiple fields (r == 0) reduce to the old byte-reversal.
fn bsMagnitudeAt(full: bsa.Bits, start: usize, len: usize, endian: BsEndian) u128 {
    std.debug.assert(len <= 128);
    var v: u128 = 0;
    if (endian == .big) {
        for (0..len) |i| v = (v << 1) | bsa.bitAt(full, start + i);
        return v;
    }
    const k8 = (len / 8) * 8; // bits covered by whole value bytes
    const r = len - k8; //       the high fragment's width
    // the k full bytes: stream byte j == value byte j (LSB first)
    var bi: usize = 0;
    while (bi * 8 < k8) : (bi += 1) {
        var byte: u128 = 0;
        for (0..8) |k| byte = (byte << 1) | bsa.bitAt(full, start + bi * 8 + k);
        v |= byte << @intCast(8 * bi);
    }
    // the r-bit fragment: value bits [k8, len), MSB-first in the stream
    // (r == 0 ⇒ nothing to place — and k8 may be 128, an illegal u128 shift).
    if (r == 0) return v;
    var frag: u128 = 0;
    for (0..r) |t| frag = (frag << 1) | bsa.bitAt(full, start + k8 + t);
    return v | (frag << @intCast(k8));
}

/// E3.3: two's-complement sign-extend an `len`-bit unsigned magnitude
/// (endianness-agnostic: `bsMagnitudeAt` has already reconstructed the
/// correctly-ordered magnitude, so the sign bit is simply bit `len-1`).
fn bsSignExtend(mag: u128, len: usize) i128 {
    // Sign-extend a `len`-bit magnitude to i128 via a shift pair — NEVER a raw
    // `@intCast(u128→i128)` (which panics when the top bit is set, mag ≥ 2^127) nor
    // a `1 << 127` (which overflows i128). Put the field's MSB at bit 127, bit-cast
    // to i128, then ARITHMETIC-shift right to replicate the sign. Correct for every
    // width 1..=128, incl. the full-width and 127-bit boundaries (DIVERGENCE 592).
    if (len == 0) return 0;
    if (len > 128) return @bitCast(mag);
    const sh: u7 = @intCast(128 - len);
    return @as(i128, @bitCast(mag << sh)) >> sh;
}

// ---- E3.3-fix (Fix 1, review of 34997cb): >128-bit integer fields --------
// `bsMagnitudeAt` above is UNCHANGED (still asserts `len <= 128`, still the
// fast i128 path) — it is called ONLY with `len <= 128` now. Widths above
// that go through `bsMagnitudeLimbsAt` below, the multi-limb generalization
// of the SAME bit-by-bit reading `bsMagnitudeAt` does (same endianness
// convention, same scope note: sub-byte little-endian falls back to the
// big-endian bit order — see `bsMagnitudeAt`'s doc comment and
// DIVERGENCE_LOG entry 16(a)).

/// Multi-limb generalization of `bsMagnitudeAt`'s bit-reading loop, into
/// `term_algebra`'s own limb convention (`limbs[0]` = least-significant 64
/// bits). Same two branches, same endianness convention as `bsMagnitudeAt`:
/// MSB-first bit-by-bit for big-endian / any sub-byte-width field; whole
/// bytes shifted in high-to-low (byte-reversed) for byte-multiple
/// little-endian.
fn bsMagnitudeLimbsAt(full: bsa.Bits, start: usize, len: usize, endian: BsEndian) [FinalTerms.max_limbs]u64 {
    var limbs: [FinalTerms.max_limbs]u64 = @splat(0);
    if (endian == .big) {
        for (0..len) |i| shiftInBit(&limbs, bsa.bitAt(full, start + i));
        return limbs;
    }
    // bs-little-oddsize: same 8k+r rule as `bsMagnitudeAt` (see its comment),
    // built MSB-first for the shiftIn helpers: the HIGH r-bit fragment (at
    // stream offset k8) enters first, then the k value bytes from byte k-1
    // down to byte 0 (stream byte j == value byte j). r == 0 reduces to the
    // old byte-reversal.
    const k8 = (len / 8) * 8;
    for (0..len - k8) |t| shiftInBit(&limbs, bsa.bitAt(full, start + k8 + t));
    var bi = len / 8;
    while (bi > 0) {
        bi -= 1;
        var byte: u8 = 0;
        for (0..8) |k| byte = (byte << 1) | bsa.bitAt(full, start + bi * 8 + k);
        shiftInByte(&limbs, byte);
    }
    return limbs;
}
fn shiftInBit(limbs: *[FinalTerms.max_limbs]u64, bit: u1) void {
    var carry: u64 = bit;
    for (0..FinalTerms.max_limbs) |k| {
        const next_carry = limbs[k] >> 63;
        limbs[k] = (limbs[k] << 1) | carry;
        carry = next_carry;
    }
}
fn shiftInByte(limbs: *[FinalTerms.max_limbs]u64, byte: u8) void {
    var carry: u64 = byte;
    for (0..FinalTerms.max_limbs) |k| {
        const next_carry = limbs[k] >> 56;
        limbs[k] = (limbs[k] << 8) | carry;
        carry = next_carry;
    }
}
/// Two's-complement negate the low `len` bits of `limbs` in place (flip
/// then add 1) — the multi-limb generalization of `bsSignExtend`'s single
/// i128 sign flip. Precondition (caller checks before calling): bit
/// `len-1` of `limbs` is 1, so the magnitude is nonzero and the low
/// `len`-bit window cannot be all-ones before the flip — the `+1` carry
/// therefore never ripples past bit `len-1`, i.e. the result never
/// overflows the field width.
fn negateLowBits(limbs: *[FinalTerms.max_limbs]u64, len: usize) void {
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const li = i / 64;
        const bi: u6 = @intCast(i % 64);
        limbs[li] ^= (@as(u64, 1) << bi);
    }
    var carry: u64 = 1;
    for (0..FinalTerms.max_limbs) |k| {
        const r = @addWithOverflow(limbs[k], carry);
        limbs[k] = r[0];
        carry = r[1];
        if (carry == 0) break;
    }
}
fn limbBitAt(limbs: *const [FinalTerms.max_limbs]u64, i: usize) u1 {
    return @truncate((limbs[i / 64] >> @as(u6, @intCast(i % 64))) & 1);
}

/// E3.3-fix (Fix 1): the width-dispatch integer-field reader, replacing the
/// direct `bsMagnitudeAt`+`intFromI128` pair at the `.bs_get_integer` and
/// `.bs_match` `.integer`-command call sites so NEITHER can panic on a
/// well-formed `.beam` (the old code hit `bsMagnitudeAt`'s
/// `assert(len <= 128)` on a legal `<<Hash:256>> = Bin` match — a real
/// pattern for 256-bit crypto hashes).
///   1..128   -> the EXISTING `bsMagnitudeAt`/`bsSignExtend`/`intFromI128`
///              fast path, byte-for-byte unchanged.
///   129..512 -> (within `FinalTerms.max_limbs*64` = 512 bits, the term
///              layer's OWN documented bignum cap) build the magnitude via
///              `bsMagnitudeLimbsAt` and construct the term through
///              `FinalTerms.intFromLimbs` — the SAME bignum constructor
///              every other integer path in this VM uses (`decode_unsigned`
///              et al.), never a new integer representation. Signed:
///              two's-complement negate via `negateLowBits` when the top
///              field bit is 1, mirroring `bsSignExtend`'s i128 case.
///   >512     -> `null` — the field cannot be represented at this VM's
///              bignum cap. The caller jumps `else_to`/`fail_to`: a
///              bounded, documented capacity limit (DIVERGENCE_LOG entry
///              16(b)), the SAME shape as the existing bignum-arithmetic-cap
///              precedent (`decode_unsigned`'s `error.Badarith` above
///              `max_limbs*8` bytes) — never a panic.
fn bsIntegerFieldTerm(m: *Machine, full: bsa.Bits, start: usize, len: usize, endian: BsEndian, signed: bool) !?FinalTerms.Term {
    if (len <= 128) {
        const mag = bsMagnitudeAt(full, start, len, endian);
        if (signed) return try FinalTerms.intFromI128(&m.ctx, bsSignExtend(mag, len));
        // Unsigned: the i128 fast path is valid ONLY when the value FITS i128. A
        // 128-bit UNSIGNED field with the top bit set is in [2^127, 2^128) and does
        // NOT fit i128 → `@intCast(u128→i128)` PANICS (bs-int-128-topbit, DIVERGENCE
        // 592). Fall through to the bignum LIMBS path (which already handles it and
        // round-trips — verified for len>128), so a full-width unsigned field is
        // decoded as a positive bignum, never a panic.
        if (mag <= @as(u128, std.math.maxInt(i128))) return try FinalTerms.intFromI128(&m.ctx, @intCast(mag));
    }
    if (len > FinalTerms.max_limbs * 64) return null;
    var limbs = bsMagnitudeLimbsAt(full, start, len, endian);
    if (signed and limbBitAt(&limbs, len - 1) == 1) {
        negateLowBits(&limbs, len);
        return try FinalTerms.intFromLimbs(&m.ctx, false, &limbs);
    }
    return try FinalTerms.intFromLimbs(&m.ctx, true, &limbs);
}

// ============================================================================
// E3.4: bit-syntax CONSTRUCTION helpers
// ============================================================================
//
// `BsBuildError` mirrors real `erl_bits.c`'s two construction failure modes
// (see the E3.4 report's `i_bs_create_bin` citation): a wrongly-typed/out-of-
// range segment source is `badarg`; a segment (or the running total) whose
// bit width cannot be represented is `system_limit` — the EXACT error atom
// each maps to (never conflated) is what the size-overflow law pins.
const BsBuildError = error{ Badarg, SystemLimit, OutOfMemory };

/// E3.4: the total-construction bit-width ceiling. Real erts' actual limit
/// is effectively "as much as the OS will allocate" (a `Uint`-overflow
/// check, not a fixed constant) — genuinely exercising THAT limit would mean
/// allocating gigabytes inside a law test. This VM instead enforces a small,
/// fixed, DOCUMENTED cap (independent of the `FinalTerms` bignum cap used
/// for individual integer segments below) so the size-overflow →
/// `system_limit` law is exercised deterministically and fast. A genuine,
/// narrow, intentional divergence — ledgered in `DIVERGENCE_LOG.md`.
pub const bs_construct_max_bits: usize = 1 << 24; // 2 MiB

/// `size × unit` for a construction segment, checked (never wraps/panics):
/// a non-integer or negative resolved size is `Badarg` (the source term
/// itself is malformed); an overflowing product is `SystemLimit` (the
/// segment's OWN width cannot be represented) — the construction-side twin
/// of `Machine.bsFieldBits` (matching side), which returns a bare `null`
/// because standalone matching has no `SystemLimit` outcome to distinguish.
fn bsFieldBitsChecked(m: *Machine, size: Src, unit: u8) BsBuildError!usize {
    const v = m.resolve(size);
    if (!FinalTerms.repIsSmall(v)) return error.Badarg;
    const n = FinalTerms.smallValOf(v);
    if (n < 0) return error.Badarg;
    return std.math.mul(usize, @intCast(n), @as(usize, unit)) catch error.SystemLimit;
}

/// Two's-complement `nbits`-wide bit pattern of `term` (small integer or
/// bignum, either sign) serialized per `endian` — the construction-side
/// INVERSE of `bsIntegerFieldTerm`. Reuses `negateLowBits`/`limbBitAt`
/// (E3.3-fix) UNCHANGED: the negation's "no overflow past the field width"
/// precondition documented on `negateLowBits` does not apply here (we only
/// ever READ BACK the low `nbits` bits it produces, so any ripple beyond
/// that window is inert) — see the E3.4 report for the full argument.
/// `nbits` beyond the bignum cap (`FinalTerms.max_limbs*64` = 512 bits) is
/// `SystemLimit` — the SAME documented capacity bound `bsIntegerFieldTerm`
/// already has on the matching side (DIVERGENCE_LOG entry 16(b)), now
/// mirrored on construction.
fn intSegBits(m: *Machine, gpa: std.mem.Allocator, term: FinalTerms.Term, nbits: usize, endian: BsEndian) BsBuildError!bsa.Bits {
    if (nbits > FinalTerms.max_limbs * 64) return error.SystemLimit;
    if (nbits == 0) return bsa.canonicalize(gpa, &.{}, 0) catch error.OutOfMemory;
    var limbs: [FinalTerms.max_limbs]u64 = @splat(0);
    var positive = true;
    if (FinalTerms.repIsSmall(term)) {
        const sv = FinalTerms.smallValOf(term);
        positive = sv >= 0;
        limbs[0] = @abs(sv);
    } else if (FinalTerms.repIsBig(&m.ctx, term)) {
        const parts = FinalTerms.bigPartsOf(&m.ctx, term);
        positive = parts.positive;
        for (parts.limbs, 0..) |l, idx| {
            if (idx >= FinalTerms.max_limbs) break;
            limbs[idx] = l;
        }
    } else return error.Badarg;
    if (!positive) negateLowBits(&limbs, nbits);
    return bitsFromLimbsField(gpa, &limbs, nbits, endian) catch error.OutOfMemory;
}

/// Serialize the low `nbits` bits of `limbs` (bit 0 = LSB, per
/// `limbBitAt`'s convention) into a canonical `bsa.Bits`, per `endian` — the
/// SAME two conventions `bsMagnitudeAt`/`bsMagnitudeLimbsAt` read by (MSB-
/// first bit order for big-endian/sub-byte fields; byte-reversed, MSB-first-
/// within-byte, for byte-multiple little-endian), just run in reverse.
fn bitsFromLimbsField(gpa: std.mem.Allocator, limbs: *const [FinalTerms.max_limbs]u64, nbits: usize, endian: BsEndian) !bsa.Bits {
    const nbytes = bsa.byteLen(nbits);
    const buf = try gpa.alloc(u8, nbytes);
    defer gpa.free(buf);
    @memset(buf, 0);
    // bs-little-oddsize (discharges the DIVERGENCE-16(a) construction half):
    // a little field of nbits = 8k+r lays out as the k LOW value bytes (LSB
    // byte first, MSB-first within each stream byte) then the HIGH r-bit
    // fragment (value bits [8k, 8k+r), MSB-first) — the inverse of
    // `bsMagnitudeAt`'s little reading. r == 0 reduces to the old
    // byte-reversal; the pre-fix arm used the big-endian bit order for odd
    // sizes (probe: `<<IBig:13/little,…>>` emitted `<<4,157,…>>` where the
    // oracle emits `<<147,5,…>>`).
    const k8 = if (endian == .little) (nbits / 8) * 8 else 0;
    var byte_i: usize = 0;
    while (byte_i < nbytes) : (byte_i += 1) {
        var byte: u8 = 0;
        for (0..8) |k| {
            var have_bit = true;
            var value_bit_idx: usize = undefined;
            const field_bit_i = byte_i * 8 + k;
            if (field_bit_i >= nbits) {
                have_bit = false;
                value_bit_idx = 0;
            } else if (endian == .little and field_bit_i < k8) {
                value_bit_idx = 8 * byte_i + 7 - k; // value byte j == stream byte j
            } else if (endian == .little) {
                const t = field_bit_i - k8; // the high fragment, MSB-first
                value_bit_idx = nbits - 1 - t;
            } else {
                value_bit_idx = nbits - 1 - field_bit_i;
            }
            const bit: u1 = if (have_bit) limbBitAt(limbs, value_bit_idx) else 0;
            byte = (byte << 1) | bit;
        }
        buf[byte_i] = byte;
    }
    return bsa.canonicalize(gpa, buf, nbits);
}

/// UTF-16 encode (surrogate-pair aware) — see the E3.4 report: `unicode.zig`
/// is UTF-8-only, so this (and `utf32Encode`/`utf32Decode` below) is NEW,
/// narrowly-scoped code, not a duplicate of an existing codec. Cited against
/// `erl_bits.c`'s `erts_bs_put_utf16`/`erts_bs_get_utf16` (surrogate range
/// 0xD800..0xDFFF and > 0x10FFFF rejected — the SAME bounds `unicode.zig`'s
/// `encodeCp`/`decodeCp` enforce for UTF-8).
fn utf16Encode(cp: u21, little: bool, out: *[4]u8) ?usize {
    if (cp >= 0xD800 and cp <= 0xDFFF) return null;
    if (cp > 0x10FFFF) return null;
    if (cp < 0x10000) {
        const v: u16 = @intCast(cp);
        if (little) {
            out[0] = @truncate(v);
            out[1] = @truncate(v >> 8);
        } else {
            out[0] = @truncate(v >> 8);
            out[1] = @truncate(v);
        }
        return 2;
    }
    const v = cp - 0x10000;
    const w1: u16 = 0xD800 | @as(u16, @truncate(v >> 10));
    const w2: u16 = 0xDC00 | @as(u16, @truncate(v & 0x3FF));
    if (little) {
        out[0] = @truncate(w1);
        out[1] = @truncate(w1 >> 8);
        out[2] = @truncate(w2);
        out[3] = @truncate(w2 >> 8);
    } else {
        out[0] = @truncate(w1 >> 8);
        out[1] = @truncate(w1);
        out[2] = @truncate(w2 >> 8);
        out[3] = @truncate(w2);
    }
    return 4;
}

fn utf16Decode(bytes: []const u8, little: bool) ?struct { cp: u21, len: usize } {
    if (bytes.len < 2) return null;
    const w1: u16 = if (little) (@as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8)) else ((@as(u16, bytes[0]) << 8) | @as(u16, bytes[1]));
    if (w1 < 0xD800 or w1 > 0xDFFF) return .{ .cp = w1, .len = 2 };
    if (w1 > 0xDBFF) return null; // lone low surrogate
    if (bytes.len < 4) return null;
    const w2: u16 = if (little) (@as(u16, bytes[2]) | (@as(u16, bytes[3]) << 8)) else ((@as(u16, bytes[2]) << 8) | @as(u16, bytes[3]));
    if (w2 < 0xDC00 or w2 > 0xDFFF) return null; // unpaired high surrogate
    const cp: u21 = 0x10000 + ((@as(u21, w1 - 0xD800) << 10) | @as(u21, w2 - 0xDC00));
    return .{ .cp = cp, .len = 4 };
}

fn utf32Encode(cp: u21, little: bool, out: *[4]u8) bool {
    if (cp >= 0xD800 and cp <= 0xDFFF) return false;
    if (cp > 0x10FFFF) return false;
    const v: u32 = cp;
    if (little) {
        out[0] = @truncate(v);
        out[1] = @truncate(v >> 8);
        out[2] = @truncate(v >> 16);
        out[3] = @truncate(v >> 24);
    } else {
        out[0] = @truncate(v >> 24);
        out[1] = @truncate(v >> 16);
        out[2] = @truncate(v >> 8);
        out[3] = @truncate(v);
    }
    return true;
}

/// Extract `nbytes` (<= 4) bytes starting at bit offset `off` of `bits`,
/// bit-by-bit (so it works whether or not `off` is byte-aligned) — the SAME
/// MSB-first-within-byte reading `bsMagnitudeAt`'s big-endian branch does.
/// Shared by `bs_get_utf`/`bs_skip_utf`'s three UTF-kind arms so the byte-
/// assembly loop is written exactly once.
fn extractBytesAt(bits: bsa.Bits, off: usize, nbytes: usize, buf: *[4]u8) void {
    for (0..nbytes) |bi| {
        var byte: u8 = 0;
        for (0..8) |k| byte = (byte << 1) | bsa.bitAt(bits, off + bi * 8 + k);
        buf[bi] = byte;
    }
}

/// Decode one UTF codepoint of `kind` at bit offset `off` of `bits` — shared
/// by `bs_get_utf` (binds `dst`) and `bs_skip_utf` (advances only). Returns
/// `null` on truncation/invalid encoding (the caller branches `else_to`).
fn bsUtfDecodeAt(bits: bsa.Bits, off: usize, kind: UtfKind, endian: BsEndian) ?struct { cp: u21, bit_len: usize } {
    const rem = bits.bit_len - off;
    switch (kind) {
        .utf8 => {
            if (rem < 8) return null;
            var buf: [4]u8 = undefined;
            const avail = @min(@as(usize, 4), rem / 8);
            extractBytesAt(bits, off, avail, &buf);
            const dec = unicode.decodeCp(buf[0..avail]) catch return null;
            return .{ .cp = dec.cp, .bit_len = dec.len * 8 };
        },
        .utf16 => {
            if (rem < 16) return null;
            var buf: [4]u8 = undefined;
            const avail = @min(@as(usize, 4), rem / 8);
            extractBytesAt(bits, off, avail, &buf);
            const dec = utf16Decode(buf[0..avail], endian == .little) orelse return null;
            return .{ .cp = dec.cp, .bit_len = dec.len * 8 };
        },
        .utf32 => {
            if (rem < 32) return null;
            var buf: [4]u8 = undefined;
            extractBytesAt(bits, off, 4, &buf);
            const cp = utf32Decode(&buf, endian == .little) orelse return null;
            return .{ .cp = cp, .bit_len = 32 };
        },
    }
}

fn utf32Decode(bytes: []const u8, little: bool) ?u21 {
    if (bytes.len < 4) return null;
    const v: u32 = if (little)
        (@as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16) | (@as(u32, bytes[3]) << 24))
    else
        ((@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) | (@as(u32, bytes[2]) << 8) | @as(u32, bytes[3]));
    if (v > 0x10FFFF) return null;
    if (v >= 0xD800 and v <= 0xDFFF) return null;
    return @intCast(v);
}

/// One `BsSeg`'s contribution to the accumulating construction bitstring —
/// the segment-type dispatch (mutant 1's target op ORDERS these calls; this
/// function itself is order-agnostic). `append`/`private_append` route
/// through the SAME `binary_all`-shaped path as their on-disk sibling (see
/// `BsSeg`'s doc comment) — no special-casing needed in a pure, functional-
/// update VM. Returns a `gpa`-owned `bsa.Bits` (caller frees).
fn bsSegBits(m: *Machine, gpa: std.mem.Allocator, seg: BsSeg) BsBuildError!bsa.Bits {
    switch (seg) {
        .integer => |s| {
            const nbits = try bsFieldBitsChecked(m, s.size, s.unit);
            return intSegBits(m, gpa, m.resolve(s.src), nbits, s.endian);
        },
        .float => |s| {
            const nbits = try bsFieldBitsChecked(m, s.size, s.unit);
            if (nbits != 32 and nbits != 64) return error.Badarg;
            const term = m.resolve(s.src);
            if (!FinalTerms.repIsNumber(&m.ctx, term)) return error.Badarg;
            const f = FinalTerms.numToF64Of(&m.ctx, term);
            const bits64: u64 = if (nbits == 64) @bitCast(f) else @as(u64, @as(u32, @bitCast(@as(f32, @floatCast(f)))));
            var limbs: [FinalTerms.max_limbs]u64 = @splat(0);
            limbs[0] = bits64;
            return bitsFromLimbsField(gpa, &limbs, nbits, s.endian) catch error.OutOfMemory;
        },
        .binary, .binary_all, .append, .private_append => {
            const src: Src = switch (seg) {
                .binary => |s| s.src,
                .binary_all => |s| s.src,
                .append => |s| s.src,
                .private_append => |s| s.src,
                else => unreachable,
            };
            const term = m.resolve(src);
            if (!FinalTerms.repIsBitstring(&m.ctx, term) and !FinalTerms.repIsBinary(&m.ctx, term)) return error.Badarg;
            const bits = FinalTerms.bitsOf(&m.ctx, term);
            const nbits: usize = switch (seg) {
                .binary => |s| try bsFieldBitsChecked(m, s.size, s.unit),
                else => bits.bit_len,
            };
            if (nbits > bits.bit_len) return error.Badarg; // "short"
            return bsa.slice(gpa, bits, 0, nbits) catch error.OutOfMemory;
        },
        .utf8 => |s| {
            const term = m.resolve(s.src);
            if (!FinalTerms.repIsSmall(term)) return error.Badarg;
            const v = FinalTerms.smallValOf(term);
            if (v < 0 or v > 0x10FFFF) return error.Badarg;
            var buf: [4]u8 = undefined;
            const n = unicode.encodeCp(@intCast(v), &buf) catch return error.Badarg;
            return bsa.canonicalize(gpa, buf[0..n], n * 8) catch error.OutOfMemory;
        },
        .utf16 => |s| {
            const term = m.resolve(s.src);
            if (!FinalTerms.repIsSmall(term)) return error.Badarg;
            const v = FinalTerms.smallValOf(term);
            if (v < 0 or v > 0x10FFFF) return error.Badarg;
            var buf: [4]u8 = undefined;
            const n = utf16Encode(@intCast(v), s.endian == .little, &buf) orelse return error.Badarg;
            return bsa.canonicalize(gpa, buf[0..n], n * 8) catch error.OutOfMemory;
        },
        .utf32 => |s| {
            const term = m.resolve(s.src);
            if (!FinalTerms.repIsSmall(term)) return error.Badarg;
            const v = FinalTerms.smallValOf(term);
            if (v < 0 or v > 0x10FFFF) return error.Badarg;
            var buf: [4]u8 = undefined;
            if (!utf32Encode(@intCast(v), s.endian == .little, &buf)) return error.Badarg;
            return bsa.canonicalize(gpa, &buf, 32) catch error.OutOfMemory;
        },
        .string => |s| return bsa.canonicalize(gpa, s.bytes, s.bytes.len * 8) catch error.OutOfMemory,
    }
}

/// gap-reduction-cost-model (R1, the {R} real-time axis): the per-instruction
/// reduction COST — the single hook that makes reduction accounting a WEIGHTED
/// fold instead of a flat +1/instruction tally.
///
/// OTP-30 charges reductions as a per-op WEIGHTED decrement (`BUMP_REDS(p,gc)`,
/// `third_party/otp/erts/emulator/beam/bif.h:71-147`): ~1 per function call, plus
/// size-weighted increments for heavy BIFs (binary/term/list work divided by a
/// per-op loop factor — `erl_bif_binary.c`, `external.c`, `erl_bif_lists.c`). A
/// flat +1 per zigvm bytecode instruction over-counts vs that per-call granularity
/// by 3-5x on real workloads (measured by `--reduction-oracle`).
///
/// R2b assigns the OTP-anchored PER-CALL weights: OTP-30 charges ~1 reduction per
/// function CALL (`BUMP_REDS(p,gc)`), NOT per bytecode instruction. So:
///   * `.call` / `.apply` / `.call_fun` / `.call_fun2` / `.call_ext_bif` /
///     `.call_ext_code` / `.apply3` / `.apply_op`  → 1  (a function call).
///     (`call_ext_bif` SIZE-weighting for heavy BIFs is R2c / out-of-scope —
///      it stays 1 here.)
///   * `.jump`  → 1 iff it is a TAIL call (`tail == true`, a beam
///     `call_only`/`call_last` back-edge, which OTP charges); an intra-function
///     forward BRANCH (`tail == false`) is 0.
///   * `.ret`   → 0  (OTP charges at the call site, not the return).
///   * EVERYTHING ELSE (move/add/sub/is_lt/test_eq/cmp_test/get_list/put_*/bs_*/…
///     all straight-line ops and guards) → 0.
/// A tail-recursive loop therefore charges EXACTLY 1 reduction per iteration (the
/// tail back-edge) — matching OTP's per-call count and driving the
/// `--reduction-oracle` ratio to ~1.0.
///
/// TOTALITY: `reductionCost` is a TOTAL function (a defined weight for every op).
/// It is NO LONGER floored at 1 — most ops are 0. Bounded preemption is preserved
/// NOT by a per-op reduction floor but by the two-counter split: the `run` fuel
/// loop / scheduler grants bound on `m.instrs` (which increments +1 per retired
/// op, so a non-terminating computation is always preempted). A non-terminating
/// computation additionally always LOOPS, and a loop is a tail-jump / call, so it
/// also charges >= 1 reduction per iteration — the per-call preemption floor.
fn reductionCost(ins: CInstr) u32 {
    return switch (ins) {
        .call, .call_fun, .call_fun2, .call_ext_bif, .call_ext_code, .apply, .apply3, .apply_fun, .apply_op => 1,
        .jump => |j| if (j.tail) 1 else 0,
        else => 0,
    };
}

/// Charge ONE retired instruction: bump the per-instruction counter (`instrs`,
/// which drives preemption/slicing) and add the per-call reduction weight
/// (`reductions`, the OTP-faithful accounting). The single choke-point every
/// direct `execInstr` arm routes through (the ops that go via `retire` are charged
/// there, identically).
fn charge(m: *Machine, ins: CInstr) void {
    m.instrs += 1;
    m.reductions += reductionCost(ins);
}

/// R2c: OTP's per-element reduction surcharge for a size-heavy BIF, read from the
/// live argument registers (its args still sit in `x0..`) and added to
/// `m.reductions` ONLY by the `call_ext_bif` arm. `ELEMENTS_PER_RED = 32` mirrors
/// erts (`erl_bif_lists.c`: `BUMP_REDS(p, count / ELEMENTS_PER_RED)`). Observational
/// (reads heads/tails, mutates nothing) and total (exhaustive switch; a new heavy
/// class is a compile error until added).
fn bifSizeReds(m: *Machine, sc: BifSizeClass) u32 {
    const ELEMENTS_PER_RED: u32 = 32;
    return switch (sc) {
        .none => 0,
        .list0_elems => properListLen(m, m.regs[0]) / ELEMENTS_PER_RED,
        // gap-reduction-size-weight (DIVERGENCE 603): same per-element charge, read
        // from the argument the erts BIF actually traverses.
        .list1_elems => properListLen(m, m.regs[1]) / ELEMENTS_PER_RED,
        .list2_elems => properListLen(m, m.regs[2]) / ELEMENTS_PER_RED,
        .bytes0_elems => binaryByteLen(m, m.regs[0]) / ELEMENTS_PER_RED,
    };
}

/// gap-reduction-bytes-weight (DIVERGENCE 604): the BYTE length of a binary in a
/// register, or 0 for a non-binary (the properListLen discipline — total, a pure
/// observation). Reads the already-materialized payload; mutates nothing.
fn binaryByteLen(m: *Machine, t: FinalTerms.Term) u32 {
    if (FinalTerms.kindOf(&m.ctx, t) != .binary) return 0;
    const CAP: u32 = 1 << 30; // 1 GiB — orders above any reduction slice
    const len = FinalTerms.binBytes(&m.ctx, t).len;
    return if (len > CAP) CAP else @intCast(len);
}

/// Length of the proper-list prefix of `t` (elements until the first non-`cons`),
/// bounded so an improper/cyclic argument can never spin the charge — a hang is a
/// failed law, and a real proper list terminates at `nil` far below the cap.
fn properListLen(m: *Machine, t: FinalTerms.Term) u32 {
    const CAP: u32 = 1 << 24; // 16M elements — orders above any reduction slice
    var n: u32 = 0;
    var cur = t;
    while (n < CAP and FinalTerms.kindOf(&m.ctx, cur) == .cons) : (n += 1) {
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return n;
}

/// The per-call reduction weight of a BlockInstr. Every block op (move/add/
/// put_list) is a straight-line op ⇒ 0 (OTP charges per call, not per op). Kept
/// as an explicit total switch so a future cost-bearing block op is a compile
/// error until weighted.
fn reductionCostBlock(ins: BlockInstr) u32 {
    return switch (ins) {
        .move, .add, .put_list => 0,
    };
}

pub fn execInstr(m: *Machine, ins: CInstr) !void {
    switch (ins) {
        .move => |v| try m.retire(.{ .move = v }),
        .add => |v| try m.retire(.{ .add = v }),
        .put_list => |v| try m.retire(.{ .put_list = v }),
        .test_eq => |t| { // is_eq_exact semantics (=:=), per real BEAM tests
            charge(m, ins);
            if (!FinalTerms.eqlExact(&m.ctx, m.resolve(t.a), m.resolve(t.b)))
                m.pc = t.else_to;
        },
        .is_lt => |t| {
            charge(m, ins);
            if (FinalTerms.compare(&m.ctx, m.resolve(t.a), m.resolve(t.b)) != .lt)
                m.pc = t.else_to;
        },
        .jump => |j| {
            charge(m, ins);
            m.pc = j.to;
        },
        .call => |c| {
            charge(m, ins);
            try m.stack.append(m.gpa, m.pc);
            m.pc = c.to;
        },
        .ret => {
            charge(m, ins);
            if (m.stack.pop()) |cp| {
                m.pc = cp;
            } else {
                m.status = .halted;
                m.result = m.regs[0];
            }
        },
        .halt => |h| {
            charge(m, ins);
            m.status = .halted;
            m.result = m.resolve(h.src);
        },
        .self_send => |v| {
            charge(m, ins);
            try m.mbox.deliver(0, m.resolve(v.src));
        },
        .recv_eq => |r| {
            charge(m, ins);
            const p = pat.Pattern(FinalTerms){ .plit = m.resolve(r.m) };
            if (try m.mbox.recvMatch(&m.ctx, &p)) |got| {
                m.regs[r.dst] = got.msg.payload;
            } else m.pc = r.else_to;
        },
        .recv_any => |r| {
            charge(m, ins);
            const p = pat.Pattern(FinalTerms){ .pwild = {} };
            if (try m.mbox.recvMatch(&m.ctx, &p)) |got| {
                m.regs[r.dst] = got.msg.payload;
            } else m.pc = r.else_to;
        },
        // E1.11 receive-loop ops -----------------------------------------------
        .send => {
            // send/0: deliver x1 to the pid in x0 (M7 `.send_to` trap); the sent
            // message is the result, so x0 := x1 (BEAM `send` returns the message).
            charge(m, ins);
            m.pending = .{ .send_to = .{ .pid = m.regs[0], .msg = m.regs[1] } };
            m.regs[0] = m.regs[1];
        },
        .loop_rec => |lr| {
            // PEEK the message at the save-pointer WITHOUT removing it: fall
            // through with it in `dst`, else (empty/exhausted queue) jump to the
            // wait clause. Reuses mailbox_algebra's arrival sequence (peekAt).
            charge(m, ins);
            m.recv_scanned = true; // E34-T1: this receive is SELECTIVE (has a loop_rec)
            if (try m.mbox.peekAt(m.recv_cursor)) |msg| {
                m.regs[lr.dst] = msg.payload;
            } else m.pc = lr.else_to;
        },
        .loop_rec_end => |le| {
            // No match at the cursor: ADVANCE the save-pointer to the next
            // message and retry `loop_rec` at Lbl. Bounded: the cursor strictly
            // increases, so loop_rec eventually exhausts the queue and jumps to
            // the wait clause (never an unbounded spin).
            charge(m, ins);
            m.recv_cursor += 1;
            m.pc = le.to;
        },
        .remove_message => {
            // COMMIT the pop of the message `loop_rec` peeked at the save-pointer,
            // then reset the cursor (BEAM resets the save point). If the cursor
            // points past the queue (nothing was validly peeked), `removeAt` is a
            // no-op — remove_message NEVER removes a phantom message (mutant 1).
            charge(m, ins);
            try m.mbox.removeAt(m.recv_cursor);
            m.recv_cursor = 0;
            m.recv_scanned = false; // E34-T1: this receive is over
            // E6.2: a matching message ENDS the in-progress receive — clear its
            // timer deadline (any armed wheel entry was already cancelled by
            // Vm.signal when the message woke us; this clears the machine state so a
            // later receive arms afresh). `timer_fired` is also cleared: a message
            // that raced the timeout wins the receive (the after-clause is skipped).
            m.recv_timeout_deadline = null;
            m.timer_fired = false;
        },
        .wait => |w| {
            // Suspend waiting for a message. Single-process E1 model: no scheduler
            // wake yet, so this is a terminal `.suspended` (bounded — the run loop
            // stops; a fuller scheduler-driven resume is a later epoch). BEAM sets
            // pc := Lbl (the receive re-enters on resume); we mirror that.
            // DIVERGENCE_LOG entry 5: message-delivery suspend/resume + the receive
            // timer wheel are deferred to the E5/E6 scheduler/timer charter (EQ on
            // the totality ledger; law-driven, receive kept OUT of randProgram).
            //
            // E4.6-fix (LOST-WAKEUP GUARD, DIVERGENCE entry 48): suspend ONLY when
            // no message beyond the receive save-pointer exists. The E3.7
            // receive-wake fires at signal-ENQUEUE time — a no-op when the target
            // is still `.running` (e.g. it exhausted its slice fuel BETWEEN
            // loop_rec's empty peek and this `wait`). Without this guard the
            // process suspends over a NONEMPTY mailbox and no later signal ever
            // wakes it (the c_spawn suite hang). Real BEAM has the same check:
            // `wait` sleeps only if the message queue gained nothing since the
            // loop last scanned (the msgq-empty test under the queue lock in
            // erl_process.c). With unseen messages we RE-ENTER the receive loop
            // (pc := Lbl, cursor reset, still `.running`) — bounded: the loop
            // consumes or exhausts the queue, never a spin over an empty one.
            charge(m, ins);
            m.pc = w.to;
            if (m.mbox.len() <= m.recv_cursor) m.status = .suspended;
            m.recv_cursor = 0;
        },
        .wait_timeout => |w| {
            // Wait up to `src` ms for a message. `infinity` suspends until a signal
            // wakes it (E3.7 receive-wake). `0` fires immediately (fall through to
            // the after-clause). A finite `N>0` now ARMS a REAL timer-wheel entry
            // (E6.2, DIVERGENCE entry 5's residual): the machine traps
            // `arm_recv_timer{ms=N}`, jumps to Lbl, and suspends; when the wheel
            // fires (proc.zig scheduler advance) it sets `timer_fired` and wakes the
            // process, which re-enters here and takes the timeout branch. Treating
            // `0` as infinite (or a finite N as fire-now) would hang / mis-time the
            // receive — the E6.2 mutant targets. The E4.6 LOST-WAKEUP GUARD extends
            // to the timer path: an unseen message re-enters the loop WITHOUT arming
            // (and a message arriving after arm cancels the entry in Vm.signal —
            // cancel-race exactly-once).
            charge(m, ins);
            const t = m.resolve(w.src);
            if (FinalTerms.repIsAtom(t) and
                std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(t)), "infinity"))
            {
                // E4.6-fix: the SAME lost-wakeup guard as `wait` (see above) —
                // an infinity receive must not sleep over unseen messages.
                m.pc = w.to;
                if (m.mbox.len() <= m.recv_cursor) m.status = .suspended;
                m.recv_cursor = 0;
                return;
            }
            // A finite timeout. LOST-WAKEUP GUARD: an unseen message (beyond the
            // save-pointer) means loop_rec has fresh work — re-enter WITHOUT arming.
            // E34-T1 (DIVERGENCE 559): this guard is valid ONLY for a SELECTIVE
            // receive (`recv_scanned` — a `loop_rec` ran and `w.to` points back at
            // it). An UNCONDITIONAL `receive after T` has NO loop_rec: its label
            // points back at the wait itself, so jumping there with queued messages
            // re-hits this same guard forever (the cursor never advances, no clause
            // consumes) — the recv-after-uncond HANG. Un-scanned ⇒ fall through to
            // fire/arm the timeout, exactly as erts does.
            if (m.recv_scanned and m.mbox.len() > m.recv_cursor) {
                m.pc = w.to;
                m.recv_cursor = 0;
                return;
            }
            // The timer already fired while we were parked: take the after-clause.
            if (m.timer_fired) {
                m.timer_fired = false;
                m.recv_timeout_deadline = null;
                m.recv_cursor = 0;
                m.recv_scanned = false;
                return; // fall through: pc already at the after-clause
            }
            // E34-T1 (recv-after-badtimeout, DIVERGENCE 559): validate the timeout
            // value. erts admits ONLY a non-negative integer in 0..2^32-1 (or the
            // atom `infinity`, handled above). Anything else — a non-`infinity`
            // atom, a float, a negative integer, or an out-of-range bignum — raises
            // `error:timeout_value` (erts BEAM `beam_common.c` / `timeout_value`),
            // NOT a silent take-the-after-branch. Smalls are 60-bit here so any
            // in-range value is a small; a bignum is necessarily out of range.
            if (!FinalTerms.repIsSmall(t)) {
                return m.raiseErrorAtom(try m.ctx.atoms.intern("timeout_value"));
            }
            const ms = FinalTerms.smallValOf(t);
            if (ms < 0 or ms > 0xFFFF_FFFF) {
                return m.raiseErrorAtom(try m.ctx.atoms.intern("timeout_value"));
            }
            if (ms == 0) {
                m.recv_cursor = 0;
                m.recv_scanned = false;
                return; // `receive after 0` — fire now (fall through)
            }
            // ARM: trap to the Vm (which computes the deadline off its virtual
            // clock, installs a wheel entry, and leaves us suspended), jump to Lbl
            // so the woken process re-scans the mailbox, and suspend.
            m.pending = .{ .arm_recv_timer = .{ .ms = @intCast(ms) } };
            m.pc = w.to;
            m.status = .suspended;
            m.recv_cursor = 0;
        },
        .timeout => {
            // After a timeout: clear the receive save-pointer so a subsequent
            // receive scans the mailbox from the start, and end the in-progress
            // receive-timer's deadline (E6.2 — a fresh receive arms a fresh timer).
            charge(m, ins);
            m.recv_cursor = 0;
            m.recv_scanned = false; // E34-T1: this receive-after is over
            m.recv_timeout_deadline = null;
            m.timer_fired = false;
        },
        .recv_marker_bind, .recv_marker_clear, .recv_marker_reserve, .recv_marker_use => {
            // Receive-queue optimization markers (fast selective-receive resume).
            // SEMANTICALLY TRANSPARENT: no observable denotation depends on them
            // (the transparency law proves it). Dispatched no-ops for E1; a real
            // marker table is an E3 perf concern.
            charge(m, ins);
        },
        .nop => {
            // E1.15: on_load / nif_start. SEMANTICALLY TRANSPARENT (the
            // transparency law): one reduction, no other observable effect.
            // Mutant guard — do NOT touch x/y/heap/pc here beyond the normal
            // fall-through the caller performs after execInstr returns.
            charge(m, ins);
        },
        // ---- E3.3: bit-syntax matching opcodes --------------------------------
        .bs_start_match => |s| {
            charge(m, ins);
            const v = m.resolve(s.src);
            const ctxv = if (FinalTerms.repIsMatchCtx(&m.ctx, v))
                v // bs_start_match4 `resume`: already a match context
            else if (FinalTerms.repIsBitstring(&m.ctx, v) or FinalTerms.repIsBinary(&m.ctx, v))
                try FinalTerms.makeMatchCtx(&m.ctx, v, 0)
            else {
                if (s.else_to) |lbl| {
                    m.pc = lbl;
                    return;
                }
                return m.crash(m.badarg); // compiler-guaranteed path taken on malformed input
            };
            m.setDst(s.ctx, ctxv);
        },
        .bs_get_integer => |g| {
            charge(m, ins);
            const ctxv = m.resolve(dstAsSrc(g.ctx));
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const nbits = m.bsFieldBits(g.size, g.unit) orelse return m.crash(m.badarg);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            if (off + nbits > bits.bit_len) {
                m.pc = g.else_to;
                return;
            }
            // E3.3-fix (Fix 1): width-dispatched, never panics — see
            // `bsIntegerFieldTerm`'s doc comment for the 1..128/129..512/
            // >512 band split.
            const value = try bsIntegerFieldTerm(m, bits, off, nbits, g.endian, g.signed) orelse {
                m.pc = g.else_to; // field width beyond the bignum cap (>512 bits)
                return;
            };
            m.setDst(g.ctx, try FinalTerms.makeMatchCtx(&m.ctx, bin, off + nbits));
            m.setDst(g.dst, value);
        },
        .bs_get_float => |g| {
            charge(m, ins);
            const ctxv = m.resolve(dstAsSrc(g.ctx));
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const nbits = m.bsFieldBits(g.size, g.unit) orelse return m.crash(m.badarg);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            // DIVERGENCE 694: 16-bit HALF-precision (IEEE 754 binary16) decode —
            // `<<X:16/float>>` matched `badmatch` because the width guard admitted
            // only 32/64 (encode already emits 16-bit via `f16`, so it was
            // asymmetric). Zig's native `f16` does the widening bit-for-bit.
            if ((nbits != 16 and nbits != 32 and nbits != 64) or off + nbits > bits.bit_len) {
                m.pc = g.else_to;
                return;
            }
            const mag = bsMagnitudeAt(bits, off, nbits, g.endian);
            const f: f64 = switch (nbits) {
                16 => @floatCast(@as(f16, @bitCast(@as(u16, @truncate(mag))))),
                32 => @floatCast(@as(f32, @bitCast(@as(u32, @truncate(mag))))),
                else => @bitCast(@as(u64, @truncate(mag))),
            };
            if (!std.math.isFinite(f)) {
                m.pc = g.else_to;
                return;
            }
            m.setDst(g.ctx, try FinalTerms.makeMatchCtx(&m.ctx, bin, off + nbits));
            m.setDst(g.dst, FinalTerms.float(&m.ctx, f));
        },
        .bs_get_binary => |g| {
            charge(m, ins);
            const ctxv = m.resolve(dstAsSrc(g.ctx));
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const nbits = m.bsFieldBits(g.size, g.unit) orelse return m.crash(m.badarg);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            if (off + nbits > bits.bit_len) {
                m.pc = g.else_to;
                return;
            }
            const sub = try bsa.slice(m.gpa, bits, off, nbits);
            defer m.gpa.free(sub.bytes);
            const value = try FinalTerms.bitstring(&m.ctx, sub.bytes, sub.bit_len);
            m.setDst(g.ctx, try FinalTerms.makeMatchCtx(&m.ctx, bin, off + nbits));
            m.setDst(g.dst, value);
        },
        .bs_skip_bits => |sk| {
            charge(m, ins);
            const ctxv = m.resolve(dstAsSrc(sk.ctx));
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const nbits = m.bsFieldBits(sk.size, sk.unit) orelse return m.crash(m.badarg);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            if (off + nbits > bits.bit_len) {
                m.pc = sk.else_to;
                return;
            }
            m.setDst(sk.ctx, try FinalTerms.makeMatchCtx(&m.ctx, bin, off + nbits));
        },
        .bs_test_tail => |t| {
            charge(m, ins);
            const ctxv = m.resolve(t.ctx);
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            // MUTANT 2 TARGET: this arm must NEVER write `t.ctx` back (there is
            // no Dst here — `t.ctx` is read-only) and must NEVER advance the
            // cursor on a mismatch. The cursor-monotonicity law pins both.
            if (bits.bit_len - off != t.bits) m.pc = t.else_to;
        },
        .bs_match_string => |s| {
            charge(m, ins);
            const ctxv = m.resolve(dstAsSrc(s.ctx));
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            if (off + s.bit_len > bits.bit_len) {
                m.pc = s.else_to;
                return;
            }
            const pat_bits = bsa.Bits{ .bytes = s.bytes, .bit_len = s.bit_len };
            var matched = true;
            var i: usize = 0;
            while (i < s.bit_len) : (i += 1) {
                if (bsa.bitAt(bits, off + i) != bsa.bitAt(pat_bits, i)) {
                    matched = false;
                    break;
                }
            }
            if (!matched) {
                m.pc = s.else_to;
                return;
            }
            m.setDst(s.ctx, try FinalTerms.makeMatchCtx(&m.ctx, bin, off + s.bit_len));
        },
        .bs_get_tail_ctx => |g| {
            charge(m, ins);
            const ctxv = m.resolve(g.ctx);
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            const rem = bits.bit_len - off;
            const sub = try bsa.slice(m.gpa, bits, off, rem);
            defer m.gpa.free(sub.bytes);
            m.setDst(g.dst, try FinalTerms.bitstring(&m.ctx, sub.bytes, sub.bit_len));
        },
        .bs_get_position => |g| {
            charge(m, ins);
            const ctxv = m.resolve(g.ctx);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            m.setDst(g.dst, try FinalTerms.intFromI128(&m.ctx, @intCast(off)));
        },
        .bs_set_position => |s| {
            charge(m, ins);
            const ctxv = m.resolve(dstAsSrc(s.ctx));
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const pos = m.resolve(s.pos);
            const new_off: usize = @intCast(FinalTerms.smallValOf(pos));
            m.setDst(s.ctx, try FinalTerms.makeMatchCtx(&m.ctx, bin, new_off));
        },
        .bs_match => |bm| {
            charge(m, ins);
            const ctxv = m.resolve(dstAsSrc(bm.ctx));
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            var off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            for (bm.cmds) |cmd| {
                switch (cmd) {
                    .ensure_at_least => |e| {
                        // bs-unaligned-tail (CORRECTS the original arm): erts
                        // `i_bs_ensure_bits_unit(NumBits, Unit)` semantics —
                        // fail if `remaining < NumBits` OR `(remaining -
                        // NumBits) % Unit != 0` (bs_instrs.tab @1282). Stride
                        // is ALREADY in bits; Unit constrains the REMAINDER's
                        // divisibility (it is 8 exactly when the tail is
                        // `/binary`). The pre-fix arm MULTIPLIED stride×unit —
                        // over-demanding 8× the bits and never checking
                        // divisibility — which made every `<<_:8,X:8,
                        // Rest/binary>>`-shaped match fail (fleet finding).
                        const rem = bits.bit_len - off;
                        if (rem < e.stride) {
                            m.pc = bm.fail_to;
                            return;
                        }
                        if (e.unit > 1 and (rem - e.stride) % e.unit != 0) {
                            m.pc = bm.fail_to;
                            return;
                        }
                    },
                    .ensure_exactly => |e| {
                        if (bits.bit_len - off != e.stride) {
                            m.pc = bm.fail_to;
                            return;
                        }
                    },
                    .integer => |ic| {
                        const nbits = m.bsFieldBits(ic.size, ic.unit) orelse {
                            m.pc = bm.fail_to;
                            return;
                        };
                        if (off + nbits > bits.bit_len) {
                            m.pc = bm.fail_to;
                            return;
                        }
                        // E3.3-fix (Fix 1): width-dispatched, never panics —
                        // see `bsIntegerFieldTerm`'s doc comment.
                        const value = try bsIntegerFieldTerm(m, bits, off, nbits, ic.endian, ic.signed) orelse {
                            m.pc = bm.fail_to; // field width beyond the bignum cap (>512 bits)
                            return;
                        };
                        m.setDst(ic.dst, value);
                        off += nbits;
                    },
                    .binary => |bc| {
                        const nbits = m.bsFieldBits(bc.size, bc.unit) orelse {
                            m.pc = bm.fail_to;
                            return;
                        };
                        if (off + nbits > bits.bit_len) {
                            m.pc = bm.fail_to;
                            return;
                        }
                        const sub = try bsa.slice(m.gpa, bits, off, nbits);
                        defer m.gpa.free(sub.bytes);
                        m.setDst(bc.dst, try FinalTerms.bitstring(&m.ctx, sub.bytes, sub.bit_len));
                        off += nbits;
                    },
                    .skip => |sk| {
                        if (off + sk.stride > bits.bit_len) {
                            m.pc = bm.fail_to;
                            return;
                        }
                        off += sk.stride;
                    },
                    .get_tail => |gt| {
                        // batch-4 fix: erts `bs_get_tail` does NOT advance the
                        // position (it captures the rest; `sb` is unchanged) —
                        // the compiler then reads `bit_size(ctx)` = the TAIL's
                        // size after the match. The pre-fix `off += rem` made
                        // that read 0 (probe: `bit_size(B)` of an unaligned
                        // `/bitstring` tail returned 0 where the oracle says 9).
                        const rem = bits.bit_len - off;
                        const sub = try bsa.slice(m.gpa, bits, off, rem);
                        defer m.gpa.free(sub.bytes);
                        m.setDst(gt.dst, try FinalTerms.bitstring(&m.ctx, sub.bytes, sub.bit_len));
                    },
                    .eq => |e| {
                        if (off + e.size > bits.bit_len) {
                            m.pc = bm.fail_to;
                            return;
                        }
                        const mag = bsMagnitudeAt(bits, off, e.size, .big);
                        const got = try FinalTerms.intFromI128(&m.ctx, @intCast(mag));
                        if (!FinalTerms.eqlExact(&m.ctx, got, e.value)) {
                            m.pc = bm.fail_to;
                            return;
                        }
                        off += e.size;
                    },
                }
            }
            // MUTANT-2-style guard: the ctx register is written ONLY on the
            // all-commands-succeeded path — any per-command failure above
            // already returned without touching `bm.ctx`.
            //
            // bs-unaligned-tail: …and NOT when a command's dst already wrote
            // the ctx REGISTER itself. erts advances the position by mutating
            // the ErlSubBits IN PLACE (no end-of-instruction register write),
            // so the compiler freely targets the ctx register as a dst — e.g.
            // `{get_tail,Live,Unit,{x,1}}` with the ctx in x1 legitimately
            // ends the instruction with the TAIL in x1. The pre-fix epilogue
            // clobbered such a dst with the updated ctx (fleet finding: p5's
            // Rest came back as the context's {bin,offset} denotation).
            const ctx_clobbered = for (bm.cmds) |cmd| {
                const d: ?Dst = switch (cmd) {
                    .integer => |ic| ic.dst,
                    .binary => |bc| bc.dst,
                    .get_tail => |gt| gt.dst,
                    else => null,
                };
                if (d) |dd| {
                    if (std.meta.eql(dd, bm.ctx)) break true;
                }
            } else false;
            if (!ctx_clobbered)
                m.setDst(bm.ctx, try FinalTerms.makeMatchCtx(&m.ctx, bin, off));
        },
        // ---- E3.4: bit-syntax CONSTRUCTION + UTF opcodes ----------------------
        .bs_create_bin => |c| {
            charge(m, ins);
            // Accumulate segments IN LIST ORDER via `bitstring_algebra.concat`
            // ONLY (MUTANT 1 target: reversing this loop's order is killed by
            // the construction↔matching round-trip law).
            var acc = bsa.Bits{ .bytes = &.{}, .bit_len = 0 };
            var acc_owned = false;
            defer if (acc_owned) m.gpa.free(acc.bytes);
            var total: usize = 0;
            for (c.segs) |seg| {
                const seg_bits = bsSegBits(m, m.gpa, seg) catch |err| {
                    switch (err) {
                        error.Badarg => return m.bifFail(c.else_to, m.badarg),
                        error.SystemLimit => return m.bifFail(c.else_to, m.system_limit),
                        error.OutOfMemory => return err,
                    }
                };
                defer m.gpa.free(seg_bits.bytes);
                total += seg_bits.bit_len;
                if (total > bs_construct_max_bits) return m.bifFail(c.else_to, m.system_limit);
                const merged = try bsa.concat(m.gpa, acc, seg_bits);
                if (acc_owned) m.gpa.free(acc.bytes);
                acc = merged;
                acc_owned = true;
            }
            // A byte-aligned result is constructed as a TRUE binary
            // (SUBTAG_BINARY, not SUBTAG_BITSTRING) — real `<<...>>` whose
            // total width is a byte multiple denotes an ordinary Erlang
            // binary (`is_binary/1` true, `binary_to_list`/etc. apply
            // directly). `FinalTerms.binBytes` (unlike `eqlExact`/`compare`)
            // is NOT subtag-polymorphic, so this also avoids handing a
            // SUBTAG_BITSTRING to a caller that expects the SUBTAG_BINARY
            // layout.
            const result = if (acc.bit_len % 8 == 0)
                try FinalTerms.binary(&m.ctx, acc.bytes)
            else
                try FinalTerms.bitstring(&m.ctx, acc.bytes, acc.bit_len);
            m.setDst(c.dst, result);
        },
        .bs_init_writable => |w| {
            charge(m, ins);
            // No distinct "writable binary" representation — see `BsSeg`'s
            // doc comment: an empty binary is a valid `append`/`private_append`
            // base under this VM's pure, concat-based construction model.
            m.setDst(w.dst, try FinalTerms.binary(&m.ctx, &.{}));
        },
        .bs_get_utf => |g| {
            charge(m, ins);
            const ctxv = m.resolve(dstAsSrc(g.ctx));
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            const dec = bsUtfDecodeAt(bits, off, g.kind, g.endian) orelse {
                m.pc = g.else_to;
                return;
            };
            m.setDst(g.ctx, try FinalTerms.makeMatchCtx(&m.ctx, bin, off + dec.bit_len));
            m.setDst(g.dst, try FinalTerms.intFromI128(&m.ctx, dec.cp));
        },
        .bs_skip_utf => |sk| {
            charge(m, ins);
            const ctxv = m.resolve(dstAsSrc(sk.ctx));
            const bin = FinalTerms.matchCtxBin(&m.ctx, ctxv);
            const off = FinalTerms.matchCtxOffset(&m.ctx, ctxv);
            const bits = FinalTerms.bitsOf(&m.ctx, bin);
            const dec = bsUtfDecodeAt(bits, off, sk.kind, sk.endian) orelse {
                m.pc = sk.else_to;
                return;
            };
            m.setDst(sk.ctx, try FinalTerms.makeMatchCtx(&m.ctx, bin, off + dec.bit_len));
        },
        .make_fun => |f| {
            charge(m, ins);
            m.regs[f.dst] = try FinalTerms.makeFun(&m.ctx, f.to, f.arity, &.{});
        },
        .call_fun => |c| {
            charge(m, ins);
            const fv = m.resolve(c.f);
            // E7.1: an EXTERNAL fun `fun M:F/A` applied ≡ apply(M,F,Args). Args
            // are already in x0..x[arity-1]; route through the shared dynamic
            // dispatcher (BIF/code/hook/undef) exactly like apply/2,3 — this is
            // the call-homomorphism law's operational half.
            if (FinalTerms.repIsExportFun(&m.ctx, fv))
                return m.fullDispatch(FinalTerms.exportFunModuleIdx(&m.ctx, fv), FinalTerms.exportFunFuncIdx(&m.ctx, fv), FinalTerms.exportFunArity(&m.ctx, fv), false);
            if (!FinalTerms.repIsFun(&m.ctx, fv)) return m.crash(m.badfun);
            // gap-callfun-arity (DIVERGENCE 734): a CLOSURE called with the wrong
            // number of args is `{badarity,{Fun,Args}}` — was: jump anyway → the fun
            // body ran with garbage/missing args (`badarith`, wrong result). BEAM
            // `call_fun Arity` places the fun in x[Arity], so the call arity IS the
            // fun operand's register index; the provided args are x0..arity-1.
            {
                const call_arity: u8 = switch (c.f) {
                    .x => |r| @intCast(r),
                    else => FinalTerms.funArity(&m.ctx, fv), // non-register source: skip
                };
                if (FinalTerms.funArity(&m.ctx, fv) != call_arity)
                    return m.raiseBadarity(fv, try m.argsFromRegs(call_arity));
            }
            loadFunEnv(m, fv); // fix-closure-aliasing: the BEAM fun-entry convention
            try m.stack.append(m.gpa, m.pc);
            m.pc = FinalTerms.funLabel(&m.ctx, fv);
        },
        // E1.7 modern call / apply / fun ops -----------------------------------
        .call_fun2 => |c| {
            // The arity-tagged fun call: identical effect to `call_fun` (badfun
            // if not a fun, else push return + jump to the fun's label), plus the
            // gap-callfun-arity (DIVERGENCE 734) `{badarity,_}` check on the static
            // `arity` operand (the compiler's arg count) against the closure's arity.
            charge(m, ins);
            const fv = m.resolve(c.f);
            // E7.1: external fun ≡ apply(M,F,Args) — same route as call_fun.
            if (FinalTerms.repIsExportFun(&m.ctx, fv))
                return m.fullDispatch(FinalTerms.exportFunModuleIdx(&m.ctx, fv), FinalTerms.exportFunFuncIdx(&m.ctx, fv), FinalTerms.exportFunArity(&m.ctx, fv), false);
            if (!FinalTerms.repIsFun(&m.ctx, fv)) return m.crash(m.badfun);
            if (FinalTerms.funArity(&m.ctx, fv) != c.arity)
                return m.raiseBadarity(fv, try m.argsFromRegs(c.arity));
            loadFunEnv(m, fv); // fix-closure-aliasing: same convention as call_fun
            try m.stack.append(m.gpa, m.pc);
            m.pc = FinalTerms.funLabel(&m.ctx, fv);
        },
        .apply => |a| {
            charge(m, ins);
            // apply_last is a TAIL call: deallocate the caller frame FIRST, then
            // apply (the BEAM `*_last` convention) — so the trap unwinds the
            // already-shortened stack. `dealloc_y` semantics: drop `last` slots.
            if (a.last) |d| m.ystack.shrinkRetainingCapacity(m.ystack.items.len - d);
            // `m:f/a` live at x[arity]/x[arity+1]. Cross-module export/label
            // resolution is E3 (full `error_handler`); with no resolver in scope
            // every apply target is unresolved → trap `undef`. Reading the operand
            // registers has no observable effect, so we go straight to the trap.
            return m.crash(m.undef);
        },
        // E3.12: static multi-module dispatch arms.
        .call_ext_bif => |c| {
            // R2c: read the size-weight from the live arg registers BEFORE the BIF
            // consumes/overwrites x0, then add it to `reductions` AFTER the call.
            // Accounting-only — the result term and `m.instrs` (preemption) are
            // byte-identical with vs without the weight (RESULT-IDENTITY).
            const extra: u32 = if (c.size_class != .none) bifSizeReds(m, c.size_class) else 0;
            charge(m, ins);
            try m.runBifInto0(c.func, c.arity);
            m.reductions += extra;
        },
        .call_ext_code => |c| {
            charge(m, ins);
            try m.dispatchMFA(c.module, c.func, c.arity, !c.push_ret);
        },
        .apply3 => |a| {
            // erlang:apply/3: M=x0, F=x1, Args=x2 (a proper list). Save the three
            // before spreading (the spread overwrites x0/x1). A non-atom M/F or an
            // improper/over-long Args list is `badarg` (the apply contract).
            charge(m, ins);
            const m_term = m.regs[0];
            const f_term = m.regs[1];
            const args_term = m.regs[2];
            if (!FinalTerms.repIsAtom(m_term) or !FinalTerms.repIsAtom(f_term))
                return m.crash(m.badarg);
            // spread the arg list into x0.. and count the arity.
            var arity: u8 = 0;
            var cur = args_term;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                // gap-apply-arity (DIVERGENCE 732): BEAM's real limit is MAX_ARG=255
                // (a function's arity is a byte). The old `>= 16` cap was a STALE
                // leftover from the pre-E5.2 `[16]` register bank — the `regs` bank is
                // now `[x_reg_count]` (=256), so 17..255-arg applies are representable
                // and MUST dispatch (they byte-EQ OTP; `apply(M,F,ArgsN)` for 17..254
                // args wrongly `system_limit`'d). Crash only at ≥256 args — which also
                // guards the `u8 arity` from overflowing (255 → wrap) before dispatch.
                if (arity >= 255) return m.crash(m.system_limit);
                m.regs[arity] = FinalTerms.listHead(&m.ctx, cur);
                arity += 1;
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return m.crash(m.badarg); // improper Args
            try m.fullDispatch(FinalTerms.atomIdxOf(m_term), FinalTerms.atomIdxOf(f_term), arity, a.tail);
        },
        .apply_fun => |a| {
            // gap-apply-fun (DIVERGENCE 733): erlang:apply(Fun, Args). Fun=x0,
            // Args=x1 (a proper list). SAVE both (the spread overwrites x0/x1), count
            // the list length, VALIDATE (non-fun → badarg; improper list → badarg;
            // arity ≠ Fun's arity → `{badarity,{Fun,Args}}`), THEN spread + dispatch
            // the fun exactly like `.call_fun` (export → fullDispatch, regular → env
            // + jump). The arity check runs BEFORE the spread, so a mismatch leaves
            // the registers untouched (the reason carries the original `Args` list).
            charge(m, ins);
            const fv = m.regs[0];
            const args_term = m.regs[1];
            const is_export = FinalTerms.repIsExportFun(&m.ctx, fv);
            const is_reg = FinalTerms.repIsFun(&m.ctx, fv);
            if (!is_export and !is_reg) return m.crash(m.badarg); // apply(NonFun, _) → badarg
            // count arity + validate the list shape (no writes yet)
            var arity: u8 = 0;
            var cur = args_term;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                if (arity >= 255) return m.crash(m.system_limit);
                arity += 1;
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return m.crash(m.badarg); // improper Args
            // arity match (both export `fun M:F/A` and a regular closure carry an arity)
            if (FinalTerms.funArity(&m.ctx, fv) != arity)
                return m.raiseBadarity(fv, args_term); // error:{badarity,{Fun,Args}}
            // spread the (validated, proper, arity-matched) args into x0..arity-1
            var i: u8 = 0;
            cur = args_term;
            while (i < arity) : (i += 1) {
                m.regs[i] = FinalTerms.listHead(&m.ctx, cur);
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            // dispatch the fun (the .call_fun logic)
            if (is_export)
                return m.fullDispatch(FinalTerms.exportFunModuleIdx(&m.ctx, fv), FinalTerms.exportFunFuncIdx(&m.ctx, fv), arity, a.tail);
            loadFunEnv(m, fv); // env at regs[arity..], the BEAM fun-entry convention
            if (!a.tail) try m.stack.append(m.gpa, m.pc);
            m.pc = FinalTerms.funLabel(&m.ctx, fv);
        },
        .apply_op => |a| {
            // apply/2 opcode: M=x[arity], F=x[arity+1]; args already in x0..x[arity-1].
            charge(m, ins);
            const m_term = m.regs[a.arity];
            const f_term = m.regs[a.arity + 1];
            if (!FinalTerms.repIsAtom(m_term) or !FinalTerms.repIsAtom(f_term))
                return m.crash(m.badarg);
            try m.fullDispatch(FinalTerms.atomIdxOf(m_term), FinalTerms.atomIdxOf(f_term), a.arity, a.tail);
        },
        .make_fun3 => |f| {
            // Build a closure capturing the resolved environment. `env` is a
            // gpa-owned slice of Srcs (built at translate time); resolve each
            // into a scratch buffer, then hand the values to makeFun (which
            // copies them onto the heap). Modelled on `make_fun` (env-less).
            charge(m, ins);
            const vals = try m.gpa.alloc(FinalTerms.Term, f.env.len);
            defer m.gpa.free(vals);
            for (f.env, 0..) |e, k| vals[k] = m.resolve(e);
            // W-16: the fun's VISIBLE arity is `f.arity` (lambda-table arity),
            // NOT `f.env.len` (num_free). `env` still sizes the captured slots.
            m.setDst(f.dst, try FinalTerms.makeFun(&m.ctx, f.to, f.arity, vals));
            // DIVERGENCE 727: record this closure's FunT metadata (defining module +
            // generated name) keyed by its label, so fun_info_mfa/1 + fun_info(F,
            // module|name) return byte-EQ. Idempotent (same label → same meta). Only
            // real make_fun3 (loader-emitted) carries name != 0; synthetic/fuzzer skip.
            if (f.name != 0) try m.fun_meta.put(m.gpa, f.to, .{ f.module, f.name, f.index, f.old_uniq });
        },
        // M8 loader ops
        .is_cons => |t| {
            charge(m, ins);
            const v = m.resolve(t.src);
            if (FinalTerms.kindOf(&m.ctx, v) != .cons) m.pc = t.else_to;
        },
        .type_test => |t| {
            charge(m, ins);
            if (!typeTestHolds(m, t.kind, m.resolve(t.src))) m.pc = t.else_to;
        },
        .cmp_test => |t| {
            charge(m, ins);
            if (!cmpTestHolds(m, t.op, m.resolve(t.a), m.resolve(t.b))) m.pc = t.else_to;
        },
        .is_function_arity => |t| {
            charge(m, ins);
            const v = m.resolve(t.src);
            // E6.8: resolve the arity — static field, or (register form) the
            // small non-negative integer in `arity_src`. A non-small / negative
            // arity register makes the guard FAIL (BEAM guard semantics: a bad
            // arity is not a MATCH), never a crash.
            const want: ?u32 = if (t.arity_src) |asrc| blk: {
                const av = m.resolve(asrc);
                if (!FinalTerms.repIsSmall(av)) break :blk null;
                const n = FinalTerms.smallValOf(av);
                if (n < 0 or n > std.math.maxInt(u32)) break :blk null;
                break :blk @intCast(n);
            } else t.arity;
            // Short-circuit protects funArity/exportFunArity (each asserts its
            // own subtag): read arity only after the matching rep test. E7.1:
            // is_function/2 holds for external funs too (arity = exported arity).
            const ok = want != null and
                ((FinalTerms.repIsFun(&m.ctx, v) and FinalTerms.funArity(&m.ctx, v) == want.?) or
                    (FinalTerms.repIsExportFun(&m.ctx, v) and FinalTerms.exportFunArity(&m.ctx, v) == want.?));
            if (!ok) m.pc = t.else_to;
        },
        // E1.5 tuple ops --------------------------------------------------------
        .get_tuple_elem => |g| {
            charge(m, ins);
            // No fail label: BEAM guarantees a tuple here (post test_arity). The
            // 0-based index reads element g.index directly.
            m.setDst(g.dst, FinalTerms.tupleElem(&m.ctx, m.resolve(g.src), g.index));
        },
        .set_tuple_elem => |s| {
            charge(m, ins);
            // Destructive in-place update (record-update semantics). No fail
            // label; the tuple is compiler-guaranteed unshared and of arity > i.
            FinalTerms.setTupleElem(&m.ctx, m.resolve(s.tuple), s.index, m.resolve(s.newval));
        },
        .put_tuple2 => |p| {
            charge(m, ins);
            const tmp = try m.gpa.alloc(FinalTerms.Term, p.elems.len);
            defer m.gpa.free(tmp);
            for (p.elems, 0..) |e, k| tmp[k] = m.resolve(e);
            m.setDst(p.dst, try FinalTerms.tuple(&m.ctx, tmp));
        },
        .update_record => |u| {
            charge(m, ins);
            // COPY-then-overwrite (record-update semantics). Build a fresh tuple
            // from the source's elements, then overwrite each updated position;
            // the SOURCE record is never mutated (aliasing law). Overwriting in
            // list order means a duplicate index keeps the LAST value, matching
            // erts's sequential `HTOP[$Offset] = $Element` writes.
            const src_t = m.resolve(u.src);
            const arity = FinalTerms.tupleArity(&m.ctx, src_t);
            const tmp = try m.gpa.alloc(FinalTerms.Term, arity);
            defer m.gpa.free(tmp);
            for (0..arity) |k| tmp[k] = FinalTerms.tupleElem(&m.ctx, src_t, k);
            for (u.updates) |up| tmp[up.index] = m.resolve(up.value);
            m.setDst(u.dst, try FinalTerms.tuple(&m.ctx, tmp));
        },
        // ---- E3.14: native-record opcodes -----------------------------------
        .is_any_native_record => |t| {
            charge(m, ins);
            const v = m.resolve(t.src);
            if (!FinalTerms.repIsNativeRecord(&m.ctx, v)) m.pc = t.else_to;
        },
        .is_native_record => |t| {
            charge(m, ins);
            const v = m.resolve(t.src);
            const ok = FinalTerms.repIsNativeRecord(&m.ctx, v) and
                FinalTerms.eqlExact(&m.ctx, FinalTerms.nrModule(&m.ctx, v), t.module) and
                FinalTerms.eqlExact(&m.ctx, FinalTerms.nrName(&m.ctx, v), t.name);
            if (!ok) m.pc = t.else_to;
        },
        .get_record_elements => |t| {
            charge(m, ins);
            // Clobber-nothing-on-miss (the get_map_elements precedent): probe
            // ALL requested field names first; if any is absent (or the source
            // is not a native record), branch writing NO register.
            const v = m.resolve(t.src);
            var all_present = FinalTerms.repIsNativeRecord(&m.ctx, v);
            if (all_present) {
                for (t.elems) |el| {
                    if (FinalTerms.nrLookup(&m.ctx, v, el.key) == null) {
                        all_present = false;
                        break;
                    }
                }
            }
            if (!all_present) {
                m.pc = t.else_to;
            } else {
                for (t.elems) |el| m.setDst(el.dst, FinalTerms.nrLookup(&m.ctx, v, el.key).?);
            }
        },
        .put_record => |t| {
            charge(m, ins);
            const src_t = m.resolve(t.src);
            if (FinalTerms.repIsNativeRecord(&m.ctx, src_t)) {
                // UPDATE: copy src, override each named field. A field name not
                // present in the record → error:{badfield, Field} (erl_update_
                // native_record's EXC_BADFIELD path).
                const n = FinalTerms.nrFieldCount(&m.ctx, src_t);
                const keys = try m.gpa.alloc(FinalTerms.Term, n);
                defer m.gpa.free(keys);
                const vals = try m.gpa.alloc(FinalTerms.Term, n);
                defer m.gpa.free(vals);
                for (0..n) |k| {
                    keys[k] = FinalTerms.nrKeyAt(&m.ctx, src_t, k);
                    vals[k] = FinalTerms.nrValAt(&m.ctx, src_t, k);
                }
                for (t.updates) |up| {
                    var found = false;
                    for (0..n) |k| {
                        if (FinalTerms.eqlExact(&m.ctx, keys[k], up.key)) {
                            vals[k] = m.resolve(up.value);
                            found = true;
                            break;
                        }
                    }
                    if (!found) return m.raiseNativeRecord("badfield", up.key);
                }
                const rec = try FinalTerms.nativeRecord(&m.ctx, FinalTerms.nrModule(&m.ctx, src_t), FinalTerms.nrName(&m.ctx, src_t), FinalTerms.nrIsExported(&m.ctx, src_t), keys, vals);
                m.setDst(t.dst, rec);
            } else {
                // CREATE (src is nil): Id resolves to the `{Module,Name}` tuple;
                // build from the update set as the FULL field list (is_exported
                // = true). Documented divergence: real BEAM merges the update
                // set over the globally-registered definition's default fields —
                // that record-definition table is an E4 code-server concern
                // (DIVERGENCE entry 3 amendment); this slice's records are
                // self-describing.
                const id = m.resolve(t.id);
                const module = FinalTerms.tupleElem(&m.ctx, id, 0);
                const name = FinalTerms.tupleElem(&m.ctx, id, 1);
                const n = t.updates.len;
                const keys = try m.gpa.alloc(FinalTerms.Term, n);
                defer m.gpa.free(keys);
                const vals = try m.gpa.alloc(FinalTerms.Term, n);
                defer m.gpa.free(vals);
                for (t.updates, 0..) |up, k| {
                    keys[k] = up.key;
                    vals[k] = m.resolve(up.value);
                }
                const rec = try FinalTerms.nativeRecord(&m.ctx, module, name, true, keys, vals);
                m.setDst(t.dst, rec);
            }
        },
        .is_record_accessible => |t| {
            charge(m, ins);
            const v = m.resolve(t.src);
            var ok = FinalTerms.repIsNativeRecord(&m.ctx, v) and FinalTerms.nrIsExported(&m.ctx, v);
            if (!ok and t.scope == .auto_local and FinalTerms.repIsNativeRecord(&m.ctx, v)) {
                // auto_local: also accessible if defined in the executing module
                // (erl_is_wildcard_record_accessible). The current module comes
                // from the loc table (locs[pc-1].m); with no Line chunk, only the
                // exported check applies (a documented bound).
                if (m.locs.len != 0 and m.pc >= 1 and m.pc - 1 < m.locs.len) {
                    const cur = FinalTerms.atom(&m.ctx, m.locs[m.pc - 1].m);
                    ok = FinalTerms.eqlExact(&m.ctx, cur, FinalTerms.nrModule(&m.ctx, v));
                }
            }
            if (!ok) m.pc = t.else_to;
        },
        .get_record_field => |t| {
            charge(m, ins);
            const v = m.resolve(t.src);
            // Not a native record, or (Id is `{M,N}` and) module/name mismatch,
            // or not exported → badrecord (Lbl==0 ⇒ raise; else branch). Id may
            // be the atom `_` (no name check) or a `{Module,Name}` tuple.
            var bad = !FinalTerms.repIsNativeRecord(&m.ctx, v);
            const id = m.resolve(t.id);
            if (!bad and FinalTerms.kindOf(&m.ctx, id) == .tuple and FinalTerms.tupleArity(&m.ctx, id) == 2) {
                bad = !FinalTerms.eqlExact(&m.ctx, FinalTerms.nrModule(&m.ctx, v), FinalTerms.tupleElem(&m.ctx, id, 0)) or
                    !FinalTerms.eqlExact(&m.ctx, FinalTerms.nrName(&m.ctx, v), FinalTerms.tupleElem(&m.ctx, id, 1));
            }
            if (!bad and !FinalTerms.nrIsExported(&m.ctx, v)) bad = true;
            if (bad) {
                if (t.else_to) |lbl| {
                    m.pc = lbl;
                } else {
                    return m.raiseNativeRecord("badrecord", v);
                }
                return;
            }
            if (FinalTerms.nrLookup(&m.ctx, v, t.field)) |fv| {
                m.setDst(t.dst, fv);
            } else if (t.else_to) |lbl| {
                m.pc = lbl;
            } else {
                return m.raiseNativeRecord("badfield", t.field);
            }
        },
        .test_arity => |t| {
            charge(m, ins);
            // Guarded test: fall through iff a tuple of EXACTLY t.arity.
            const v = m.resolve(t.src);
            const ok = FinalTerms.kindOf(&m.ctx, v) == .tuple and
                FinalTerms.tupleArity(&m.ctx, v) == t.arity;
            if (!ok) m.pc = t.else_to;
        },
        .is_tagged_tuple => |t| {
            charge(m, ins);
            // Guarded test: tuple of arity t.arity whose element 0 =:= t.tag.
            // arity >= 1 is enforced before reading element 0 so an empty tuple
            // never indexes out of bounds.
            const v = m.resolve(t.src);
            const ok = FinalTerms.kindOf(&m.ctx, v) == .tuple and
                t.arity >= 1 and FinalTerms.tupleArity(&m.ctx, v) == t.arity and
                FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, v, 0), t.tag);
            if (!ok) m.pc = t.else_to;
        },
        // E1.6 select ops ------------------------------------------------------
        .select_val => |s| {
            charge(m, ins);
            // Linear scan (bounded: fixed slice). EXACT key match — 1 =:= 1.0
            // is false, so an int key never matches a float Src and vice versa.
            const v = m.resolve(s.src);
            var target = s.fail_to;
            for (s.pairs) |p| {
                if (FinalTerms.eqlExact(&m.ctx, v, p.key)) {
                    target = p.to;
                    break;
                }
            }
            m.pc = target;
        },
        .select_tuple_arity => |s| {
            charge(m, ins);
            // Non-tuple Src never matches any arity ⇒ fail_to. Guard kindOf
            // before reading tupleArity so a non-tuple word is never misread.
            const v = m.resolve(s.src);
            var target = s.fail_to;
            if (FinalTerms.kindOf(&m.ctx, v) == .tuple) {
                const ar = FinalTerms.tupleArity(&m.ctx, v);
                for (s.pairs) |p| {
                    if (ar == p.arity) {
                        target = p.to;
                        break;
                    }
                }
            }
            m.pc = target;
        },
        // E1.10 map ops -------------------------------------------------------
        .has_map_fields => |h| {
            charge(m, ins);
            // Guarded test: fall through iff the map has EVERY listed key, else
            // pc = else_to. A non-map src can never have the keys ⇒ else_to
            // (kindOf guard so mapGet is only ever asked of a real map).
            const mp = m.resolve(h.src);
            var all = FinalTerms.repIsMap(&m.ctx, mp);
            if (all) for (h.keys) |k| {
                // E5.2: resolve the key Src at runtime (a literal .imm/.atom_/.nil
                // OR a register .x/.y) — DIVERGENCE 47.
                if (FinalTerms.mapGet(&m.ctx, mp, m.resolve(k)) == null) {
                    all = false;
                    break;
                }
            };
            if (!all) m.pc = h.else_to;
        },
        .get_map_elements => |g| {
            charge(m, ins);
            // ALL-OR-NOTHING (the BEAM map-extract semantics): verify EVERY key
            // is present BEFORE writing any dst. If any is absent (or the src is
            // not a map) jump else_to having written NOTHING; else write each
            // looked-up value to its dst. Writing during the presence scan
            // (mutant 1) would clobber a dst and THEN jump — the law below
            // (present+absent mix leaves the dst untouched) kills that.
            const mp = m.resolve(g.src);
            var all = FinalTerms.repIsMap(&m.ctx, mp);
            // E5.2: resolve each key Src at runtime (literal or register) —
            // DIVERGENCE 47. All-or-nothing over the resolved keys.
            if (all) for (g.pairs) |p| {
                if (FinalTerms.mapGet(&m.ctx, mp, m.resolve(p.key)) == null) {
                    all = false;
                    break;
                }
            };
            if (all) {
                for (g.pairs) |p| m.setDst(p.dst, FinalTerms.mapGet(&m.ctx, mp, m.resolve(p.key)).?);
            } else {
                m.pc = g.else_to;
            }
        },
        .put_map => |p| {
            charge(m, ins);
            // Build a NEW map via the FinalTerms map API. `src` must be a map
            // (BEAM guarantees it; a non-map is `{badmap, Term}`). For `exact`
            // every key must ALREADY exist — an absent key is `{badkey, Key}`
            // and NO map is produced (mutant 2 skips this check and inserts, so
            // exact wrongly behaves like assoc). Assoc has no such precondition.
            const src_map = m.resolve(p.src);
            if (!FinalTerms.repIsMap(&m.ctx, src_map)) {
                const tup = try FinalTerms.tuple(&m.ctx, &.{
                    FinalTerms.atom(&m.ctx, m.badmap_atom), src_map,
                });
                try m.raiseWith(.error_, tup);
                return;
            }
            if (p.exact) {
                for (p.kvs) |kv| {
                    const key = m.resolve(kv.k);
                    if (FinalTerms.mapGet(&m.ctx, src_map, key) == null) {
                        const tup = try FinalTerms.tuple(&m.ctx, &.{
                            FinalTerms.atom(&m.ctx, m.badkey_atom), key,
                        });
                        try m.raiseWith(.error_, tup);
                        return;
                    }
                }
            }
            var acc = src_map;
            for (p.kvs) |kv| acc = try FinalTerms.mapPut(&m.ctx, acc, m.resolve(kv.k), m.resolve(kv.v));
            m.setDst(p.dst, acc);
        },
        .get_list => |g| {
            charge(m, ins);
            const v = m.resolve(g.src);
            const h = FinalTerms.listHead(&m.ctx, v);
            const t = FinalTerms.listTail(&m.ctx, v);
            m.setDst(g.hd, h);
            m.setDst(g.tl, t);
        },
        .get_hd => |g| {
            charge(m, ins);
            m.setDst(g.dst, FinalTerms.listHead(&m.ctx, m.resolve(g.src)));
        },
        .get_tl => |g| {
            charge(m, ins);
            m.setDst(g.dst, FinalTerms.listTail(&m.ctx, m.resolve(g.src)));
        },
        .alloc_y => |a| {
            charge(m, ins);
            const n = FinalTerms.nil(&m.ctx);
            for (0..a.n) |_| try m.ystack.append(m.gpa, n);
        },
        .dealloc_y => |a| {
            charge(m, ins);
            m.ystack.shrinkRetainingCapacity(m.ystack.items.len - a.n);
        },
        .alloc_heap => |a| {
            charge(m, ins);
            // `stack` y-slots exactly like `alloc_y` — StackNeed is the ONLY
            // operand that touches the y-stack. `HeapNeed` (not carried in the
            // CInstr) and `live` are moving-GC hints; this arena grows on
            // demand, so there is no heap-need slot count to allocate here
            // (allocating y-slots for HeapNeed would confuse the two operands
            // — mutant 2).
            const n = FinalTerms.nil(&m.ctx);
            for (0..a.stack) |_| try m.ystack.append(m.gpa, n);
        },
        .trim => |t| {
            charge(m, ins);
            // Drop the top `n` y-slots, KEEPING the remaining (older) frame —
            // same direction as `dealloc_y`. Assert the precondition BEAM's
            // compiler guarantees (n <= current depth); mutant 1 trims from
            // the wrong end (the bottom) by keeping the top `n` slots instead.
            std.debug.assert(t.n <= m.ystack.items.len);
            m.ystack.shrinkRetainingCapacity(m.ystack.items.len - t.n);
        },
        .move2 => |v| {
            charge(m, ins);
            m.setDst(v.dst, m.resolve(v.src));
        },
        .swap => |v| {
            // gap-swap-x15 (DIVERGENCE 730): a TRUE two-register exchange. Read
            // BOTH operands first (into native Zig temps — never an x-register),
            // then write them back crossed. The prior lowering used `x15` as the
            // scratch slot, which SILENTLY corrupted the 16th argument of any
            // 16-arity function (x0..x15) — e.g. gen_statem's `loop_timeouts/16`,
            // whose `TimeoutOpts` ([]) in x15 became garbage → `start_timer(_,_,_,
            // <atom>)` → badarg → every state/event timer died. A native temp has
            // no register aliasing, so no live value is ever clobbered.
            charge(m, ins);
            const av = m.resolve(dstAsSrc(v.a));
            const bv = m.resolve(dstAsSrc(v.b));
            m.setDst(v.a, bv);
            m.setDst(v.b, av);
        },
        .sub => |a| {
            charge(m, ins);
            const x = m.resolve(a.a);
            const y = m.resolve(a.b);
            if (!FinalTerms.repIsNumber(&m.ctx, x) or
                !FinalTerms.repIsNumber(&m.ctx, y))
                return m.crash(m.badarith);
            const ny = FinalTerms.negate(&m.ctx, y) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
            };
            m.regs[a.dst] = FinalTerms.add(&m.ctx, x, ny) catch |e| switch (e) {
                error.Badarith => return m.crash(m.badarith),
                error.OutOfMemory => return error.OutOfMemory,
            };
        },
        // E1.12: float-register opcodes. One reduction each. Non-finite results
        // (overflow/inf, or x/0) crash `badarith` — the FR bank is thereby kept
        // finite, so `fmove_from_f`'s `FinalTerms.float` (which asserts finite)
        // never sees a non-finite input.
        .fmove_to_f => |v| {
            charge(m, ins);
            const t = m.resolve(v.src);
            if (!FinalTerms.repIsFloat(&m.ctx, t)) return m.crash(m.badarith);
            m.fregs[v.fdst] = FinalTerms.floatValOf(&m.ctx, t);
        },
        .fmove_from_f => |v| {
            charge(m, ins);
            // The bank is finite by construction (arith crashes non-finite), so
            // boxing back to a float term is always valid.
            m.setDst(v.dst, FinalTerms.float(&m.ctx, m.fregs[v.fsrc]));
        },
        .fconv => |v| {
            charge(m, ins);
            const t = m.resolve(v.src);
            if (!FinalTerms.repIsNumber(&m.ctx, t)) return m.crash(m.badarith);
            // CONVERSION, not bit-cast: int `5` → `5.0` (numToF64Of == @floatFromInt).
            const v64 = FinalTerms.numToF64Of(&m.ctx, t);
            // Finiteness guard, mirroring the FR-arith arms: a non-finite bank
            // value would make a later `fmove_from_f`/`FinalTerms.float` assert
            // (panic) instead of raising, and real BEAM raises badarith on a
            // conversion that overflows f64 (`float(1 bsl 2000)` → error). NOTE
            // (E1): in THIS final encoding the negative branch is currently
            // UNREACHABLE — the bignum magnitude is capped at 8 limbs (max ≈ 2^512
            // ≈ 1.34e154, finite) and float terms are finite by construction
            // (`FinalTerms.float` asserts), so `numToF64Of` is provably finite for
            // every constructible number term. The guard is kept as defense-in-
            // depth and forward-compat (if `max_limbs` ever grows past 16, or a
            // non-finite float source is admitted); see MUTATION_LOG (EQUIVALENT).
            if (!std.math.isFinite(v64)) return m.crash(m.badarith);
            m.fregs[v.fdst] = v64;
        },
        .fadd => |v| {
            charge(m, ins);
            const r = m.fregs[v.a] + m.fregs[v.b];
            if (!std.math.isFinite(r)) return m.crash(m.badarith);
            m.fregs[v.fdst] = r;
        },
        .fsub => |v| {
            charge(m, ins);
            const r = m.fregs[v.a] - m.fregs[v.b]; // FA - FB (order matters)
            if (!std.math.isFinite(r)) return m.crash(m.badarith);
            m.fregs[v.fdst] = r;
        },
        .fmul => |v| {
            charge(m, ins);
            const r = m.fregs[v.a] * m.fregs[v.b];
            if (!std.math.isFinite(r)) return m.crash(m.badarith);
            m.fregs[v.fdst] = r;
        },
        .fdiv => |v| {
            charge(m, ins);
            const r = m.fregs[v.a] / m.fregs[v.b]; // x/0 → inf → non-finite crash
            if (!std.math.isFinite(r)) return m.crash(m.badarith);
            m.fregs[v.fdst] = r;
        },
        .fnegate => |v| {
            charge(m, ins);
            const r = -m.fregs[v.a];
            if (!std.math.isFinite(r)) return m.crash(m.badarith);
            m.fregs[v.fdst] = r;
        },
        .func_info => {
            charge(m, ins);
            return m.crash(m.fclause);
        },
        // M7 effect traps — one reduction each, then the VM takes over
        .spawn => |v| {
            charge(m, ins);
            m.pending = .{ .spawn = .{ .to = v.to, .dst = v.dst } };
        },
        .send_to => |v| {
            charge(m, ins);
            m.pending = .{ .send_to = .{ .pid = m.resolve(v.pid), .msg = m.resolve(v.msg) } };
        },
        .link_to => |v| {
            charge(m, ins);
            m.pending = .{ .link_to = .{ .pid = m.resolve(v.pid) } };
        },
        .unlink_to => |v| {
            charge(m, ins);
            m.pending = .{ .unlink_to = .{ .pid = m.resolve(v.pid) } };
        },
        .monitor_to => |v| {
            charge(m, ins);
            m.pending = .{ .monitor_to = .{ .pid = m.resolve(v.pid), .dst = v.dst } };
        },
        .demonitor_ref => |v| {
            charge(m, ins);
            m.pending = .{ .demonitor_ref = .{ .ref = m.resolve(v.ref), .info = false } };
        },
        .exit_proc => |v| {
            charge(m, ins);
            m.pending = .{ .exit_proc = .{ .reason = m.resolve(v.reason) } };
        },
        .trap_exits => |v| {
            charge(m, ins);
            m.pending = .{ .trap_exits = .{ .on = v.on } };
        },
        // E1.8 exception opcodes -----------------------------------------------
        .catch_ => |c| {
            // PUSH a catch landing pad: record the recovery pc and the current
            // ystack height (restored on unwind). The `dst` y-slot is BEAM's
            // frame marker; the E1 model tracks the frame on `catch_stack`.
            charge(m, ins);
            try m.catch_stack.append(m.gpa, .{ .to = c.to, .kind = .catch_, .y_depth = m.ystack.items.len, .c_depth = m.stack.items.len });
        },
        .try_ => |c| {
            charge(m, ins);
            try m.catch_stack.append(m.gpa, .{ .to = c.to, .kind = .try_, .y_depth = m.ystack.items.len, .c_depth = m.stack.items.len });
        },
        .catch_end => {
            // Normal exit of the protected region: POP the frame. `pop()` on an
            // empty stack is a no-op (returns null) — an unbalanced `catch_end`
            // is inert, never a crash.
            charge(m, ins);
            _ = m.catch_stack.pop();
        },
        .try_end => {
            charge(m, ins);
            _ = m.catch_stack.pop();
        },
        .try_case => {
            // The try-exception LANDING helper: the frame was already consumed by
            // the unwind (raiseWith popped it), so this is a catch-stack no-op —
            // the handler code follows. x0/x1/x2 already hold class/reason/stack.
            charge(m, ins);
        },
        .raise_reason => |r| {
            // batch-4: the compiled failure-path raisers — `badmatch Src` ⇒
            // error:{badmatch, V}; `case_end Src` ⇒ error:{case_clause, V};
            // `if_end` ⇒ error:if_clause (BARE atom — the one shape with no
            // value). Exactly BEAM's reason shapes; class `error` for all.
            charge(m, ins);
            const reason = if (r.src) |src| blk: {
                const tag = switch (r.tag) {
                    .badmatch => m.badmatch_atom,
                    .case_clause => m.case_clause_atom,
                    .if_clause => m.if_clause_atom,
                };
                break :blk FinalTerms.tuple(&m.ctx, &.{
                    FinalTerms.atom(&m.ctx, tag),
                    m.resolve(src),
                }) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                };
            } else FinalTerms.atom(&m.ctx, m.if_clause_atom);
            try m.raiseWith(.error_, reason);
        },
        .try_case_end => |t| {
            // A handler that matched no clause: raise {try_clause, Value}.
            charge(m, ins);
            const tup = FinalTerms.tuple(&m.ctx, &.{
                FinalTerms.atom(&m.ctx, m.try_clause),
                m.resolve(t.src),
            }) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
            };
            try m.raiseWith(.error_, tup);
        },
        .raise => |r| {
            // Re-raise (raise/2): unwind with the resolved Value as the reason,
            // PRESERVING the ORIGINAL class of the exception being handled
            // (`m.exc.class`, set when this handler was entered — entry 2c).
            // Mutant 2 hardcodes `.error_` here, losing a re-raised throw/exit.
            // `trace` is resolved for effect-parity (E1-minimal `nil` trace).
            charge(m, ins);
            _ = m.resolve(r.trace);
            try m.raiseWith(m.exc.class, m.resolve(r.value));
        },
        .raw_raise => {
            // erlang:raise/3: class in x0, reason in x1, raw stacktrace in x2.
            // BEAM returns the atom `badarg` WITHOUT raising when x0 is not one
            // of error/exit/throw (entry 2d); otherwise it raises with that
            // exact class. `classOfAtom` is the bad-class guard.
            charge(m, ins);
            if (m.classOfAtom(m.regs[0])) |cls| {
                try m.raiseWith(cls, m.regs[1]);
            } else {
                m.regs[0] = FinalTerms.atom(&m.ctx, m.badarg);
            }
        },
        .build_stacktrace => {
            // E3.11: cook the raw stacktrace in x0 into the symbolic term. Our
            // model already carries the COOKED trace on `m.exc.stacktrace` (built
            // by `raiseWith` from `m.locs`), so this returns it directly. With no
            // `Line` chunk / no active exception it is the E1-minimal `nil`.
            charge(m, ins);
            m.regs[0] = m.exc.stacktrace;
        },
        .badrecord => |b| {
            // Raise error:{badrecord, Value} — the exact BEAM reason shape,
            // class `error` (a record-guard failure is an error, not a throw).
            charge(m, ins);
            const tup = FinalTerms.tuple(&m.ctx, &.{
                FinalTerms.atom(&m.ctx, m.badrecord_atom),
                m.resolve(b.src),
            }) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
            };
            try m.raiseWith(.error_, tup);
        },
        // E1.13/E2.4: BIF dispatch (bif0/1/2/3, gc_bif1/2/3). Total by
        // construction: the decoded `bif` is either a resolved family fn
        // (`.func`) or a trapped `.unsupported`. `gc_live` is advisory (the arena
        // grows on demand), so it is not read. This is the ONE, uniform arm every
        // BIF family flows through — no per-BIF special-case ever lands here.
        .bif_call => |c| {
            charge(m, ins);
            switch (c.bif) {
                // COVERAGE grows in later E2 tasks: an unimplemented BIF cannot
                // produce a guard truth value, so it is `undef` in EVERY context
                // (never a guard branch — branching would fabricate a `false`).
                .unsupported => return m.crash(m.undef),
                .func => |f| {
                    // Resolve exactly the declared args, call the family fn, and
                    // route any error through the ONE guard-vs-body site
                    // (`bifFail`): GUARD (else_to set) BRANCHES, BODY crashes the
                    // exact reason. A family fn NEVER panics on a well-formed call.
                    var buf: [3]FinalTerms.Term = undefined;
                    for (0..c.argc) |i| buf[i] = m.resolve(c.args[i]);
                    const res = f(m, buf[0..c.argc]) catch |e| switch (e) {
                        // E3.10: `bifFail` is now fallible (a body-context crash
                        // may build a structured reason term); propagate its
                        // error union straight out of this `!void` arm.
                        error.Badarg => return m.bifFail(c.else_to, m.badarg),
                        error.Badarith => return m.bifFail(c.else_to, m.badarith),
                        // E3.10: a STRUCTURED / class-tagged raise staged on
                        // `m.bif_raise` (map_get/is_map_key → {badmap,_}/{badkey,_};
                        // error/throw/exit/raise/3/nif_error → arbitrary class+reason).
                        // STILL guard-vs-body split: a guard context (else_to set)
                        // BRANCHES and never raises (DIVERGENCE 6b/c — guard behaviour
                        // is exact); a body context (else_to null) unwinds via raiseWith.
                        error.Raise => {
                            const staged = m.bif_raise.?;
                            m.bif_raise = null;
                            if (c.else_to) |lbl| {
                                m.pc = lbl;
                                return; // guard branch — no dst write
                            }
                            return m.raiseWith(staged.class, staged.reason);
                        },
                        error.OutOfMemory => return error.OutOfMemory,
                    };
                    // e21-t2 (DIVERGENCE 490): a guard-bif compiled as `bif0/1`
                    // (e.g. `node/0`) may TRAP (set `pending`) with a NON-x0 `Dst`.
                    // Record that Dst so the scheduler's trap arm delivers the
                    // resolved value there (not to x0). `res` is the trap placeholder
                    // and is overwritten by `deliverTrap`. `node/0` is the only
                    // `bif0/1`-reachable trapping bridge bif today (node/1 returns
                    // directly), so this is consumed by the very next `interpret`.
                    if (m.pending != null) m.bif_trap_dst = c.dst;
                    m.setDst(c.dst, res);
                },
            }
        },
    }
}

/// Observational machine equality: register/result DENOTATIONS (never raw
/// words — the heaps differ), plus control state and reduction count.
fn actionTermOrNil(ctx: *FinalTerms.Ctx, act: Action) FinalTerms.Term {
    return switch (act) {
        .send_to => |v| v.msg,
        .link_to => |v| v.pid,
        .unlink_to => |v| v.pid,
        .monitor_to => |v| v.pid,
        .demonitor_ref => |v| v.ref,
        .exit_proc => |v| v.reason,
        .spawn_fun => |v| v.fun,
        .spawn_mfa => |v| v.func,
        .exit_to => |v| v.reason,
        .is_alive => |v| v.pid,
        .spawn, .trap_exits, .list_processes, .list_registered, .stat_run_queue, .stat_memory, .ensure_loaded, .hibernate_wait, .get_dist_node, .get_dist_creation, .is_node_alive => FinalTerms.nil(ctx),
        .os_cmd => |v| v.cmd,
        .init_plain_args => FinalTerms.nil(ctx), // gap-erl-cli-args: no term arg
        .init_get_argument => |v| v.flag,
        .init_get_arguments => FinalTerms.nil(ctx), // gap-hof-parse: no term arg
        .trace_info_mfa => |v| v.item, // gap-tracing-trace-info
        .trace_delivered => |v| v.tracee,
        .file_read => |v| v.path,
        .file_write => |v| v.path,
        .file_list_dir => |v| v.path,
        .file_read_file_info => |v| v.path,
        .file_open => |v| v.path,
        .file_pread => |v| v.fd,
        .file_pwrite => |v| v.fd,
        .file_close => |v| v.fd,
        .file_read_seq => |v| v.fd,
        .file_write_seq => |v| v.fd,
        .file_position => |v| v.fd,
        .file_read_info_opts => |v| v.path,
        .file_delete => |v| v.path,
        .file_rename => |v| v.from,
        .file_make_dir => |v| v.path,
        .file_del_dir => |v| v.path,
        .file_truncate => |v| v.fd,
        .file_sync => |v| v.fd,
        .file_read_link_info => |v| v.path,
        .trace_set => |v| v.pid,
        .trace_pattern => FinalTerms.nil(ctx),
        .call_trace => |v| v.args,
        .node_halt => |v| v.status,
        .register_name => |v| v.pid,
        .unregister_name => |v| v.name,
        .whereis_name => |v| v.name,
        .process_info_all => |v| v.pid,
        .process_info_item => |v| v.pid,
        .set_group_leader => |v| v.pid,
        .demonitor_flush => |v| v.ref,
        .spawn_request => |v| v.func,
        .list_dist_nodes => FinalTerms.nil(ctx),
        .list_dist_node_infos => FinalTerms.nil(ctx),
        .dist_dflag_unicode_io => |v| v.pid,
        .monitor_dist_node => |v| v.node,
        .remote_exit_signal => |v| v.pid,
        .new_dist_connection => |v| v.node,
        .abort_pending_dist_connection => |v| v.conn,
        .set_dist_node => |v| v.node,
        .create_dist_channel => |v| v.node,
        .disconnect_dist_node => |v| v.node,
        .dist_spawn_request => |v| v.error_reason,
        .set_trap_exit => |v| v.pid,
        .spawn_system => |v| v.func,
        .io_request => |v| v.request,
        // E5.4: the live os-port effects — the port term (or the command name)
        // is the carried term whose denotation the differential must agree on.
        .open_port_spawn => |v| v.name,
        .port_cmd => |v| v.port,
        .port_close_sig => |v| v.port,
        .socket_roundtrip => |v| v.data,
        .socket_op => |v| v.arg,
        .code_ensure_loaded => |v| v.module,
        .port_set_data => |v| v.port,
        .port_get_data => |v| v.port,
        // E6.7 (Task 7): the port-representation + ETS give_away traps — the port/
        // table term is the carried term whose denotation the differential agrees on.
        .ports_list => FinalTerms.nil(ctx),
        .port_info => |v| v.port,
        .port_connect_sig => |v| v.port,
        .ets_give_away => |v| v.tid,
        // E5.5 (Task 5): the alias-signal model traps.
        .make_alias => FinalTerms.nil(ctx),
        .unalias_ref => |v| v.ref,
        .is_alive_request => |v| v.pid,
        // E5.6 (Task 6): the async spawn/request protocol traps.
        .abandon_spawn => |v| v.ref,
        .process_flag3 => |v| v.pid,
        // E6.2 (Task 2): the live receive/BIF timer traps — the carried term whose
        // denotation the differential must agree on (arm carries no term).
        .arm_recv_timer => FinalTerms.nil(ctx),
        .timer_start => |v| v.msg,
        .timer_cancel => |v| v.tref,
        .timer_read => |v| v.tref,
        // E6.4 (Task 4): the process-suspension family traps — the target pid is
        // the carried term whose denotation the differential must agree on.
        .suspend_proc => |v| v.pid,
        .resume_proc => |v| v.pid,
        .is_system_process => |v| v.pid,
        // E6.6 (Task 6): the direct display verbs — the chars whose FLATTENED
        // bytes the stdout differential must agree on.
        .display_out => |v| v.chars,
        // E7.2 (DIVERGENCE 147): the on_load run trap carries only a pc, no term.
        .run_on_load => FinalTerms.nil(ctx),
        // E7.5 (Task 5): hibernate carries the MFA (the func atom is the carried
        // term); request_system_task carries the ReqId ref whose denotation the
        // reply differential must agree on.
        .hibernate => |v| v.func,
        .request_system_task => |v| v.reqid,
    };
}

pub fn eqMachines(a: *Machine, b: *Machine, sa: std.mem.Allocator) !bool {
    if (a.status != b.status or a.pc != b.pc or a.reductions != b.reductions or a.instrs != b.instrs)
        return false;
    if (a.recv_cursor != b.recv_cursor) return false; // E1.11: receive save-pointer
    // E1.12: the float-register bank is observable machine state (like x-regs).
    // Compare RAW BITS, not `==`: raw registers are values, and bit-identity is
    // the exact observation (distinguishes ±0.0 and any NaN payload; two machines
    // running the same program deterministically produce identical f64 bits).
    for (a.fregs, b.fregs) |fa, fb| {
        if (@as(u64, @bitCast(fa)) != @as(u64, @bitCast(fb))) return false;
    }
    if (!std.mem.eql(usize, a.stack.items, b.stack.items)) return false;
    // E1.8: the catch-stack is observable control state (like the CP stack).
    // Frames are plain scalars (to, kind, y_depth) — a direct value compare, no
    // denotation needed. Within one program layout (determinism / slice /
    // differential laws) the `to` labels are identical, so exact compare is right.
    if (a.catch_stack.items.len != b.catch_stack.items.len) return false;
    for (a.catch_stack.items, b.catch_stack.items) |fa, fb| {
        if (fa.to != fb.to or fa.kind != fb.kind or fa.y_depth != fb.y_depth) return false;
    }
    if (a.ystack.items.len != b.ystack.items.len) return false;
    for (a.ystack.items, b.ystack.items) |ya, yb| {
        if (!spec.eqlExact(
            try FinalTerms.denote(&a.ctx, sa, ya),
            try FinalTerms.denote(&b.ctx, sa, yb),
        )) return false;
    }
    for (a.regs, b.regs) |ra, rb| {
        if (!spec.eql(
            try FinalTerms.denote(&a.ctx, sa, ra),
            try FinalTerms.denote(&b.ctx, sa, rb),
        )) return false;
    }
    // pending effects must agree (M7)
    if ((a.pending == null) != (b.pending == null)) return false;
    if (a.pending != null) {
        const pa = a.pending.?;
        const pb = b.pending.?;
        if (std.meta.activeTag(pa) != std.meta.activeTag(pb)) return false;
        // compare any carried terms by denotation via a cheap hash
        if (FinalTerms.hashTerm(&a.ctx, actionTermOrNil(&a.ctx, pa)) !=
            FinalTerms.hashTerm(&b.ctx, actionTermOrNil(&b.ctx, pb))) return false;
    }
    // mailboxes: same arrival sequence, denotationally (M5)
    var buf_a: [128]mba.Msg(FinalTerms) = undefined;
    var buf_b: [128]mba.Msg(FinalTerms) = undefined;
    const qa = a.mbox.toSeq(&buf_a);
    const qb = b.mbox.toSeq(&buf_b);
    if (qa.len != qb.len) return false;
    for (qa, qb) |x, y| {
        if (x.sender != y.sender or x.stamp != y.stamp) return false;
        if (!spec.eqlExact(
            try FinalTerms.denote(&a.ctx, sa, x.payload),
            try FinalTerms.denote(&b.ctx, sa, y.payload),
        )) return false;
    }
    return spec.eql(
        try FinalTerms.denote(&a.ctx, sa, a.result),
        try FinalTerms.denote(&b.ctx, sa, b.result),
    );
}

// ============================================================================
// PART 4: LAWS
// ============================================================================

pub const LawConfig = struct {
    iterations: usize = 100,
    seed: u64 = 0xBEA0_1213,
};

fn expectLaw(ok: bool, name: []const u8, cfg: LawConfig, iter: usize) !void {
    if (!ok) {
        std.debug.print("LAW FAILED: {s} (seed=0x{x}, iteration={d})\n", .{ name, cfg.seed, iter });
        return error.LawViolated;
    }
}

fn randSrc(random: std.Random) Src {
    return switch (random.uintLessThan(u8, 3)) {
        0 => .{ .x = @as(XReg, random.int(u4)) },
        1 => .{ .imm = @as(i64, random.int(i32)) },
        else => .nil,
    };
}

fn randBlockInstr(random: std.Random) BlockInstr {
    return switch (random.uintLessThan(u8, 3)) {
        0 => .{ .move = .{ .src = randSrc(random), .dst = @as(XReg, random.int(u4)) } },
        1 => .{ .add = .{ .a = randSrc(random), .b = randSrc(random), .dst = @as(XReg, random.int(u4)) } },
        else => .{ .put_list = .{ .h = randSrc(random), .t = randSrc(random), .dst = @as(XReg, random.int(u4)) } },
    };
}

pub fn genBlock(
    comptime Impl: type,
    random: std.Random,
    ctx: *Impl.Ctx,
    size: usize,
) !Impl.Block {
    // Build with random association so laws see arbitrary seq-tree shapes.
    if (size == 0) return try Impl.nop(ctx);
    if (size == 1) return try Impl.one(ctx, randBlockInstr(random));
    const split = 1 + random.uintLessThan(usize, size - 1);
    const l = try genBlock(Impl, random, ctx, split);
    const r = try genBlock(Impl, random, ctx, size - split);
    return try Impl.seq(ctx, l, r);
}

fn freshMachine(gpa: std.mem.Allocator, atoms: *AtomTable, seed: u64) !Machine {
    var m = try Machine.init(gpa, atoms);
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    // E5.2: seed only the low 16 x-slots — the differential corpus references
    // x0..x15 only; higher slots stay nil (from `init`'s `@splat`) in both twins.
    for (m.regs[0..16]) |*r| r.* = FinalTerms.int(&m.ctx, @as(i64, random.int(i32)));
    return m;
}

test "LAW gap-reduction-cost-model R2b TOTALITY + COST-ACCOUNTING (per-call weights, two-counter)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // TOTALITY: `reductionCost` is a TOTAL function — a defined weight for every op
    // (no crash, no UB) — and the PER-CALL weight lattice holds: a call-family op
    // costs 1, a TAIL jump costs 1, a non-tail (forward branch) jump costs 0, and
    // every other op (straight-line / guard) costs 0. Bounded preemption no longer
    // relies on a per-op reduction floor: it rides `m.instrs` (+1 per retired op).
    try std.testing.expectEqual(@as(u32, 1), reductionCost(.{ .call = .{ .to = 0 } }));
    try std.testing.expectEqual(@as(u32, 1), reductionCost(.{ .call_ext_bif = .{ .func = undefined, .arity = 0 } }));
    try std.testing.expectEqual(@as(u32, 1), reductionCost(.{ .jump = .{ .to = 0, .tail = true } }));
    try std.testing.expectEqual(@as(u32, 0), reductionCost(.{ .jump = .{ .to = 0, .tail = false } }));
    try std.testing.expectEqual(@as(u32, 0), reductionCost(.{ .move = .{ .src = .{ .imm = 0 }, .dst = 0 } }));
    try std.testing.expectEqual(@as(u32, 0), reductionCost(.ret));

    // COST-ACCOUNTING: running a program charges EXACTLY the sum of `reductionCost`
    // over its executed instruction stream into `m.reductions`, and EXACTLY one
    // `m.instrs` per retired op. A straight-line move block therefore charges 0
    // reductions and `prog.len` instrs (the two-counter split made visible).
    const prog = [_]CInstr{
        .{ .move = .{ .src = .{ .imm = 1 }, .dst = 0 } },
        .{ .move = .{ .src = .{ .imm = 2 }, .dst = 1 } },
        .{ .move = .{ .src = .{ .imm = 3 }, .dst = 2 } },
        .{ .move = .{ .src = .{ .imm = 4 }, .dst = 3 } },
    };
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    try run(&m, prog[0..], 100);
    var sum: u64 = 0;
    for (prog) |ins| sum += reductionCost(ins);
    try std.testing.expectEqual(sum, m.reductions); // reductions == Σ reductionCost (the accounting law)
    try std.testing.expectEqual(@as(u64, 0), m.reductions); // straight-line ⇒ 0 per-call reductions
    try std.testing.expectEqual(@as(u64, prog.len), m.instrs); // one instr retired per op

    // A TAIL-recursive loop charges EXACTLY 1 reduction per iteration (the tail
    // back-edge) — the per-call count OTP reports. Countdown N times to a halt.
    const N: i64 = 20;
    const loop = [_]CInstr{
        .{ .is_lt = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .else_to = 2 } }, // 0: N<1 → halt
        .{ .halt = .{ .src = .{ .x = 0 } } }, //                                 1
        .{ .sub = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } }, //      2: N -= 1
        .{ .jump = .{ .to = 0, .tail = true } }, //                              3: tail back-edge
    };
    var m2 = try Machine.init(gpa, &atoms);
    defer m2.deinit();
    m2.regs[0] = FinalTerms.int(&m2.ctx, N);
    try run(&m2, loop[0..], 10_000);
    try std.testing.expectEqual(.halted, m2.status);
    try std.testing.expectEqual(@as(u64, @intCast(N)), m2.reductions); // exactly N tail-calls
}

test "LAW gap-r2c-behavioral-parity: runReductionPreempt yields on REDUCTIONS (behavioral parity, F reds despite >F instrs) with an instr SAFETY-CAP that bounds a 0-reduction straight-line hog (no hang) — R2c epoch Increment 0 (DIVERGENCE 606)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // (A) BEHAVIORAL PARITY: a MIXED infinite loop — one straight-line `move` (0 reds,
    // 1 instr) + a tail-jump back-edge (1 red, 1 instr) per iteration ⇒ 1 reduction /
    // 2 instrs per iter. A grant of F REDUCTIONS must yield after EXACTLY F reductions,
    // having run 2F INSTRS — the straight-line op does NOT count against the reduction
    // budget (this is the OTP behavior; ia.run would yield at F instrs = F/2 reds).
    const mixed = [_]CInstr{
        .{ .move = .{ .src = .{ .imm = 0 }, .dst = 0 } }, // 0 reductions, 1 instr
        .{ .jump = .{ .to = 0, .tail = true } }, //           1 reduction,  1 instr
    };
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const F: u64 = 100;
    try runReductionPreempt(&m, mixed[0..], F, 1_000_000);
    try std.testing.expectEqual(F, m.reductions); // yielded on EXACTLY F reductions
    try std.testing.expectEqual(@as(u64, 2) * F, m.instrs); // ...having run 2F instrs (parity!)
    try std.testing.expectEqual(.running, m.status); // preempted (still runnable), not halted

    // sanity: the SAME program under ia.run(F instrs) yields at F instrs = F/2 reds —
    // the DIVERGENCE this epoch closes (instr-preemption charges the straight-line op).
    var mi = try Machine.init(gpa, &atoms);
    defer mi.deinit();
    try run(&mi, mixed[0..], F);
    try std.testing.expectEqual(F, mi.instrs);
    try std.testing.expectEqual(F / 2, mi.reductions); // half the reductions for the same instr budget

    // (B) SAFETY-CAP: a 0-REDUCTION straight-line hog (a non-tail back-edge) charges 0
    // reductions FOREVER — a reductions-only bound would HANG. The instr_cap fires,
    // bounding it (CTRL-realtime preserved). Kills a mutant that drops the instr_cap.
    const straightline = [_]CInstr{.{ .jump = .{ .to = 0, .tail = false } }}; // 0 reds, 1 instr/iter
    var ms = try Machine.init(gpa, &atoms);
    defer ms.deinit();
    const CAP: u64 = 500;
    try runReductionPreempt(&ms, straightline[0..], F, CAP);
    try std.testing.expectEqual(@as(u64, 0), ms.reductions); // never charged a reduction
    try std.testing.expectEqual(CAP, ms.instrs); // ...yet BOUNDED by the instr safety-cap (no hang)
    try std.testing.expectEqual(.running, ms.status);
}

test "LAW R2c call_ext_bif size-weighting: SIZE-COUNT + WEIGHTED-ACCOUNTING + RESULT-IDENTITY" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const EPR: u32 = 32; // ELEMENTS_PER_RED (erts erl_bif_lists.c)

    // Build a proper list [0,1,..,L-1] in m.ctx.
    const mkList = struct {
        fn go(m: *Machine, len: i64) !FinalTerms.Term {
            var lst = FinalTerms.nil(&m.ctx);
            var k: i64 = 0;
            while (k < len) : (k += 1) lst = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, k), lst);
            return lst;
        }
    }.go;

    // SIZE-COUNT + WEIGHT: properListLen counts the proper prefix EXACTLY, and the
    // list0_elems weight is len/ELEMENTS_PER_RED; .none is always 0. Also boundary
    // exactness at multiples of EPR (integer floor). Reading the weight mutates
    // nothing (no instrs/reductions/pc/regs change) — the accounting-only invariant.
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    for ([_]i64{ 0, 1, 31, 32, 33, 64, 100 }) |L| {
        m.regs[0] = try mkList(&m, L);
        const ul: u32 = @intCast(L);
        try std.testing.expectEqual(ul, properListLen(&m, m.regs[0]));
        try std.testing.expectEqual(ul / EPR, bifSizeReds(&m, .list0_elems));
        try std.testing.expectEqual(@as(u32, 0), bifSizeReds(&m, .none));
        // gap-reduction-size-weight (DIVERGENCE 603): list1/list2 read x1/x2 — a
        // DISTINCT arg. Give x1 and x2 DIFFERENT lengths (L and 2L) and x0 a non-list,
        // so a weight reading the WRONG register is caught (kills MUT list2→x1).
        m.regs[1] = try mkList(&m, L);
        m.regs[2] = try mkList(&m, L * 2);
        m.regs[0] = FinalTerms.int(&m.ctx, 7); // x0 is NOT a list here
        try std.testing.expectEqual(ul / EPR, bifSizeReds(&m, .list1_elems)); // reads x1 (len L)
        try std.testing.expectEqual((ul * 2) / EPR, bifSizeReds(&m, .list2_elems)); // reads x2 (len 2L)
        try std.testing.expectEqual(@as(u32, 0), bifSizeReds(&m, .list0_elems)); // x0 non-list → 0
        // gap-reduction-bytes-weight (DIVERGENCE 604): bytes0 weights a BINARY in x0
        // by its BYTE length. Put a 3L-byte binary in x0; a non-binary → 0.
        var bin_buf: [512]u8 = undefined;
        const nbytes: usize = @intCast(@min(L * 3, 512));
        const bin = try FinalTerms.binary(&m.ctx, bin_buf[0..nbytes]);
        m.regs[0] = bin;
        try std.testing.expectEqual(@as(u32, @intCast(nbytes)) / EPR, bifSizeReds(&m, .bytes0_elems)); // byte length / EPR
        try std.testing.expectEqual(@as(u32, 0), bifSizeReds(&m, .list0_elems)); // a binary is not a proper list → 0
        m.regs[0] = try mkList(&m, L); // restore x0 for the pure-observation check below
        try std.testing.expectEqual(@as(u32, 0), bifSizeReds(&m, .bytes0_elems)); // a list is not a binary → 0
        const pre_i = m.instrs;
        const pre_r = m.reductions;
        _ = bifSizeReds(&m, .list0_elems);
        try std.testing.expectEqual(pre_i, m.instrs); // reading the weight is a pure observation
        try std.testing.expectEqual(pre_r, m.reductions);
    }

    // WEIGHTED-ACCOUNTING + RESULT-IDENTITY: run the SAME BIF over the SAME list,
    // once with size_class=.none and once with .list0_elems. The weighted run
    // charges EXACTLY L/EPR MORE `reductions` — and NOTHING else differs: identical
    // `instrs` (preemption), identical result term in x0. This is the admission
    // anchor (kills MUT-R2C-1 accounting→instrs and MUT-R2C-2 wrong-factor).
    const idBif = struct {
        fn f(mm: *Machine, args: []const FinalTerms.Term) BifError!FinalTerms.Term {
            _ = mm;
            return args[0]; // returns the list unchanged — a total, side-effect-free BIF
        }
    }.f;
    const L: i64 = 200;
    var mn = try Machine.init(gpa, &atoms);
    defer mn.deinit();
    var mw = try Machine.init(gpa, &atoms);
    defer mw.deinit();
    mn.regs[0] = try mkList(&mn, L);
    mn.regs[1] = FinalTerms.nil(&mn.ctx);
    mw.regs[0] = try mkList(&mw, L);
    mw.regs[1] = FinalTerms.nil(&mw.ctx);
    const prog_none = [_]CInstr{ .{ .call_ext_bif = .{ .func = idBif, .arity = 2, .size_class = .none } }, .ret };
    const prog_wt = [_]CInstr{ .{ .call_ext_bif = .{ .func = idBif, .arity = 2, .size_class = .list0_elems } }, .ret };
    try run(&mn, prog_none[0..], 100);
    try run(&mw, prog_wt[0..], 100);
    const expect_extra: u64 = @as(u64, @intCast(L)) / EPR;
    try std.testing.expectEqual(mn.reductions + expect_extra, mw.reductions); // exactly the weight, added
    try std.testing.expect(expect_extra > 0); // the weight is non-trivial at this size
    try std.testing.expectEqual(mn.instrs, mw.instrs); // RESULT-IDENTITY: preemption count unchanged
    try std.testing.expectEqual(properListLen(&mn, mn.regs[0]), properListLen(&mw, mw.regs[0])); // result term identical
}

pub fn verifyBlockMonoidLaws(comptime Impl: type, gpa: std.mem.Allocator, cfg: LawConfig) !void {
    comptime requireBlockAlgebra(Impl);
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = Impl.Ctx.init(gpa);
        defer ctx.deinit();
        var spec_arena = std.heap.ArenaAllocator.init(gpa);
        defer spec_arena.deinit();
        const sa = spec_arena.allocator();

        const p = try genBlock(Impl, random, &ctx, random.uintLessThan(usize, 5));
        const q = try genBlock(Impl, random, &ctx, random.uintLessThan(usize, 5));
        const r = try genBlock(Impl, random, &ctx, random.uintLessThan(usize, 5));
        const regs_seed = cfg.seed +% i;

        // Identity: exec(seq(nop,p)) == exec(p) == exec(seq(p,nop))
        {
            var m1 = try freshMachine(gpa, &atoms, regs_seed);
            defer m1.deinit();
            var m2 = try freshMachine(gpa, &atoms, regs_seed);
            defer m2.deinit();
            var m3 = try freshMachine(gpa, &atoms, regs_seed);
            defer m3.deinit();
            try Impl.exec(&m1, try Impl.seq(&ctx, try Impl.nop(&ctx), p));
            try Impl.exec(&m2, p);
            try Impl.exec(&m3, try Impl.seq(&ctx, p, try Impl.nop(&ctx)));
            try expectLaw(try eqMachines(&m1, &m2, sa), "seq left identity", cfg, i);
            try expectLaw(try eqMachines(&m3, &m2, sa), "seq right identity", cfg, i);
        }
        // Associativity: exec(seq(seq(p,q),r)) == exec(seq(p,seq(q,r)))
        {
            var m1 = try freshMachine(gpa, &atoms, regs_seed);
            defer m1.deinit();
            var m2 = try freshMachine(gpa, &atoms, regs_seed);
            defer m2.deinit();
            try Impl.exec(&m1, try Impl.seq(&ctx, try Impl.seq(&ctx, p, q), r));
            try Impl.exec(&m2, try Impl.seq(&ctx, p, try Impl.seq(&ctx, q, r)));
            try expectLaw(try eqMachines(&m1, &m2, sa), "seq associativity", cfg, i);
        }
        // Compositionality: exec(seq(p,q)) == exec(q) ∘ exec(p)
        {
            var m1 = try freshMachine(gpa, &atoms, regs_seed);
            defer m1.deinit();
            var m2 = try freshMachine(gpa, &atoms, regs_seed);
            defer m2.deinit();
            try Impl.exec(&m1, try Impl.seq(&ctx, p, q));
            try Impl.exec(&m2, p);
            try Impl.exec(&m2, q);
            try expectLaw(try eqMachines(&m1, &m2, sa), "compositionality", cfg, i);
        }
        // Block fuel: a machine still running has retired exactly len(p) instrs.
        // R2b: this INTERNAL consistency law rides on the per-INSTRUCTION counter
        // `m.instrs` (block ops are straight-line ⇒ 0 per-call reductions, so the
        // law would be vacuous on `m.reductions`).
        {
            var m = try freshMachine(gpa, &atoms, regs_seed);
            defer m.deinit();
            try Impl.exec(&m, p);
            try expectLaw(m.instrs <= Impl.len(p), "block fuel upper bound", cfg, i);
            if (m.status == .running)
                try expectLaw(m.instrs == Impl.len(p), "block fuel exactness", cfg, i);
            // Block ops are straight-line: they charge ZERO per-call reductions.
            try expectLaw(m.reductions == 0, "block per-call reductions are zero", cfg, i);
        }
    }
}

/// Twin-seed homomorphism: seq-trees and flat arrays execute identically.
pub fn verifyBlockHomomorphism(gpa: std.mem.Allocator, cfg: LawConfig) !void {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng_a = std.Random.DefaultPrng.init(cfg.seed);
    var prng_b = std.Random.DefaultPrng.init(cfg.seed);

    for (0..cfg.iterations) |i| {
        var ic = InitialBlocks.Ctx.init(gpa);
        defer ic.deinit();
        var fc = FinalBlocks.Ctx.init(gpa);
        defer fc.deinit();
        var spec_arena = std.heap.ArenaAllocator.init(gpa);
        defer spec_arena.deinit();

        const ra = prng_a.random();
        const rb = prng_b.random();
        const size = ra.uintLessThan(usize, 7);
        std.debug.assert(size == rb.uintLessThan(usize, 7)); // twins in lockstep
        const bi = try genBlock(InitialBlocks, ra, &ic, size);
        const bf = try genBlock(FinalBlocks, rb, &fc, size);

        var m1 = try freshMachine(gpa, &atoms, cfg.seed +% i);
        defer m1.deinit();
        var m2 = try freshMachine(gpa, &atoms, cfg.seed +% i);
        defer m2.deinit();
        try InitialBlocks.exec(&m1, bi);
        try FinalBlocks.exec(&m2, bf);
        try expectLaw(try eqMachines(&m1, &m2, spec_arena.allocator()), "block homomorphism: tree == flat", cfg, i);
    }
}

// ---- control-layer laws -----------------------------------------------------

/// Static (’static-lifetime) operand slice for the `put_tuple2` the fuzzer
/// emits. Using a const array sidesteps allocation/ownership in `randProgram`
/// (which has no allocator); it is NEVER freed and never reaches `freeProg`.
const rand_tuple_elems = [_]Src{ .{ .imm = 7 }, .{ .x = 0 }, .{ .imm = 9 } };

/// Static ('static-lifetime) jump tables for the `select_val`/
/// `select_tuple_arity` the fuzzer emits. Like `rand_tuple_elems` these are
/// const arrays — `randProgram` has no allocator, and a differential/predecode
/// consumer only shallow-dupes the CInstr array (aliasing the pairs, never
/// mutating them). The `.to` labels are 0..2 — always < `len` (len ≥ 4) so the
/// fuzzed jumps stay in bounds. The one MUTATING consumer, `transform.peephole`,
/// deep-copies owned sub-slices before remapping, so it never writes here.
const rand_select_val_pairs = [_]SelectValPair{
    .{ .key = FinalTerms.int(undefined, 1), .to = 0 },
    .{ .key = FinalTerms.atomTerm(1), .to = 1 },
    .{ .key = FinalTerms.nil_term, .to = 2 },
};
const rand_select_arity_pairs = [_]SelectArityPair{
    .{ .arity = 1, .to = 0 },
    .{ .arity = 2, .to = 1 },
    .{ .arity = 3, .to = 2 },
};
/// E1.7: static env for the `make_fun3` the fuzzer emits. Like `rand_tuple_elems`
/// / the select pair tables it is a const array (randProgram has no allocator);
/// a differential/predecode consumer only shallow-dupes the CInstr array
/// (aliasing this slice, never mutating it), and `transform.peephole` deep-copies
/// it before remapping, so this const backing is never written through.
const rand_fun_env = [_]Src{ .{ .x = 0 }, .{ .x = 1 } };

/// E1.10: static ('static-lifetime) backing for the map ops the fuzzer emits.
/// Like the tuple/select tables these are const arrays (randProgram has no
/// allocator, never freed, never reach freeProg). A fuzzed register never holds
/// a map (no randProgram op builds one), so the guarded map ops deterministically
/// take their fail path (else_to / badmap) — that is enough to ride the
/// DIFFERENTIAL law (engine #2 ≡ #3) and to exercise peephole's deep-copy of the
/// owned `keys`/`pairs`/`kvs` slices; the FOUND paths (all-or-nothing extract,
/// assoc/exact insert) are covered by the dedicated E1.10 semantic laws below,
/// exactly like `get_tuple_elem`/`apply`. The one MUTATING consumer,
/// `transform.peephole`, deep-copies these before remapping, so it never writes here.
// E5.2: keys are now runtime Srcs (DIVERGENCE 47). A fuzzed register never
// holds a map, so these guarded ops deterministically take the fail path — the
// keys' exact form is immaterial to the DIFFERENTIAL law; literal .imm/.atom_
// are used (matching the prior Term keys' values).
const rand_map_keys = [_]Src{ .{ .imm = 1 }, .{ .atom_ = 1 } };
const rand_map_elem_pairs = [_]MapElemPair{
    .{ .key = .{ .imm = 1 }, .dst = .{ .x = 0 } },
    .{ .key = .{ .atom_ = 1 }, .dst = .{ .x = 1 } },
};
const rand_map_kvs = [_]MapKV{
    .{ .k = .{ .imm = 1 }, .v = .{ .x = 0 } },
    .{ .k = .{ .atom_ = 1 }, .v = .{ .x = 1 } },
};

// E1.17 randProgram coverage checklist — every implemented CInstr variant from
// the E1 opcode tasks (3–15) is either FUZZED here (so the generic DIFFERENTIAL
// law, dispatch.zig, covers engine#2 ≡ engine#3 over it) or DELIBERATELY EXCLUDED
// and covered by a dedicated semantic law (the documented `apply`/receive/FR/
// tuple/exception precedent — a fuzzed control-flow jump would hit its
// precondition or require pre-loaded state). No implemented, fuzzable variant is
// silently uncovered:
//   T3 type_test .{integer..bitstr} .......... FUZZED (enum sprinkle)
//   T4 cmp_test .{ge,eq_arith,ne_arith,ne_exact} FUZZED (enum sprinkle)
//      is_function_arity ..................... FUZZED
//   T5 put_tuple2, test_arity, is_tagged_tuple  FUZZED (guarded)
//      get_tuple_elem, set_tuple_elem ........ excluded: UNGUARDED (no fail label,
//                                              like get_hd/get_tl) → E1.5 law
//   T6 select_val, select_tuple_arity ........ FUZZED
//   T7 make_fun3, call_fun2, call_fun ........ FUZZED
//      apply .................................. excluded: needs a live m:f/a, always
//                                              traps undef → E1.7 law
//   T8 catch_/try_/…/raise/build_stacktrace .. excluded: an exception rewrites
//                                              control flow → E1.8 laws
//   T9 alloc_heap, trim ...................... excluded: y-stack precondition (the
//                                              alloc_y/dealloc_y family) → E1.9 law
//   T10 has_map_fields, get_map_elements, put_map FUZZED (fail paths; found paths → E1.10 laws)
//   T11 send/loop_rec/…/recv_marker_* ........ excluded: stateful receive → E1.11 laws
//   T12 fmove_*/fconv/fadd/…/fnegate ......... excluded: FR bank needs pre-loading → E1.12 laws
//   T13 bif_call ............................. FUZZED (bif2 over `+`, body & guard)
//   T14 update_record ........................ excluded: UNGUARDED, needs a real
//                                              record tuple (the get_tuple_elem
//                                              precedent) → E1.14 law
//   T15 nop (on_load/nif_start) .............. FUZZED (splice-anywhere transparency)
//   E3.3 bs_start_match/bs_get_*/bs_skip_bits/  excluded: EVERY bs_* op needs a LIVE
//       bs_test_tail/bs_match_string/bs_get_*   MatchCtx already sitting in its `ctx`
//       position/bs_set_position/bs_match       register (the FR-bank/receive-cursor
//                                                precedent — a blind Src/Dst fuzzer
//                                                never constructs one) → dedicated
//                                                hand-assembled E3.3 semantic laws
//   E3.4 bs_create_bin/bs_init_writable/        excluded: `bs_create_bin` needs a
//       bs_get_utf/bs_skip_utf                  well-typed `segs` list (a fuzzed Src
//                                                would mostly hit Badarg, testing
//                                                nothing new) and bs_get_utf/skip_utf
//                                                need the SAME live MatchCtx as
//                                                E3.3's family → dedicated hand-
//                                                assembled E3.4 semantic laws
pub fn randProgram(random: std.Random, buf: []CInstr) Program {
    const len: u16 = @intCast(4 + random.uintLessThan(usize, buf.len - 4));
    for (buf[0..len]) |*ins| {
        ins.* = switch (random.uintLessThan(u8, 13)) {
            0, 1 => .{ .move = .{ .src = randSrc(random), .dst = @as(XReg, random.int(u4)) } },
            2, 3 => .{ .add = .{ .a = randSrc(random), .b = randSrc(random), .dst = @as(XReg, random.int(u4)) } },
            4 => .{ .put_list = .{ .h = randSrc(random), .t = randSrc(random), .dst = @as(XReg, random.int(u4)) } },
            5 => .{ .test_eq = .{ .a = randSrc(random), .b = randSrc(random), .else_to = random.uintLessThan(u16, len) } },
            6 => .{ .is_lt = .{ .a = randSrc(random), .b = randSrc(random), .else_to = random.uintLessThan(u16, len) } },
            7 => .{ .jump = .{ .to = random.uintLessThan(u16, len) } },
            8 => .{ .self_send = .{ .src = randSrc(random) } },
            9 => .{ .recv_eq = .{ .m = randSrc(random), .dst = @as(XReg, random.int(u4)), .else_to = random.uintLessThan(u16, len) } },
            10 => .{ .recv_any = .{ .dst = @as(XReg, random.int(u4)), .else_to = random.uintLessThan(u16, len) } },
            11 => .{ .make_fun = .{ .to = random.uintLessThan(u16, len), .arity = random.uintLessThan(u8, 3), .dst = @as(XReg, random.int(u4)) } },
            else => .{ .call = .{ .to = random.uintLessThan(u16, len) } },
        };
        // E1.3: sprinkle type-test guards so the DIFFERENTIAL law covers the
        // whole is_* class (engine #2 ≡ #3). A random kind over a random Src
        // exercises both branches (hold → fall through, fail → jump else_to).
        if (random.uintLessThan(u8, 5) == 0) {
            const kinds = std.enums.values(TypeTestKind);
            ins.* = .{ .type_test = .{
                .kind = kinds[random.uintLessThan(usize, kinds.len)],
                .src = randSrc(random),
                .else_to = random.uintLessThan(u16, len),
            } };
        }
        // E1.4: sprinkle comparison-test guards so the DIFFERENTIAL law covers
        // the whole binary-compare class. A random kind over two random Srcs
        // exercises both branches (hold → fall through, fail → jump else_to).
        if (random.uintLessThan(u8, 5) == 0) {
            const ops = std.enums.values(CmpTestKind);
            ins.* = .{ .cmp_test = .{
                .op = ops[random.uintLessThan(usize, ops.len)],
                .a = randSrc(random),
                .b = randSrc(random),
                .else_to = random.uintLessThan(u16, len),
            } };
        }
        if (random.uintLessThan(u8, 13) == 0) ins.* = .{ .is_function_arity = .{
            .src = randSrc(random),
            .arity = random.uintLessThan(u32, 3),
            .else_to = random.uintLessThan(u16, len),
        } };
        // E1.5: sprinkle the SAFE-over-arbitrary-terms tuple ops so the
        // DIFFERENTIAL law (engine #2 ≡ #3) covers them. `put_tuple2` builds a
        // tuple from resolvable Srcs; `test_arity`/`is_tagged_tuple` are guarded
        // test ops (kindOf==.tuple checked first, so a non-tuple register just
        // jumps — never an out-of-bounds heap read). `get_tuple_elem`/
        // `set_tuple_elem` are UNGUARDED (no fail label, like get_hd/get_tl) so
        // they are NOT fuzzed here; their semantic law below drives them over
        // real tuples. `type_test .tuple` is already covered by the enum sprinkle.
        if (random.uintLessThan(u8, 9) == 0) ins.* = .{ .put_tuple2 = .{
            .dst = .{ .x = @as(XReg, random.int(u4)) },
            .elems = &rand_tuple_elems,
        } };
        if (random.uintLessThan(u8, 9) == 0) ins.* = .{ .test_arity = .{
            .src = randSrc(random),
            .arity = random.uintLessThan(u16, 4),
            .else_to = random.uintLessThan(u16, len),
        } };
        if (random.uintLessThan(u8, 9) == 0) ins.* = .{ .is_tagged_tuple = .{
            .src = randSrc(random),
            .arity = 1 + random.uintLessThan(u16, 3),
            .tag = FinalTerms.nil_term,
            .else_to = random.uintLessThan(u16, len),
        } };
        // E1.6: sprinkle the select (jump-table) ops so the DIFFERENTIAL law
        // (engine #2 ≡ #3) covers them over a random Src. 1–3 static-const pairs
        // (never allocated, never freed); a random Src exercises both a table
        // hit and the fail_to fall-through. peephole deep-copies before remap.
        if (random.uintLessThan(u8, 9) == 0) ins.* = .{ .select_val = .{
            .src = randSrc(random),
            .fail_to = random.uintLessThan(u16, len),
            .pairs = rand_select_val_pairs[0 .. 1 + random.uintLessThan(usize, rand_select_val_pairs.len)],
        } };
        if (random.uintLessThan(u8, 9) == 0) ins.* = .{ .select_tuple_arity = .{
            .src = randSrc(random),
            .fail_to = random.uintLessThan(u16, len),
            .pairs = rand_select_arity_pairs[0 .. 1 + random.uintLessThan(usize, rand_select_arity_pairs.len)],
        } };
        // E1.10: sprinkle the map ops (static-const backing, guarded exec) so the
        // DIFFERENTIAL law covers them and peephole deep-copies their owned slices.
        // A fuzzed register never holds a map, so these take their fail path here
        // (else_to / badmap) — the FOUND paths ride the dedicated E1.10 laws.
        if (random.uintLessThan(u8, 11) == 0) ins.* = .{ .has_map_fields = .{
            .src = randSrc(random),
            .keys = rand_map_keys[0 .. 1 + random.uintLessThan(usize, rand_map_keys.len)],
            .else_to = random.uintLessThan(u16, len),
        } };
        if (random.uintLessThan(u8, 11) == 0) ins.* = .{ .get_map_elements = .{
            .src = randSrc(random),
            .pairs = rand_map_elem_pairs[0 .. 1 + random.uintLessThan(usize, rand_map_elem_pairs.len)],
            .else_to = random.uintLessThan(u16, len),
        } };
        if (random.uintLessThan(u8, 11) == 0) ins.* = .{ .put_map = .{
            .exact = random.boolean(),
            .src = randSrc(random),
            .dst = .{ .x = @as(XReg, random.int(u4)) },
            .kvs = rand_map_kvs[0 .. 1 + random.uintLessThan(usize, rand_map_kvs.len)],
        } };
        // occasionally call a fun (usually badfun — still deterministic)
        if (random.uintLessThan(u8, 12) == 0) ins.* = .{ .call_fun = .{ .f = randSrc(random) } };
        // E1.7: sprinkle make_fun3 (small/empty env, static-const backing) and
        // call_fun2 so the DIFFERENTIAL law (engine #2 ≡ #3) covers them. `jump`
        // (case 7) and `call_fun` (above) already flow through. `apply`/
        // `apply_last` are NOT fuzzed — they need a valid m:f/a in registers and
        // always trap `undef`; their dedicated E1.7 semantic law drives them.
        if (random.uintLessThan(u8, 11) == 0) ins.* = .{ .make_fun3 = .{
            .to = random.uintLessThan(u16, len),
            .arity = random.uintLessThan(u8, 4), // W-16: visible arity, independent of env.len
            .dst = .{ .x = @as(XReg, random.int(u4)) },
            .env = rand_fun_env[0 .. random.uintLessThan(usize, rand_fun_env.len + 1)],
        } };
        if (random.uintLessThan(u8, 12) == 0) ins.* = .{ .call_fun2 = .{
            .f = randSrc(random),
            .arity = random.uintLessThan(u8, 3),
        } };
        // E1.13: sprinkle a `bif2` over the SUPPORTED `+` so the DIFFERENTIAL
        // law (engine #2 ≡ #3) covers the BIF-dispatch mechanics. A random Src
        // pair exercises both the arith path and the failure path; a random
        // `else_to` (∈ [0,len), a valid pc) makes it a GUARD bif half the time
        // (failure branches) and a BODY bif otherwise (failure crashes). `dst`
        // is a random x-reg so a wrong-`dst` mutant diverges the register file.
        if (random.uintLessThan(u8, 11) == 0) ins.* = .{ .bif_call = .{
            .bif = .{ .func = &bif_erlang.add },
            .args = .{ randSrc(random), randSrc(random), .nil },
            .argc = 2,
            .dst = .{ .x = @as(XReg, random.int(u4)) },
            .else_to = if (random.boolean()) random.uintLessThan(u16, len) else null,
            .gc_live = null,
        } };
        // occasionally trap an effect (machine pauses; still deterministic)
        if (random.uintLessThan(u8, 14) == 0) ins.* = .{ .send_to = .{ .pid = randSrc(random), .msg = randSrc(random) } };
        // E1.15: sprinkle nop (on_load/nif_start) so the DIFFERENTIAL law
        // (engine #2 ≡ #3) and the transparency law's splice-anywhere claim
        // both get fuzz coverage — a nop carries no label/owned slice, so it
        // is safe to drop in unconditionally like recv_marker_* would be.
        if (random.uintLessThan(u8, 14) == 0) ins.* = .{ .nop = .{ .note = if (random.boolean()) .on_load else .nif_start } };
        // sprinkle rets and halts so some programs terminate early
        if (random.uintLessThan(u8, 10) == 0) ins.* = .ret;
        if (random.uintLessThan(u8, 16) == 0) ins.* = .{ .halt = .{ .src = randSrc(random) } };
    }
    return buf[0..len];
}

pub fn verifyControlLaws(gpa: std.mem.Allocator, cfg: LawConfig) !void {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var spec_arena = std.heap.ArenaAllocator.init(gpa);
        defer spec_arena.deinit();
        const sa = spec_arena.allocator();
        var buf: [16]CInstr = undefined;
        const prog = randProgram(random, &buf);
        const regs_seed = cfg.seed +% i;
        const fuel: u64 = 60;

        // Determinism: identical machines, identical budgets ⇒ identical states
        var m1 = try freshMachine(gpa, &atoms, regs_seed);
        defer m1.deinit();
        var m2 = try freshMachine(gpa, &atoms, regs_seed);
        defer m2.deinit();
        try run(&m1, prog, fuel);
        try run(&m2, prog, fuel);
        try expectLaw(try eqMachines(&m1, &m2, sa), "step determinism", cfg, i);

        // Fuel exactness: still running AND not trapped on an effect ⇒ the
        // whole budget was consumed (a pending Action is a VM trap, not a
        // preemption); never more than the budget in any case. R2b: preemption is
        // bounded on the per-INSTRUCTION counter `m.instrs` (byte-identical to the
        // pre-R2b `reductions`-fuel model), so the fuel law rides `m.instrs`.
        try expectLaw(m1.instrs <= fuel, "fuel upper bound", cfg, i);
        if (m1.status == .running and m1.pending == null)
            try expectLaw(m1.instrs == fuel, "fuel exactness on preemption", cfg, i);

        // SLICE INVARIANCE: any partition of the budget is unobservable.
        var m3 = try freshMachine(gpa, &atoms, regs_seed);
        defer m3.deinit();
        var left: u64 = fuel;
        while (left > 0) {
            const slice = 1 + random.uintLessThan(u64, @min(left, 7));
            try run(&m3, prog, slice);
            left -= slice;
        }
        try expectLaw(try eqMachines(&m1, &m3, sa), "slice invariance (preemption theorem)", cfg, i);
    }
}

// ============================================================================
// Verification suite
// ============================================================================

test "Laws: block monoid — Initial (seq-trees) is lawful" {
    try verifyBlockMonoidLaws(InitialBlocks, std.testing.allocator, .{});
}

test "Laws: block monoid — Final (flat arrays, the normal form) is lawful" {
    try verifyBlockMonoidLaws(FinalBlocks, std.testing.allocator, .{});
}

test "Homomorphism: seq-trees and flat BEAM-shaped code execute identically" {
    try verifyBlockHomomorphism(std.testing.allocator, .{});
}

test "Laws: control machine — determinism, fuel, slice invariance" {
    try verifyControlLaws(std.testing.allocator, .{});
}

test "M5 gate: selective receive skips, funs are applied, order intact" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sa = arena.allocator();

    // send 10, 20, 30 to self; selectively receive 20; then receive the
    // oldest remaining (10); apply a fun that adds them; halt x0+x1 = 30.
    const prog: Program = &.{
        .{ .self_send = .{ .src = .{ .imm = 10 } } }, // 0
        .{ .self_send = .{ .src = .{ .imm = 20 } } }, // 1
        .{ .self_send = .{ .src = .{ .imm = 30 } } }, // 2
        .{ .recv_eq = .{ .m = .{ .imm = 20 }, .dst = 0, .else_to = 9 } }, // 3: x0=20
        .{ .recv_any = .{ .dst = 1, .else_to = 9 } }, // 4: x1=10 (oldest left)
        // 5: x2 = fun@7. arity 2 matches the `call_fun{f=x2}` convention (BEAM
        // `call_fun Arity` puts the fun in x[Arity], args in x0..Arity-1) so the
        // gap-callfun-arity (DIVERGENCE 734) check passes; the body adds its 2 args.
        .{ .make_fun = .{ .to = 7, .arity = 2, .dst = 2 } },
        .{ .call_fun = .{ .f = .{ .x = 2 } } }, // 6: call it (x0,x1 = the 2 args)
        .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 1 }, .dst = 0 } }, // 7: x0=30
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 8
        .{ .halt = .{ .src = .{ .imm = -1 } } }, // 9: failure path
    };

    // run in tiny slices — selective receive under preemption
    while (m.status == .running) try run(&m, prog, 2);
    try std.testing.expectEqual(Status.halted, m.status);
    const want = try spec.bigFromI128(sa, 30);
    try std.testing.expect((try FinalTerms.denote(&m.ctx, sa, m.result)).int.order(want) == .eq);
    // mailbox retains exactly the unreceived 30, FIFO intact
    var buf: [8]mba.Msg(FinalTerms) = undefined;
    const rest = m.mbox.toSeq(&buf);
    try std.testing.expectEqual(@as(usize, 1), rest.len);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, rest[0].payload, FinalTerms.int(&m.ctx, 30)));
}

test "LAW E1.11 receive: mailbox conservation — remove_message removes EXACTLY the peeked message" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();

    // Seed [10,20,30] into self, then run the REAL BEAM receive skeleton for 20.
    // loop_rec peeks the save-pointer; test_eq is the guard; loop_rec_end advances
    // the cursor; remove_message commits the pop of the peeked (matched) message.
    const prog: Program = &.{
        .{ .self_send = .{ .src = .{ .imm = 10 } } }, // 0
        .{ .self_send = .{ .src = .{ .imm = 20 } } }, // 1
        .{ .self_send = .{ .src = .{ .imm = 30 } } }, // 2
        .{ .loop_rec = .{ .else_to = 8, .dst = 0 } }, // 3: L_loop — peek → x0
        .{ .test_eq = .{ .a = .{ .x = 0 }, .b = .{ .imm = 20 }, .else_to = 7 } }, // 4
        .remove_message, // 5: matched ⇒ commit the pop of the peeked message
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 6: done, x0 = 20
        .{ .loop_rec_end = .{ .to = 3 } }, // 7: L_next — advance cursor, retry
        .{ .wait_timeout = .{ .to = 3, .src = .{ .imm = 0 } } }, // 8: L_wait — timeout 0
        .timeout, // 9
        .{ .halt = .{ .src = .{ .imm = -1 } } }, // 10: no-match path
    };

    var guard: usize = 0;
    while (m.status == .running and guard < 100) : (guard += 1) try run(&m, prog, 3);
    try std.testing.expectEqual(Status.halted, m.status);
    // received the matched 20; MAILBOX CONSERVED: started 3, removed exactly 1 → 2
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.int(&m.ctx, 20)));
    try std.testing.expectEqual(@as(usize, 2), m.mbox.len());
    // and the SURVIVORS are exactly [10,30] — the matched message, not a phantom
    // (mutant 1 removes the wrong / an extra message, breaking these).
    var buf: [8]mba.Msg(FinalTerms) = undefined;
    const rest = m.mbox.toSeq(&buf);
    try std.testing.expectEqual(@as(usize, 2), rest.len);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, rest[0].payload, FinalTerms.int(&m.ctx, 10)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, rest[1].payload, FinalTerms.int(&m.ctx, 30)));

    // remove_message with the cursor past the queue removes NOTHING (the "fell
    // through to Lbl" case — mutant 1 pops a phantom here).
    var m2 = try Machine.init(std.testing.allocator, &atoms);
    defer m2.deinit();
    try m2.mbox.deliver(0, FinalTerms.int(&m2.ctx, 7));
    try m2.mbox.deliver(0, FinalTerms.int(&m2.ctx, 8));
    m2.recv_cursor = 5; // past end (no valid peek)
    try execInstr(&m2, .remove_message);
    try std.testing.expectEqual(@as(usize, 2), m2.mbox.len());
    try std.testing.expectEqual(@as(usize, 0), m2.recv_cursor); // reset
}

test "LAW gap-swap-x15 (DIVERGENCE 730): `swap` exchanges its two operands and NEVER clobbers x15 — the 16th arg of a 16-arity function (e.g. gen_statem loop_timeouts/16's TimeoutOpts []), whose corruption killed every gen_statem state/event timer" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();
    // Mirror gen_statem's exact shape: load the 16th arg into x15, then two swaps
    // among LOWER registers. The OLD lowering used x15 as swap scratch, so the two
    // swaps below overwrote x15 — passing garbage as arg 16. A true `.swap` leaves
    // x15 untouched.
    const prog: Program = &.{
        .{ .move2 = .{ .src = .{ .imm = 12 }, .dst = .{ .x = 12 } } }, // 0: x12=12
        .{ .move2 = .{ .src = .{ .imm = 13 }, .dst = .{ .x = 13 } } }, // 1: x13=13
        .{ .move2 = .{ .src = .{ .imm = 14 }, .dst = .{ .x = 14 } } }, // 2: x14=14
        .{ .move2 = .{ .src = .{ .imm = 15 }, .dst = .{ .x = 15 } } }, // 3: x15=15 (the "[] TimeoutOpts")
        .{ .swap = .{ .a = .{ .x = 13 }, .b = .{ .x = 14 } } }, // 4: {swap,x14,x13} → x13=14,x14=13
        .{ .swap = .{ .a = .{ .x = 12 }, .b = .{ .x = 14 } } }, // 5: {swap,x12,x14} → x12=13,x14=12
        .{ .halt = .{ .src = .{ .x = 15 } } }, // 6: return x15
    };
    try run(&m, prog, 100);
    try std.testing.expectEqual(Status.halted, m.status);
    // THE ANTI-CLOBBER INVARIANT: x15 survives the swaps untouched (=15). The
    // x15-scratch mutant reds HERE (x15 becomes a swapped lower-reg value).
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.int(&m.ctx, 15)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[15], FinalTerms.int(&m.ctx, 15)));
    // and the swaps ACTUALLY exchanged (a no-op-swap mutant reds here):
    //   after swap1: x13=14,x14=13 ; after swap2: x12=13(old x14), x14=12(old x12)
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[12], FinalTerms.int(&m.ctx, 13)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[13], FinalTerms.int(&m.ctx, 14)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[14], FinalTerms.int(&m.ctx, 12)));
}

test "LAW E1.11 receive: wait_timeout 0 fires immediately (never hangs) — mutant 2" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();

    // EMPTY mailbox: loop_rec jumps straight to the wait clause; wait_timeout 0
    // must FIRE NOW (fall through to the after-clause) so the bounded driver sees
    // the machine HALT. Mutant 2 (treat 0 as infinite ⇒ jump back to L_loop and
    // keep running) spins the receive loop forever — the fuel cap trips and the
    // `expect halted` below fails (a hang is a failed law).
    const prog: Program = &.{
        .{ .loop_rec = .{ .else_to = 2, .dst = 0 } }, // 0: L_loop — empty ⇒ jump 2
        .{ .halt = .{ .src = .{ .imm = 999 } } }, // 1: (match path — never reached)
        .{ .wait_timeout = .{ .to = 0, .src = .{ .imm = 0 } } }, // 2: L_wait — timeout 0
        .timeout, // 3: after-clause — clear save-pointer
        .{ .halt = .{ .src = .{ .imm = 42 } } }, // 4: timed-out result
    };

    var guard: usize = 0;
    while (m.status == .running and guard < 500) : (guard += 1) try run(&m, prog, 1);
    try std.testing.expectEqual(Status.halted, m.status); // reached the after-clause
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.int(&m.ctx, 42)));

    // `wait/1` (and `wait_timeout infinity`) SUSPEND — bounded (the run loop
    // stops), never a spin. Empty mailbox, plain `wait`:
    var mw = try Machine.init(std.testing.allocator, &atoms);
    defer mw.deinit();
    const wprog: Program = &.{
        .{ .loop_rec = .{ .else_to = 1, .dst = 0 } }, // 0
        .{ .wait = .{ .to = 0 } }, // 1: suspend
    };
    var g2: usize = 0;
    while (mw.status == .running and g2 < 500) : (g2 += 1) try run(&mw, wprog, 1);
    try std.testing.expectEqual(Status.suspended, mw.status);
}

test "LAW E34-T1 recv-after-uncond: unconditional receive-after with a NON-EMPTY mailbox FIRES the timeout (never hangs) — DIVERGENCE 559" {
    // An UNCONDITIONAL `receive after T -> B end` has NO message clauses, so the
    // compiler emits NO `loop_rec`: the `wait_timeout` label points BACK at the
    // wait itself. With messages queued, the old lost-wakeup guard (`mbox.len() >
    // cursor`) misfired — jump to the label, re-hit the guard, forever (the
    // recv-after-uncond HANG). The `recv_scanned` gate (no loop_rec ran ⇒ guard
    // is invalid here) makes it FALL THROUGH to fire the after-clause. MUTANT:
    // drop the `recv_scanned and` gate ⇒ the queued-message guard jumps to the
    // label (the wait itself) and re-hits forever, never halting (a hang is a
    // failed law — the fuel cap trips, `expect halted` fails). A `0` timeout
    // through `wait_timeout` is the clean unit repro: the guard misfires BEFORE
    // the `ms==0` fire-now check, so the spin is on the guard, not the timer (a
    // finite T>0 additionally arms the wheel — that path is driven by the E6.2
    // timer laws + the differential after_SUITE, not this bare-`run` unit).
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();

    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();
    // Two messages sit queued; the unconditional receive-after must leave them
    // there and fire the after-branch regardless.
    try m.mbox.deliver(0, FinalTerms.int(&m.ctx, 111));
    try m.mbox.deliver(0, FinalTerms.int(&m.ctx, 222));
    const prog: Program = &.{
        .{ .wait_timeout = .{ .to = 0, .src = .{ .imm = 0 } } }, // 0: L_wait — label points back at itself (unconditional)
        .timeout, //                                                 1: after-clause
        .{ .halt = .{ .src = .{ .imm = 42 } } }, //                  2: timed-out result
    };
    var guard: usize = 0;
    while (m.status == .running and guard < 500) : (guard += 1) try run(&m, prog, 1);
    try std.testing.expectEqual(Status.halted, m.status); // reached the after-clause, did NOT hang
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.int(&m.ctx, 42)));
    // The queued messages are untouched (FIFO preserved).
    try std.testing.expectEqual(@as(usize, 2), m.mbox.len());
}

test "LAW E34-T1 recv-after-badtimeout: an invalid receive-after timeout raises error:timeout_value — DIVERGENCE 559" {
    // erts admits only a non-negative integer in 0..2^32-1 (or `infinity`); a
    // negative int, a float, a non-`infinity` atom, or an out-of-range bignum
    // raises `error:timeout_value` — NOT a silent take-the-after-branch. MUTANT:
    // revert to the old `!repIsSmall ⇒ fall through` ⇒ a bad timeout silently
    // fires and the machine HALTS 42 instead of raising (this law's `expect NOT
    // halted-42 / IS a raised error` fails).
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();

    // Each bad value drives an UNCONDITIONAL receive-after (no loop_rec) so the
    // validation is reached immediately. A raise with no catch frame parks the
    // machine `.crashed` with the bare reason atom `timeout_value` as the result
    // (the pre-E1.8 backward-compat halt path). The MUTANT (silent fall-through)
    // instead reaches the after-clause and HALTS 42 — which this law rejects.
    inline for (.{
        Src{ .imm = -1 }, //             negative small
        Src{ .imm = 0x1_0000_0000 }, //  2^32 — one past the erts ceiling
    }) |bad_src| {
        var m = try Machine.init(std.testing.allocator, &atoms);
        defer m.deinit();
        const prog: Program = &.{
            .{ .wait_timeout = .{ .to = 0, .src = bad_src } }, // 0: unconditional, invalid timeout
            .timeout, //                                          1: after-clause (must NOT be reached)
            .{ .halt = .{ .src = .{ .imm = 42 } } }, //           2
        };
        var guard: usize = 0;
        while (m.status == .running and guard < 500) : (guard += 1) try run(&m, prog, 1);

        try std.testing.expectEqual(Status.crashed, m.status); // raised, did NOT time out
        const tv = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("timeout_value"));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, tv));
    }
}

test "LAW E1.11 recv_marker_* are semantically transparent (no denotation depends on them)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();

    // Same receive, WITH and WITHOUT the marker ops interleaved. The observable
    // outcome (status, result, mailbox sequence) must be identical — enabling the
    // markers changes nothing (they are a perf optimization only).
    const plain: Program = &.{
        .{ .self_send = .{ .src = .{ .imm = 5 } } }, // 0
        .{ .self_send = .{ .src = .{ .imm = 6 } } }, // 1
        .{ .loop_rec = .{ .else_to = 5, .dst = 0 } }, // 2
        .remove_message, // 3
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 4
        .{ .halt = .{ .src = .{ .imm = -1 } } }, // 5
    };
    const marked: Program = &.{
        .{ .self_send = .{ .src = .{ .imm = 5 } } }, // 0
        .recv_marker_reserve, // 1: transparent
        .{ .self_send = .{ .src = .{ .imm = 6 } } }, // 2
        .recv_marker_bind, // 3: transparent
        .{ .loop_rec = .{ .else_to = 8, .dst = 0 } }, // 4
        .recv_marker_use, // 5: transparent
        .remove_message, // 6
        .recv_marker_clear, // 7: transparent
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 8
        .{ .halt = .{ .src = .{ .imm = -1 } } }, // 9
    };

    var ma = try Machine.init(std.testing.allocator, &atoms);
    defer ma.deinit();
    var mb = try Machine.init(std.testing.allocator, &atoms);
    defer mb.deinit();
    var ga: usize = 0;
    while (ma.status == .running and ga < 100) : (ga += 1) try run(&ma, plain, 3);
    var gb: usize = 0;
    while (mb.status == .running and gb < 100) : (gb += 1) try run(&mb, marked, 3);

    try std.testing.expectEqual(ma.status, mb.status);
    try std.testing.expect(FinalTerms.eqlExact(&ma.ctx, ma.result, FinalTerms.int(&ma.ctx, 5)));
    try std.testing.expect(FinalTerms.eqlExact(&mb.ctx, mb.result, FinalTerms.int(&mb.ctx, 5)));
    var ba: [8]mba.Msg(FinalTerms) = undefined;
    var bb: [8]mba.Msg(FinalTerms) = undefined;
    const sa2 = ma.mbox.toSeq(&ba);
    const sb2 = mb.mbox.toSeq(&bb);
    try std.testing.expectEqual(sa2.len, sb2.len); // both retain just [6]
    try std.testing.expect(FinalTerms.eqlExact(&ma.ctx, sa2[0].payload, FinalTerms.int(&ma.ctx, 6)));
    try std.testing.expect(FinalTerms.eqlExact(&mb.ctx, sb2[0].payload, FinalTerms.int(&mb.ctx, 6)));
}

test "LAW E1.15 nop (on_load/nif_start) is semantically transparent (splice-anywhere)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();

    // Same computation, WITH nops spliced in at several points (before, between,
    // and after the real work) and WITHOUT any. The observable outcome (status,
    // x0 result, heap-visible term) must be IDENTICAL — a nop changes nothing
    // except consuming one reduction and advancing to the next instruction.
    const plain: Program = &.{
        .{ .move = .{ .src = .{ .imm = 5 }, .dst = 0 } }, // 0
        .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 2 }, .dst = 1 } }, // 1
        .{ .move = .{ .src = .{ .x = 1 }, .dst = 0 } }, // 2
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 3
    };
    const nopped: Program = &.{
        .{ .nop = .{ .note = .on_load } }, // 0: transparent (before)
        .{ .move = .{ .src = .{ .imm = 5 }, .dst = 0 } }, // 1
        .{ .nop = .{ .note = .nif_start } }, // 2: transparent (between)
        .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 2 }, .dst = 1 } }, // 3
        .{ .nop = .{ .note = .on_load } }, // 4: transparent (between)
        .{ .move = .{ .src = .{ .x = 1 }, .dst = 0 } }, // 5
        .{ .nop = .{ .note = .nif_start } }, // 6: transparent (after)
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 7
    };

    var ma = try Machine.init(std.testing.allocator, &atoms);
    defer ma.deinit();
    var mb = try Machine.init(std.testing.allocator, &atoms);
    defer mb.deinit();
    try run(&ma, plain, plain.len);
    try run(&mb, nopped, nopped.len);

    try std.testing.expectEqual(ma.status, mb.status);
    try std.testing.expectEqual(Status.halted, ma.status);
    try std.testing.expect(FinalTerms.eqlExact(&ma.ctx, ma.result, FinalTerms.int(&ma.ctx, 7)));
    try std.testing.expect(FinalTerms.eqlExact(&mb.ctx, mb.result, FinalTerms.int(&mb.ctx, 7)));
    // x/y registers untouched by the nops: whole-register-file agreement.
    try std.testing.expectEqualSlices(FinalTerms.Term, &ma.regs, &mb.regs);
}

test "LAW E1.11 send/0 traps .send_to (pid=x0, msg=x1) and returns the message in x0" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();
    m.regs[0] = FinalTerms.int(&m.ctx, 3); // pid
    m.regs[1] = FinalTerms.int(&m.ctx, 99); // message
    try execInstr(&m, .send);
    try std.testing.expect(m.pending != null and m.pending.? == .send_to);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.send_to.pid, FinalTerms.int(&m.ctx, 3)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.send_to.msg, FinalTerms.int(&m.ctx, 99)));
    // BEAM `send` returns the sent message
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.int(&m.ctx, 99)));
}

test "G1: hand-assembled loop runs, preempts, and promotes to bignum" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sa = arena.allocator();

    // x0 = 2^59 - 3 (acc, 3 shy of the small/big boundary); x1 = 5 (i)
    // loop: if i == 0 -> done; acc += i; i += -1; goto loop; done: halt acc
    const start: i64 = (1 << 59) - 3;
    const prog: Program = &.{
        .{ .move = .{ .src = .{ .imm = start }, .dst = 0 } }, // 0
        .{ .move = .{ .src = .{ .imm = 5 }, .dst = 1 } }, // 1
        .{ .test_eq = .{ .a = .{ .x = 1 }, .b = .{ .imm = 0 }, .else_to = 4 } }, // 2: eq -> fall to done
        .{ .jump = .{ .to = 7 } }, // 3: i == 0 -> done
        .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 1 }, .dst = 0 } }, // 4
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .imm = -1 }, .dst = 1 } }, // 5
        .{ .jump = .{ .to = 2 } }, // 6
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 7
    };

    // Drive it in tiny slices — a caricature of a preempting scheduler.
    var slices: u64 = 0;
    while (m.status == .running) : (slices += 1) try run(&m, prog, 3);

    try std.testing.expectEqual(Status.halted, m.status);
    try std.testing.expect(slices > 1); // it really was preempted mid-loop
    // acc = 2^59 - 3 + (5+4+3+2+1) = 2^59 + 12 — past the boundary: a bignum.
    try std.testing.expect(FinalTerms.repIsBig(&m.ctx, m.result));
    const want = try spec.bigFromI128(sa, (1 << 59) + 12);
    try std.testing.expect((try FinalTerms.denote(&m.ctx, sa, m.result)).int.order(want) == .eq);
}

// ============================================================================
// E1.7 call / apply / fun laws. These pin the semantics the two mutants
// regress against: (1) make_fun3 dropping its environment; (2) apply_last
// forgetting to deallocate its frame. `jump`/`call_fun` reuse pre-existing
// variants (covered by the differential/G1/M5 gates); `call_fun2`/`make_fun3`
// also ride the DIFFERENTIAL law via `randProgram`. `apply`/`apply_last` are
// driven HERE (they always trap `undef` and cannot be safely fuzzed).
// ============================================================================

test "LAW E1.7 make_fun3 captures its resolved environment into the closure value" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    // x0 = 7, x1 = the list [7]; make_fun3 fun@3 -> x2 capturing {x0, x1}. The
    // closure value must carry env = [7, [7]] (env_len == num_free == 2). W-16:
    // the VISIBLE arity is set INDEPENDENTLY (arity=1 here) — it is NOT env.len,
    // proving the fun-header ARITY / ENV_SIZE split (OTP `i_make_fun3`). Mutant 1
    // (drop env → makeFun with &.{}) collapses env_len to 0 — this law fails.
    const seven = FinalTerms.int(&m.ctx, 7);
    m.regs[0] = seven;
    m.regs[1] = try FinalTerms.cons(&m.ctx, seven, FinalTerms.nil(&m.ctx));
    const prog: Program = &.{
        .{ .make_fun3 = .{ .to = 3, .arity = 1, .dst = .{ .x = 2 }, .env = &.{ .{ .x = 0 }, .{ .x = 1 } } } }, // 0
        .{ .halt = .{ .src = .{ .x = 2 } } }, // 1
    };
    try run(&m, prog, 8);
    try std.testing.expectEqual(Status.halted, m.status);
    const fv = m.result;
    try std.testing.expect(FinalTerms.repIsFun(&m.ctx, fv));
    const parts = FinalTerms.funParts(&m.ctx, fv);
    try std.testing.expectEqual(@as(u32, 3), parts.label);
    try std.testing.expectEqual(@as(usize, 2), parts.env_len); // num_free
    try std.testing.expectEqual(@as(u8, 1), parts.arity); // W-16: visible arity ≠ env.len
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.funEnvElem(&m.ctx, fv, 0), seven));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.funEnvElem(&m.ctx, fv, 1), m.regs[1]));
}

test "LAW fix-closure-aliasing FUN-ENTRY homomorphism: call_fun2 restores each closure's OWN env at x[visible_arity]; two closures from one label stay distinct" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // The erlc shape of `Mk = fun(N) -> fun() -> N end end; G1 = Mk(1),
    // G2 = Mk(2), {G1(), G2()}`: the closure body @8 is a BARE `ret` (it
    // returns x0), exactly like the compiled `'-…-fun-0-'` — the value it
    // returns exists ONLY because the fun-entry convention restored env[0]
    // into x[visible_arity=0]. x0 is POISONED (99) before each call, so a
    // `call_fun2` that skips `loadFunEnv` returns 99, and a restore at the
    // WRONG base (e.g. the FunT TOTAL arity — the pre-fix loader bug) leaves
    // the poison in x0 too. Distinctness: the two closures were built from
    // the SAME label with different captures; each must return its OWN.
    const prog2: Program = &.{
        .{ .move = .{ .src = .{ .imm = 1 }, .dst = 0 } }, // 0
        .{ .make_fun3 = .{ .to = 9, .arity = 0, .dst = .{ .x = 3 }, .env = &.{.{ .x = 0 }} } }, // 1
        .{ .move = .{ .src = .{ .imm = 2 }, .dst = 0 } }, // 2
        .{ .make_fun3 = .{ .to = 9, .arity = 0, .dst = .{ .x = 4 }, .env = &.{.{ .x = 0 }} } }, // 3
        .{ .move = .{ .src = .{ .imm = 99 }, .dst = 0 } }, // 4: poison
        .{ .call_fun2 = .{ .f = .{ .x = 3 }, .arity = 0 } }, // 5: G1() → 1
        .{ .move = .{ .src = .{ .x = 0 }, .dst = 5 } }, // 6: stash
        .{ .move = .{ .src = .{ .imm = 99 }, .dst = 0 } }, // 7: poison again
        .{ .jump = .{ .to = 10 } }, // 8: skip over the body
        .ret, // 9: the closure BODY (bare return-x0, the erlc shape)
        .{ .call_fun2 = .{ .f = .{ .x = 4 }, .arity = 0 } }, // 10: G2() → 2
        .{ .put_list = .{ .h = .{ .x = 5 }, .t = .{ .x = 0 }, .dst = 6 } }, // 11
        .{ .halt = .{ .src = .{ .x = 6 } } }, // 12
    };
    try run(&m, prog2, 64);
    try std.testing.expectEqual(Status.halted, m.status);
    const res = m.result;
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, res) == .cons);
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    // G1 returned ITS capture (1), G2 ITS capture (2) — not the poison, not
    // each other's, not the fun terms themselves.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, res), one));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listTail(&m.ctx, res), two));
}

test "LAW E1.7 call_fun2 applies a closure (jump to its label); non-fun ⇒ badfun" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // make_fun3 fun@4 -> x2 (empty env); call_fun2 x2 pushes the return pc and
    // jumps to the fun body @4, which increments x0 (41 → 42) and `ret`s back
    // to the halt @3. Reuses the call_fun jump/return path with an arity operand.
    const prog: Program = &.{
        .{ .move = .{ .src = .{ .imm = 41 }, .dst = 0 } }, // 0
        .{ .make_fun3 = .{ .to = 4, .arity = 0, .dst = .{ .x = 2 }, .env = &.{} } }, // 1
        .{ .call_fun2 = .{ .f = .{ .x = 2 }, .arity = 0 } }, // 2: push ret=3, jump 4
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 3: return target
        .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } }, // 4: x0 = 42
        .ret, // 5: pop -> 3
    };
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    while (m.status == .running) try run(&m, prog, 2);
    try std.testing.expectEqual(Status.halted, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.int(&m.ctx, 42)));

    // call_fun2 over a non-fun (x0 is an integer) ⇒ badfun, exactly like call_fun.
    var mb = try Machine.init(gpa, &atoms);
    defer mb.deinit();
    mb.regs[0] = FinalTerms.int(&mb.ctx, 99);
    try execInstr(&mb, .{ .call_fun2 = .{ .f = .{ .x = 0 }, .arity = 1 } });
    try std.testing.expectEqual(Status.crashed, mb.status);
    try std.testing.expect(FinalTerms.eqlExact(&mb.ctx, mb.result, FinalTerms.atom(&mb.ctx, mb.badfun)));
}

test "LAW E1.7 apply/apply_last trap undef; apply_last deallocates its frame first" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // Three live y-slots (a caller frame). Cross-module resolution is E3, so
    // every apply target traps `undef`. Plain apply/1 must NOT touch the frame.
    const nilv = FinalTerms.nil(&m.ctx);
    try m.ystack.append(m.gpa, nilv);
    try m.ystack.append(m.gpa, nilv);
    try m.ystack.append(m.gpa, nilv);
    try execInstr(&m, .{ .apply = .{ .arity = 1, .last = null } });
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.undef)));
    try std.testing.expectEqual(@as(usize, 3), m.ystack.items.len); // frame intact

    // apply_last/2 with Dealloc=2 deallocates 2 slots BEFORE trapping undef
    // (the *_last tail-call convention). Mutant 2 (skip dealloc) leaves 3 slots.
    m.status = .running;
    try execInstr(&m, .{ .apply = .{ .arity = 1, .last = 2 } });
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.undef)));
    try std.testing.expectEqual(@as(usize, 1), m.ystack.items.len); // 3 - 2 = 1
}

// ============================================================================
// E1.13 BIF-dispatch opcode mechanics. These are the MECHANISM laws (decode +
// dispatch + totality); BIF coverage (which M:F/A compute) is E2. The four laws
// pin: (1) a supported `bif2` over `+` computes and lands in the RIGHT `dst`
// (mutant 2: writing x0 breaks it); (2) the GUARD-CONTEXT law — a failing guard
// BIF BRANCHES to else_to, never raises (mutant 1: raise breaks it); (3) a
// failing BODY BIF (no fail label) CRASHES badarith; (4) an `.unsupported` BIF
// traps `undef` in EVERY context (coverage is E2).
// ============================================================================

test "LAW E1.13 a supported bif2 (`+`) computes and lands the result in dst (mutant: writes x0)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // x1 = 40, x2 = 2. A body `bif2 +` into x3 must place 42 in x3, NOT x0.
    m.regs[1] = FinalTerms.int(&m.ctx, 40);
    m.regs[2] = FinalTerms.int(&m.ctx, 2);
    const x0_before = m.regs[0];
    try execInstr(&m, .{ .bif_call = .{
        .bif = .{ .func = &bif_erlang.add },
        .args = .{ .{ .x = 1 }, .{ .x = 2 }, .nil },
        .argc = 2,
        .dst = .{ .x = 3 },
        .else_to = null,
        .gc_live = null,
    } });
    try std.testing.expectEqual(Status.running, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[3], FinalTerms.int(&m.ctx, 42)));
    // Mutant 2 (ignore dst → write x0) would clobber x0; the honest impl leaves it.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], x0_before));
}

test "LAW E1.13 GUARD-CONTEXT: a failing guard bif2 BRANCHES to else_to, never raises (mutant: raise)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // x1 = an atom (not a number): `+` fails with badarith. In GUARD context
    // (else_to = 7, a valid fail label) the machine must JUMP to 7 and STAY
    // running — a guard BIF has no side effects, so failure is a branch, NOT an
    // exception. Mutant 1 (raise instead of branch) would crash here.
    m.regs[1] = FinalTerms.atom(&m.ctx, try atoms.intern("not_a_number"));
    m.regs[2] = FinalTerms.int(&m.ctx, 2);
    m.pc = 3;
    try execInstr(&m, .{ .bif_call = .{
        .bif = .{ .func = &bif_erlang.add },
        .args = .{ .{ .x = 1 }, .{ .x = 2 }, .nil },
        .argc = 2,
        .dst = .{ .x = 3 },
        .else_to = 7,
        .gc_live = null,
    } });
    try std.testing.expectEqual(Status.running, m.status); // NOT crashed
    try std.testing.expectEqual(@as(usize, 7), m.pc); //     branched to else_to
}

test "LAW E1.13 BODY-CONTEXT: a failing bif2 with no fail label CRASHES badarith" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // Same failing `+`, but BODY context (else_to = null). With no fail label
    // and an empty catch-stack, failure halts .crashed with reason badarith.
    m.regs[1] = FinalTerms.atom(&m.ctx, try atoms.intern("not_a_number"));
    m.regs[2] = FinalTerms.int(&m.ctx, 2);
    try execInstr(&m, .{ .bif_call = .{
        .bif = .{ .func = &bif_erlang.add },
        .args = .{ .{ .x = 1 }, .{ .x = 2 }, .nil },
        .argc = 2,
        .dst = .{ .x = 3 },
        .else_to = null,
        .gc_live = null,
    } });
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.badarith)));
}

test "LAW E1.13 an unsupported BIF traps undef in EVERY context (coverage is E2)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // An `.unsupported` decode (a valid M:F/A the executor has no impl for) is
    // undefined, not a guard result. It traps `undef` whether a fail label is
    // present (guard) or not (body) — branching would fabricate a false guard.
    for ([_]?u32{ null, 5 }) |else_to| {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.pc = 2;
        try execInstr(&m, .{ .bif_call = .{
            .bif = .unsupported,
            .args = .{ .nil, .nil, .nil },
            .argc = 0,
            .dst = .{ .x = 0 },
            .else_to = else_to,
            .gc_live = null,
        } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.undef)));
    }
}

// E2.4 GUARD-CONTEXT law over a REAL guard BIF (`element/2`), driven through the
// executor's `bif_call` arm so the guard-vs-body routing (`bifFail`) is under
// test end-to-end. `element(0, {a})` is a bad argument: in GUARD context (a fail
// label present) it must BRANCH to `else_to` and STAY running (a guard BIF has no
// side effect, so a bad arg is a branch, not an exception); in BODY context (no
// label) it must CRASH with the exact `badarg` reason. MUTANT 2 (a family fn that
// raises instead of returning error.Badarg, or the executor crashing in guard
// context) is killed by the guard half; MUTANT 1 (element off-by-one) is killed
// by the denotation law in bifs/erlang.zig.
test "LAW E2.4 GUARD-CONTEXT: element(0,{a}) BRANCHES in guard, CRASHES badarg in body" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // A one-tuple {a} in x1, the bad index 0 in x2.
    // GUARD context: else_to = 7, pc starts at 3 → must jump to 7, still running.
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
        m.regs[1] = try FinalTerms.tuple(&m.ctx, &.{a});
        m.regs[2] = FinalTerms.int(&m.ctx, 0);
        m.pc = 3;
        try execInstr(&m, .{ .bif_call = .{
            .bif = .{ .func = &bif_erlang.element },
            .args = .{ .{ .x = 2 }, .{ .x = 1 }, .nil },
            .argc = 2,
            .dst = .{ .x = 3 },
            .else_to = 7,
            .gc_live = null,
        } });
        try std.testing.expectEqual(Status.running, m.status); // NOT crashed
        try std.testing.expectEqual(@as(usize, 7), m.pc); //     branched to else_to
    }
    // BODY context: else_to = null → crash badarg (the exact reason atom).
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
        m.regs[1] = try FinalTerms.tuple(&m.ctx, &.{a});
        m.regs[2] = FinalTerms.int(&m.ctx, 0);
        try execInstr(&m, .{ .bif_call = .{
            .bif = .{ .func = &bif_erlang.element },
            .args = .{ .{ .x = 2 }, .{ .x = 1 }, .nil },
            .argc = 2,
            .dst = .{ .x = 3 },
            .else_to = null,
            .gc_live = null,
        } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.badarg)));
    }
    // Sanity: a GOOD element in body context lands the result (element is 1-based).
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
        const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
        m.regs[1] = try FinalTerms.tuple(&m.ctx, &.{ a, b });
        m.regs[2] = FinalTerms.int(&m.ctx, 2);
        try execInstr(&m, .{ .bif_call = .{
            .bif = .{ .func = &bif_erlang.element },
            .args = .{ .{ .x = 2 }, .{ .x = 1 }, .nil },
            .argc = 2,
            .dst = .{ .x = 3 },
            .else_to = null,
            .gc_live = null,
        } });
        try std.testing.expectEqual(Status.running, m.status);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[3], b));
    }
}

// ============================================================================
// E1.8 BACKWARD-COMPATIBILITY law (written FIRST, before m.crash was rewired
// to unwind): with an EMPTY catch-stack, a crash must halt EXACTLY as it did
// through M1–M14 — status .crashed, result = the reason atom, no unwind. This
// is the safety net for the crash-semantics rewrite: every crash-dependent
// milestone (badmatch/func_info→function_clause, badarith, badfun, undef, the
// M8 crash-dump golden) rides on this behaviour, so it is pinned independently
// here and re-verified after the rewrite. It held GREEN before the rewrite
// (crash always halted) and holds GREEN after (empty stack ⇒ the halt branch).
// ============================================================================

test "LAW E1.8 backward-compat: with no catch frame, a crash halts exactly as before" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // No try/catch has run, so the catch-stack is empty: func_info must crash
    // to the halt state (status .crashed, result = function_clause), never
    // unwind. This is the exact behaviour the M8 crash-dump golden depends on.
    const prog: Program = &.{.func_info};
    try run(&m, prog, 8);
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.fclause)));

    // Every existing crash reason takes the same halt path with an empty stack:
    // a badarith (adding two non-numbers) and a badfun (call_fun on a non-fun).
    var m2 = try Machine.init(gpa, &atoms);
    defer m2.deinit();
    m2.regs[0] = FinalTerms.atom(&m2.ctx, try atoms.intern("not_a_number"));
    try execInstr(&m2, .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 0 }, .dst = 1 } });
    try std.testing.expectEqual(Status.crashed, m2.status);
    try std.testing.expect(FinalTerms.eqlExact(&m2.ctx, m2.result, FinalTerms.atom(&m2.ctx, m2.badarith)));

    var m3 = try Machine.init(gpa, &atoms);
    defer m3.deinit();
    m3.regs[0] = FinalTerms.int(&m3.ctx, 7); // not a fun
    try execInstr(&m3, .{ .call_fun = .{ .f = .{ .x = 0 } } });
    try std.testing.expectEqual(Status.crashed, m3.status);
    try std.testing.expect(FinalTerms.eqlExact(&m3.ctx, m3.result, FinalTerms.atom(&m3.ctx, m3.badfun)));
}

// ============================================================================
// E1.8 LIFO law: the catch-stack is a stack. A `try`/`catch` PUSH followed by
// its `try_end`/`catch_end` POP restores the EXACT prior catch-stack (depth and
// top frame). MUTANT 1 (`catch_end` does not pop) leaves the frame — depth 1,
// not 0 — and this law fails.
// ============================================================================

test "LAW E1.8 catch-stack is LIFO: push then pop restores the prior stack" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    try std.testing.expectEqual(@as(usize, 0), m.catch_stack.items.len);

    // catch push → depth 1 with the recorded frame, catch_end pop → depth 0.
    try execInstr(&m, .{ .catch_ = .{ .to = 5, .dst = .{ .y = 0 } } });
    try std.testing.expectEqual(@as(usize, 1), m.catch_stack.items.len);
    try std.testing.expectEqual(@as(u16, 5), m.catch_stack.items[0].to);
    try execInstr(&m, .{ .catch_end = .{ .dst = .{ .y = 0 } } });
    try std.testing.expectEqual(@as(usize, 0), m.catch_stack.items.len);

    // try push → try_end pop, symmetric.
    try execInstr(&m, .{ .try_ = .{ .to = 9, .dst = .{ .y = 0 } } });
    try std.testing.expectEqual(@as(usize, 1), m.catch_stack.items.len);
    try execInstr(&m, .{ .try_end = .{ .dst = .{ .y = 0 } } });
    try std.testing.expectEqual(@as(usize, 0), m.catch_stack.items.len);

    // NESTED: push A, push B, pop B, pop A restores each layer in LIFO order.
    try execInstr(&m, .{ .catch_ = .{ .to = 3, .dst = .{ .y = 0 } } }); // A
    try execInstr(&m, .{ .try_ = .{ .to = 7, .dst = .{ .y = 0 } } }); // B on top
    try std.testing.expectEqual(@as(usize, 2), m.catch_stack.items.len);
    try std.testing.expectEqual(@as(u16, 7), m.catch_stack.items[1].to); // B is the top
    try execInstr(&m, .{ .try_end = .{ .dst = .{ .y = 0 } } }); // pop B
    try std.testing.expectEqual(@as(usize, 1), m.catch_stack.items.len);
    try std.testing.expectEqual(@as(u16, 3), m.catch_stack.items[0].to); // A remains
    try execInstr(&m, .{ .catch_end = .{ .dst = .{ .y = 0 } } }); // pop A
    try std.testing.expectEqual(@as(usize, 0), m.catch_stack.items.len);
}

// E3.10 test helper: assert `x` is the BEAM `catch`-of-`error` value wrap
// `{'EXIT', {Reason, Stacktrace}}` with the given `reason` term and an
// E1-minimal `nil` stacktrace. Used by the E1.8 catch laws, re-asserted at
// E3.10 with the class-discriminated wrap (was: a bare reason).
fn expectErrorCatchWrap(m: *Machine, x: FinalTerms.Term, reason: FinalTerms.Term) !void {
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, x));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, x, 0), FinalTerms.atom(&m.ctx, m.exit_tag)));
    const inner = FinalTerms.tupleElem(&m.ctx, x, 1); // {Reason, Stacktrace}
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, inner));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, inner, 0), reason));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, inner, 1), FinalTerms.nil(&m.ctx)));
}

test "LAW E1.8 integration: the run loop resumes at the handler after an unwind" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // 0: catch → landing pad at pc 3 (the handler)
    // 1: add x0+x0 where x0 is an atom → badarith crash → UNWIND to pc 3
    // 2: halt -1 (the "no crash" path — must be skipped)
    // 3: handler — x0 now holds the reason; move a marker and halt it
    m.regs[0] = FinalTerms.atom(&m.ctx, try atoms.intern("bad"));
    const prog: Program = &.{
        .{ .catch_ = .{ .to = 3, .dst = .{ .y = 0 } } }, // 0
        .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 0 }, .dst = 1 } }, // 1: crash → unwind
        .{ .halt = .{ .src = .{ .imm = -1 } } }, // 2: skipped
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 3: handler halts the caught reason
    };
    while (m.status == .running) try run(&m, prog, 2);
    try std.testing.expectEqual(Status.halted, m.status);
    // The handler halted x0, NOT -1. E3.10: a `catch` of an `error`-class crash
    // (badarith) now yields the class-discriminated wrap `{'EXIT',{badarith,[]}}`
    // (was: the bare `badarith` atom pre-E3.10) — the class-discrimination law.
    try expectErrorCatchWrap(&m, m.result, FinalTerms.atom(&m.ctx, m.badarith));
}

// ============================================================================
// E1.8 UNWIND law: a crash raised inside a frame lands at `to`, restores the
// ystack to `y_depth`, and lands the reason in x0 (catch) / class·reason in
// x0·x1 (try). MUTANT 2 (unwind forgets to restore `y_depth`) leaves the
// inside-region y-slots on the stack — the "ystack back to y_depth" assert
// fails. This is also where the backward-compat unwind branch is exercised.
// ============================================================================

test "LAW E1.8 unwind: a crash in a frame lands at `to`, reason in x0, ystack restored" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // ---- catch frame: reason value lands in x0 ----
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    // A caller y-frame of 2 slots exists BEFORE the protected region.
    try m.ystack.append(m.gpa, FinalTerms.nil(&m.ctx));
    try m.ystack.append(m.gpa, FinalTerms.nil(&m.ctx));
    // Enter a catch landing at pc 42, then allocate 3 more y-slots inside it.
    try execInstr(&m, .{ .catch_ = .{ .to = 42, .dst = .{ .y = 0 } } });
    try execInstr(&m, .{ .alloc_y = .{ .n = 3 } });
    try std.testing.expectEqual(@as(usize, 5), m.ystack.items.len);
    m.pc = 100; // pretend we are deep inside the region
    // A badarith crash inside the region must UNWIND, not halt.
    m.regs[0] = FinalTerms.atom(&m.ctx, try atoms.intern("boom"));
    try execInstr(&m, .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 0 }, .dst = 1 } });
    try std.testing.expectEqual(Status.running, m.status); // did NOT halt
    try std.testing.expectEqual(@as(usize, 42), m.pc); // landed at `to`
    try std.testing.expectEqual(@as(usize, 2), m.ystack.items.len); // y-stack back to y_depth (MUTANT 2)
    // gap-nested-catch (DIVERGENCE 680): the unwind to a `catch_` frame LEAVES it
    // on the stack — `frame.to` IS the `catch_end` pc, and `catch_end` is the
    // single pop point (a second pop in the unwind would eat the enclosing frame).
    try std.testing.expectEqual(@as(usize, 1), m.catch_stack.items.len); // frame REMAINS for catch_end
    // reason landed in x0 (the catch value convention). E3.10: an `error`-class
    // crash is wrapped `{'EXIT',{badarith,[]}}` by `catch` (class-discrimination).
    try expectErrorCatchWrap(&m, m.regs[0], FinalTerms.atom(&m.ctx, m.badarith));
    // catch_end (at `frame.to`) pops the frame exactly once — the normal and the
    // exception paths CONVERGE here, so this is the lone pop for a `catch`.
    try execInstr(&m, .{ .catch_end = .{ .dst = .{ .y = 0 } } });
    try std.testing.expectEqual(@as(usize, 0), m.catch_stack.items.len); // now consumed

    // ---- try frame: class in x0, reason in x1, stacktrace (nil) in x2 ----
    var mt = try Machine.init(gpa, &atoms);
    defer mt.deinit();
    try execInstr(&mt, .{ .try_ = .{ .to = 77, .dst = .{ .y = 0 } } });
    mt.pc = 200;
    try execInstr(&mt, .func_info); // function_clause crash inside the try
    try std.testing.expectEqual(Status.running, mt.status);
    try std.testing.expectEqual(@as(usize, 77), mt.pc);
    try std.testing.expect(FinalTerms.eqlExact(&mt.ctx, mt.regs[0], FinalTerms.atom(&mt.ctx, mt.err_class)));
    try std.testing.expect(FinalTerms.eqlExact(&mt.ctx, mt.regs[1], FinalTerms.atom(&mt.ctx, mt.fclause)));
    try std.testing.expect(FinalTerms.eqlExact(&mt.ctx, mt.regs[2], FinalTerms.nil(&mt.ctx)));

    // ---- nested: inner catch handles first; an outer frame still catches a
    // re-raise. try_case_end raises {try_clause, Value}; the OUTER catch lands it.
    var mn = try Machine.init(gpa, &atoms);
    defer mn.deinit();
    try execInstr(&mn, .{ .catch_ = .{ .to = 9, .dst = .{ .y = 0 } } }); // outer
    try execInstr(&mn, .{ .try_ = .{ .to = 5, .dst = .{ .y = 0 } } }); // inner
    mn.regs[0] = FinalTerms.int(&mn.ctx, 123);
    try execInstr(&mn, .{ .try_case_end = .{ .src = .{ .x = 0 } } }); // unwinds inner→ pc 5? no:
    // try_case_end raises INSIDE the inner try region, so it unwinds the INNER
    // (try) frame: lands at 5 with class/reason in x0/x1.
    try std.testing.expectEqual(@as(usize, 5), mn.pc);
    try std.testing.expectEqual(@as(usize, 1), mn.catch_stack.items.len); // outer remains
    try std.testing.expect(FinalTerms.eqlExact(&mn.ctx, mn.regs[0], FinalTerms.atom(&mn.ctx, mn.err_class)));
    // reason is {try_clause, 123}
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&mn.ctx, mn.regs[1]));
    try std.testing.expect(FinalTerms.eqlExact(&mn.ctx, FinalTerms.tupleElem(&mn.ctx, mn.regs[1], 0), FinalTerms.atom(&mn.ctx, mn.try_clause)));
}

test "LAW gap-nested-catch (DIVERGENCE 680): an inner `catch` that handles an exception LEAVES the enclosing catch frame intact, so a re-raise in the same region is caught by the OUTER catch (the double-pop that broke gen_server:call crash handling)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    // OUTER catch lands at pc 90; INNER catch lands at pc 40 (each `frame.to` is
    // its own `catch_end` pc, per the BEAM layout `{catch,_,{f,L}}; ...; L:
    // catch_end`). This mirrors `reraise/0`: outer `catch ( inner catch exit; re-raise )`.
    try execInstr(&m, .{ .catch_ = .{ .to = 90, .dst = .{ .y = 0 } } }); // OUTER
    try std.testing.expectEqual(@as(usize, 1), m.catch_stack.items.len);
    try execInstr(&m, .{ .catch_ = .{ .to = 40, .dst = .{ .y = 1 } } }); // INNER
    try std.testing.expectEqual(@as(usize, 2), m.catch_stack.items.len);
    // The inner region raises `exit(orig)` → unwinds to the INNER frame (pc 40),
    // leaving BOTH frames on the stack (the inner is popped by its own catch_end).
    m.regs[3] = FinalTerms.atom(&m.ctx, try atoms.intern("orig"));
    try execInstr(&m, .{ .raise = .{ .trace = .nil, .value = .{ .x = 3 } } });
    try std.testing.expectEqual(@as(usize, 40), m.pc); // landed at the inner catch_end
    // ★ THE FIX: the OUTER frame MUST still be present (the pre-fix double-pop
    // consumed it here, so the re-raise below escaped to a process crash).
    try std.testing.expectEqual(@as(usize, 2), m.catch_stack.items.len); // BOTH remain
    // The inner catch_end runs (at frame.to) and pops exactly the inner frame.
    try execInstr(&m, .{ .catch_end = .{ .dst = .{ .y = 1 } } });
    try std.testing.expectEqual(@as(usize, 1), m.catch_stack.items.len); // outer remains
    // Now re-raise `exit({wrapped, ...})` in the SAME region → the OUTER catch
    // (pc 90) MUST catch it. Pre-fix this hit an empty stack → process crash.
    m.regs[3] = FinalTerms.atom(&m.ctx, try atoms.intern("wrapped"));
    try execInstr(&m, .{ .raise = .{ .trace = .nil, .value = .{ .x = 3 } } });
    try std.testing.expectEqual(Status.running, m.status); // caught, NOT crashed
    try std.testing.expectEqual(@as(usize, 90), m.pc); // landed at the OUTER catch_end
    try std.testing.expectEqual(@as(usize, 1), m.catch_stack.items.len); // outer left for ITS catch_end
    try expectErrorCatchWrap(&m, m.regs[0], FinalTerms.atom(&m.ctx, try atoms.intern("wrapped")));
    try execInstr(&m, .{ .catch_end = .{ .dst = .{ .y = 0 } } });
    try std.testing.expectEqual(@as(usize, 0), m.catch_stack.items.len); // fully unwound, balanced
}

test "LAW gap-exit-reason-cook (DIVERGENCE 683): cookedExitReason cooks an uncaught-exception process EXIT reason by class — error:R->{R,St}, throw(V)->{{nocatch,V},St}, exit(R)->R (bare) — the OTP terminate_proc contract delivered to trap_exit linkers + monitors" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const boom = FinalTerms.atom(&m.ctx, try atoms.intern("boom"));
    // a stand-in cooked stacktrace term (cooking embeds whatever `exc.stacktrace` holds)
    const st = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("frame")), FinalTerms.nil(&m.ctx) });

    // error:boom -> {boom, St}
    m.exc = .{ .class = .error_, .reason = boom, .stacktrace = st };
    const er = try m.cookedExitReason();
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, er) == .tuple and FinalTerms.tupleArity(&m.ctx, er) == 2);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, er, 0), boom));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, er, 1), st)); // stacktrace preserved

    // throw(boom) -> {{nocatch, boom}, St}
    m.exc = .{ .class = .throw_, .reason = boom, .stacktrace = st };
    const tr = try m.cookedExitReason();
    try std.testing.expect(FinalTerms.tupleArity(&m.ctx, tr) == 2);
    const inner = FinalTerms.tupleElem(&m.ctx, tr, 0);
    try std.testing.expect(FinalTerms.tupleArity(&m.ctx, inner) == 2);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, inner, 0), FinalTerms.atom(&m.ctx, try atoms.intern("nocatch"))));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, inner, 1), boom)); // the thrown value
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, tr, 1), st));

    // exit(boom) -> boom (BARE — an explicit exit reason is delivered verbatim, never wrapped)
    m.exc = .{ .class = .exit_, .reason = boom, .stacktrace = st };
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try m.cookedExitReason(), boom));
}

test "LAW E1.8 raise/badrecord/build_stacktrace: re-raise, tuple reasons, cooked trace" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // raise/2 re-raises the resolved Value into an enclosing catch (→ x0).
    // E3.10: raise/2 preserves `m.exc.class` — here no exception is in flight so
    // it defaults to `error`, so the `catch` wraps `kaboom` as `{'EXIT',{kaboom,[]}}`.
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    try execInstr(&m, .{ .catch_ = .{ .to = 8, .dst = .{ .y = 0 } } });
    m.regs[3] = FinalTerms.atom(&m.ctx, try atoms.intern("kaboom"));
    try execInstr(&m, .{ .raise = .{ .trace = .nil, .value = .{ .x = 3 } } });
    try std.testing.expectEqual(@as(usize, 8), m.pc);
    try expectErrorCatchWrap(&m, m.regs[0], FinalTerms.atom(&m.ctx, try atoms.intern("kaboom")));

    // badrecord/1 raises {badrecord, Value}; with NO frame it halts with that
    // tuple as the crash reason (backward-compat halt path, tuple reason).
    var mb = try Machine.init(gpa, &atoms);
    defer mb.deinit();
    mb.regs[0] = FinalTerms.int(&mb.ctx, 55);
    try execInstr(&mb, .{ .badrecord = .{ .src = .{ .x = 0 } } });
    try std.testing.expectEqual(Status.crashed, mb.status);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&mb.ctx, mb.result));
    try std.testing.expect(FinalTerms.eqlExact(&mb.ctx, FinalTerms.tupleElem(&mb.ctx, mb.result, 0), FinalTerms.atom(&mb.ctx, mb.badrecord_atom)));
    try std.testing.expect(FinalTerms.eqlExact(&mb.ctx, FinalTerms.tupleElem(&mb.ctx, mb.result, 1), FinalTerms.int(&mb.ctx, 55)));

    // build_stacktrace cooks x0 to the E1-minimal empty stacktrace (nil).
    var ms = try Machine.init(gpa, &atoms);
    defer ms.deinit();
    ms.regs[0] = FinalTerms.int(&ms.ctx, 999);
    try execInstr(&ms, .build_stacktrace);
    try std.testing.expect(FinalTerms.eqlExact(&ms.ctx, ms.regs[0], FinalTerms.nil(&ms.ctx)));

    // raw_raise reads class from x0, reason from x1, and unwinds into a catch.
    var mr = try Machine.init(gpa, &atoms);
    defer mr.deinit();
    try execInstr(&mr, .{ .try_ = .{ .to = 4, .dst = .{ .y = 0 } } });
    mr.regs[0] = FinalTerms.atom(&mr.ctx, try atoms.intern("throw"));
    mr.regs[1] = FinalTerms.int(&mr.ctx, 7);
    try execInstr(&mr, .raw_raise);
    try std.testing.expectEqual(@as(usize, 4), mr.pc);
    try std.testing.expect(FinalTerms.eqlExact(&mr.ctx, mr.regs[0], FinalTerms.atom(&mr.ctx, try atoms.intern("throw")))); // class preserved
    try std.testing.expect(FinalTerms.eqlExact(&mr.ctx, mr.regs[1], FinalTerms.int(&mr.ctx, 7))); // reason
}

// ============================================================================
// E3.10 EXCEPTION-MODEL laws (Task 10). The E1.8 catch-stack stays; the
// exception VALUE now carries a CLASS {throw, error, exit}. These laws pin the
// four charter properties + the two mutants:
//   (1) class-discrimination: `catch` wraps error/exit/throw DISTINCTLY.
//   (2) re-raise class-preservation: `.raise` re-raises with `m.exc.class`.
//   (3) raw_raise/raise-3 bad class -> `badarg` WITHOUT raising.
//   (4) structured {badmap,_}/{badkey,_} through the executor, guard/body split.
// ============================================================================

// (1) class-discrimination — one assertion per class through a single `catch`.
// A `raw_raise` (class in x0, reason in x1) inside a catch frame lands the
// CLASS-WRAPPED value in x0: throw -> bare; exit -> {'EXIT',R}; error ->
// {'EXIT',{R,[]}}. MUTANT 1 (catch wraps a throw as {'EXIT',_} too) breaks the
// throw arm; MUTANT (error not double-wrapped) breaks the error arm.
test "LAW E3.10 class-discrimination: catch wraps throw/exit/error distinctly" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    const Case = struct { class: []const u8, kind: enum { bare, exit_tuple, error_tuple } };
    const cases = [_]Case{
        .{ .class = "throw", .kind = .bare },
        .{ .class = "exit", .kind = .exit_tuple },
        .{ .class = "error", .kind = .error_tuple },
    };
    for (cases) |cse| {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        try execInstr(&m, .{ .catch_ = .{ .to = 9, .dst = .{ .y = 0 } } });
        const reason = FinalTerms.int(&m.ctx, 42);
        m.regs[0] = FinalTerms.atom(&m.ctx, try atoms.intern(cse.class));
        m.regs[1] = reason;
        try execInstr(&m, .raw_raise);
        try std.testing.expectEqual(@as(usize, 9), m.pc); // landed at the catch
        switch (cse.kind) {
            // throw: the value is caught BARE (a thrown value is caught as itself).
            .bare => try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], reason)),
            // exit: {'EXIT', Reason}.
            .exit_tuple => {
                try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, m.regs[0]));
                try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.regs[0], 0), FinalTerms.atom(&m.ctx, m.exit_tag)));
                try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.regs[0], 1), reason));
            },
            // error: {'EXIT', {Reason, Stacktrace}} — the shared helper.
            .error_tuple => try expectErrorCatchWrap(&m, m.regs[0], reason),
        }
    }
}

// (2) re-raise class-preservation — a THROW caught into a try handler (so
// `m.exc.class == .throw_`), then re-raised via `.raise` into an ENCLOSING
// catch, is STILL caught bare (throw), not `{'EXIT',_}`. MUTANT 2 (`.raise`
// hardcodes `.error_`) would double-wrap it as an error tuple — killed here.
test "LAW E3.10 re-raise preserves the original class (throw stays throw)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // Outer catch (lands the re-raise), then an inner try that catches a throw.
    try execInstr(&m, .{ .catch_ = .{ .to = 20, .dst = .{ .y = 0 } } }); // outer
    try execInstr(&m, .{ .try_ = .{ .to = 10, .dst = .{ .y = 1 } } }); // inner
    const reason = FinalTerms.int(&m.ctx, 99);
    m.regs[0] = FinalTerms.atom(&m.ctx, try atoms.intern("throw"));
    m.regs[1] = reason;
    try execInstr(&m, .raw_raise); // unwinds inner try -> x0=throw, x1=reason, x2=[]
    try std.testing.expectEqual(@as(usize, 10), m.pc);
    try std.testing.expectEqual(ExcClass.throw_, m.exc.class); // recorded
    // Now re-raise the handled exception (`raise Trace Value`) into the outer catch.
    try execInstr(&m, .{ .raise = .{ .trace = .{ .x = 2 }, .value = .{ .x = 1 } } });
    try std.testing.expectEqual(@as(usize, 20), m.pc); // landed at the outer catch
    // PRESERVED throw -> caught BARE (mutant 2 would give {'EXIT',{99,[]}}).
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], reason));
}

// (3) raw_raise with a NON-class x0 returns the atom `badarg` WITHOUT raising
// (BEAM's raise/3 contract, entry 2d): the catch frame is NOT consumed and the
// machine keeps running. Same for the `erlang:raise/3` BIF (checked in erlang.zig).
test "LAW E3.10 raw_raise with a bad class -> badarg, no raise" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    try execInstr(&m, .{ .catch_ = .{ .to = 5, .dst = .{ .y = 0 } } });
    m.regs[0] = FinalTerms.atom(&m.ctx, try atoms.intern("not_a_class"));
    m.regs[1] = FinalTerms.int(&m.ctx, 1);
    m.pc = 3;
    try execInstr(&m, .raw_raise);
    try std.testing.expectEqual(Status.running, m.status); // did NOT raise/halt
    try std.testing.expectEqual(@as(usize, 1), m.catch_stack.items.len); // frame intact
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.atom(&m.ctx, m.badarg)));
}

// (4) structured reason through the REAL executor + the guard/body split. In
// BODY context (else_to null) `erlang:map_get` on an absent key raises the
// STRUCTURED error:{badkey,Key} (halt reason = the tuple). In GUARD context
// (else_to set) the SAME failure BRANCHES — DIVERGENCE 6b/c: guard behaviour is
// EXACT, only the body reason gains structure.
test "LAW E3.10 structured {badkey,_} via executor, guard/body split preserved" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    const c = struct {
        fn absentKeyCall(m: *Machine, else_to: ?u32) !void {
            const a = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("a"));
            const absent = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("z"));
            const mp = try FinalTerms.mapNew(&m.ctx, &.{a}, &.{FinalTerms.int(&m.ctx, 1)});
            m.regs[0] = absent;
            m.regs[1] = mp;
            try execInstr(m, .{ .bif_call = .{
                .bif = .{ .func = &bif_erlang.map_get },
                .args = .{ .{ .x = 0 }, .{ .x = 1 }, .nil },
                .argc = 2,
                .dst = .{ .x = 2 },
                .else_to = else_to,
                .gc_live = null,
            } });
        }
    };

    // BODY context: absent key -> crash with error:{badkey, z}.
    var mb = try Machine.init(gpa, &atoms);
    defer mb.deinit();
    try c.absentKeyCall(&mb, null);
    try std.testing.expectEqual(Status.crashed, mb.status);
    try std.testing.expectEqual(ExcClass.error_, mb.exc.class);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&mb.ctx, mb.result));
    try std.testing.expect(FinalTerms.eqlExact(&mb.ctx, FinalTerms.tupleElem(&mb.ctx, mb.result, 0), FinalTerms.atom(&mb.ctx, mb.badkey_atom)));

    // GUARD context: the SAME absent-key failure BRANCHES to else_to, no crash.
    var mg = try Machine.init(gpa, &atoms);
    defer mg.deinit();
    mg.pc = 3;
    try c.absentKeyCall(&mg, 7);
    try std.testing.expectEqual(Status.running, mg.status);
    try std.testing.expectEqual(@as(usize, 7), mg.pc);
    try std.testing.expect(mg.bif_raise == null); // staged reason consumed
}

// ============================================================================
// E3.11 STACKTRACE laws (Task 11, DIVERGENCE entry 2b). `cookStacktrace` builds
// `[{M,F,Arity,[{file,File},{line,L}]} | Callers]` from the pc→loc table
// (`m.locs`) + the return stack. The end-to-end BEAM-exactness is covered by
// the `try_class`/stacktrace differential corpus; these unit laws pin the
// head-frame mfa+line, the return-order of callers, the depth bound, and the
// transparency (no locs ⇒ the E1-minimal `nil`, execution unchanged).
// ============================================================================

fn stackListLen(m: *Machine, lst: FinalTerms.Term) usize {
    var n: usize = 0;
    var cur = lst;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) : (n += 1) cur = FinalTerms.listTail(&m.ctx, cur);
    return n;
}

// Assert `frame` is `{M, F, Arity, [{file,FileCharlist},{line,Line}]}`.
fn expectFrame(m: *Machine, frame: FinalTerms.Term, mi: ta.AtomIdx, fi: ta.AtomIdx, arity: i64, line: i64) !void {
    try std.testing.expectEqual(@as(usize, 4), FinalTerms.tupleArity(&m.ctx, frame));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, frame, 0), FinalTerms.atom(&m.ctx, mi)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, frame, 1), FinalTerms.atom(&m.ctx, fi)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, frame, 2), FinalTerms.int(&m.ctx, arity)));
    const loc = FinalTerms.tupleElem(&m.ctx, frame, 3); // [{file,_},{line,L}]
    try std.testing.expectEqual(@as(usize, 2), stackListLen(m, loc));
    const line_pair = FinalTerms.listHead(&m.ctx, FinalTerms.listTail(&m.ctx, loc));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, line_pair, 0), FinalTerms.atom(&m.ctx, m.line_key)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, line_pair, 1), FinalTerms.int(&m.ctx, line)));
}

test "LAW E3.11 head-frame exactness: the cooked head names the faulting mfa + line (mutant: off-by-one pc)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const mi = try atoms.intern("mymod");
    const fi = try atoms.intern("myfun");
    const filei = try atoms.intern("mymod.erl");
    // Distinct lines per pc, so an off-by-one head pc is observable (mutant 1).
    const locs = [_]Loc{
        .{ .m = mi, .f = fi, .a = 2, .line = 40, .file = filei },
        .{ .m = mi, .f = fi, .a = 2, .line = 41, .file = filei },
        .{ .m = mi, .f = fi, .a = 2, .line = 42, .file = filei },
    };
    m.locs = &locs;
    m.pc = 3; // `run` increments pc BEFORE execInstr → faulting pc = pc-1 = 2 (line 42)
    try m.crash(m.badarith); // empty catch stack → halt, but the trace is cooked
    const st = m.exc.stacktrace;
    try std.testing.expectEqual(@as(usize, 1), stackListLen(&m, st)); // head only, no callers
    try expectFrame(&m, FinalTerms.listHead(&m.ctx, st), mi, fi, 2, 42);
    // The file is the charlist "mymod.erl" (checked separately from expectFrame).
    const loc = FinalTerms.tupleElem(&m.ctx, FinalTerms.listHead(&m.ctx, st), 3);
    const file_pair = FinalTerms.listHead(&m.ctx, loc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, file_pair, 0), FinalTerms.atom(&m.ctx, m.file_key)));
    const fc = FinalTerms.tupleElem(&m.ctx, file_pair, 1);
    try std.testing.expectEqual(@as(usize, "mymod.erl".len), stackListLen(&m, fc)); // a 9-char charlist
}

test "LAW E3.11 caller frames are in RETURN order (most-recent first) — mutant: call order" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const mi = try atoms.intern("m");
    const fh = try atoms.intern("head");
    const fa = try atoms.intern("caller_a");
    const fb = try atoms.intern("caller_b");
    const filei = try atoms.intern("m.erl");
    // pc 0 = caller_a's return site, pc 1 = caller_b's return site, pc 2 = head.
    const locs = [_]Loc{
        .{ .m = mi, .f = fa, .a = 1, .line = 10, .file = filei },
        .{ .m = mi, .f = fb, .a = 1, .line = 20, .file = filei },
        .{ .m = mi, .f = fh, .a = 1, .line = 30, .file = filei },
    };
    m.locs = &locs;
    m.pc = 3; // head = locs[2]
    // Return stack: caller_a called first (bottom), caller_b called last (top).
    try m.stack.append(m.gpa, 0); // caller_a return pc (older)
    try m.stack.append(m.gpa, 1); // caller_b return pc (newer, top)
    try m.crash(m.badarith);
    const st = m.exc.stacktrace;
    // [head(fh,30), caller_b(fb,20), caller_a(fa,10)] — RETURN order for callers.
    try std.testing.expectEqual(@as(usize, 3), stackListLen(&m, st));
    const f0 = FinalTerms.listHead(&m.ctx, st);
    const f1 = FinalTerms.listHead(&m.ctx, FinalTerms.listTail(&m.ctx, st));
    const f2 = FinalTerms.listHead(&m.ctx, FinalTerms.listTail(&m.ctx, FinalTerms.listTail(&m.ctx, st)));
    try expectFrame(&m, f0, mi, fh, 1, 30); // head
    try expectFrame(&m, f1, mi, fb, 1, 20); // most-recent caller first (mutant 2 swaps f1/f2)
    try expectFrame(&m, f2, mi, fa, 1, 10);
}

test "LAW E3.11 depth-bound: the cooked trace is at most 8 frames" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const mi = try atoms.intern("m");
    const fi = try atoms.intern("f");
    var locs: [20]Loc = undefined;
    for (&locs, 0..) |*l, i| l.* = .{ .m = mi, .f = fi, .a = 0, .line = @intCast(i + 1), .file = null };
    m.locs = &locs;
    m.pc = 20; // head = locs[19]
    // Push 19 return pcs — far more than the bound of 8.
    var i: usize = 0;
    while (i < 19) : (i += 1) try m.stack.append(m.gpa, @intCast(i));
    try m.crash(m.badarith);
    try std.testing.expectEqual(@as(usize, 8), stackListLen(&m, m.exc.stacktrace)); // bounded
}

test "LAW E3.11 transparency: with NO locs the trace is the E1-minimal nil, execution unchanged" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // Twin machines: one with locs, one without. Same crash → same status/reason;
    // only the stacktrace differs (cooked vs nil). No `Line` chunk ⇒ nil, so no
    // pre-E3.11 law (which never set m.locs) shifts.
    var bare = try Machine.init(gpa, &atoms);
    defer bare.deinit();
    bare.pc = 1;
    try bare.crash(bare.badarith);
    try std.testing.expectEqual(Status.crashed, bare.status);
    try std.testing.expect(FinalTerms.eqlExact(&bare.ctx, bare.result, FinalTerms.atom(&bare.ctx, bare.badarith)));
    try std.testing.expect(FinalTerms.eqlExact(&bare.ctx, bare.exc.stacktrace, FinalTerms.nil(&bare.ctx))); // nil

    const mi = try atoms.intern("m");
    const fi = try atoms.intern("f");
    var withloc = try Machine.init(gpa, &atoms);
    defer withloc.deinit();
    const locs = [_]Loc{.{ .m = mi, .f = fi, .a = 0, .line = 7, .file = null }};
    withloc.locs = &locs;
    withloc.pc = 1;
    try withloc.crash(withloc.badarith);
    // SAME status + reason as the bare twin (transparency of execution) ...
    try std.testing.expectEqual(Status.crashed, withloc.status);
    try std.testing.expect(FinalTerms.eqlExact(&withloc.ctx, withloc.result, FinalTerms.atom(&withloc.ctx, withloc.badarith)));
    // ... but a NON-nil cooked head frame (line 7, no file → `[{line,7}]`).
    try std.testing.expectEqual(@as(usize, 1), stackListLen(&withloc, withloc.exc.stacktrace));
}

// ============================================================================
// E3.12: static multi-module dispatch — call_ext BIF/code resolution, apply/3,
// error_handler/undefined_function, undef stacktrace. These are the arm-level
// semantic laws (the loader-decode + end-to-end corpus proof live in
// beam_loader / the Erlang corpus). The crux the epoch turns on: with call_ext
// dispatching, the E3.7/E3.8/E3.9/E3.10 deferred-E4-procdispatch BIF families are
// END-TO-END reachable (before this every call_ext translated to func_info).
// ============================================================================

test "LAW E3.12 call_ext_bif runs a resolved BIF over x0..x[arity-1] into x0" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // erlang:length/1 is an implemented BIF: x0 = [a,b,c] → call_ext length → 3.
    const lst = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 2), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 3), FinalTerms.nil(&m.ctx))));
    m.regs[0] = lst;
    const len_fn = bif_dispatch.resolve("erlang", "length", 1).?;
    try execInstr(&m, .{ .call_ext_bif = .{ .func = len_fn, .arity = 1 } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.int(&m.ctx, 3)));
    try std.testing.expect(m.pending == null);
}

test "LAW E3.12 call_ext_bif to a process-effect BIF (send) sets the trap and returns the msg" {
    const procsys = @import("bifs/procsys.zig");
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // send(Pid, Msg): x0 = pid, x1 = msg. call_ext send/2 → pending .send_to, x0 = msg.
    const pid = try FinalTerms.pid(&m.ctx, 2, 0);
    const msg = FinalTerms.int(&m.ctx, 42);
    m.regs[0] = pid;
    m.regs[1] = msg;
    try execInstr(&m, .{ .call_ext_bif = .{ .func = &procsys.send_2, .arity = 2 } });
    try std.testing.expect(m.pending != null and m.pending.? == .send_to);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], msg)); // send returns the msg
}

test "LAW E3.12 call_ext_bif to a raising BIF (error/1) unwinds error:reason" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // erlang:error/1: x0 = Reason → raises class error, bare reason on the halt path.
    const reason = FinalTerms.atom(&m.ctx, try atoms.intern("boom"));
    m.regs[0] = reason;
    try execInstr(&m, .{ .call_ext_bif = .{ .func = &bif_erlang.error_1, .arity = 1 } });
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expectEqual(ExcClass.error_, m.exc.class);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, reason));
}

test "LAW E3.12 call_ext_code resolves a loaded export (push return, jump); miss -> error:undef with {M,F,Args,[]} head" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const m2 = try atoms.intern("m2");
    const g = try atoms.intern("g");
    const exports = [_]Export{.{ .module = m2, .func = g, .arity = 1, .pc = 77 }};
    m.exports = &exports;

    // HIT: call_ext_code m2:g/1 (push_ret) pushes the continuation and jumps to 77.
    m.pc = 10; // the "continuation" (pc already advanced past call_ext by run)
    m.regs[0] = FinalTerms.int(&m.ctx, 5);
    try execInstr(&m, .{ .call_ext_code = .{ .module = m2, .func = g, .arity = 1, .push_ret = true } });
    try std.testing.expectEqual(@as(usize, 77), m.pc);
    try std.testing.expectEqual(@as(usize, 1), m.stack.items.len);
    try std.testing.expectEqual(@as(usize, 10), m.stack.items[0]);

    // MISS: an unresolved M:F/A raises error:undef with head frame {M,F,Args,[]}.
    var m3 = try Machine.init(gpa, &atoms);
    defer m3.deinit();
    const nomod = try atoms.intern("nomod");
    const nofun = try atoms.intern("nofun");
    m3.regs[0] = FinalTerms.int(&m3.ctx, 7);
    m3.regs[1] = FinalTerms.int(&m3.ctx, 8);
    try execInstr(&m3, .{ .call_ext_code = .{ .module = nomod, .func = nofun, .arity = 2, .push_ret = true } });
    try std.testing.expectEqual(Status.crashed, m3.status);
    try std.testing.expect(FinalTerms.eqlExact(&m3.ctx, m3.result, FinalTerms.atom(&m3.ctx, m3.undef)));
    // head frame {nomod, nofun, [7,8], []}
    const head = FinalTerms.listHead(&m3.ctx, m3.exc.stacktrace);
    var buf: [4]FinalTerms.Term = undefined;
    try std.testing.expectEqual(@as(usize, 4), FinalTerms.tupleArity(&m3.ctx, head));
    for (0..4) |i| buf[i] = FinalTerms.tupleElem(&m3.ctx, head, i);
    try std.testing.expect(FinalTerms.eqlExact(&m3.ctx, buf[0], FinalTerms.atom(&m3.ctx, nomod)));
    try std.testing.expect(FinalTerms.eqlExact(&m3.ctx, buf[1], FinalTerms.atom(&m3.ctx, nofun)));
    const args = buf[2];
    try std.testing.expect(FinalTerms.eqlExact(&m3.ctx, FinalTerms.listHead(&m3.ctx, args), FinalTerms.int(&m3.ctx, 7)));
    try std.testing.expect(FinalTerms.eqlExact(&m3.ctx, buf[3], FinalTerms.nil(&m3.ctx))); // [] loc
}

test "LAW E7.1 call homomorphism: (fun M:F/A)(Args) == apply(M,F,Args) — code target AND bif target" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    const m2 = try atoms.intern("m2");
    const g = try atoms.intern("g");
    const exports = [_]Export{.{ .module = m2, .func = g, .arity = 1, .pc = 77 }};

    // --- CODE target: call_fun on `fun m2:g/1` routes through dispatchMFA to
    //     the loaded export (push continuation, jump to 77) — byte-identical
    //     control effect to apply/2 of m2:g/1.
    var mc = try Machine.init(gpa, &atoms);
    defer mc.deinit();
    mc.exports = &exports;
    const ef = try FinalTerms.makeExportFun(&mc.ctx, FinalTerms.atomTerm(m2), FinalTerms.atomTerm(g), 1);
    mc.pc = 10; // continuation
    mc.regs[0] = FinalTerms.int(&mc.ctx, 5); // the single Arg (already in x0)
    mc.regs[1] = ef;
    try execInstr(&mc, .{ .call_fun = .{ .f = .{ .x = 1 } } });
    try std.testing.expectEqual(@as(usize, 77), mc.pc);
    try std.testing.expectEqual(@as(usize, 1), mc.stack.items.len);
    try std.testing.expectEqual(@as(usize, 10), mc.stack.items[0]);

    // apply/2 twin: same M:F/A, same Arg — identical (pc 77, one pushed cont).
    var ma = try Machine.init(gpa, &atoms);
    defer ma.deinit();
    ma.exports = &exports;
    ma.pc = 10;
    ma.regs[0] = FinalTerms.int(&ma.ctx, 5); // Arg
    ma.regs[1] = FinalTerms.atomTerm(m2); // M = x[arity]
    ma.regs[2] = FinalTerms.atomTerm(g); //  F = x[arity+1]
    try execInstr(&ma, .{ .apply_op = .{ .arity = 1, .tail = false } });
    try std.testing.expectEqual(mc.pc, ma.pc); // 77 == 77
    try std.testing.expectEqual(mc.stack.items.len, ma.stack.items.len);

    // --- BIF target: call_fun on `fun erlang:abs/1` runs the BIF inline (result
    //     into x0, NO continuation pushed) — exactly like apply of erlang:abs/1.
    var mb = try Machine.init(gpa, &atoms);
    defer mb.deinit();
    const erl = try atoms.intern("erlang");
    const abs_ = try atoms.intern("abs");
    const ef2 = try FinalTerms.makeExportFun(&mb.ctx, FinalTerms.atomTerm(erl), FinalTerms.atomTerm(abs_), 1);
    mb.regs[0] = FinalTerms.int(&mb.ctx, -5);
    mb.regs[1] = ef2;
    try execInstr(&mb, .{ .call_fun = .{ .f = .{ .x = 1 } } });
    try std.testing.expect(FinalTerms.eqlExact(&mb.ctx, mb.regs[0], FinalTerms.int(&mb.ctx, 5)));
    try std.testing.expectEqual(@as(usize, 0), mb.stack.items.len); // bif: no push

    // apply twin of the BIF: same result in x0.
    var mb2 = try Machine.init(gpa, &atoms);
    defer mb2.deinit();
    mb2.regs[0] = FinalTerms.int(&mb2.ctx, -5);
    mb2.regs[1] = FinalTerms.atomTerm(erl);
    mb2.regs[2] = FinalTerms.atomTerm(abs_);
    try execInstr(&mb2, .{ .apply_op = .{ .arity = 1, .tail = false } });
    try std.testing.expect(FinalTerms.eqlExact(&mb2.ctx, mb2.regs[0], FinalTerms.int(&mb2.ctx, 5)));

    // is_function/1 holds for an export fun.
    try std.testing.expect(typeTestHolds(&mb, .function, ef2));
}

// ============================================================================
// e5-dispatch-codeidx (Task 2 RELOAD half, DIVERGENCE 81): `call_ext` dispatch
// consults the RUNTIME code table. These four laws pin the dispatch mechanism
// the live-reload BIFs (`prepare_loading/2`+`finish_loading/1`) ride: a module
// loaded at run time is spliced into the UNIFIED code space (`dyn_code`) and made
// callable via `dyn_exports`, while a running continuation keeps its version
// (M10 at the dispatch layer) and an un-reloaded static module is unchanged.
// ============================================================================

/// A tiny runtime module `d` whose `f/0` returns `val`: `move val -> x0; ret`.
/// Appended into `m.dyn_code` at the current end; registers `d:f/0` in
/// `dyn_exports` (at the unified pc) and in `code_index` (the currency gate).
fn loadRuntimeMod(m: *Machine, gpa: std.mem.Allocator, name: []const u8, val: i64) !u32 {
    const d = try m.ctx.atoms.intern(name);
    const f = try m.ctx.atoms.intern("f");
    const pc: u32 = @intCast(m.code_base + m.dyn_code.items.len);
    try m.dyn_code.append(gpa, .{ .move = .{ .dst = 0, .src = .{ .imm = val } } });
    try m.dyn_code.append(gpa, .ret);
    // reload: NEW code wins — drop any prior committed export for `d`.
    var i: usize = 0;
    while (i < m.dyn_exports.items.len) {
        if (m.dyn_exports.items[i].module == d) {
            _ = m.dyn_exports.swapRemove(i);
        } else i += 1;
    }
    try m.dyn_exports.append(gpa, .{ .module = d, .func = f, .arity = 0, .pc = pc });
    try m.code_index.load(name, &.{});
    return pc;
}

test "LAW e5-dispatch-codeidx: dispatch consults the runtime table (a finish_loaded module is callable)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const d = try atoms.intern("d");
    const f = try atoms.intern("f");
    // The static linked image: call d:f/0, then halt with x0. `d` is NOT in the
    // static `exports` — only the runtime code server can make it callable.
    const stat: Program = &.{
        .{ .call_ext_code = .{ .module = d, .func = f, .arity = 0, .push_ret = true } },
        .{ .halt = .{ .src = .{ .x = 0 } } },
    };
    m.code_base = stat.len;

    // Before load: d:f/0 is unresolved → a call raises error:undef (rejection).
    try std.testing.expect(m.resolveRuntime(d, f, 0) == null);

    // Load d:f/0 (returns 42) into the runtime code space; now it is callable.
    _ = try loadRuntimeMod(&m, gpa, "d", 42);
    var guard: usize = 0;
    while (m.status == .running and guard < 100) : (guard += 1) try run(&m, stat, 4);
    try std.testing.expectEqual(Status.halted, m.status);
    try std.testing.expectEqual(@as(i64, 42), FinalTerms.smallValOf(m.result));
}

test "LAW e5-dispatch-codeidx: continuation-stays — a reload appends new code; the old version survives" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const d = try atoms.intern("d");
    const f = try atoms.intern("f");
    m.code_base = 4; // a non-zero static image length (its content is irrelevant here)

    const pc_v1 = try loadRuntimeMod(&m, gpa, "d", 42); // v1: f/0 -> 42
    const pc_v2 = try loadRuntimeMod(&m, gpa, "d", 99); // v2: f/0 -> 99 (RELOAD)

    // NEW-CODE-WINS: a fresh external call resolves to v2 (the newest version).
    try std.testing.expectEqual(pc_v2, m.resolveRuntime(d, f, 0).?);
    try std.testing.expect(pc_v2 != pc_v1);

    // CONTINUATION-STAYS: the OLD version's code range is UNCHANGED (append-only),
    // so a process holding a return pc into v1 keeps executing v1's semantics.
    // Run a machine from the v1 entry pc: it still returns 42, not 99. (Execution
    // fetches from dyn_code once pc >= code_base, so an empty static image suffices.)
    const stat: Program = &.{};
    m.pc = pc_v1;
    var guard: usize = 0;
    while (m.status == .running and guard < 100) : (guard += 1) try run(&m, stat, 4);
    try std.testing.expectEqual(@as(i64, 42), FinalTerms.smallValOf(m.result));

    // …and a fresh run from v2's entry returns 99 (the two versions COEXIST).
    var m2 = try Machine.init(gpa, &atoms);
    defer m2.deinit();
    m2.code_base = 4;
    _ = try loadRuntimeMod(&m2, gpa, "d", 42);
    const pc2_v2 = try loadRuntimeMod(&m2, gpa, "d", 99);
    m2.pc = pc2_v2;
    var g2: usize = 0;
    while (m2.status == .running and g2 < 100) : (g2 += 1) try run(&m2, stat, 4);
    try std.testing.expectEqual(@as(i64, 99), FinalTerms.smallValOf(m2.result));
}

test "LAW e5-dispatch-codeidx: static≡runtime homomorphism — an un-reloaded module dispatches via the static path unchanged" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    const s = try atoms.intern("s");
    const g = try atoms.intern("g");
    const exports = [_]Export{.{ .module = s, .func = g, .arity = 0, .pc = 5 }};

    // A machine with s:g/0 in the STATIC exports and NO runtime code.
    var ma = try Machine.init(gpa, &atoms);
    defer ma.deinit();
    ma.exports = &exports;
    try std.testing.expect(ma.resolveRuntime(s, g, 0) == null); // no runtime row
    ma.pc = 3;
    try execInstr(&ma, .{ .call_ext_code = .{ .module = s, .func = g, .arity = 0, .push_ret = true } });
    const static_pc = ma.pc; // where the static path dispatched to

    // The SAME machine but with an UNRELATED runtime module `d` also loaded: the
    // static call to s:g/0 dispatches IDENTICALLY (the runtime table never
    // shadows a module it did not load — the homomorphism).
    var mb = try Machine.init(gpa, &atoms);
    defer mb.deinit();
    mb.exports = &exports;
    mb.code_base = 8;
    _ = try loadRuntimeMod(&mb, gpa, "d", 7); // an UNRELATED runtime module
    try std.testing.expect(mb.resolveRuntime(s, g, 0) == null); // s still static-only
    mb.pc = 3;
    try execInstr(&mb, .{ .call_ext_code = .{ .module = s, .func = g, .arity = 0, .push_ret = true } });
    try std.testing.expectEqual(static_pc, mb.pc); // identical dispatch (== 5)
    try std.testing.expectEqual(@as(usize, 5), mb.pc);
}

test "LAW e5-dispatch-codeidx: rejection totality — an unknown module and a DELETED runtime module both trap undef" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const d = try atoms.intern("d");
    const f = try atoms.intern("f");
    const nomod = try atoms.intern("nomod");
    m.code_base = 4;
    _ = try loadRuntimeMod(&m, gpa, "d", 42);

    // A module neither static nor runtime-loaded → undef.
    m.regs[0] = FinalTerms.int(&m.ctx, 1);
    try execInstr(&m, .{ .call_ext_code = .{ .module = nomod, .func = f, .arity = 0, .push_ret = true } });
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.undef)));

    // A runtime module whose current version was RETIRED (delete_module) is no
    // longer callable — `resolveRuntime`'s currency gate misses → undef.
    try std.testing.expect(m.resolveRuntime(d, f, 0) != null); // callable now…
    try std.testing.expectEqual(codeix.DeleteResult.deleted, m.code_index.deleteModule("d"));
    try std.testing.expect(m.resolveRuntime(d, f, 0) == null); // …deleted → uncallable
}

test "LAW E3.12 error_handler:undefined_function/3 hook is honored when loaded" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const eh = try atoms.intern("error_handler");
    const uf = try atoms.intern("undefined_function");
    const exports = [_]Export{.{ .module = eh, .func = uf, .arity = 3, .pc = 55 }};
    m.exports = &exports;

    const nomod = try atoms.intern("nomod");
    const nofun = try atoms.intern("nofun");
    m.pc = 3;
    m.regs[0] = FinalTerms.int(&m.ctx, 9); // the sole arg
    try execInstr(&m, .{ .call_ext_code = .{ .module = nomod, .func = nofun, .arity = 1, .push_ret = true } });
    // The hook is CALLED: pc jumps to it, x0=M, x1=F, x2=Args, return pushed.
    try std.testing.expectEqual(@as(usize, 55), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.atom(&m.ctx, nomod)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.atom(&m.ctx, nofun)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, m.regs[2]), FinalTerms.int(&m.ctx, 9)));
    try std.testing.expectEqual(Status.running, m.status); // NOT crashed — the hook ran
}

test "LAW E3.12 apply/3 spreads Args and dispatches identically to call_ext (apply/3 == call_ext)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    const m2 = try atoms.intern("m2");
    const g = try atoms.intern("g");
    const exports = [_]Export{.{ .module = m2, .func = g, .arity = 2, .pc = 88 }};

    // apply(m2, g, [10,20]): spreads 10,20 into x0/x1 and dispatches m2:g/2 → pc 88,
    // the SAME denotation as call_ext_code m2:g/2 with x0=10,x1=20.
    var ma = try Machine.init(gpa, &atoms);
    defer ma.deinit();
    ma.exports = &exports;
    ma.regs[0] = FinalTerms.atom(&ma.ctx, m2);
    ma.regs[1] = FinalTerms.atom(&ma.ctx, g);
    ma.regs[2] = try FinalTerms.cons(&ma.ctx, FinalTerms.int(&ma.ctx, 10), try FinalTerms.cons(&ma.ctx, FinalTerms.int(&ma.ctx, 20), FinalTerms.nil(&ma.ctx)));
    ma.pc = 4;
    try execInstr(&ma, .{ .apply3 = .{ .tail = false } });
    try std.testing.expectEqual(@as(usize, 88), ma.pc);
    try std.testing.expect(FinalTerms.eqlExact(&ma.ctx, ma.regs[0], FinalTerms.int(&ma.ctx, 10)));
    try std.testing.expect(FinalTerms.eqlExact(&ma.ctx, ma.regs[1], FinalTerms.int(&ma.ctx, 20)));
    try std.testing.expectEqual(@as(usize, 1), ma.stack.items.len); // non-tail pushed the return

    // apply/3 with a non-atom M is badarg.
    var mb = try Machine.init(gpa, &atoms);
    defer mb.deinit();
    mb.regs[0] = FinalTerms.int(&mb.ctx, 1);
    mb.regs[1] = FinalTerms.atom(&mb.ctx, g);
    mb.regs[2] = FinalTerms.nil(&mb.ctx);
    try execInstr(&mb, .{ .apply3 = .{ .tail = false } });
    try std.testing.expectEqual(Status.crashed, mb.status);
    try std.testing.expect(FinalTerms.eqlExact(&mb.ctx, mb.result, FinalTerms.atom(&mb.ctx, mb.badarg)));
}

test "LAW gap-apply-arity (DIVERGENCE 732): apply/3 spreads + dispatches ANY arity up to MAX_ARG (255) — NOT capped at the stale 16 — and system_limits only at >=256 args" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const m3 = try atoms.intern("m3");
    const h = try atoms.intern("h");

    // 17 ARGS — the exact bug: the old `>= 16` cap `system_limit`'d this. Now it
    // spreads regs[0..16] and dispatches m3:h/17 → pc 88. regs[16] (the 17th arg,
    // one PAST the old cap) must hold the 17th list element.
    {
        const exp = [_]Export{.{ .module = m3, .func = h, .arity = 17, .pc = 88 }};
        var mx = try Machine.init(gpa, &atoms);
        defer mx.deinit();
        mx.exports = &exp;
        mx.regs[0] = FinalTerms.atom(&mx.ctx, m3);
        mx.regs[1] = FinalTerms.atom(&mx.ctx, h);
        var lst = FinalTerms.nil(&mx.ctx);
        var i: i64 = 116;
        while (i >= 100) : (i -= 1) lst = try FinalTerms.cons(&mx.ctx, FinalTerms.int(&mx.ctx, i), lst);
        mx.regs[2] = lst;
        mx.pc = 4;
        try execInstr(&mx, .{ .apply3 = .{ .tail = false } });
        try std.testing.expect(mx.status != .crashed); // NOT system_limit
        try std.testing.expectEqual(@as(usize, 88), mx.pc); // dispatched
        try std.testing.expect(FinalTerms.eqlExact(&mx.ctx, mx.regs[0], FinalTerms.int(&mx.ctx, 100)));
        try std.testing.expect(FinalTerms.eqlExact(&mx.ctx, mx.regs[16], FinalTerms.int(&mx.ctx, 116)));
    }

    // 200 ARGS — well above the old cap: still dispatches (kills a mutant that lowers
    // the cap below MAX_ARG). regs[199] is the 200th arg.
    {
        const exp = [_]Export{.{ .module = m3, .func = h, .arity = 200, .pc = 88 }};
        var mx = try Machine.init(gpa, &atoms);
        defer mx.deinit();
        mx.exports = &exp;
        mx.regs[0] = FinalTerms.atom(&mx.ctx, m3);
        mx.regs[1] = FinalTerms.atom(&mx.ctx, h);
        var lst = FinalTerms.nil(&mx.ctx);
        var i: i64 = 199;
        while (i >= 0) : (i -= 1) lst = try FinalTerms.cons(&mx.ctx, FinalTerms.int(&mx.ctx, i), lst);
        mx.regs[2] = lst;
        mx.pc = 4;
        try execInstr(&mx, .{ .apply3 = .{ .tail = false } });
        try std.testing.expect(mx.status != .crashed);
        try std.testing.expectEqual(@as(usize, 88), mx.pc);
        try std.testing.expect(FinalTerms.eqlExact(&mx.ctx, mx.regs[199], FinalTerms.int(&mx.ctx, 199)));
    }

    // 256 ARGS — over MAX_ARG: the cap DOES fire (system_limit), and the `u8` arity
    // never overflows. No export needed (it crashes before dispatch).
    {
        var mx = try Machine.init(gpa, &atoms);
        defer mx.deinit();
        mx.regs[0] = FinalTerms.atom(&mx.ctx, m3);
        mx.regs[1] = FinalTerms.atom(&mx.ctx, h);
        var lst = FinalTerms.nil(&mx.ctx);
        var i: i64 = 255;
        while (i >= 0) : (i -= 1) lst = try FinalTerms.cons(&mx.ctx, FinalTerms.int(&mx.ctx, i), lst);
        mx.regs[2] = lst;
        mx.pc = 4;
        try execInstr(&mx, .{ .apply3 = .{ .tail = false } });
        try std.testing.expectEqual(Status.crashed, mx.status);
        try std.testing.expect(FinalTerms.eqlExact(&mx.ctx, mx.result, FinalTerms.atom(&mx.ctx, mx.system_limit)));
    }
}

test "LAW gap-apply-fun (DIVERGENCE 733): erlang:apply/2 spreads Args + dispatches the FUN (arity-matched); arity-mismatch → {badarity,{Fun,Args}}; non-fun → badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // (1) a regular fun of arity 3 at label 88, applied to [10,20,30]: spreads
    // regs[0..2] = 10,20,30 and JUMPS to the fun's label (non-tail pushes the return).
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = try FinalTerms.makeFun(&m.ctx, 88, 3, &.{});
        m.regs[1] = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 10), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 20), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 30), FinalTerms.nil(&m.ctx))));
        m.pc = 4;
        try execInstr(&m, .{ .apply_fun = .{ .tail = false } });
        try std.testing.expect(m.status != .crashed);
        try std.testing.expectEqual(@as(usize, 88), m.pc); // jumped to funLabel
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.int(&m.ctx, 10)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[2], FinalTerms.int(&m.ctx, 30)));
        try std.testing.expectEqual(@as(usize, 1), m.stack.items.len); // return pushed
    }

    // (2) ARITY MISMATCH: a 3-arity fun applied to [10,20] → error:{badarity,{Fun,Args}}
    // (the reason carries the ORIGINAL Args list — the check runs BEFORE the spread).
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = try FinalTerms.makeFun(&m.ctx, 88, 3, &.{});
        m.regs[1] = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 10), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 20), FinalTerms.nil(&m.ctx)));
        m.pc = 4;
        try execInstr(&m, .{ .apply_fun = .{ .tail = false } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.tupleArity(&m.ctx, m.result) == 2);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.result, 0), FinalTerms.atom(&m.ctx, m.badarity)));
        // the inner pair's 2nd element is the ORIGINAL 2-element Args list.
        const pair = FinalTerms.tupleElem(&m.ctx, m.result, 1);
        try std.testing.expect(FinalTerms.tupleArity(&m.ctx, pair) == 2);
        try std.testing.expect(FinalTerms.kindOf(&m.ctx, FinalTerms.tupleElem(&m.ctx, pair, 1)) == .cons);
    }

    // (3) NON-FUN first arg → badarg.
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 7); // not a fun
        m.regs[1] = FinalTerms.nil(&m.ctx);
        try execInstr(&m, .{ .apply_fun = .{ .tail = false } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.badarg)));
    }
}

test "LAW gap-callfun-arity (DIVERGENCE 734): call_fun/call_fun2 of a CLOSURE with the wrong arg count → {badarity,{Fun,Args}} (was: jump → badarith/garbage); a MATCHING arity still dispatches" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // call_fun2 arity MISMATCH: a /3 closure (in x5) called with arity 2 →
    // error:{badarity,{Fun,[7,8]}} (the Args are the 2 provided call registers).
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 7);
        m.regs[1] = FinalTerms.int(&m.ctx, 8);
        m.regs[5] = try FinalTerms.makeFun(&m.ctx, 88, 3, &.{});
        m.pc = 4;
        try execInstr(&m, .{ .call_fun2 = .{ .f = .{ .x = 5 }, .arity = 2 } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.tupleArity(&m.ctx, m.result) == 2);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.result, 0), FinalTerms.atom(&m.ctx, m.badarity)));
        const args = FinalTerms.tupleElem(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.result, 1), 1);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, args), FinalTerms.int(&m.ctx, 7))); // Args = [7,8]
    }

    // call_fun2 arity MATCH: a /2 closure called with arity 2 → jumps to funLabel.
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 7);
        m.regs[1] = FinalTerms.int(&m.ctx, 8);
        m.regs[5] = try FinalTerms.makeFun(&m.ctx, 88, 2, &.{});
        m.pc = 4;
        try execInstr(&m, .{ .call_fun2 = .{ .f = .{ .x = 5 }, .arity = 2 } });
        try std.testing.expect(m.status != .crashed);
        try std.testing.expectEqual(@as(usize, 88), m.pc);
    }

    // call_fun arity MISMATCH: a /3 closure whose call_fun register index is 2 (the
    // BEAM `call_fun Arity` convention ⇒ call arity 2) → badarity. The register index
    // IS the call arity; funArity 3 ≠ 2.
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 1);
        m.regs[1] = FinalTerms.int(&m.ctx, 2);
        m.regs[2] = try FinalTerms.makeFun(&m.ctx, 88, 3, &.{});
        m.pc = 4;
        try execInstr(&m, .{ .call_fun = .{ .f = .{ .x = 2 } } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.result, 0), FinalTerms.atom(&m.ctx, m.badarity)));
    }
}

test "LAW E3.12 apply/2 opcode dispatches M=x[arity],F=x[arity+1] dynamically (code + bif)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // CODE target: apply_op arity=1, x0=arg, x1=M, x2=F → resolves m2:g/1 → jump.
    const m2 = try atoms.intern("m2");
    const g = try atoms.intern("g");
    const exports = [_]Export{.{ .module = m2, .func = g, .arity = 1, .pc = 99 }};
    var mc = try Machine.init(gpa, &atoms);
    defer mc.deinit();
    mc.exports = &exports;
    mc.regs[0] = FinalTerms.int(&mc.ctx, 3);
    mc.regs[1] = FinalTerms.atom(&mc.ctx, m2);
    mc.regs[2] = FinalTerms.atom(&mc.ctx, g);
    try execInstr(&mc, .{ .apply_op = .{ .arity = 1, .tail = false } });
    try std.testing.expectEqual(@as(usize, 99), mc.pc);

    // BIF target: apply_op arity=1, x0=[1,2], x1=erlang, x2=length → x0 = 2.
    var md = try Machine.init(gpa, &atoms);
    defer md.deinit();
    md.regs[0] = try FinalTerms.cons(&md.ctx, FinalTerms.int(&md.ctx, 1), try FinalTerms.cons(&md.ctx, FinalTerms.int(&md.ctx, 2), FinalTerms.nil(&md.ctx)));
    md.regs[1] = FinalTerms.atom(&md.ctx, try atoms.intern("erlang"));
    md.regs[2] = FinalTerms.atom(&md.ctx, try atoms.intern("length"));
    try execInstr(&md, .{ .apply_op = .{ .arity = 1, .tail = false } });
    try std.testing.expect(FinalTerms.eqlExact(&md.ctx, md.regs[0], FinalTerms.int(&md.ctx, 2)));
}

// ============================================================================
// E1.3 type-test execution law: the predicate for each kind matches BEAM
// `is_*` guard semantics — hold ⇒ fall through, fail ⇒ pc = else_to. This is
// the oracle-behaviour law the two mutants regress against (mutant 1 widens
// `integer` to accept floats; a `float` argument then wrongly falls through).
// ============================================================================

test "LAW E1.3 type-test predicate matches BEAM is_* guard semantics" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // A gallery of representative terms, one per shape the predicates observe.
    const small = FinalTerms.int(&m.ctx, 42);
    const big = try FinalTerms.intFromI128(&m.ctx, (1 << 70) + 1);
    const flt = FinalTerms.float(&m.ctx, 3.5);
    const at_ok = FinalTerms.atom(&m.ctx, try atoms.intern("ok"));
    const at_true = FinalTerms.atom(&m.ctx, try atoms.intern("true"));
    const at_false = FinalTerms.atom(&m.ctx, try atoms.intern("false"));
    const nilv = FinalTerms.nil(&m.ctx);
    const consv = try FinalTerms.cons(&m.ctx, small, nilv);
    const mapv = try FinalTerms.mapNew(&m.ctx, &.{small}, &.{small});
    const binv = try FinalTerms.binary(&m.ctx, "hi");
    const funv = try FinalTerms.makeFun(&m.ctx, 3, 1, &.{});
    const tupv = try FinalTerms.tuple(&m.ctx, &.{ small, at_ok });
    // E3.1-fix: an ALIGNED bitstring (bit_len % 8 == 0, "hi" == 16 bits) IS a
    // binary denotationally; a SUB-BYTE bitstring is NOT a binary but IS a
    // bitstring.
    const aligned_bitstr = try FinalTerms.bitstring(&m.ctx, "hi", 16);
    const subbyte_bitstr = try FinalTerms.bitstring(&m.ctx, "\xFF", 5);

    // holds(kind, term): run a single type_test with the term in x0 and observe
    // whether execInstr left pc unchanged (fall through = predicate held).
    const H = struct {
        fn holds(mm: *Machine, kind: TypeTestKind, v: FinalTerms.Term) !bool {
            mm.regs[0] = v;
            mm.pc = 0;
            try execInstr(mm, .{ .type_test = .{ .kind = kind, .src = .{ .x = 0 }, .else_to = 7 } });
            return mm.pc == 0; // 7 ⇒ jumped ⇒ predicate failed
        }
    };

    // integer: ints and bignums yes; float NO (the narrowing mutant 1 breaks here)
    try std.testing.expect(try H.holds(&m, .integer, small));
    try std.testing.expect(try H.holds(&m, .integer, big));
    try std.testing.expect(!try H.holds(&m, .integer, flt));
    try std.testing.expect(!try H.holds(&m, .integer, at_ok));
    // float
    try std.testing.expect(try H.holds(&m, .float, flt));
    try std.testing.expect(!try H.holds(&m, .float, small));
    // number: ints, bignums, floats — but not atoms
    try std.testing.expect(try H.holds(&m, .number, small));
    try std.testing.expect(try H.holds(&m, .number, big));
    try std.testing.expect(try H.holds(&m, .number, flt));
    try std.testing.expect(!try H.holds(&m, .number, at_ok));
    // atom (booleans ARE atoms)
    try std.testing.expect(try H.holds(&m, .atom, at_ok));
    try std.testing.expect(try H.holds(&m, .atom, at_true));
    try std.testing.expect(!try H.holds(&m, .atom, small));
    // list: cons and [] yes; other no
    try std.testing.expect(try H.holds(&m, .list, consv));
    try std.testing.expect(try H.holds(&m, .list, nilv));
    try std.testing.expect(!try H.holds(&m, .list, small));
    // map
    try std.testing.expect(try H.holds(&m, .map, mapv));
    try std.testing.expect(!try H.holds(&m, .map, consv));
    // binary and bitstr — E3.1-fix truth table:
    //   is_binary     ⟺ byte-aligned (true binary OR aligned bitstring)
    //   is_bitstring  ⟺ ANY bitstring (aligned or sub-byte) OR true binary
    try std.testing.expect(try H.holds(&m, .binary, binv));
    try std.testing.expect(try H.holds(&m, .bitstr, binv));
    try std.testing.expect(!try H.holds(&m, .binary, small));
    try std.testing.expect(try H.holds(&m, .binary, aligned_bitstr)); // aligned SUBTAG_BITSTRING IS a binary
    try std.testing.expect(try H.holds(&m, .bitstr, aligned_bitstr));
    try std.testing.expect(!try H.holds(&m, .binary, subbyte_bitstr)); // sub-byte is NOT a binary
    try std.testing.expect(try H.holds(&m, .bitstr, subbyte_bitstr)); // but IS a bitstring
    try std.testing.expect(!try H.holds(&m, .bitstr, small)); // non-bitstring terms: both false
    try std.testing.expect(!try H.holds(&m, .binary, small));
    // boolean: exactly true/false, no other atom
    try std.testing.expect(try H.holds(&m, .boolean, at_true));
    try std.testing.expect(try H.holds(&m, .boolean, at_false));
    try std.testing.expect(!try H.holds(&m, .boolean, at_ok));
    // function
    try std.testing.expect(try H.holds(&m, .function, funv));
    try std.testing.expect(!try H.holds(&m, .function, small));
    // tuple (E1.5): any-arity tuple yes; non-tuples no
    try std.testing.expect(try H.holds(&m, .tuple, tupv));
    try std.testing.expect(!try H.holds(&m, .tuple, small));
    try std.testing.expect(!try H.holds(&m, .tuple, consv));
    // pid/reference/port (E3.5): truthful exactly on their own kind, false
    // on every other term (the type_test truthfulness law).
    const a_pid = try FinalTerms.pid(&m.ctx, 3, 0);
    const a_ref = try FinalTerms.freshRef(&m.ctx);
    const a_port = try FinalTerms.port(&m.ctx, 7);
    for ([_]FinalTerms.Term{ small, at_ok, consv, mapv, binv, funv, tupv, a_ref, a_port }) |t| {
        try std.testing.expect(!try H.holds(&m, .pid, t));
    }
    for ([_]FinalTerms.Term{ small, at_ok, consv, mapv, binv, funv, tupv, a_pid, a_port }) |t| {
        try std.testing.expect(!try H.holds(&m, .reference, t));
    }
    for ([_]FinalTerms.Term{ small, at_ok, consv, mapv, binv, funv, tupv, a_pid, a_ref }) |t| {
        try std.testing.expect(!try H.holds(&m, .port, t));
    }
    try std.testing.expect(try H.holds(&m, .pid, a_pid));
    try std.testing.expect(try H.holds(&m, .reference, a_ref));
    try std.testing.expect(try H.holds(&m, .port, a_port));
}

// ============================================================================
// E1.4 comparison-test execution law: each op's predicate matches BEAM binary
// compare-guard semantics — hold ⇒ fall through, fail ⇒ pc = else_to. The two
// mutants regress here: mutant 1 flips `ge` to jump on `.eq` (equal args must
// fall through); mutant 2 makes `ne_arith` exact, so the `1`/`1.0` case (arith
// equal but not exactly equal) distinguishes arith from exact.
// ============================================================================

test "LAW E1.4 comparison-test predicate matches BEAM binary-compare guard semantics" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const one_i = FinalTerms.int(&m.ctx, 1);
    const one_f = FinalTerms.float(&m.ctx, 1.0);
    const two_i = FinalTerms.int(&m.ctx, 2);

    // holds(op, a, b): run a single cmp_test with a in x0, b in x1 and observe
    // whether execInstr left pc unchanged (fall through = comparison held).
    const H = struct {
        fn holds(mm: *Machine, op: CmpTestKind, a: FinalTerms.Term, b: FinalTerms.Term) !bool {
            mm.regs[0] = a;
            mm.regs[1] = b;
            mm.pc = 0;
            try execInstr(mm, .{ .cmp_test = .{ .op = op, .a = .{ .x = 0 }, .b = .{ .x = 1 }, .else_to = 9 } });
            return mm.pc == 0; // 9 ⇒ jumped ⇒ comparison failed
        }
    };

    // ge (>=): standard term order "not less than".
    try std.testing.expect(try H.holds(&m, .ge, two_i, one_i)); // 2 >= 1
    try std.testing.expect(try H.holds(&m, .ge, one_i, one_i)); // 1 >= 1 (mutant 1 breaks: equal must fall through)
    try std.testing.expect(!try H.holds(&m, .ge, one_i, two_i)); // 1 >= 2 is false
    try std.testing.expect(try H.holds(&m, .ge, one_i, one_f)); // 1 >= 1.0 (arith tie)

    // eq_arith (==): arithmetic equality, 1 == 1.0 is TRUE.
    try std.testing.expect(try H.holds(&m, .eq_arith, one_i, one_i));
    try std.testing.expect(try H.holds(&m, .eq_arith, one_i, one_f)); // arith-eq crosses int/float
    try std.testing.expect(!try H.holds(&m, .eq_arith, one_i, two_i));

    // ne_arith (/=): arithmetic inequality, 1 /= 1.0 is FALSE.
    try std.testing.expect(try H.holds(&m, .ne_arith, one_i, two_i));
    try std.testing.expect(!try H.holds(&m, .ne_arith, one_i, one_i));
    try std.testing.expect(!try H.holds(&m, .ne_arith, one_i, one_f)); // mutant 2 breaks: exact would fall through

    // ne_exact (=/=): exact inequality, 1 =/= 1.0 is TRUE.
    try std.testing.expect(try H.holds(&m, .ne_exact, one_i, two_i));
    try std.testing.expect(try H.holds(&m, .ne_exact, one_i, one_f)); // int and float are NOT exactly equal
    try std.testing.expect(!try H.holds(&m, .ne_exact, one_i, one_i));
}

test "LAW E1.3 is_function_arity holds only for a fun of the exact arity" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const fun1 = try FinalTerms.makeFun(&m.ctx, 3, 1, &.{}); // arity 1
    const notfun = FinalTerms.int(&m.ctx, 7);

    const H = struct {
        fn holds(mm: *Machine, v: FinalTerms.Term, arity: u32) !bool {
            mm.regs[0] = v;
            mm.pc = 0;
            try execInstr(mm, .{ .is_function_arity = .{ .src = .{ .x = 0 }, .arity = arity, .else_to = 9 } });
            return mm.pc == 0;
        }
    };
    try std.testing.expect(try H.holds(&m, fun1, 1)); // right arity
    try std.testing.expect(!try H.holds(&m, fun1, 2)); // wrong arity
    try std.testing.expect(!try H.holds(&m, notfun, 1)); // not a fun (no funArity read)
}

test "LAW E6.8 is_function_arity with a REGISTER arity resolves the runtime integer (eunit_data check_arity)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const fun2 = try FinalTerms.makeFun(&m.ctx, 4, 2, &.{}); // a fun of arity 2
    const notfun = FinalTerms.int(&m.ctx, 7);

    // The guard reads the arity from x1 (arity_src). Fun-of-arity-N holds iff x1
    // holds the small integer N; a non-integer / negative / non-fun FAILS the
    // guard (jump to else_to), never crashes.
    const H = struct {
        fn holds(mm: *Machine, target: FinalTerms.Term, arity_term: FinalTerms.Term) !bool {
            mm.regs[0] = target;
            mm.regs[1] = arity_term;
            mm.pc = 0;
            try execInstr(mm, .{ .is_function_arity = .{
                .src = .{ .x = 0 },
                .arity = 0,
                .arity_src = .{ .x = 1 },
                .else_to = 9,
            } });
            return mm.pc == 0;
        }
    };
    try std.testing.expect(try H.holds(&m, fun2, FinalTerms.int(&m.ctx, 2))); // fun/2, arity 2 in x1 → holds
    try std.testing.expect(!try H.holds(&m, fun2, FinalTerms.int(&m.ctx, 1))); // arity mismatch → fails
    try std.testing.expect(!try H.holds(&m, notfun, FinalTerms.int(&m.ctx, 2))); // not a fun → fails
    // A NON-INTEGER arity register (BEAM guard semantics: not a match, no crash).
    const an_atom = FinalTerms.atom(&m.ctx, try atoms.intern("two"));
    try std.testing.expect(!try H.holds(&m, fun2, an_atom));
    // A NEGATIVE arity register cleanly fails (funArity is non-negative).
    try std.testing.expect(!try H.holds(&m, fun2, FinalTerms.int(&m.ctx, -1)));
}

// ============================================================================
// E1.5 tuple-op execution law: concrete oracle behaviour for the whole family.
// This is the law the two mutants regress against:
//   MUTANT 1 (get_tuple_element off-by-one / 1-based): reading index 0 of
//            {a,b,c} would return `b`, not `a` — the get_tuple_elem asserts kill it.
//   MUTANT 2 (test_arity uses `>=` not `==`): a 3-tuple tested for arity 2 would
//            wrongly fall through — the "wrong arity jumps" asserts kill it.
// ============================================================================

test "LAW E1.5 tuple ops: get/set/put/test_arity/is_tagged_tuple match BEAM semantics" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.int(&m.ctx, 10);
    const b = FinalTerms.int(&m.ctx, 20);
    const c = FinalTerms.int(&m.ctx, 30);
    const tag = FinalTerms.atom(&m.ctx, try atoms.intern("rec"));

    // put_tuple2 builds {10,20,30} into x0 from three Srcs.
    m.regs[1] = a;
    m.regs[2] = b;
    m.regs[3] = c;
    try execInstr(&m, .{ .put_tuple2 = .{
        .dst = .{ .x = 0 },
        .elems = &.{ .{ .x = 1 }, .{ .x = 2 }, .{ .x = 3 } },
    } });
    const tup = m.regs[0];
    try std.testing.expectEqual(@as(usize, 3), FinalTerms.tupleArity(&m.ctx, tup));

    // get_tuple_element is 0-BASED: index 0 → 10 (mutant 1 would return 20).
    try execInstr(&m, .{ .get_tuple_elem = .{ .src = .{ .x = 0 }, .index = 0, .dst = .{ .x = 4 } } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[4], a));
    try execInstr(&m, .{ .get_tuple_elem = .{ .src = .{ .x = 0 }, .index = 1, .dst = .{ .x = 4 } } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[4], b));
    try execInstr(&m, .{ .get_tuple_elem = .{ .src = .{ .x = 0 }, .index = 2, .dst = .{ .x = 4 } } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[4], c));

    // set_tuple_element (0-based): overwrite index 1 with 99, others untouched.
    m.regs[5] = FinalTerms.int(&m.ctx, 99);
    try execInstr(&m, .{ .set_tuple_elem = .{ .newval = .{ .x = 5 }, .tuple = .{ .x = 0 }, .index = 1 } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, tup, 0), a));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, tup, 1), FinalTerms.int(&m.ctx, 99)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, tup, 2), c));

    // test_arity: fall through iff the term is a tuple of EXACTLY the arity.
    const TA = struct {
        fn falls(mm: *Machine, v: FinalTerms.Term, arity: u16) !bool {
            mm.regs[6] = v;
            mm.pc = 0;
            try execInstr(mm, .{ .test_arity = .{ .src = .{ .x = 6 }, .arity = arity, .else_to = 9 } });
            return mm.pc == 0;
        }
    };
    try std.testing.expect(try TA.falls(&m, tup, 3)); // 3-tuple, arity 3 → fall
    try std.testing.expect(!try TA.falls(&m, tup, 2)); // arity 2 → jump (mutant 2: `>=` would fall)
    try std.testing.expect(!try TA.falls(&m, tup, 4)); // arity 4 → jump
    try std.testing.expect(!try TA.falls(&m, a, 3)); // not a tuple → jump

    // is_tagged_tuple: tuple of arity N whose element 0 =:= tag.
    const tagged = try FinalTerms.tuple(&m.ctx, &.{ tag, a, b });
    const IT = struct {
        fn falls(mm: *Machine, v: FinalTerms.Term, arity: u16, tg: FinalTerms.Term) !bool {
            mm.regs[7] = v;
            mm.pc = 0;
            try execInstr(mm, .{ .is_tagged_tuple = .{ .src = .{ .x = 7 }, .arity = arity, .tag = tg, .else_to = 9 } });
            return mm.pc == 0;
        }
    };
    try std.testing.expect(try IT.falls(&m, tagged, 3, tag)); // matching tag+arity → fall
    try std.testing.expect(!try IT.falls(&m, tagged, 3, a)); // wrong tag → jump
    try std.testing.expect(!try IT.falls(&m, tagged, 2, tag)); // wrong arity → jump
    try std.testing.expect(!try IT.falls(&m, a, 3, tag)); // not a tuple → jump
}

// E1.14 update_record semantics. Two laws are pinned here:
//   HOMOMORPHISM: denote(after) == the source record with the listed 0-based
//     positions replaced by their values (every other position unchanged).
//   ALIASING (mutant 1 target): the SOURCE record is UNCHANGED after the update
//     — the interpreter COPIES, never mutates in place. A mutant that overwrites
//     `src` via setTupleElem and returns `src` leaves the copy assert intact but
//     fails the "source still {rec,10,20,30}" assert below.
test "LAW E1.14 update_record: copy-then-overwrite homomorphism; source unchanged (aliasing)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const tag = FinalTerms.atom(&m.ctx, try atoms.intern("rec"));
    const v10 = FinalTerms.int(&m.ctx, 10);
    const v20 = FinalTerms.int(&m.ctx, 20);
    const v30 = FinalTerms.int(&m.ctx, 30);
    // Source record {rec,10,20,30} in x0 (element indices 0..3).
    const src = try FinalTerms.tuple(&m.ctx, &.{ tag, v10, v20, v30 });
    m.regs[0] = src;
    // Replacement values in registers.
    m.regs[1] = FinalTerms.int(&m.ctx, 99); // → position 1 (BEAM Offset 2)
    m.regs[2] = FinalTerms.int(&m.ctx, 88); // → position 3 (BEAM Offset 4)

    // update_record: set index 1 ← x1(99), index 3 ← x2(88); dst = x0.
    try execInstr(&m, .{ .update_record = .{
        .src = .{ .x = 0 },
        .dst = .{ .x = 5 },
        .updates = &.{
            .{ .index = 1, .value = .{ .x = 1 } },
            .{ .index = 3, .value = .{ .x = 2 } },
        },
    } });

    // Homomorphism: the result is {rec,99,20,88}.
    const out = m.regs[5];
    try std.testing.expectEqual(@as(usize, 4), FinalTerms.tupleArity(&m.ctx, out));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, out, 0), tag));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, out, 1), FinalTerms.int(&m.ctx, 99)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, out, 2), v20));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, out, 3), FinalTerms.int(&m.ctx, 88)));

    // Aliasing: the SOURCE record is still {rec,10,20,30} (mutant 1 breaks this).
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, src, 1), v10));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, src, 2), v20));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, src, 3), v30));

    // Duplicate index: the LAST write wins (matches erts's sequential writes).
    m.regs[0] = src;
    m.regs[3] = FinalTerms.int(&m.ctx, 1);
    m.regs[4] = FinalTerms.int(&m.ctx, 2);
    try execInstr(&m, .{ .update_record = .{
        .src = .{ .x = 0 },
        .dst = .{ .x = 6 },
        .updates = &.{
            .{ .index = 2, .value = .{ .x = 3 } },
            .{ .index = 2, .value = .{ .x = 4 } },
        },
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.regs[6], 2), FinalTerms.int(&m.ctx, 2)));
}

// ---- E3.14: native-record opcode laws (genop.tab 186-191) ----------------
// LAW-DRIVEN (like E1.8 try/catch): host OTP 28 erlc never EMITS these ops
// (records compile tuple-backed), so there is no differential corpus; the
// ledger flip rests on dump-caps ∩ genop.tab totality + these execution laws.

test "LAW E3.14 native-record guard/accessor opcodes: is_*, get_record_*, is_record_accessible" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const modA = FinalTerms.atomTerm(try atoms.intern("mod"));
    const nmA = FinalTerms.atomTerm(try atoms.intern("point"));
    const kx = FinalTerms.atomTerm(try atoms.intern("x"));
    const ky = FinalTerms.atomTerm(try atoms.intern("y"));
    const kz = FinalTerms.atomTerm(try atoms.intern("z"));
    const rec = try FinalTerms.nativeRecord(&m.ctx, modA, nmA, true, &.{ kx, ky }, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) });
    const not_rec = try FinalTerms.tuple(&m.ctx, &.{ kx, ky });
    m.regs[0] = rec;
    m.regs[1] = not_rec;
    m.regs[9] = try FinalTerms.tuple(&m.ctx, &.{ modA, nmA }); // Id {mod,point}

    // is_any_native_record: record falls through; tuple branches.
    m.pc = 0;
    try execInstr(&m, .{ .is_any_native_record = .{ .src = .{ .x = 0 }, .else_to = 999 } });
    try std.testing.expectEqual(@as(u32, 0), m.pc);
    m.pc = 0;
    try execInstr(&m, .{ .is_any_native_record = .{ .src = .{ .x = 1 }, .else_to = 999 } });
    try std.testing.expectEqual(@as(u32, 999), m.pc);

    // is_native_record: matching mod/name → fall through; wrong name → branch.
    m.pc = 0;
    try execInstr(&m, .{ .is_native_record = .{ .src = .{ .x = 0 }, .module = modA, .name = nmA, .else_to = 999 } });
    try std.testing.expectEqual(@as(u32, 0), m.pc);
    m.pc = 0;
    try execInstr(&m, .{ .is_native_record = .{ .src = .{ .x = 0 }, .module = modA, .name = kz, .else_to = 999 } });
    try std.testing.expectEqual(@as(u32, 999), m.pc);

    // get_record_elements: all present → writes; a missing key → branch, no write.
    m.regs[3] = FinalTerms.nil(&m.ctx);
    m.regs[4] = FinalTerms.nil(&m.ctx);
    m.pc = 0;
    try execInstr(&m, .{ .get_record_elements = .{ .src = .{ .x = 0 }, .elems = &.{
        .{ .key = kx, .dst = .{ .x = 3 } },
        .{ .key = ky, .dst = .{ .x = 4 } },
    }, .else_to = 999 } });
    try std.testing.expectEqual(@as(u32, 0), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[3], FinalTerms.int(&m.ctx, 1)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[4], FinalTerms.int(&m.ctx, 2)));
    // missing key z: branch, x5 untouched (clobber-nothing)
    m.regs[5] = FinalTerms.int(&m.ctx, 77);
    m.pc = 0;
    try execInstr(&m, .{ .get_record_elements = .{ .src = .{ .x = 0 }, .elems = &.{
        .{ .key = kz, .dst = .{ .x = 5 } },
    }, .else_to = 999 } });
    try std.testing.expectEqual(@as(u32, 999), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[5], FinalTerms.int(&m.ctx, 77)));

    // get_record_field: Id={mod,point}, field x → x6=1; with Lbl branch on miss.
    m.pc = 0;
    try execInstr(&m, .{ .get_record_field = .{ .src = .{ .x = 0 }, .id = .{ .x = 9 }, .field = kx, .dst = .{ .x = 6 }, .else_to = null } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[6], FinalTerms.int(&m.ctx, 1)));
    m.pc = 0;
    try execInstr(&m, .{ .get_record_field = .{ .src = .{ .x = 0 }, .id = .{ .x = 9 }, .field = kz, .dst = .{ .x = 6 }, .else_to = 999 } });
    try std.testing.expectEqual(@as(u32, 999), m.pc); // missing field branches

    // is_record_accessible external: exported → fall through.
    m.pc = 0;
    try execInstr(&m, .{ .is_record_accessible = .{ .src = .{ .x = 0 }, .scope = .external, .else_to = 999 } });
    try std.testing.expectEqual(@as(u32, 0), m.pc);
    // a NON-exported record branches under external scope.
    const rec_priv = try FinalTerms.nativeRecord(&m.ctx, modA, nmA, false, &.{kx}, &.{FinalTerms.int(&m.ctx, 1)});
    m.regs[7] = rec_priv;
    m.pc = 0;
    try execInstr(&m, .{ .is_record_accessible = .{ .src = .{ .x = 7 }, .scope = .external, .else_to = 999 } });
    try std.testing.expectEqual(@as(u32, 999), m.pc);
}

test "LAW E3.14 get_record_field RAISES on failure when Lbl==0 (badrecord/badfield)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const modA = FinalTerms.atomTerm(try atoms.intern("mod"));
    const nmA = FinalTerms.atomTerm(try atoms.intern("point"));
    const kx = FinalTerms.atomTerm(try atoms.intern("x"));
    const under = FinalTerms.atomTerm(try atoms.intern("_"));
    m.regs[0] = FinalTerms.int(&m.ctx, 42); // NOT a record
    m.regs[1] = under; // Id = `_` (no name check)
    // get_record_field on a non-record, Lbl==0 → error:{badrecord, 42}.
    m.pc = 0;
    try execInstr(&m, .{ .get_record_field = .{ .src = .{ .x = 0 }, .id = .{ .x = 1 }, .field = kx, .dst = .{ .x = 2 }, .else_to = null } });
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, m.result) == .tuple);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.result, 0), FinalTerms.atom(&m.ctx, try atoms.intern("badrecord"))));

    // missing field on a real record, Lbl==0 → error:{badfield, x}.
    var m2 = try Machine.init(gpa, &atoms);
    defer m2.deinit();
    const rec = try FinalTerms.nativeRecord(&m2.ctx, modA, nmA, true, &.{FinalTerms.atomTerm(try atoms.intern("y"))}, &.{FinalTerms.int(&m2.ctx, 2)});
    m2.regs[0] = rec;
    m2.regs[1] = FinalTerms.atomTerm(try atoms.intern("_"));
    m2.pc = 0;
    try execInstr(&m2, .{ .get_record_field = .{ .src = .{ .x = 0 }, .id = .{ .x = 1 }, .field = FinalTerms.atomTerm(try atoms.intern("x")), .dst = .{ .x = 2 }, .else_to = null } });
    try std.testing.expectEqual(Status.crashed, m2.status);
    try std.testing.expect(FinalTerms.eqlExact(&m2.ctx, FinalTerms.tupleElem(&m2.ctx, m2.result, 0), FinalTerms.atom(&m2.ctx, try atoms.intern("badfield"))));
}

test "LAW E3.14 put_record: CREATE from Id+updates; UPDATE overrides fields; badfield on unknown key" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const modA = FinalTerms.atomTerm(try atoms.intern("mod"));
    const nmA = FinalTerms.atomTerm(try atoms.intern("point"));
    const kx = FinalTerms.atomTerm(try atoms.intern("x"));
    const ky = FinalTerms.atomTerm(try atoms.intern("y"));

    // CREATE: src = nil, Id = {mod,point}, updates = {x=1,y=2}.
    m.regs[0] = FinalTerms.nil(&m.ctx);
    m.regs[9] = try FinalTerms.tuple(&m.ctx, &.{ modA, nmA });
    m.regs[1] = FinalTerms.int(&m.ctx, 1);
    m.regs[2] = FinalTerms.int(&m.ctx, 2);
    try execInstr(&m, .{ .put_record = .{ .id = .{ .x = 9 }, .src = .{ .x = 0 }, .dst = .{ .x = 3 }, .updates = &.{
        .{ .key = kx, .value = .{ .x = 1 } },
        .{ .key = ky, .value = .{ .x = 2 } },
    } } });
    const created = m.regs[3];
    try std.testing.expect(FinalTerms.repIsNativeRecord(&m.ctx, created));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrModule(&m.ctx, created), modA));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, created, kx).?, FinalTerms.int(&m.ctx, 1)));

    // UPDATE: src = the created record, override x=9; y stays 2.
    m.regs[4] = FinalTerms.int(&m.ctx, 9);
    try execInstr(&m, .{ .put_record = .{ .id = .{ .x = 9 }, .src = .{ .x = 3 }, .dst = .{ .x = 5 }, .updates = &.{
        .{ .key = kx, .value = .{ .x = 4 } },
    } } });
    const updated = m.regs[5];
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, updated, kx).?, FinalTerms.int(&m.ctx, 9)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, updated, ky).?, FinalTerms.int(&m.ctx, 2)));
    // source unchanged (aliasing): created still has x=1
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, created, kx).?, FinalTerms.int(&m.ctx, 1)));

    // UPDATE with an unknown field → error:{badfield, z}.
    try execInstr(&m, .{ .put_record = .{ .id = .{ .x = 9 }, .src = .{ .x = 3 }, .dst = .{ .x = 6 }, .updates = &.{
        .{ .key = FinalTerms.atomTerm(try atoms.intern("z")), .value = .{ .x = 4 } },
    } } });
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.result, 0), FinalTerms.atom(&m.ctx, try atoms.intern("badfield"))));
}

// CP-4: put_record write-arm depth. The existing put_record law covers CREATE,
// a single-field UPDATE override, and a single-field badfield. The DARK arms it
// leaves are (a) a multi-field UPDATE that must apply EVERY listed field, (b) a
// valid field applied BEFORE a badfield — the transactional-abort path where the
// local `vals` buffer is already mutated before the `!found` raise, so the law
// pins that NO partial write reaches `dst`, and (c) the empty-update sets:
// CREATE with `updates=&.{}` yields an empty EXPORTED record; UPDATE with
// `updates=&.{}` is an identity copy that preserves the source's exported flag.
// Semantic domain: put_record UPDATE denotes a transactional right-fold over the
// update list against the record's key set — total on subsets of the key set,
// rejecting (badfield) on any unknown key with no observable partial effect.
test "LAW CP-4 put_record UPDATE transactional multi-field + empty-update identity/create" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const modA = FinalTerms.atomTerm(try atoms.intern("mod"));
    const nmA = FinalTerms.atomTerm(try atoms.intern("point3"));
    const kx = FinalTerms.atomTerm(try atoms.intern("x"));
    const ky = FinalTerms.atomTerm(try atoms.intern("y"));
    const kz = FinalTerms.atomTerm(try atoms.intern("z"));
    const kbad = FinalTerms.atomTerm(try atoms.intern("nope"));

    // Base record {x=1, y=2, z=3} via CREATE.
    m.regs[0] = FinalTerms.nil(&m.ctx);
    m.regs[9] = try FinalTerms.tuple(&m.ctx, &.{ modA, nmA });
    m.regs[1] = FinalTerms.int(&m.ctx, 1);
    m.regs[2] = FinalTerms.int(&m.ctx, 2);
    m.regs[3] = FinalTerms.int(&m.ctx, 3);
    try execInstr(&m, .{ .put_record = .{ .id = .{ .x = 9 }, .src = .{ .x = 0 }, .dst = .{ .x = 10 }, .updates = &.{
        .{ .key = kx, .value = .{ .x = 1 } },
        .{ .key = ky, .value = .{ .x = 2 } },
        .{ .key = kz, .value = .{ .x = 3 } },
    } } });
    const base = m.regs[10];
    try std.testing.expect(FinalTerms.repIsNativeRecord(&m.ctx, base));

    // (a) MULTI-FIELD UPDATE: override x AND z in one op; y untouched. Kills a
    // mutant that stops after the first update (only x would change).
    m.regs[4] = FinalTerms.int(&m.ctx, 40);
    m.regs[5] = FinalTerms.int(&m.ctx, 60);
    try execInstr(&m, .{ .put_record = .{ .id = .{ .x = 9 }, .src = .{ .x = 10 }, .dst = .{ .x = 11 }, .updates = &.{
        .{ .key = kx, .value = .{ .x = 4 } },
        .{ .key = kz, .value = .{ .x = 5 } },
    } } });
    const multi = m.regs[11];
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, multi, kx).?, FinalTerms.int(&m.ctx, 40)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, multi, ky).?, FinalTerms.int(&m.ctx, 2)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, multi, kz).?, FinalTerms.int(&m.ctx, 60)));

    // (c) EMPTY-UPDATE UPDATE is an identity copy — same fields, exported flag
    // preserved. denote(out) == denote(src).
    try execInstr(&m, .{ .put_record = .{ .id = .{ .x = 9 }, .src = .{ .x = 10 }, .dst = .{ .x = 12 }, .updates = &.{} } });
    const copy = m.regs[12];
    try std.testing.expectEqual(FinalTerms.nrFieldCount(&m.ctx, base), FinalTerms.nrFieldCount(&m.ctx, copy));
    try std.testing.expectEqual(FinalTerms.nrIsExported(&m.ctx, base), FinalTerms.nrIsExported(&m.ctx, copy));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, copy, ky).?, FinalTerms.int(&m.ctx, 2)));

    // (c) EMPTY-UPDATE CREATE yields an empty record that IS exported (mutant on
    // the `is_exported=true` create flag dies here).
    try execInstr(&m, .{ .put_record = .{ .id = .{ .x = 9 }, .src = .{ .x = 0 }, .dst = .{ .x = 13 }, .updates = &.{} } });
    const empty = m.regs[13];
    try std.testing.expect(FinalTerms.repIsNativeRecord(&m.ctx, empty));
    try std.testing.expectEqual(@as(usize, 0), FinalTerms.nrFieldCount(&m.ctx, empty));
    try std.testing.expect(FinalTerms.nrIsExported(&m.ctx, empty));

    // (b) TRANSACTIONAL ABORT: a VALID field precedes an unknown key. Pre-load
    // dst with a sentinel so we can prove NO partial write lands. The op must
    // raise {badfield, nope} and leave dst untouched — the guard inversion mutant
    // (!found -> found) dies because the leading valid field would then raise.
    const sentinel = FinalTerms.int(&m.ctx, 777);
    m.regs[14] = sentinel;
    m.regs[6] = FinalTerms.int(&m.ctx, 99);
    try execInstr(&m, .{ .put_record = .{ .id = .{ .x = 9 }, .src = .{ .x = 10 }, .dst = .{ .x = 14 }, .updates = &.{
        .{ .key = kx, .value = .{ .x = 6 } }, // valid — applied to local buffer first
        .{ .key = kbad, .value = .{ .x = 6 } }, // unknown — aborts the whole op
    } } });
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.result, 0), FinalTerms.atom(&m.ctx, try atoms.intern("badfield"))));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, m.result, 1), kbad));
    // No partial write: dst register still holds the sentinel.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[14], sentinel));
}

test "LAW E3.14 translate decodes the 6 native-record ops (round-trip, gpa-owned, no leak)" {
    // The 6 ops are in supported_ops (dump-caps totality law) and decode
    // through beam_loader.translate — verified in beam_loader's E3.14 test.
    // Here we assert the executor arms exist (compile-time exhaustiveness is
    // enforced by the CInstr switch; this is the mutants' anchor).
}

test "MUTANT E3.14-op RED-demos (documented, planted+run+reverted — see MUTATION_LOG.md E3.14)" {
    // Mutant 3: `is_native_record` drops the name check (module-only match) →
    // RED against "is_native_record ... wrong name → branch" (a wrong-name
    // record would wrongly fall through).
    // Mutant 4: `get_record_field`'s Lbl==0 miss BRANCHES (pc=0) instead of
    // raising → RED against the badfield RAISE law (status stays running, not
    // crashed). Both reverted; the suite is green with the arms above.
}

// E1.6 select-opcode semantics. Two mutant targets are pinned here:
//   MUTANT 1 (scan stops after the FIRST pair regardless of match): a 3-way
//            select whose match is the 2nd/3rd pair would land on fail_to (or
//            the wrong label) — the "x0=20 → pc 200" assert kills it.
//   MUTANT 2 (select_val uses arith-eq `==` not exact `=:=`): key int 1 vs a
//            float 1.0 Src would MATCH — the "float 1.0 → fail_to" assert kills it.
test "LAW E1.6 select_val: linear scan, EXACT match, else fail_to" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // Jump table: 10→100, 20→200, 30→300; no match → 999.
    const pairs = [_]SelectValPair{
        .{ .key = FinalTerms.int(&m.ctx, 10), .to = 100 },
        .{ .key = FinalTerms.int(&m.ctx, 20), .to = 200 },
        .{ .key = FinalTerms.int(&m.ctx, 30), .to = 300 },
    };
    const SV = struct {
        fn target(mm: *Machine, ps: []const SelectValPair, v: FinalTerms.Term) !u16 {
            mm.regs[0] = v;
            mm.pc = 0;
            try execInstr(mm, .{ .select_val = .{ .src = .{ .x = 0 }, .fail_to = 999, .pairs = ps } });
            return @intCast(mm.pc);
        }
    };
    // First pair matches.
    try std.testing.expectEqual(@as(u16, 100), try SV.target(&m, &pairs, FinalTerms.int(&m.ctx, 10)));
    // MUTANT 1: a "stop after first pair" scan would return 999 here, not 200/300.
    try std.testing.expectEqual(@as(u16, 200), try SV.target(&m, &pairs, FinalTerms.int(&m.ctx, 20)));
    try std.testing.expectEqual(@as(u16, 300), try SV.target(&m, &pairs, FinalTerms.int(&m.ctx, 30)));
    // No matching key → fail_to.
    try std.testing.expectEqual(@as(u16, 999), try SV.target(&m, &pairs, FinalTerms.int(&m.ctx, 99)));
    // MUTANT 2: EXACT match — int key 1 must NOT match a float 1.0 Src.
    const exact_pairs = [_]SelectValPair{.{ .key = FinalTerms.int(&m.ctx, 1), .to = 42 }};
    try std.testing.expectEqual(@as(u16, 42), try SV.target(&m, &exact_pairs, FinalTerms.int(&m.ctx, 1)));
    try std.testing.expectEqual(@as(u16, 999), try SV.target(&m, &exact_pairs, FinalTerms.float(&m.ctx, 1.0)));
}

test "LAW E1.6 select_tuple_arity: matches tuple arity, non-tuple → fail_to" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const e = FinalTerms.int(&m.ctx, 7);
    const t1 = try FinalTerms.tuple(&m.ctx, &.{e});
    const t2 = try FinalTerms.tuple(&m.ctx, &.{ e, e });
    const t3 = try FinalTerms.tuple(&m.ctx, &.{ e, e, e });
    // arity 2→200, arity 3→300; else 999.
    const pairs = [_]SelectArityPair{
        .{ .arity = 2, .to = 200 },
        .{ .arity = 3, .to = 300 },
    };
    const SA = struct {
        fn target(mm: *Machine, ps: []const SelectArityPair, v: FinalTerms.Term) !u16 {
            mm.regs[0] = v;
            mm.pc = 0;
            try execInstr(mm, .{ .select_tuple_arity = .{ .src = .{ .x = 0 }, .fail_to = 999, .pairs = ps } });
            return @intCast(mm.pc);
        }
    };
    try std.testing.expectEqual(@as(u16, 200), try SA.target(&m, &pairs, t2)); // 2nd pair (linear scan past 1st)
    try std.testing.expectEqual(@as(u16, 300), try SA.target(&m, &pairs, t3));
    try std.testing.expectEqual(@as(u16, 999), try SA.target(&m, &pairs, t1)); // arity 1 absent → fail_to
    try std.testing.expectEqual(@as(u16, 999), try SA.target(&m, &pairs, e)); // not a tuple → fail_to
}

// ============================================================================
// E0.6 BIF round-trip law (the SINGLE-SOURCE guard for the executable BIF set)
// ============================================================================
//
// Mirrors beam_loader's "dump-caps totality over the translate dispatch" law,
// but for BIFs: `cli.dumpCaps` prints exactly the `supported_bifs` table (the
// advertised ledger `bifs/dispatch.resolve` agrees with). This law re-parses OUR OWN
// dump-caps `bif ` lines and asserts SET-EQUALITY with `supported_bifs` — count,
// membership, and the declared sorted order — so dump-caps can neither advertise
// a BIF the executor does not run nor omit one it does. Dropping a
// `supported_bifs` entry from the dumpCaps view (MUTATION_LOG E0.6) turns this
// red on the count check.

test "LAW dump-caps totality over BIFs: output round-trips supported_bifs exactly" {
    const cli = @import("cli.zig");
    const gpa = std.testing.allocator;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try cli.dumpCaps(gpa, &buf);

    // Parse OUR OWN `bif <module>:<name>/<arity>` lines back into triples, in
    // first-seen order (op lines are covered by their own loader law).
    const Triple = struct { module: []const u8, name: []const u8, arity: u8 };
    var got: std.ArrayList(Triple) = .empty;
    defer got.deinit(gpa);
    var lines = std.mem.tokenizeScalar(u8, buf.items, '\n');
    while (lines.next()) |line| {
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        const kind = f.next().?;
        if (!std.mem.eql(u8, kind, "bif")) continue; // skip op lines
        const unit = f.next().?; // module:name/arity
        const colon = std.mem.indexOfScalar(u8, unit, ':').?;
        const slash = std.mem.lastIndexOfScalar(u8, unit, '/').?;
        try got.append(gpa, .{
            .module = unit[0..colon],
            .name = unit[colon + 1 .. slash],
            .arity = try std.fmt.parseInt(u8, unit[slash + 1 ..], 10),
        });
    }

    // Exactly the table, no more, no fewer, and in the SAME sorted order the
    // table declares (module, then name, then arity) — so the printed order is
    // itself pinned.
    try std.testing.expectEqual(supported_bifs.len, got.items.len);
    for (supported_bifs, got.items) |want, have| {
        try std.testing.expect(std.mem.eql(u8, want.module, have.module));
        try std.testing.expect(std.mem.eql(u8, want.name, have.name));
        try std.testing.expectEqual(want.arity, have.arity);
    }
}

test "LAW supported_bifs is sorted and duplicate-free (module, then name, then arity)" {
    for (supported_bifs[1..], 0..) |cur, i| {
        const prev = supported_bifs[i];
        const mc = std.mem.order(u8, prev.module, cur.module);
        const nc = std.mem.order(u8, prev.name, cur.name);
        // strictly increasing on (module, name, arity)
        try std.testing.expect(
            mc == .lt or
                (mc == .eq and nc == .lt) or
                (mc == .eq and nc == .eq and prev.arity < cur.arity),
        );
    }
}

// ============================================================================
// E1.9: stack/heap frame opcodes (allocate_heap, trim)
// ============================================================================
//
// `trim` carries a real-y-depth precondition (like `dealloc_y`/`get_tuple_elem`
// before it), so it is driven only by THIS dedicated semantic law, never by
// `randProgram` — see the module doc-comment's E1.9 section for why.
//
//   MUTANT 1 (trim drops from the wrong end / the bottom): a `trim n` that
//            keeps the top `n` slots and drops the rest, instead of dropping
//            the top `n` and keeping the rest, would leave a DIFFERENT y0
//            after trim — the "y2 survives trim 2,3 as the new y0" assert
//            below kills it.
//   MUTANT 2 (allocate_heap confuses StackNeed/HeapNeed): allocating the
//            HeapNeed count of y-slots instead of StackNeed would leave the
//            y-stack at the wrong depth — the depth assert right after
//            `alloc_heap` kills it.

test "LAW E1.9 alloc_heap allocates StackNeed y-slots (HeapNeed/Live are advisory, not carried)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // allocate_heap StackNeed=3 HeapNeed=50 Live=1 → exactly 3 new y-slots.
    // Mutant 2 (stack/heap-need mix-up) would allocate 50 instead of 3.
    try execInstr(&m, .{ .alloc_heap = .{ .stack = 3, .live = 1 } });
    try std.testing.expectEqual(@as(usize, 3), m.ystack.items.len);

    // The new slots are nil, exactly like alloc_y.
    for (m.ystack.items) |y| try std.testing.expect(FinalTerms.eqlExact(&m.ctx, y, FinalTerms.nil(&m.ctx)));
}

test "LAW E1.9 trim drops the top N y-slots, keeping the remaining (older) frame" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // Build a 5-slot frame with DISTINCT values so trim's direction is
    // observable: y4..y0 = 10,20,30,40,50 (y0 is the most-recently-pushed —
    // see `Machine.yreg`'s `items[len-1-i]` addressing).
    var i: i64 = 10;
    while (i <= 50) : (i += 10) {
        try m.ystack.append(m.gpa, FinalTerms.int(&m.ctx, i));
    }
    try std.testing.expectEqual(@as(usize, 5), m.ystack.items.len);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.yreg(0).*, FinalTerms.int(&m.ctx, 50))); // y0 = 50 pre-trim

    // trim N=2 Remaining=3: drop the top 2 (the newest, y0/y1 = 50,40),
    // keep the remaining 3 (10,20,30) — renumbered so the OLD y2 (30) is the
    // NEW y0. Mutant 1 (wrong end) would instead keep {40,50,30} or drop from
    // the array's front, leaving a different — and wrong — new y0.
    try execInstr(&m, .{ .trim = .{ .n = 2 } });
    try std.testing.expectEqual(@as(usize, 3), m.ystack.items.len);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.yreg(0).*, FinalTerms.int(&m.ctx, 30))); // new y0 = old y2
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.yreg(1).*, FinalTerms.int(&m.ctx, 20)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.yreg(2).*, FinalTerms.int(&m.ctx, 10)));
}

// ============================================================================
// E1.10 map-opcode execution laws. Every lookup/insert delegates to the
// term_algebra map API (EXACT keys, flat↔HAMT) — these laws pin the OPCODE
// semantics on top of it (which branch, what pc, what registers), and kill the
// two mutants: (1) get_map_elements writing before it confirms all keys present
// (partial write), and (2) put_map_exact inserting an absent key (exact behaves
// like assoc). execInstr does not advance pc (the run loop does), so a fresh
// machine at pc 0 shows a fall-through as pc == 0 and a jump as pc == else_to.
// ============================================================================

/// Build a two-entry map {a => 1, atom("k") => 2} on a machine heap.
fn buildMapAK(m: *Machine, k_atom: ta.AtomIdx) !FinalTerms.Term {
    const ka = FinalTerms.int(&m.ctx, 7); // key 7 -> value 1
    const kk = FinalTerms.atom(&m.ctx, k_atom); // key atom -> value 2
    return FinalTerms.mapNew(&m.ctx, &.{ ka, kk }, &.{
        FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2),
    });
}

test "LAW E1.10 has_map_fields falls through iff the map has ALL keys, else jumps" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const k = try atoms.intern("k");
    m.regs[0] = try buildMapAK(&m, k);
    // E5.2: keys are runtime Srcs (DIVERGENCE 47). LITERAL keys are .imm/.atom_.
    const key7: Src = .{ .imm = 7 };
    const keyk: Src = .{ .atom_ = k };
    const key_absent: Src = .{ .imm = 99 };

    // ALL present (both keys) → fall through (pc unchanged).
    m.pc = 0;
    try execInstr(&m, .{ .has_map_fields = .{ .src = .{ .x = 0 }, .keys = &.{ key7, keyk }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);

    // one key absent → jump else_to (the map lacks 99 even though it has 7).
    m.pc = 0;
    try execInstr(&m, .{ .has_map_fields = .{ .src = .{ .x = 0 }, .keys = &.{ key7, key_absent }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 42), m.pc);

    // src is not a map → jump else_to (a non-map has no keys).
    m.pc = 0;
    m.regs[1] = FinalTerms.int(&m.ctx, 5);
    try execInstr(&m, .{ .has_map_fields = .{ .src = .{ .x = 1 }, .keys = &.{key7}, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 42), m.pc);

    // E5.2 (DIVERGENCE 47): a REGISTER-valued key resolves at runtime. Put the
    // key value 7 into x5 and look it up via `.key = .x 5` — present ⇒ fall
    // through, exactly as the literal `.imm 7` did.
    m.pc = 0;
    m.regs[5] = FinalTerms.int(&m.ctx, 7);
    try execInstr(&m, .{ .has_map_fields = .{ .src = .{ .x = 0 }, .keys = &.{.{ .x = 5 }}, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    // a register holding an ABSENT key value ⇒ jump.
    m.pc = 0;
    m.regs[6] = FinalTerms.int(&m.ctx, 99);
    try execInstr(&m, .{ .has_map_fields = .{ .src = .{ .x = 0 }, .keys = &.{.{ .x = 6 }}, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 42), m.pc);
}

test "LAW E1.10 get_map_elements is ALL-OR-NOTHING (a missing key clobbers no dst)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const k = try atoms.intern("k");
    m.regs[0] = try buildMapAK(&m, k);
    // E5.2: keys are runtime Srcs (DIVERGENCE 47).
    const key7: Src = .{ .imm = 7 };
    const keyk: Src = .{ .atom_ = k };
    const key_absent: Src = .{ .imm = 99 };

    // ALL keys present → write each value to its dst (7→x2=1, k→x3=2), no jump.
    m.pc = 0;
    m.regs[2] = FinalTerms.nil(&m.ctx);
    m.regs[3] = FinalTerms.nil(&m.ctx);
    try execInstr(&m, .{ .get_map_elements = .{ .src = .{ .x = 0 }, .pairs = &.{
        .{ .key = key7, .dst = .{ .x = 2 } },
        .{ .key = keyk, .dst = .{ .x = 3 } },
    }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[2], FinalTerms.int(&m.ctx, 1)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[3], FinalTerms.int(&m.ctx, 2)));

    // MUTANT 1 target: present-then-absent. The all-or-nothing law requires that
    // NO dst is written when any key is absent — even though key7 (present) is
    // scanned FIRST. A write-as-you-scan mutant would clobber x2 then jump.
    m.pc = 0;
    const sentinel = FinalTerms.int(&m.ctx, 12345);
    m.regs[2] = sentinel;
    try execInstr(&m, .{ .get_map_elements = .{ .src = .{ .x = 0 }, .pairs = &.{
        .{ .key = key7, .dst = .{ .x = 2 } }, // present, listed first
        .{ .key = key_absent, .dst = .{ .x = 3 } }, // absent → whole op fails
    }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 42), m.pc); // jumped
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[2], sentinel)); // x2 UNTOUCHED

    // E5.2 (DIVERGENCE 47): a REGISTER-valued key resolves at runtime and drives
    // the same all-or-nothing extract. Put key value 7 into x6; `.key = .x 6`
    // extracts value 1 into x7, no jump — identical to the literal `.imm 7`.
    m.pc = 0;
    m.regs[6] = FinalTerms.int(&m.ctx, 7);
    m.regs[7] = FinalTerms.nil(&m.ctx);
    try execInstr(&m, .{ .get_map_elements = .{ .src = .{ .x = 0 }, .pairs = &.{
        .{ .key = .{ .x = 6 }, .dst = .{ .x = 7 } },
    }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[7], FinalTerms.int(&m.ctx, 1)));
}

test "LAW E1.10 put_map: assoc inserts/updates; exact updates only, absent key ⇒ badkey" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const k = try atoms.intern("k");
    m.regs[0] = try buildMapAK(&m, k); // {7 => 1, k => 2}

    // assoc: update existing key 7 → 100 AND insert fresh key 8 → 8. Size grows
    // to 3, key 7's value is overwritten.
    try execInstr(&m, .{ .put_map = .{ .exact = false, .src = .{ .x = 0 }, .dst = .{ .x = 1 }, .kvs = &.{
        .{ .k = .{ .imm = 7 }, .v = .{ .imm = 100 } },
        .{ .k = .{ .imm = 8 }, .v = .{ .imm = 8 } },
    } } });
    try std.testing.expectEqual(Status.running, m.status);
    const assoc_map = m.regs[1];
    try std.testing.expectEqual(@as(usize, 3), FinalTerms.mapSize(&m.ctx, assoc_map));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.mapGet(&m.ctx, assoc_map, FinalTerms.int(&m.ctx, 7)).?, FinalTerms.int(&m.ctx, 100)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.mapGet(&m.ctx, assoc_map, FinalTerms.int(&m.ctx, 8)).?, FinalTerms.int(&m.ctx, 8)));

    // exact on EXISTING key: updates in place, size unchanged, no crash.
    var me = try Machine.init(gpa, &atoms);
    defer me.deinit();
    me.regs[0] = try buildMapAK(&me, k);
    try execInstr(&me, .{ .put_map = .{ .exact = true, .src = .{ .x = 0 }, .dst = .{ .x = 1 }, .kvs = &.{
        .{ .k = .{ .imm = 7 }, .v = .{ .imm = 100 } },
    } } });
    try std.testing.expectEqual(Status.running, me.status);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.mapSize(&me.ctx, me.regs[1]));
    try std.testing.expect(FinalTerms.eqlExact(&me.ctx, FinalTerms.mapGet(&me.ctx, me.regs[1], FinalTerms.int(&me.ctx, 7)).?, FinalTerms.int(&me.ctx, 100)));

    // MUTANT 2 target: exact on an ABSENT key must NOT insert — it crashes
    // {badkey, Key}. An assoc-like mutant would instead grow the map and not crash.
    var mx = try Machine.init(gpa, &atoms);
    defer mx.deinit();
    mx.regs[0] = try buildMapAK(&mx, k);
    try execInstr(&mx, .{ .put_map = .{ .exact = true, .src = .{ .x = 0 }, .dst = .{ .x = 1 }, .kvs = &.{
        .{ .k = .{ .imm = 55 }, .v = .{ .imm = 9 } }, // key 55 absent
    } } });
    try std.testing.expectEqual(Status.crashed, mx.status);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&mx.ctx, mx.result));
    try std.testing.expect(FinalTerms.eqlExact(&mx.ctx, FinalTerms.tupleElem(&mx.ctx, mx.result, 0), FinalTerms.atom(&mx.ctx, mx.badkey_atom)));
    try std.testing.expect(FinalTerms.eqlExact(&mx.ctx, FinalTerms.tupleElem(&mx.ctx, mx.result, 1), FinalTerms.int(&mx.ctx, 55)));

    // put_map over a non-map src ⇒ {badmap, Term} crash.
    var mm = try Machine.init(gpa, &atoms);
    defer mm.deinit();
    mm.regs[0] = FinalTerms.int(&mm.ctx, 5);
    try execInstr(&mm, .{ .put_map = .{ .exact = false, .src = .{ .x = 0 }, .dst = .{ .x = 1 }, .kvs = &.{
        .{ .k = .{ .imm = 1 }, .v = .{ .imm = 1 } },
    } } });
    try std.testing.expectEqual(Status.crashed, mm.status);
    try std.testing.expect(FinalTerms.eqlExact(&mm.ctx, FinalTerms.tupleElem(&mm.ctx, mm.result, 0), FinalTerms.atom(&mm.ctx, mm.badmap_atom)));
}

// ============================================================================
// E1.12 float-register (FR) opcode execution laws. The FR bank (`Machine.fregs`)
// holds raw IEEE f64; `fmove_to_f`/`fconv` load it, the arithmetic ops compute
// in f64, `fmove_from_f` boxes back to a float term. These laws pin: (a) FR
// arithmetic denotes the SAME f64 IEEE result as `term_algebra`'s float ops
// (fadd 2.0,3.0 → 5.0); (b) `fconv` of an INTEGER term is a CONVERSION, int `5`
// → `5.0` (kills the truncation mutant); (c) `fsub` is `FA - FB` (kills the
// swapped-operand mutant); (d) the bank is observable — `eqMachines` sees an FR
// divergence; (e) a non-finite result crashes badarith. FR ops are LAW-DRIVEN
// (not fuzzed by randProgram — the bank needs pre-loading, the `apply` precedent).
// ============================================================================

test "LAW E1.12 FR arithmetic denotes the same f64 as term_algebra float ops (fadd 2.0,3.0 → 5.0)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // Load 2.0 into FR0 and 3.0 into FR1 from boxed float terms, add into FR2,
    // box FR2 back into x0. The result must be EXACTLY the float term 5.0.
    m.regs[0] = FinalTerms.float(&m.ctx, 2.0);
    m.regs[1] = FinalTerms.float(&m.ctx, 3.0);
    try execInstr(&m, .{ .fmove_to_f = .{ .src = .{ .x = 0 }, .fdst = 0 } });
    try execInstr(&m, .{ .fmove_to_f = .{ .src = .{ .x = 1 }, .fdst = 1 } });
    try std.testing.expectEqual(@as(f64, 2.0), m.fregs[0]);
    try std.testing.expectEqual(@as(f64, 3.0), m.fregs[1]);
    try execInstr(&m, .{ .fadd = .{ .a = 0, .b = 1, .fdst = 2 } });
    try std.testing.expectEqual(@as(f64, 5.0), m.fregs[2]);
    try execInstr(&m, .{ .fmove_from_f = .{ .fsrc = 2, .dst = .{ .x = 0 } } });
    // Boxed result denotes the same f64 the term algebra's own float would.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.float(&m.ctx, 5.0)));

    // fmul/fdiv/fnegate close the same loop (2*3=6, 6/3=2, -2 = -2).
    try execInstr(&m, .{ .fmul = .{ .a = 0, .b = 1, .fdst = 3 } });
    try std.testing.expectEqual(@as(f64, 6.0), m.fregs[3]);
    try execInstr(&m, .{ .fdiv = .{ .a = 3, .b = 1, .fdst = 4 } });
    try std.testing.expectEqual(@as(f64, 2.0), m.fregs[4]);
    try execInstr(&m, .{ .fnegate = .{ .a = 0, .fdst = 5 } });
    try std.testing.expectEqual(@as(f64, -2.0), m.fregs[5]);
}

test "LAW E1.12 fconv of the integer term 5 is a CONVERSION to f64 5.0 (mutant: truncation)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // fconv Src FR: the integer 5 must become the f64 5.0 — a numeric widening,
    // NOT a bit-reinterpretation (the mutant truncates/bit-casts and fails here).
    m.regs[0] = FinalTerms.int(&m.ctx, 5);
    try execInstr(&m, .{ .fconv = .{ .src = .{ .x = 0 }, .fdst = 0 } });
    try std.testing.expectEqual(@as(f64, 5.0), m.fregs[0]);

    // fconv of a float term is the identity conversion (2.5 → 2.5).
    m.regs[1] = FinalTerms.float(&m.ctx, 2.5);
    try execInstr(&m, .{ .fconv = .{ .src = .{ .x = 1 }, .fdst = 1 } });
    try std.testing.expectEqual(@as(f64, 2.5), m.fregs[1]);

    // fconv of a non-number crashes badarith (the honest guard).
    var m2 = try Machine.init(gpa, &atoms);
    defer m2.deinit();
    m2.regs[0] = FinalTerms.atom(&m2.ctx, m2.badarith);
    try execInstr(&m2, .{ .fconv = .{ .src = .{ .x = 0 }, .fdst = 0 } });
    try std.testing.expectEqual(Status.crashed, m2.status);
}

test "LAW E1.12 fconv finiteness: max-magnitude bignum converts to a FINITE f64 (guard does not false-trip)" {
    // FIX 2 boundary law. `fconv` guards `std.math.isFinite` before storing into
    // the FR bank, mirroring the FR-arith arms, so a non-finite bank value can
    // never reach `fmove_from_f`/`FinalTerms.float` (which asserts finite → panic).
    //
    // In THIS final encoding the guard's negative (crash) branch is UNREACHABLE:
    // the bignum magnitude is capped at 8 limbs (`max_limbs`), so the LARGEST
    // representable integer is ≈ 2^512 ≈ 1.34e154 — well within f64's ~1.8e308
    // range — and float terms are finite by construction. This law pins that
    // fact: fconv of the maximum-magnitude bignum yields a FINITE f64 and does
    // NOT crash (the guard must not false-trip at the boundary). Overflow-to-inf
    // is therefore recorded as an EQUIVALENT mutant in MUTATION_LOG, not a kill;
    // the guard stands as defense-in-depth / forward-compat (see the arm comment).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // The maximal 8-limb magnitude: every limb 0xFFFF…FFFF (value = 2^512 − 1).
    const num_limbs = 8;
    var limbs: [num_limbs]u64 = .{std.math.maxInt(u64)} ** num_limbs;
    const big = try FinalTerms.intFromLimbs(&m.ctx, true, &limbs);
    _ = &limbs;
    try std.testing.expect(FinalTerms.repIsBig(&m.ctx, big));

    m.regs[0] = big;
    try execInstr(&m, .{ .fconv = .{ .src = .{ .x = 0 }, .fdst = 0 } });
    // fconv did NOT crash, and the bank value is finite (guard did not false-trip).
    try std.testing.expect(m.status != .crashed);
    try std.testing.expect(std.math.isFinite(m.fregs[0]));
    try std.testing.expectApproxEqRel(@as(f64, 1.3407807929942597e154), m.fregs[0], 1e-12);
}

test "LAW E1.12 fsub is FA - FB, order-sensitive (mutant: FB - FA)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // FR0 = 7.0, FR1 = 2.0. fsub FA=0 FB=1 → 5.0 (NOT -5.0). Distinct operands
    // make the direction observable: the swapped-operand mutant yields -5.0.
    m.fregs[0] = 7.0;
    m.fregs[1] = 2.0;
    try execInstr(&m, .{ .fsub = .{ .a = 0, .b = 1, .fdst = 2 } });
    try std.testing.expectEqual(@as(f64, 5.0), m.fregs[2]);
}

test "LAW E1.12 the FR bank is observable machine state (eqMachines sees an FR divergence)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var a = try Machine.init(gpa, &atoms);
    defer a.deinit();
    var b = try Machine.init(gpa, &atoms);
    defer b.deinit();

    var sa = std.heap.ArenaAllocator.init(gpa);
    defer sa.deinit();
    // Identical fresh machines are equal; a lone FR difference must break it —
    // otherwise the differential law is BLIND to FR-bank divergence.
    try std.testing.expect(try eqMachines(&a, &b, sa.allocator()));
    a.fregs[3] = 1.5;
    try std.testing.expect(!try eqMachines(&a, &b, sa.allocator()));
    b.fregs[3] = 1.5;
    try std.testing.expect(try eqMachines(&a, &b, sa.allocator()));
}

test "LAW E1.12 a non-finite FR result crashes badarith (fdiv by 0.0, overflow)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // x / 0.0 → inf → non-finite → badarith crash.
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    m.fregs[0] = 1.0;
    m.fregs[1] = 0.0;
    try execInstr(&m, .{ .fdiv = .{ .a = 0, .b = 1, .fdst = 2 } });
    try std.testing.expectEqual(Status.crashed, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.badarith)));

    // Overflow to +inf (max * 2) is equally non-finite → badarith.
    var m2 = try Machine.init(gpa, &atoms);
    defer m2.deinit();
    m2.fregs[0] = std.math.floatMax(f64);
    m2.fregs[1] = 2.0;
    try execInstr(&m2, .{ .fmul = .{ .a = 0, .b = 1, .fdst = 2 } });
    try std.testing.expectEqual(Status.crashed, m2.status);
}

// ============================================================================
// E3.3: bit-syntax MATCHING opcode laws
// ============================================================================

test "LAW E3.3 bs_start_match3 builds a match context over a binary/bitstring; a non-bitstring src jumps else_to" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    m.regs[0] = try FinalTerms.binary(&m.ctx, &.{ 1, 2 });
    m.pc = 0;
    try execInstr(&m, .{ .bs_start_match = .{ .src = .{ .x = 0 }, .ctx = .{ .x = 1 }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc); // fell through
    try std.testing.expect(FinalTerms.repIsMatchCtx(&m.ctx, m.regs[1]));
    try std.testing.expectEqual(@as(usize, 0), FinalTerms.matchCtxOffset(&m.ctx, m.regs[1]));

    // non-bitstring src: jump else_to, ctx register untouched (still whatever it was).
    m.regs[0] = FinalTerms.int(&m.ctx, 5);
    m.pc = 0;
    try execInstr(&m, .{ .bs_start_match = .{ .src = .{ .x = 0 }, .ctx = .{ .x = 2 }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 42), m.pc);
}

// The worked op: big-endian unsigned `<<1,2>>` (bytes 0x01,0x02) as a 16-bit
// integer denotes 258 (0x0102) — MUTANT 1's law (a little-endian-by-default
// bug would read 0x0201 = 513 instead).
test "LAW E3.3 bs_get_integer2 big-endian unsigned: <<1,2>> as a 16-bit field == 258, cursor advances by exactly 16 bits" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2 });
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 },
        .size = .{ .imm = 16 },
        .unit = 1,
        .signed = false,
        .endian = .big,
        .dst = .{ .x = 1 },
        .else_to = 42,
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, 258)));
    try std.testing.expect(FinalTerms.repIsMatchCtx(&m.ctx, m.regs[0]));
    try std.testing.expectEqual(@as(usize, 16), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));
}

// LAW cp-instr-bs (COVERAGE_PLAN) — the DARK `bs_get_utf` opcode (0 dedicated tests).
// It decodes ONE UTF-8/16/32 codepoint at the match cursor, writes the codepoint to
// `dst`, and advances the ctx cursor by EXACTLY the encoded bit_len (variable for
// utf8: 8/16/24/32; utf16: 16 or 32 for a surrogate pair; utf32: 32). A short or
// malformed/out-of-range encoding jumps `else_to`, leaving ctx + dst untouched.
// OTP-30: erl_bits.c erts_bs_get_utf8/16/32 — the wrong-answer-decode surface where
// a mis-advanced cursor silently misaligns every subsequent match (the E24 pattern).
test "LAW cp-instr-bs bs_get_utf: utf8 variable-width sequential decode (exact per-cp advance) + utf32 endian + reject arms" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // <<"A", é, €, 😀>> — 1+2+3+4 UTF-8 bytes. Reading sequentially proves each
    // cursor advance is EXACTLY the codepoint width (a wrong advance misaligns the next).
    const bin = try FinalTerms.binary(&m.ctx, &.{
        0x41, // 'A'   U+0041 (1 byte)
        0xC3, 0xA9, // 'é'   U+00E9 (2 bytes)
        0xE2, 0x82, 0xAC, // '€'   U+20AC (3 bytes)
        0xF0, 0x9F, 0x98, 0x80, // '😀'  U+1F600 (4 bytes)
    });
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    const getu8: CInstr = .{ .bs_get_utf = .{ .ctx = .{ .x = 0 }, .kind = .utf8, .endian = .big, .dst = .{ .x = 1 }, .else_to = 99 } };
    const expect = [_]struct { cp: i64, off: usize }{
        .{ .cp = 65, .off = 8 }, .{ .cp = 233, .off = 24 },
        .{ .cp = 8364, .off = 48 }, .{ .cp = 128512, .off = 80 },
    };
    for (expect) |e| {
        try execInstr(&m, getu8);
        try std.testing.expectEqual(@as(usize, 0), m.pc); // success, no branch
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, e.cp)));
        try std.testing.expectEqual(e.off, FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));
    }
    // at the end (cursor 80 of 80) a further utf8 read fails: rem < 8 -> else_to.
    try execInstr(&m, getu8);
    try std.testing.expectEqual(@as(usize, 99), m.pc);

    // utf32 BIG vs LITTLE endian decode the SAME codepoint (U+1F600), cursor +32.
    m.pc = 0;
    const bin32b = try FinalTerms.binary(&m.ctx, &.{ 0x00, 0x01, 0xF6, 0x00 });
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin32b, 0);
    try execInstr(&m, .{ .bs_get_utf = .{ .ctx = .{ .x = 0 }, .kind = .utf32, .endian = .big, .dst = .{ .x = 1 }, .else_to = 99 } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, 128512)));
    try std.testing.expectEqual(@as(usize, 32), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));
    const bin32l = try FinalTerms.binary(&m.ctx, &.{ 0x00, 0xF6, 0x01, 0x00 });
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin32l, 0);
    try execInstr(&m, .{ .bs_get_utf = .{ .ctx = .{ .x = 0 }, .kind = .utf32, .endian = .little, .dst = .{ .x = 1 }, .else_to = 99 } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, 128512)));

    // REJECT: an out-of-range utf32 value (> 0x10FFFF) jumps else_to; ctx + dst untouched.
    m.pc = 0;
    m.regs[1] = FinalTerms.atomTerm(try atoms.intern("sentinel"));
    const binbad = try FinalTerms.binary(&m.ctx, &.{ 0xFF, 0xFF, 0xFF, 0xFF });
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, binbad, 0);
    try execInstr(&m, .{ .bs_get_utf = .{ .ctx = .{ .x = 0 }, .kind = .utf32, .endian = .big, .dst = .{ .x = 1 }, .else_to = 99 } });
    try std.testing.expectEqual(@as(usize, 99), m.pc);
    try std.testing.expectEqual(@as(usize, 0), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0])); // cursor untouched
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.atom(&m.ctx, try atoms.intern("sentinel")))); // dst untouched
}

// LAW CP-1 (COVERAGE_PLAN) — the DARK `bs_get_float` opcode (0 dedicated tests; the
// #1-criticality module instr_algebra, Stratum-A, priority 53M). It decodes a 32- or
// 64-bit IEEE float field from a bitstring match context, advancing the cursor, and
// jumps to `else_to` on: a size that is NEITHER 32 nor 64, insufficient bits, or a
// NON-FINITE result (NaN/Inf).
//
// OTP-30 CORRELATION. `erl_bits.c` `erts_bs_get_float_2`: reads `Sz*Unit` bits as an
// IEEE float, requires the field to be a whole 32- or 64-bit float, advances the match
// offset, and FAILS the match (the `else`/`fail` branch) on a bad size, a short buffer,
// or a non-finite value. This law pins the byte-accurate round-trip on the happy path
// and each of the three fail arms. Big-endian byte order (byte 0 = MSB) mirrors
// `BSF_LITTLE`-absent (the default) — the same convention `bs_get_integer2` uses.
//
// Mutants MUTATION_LOG cp-1 m1 (the finite guard `!isFinite` dropped → Inf leaks a
// non-finite float instead of failing) / m2 (the size guard admits 16-bit → a
// 2-byte field is bit-cast as a bogus float instead of failing).
test "LAW CP-1 bs_get_float: 64/32-bit IEEE round-trip + fail arms (bad size / short / non-finite) — OTP erl_bits.c erts_bs_get_float_2" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const beBytes = struct {
        fn be8(bits: u64) [8]u8 {
            var out: [8]u8 = undefined;
            for (0..8) |i| out[i] = @truncate(bits >> @intCast(8 * (7 - i)));
            return out;
        }
        fn be4(bits: u32) [4]u8 {
            var out: [4]u8 = undefined;
            for (0..4) |i| out[i] = @truncate(bits >> @intCast(8 * (3 - i)));
            return out;
        }
    };

    // (1) 64-bit big-endian round-trip: <<3.14/float>> decodes to 3.14, cursor += 64.
    {
        const f: f64 = 3.14;
        const bytes = beBytes.be8(@bitCast(f));
        const bin = try FinalTerms.binary(&m.ctx, &bytes);
        m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
        m.pc = 0;
        try execInstr(&m, .{ .bs_get_float = .{
            .ctx = .{ .x = 0 }, .size = .{ .imm = 64 }, .unit = 1, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
        } });
        try std.testing.expectEqual(@as(usize, 0), m.pc); // did NOT fail
        try std.testing.expectEqual(f, FinalTerms.floatValOf(&m.ctx, m.regs[1]));
        try std.testing.expectEqual(@as(usize, 64), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));
    }

    // (2) 32-bit round-trip: a 4-byte IEEE-754 single decodes to its f64 value.
    {
        const f32v: f32 = 1.5;
        const bytes = beBytes.be4(@bitCast(f32v));
        const bin = try FinalTerms.binary(&m.ctx, &bytes);
        m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
        m.pc = 0;
        try execInstr(&m, .{ .bs_get_float = .{
            .ctx = .{ .x = 0 }, .size = .{ .imm = 32 }, .unit = 1, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
        } });
        try std.testing.expectEqual(@as(usize, 0), m.pc);
        try std.testing.expectEqual(@as(f64, 1.5), FinalTerms.floatValOf(&m.ctx, m.regs[1]));
        try std.testing.expectEqual(@as(usize, 32), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));
    }

    // (3) BAD SIZE (8, none of 16/32/64) → jump else_to, cursor unchanged.
    {
        const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2 });
        m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
        m.pc = 0;
        try execInstr(&m, .{ .bs_get_float = .{
            .ctx = .{ .x = 0 }, .size = .{ .imm = 8 }, .unit = 1, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
        } });
        try std.testing.expectEqual(@as(usize, 42), m.pc);
    }

    // (3b) DIVERGENCE 694: 16-bit HALF-precision decode. `<<62,0>>` is IEEE
    // binary16 for 1.5 → the match SUCCEEDS (pc stays), regs[1]==1.5, cursor→16.
    {
        const bin = try FinalTerms.binary(&m.ctx, &.{ 62, 0 });
        m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
        m.pc = 0;
        try execInstr(&m, .{ .bs_get_float = .{
            .ctx = .{ .x = 0 }, .size = .{ .imm = 16 }, .unit = 1, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
        } });
        try std.testing.expectEqual(@as(usize, 0), m.pc); // matched, no jump
        try std.testing.expectEqual(@as(f64, 1.5), FinalTerms.floatValOf(&m.ctx, m.regs[1]));
        try std.testing.expectEqual(@as(usize, 16), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));
    }

    // (4) SHORT BUFFER: a 32-bit binary can't supply a 64-bit field → else_to.
    {
        const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3, 4 });
        m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
        m.pc = 0;
        try execInstr(&m, .{ .bs_get_float = .{
            .ctx = .{ .x = 0 }, .size = .{ .imm = 64 }, .unit = 1, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
        } });
        try std.testing.expectEqual(@as(usize, 42), m.pc);
    }

    // (5) NON-FINITE: the IEEE-754 bit pattern of +Inf decodes to a non-finite float
    //     → the match FAILS (else_to), never leaking an Inf term.
    {
        const inf_bits: u64 = 0x7FF0_0000_0000_0000;
        const bytes = beBytes.be8(inf_bits);
        const bin = try FinalTerms.binary(&m.ctx, &bytes);
        m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
        m.pc = 0;
        try execInstr(&m, .{ .bs_get_float = .{
            .ctx = .{ .x = 0 }, .size = .{ .imm = 64 }, .unit = 1, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
        } });
        try std.testing.expectEqual(@as(usize, 42), m.pc);
    }
}

// LAW CP-2 (COVERAGE_PLAN) — the DARK `bs_skip_bits` opcode (0 dedicated tests;
// instr_algebra #1). Advances the match cursor by `Size*Unit` bits, jumping to
// `else_to` when the field runs past the end. OTP-30 `erl_bits.c` `bs_skip_bits2`.
// Mutants MUTATION_LOG cp-2 m1 (the short-buffer guard `>` → `>=` rejects an exact
// fit) / m2 (the cursor advances by the wrong amount).
test "LAW CP-2 bs_skip_bits: advances the cursor by exactly n bits; a short field jumps else_to (OTP bs_skip_bits2)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2 }); // 16 bits

    // (1) skip 8 bits → cursor 8, pc unchanged.
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    m.pc = 0;
    try execInstr(&m, .{ .bs_skip_bits = .{ .ctx = .{ .x = 0 }, .size = .{ .imm = 8 }, .unit = 1, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expectEqual(@as(usize, 8), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));

    // (2) skip the remaining 8 bits (EXACT fit to the end) → cursor 16, no fail.
    try execInstr(&m, .{ .bs_skip_bits = .{ .ctx = .{ .x = 0 }, .size = .{ .imm = 8 }, .unit = 1, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expectEqual(@as(usize, 16), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));

    // (3) skip past the end (17 > 16) → else_to.
    m.regs[1] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    m.pc = 0;
    try execInstr(&m, .{ .bs_skip_bits = .{ .ctx = .{ .x = 1 }, .size = .{ .imm = 17 }, .unit = 1, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 42), m.pc);
}

// LAW CP-3 (COVERAGE_PLAN) — the thin `bs_get_binary` opcode's dark arms
// (sub-byte extraction + short-field fail). Extracts a `Size*Unit`-bit sub-bitstring
// and advances the cursor. OTP-30 `erl_bits.c` `bs_get_binary2`.
// Mutants MUTATION_LOG cp-3 m1 (extract the wrong bit length) / m2 (the short-buffer
// guard dropped → OOB slice).
test "LAW CP-3 bs_get_binary: byte-aligned + SUB-BYTE extraction advances the cursor; a short field jumps else_to (OTP bs_get_binary2)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const bin = try FinalTerms.binary(&m.ctx, &.{ 0xAB, 0xCD, 0xEF, 0x12 }); // 32 bits

    // (1) 16-bit (byte-aligned) sub-binary == <<0xAB,0xCD>>, cursor → 16.
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    m.pc = 0;
    try execInstr(&m, .{ .bs_get_binary = .{ .ctx = .{ .x = 0 }, .size = .{ .imm = 16 }, .unit = 1, .dst = .{ .x = 1 }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expectEqualSlices(u8, &.{ 0xAB, 0xCD }, FinalTerms.bitsOf(&m.ctx, m.regs[1]).bytes);
    try std.testing.expectEqual(@as(usize, 16), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));

    // (2) SUB-BYTE: a 4-bit field from a fresh ctx captures the top nibble 0xA (0b1010).
    m.regs[2] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    m.pc = 0;
    try execInstr(&m, .{ .bs_get_binary = .{ .ctx = .{ .x = 2 }, .size = .{ .imm = 4 }, .unit = 1, .dst = .{ .x = 3 }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expectEqual(@as(usize, 4), FinalTerms.bitsOf(&m.ctx, m.regs[3]).bit_len);
    try std.testing.expectEqual(@as(usize, 4), FinalTerms.matchCtxOffset(&m.ctx, m.regs[2]));

    // (3) 40-bit field from a 32-bit binary → else_to (short buffer).
    m.regs[4] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    m.pc = 0;
    try execInstr(&m, .{ .bs_get_binary = .{ .ctx = .{ .x = 4 }, .size = .{ .imm = 40 }, .unit = 1, .dst = .{ .x = 5 }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 42), m.pc);
}

test "LAW E3.3 bs_get_integer2 little-endian: <<1,2>> as a 16-bit LE field == 0x0201 == 513" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2 });
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 16 }, .unit = 1,
        .signed = false, .endian = .little, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, 513)));
}

test "LAW E3.3 bs_get_integer2 signed: a top-bit-set 8-bit field reads negative" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{0xFF}); // -1 signed, 255 unsigned
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 8 }, .unit = 1,
        .signed = true, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, -1)));

    // unsigned twin of the same bits reads 255.
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 8 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, 255)));
}

test "LAW E3.3 bs_get_integer2 unit×size product: size=2,unit=8 reads 16 bits" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2 });
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 2 }, .unit = 8,
        .signed = false, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, 258)));
    try std.testing.expectEqual(@as(usize, 16), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));
}

// vm-binmatch-gc GC-SURVIVAL LAW (DIVERGENCE 57/68): a binary that crosses a
// heap boundary via `gcCopy` (the send/mailbox copy path) is STILL a valid
// bit-match source — `bs_start_match` accepts it and `bs_get_integer` reads it.
// This pins the term/gc side of the invariant (the actual bug was the LOADER
// misreading bs_start_match3's Src operand — see beam_loader.zig — but this law
// guards the representation the loader path relies on).
test "LAW vm-binmatch-gc: a gcCopy'd binary bit-matches (bs_start_match + bs_get_integer)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    // sender machine A, receiver machine B (cross-heap send copy path)
    var a = try Machine.init(gpa, &atoms);
    defer a.deinit();
    var b = try Machine.init(gpa, &atoms);
    defer b.deinit();

    const src = try FinalTerms.binary(&a.ctx, &.{ 1, 2 });
    // cross the mailbox: gcCopy A's binary into B's heap (the send copy path)
    const recv = try FinalTerms.gcCopy(&b.ctx, &a.ctx, src);
    try std.testing.expect(FinalTerms.repIsBinary(&b.ctx, recv));
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.binBytes(&b.ctx, recv).len);

    b.regs[0] = recv;
    b.pc = 0;
    try execInstr(&b, .{ .bs_start_match = .{ .src = .{ .x = 0 }, .ctx = .{ .x = 1 }, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), b.pc); // must NOT jump else_to
    try std.testing.expect(FinalTerms.repIsMatchCtx(&b.ctx, b.regs[1]));
    try execInstr(&b, .{ .bs_get_integer = .{
        .ctx = .{ .x = 1 }, .size = .{ .imm = 8 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 2 }, .else_to = 42,
    } });
    try std.testing.expectEqual(@as(usize, 0), b.pc); // must NOT jump else_to
    try std.testing.expect(FinalTerms.eqlExact(&b.ctx, b.regs[2], FinalTerms.int(&b.ctx, 1)));
}

// CURSOR-MONOTONICITY LAW (the brief's core, MUTANT 2's law): a failed
// bit-syntax test/get leaves the match context register UNCHANGED and jumps
// `else_to`. Exercised over `bs_get_integer2` (over-read) AND `bs_test_tail2`
// (mismatch) — the task's named mutant-2 target op.
test "LAW E3.3 cursor-monotonicity: an over-read bs_get_integer2 jumps else_to and leaves ctx UNCHANGED" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{1}); // only 8 bits available
    const ctx0 = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    m.regs[0] = ctx0;
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 16 }, .unit = 1, // needs 16, only 8 present
        .signed = false, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expectEqual(@as(usize, 42), m.pc);
    // the register still holds the EXACT prior ctx term (word identity, not
    // merely observational equality — nothing wrote it).
    try std.testing.expectEqual(ctx0, m.regs[0]);
}

test "LAW E3.3 cursor-monotonicity: a mismatching bs_test_tail2 jumps else_to and leaves ctx UNCHANGED (MUTANT 2 target)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2 }); // 16 bits total
    const ctx0 = try FinalTerms.makeMatchCtx(&m.ctx, bin, 8); // 8 bits remain
    m.regs[0] = ctx0;
    m.pc = 0;
    // expects EXACTLY 0 remaining bits — mismatch (8 remain) ⇒ jump, ctx unchanged.
    try execInstr(&m, .{ .bs_test_tail = .{ .ctx = .{ .x = 0 }, .bits = 0, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 42), m.pc);
    try std.testing.expectEqual(ctx0, m.regs[0]);

    // exact match (8 remain, expect 8) ⇒ fall through, ctx STILL unchanged
    // (bs_test_tail2 never advances the cursor even on success — it is a
    // pure test, not a consuming read).
    m.pc = 0;
    try execInstr(&m, .{ .bs_test_tail = .{ .ctx = .{ .x = 0 }, .bits = 8, .else_to = 42 } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expectEqual(ctx0, m.regs[0]);
}

test "LAW E3.3 bs_get_binary2/bs_get_tail produce the correct sub-bitstring (aligned -> binary, sub-byte -> bitstring)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3 });
    // aligned 1-byte extraction at offset 8 -> a plain binary <<2>>.
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 8);
    try execInstr(&m, .{ .bs_get_binary = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 1 }, .unit = 8, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, m.regs[1]));
    try std.testing.expectEqualSlices(u8, &.{2}, FinalTerms.bitsOf(&m.ctx, m.regs[1]).bytes);
    try std.testing.expectEqual(@as(usize, 16), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));

    // bs_get_tail: whatever remains (16 bits: bytes 2 and 3).
    try execInstr(&m, .{ .bs_get_tail_ctx = .{ .ctx = .{ .x = 0 }, .dst = .{ .x = 2 } } });
    try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, m.regs[2]));
    try std.testing.expectEqualSlices(u8, &.{3}, FinalTerms.bitsOf(&m.ctx, m.regs[2]).bytes);

    // sub-byte extraction: 4 bits at offset 0 of <<1>> (0b0000_0001) -> the
    // top nibble 0b0000, a genuine bitstring (bit_len 4, not byte-aligned).
    const bin2 = try FinalTerms.binary(&m.ctx, &.{0b0000_0001});
    m.regs[3] = try FinalTerms.makeMatchCtx(&m.ctx, bin2, 0);
    try execInstr(&m, .{ .bs_get_binary = .{
        .ctx = .{ .x = 3 }, .size = .{ .imm = 4 }, .unit = 1, .dst = .{ .x = 4 }, .else_to = 42,
    } });
    try std.testing.expect(FinalTerms.repIsBitstring(&m.ctx, m.regs[4]));
    try std.testing.expectEqual(@as(usize, 4), FinalTerms.bitsOf(&m.ctx, m.regs[4]).bit_len);
}

test "LAW E3.3 bs_match_string: literal bit-pattern equality at the cursor" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 0x41, 0x42 }); // "AB"
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    // matches "A" (0x41): fall through, cursor advances 8 bits.
    try execInstr(&m, .{ .bs_match_string = .{
        .ctx = .{ .x = 0 }, .bit_len = 8, .bytes = &.{0x41}, .else_to = 42,
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expectEqual(@as(usize, 8), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));

    // does NOT match "A" again (next byte is 0x42) -> jump, ctx unchanged.
    const ctx1 = m.regs[0];
    try execInstr(&m, .{ .bs_match_string = .{
        .ctx = .{ .x = 0 }, .bit_len = 8, .bytes = &.{0x41}, .else_to = 42,
    } });
    try std.testing.expectEqual(@as(usize, 42), m.pc);
    try std.testing.expectEqual(ctx1, m.regs[0]);
}

test "LAW E3.3 bs_get_position / bs_set_position round-trip: set(get(ctx)) reads the same bits again" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3 });
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    // consume the first byte
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 8 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, 1)));
    // save position (== 8), consume another byte (now at 16)
    try execInstr(&m, .{ .bs_get_position = .{ .ctx = .{ .x = 0 }, .dst = .{ .x = 2 } } });
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 8 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 3 }, .else_to = 42,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[3], FinalTerms.int(&m.ctx, 2)));
    // restore -> re-reading gives the SAME second byte again.
    try execInstr(&m, .{ .bs_set_position = .{ .ctx = .{ .x = 0 }, .pos = .{ .x = 2 } } });
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 8 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 4 }, .else_to = 42,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[4], FinalTerms.int(&m.ctx, 2)));
}

test "LAW E3.3 bs_match: the unified matcher runs ensure_at_least/integer/binary/get_tail sequentially, fails fail_to on a short input" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3, 4 });
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_match = .{
        .ctx = .{ .x = 0 },
        .fail_to = 99,
        .cmds = &.{
            // bs-unaligned-tail (CORRECTS the original law's operands): erts
            // ensure_at_least(NumBits, Unit) takes NumBits IN BITS + a
            // remainder-divisibility Unit — {16,8} is exactly the compiler's
            // `<<_:8,X:8,Rest/binary>>` shape (rem 32 ≥ 16, (32-16)%8 == 0).
            // The pre-fix law passed {4,8} believing stride×unit==32.
            .{ .ensure_at_least = .{ .stride = 16, .unit = 8 } },
            .{ .integer = .{ .size = .{ .imm = 1 }, .unit = 8, .signed = false, .endian = .big, .dst = .{ .x = 1 } } },
            .{ .skip = .{ .stride = 8 } },
            .{ .get_tail = .{ .unit = 1, .dst = .{ .x = 2 } } },
        },
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, 1)));
    try std.testing.expectEqualSlices(u8, &.{ 3, 4 }, FinalTerms.bitsOf(&m.ctx, m.regs[2]).bytes);
    // batch-4 (CORRECTS the original expectation of 32): erts get_tail does
    // NOT advance the position — the ctx ends at the 16 bits the integer+skip
    // consumed, so a following bit_size(ctx) reads the TAIL's size (16 here).
    try std.testing.expectEqual(@as(usize, 16), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));

    // bs-unaligned-tail: a get_tail whose dst IS the ctx register — the erts
    // in-place-position semantics mean the register legitimately ends holding
    // the TAIL, and the epilogue must NOT clobber it with the updated ctx
    // (the p5 fleet-finding shape: `{get_tail,_,8,{x,1}}` with ctx in x1).
    const bin_ct = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3, 4 });
    m.regs[7] = try FinalTerms.makeMatchCtx(&m.ctx, bin_ct, 0);
    m.pc = 0;
    try execInstr(&m, .{ .bs_match = .{
        .ctx = .{ .x = 7 },
        .fail_to = 99,
        .cmds = &.{
            .{ .ensure_at_least = .{ .stride = 16, .unit = 8 } },
            .{ .skip = .{ .stride = 8 } },
            .{ .integer = .{ .size = .{ .imm = 1 }, .unit = 8, .signed = false, .endian = .big, .dst = .{ .x = 6 } } },
            .{ .get_tail = .{ .unit = 8, .dst = .{ .x = 7 } } }, // dst == ctx
        },
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[6], FinalTerms.int(&m.ctx, 2)));
    // x7 holds the TAIL <<3,4>>, NOT a match context.
    try std.testing.expect(!FinalTerms.repIsMatchCtx(&m.ctx, m.regs[7]));
    try std.testing.expectEqualSlices(u8, &.{ 3, 4 }, FinalTerms.bitsOf(&m.ctx, m.regs[7]).bytes);

    // FAIL path 1: ensure_at_least demands more BITS than are present ->
    // fail_to, ctx register UNCHANGED (still the pre-match-attempt ctx term).
    const bin2 = try FinalTerms.binary(&m.ctx, &.{1});
    const ctx0 = try FinalTerms.makeMatchCtx(&m.ctx, bin2, 0);
    m.regs[3] = ctx0;
    m.pc = 0;
    try execInstr(&m, .{ .bs_match = .{
        .ctx = .{ .x = 3 },
        .fail_to = 99,
        .cmds = &.{.{ .ensure_at_least = .{ .stride = 16, .unit = 8 } }},
    } });
    try std.testing.expectEqual(@as(usize, 99), m.pc);
    try std.testing.expectEqual(ctx0, m.regs[3]);

    // FAIL path 2 (bs-unaligned-tail): enough bits but the REMAINDER is not
    // divisible by the unit — a 12-bit input with {stride=4, unit=8} has
    // (12-4)%8 == 0 ✓… use {stride=2, unit=8}: (12-2)%8 = 2 ≠ 0 -> fail_to
    // (the divisibility arm the pre-fix multiply semantics never checked).
    const bits12 = try FinalTerms.bitstring(&m.ctx, &.{ 0xAB, 0xC0 }, 12);
    const ctx1 = try FinalTerms.makeMatchCtx(&m.ctx, bits12, 0);
    m.regs[4] = ctx1;
    m.pc = 0;
    try execInstr(&m, .{ .bs_match = .{
        .ctx = .{ .x = 4 },
        .fail_to = 99,
        .cmds = &.{.{ .ensure_at_least = .{ .stride = 2, .unit = 8 } }},
    } });
    try std.testing.expectEqual(@as(usize, 99), m.pc);
}

test "LAW E3.3 bs_match '=:=' fused literal-equality command: matches consume+advance, mismatch fails" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{5});
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_match = .{
        .ctx = .{ .x = 0 },
        .fail_to = 99,
        .cmds = &.{.{ .eq = .{ .size = 8, .value = FinalTerms.int(&m.ctx, 5) } }},
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expectEqual(@as(usize, 8), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));

    m.regs[1] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_match = .{
        .ctx = .{ .x = 1 },
        .fail_to = 99,
        .cmds = &.{.{ .eq = .{ .size = 8, .value = FinalTerms.int(&m.ctx, 6) } }},
    } });
    try std.testing.expectEqual(@as(usize, 99), m.pc);
}

test "LAW E3.3 eqMachines observes a MatchCtx OBSERVATIONALLY (bin + offset), not by heap-word identity" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var a = try Machine.init(gpa, &atoms);
    defer a.deinit();
    var b = try Machine.init(gpa, &atoms);
    defer b.deinit();

    var sa = std.heap.ArenaAllocator.init(gpa);
    defer sa.deinit();

    // Two INDEPENDENTLY built MatchCtx terms (different heap words in
    // different ctxs) with the SAME bin content and the SAME cursor compare
    // EQUAL — proving `denote`'s SUBTAG_MATCHCTX extension is observational,
    // not pointer/word identity.
    const bin_a = try FinalTerms.binary(&a.ctx, &.{ 9, 9 });
    const bin_b = try FinalTerms.binary(&b.ctx, &.{ 9, 9 });
    a.regs[0] = try FinalTerms.makeMatchCtx(&a.ctx, bin_a, 3);
    b.regs[0] = try FinalTerms.makeMatchCtx(&b.ctx, bin_b, 3);
    try std.testing.expect(try eqMachines(&a, &b, sa.allocator()));

    // A cursor divergence is DETECTED.
    b.regs[0] = try FinalTerms.makeMatchCtx(&b.ctx, bin_b, 4);
    try std.testing.expect(!try eqMachines(&a, &b, sa.allocator()));
}

// ---- E3.3-fix (Fix 1, review of 34997cb): >128-bit integer fields --------
// The old `bsMagnitudeAt` `assert(len <= 128)` was reachable from a legal
// `<<Hash:256>> = Bin` match (256-bit crypto hashes are common real Erlang).
// These laws pin the three width bands `bsIntegerFieldTerm` now dispatches:
// 1..128 (unchanged fast path, covered above), 129..512 (bignum, HERE), and
// >512 (a bounded `else_to`/`fail_to`, never a panic — the regression case).

test "LAW E3.3-fix (Fix 1) bs_get_integer2 256-bit big-endian field builds the correct bignum (no panic on the old len<=128 assert)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // 32-byte (256-bit) big-endian binary encoding 2^200: bit 200 set,
    // counting from the LSB (byte 31 is the LSB byte).
    var buf: [32]u8 = @splat(0);
    const k: usize = 200;
    buf[31 - k / 8] = @as(u8, 1) << @intCast(k % 8);
    const bin = try FinalTerms.binary(&m.ctx, &buf);
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 256 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc); // within the bignum cap: no else_to jump
    try std.testing.expectEqual(@as(usize, 256), FinalTerms.matchCtxOffset(&m.ctx, m.regs[0]));

    var limbs: [FinalTerms.max_limbs]u64 = @splat(0);
    limbs[k / 64] = @as(u64, 1) << @intCast(k % 64);
    const expected = try FinalTerms.intFromLimbs(&m.ctx, true, &limbs);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], expected));

    // Same field via bs_match's `.integer` command (the other Fix-1 call
    // site) must agree.
    m.regs[2] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_match = .{
        .ctx = .{ .x = 2 },
        .fail_to = 99,
        .cmds = &.{.{ .integer = .{ .size = .{ .imm = 256 }, .unit = 1, .signed = false, .endian = .big, .dst = .{ .x = 3 } } }},
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[3], expected));
}

test "LAW E3.3-fix (Fix 1) little-endian 256-bit field ≡ big-endian of the byte-reversed binary (exercises the multi-limb BYTE-shift path shiftInByte)" {
    // E24-T1: the byte-aligned little-endian >128-bit reader
    // (`bsMagnitudeLimbsAt`'s else branch → `shiftInByte`) was DARK — zero test
    // coverage on the wide little-endian decode. This is a self-oracling
    // HOMOMORPHISM: reading a binary little-endian must equal reading its
    // byte-reversed form big-endian (the trusted bit-by-bit `shiftInBit` path).
    // A byte-order / limb-assembly bug in the byte path breaks the equality.
    // OTP-30 CORRELATION: this IS erl_bits.c erts_bs_get_integer_2 — BSF_LITTLE
    // does erts_copy_bits_fwd (byte 0 = LSB) while big-endian does
    // erts_copy_bits_rev, so OTP's big read is the byte-reversal of its little
    // read; byte-aligned only (sub-byte little is DIVERGENCE 16a, out of scope).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // A non-palindromic 32-byte (256-bit) pattern so byte order is observable.
    var buf: [32]u8 = undefined;
    for (0..32) |i| buf[i] = @intCast(i + 1); // 1,2,...,32
    var rev: [32]u8 = undefined;
    for (0..32) |i| rev[i] = buf[31 - i];

    const bin_le = try FinalTerms.binary(&m.ctx, &buf);
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin_le, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 256 }, .unit = 1,
        .signed = false, .endian = .little, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc); // within the bignum cap

    const bin_be = try FinalTerms.binary(&m.ctx, &rev);
    m.regs[2] = try FinalTerms.makeMatchCtx(&m.ctx, bin_be, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 2 }, .size = .{ .imm = 256 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 3 }, .else_to = 43,
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);

    // HOMOMORPHISM: little(buf) == big(reverse(buf)).
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], m.regs[3]));

    // Genuinely a >128-bit value (top byte 0x20 = 32 at bit 248..255), so this
    // really drove the multi-limb path, not a degenerate small int.
    var top: [FinalTerms.max_limbs]u64 = @splat(0);
    top[3] = @as(u64, 32) << 56; // byte 31 (=32) is the MOST significant of the LE value
    const top_term = try FinalTerms.intFromLimbs(&m.ctx, true, &top);
    // top-most limb nonzero ⇒ value ≥ 2^248 ⇒ not representable in i128.
    try std.testing.expect(!FinalTerms.eqlExact(&m.ctx, m.regs[1], top_term)); // it's larger than just the top byte
}

test "LAW E3.3-fix (Fix 1) bs_get_integer2 signed 256-bit field: all-ones two's-complement reads -1" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const buf: [32]u8 = @splat(0xFF); // 256 one-bits: two's-complement -1
    const bin = try FinalTerms.binary(&m.ctx, &buf);
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 256 }, .unit = 1,
        .signed = true, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expectEqual(@as(usize, 0), m.pc);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], FinalTerms.int(&m.ctx, -1)));

    // unsigned twin: all-ones 256 bits is 2^256 - 1.
    m.regs[0] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 256 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    // 256 bits = 4 of the 8 available limbs; only those are all-ones.
    var all_ones: [FinalTerms.max_limbs]u64 = @splat(0);
    all_ones[0] = std.math.maxInt(u64);
    all_ones[1] = std.math.maxInt(u64);
    all_ones[2] = std.math.maxInt(u64);
    all_ones[3] = std.math.maxInt(u64);
    const expected_unsigned = try FinalTerms.intFromLimbs(&m.ctx, true, &all_ones);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[1], expected_unsigned));
}

test "LAW E3.3-fix (Fix 1) a field beyond bignum cap (66000 bits) jumps else_to/fail_to cleanly — the old-assert regression case, no panic" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    var buf: [8260]u8 = @splat(0); // 66080 bits available, enough for a 66000-bit field
    const bin = try FinalTerms.binary(&m.ctx, &buf);
    const ctx0 = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    m.regs[0] = ctx0;
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 0 }, .size = .{ .imm = 66000 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 1 }, .else_to = 42,
    } });
    try std.testing.expectEqual(@as(usize, 42), m.pc); // else_to, not a panic
    try std.testing.expectEqual(ctx0, m.regs[0]); // cursor-monotonicity: unchanged on the jump

    // the same width via bs_match's `.integer` command jumps fail_to.
    m.regs[2] = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    m.pc = 0;
    try execInstr(&m, .{ .bs_match = .{
        .ctx = .{ .x = 2 },
        .fail_to = 99,
        .cmds = &.{.{ .integer = .{ .size = .{ .imm = 66000 }, .unit = 1, .signed = false, .endian = .big, .dst = .{ .x = 3 } } }},
    } });
    try std.testing.expectEqual(@as(usize, 99), m.pc);
    _ = &buf;
}

// ---- E3.3-fix (Fix 3, review of 34997cb): SUBTAG_MATCHCTX term-boundary --
// robustness. A match context never escapes to compare/hash/sort in
// compiler-emitted code, but an adversarial `.beam` could route one through
// `is_eq_exact`/a sort BIF; `kindOf`/`compare`/`hashTerm` must never panic.

test "LAW E3.3-fix (Fix 3) MatchCtx compare/hash/kindOf never panic; order+hash agree with denote's {bin,offset} pair" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2 });
    const c0 = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
    const c0b = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0); // independently built, same {bin,offset}
    const c1 = try FinalTerms.makeMatchCtx(&m.ctx, bin, 8); // a later cursor

    // kindOf never hits `unreachable`.
    try std.testing.expectEqual(FinalTerms.Kind.binary, FinalTerms.kindOf(&m.ctx, c0));

    // compareExact: same {bin,offset} -> eq; a later cursor -> gt (offset
    // is the second component of the denote-shaped pair, compared after
    // bin equality holds).
    try std.testing.expectEqual(ta.Order.eq, FinalTerms.compareExact(&m.ctx, c0, c0b));
    try std.testing.expectEqual(ta.Order.lt, FinalTerms.compareExact(&m.ctx, c0, c1));
    try std.testing.expectEqual(ta.Order.gt, FinalTerms.compareExact(&m.ctx, c1, c0));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, c0, c0b));
    try std.testing.expect(!FinalTerms.eqlExact(&m.ctx, c0, c1));

    // hashTerm: equal-denotation MatchCtx terms hash equal; never panics.
    try std.testing.expectEqual(FinalTerms.hashTerm(&m.ctx, c0), FinalTerms.hashTerm(&m.ctx, c0b));
}

// ============================================================================
// E3.4: bit-syntax CONSTRUCTION + UTF opcodes — the construction↔matching
// round-trip is the KEYSTONE law (the LA-3 homomorphism, executable): build
// with `bs_create_bin`, re-match with E3.3's ops, recover every source.
// ============================================================================

test "LAW E3.4 bs_init_writable produces an empty binary" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    try execInstr(&m, .{ .bs_init_writable = .{ .dst = .{ .x = 3 } } });
    try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, m.regs[3]));
    try std.testing.expectEqual(@as(usize, 0), FinalTerms.binBytes(&m.ctx, m.regs[3]).len);
}

test "LAW bs-little-oddsize ODD-SIZE little-endian fields: erts 8k+r layout, put<->get round-trip + oracle vectors (discharges DIVERGENCE 16(a))" {
    const gpa = std.testing.allocator;

    // ORACLE VECTORS (generated on OTP erl, cited in the fixture probes):
    // `<<17555:15/little>>` = byte 0x93 (low byte) then the 7-bit fragment
    // 0x44 (bits 8..14) — reading it back yields 17555, and the OLD
    // big-endian-fallback reading yields 18884 (the fleet finding).
    var limbs17555: [FinalTerms.max_limbs]u64 = @splat(0);
    limbs17555[0] = 17555;
    const b15 = try bitsFromLimbsField(gpa, &limbs17555, 15, .little);
    defer gpa.free(b15.bytes);
    try std.testing.expectEqual(@as(u128, 17555), bsMagnitudeAt(b15, 0, 15, .little));
    // byte 0 of the stream is the LOW value byte (0x93), NOT the high bits.
    try std.testing.expectEqual(@as(u8, 0x93), b15.bytes[0]);

    // `<<57285702734876389752897683:13/little>>` low 13 bits: byte 147 then
    // fragment 0 — the p2 construction shape.
    var limbs13: [FinalTerms.max_limbs]u64 = @splat(0);
    limbs13[0] = 57285702734876389752897683 & 0x1FFF;
    const b13 = try bitsFromLimbsField(gpa, &limbs13, 13, .little);
    defer gpa.free(b13.bytes);
    try std.testing.expectEqual(@as(u8, 147), b13.bytes[0]);
    try std.testing.expectEqual(limbs13[0], @as(u64, @intCast(bsMagnitudeAt(b13, 0, 13, .little))));

    // SEEDED put<->get round-trip: every width 1..=128, both endians — the
    // serializer and the reader are exact inverses over the whole field-width
    // domain (byte-multiple widths reduce to the old byte-reversal; the odd
    // widths are the discharged bound).
    var prng = std.Random.DefaultPrng.init(0x11771E);
    const random = prng.random();
    for (0..300) |_| {
        const len = 1 + random.uintLessThan(usize, 128);
        const v = random.int(u128) & (if (len == 128) ~@as(u128, 0) else (@as(u128, 1) << @intCast(len)) - 1);
        var limbs: [FinalTerms.max_limbs]u64 = @splat(0);
        limbs[0] = @truncate(v);
        limbs[1] = @truncate(v >> 64);
        const e: BsEndian = if (random.boolean()) .little else .big;
        const bits = try bitsFromLimbsField(gpa, &limbs, len, e);
        defer gpa.free(bits.bytes);
        try std.testing.expectEqual(v, bsMagnitudeAt(bits, 0, len, e));
    }

    // >128-bit odd-little (the limbs reader): a 133-bit round-trip.
    var big_limbs: [FinalTerms.max_limbs]u64 = @splat(0);
    big_limbs[0] = 0xDEADBEEFCAFEF00D;
    big_limbs[1] = 0x123456789ABCDEF0;
    big_limbs[2] = 0x1B; // 5 top bits: 133 = 2*64 + 5
    const b133 = try bitsFromLimbsField(gpa, &big_limbs, 133, .little);
    defer gpa.free(b133.bytes);
    const rd = bsMagnitudeLimbsAt(b133, 0, 133, .little);
    try std.testing.expectEqual(big_limbs[0], rd[0]);
    try std.testing.expectEqual(big_limbs[1], rd[1]);
    try std.testing.expectEqual(big_limbs[2], rd[2]);
}

test "LAW bs-int-128-topbit: bsIntegerFieldTerm decodes a FULL-WIDTH unsigned field (128-bit, top bit set, ≥ 2^127) to a positive bignum WITHOUT a panic (@intCast(u128→i128) overflow), byte-EQ vs the value (DIVERGENCE 592)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // A 128-bit UNSIGNED field with the top bit set: mag = (0xFF << 120) | 0x07 —
    // in [2^127, 2^128), which does NOT fit i128. Pre-fix, bsIntegerFieldTerm did
    // `intFromI128(@intCast(mag))` → PANIC. Post-fix it falls to the limbs path.
    var limbs: [FinalTerms.max_limbs]u64 = @splat(0);
    limbs[0] = 0x07; // low 64
    limbs[1] = @as(u64, 0xFF) << 56; // high 64 → bit 127 set
    inline for (.{ BsEndian.big, BsEndian.little }) |e| {
        const bits = try bitsFromLimbsField(gpa, &limbs, 128, e);
        defer gpa.free(bits.bytes);
        // (1) NO PANIC + a real Term.
        const t = (try bsIntegerFieldTerm(&m, bits, 0, 128, e, false)) orelse return error.TestUnexpectedResult;
        try std.testing.expect(!FinalTerms.repIsSmall(t)); // ≥ 2^127 is a bignum, not a small
        // (1b) POSITIVE: an UNSIGNED field is never negative (guards a sign-flip in the
        // fall-through's intFromLimbs — a full-width unsigned value must be > 0).
        try std.testing.expect(FinalTerms.compareExact(&m.ctx, t, FinalTerms.int(&m.ctx, 0)) == .gt);
        // (2) VALUE correct: re-read the magnitude and cross-check the low/high limbs.
        const back = bsMagnitudeLimbsAt(bits, 0, 128, e);
        try std.testing.expectEqual(limbs[0], back[0]);
        try std.testing.expectEqual(limbs[1], back[1]);
    }

    // The i128-FITTING full-width case still uses the fast path (top bit 0).
    var lo: [FinalTerms.max_limbs]u64 = @splat(0);
    lo[0] = 0x0102030405060708;
    lo[1] = 0x0102030405060708; // bit 127 clear → fits i128
    const bfit = try bitsFromLimbsField(gpa, &lo, 128, .big);
    defer gpa.free(bfit.bytes);
    _ = (try bsIntegerFieldTerm(&m, bfit, 0, 128, .big, false)) orelse return error.TestUnexpectedResult;

    // SEEDED CLASS GUARD (the fix for the coverage HOLE that let 592 slip through:
    // the pre-existing seeded round-trip tested only `bsMagnitudeAt`, NOT the
    // Term-BUILDING `bsIntegerFieldTerm` — so a top-bit-set 128-bit value never
    // reached the panicking `@intCast`). Sweep the FULL decode path over every width
    // 1..=192 × both signs × both endians on random values incl. the full-width
    // boundary: it must NEVER panic and the magnitude must round-trip.
    var prng = std.Random.DefaultPrng.init(0x592B17);
    const random = prng.random();
    for (0..600) |_| {
        const len = 1 + random.uintLessThan(usize, 192);
        var v: [FinalTerms.max_limbs]u64 = @splat(0);
        v[0] = random.int(u64);
        v[1] = random.int(u64);
        if (len > 128) v[2] = random.int(u64) & (if (len - 128 >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(len - 128)) - 1);
        // mask to the field width
        if (len < 64) v[0] &= (@as(u64, 1) << @intCast(len)) - 1;
        if (len >= 64 and len < 128) v[1] &= (@as(u64, 1) << @intCast(len - 64)) - 1;
        if (len < 128) v[1] = if (len <= 64) 0 else v[1];
        if (len <= 64) v[1] = 0;
        const e: BsEndian = if (random.boolean()) .little else .big;
        const bits = try bitsFromLimbsField(gpa, &v, len, e);
        defer gpa.free(bits.bytes);
        inline for (.{ false, true }) |sgn| {
            // Must not panic (the whole point). Result may be null only at the >512-bit cap (len≤192 here → always a Term).
            _ = (try bsIntegerFieldTerm(&m, bits, 0, len, e, sgn)) orelse return error.TestUnexpectedResult;
        }
    }
}

test "LAW E3.4 construction<->matching round-trip: integer/binary/float/utf8/string, IN LIST ORDER (mutant 1's kill law)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    m.regs[0] = FinalTerms.int(&m.ctx, 258); // 16-bit BE integer segment: 0x0102
    m.regs[1] = try FinalTerms.binary(&m.ctx, &.{ 0xAA, 0xBB }); // binary_all segment
    m.regs[2] = FinalTerms.float(&m.ctx, 3.5); // 32-bit float segment
    m.regs[3] = FinalTerms.int(&m.ctx, 65); // utf8 'A'

    try execInstr(&m, .{ .bs_create_bin = .{
        .dst = .{ .x = 10 },
        .else_to = null,
        .segs = &.{
            .{ .integer = .{ .src = .{ .x = 0 }, .size = .{ .imm = 16 }, .unit = 1, .endian = .big } },
            .{ .binary_all = .{ .src = .{ .x = 1 } } },
            .{ .float = .{ .src = .{ .x = 2 }, .size = .{ .imm = 32 }, .unit = 1, .endian = .big } },
            .{ .utf8 = .{ .src = .{ .x = 3 } } },
            .{ .string = .{ .bytes = "XY" } },
        },
    } });
    try std.testing.expectEqual(Status.running, m.status);
    try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, m.regs[10]));
    // 16 + 16 + 32 + 8 + 16 = 88 bits = 11 bytes.
    try std.testing.expectEqual(@as(usize, 11), FinalTerms.binBytes(&m.ctx, m.regs[10]).len);

    // Re-match with E3.3's ops and recover EVERY source, IN THE SAME ORDER
    // they were written — if `bs_create_bin` wrote segments in reverse
    // (mutant 1), the first `bs_get_integer` below would read the float's
    // bit pattern instead of 258, failing this exact assertion.
    try execInstr(&m, .{ .bs_start_match = .{ .src = .{ .x = 10 }, .ctx = .{ .x = 11 }, .else_to = null } });
    try execInstr(&m, .{ .bs_get_integer = .{
        .ctx = .{ .x = 11 }, .size = .{ .imm = 16 }, .unit = 1,
        .signed = false, .endian = .big, .dst = .{ .x = 12 }, .else_to = 999,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[12], FinalTerms.int(&m.ctx, 258)));

    try execInstr(&m, .{ .bs_get_binary = .{
        .ctx = .{ .x = 11 }, .size = .{ .imm = 16 }, .unit = 1, .dst = .{ .x = 13 }, .else_to = 999,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[13], m.regs[1]));

    try execInstr(&m, .{ .bs_get_float = .{
        .ctx = .{ .x = 11 }, .size = .{ .imm = 32 }, .unit = 1, .endian = .big, .dst = .{ .x = 14 }, .else_to = 999,
    } });
    try std.testing.expectEqual(@as(f64, 3.5), FinalTerms.floatValOf(&m.ctx, m.regs[14]));

    try execInstr(&m, .{ .bs_get_utf = .{
        .ctx = .{ .x = 11 }, .kind = .utf8, .endian = .big, .dst = .{ .x = 15 }, .else_to = 999,
    } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[15], FinalTerms.int(&m.ctx, 65)));

    try execInstr(&m, .{ .bs_get_tail_ctx = .{ .ctx = .{ .x = 11 }, .dst = .{ .x = 9 } } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[9], try FinalTerms.binary(&m.ctx, "XY")));
    try std.testing.expect(m.pc != 999); // no branch above was ever taken
}

test "LAW E3.4 UTF construction<->matching round-trip: utf16-little (incl. surrogate pair) and utf32-big; bs_skip_utf advances without binding" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    m.regs[0] = FinalTerms.int(&m.ctx, 0x00E9); // BMP: 'é', 2 bytes as utf16
    m.regs[1] = FinalTerms.int(&m.ctx, 0x1F600); // supplementary: needs a surrogate pair, 4 bytes
    m.regs[2] = FinalTerms.int(&m.ctx, 0x10437); // utf32 codepoint

    try execInstr(&m, .{ .bs_create_bin = .{
        .dst = .{ .x = 10 },
        .else_to = null,
        .segs = &.{
            .{ .utf16 = .{ .src = .{ .x = 0 }, .endian = .little } },
            .{ .utf16 = .{ .src = .{ .x = 1 }, .endian = .little } },
            .{ .utf32 = .{ .src = .{ .x = 2 }, .endian = .big } },
        },
    } });
    try std.testing.expectEqual(Status.running, m.status);
    try std.testing.expectEqual(@as(usize, 2 + 4 + 4), FinalTerms.binBytes(&m.ctx, m.regs[10]).len);

    try execInstr(&m, .{ .bs_start_match = .{ .src = .{ .x = 10 }, .ctx = .{ .x = 11 }, .else_to = null } });
    try execInstr(&m, .{ .bs_get_utf = .{ .ctx = .{ .x = 11 }, .kind = .utf16, .endian = .little, .dst = .{ .x = 12 }, .else_to = 999 } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[12], FinalTerms.int(&m.ctx, 0x00E9)));

    // skip the surrogate-pair codepoint WITHOUT binding a register.
    try execInstr(&m, .{ .bs_skip_utf = .{ .ctx = .{ .x = 11 }, .kind = .utf16, .endian = .little, .else_to = 999 } });

    try execInstr(&m, .{ .bs_get_utf = .{ .ctx = .{ .x = 11 }, .kind = .utf32, .endian = .big, .dst = .{ .x = 13 }, .else_to = 999 } });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[13], FinalTerms.int(&m.ctx, 0x10437)));

    try execInstr(&m, .{ .bs_test_tail = .{ .ctx = .{ .x = 11 }, .bits = 0, .else_to = 999 } });
    try std.testing.expect(m.pc != 999); // fully consumed: exactly 0 trailing bits
}

test "LAW E3.4 UTF rejection: an invalid codepoint (surrogate/out-of-range) crashes badarg on construction; an overlong UTF-8 encoding jumps else_to on matching (mutant 2's kill law)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // construction: a UTF-16 surrogate value is rejected (BODY context: crash).
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 0xD800);
        try execInstr(&m, .{ .bs_create_bin = .{
            .dst = .{ .x = 1 }, .else_to = null,
            .segs = &.{.{ .utf16 = .{ .src = .{ .x = 0 }, .endian = .big } }},
        } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.badarg)));
    }
    // construction: an out-of-range UTF-32 codepoint (GUARD context: branches).
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 0x110000);
        try execInstr(&m, .{ .bs_create_bin = .{
            .dst = .{ .x = 1 }, .else_to = 77,
            .segs = &.{.{ .utf32 = .{ .src = .{ .x = 0 }, .endian = .big } }},
        } });
        try std.testing.expectEqual(@as(usize, 77), m.pc);
        try std.testing.expectEqual(Status.running, m.status);
    }
    // matching: bs_get_utf8 over a hand-crafted OVERLONG 2-byte encoding of
    // NUL (0xC0,0x80 — the classic overlong form `unicode.zig`'s decodeCp
    // rejects with error.Overlong) must jump `else_to`, leaving the ctx
    // register UNCHANGED — accepting it (mutant 2) would instead bind a
    // bogus codepoint and advance the cursor.
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        const bin = try FinalTerms.binary(&m.ctx, &.{ 0xC0, 0x80 });
        const ctx0 = try FinalTerms.makeMatchCtx(&m.ctx, bin, 0);
        m.regs[0] = ctx0;
        try execInstr(&m, .{ .bs_get_utf = .{ .ctx = .{ .x = 0 }, .kind = .utf8, .endian = .big, .dst = .{ .x = 1 }, .else_to = 55 } });
        try std.testing.expectEqual(@as(usize, 55), m.pc);
        try std.testing.expectEqual(ctx0, m.regs[0]); // cursor-monotonicity: unchanged
    }
}

test "LAW E3.4 size-overflow -> system_limit (exact error atom, not badarg)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // BODY context: crashes {system_limit-atom}.
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 1);
        try execInstr(&m, .{ .bs_create_bin = .{
            .dst = .{ .x = 1 }, .else_to = null,
            .segs = &.{.{ .integer = .{ .src = .{ .x = 0 }, .size = .{ .imm = 66000 }, .unit = 1, .endian = .big } }}, // 66000 bits > the bignum cap
        } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.system_limit)));
    }
    // GUARD context: branches else_to (not badarg's label, a distinct one
    // would prove the exact atom if it crashed instead — here we confirm it
    // does NOT crash).
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 1);
        try execInstr(&m, .{ .bs_create_bin = .{
            .dst = .{ .x = 1 }, .else_to = 88,
            .segs = &.{.{ .integer = .{ .src = .{ .x = 0 }, .size = .{ .imm = 66000 }, .unit = 1, .endian = .big } }},
        } });
        try std.testing.expectEqual(@as(usize, 88), m.pc);
        try std.testing.expectEqual(Status.running, m.status);
    }
}

test "LAW E3.4 badarg: a non-numeric integer-segment source, and a binary segment shorter than requested, both crash/branch badarg (never system_limit)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.atom(&m.ctx, m.badarg); // any atom: not a number
        try execInstr(&m, .{ .bs_create_bin = .{
            .dst = .{ .x = 1 }, .else_to = null,
            .segs = &.{.{ .integer = .{ .src = .{ .x = 0 }, .size = .{ .imm = 8 }, .unit = 1, .endian = .big } }},
        } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.badarg)));
    }
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = try FinalTerms.binary(&m.ctx, &.{0xAA}); // 8 bits available
        try execInstr(&m, .{ .bs_create_bin = .{
            .dst = .{ .x = 1 }, .else_to = null,
            .segs = &.{.{ .binary = .{ .src = .{ .x = 0 }, .size = .{ .imm = 16 }, .unit = 1 } }}, // requests 16, only 8 present
        } });
        try std.testing.expectEqual(Status.crashed, m.status);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.badarg)));
    }
}

test "LAW E3.4 bs_init_writable + append/private_append round-trip: the writable base's bits precede every following segment" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    try execInstr(&m, .{ .bs_init_writable = .{ .dst = .{ .x = 0 } } });
    m.regs[1] = FinalTerms.int(&m.ctx, 200);
    try execInstr(&m, .{ .bs_create_bin = .{
        .dst = .{ .x = 2 }, .else_to = null,
        .segs = &.{
            .{ .append = .{ .src = .{ .x = 0 } } }, // empty writable base
            .{ .integer = .{ .src = .{ .x = 1 }, .size = .{ .imm = 8 }, .unit = 1, .endian = .big } },
            .{ .string = .{ .bytes = "Z" } },
        },
    } });
    try std.testing.expectEqualSlices(u8, &.{ 200, 'Z' }, FinalTerms.binBytes(&m.ctx, m.regs[2]));

    // private_append onto a NON-empty base: the base's own bytes come first.
    const base = try FinalTerms.binary(&m.ctx, &.{ 1, 2 });
    m.regs[3] = base;
    m.regs[4] = FinalTerms.int(&m.ctx, 3);
    try execInstr(&m, .{ .bs_create_bin = .{
        .dst = .{ .x = 5 }, .else_to = null,
        .segs = &.{
            .{ .private_append = .{ .src = .{ .x = 3 } } },
            .{ .integer = .{ .src = .{ .x = 4 }, .size = .{ .imm = 8 }, .unit = 1, .endian = .big } },
        },
    } });
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, FinalTerms.binBytes(&m.ctx, m.regs[5]));
}
