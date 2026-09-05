//! beam-zig M8 / S15: the **BEAM file loader** (cf. erts beam_file.c,
//! beam_load.c) — gate G2.
//!
//! Round-trip algebra:
//!   parse : bytes -> Module        (IFF chunks + compact term encoding)
//!   emit  : Module.code -> bytes   (the assembler direction)
//!   translate : Module -> ia.Program  (generic ops → the M3/M5/M8 machine)
//!
//! Laws:
//!   EMIT∘PARSE = id      re-encoding the parsed Code section reproduces the
//!                        compiler's bytes EXACTLY (the compact encoding is
//!                        minimal; so is ours)
//!   PARSE∘EMIT = id      structural: re-parsing re-emitted bytes yields the
//!                        same op list (follows from the above on fixtures,
//!                        asserted independently for synthetic operands)
//!   OPNAME ORACLE        the parsed opcode-name sequence per function equals
//!                        what OTP's own beam_disasm reports (vendored
//!                        fixture opnames.txt) — a cross-toolchain oracle
//!   NEGATE LAW           denote(add(n, negate(n))) == 0 (the '-' translation
//!                        is negate∘add; this pins negate to the arithmetic
//!                        oracle)
//!   G2 GATE              mylists.beam — compiled by REAL erlc (vendored with
//!                        expected results computed by a REAL node) — loads,
//!                        translates, and EXECUTES: sum, len, rev, seq, and
//!                        sum(seq(20)) all match the node's answers
//!
//! Literals (LitT, W-17): the LitT chunk decodes into `Module.literals` — one
//! raw external-format byte slice per literal — reusing etf.zig's zlib
//! decompressor and term decoder (NO new ETF semantics). The on-disk split is
//! ONLY compression — per the pin (beam_file.c) each literal carries its `131`
//! version byte in BOTH forms: uncompressed-size 0 → the table follows verbatim
//! (OTP-28+); uncompressed-size > 0 → a zlib blob (classic). `materializeLiterals`
//! peeks the per-literal first byte (`131` ⇒ version-ful decode; else the
//! version-less entry) — defensive and unambiguous (`131` is not a valid first
//! term tag). A `.lit N` operand resolves through `srcOf` to `Src.literal(N)`
//! (bounds-checked like `uOf`/`labelIdOf`, never a raw union access);
//! `materializeLiterals` decodes each into the executing machine's heap so
//! `resolve` reads it like any other source — decoded PER machine because a
//! heap ref is only valid in the ctx that built it.
//!
//! Multi-module LINKING (E3.12b): `link` composes N `translate`d modules into
//! ONE flat program — the loading homomorphism `load(A ++ B) == link(load A,
//! load B)`. Each module is translated into its OWN 0-based pc AND literal-index
//! space; linking concatenates the programs, relocating (1) every intra-module
//! pc target (`relocPc`, mirroring the label-fixup switch) by the module's pc
//! offset and (2) every `.literal` operand index (`relocLits`, a comptime-
//! reflective `Src` walker) by the module's literal offset into the COMBINED
//! pool — the literal relocation that made concatenating separately-compiled
//! real erlc `.beam`s the E3.12 genuine blocker. It builds the cross-module
//! EXPORT index (`module:func/arity → global pc`) that `instr_algebra`'s
//! `call_ext_code` resolves through, so a fully-qualified call in one module
//! dispatches into another's body. `onLoadFun` reads a module's `-on_load`
//! function from its `Attr` proplist and `resolveLocal` finds its (unexported)
//! entry via the `locs` table, for `cli.runMulti`'s load-time `ok`-gating.
//!
//! Scope (documented): select_val/select_tuple_arity, floats-in-code, and
//! try/catch ops land when gate modules need them. Opcode table
//! is generated from THIS OTP install's beam_opcodes module (vendored:
//! src/isa_opcodes.txt, provenance in fixtures/).
//!
//! E4-boot-residual / E5.2 (preloaded-module loader coverage): every `.beam` in
//! `erts/preloaded/ebin` now either fully translates or is rejected with a
//! SPECIFIC named diagnostic — NEVER a bare `error.BadOperand` and never an
//! `@intCast` truncation panic. The three coverage residuals are now ALL closed:
//! (1) `put_list` into a Y (stack) slot — a Y dst lowers to a cons into the x15
//! scratch + a `move2` to the stack (the `swap` idiom; decode-only) — flips
//! `erlang.beam` and `erl_prim_loader.beam` to full load; (2) DISCHARGED (E5.2,
//! DIVERGENCE 46): the x-register file was widened from the 16-slot (`u4`) bank
//! to the full decodable `ia.x_reg_count` range (`ia.XReg = u8`), so `xReg` is
//! TOTAL — x16..x255 load, `prim_inet`/`prim_zip` no longer reject; (3)
//! DISCHARGED (E5.2, DIVERGENCE 47): `get_map_elements`/`has_map_fields` keys are
//! now runtime `Src`s (`srcOf`) resolved at execution, so a register-valued key
//! loads and runs — `init`, `prim_net`, `prim_socket`, `socket_registry` no
//! longer reject.
//!
//! Type-test guards (E1.3): the 13 unary `is_*` ops (is_integer/is_float/
//! is_number/is_atom/is_pid/is_reference/is_port/is_binary/is_list/is_map/
//! is_boolean/is_function/is_bitstr, operand order Lbl,Src) decode to one
//! parametric `ia.type_test{kind,...}` CInstr, and `is_function2` (Lbl,Src,
//! Arity) to `ia.is_function_arity`. W-19: Arity is decoded via `intArgOf`
//! (accepts `.u` OR a non-negative `.i`) — real erlc emits it as a signed
//! integer-literal operand, unlike every other count/arity operand in this
//! loader (which stay on the `.u`-only `uOf`, confirmed by `beam_disasm`
//! against the curated OTP corpus). E6.8 (DIVERGENCE 128 (3a)): the Arity may
//! ALSO be a REGISTER (`.x`/`.y`/`.tr`) when erlc knows the arity only at
//! runtime — `is_function(F, X)` where X is a variable (eunit_data's
//! `check_arity/3`: a `{tr,{x,1},t_integer}` typed register). A register Arity
//! routes through `srcOf` into `ia.is_function_arity.arity_src`; the guard then
//! resolves it at run time (a non-integer/negative fails the guard, BEAM
//! semantics). `typeTestKindOf` is the single source
//! pairing op names with kinds; the operand law "emit∘parse identity" pins the
//! decode (label→else_to patched to a pc, arg→src, kind from the name). Their
//! predicate semantics live in instr_algebra (the term-algebra observations).
//!
//! Comparison-test guards (E1.4): the four binary compare ops (is_ge/is_eq/
//! is_ne/is_ne_exact, operand order Lbl,Src,Src) decode to one parametric
//! `ia.cmp_test{op,a,b,else_to}` CInstr via `cmpTestKindOf` (the single source
//! pairing names with kinds); the arith-vs-exact split is fixed in
//! instr_algebra's `cmpTestHolds`. `is_lt`/`is_eq_exact` predate this and keep
//! their own `is_lt`/`test_eq` arms.
//!
//! Tuple opcodes (E1.5): `get_tuple_element` (Src,0-based Index,Dst),
//! `set_tuple_element` (NewVal,Tuple,0-based Index), `put_tuple2` (Dst,{list})
//! decode to `ia.get_tuple_elem`/`set_tuple_elem`/`put_tuple2`; `test_arity`
//! (Lbl,Src,Arity) and `is_tagged_tuple` (Lbl,Src,Arity,Atom) decode to the
//! guarded `ia.test_arity`/`is_tagged_tuple` (else_to fixups); `is_tuple`
//! (Lbl,Src) joins the E1.3 `type_test` family via `typeTestKindOf` → `.tuple`.
//! `put_tuple2`'s `elems` slice — the `select_val`/`select_tuple_arity`
//! jump-table `pairs` slice (E1.6), `make_fun3`'s captured `env` slice
//! (E1.7), and the E1.10 map-opcode slices (`has_map_fields.keys`,
//! `get_map_elements.pairs`, `put_map.kvs`) — are gpa-owned and freed by
//! `freeProg` (and by `translate`'s errdefer on mid-decode failure).
//! Ownership rule: any site that may translate a module bearing `put_tuple2` or
//! a `case`/`select` (`cli.run`, `cli.checkLoad` — the arbitrary/corpus paths)
//! MUST release with `freeProg`, not `gpa.free(t.prog)`. Fixed-fixture and
//! synthetic-single-op sites (`boot.zig`, `diag.zig`, `dispatch.zig`, the
//! `translateSingle`/G2 test helpers) translate only `put_tuple2`/select-free
//! code and stay on `gpa.free`; converting `boot.link` in particular would
//! DOUBLE-FREE, since it shallow-copies `t.prog` (aliasing any owned sub-slice).
//! The
//! `is_tagged_tuple` tag is resolved to a term with `FinalTerms.atomTerm` (atoms
//! are ctx-free immediates, so no heap is needed at translate time).
//!
//! AtU8 dual form (E0.6): the atom-table chunk is accepted in BOTH the legacy
//! layout (positive u32 count, plain u8 length prefixes — the vendored OTP-30
//! fixture) AND the OTP-28+ "long atom names" layout (NEGATIVE i32 count whose
//! magnitude is the atom count, each length compact-term encoded so names may
//! exceed 255 bytes). The AtU8 long-atom law pins their equivalence; this is
//! what lets host-28 erlc-compiled corpus modules load in E0 bring-up mode.
//!
//! FunT / lambda table (W-15): the loader parses the `FunT` chunk into
//! `Module.lambdas` — a fixed 6×u32 record per closure {atom, arity, label,
//! index, num_free, old_uniq}. `make_fun3`'s FIRST operand is an UNSIGNED
//! `.u` INDEX into this table (NOT a raw code label); `translate` resolves it
//! to the entry's `label`, then the normal label→pc fixup runs. The pre-W-15
//! arm read that operand as a label `.f` and PANICKED on every real module
//! carrying a closure (the E1.7 laws missed it — they build the `make_fun3`
//! CInstr directly, bypassing the loader boundary). A malformed operand or an
//! out-of-range index is a clean `error.BadOperand`, never a panic.
//!
//! Operand totality (W-16): the W-15 panic was one instance of a systemic
//! bug-class — `translate` arms that read an operand's union field raw
//! (`op.args[i].f` / `.u` / `.list`) would PANIC ("access of union field X
//! while field Y is active") whenever the real compiler emits a valid-but-
//! differently-tagged operand than the arm assumed. EVERY such access now
//! routes through a checked helper (`labelIdOf`/`uOf`/`listOf`/`srcOf`/`dstOf`/
//! `xOf`/`frOf`) that returns `error.BadOperand` on a variant mismatch. The
//! invariant: `translate` NEVER panics on a well-formed `.beam` — it decodes,
//! or returns `error.BadOperand`/`error.UnsupportedOp`. Decode behavior is
//! unchanged (a helper accepts the exact variant the raw access read). W-16
//! also CLOSES the E1.7 make_fun3 arity divergence: the closure's VISIBLE fun
//! arity is the FunT lambda-table `arity` field (per OTP `i_make_fun3`:
//! header ARITY == fe->arity, num_free carried separately), threaded through
//! `make_fun3.arity` — not `env.len` as before.
//!
//! Bit-syntax MATCHING opcodes (E3.3): `bs_start_match3/4`, `bs_match/3`,
//! `bs_get_integer2/7`, `bs_get_float2/7`, `bs_get_binary2/7`,
//! `bs_skip_bits2/5`, `bs_test_tail2/3`, `bs_match_string/4`, `bs_get_tail/3`,
//! `bs_get_position/3`, `bs_set_position/2` — the semantic domain (MatchCtx,
//! cursor-monotonicity) lives in `instr_algebra.zig`'s doc comment; this is
//! the DECODE side. Genop operand orders confirmed against the pin's classic
//! loader `erts/emulator/beam/emu/ops.tab` (e.g. `bs_get_integer2 Fail Ms
//! Live Sz Unit Flags Dst`) and `genop.tab`'s `@spec` comments (e.g.
//! `bs_get_tail Ctx Dst Live`). `bsFlagsOf` decodes the Flags `.u` bitmask
//! (`erl_bits.h`'s `BSF_LITTLE`/`BSF_SIGNED`/`BSF_NATIVE`, resolving NATIVE to
//! the host endianness at translate time). `bsStartFailOf` extends the
//! `bif_call`-style optional-label convention: `bs_start_match4`'s Fail may be
//! the atom `no_fail`/`resume` (compiler-proven success), decoding to
//! `else_to = null`. `bsCommandsOf` decodes `bs_match/3`'s `{commands,
//! Commands}` FLAT `.list` operand — each `{Tag, Field...}` tuple is spliced
//! on-disk as `[{atom,Tag}, Field...]` (confirmed against `beam_asm.erl`'s
//! `encode_arg({commands,List0},_)`, which literally does
//! `[{atom,H}|T] <- tuple_to_list(Tuple)`, and cross-checked against
//! `beam_disasm.erl`'s `resolve_bs_match_commands/1`) — see `ia.BsCmd`'s doc
//! comment for the full per-command field grammar, cited against the pin's
//! `genop.tab` line 182 doc comment VERBATIM. `bs_match_string`'s literal
//! pattern bytes are copied out of the module's NEW `StrT` chunk (`Module.
//! strtab` — a flat, unframed byte blob; the op's `(Bits, Off)` operand pair
//! decodes as plain `.u` values on disk, confirmed against `beam_disasm.erl`'s
//! `resolve_inst({bs_match_string,[F,Ms,{u,Bits},{u,Off}]},_,_,_)` — NOT the
//! compiler-level symbolic `{string,Bin}` form) at TRANSLATE time into a
//! gpa-owned slice (freed by `freeProg`, the `put_tuple2.elems` ownership
//! precedent); an out-of-range `Off` is a clean `error.BadOperand`.
//!
//! Bit-syntax CONSTRUCTION + UTF opcodes (E3.4): `bs_create_bin/6`,
//! `bs_init_writable/0`, `bs_get_utf8/16/32`, `bs_skip_utf8/16/32` — the
//! semantic domain lives in `instr_algebra.zig`'s doc comment; this is the
//! DECODE side. `bsCreateSegsOf` decodes `bs_create_bin`'s `OpList` — a FLAT
//! `.list` where each logical segment `{Type,Seg,Unit,Flags,Val,Size}`
//! splices as 6 consecutive raw operands (confirmed against a freshly
//! `erlc`-compiled fixture LOADED THROUGH THIS LOADER, cross-checked against
//! `beam_disasm.erl`'s `resolve_bs_create_bin_list/2` — see `ia.BsSeg`'s doc
//! comment for the pin citation and per-type field grammar). `bsFieldFlagsOf`
//! decodes the OTP-25+ "field_flags" Flags shape (nil atom / a `.lit`
//! literal atom-list `little`/`native`/`signed`) shared by `bs_create_bin`'s
//! segments AND — an E3.3 FIX discovered while building this task's
//! differential corpus — `bs_match/3`'s embedded `integer`/`binary`
//! sub-commands (E3.3 wrongly reused the OLDER `.u`-bitmask `bsFlagsOf`
//! there; real `bs_match` is itself an OTP-25+ instruction sharing
//! `bs_create_bin`'s Flags shape, not `bs_get_integer2`'s). `bs_init_writable/0`
//! has GENUINELY ZERO on-disk operands (confirmed against the pin's
//! `bs_instrs.tab`: it reads/writes `x(0)` directly) — decoded to a
//! hardcoded `{dst: .x = 0}`. `bs_get_utf8/16/32`/`bs_skip_utf8/16/32`'s
//! Flags decode via the OLDER `bsFlagsOf` `.u` bitmask (confirmed against
//! the SAME fixture — these standalone UTF ops are R12B-era, unlike
//! `bs_create_bin`/`bs_match`). SECOND E3.3 FIX (same discovery): the
//! on-disk operand order for `bs_start_match4` is `Fail, Live, Src, Dst`
//! (Live BEFORE Src), NOT `Fail, Src, Live, Dst` — the old code silently
//! built a MatchCtx over the Live COUNT instead of the real binary source.
//! vm-binmatch-gc FIX (DIVERGENCE 57/68): `bs_start_match3` does NOT share
//! that order — its genop.tab @spec is `Fail, Bin, Live, Dst` (Bin BEFORE
//! Live), so its Src is arg[1], not arg[2]. The E3.3 fix over-generalized
//! and applied the match4 order to match3 too; that was invisible until a
//! real `receive`+`<<X:8>>=B` beam forced the compiler to emit match3 (with
//! a Fail label) rather than the no_fail match4 in-function path. See the
//! `bs_start_match3`/`4` translate arms' inline comments and DIVERGENCE_LOG
//! entries 17/57/68 (both fixes were caught by exercising REAL compiled
//! `.beam`, not by any hand-built unit test — the exact failure mode a
//! differential corpus exists to catch).

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");
const etf = @import("etf.zig");
const bif_dispatch = @import("bifs/dispatch.zig");

/// R2c: classify a resolved BIF's reduction size-class from its (module,name,arity)
/// — the ONE place the name is known (the `call_ext_bif` exec arm sees only a func
/// pointer). A tiny explicit, total table: `.none` for everything not yet calibrated
/// to an erts per-element loop factor. `lists:reverse/2` is the first member (its
/// erts `lists_reverse_2` bumps `count / ELEMENTS_PER_RED`); its list argument is x0.
fn bifSizeClassOf(module: []const u8, name: []const u8, arity: u8) ia.BifSizeClass {
    if (std.mem.eql(u8, module, "lists")) {
        if (std.mem.eql(u8, name, "reverse") and arity == 2) return .list0_elems; // reverse(List,Tail)
        // gap-reduction-size-weight (DIVERGENCE 603): the sibling erl_bif_lists.c BIFs
        // that scan a list in a LATER argument. member(Elem,List) → x1;
        // keyfind/keymember/keysearch(Key,N,TupleList) → x2. Same per-element charge.
        if (std.mem.eql(u8, name, "member") and arity == 2) return .list1_elems;
        if (arity == 3 and (std.mem.eql(u8, name, "keyfind") or
            std.mem.eql(u8, name, "keymember") or std.mem.eql(u8, name, "keysearch"))) return .list2_elems;
    }
    // gap-reduction-bytes-weight (DIVERGENCE 604): the byte/element-heavy binary BIFs.
    // binary_to_list(Bin) scans the BINARY in x0 → byte-weighted; list_to_binary(List)
    // scans the input LIST in x0 → element-weighted (the flat-iolist approximation).
    // NB both TRAP in erts → the weight is a same-order linear approximation (bound).
    if (std.mem.eql(u8, module, "erlang")) {
        if (std.mem.eql(u8, name, "binary_to_list") and arity == 1) return .bytes0_elems;
        if (std.mem.eql(u8, name, "list_to_binary") and arity == 1) return .list0_elems;
    }
    return .none;
}

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;

// ============================================================================
// Opcode table (generated from beam_opcodes:opname/1 — ground truth)
// ============================================================================

pub const OpInfo = struct { name: []const u8, arity: u8 };

pub const op_table: [201]?OpInfo = blk: {
    @setEvalBranchQuota(100_000);
    var t: [201]?OpInfo = @splat(null);
    const text = @embedFile("isa_opcodes.txt");
    var it = std.mem.tokenizeScalar(u8, text, '\n');
    while (it.next()) |line| {
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        const num = std.fmt.parseInt(u16, f.next().?, 10) catch unreachable;
        const raw = f.next().?;
        // beam_disasm quotes ops whose names are Erlang keywords (`'catch'`,
        // `'try'`); the quotes are a display artifact, not part of the op name.
        // genop.tab and `supported_ops` use the bare name, so strip a matching
        // pair of surrounding single-quotes here (the SINGLE SOURCE of op names).
        const name = if (raw.len >= 2 and raw[0] == '\'' and raw[raw.len - 1] == '\'')
            raw[1 .. raw.len - 1]
        else
            raw;
        const arity = std.fmt.parseInt(u8, f.next().?, 10) catch unreachable;
        t[num] = .{ .name = name, .arity = arity };
    }
    break :blk t;
};

pub fn opName(opcode: u16) []const u8 {
    return (op_table[opcode] orelse return "?").name;
}

// ============================================================================
// Capability table (the SINGLE SOURCE for translate coverage) — E0.5
// ============================================================================
//
// `supported_ops` is the authoritative list of generic ops the loader's
// `translate` dispatch actually implements. `translate` GUARDS on it (an op
// whose name is absent is rejected with error.UnsupportedOp before the
// dispatch chain runs), and `cli.dumpCaps` PRINTS from it. One table, two
// consumers — so `dump-caps` can never drift from what the loader accepts, and
// the round-trip / negative laws in this module pin that identity.
//
// Arities are the generic-op arities from OTP's genop.tab for the SAME pin the
// harness ledgers against, so the harness cross-law (every caps `op` exists in
// the parsed genop set) matches on `<name> <arity>` exactly. Kept sorted by
// (name, then arity) so dumpCaps output is deterministic and the sort law holds.

pub const OpCap = struct { name: []const u8, arity: u8 };

pub const supported_ops = [_]OpCap{
    .{ .name = "allocate", .arity = 2 },
    .{ .name = "allocate_heap", .arity = 3 },
    .{ .name = "apply", .arity = 1 },
    .{ .name = "apply_last", .arity = 2 },
    .{ .name = "badmatch", .arity = 1 },
    .{ .name = "badrecord", .arity = 1 },
    .{ .name = "bif0", .arity = 2 },
    .{ .name = "bif1", .arity = 4 },
    .{ .name = "bif2", .arity = 5 },
    .{ .name = "bif3", .arity = 6 },
    .{ .name = "bs_create_bin", .arity = 6 },
    .{ .name = "bs_get_binary2", .arity = 7 },
    .{ .name = "bs_get_float2", .arity = 7 },
    .{ .name = "bs_get_integer2", .arity = 7 },
    .{ .name = "bs_get_position", .arity = 3 },
    .{ .name = "bs_get_tail", .arity = 3 },
    .{ .name = "bs_get_utf16", .arity = 5 },
    .{ .name = "bs_get_utf32", .arity = 5 },
    .{ .name = "bs_get_utf8", .arity = 5 },
    .{ .name = "bs_init_writable", .arity = 0 },
    .{ .name = "bs_match", .arity = 3 },
    .{ .name = "bs_match_string", .arity = 4 },
    .{ .name = "bs_set_position", .arity = 2 },
    .{ .name = "bs_skip_bits2", .arity = 5 },
    .{ .name = "bs_skip_utf16", .arity = 4 },
    .{ .name = "bs_skip_utf32", .arity = 4 },
    .{ .name = "bs_skip_utf8", .arity = 4 },
    .{ .name = "bs_start_match3", .arity = 4 },
    .{ .name = "bs_start_match4", .arity = 4 },
    .{ .name = "bs_test_tail2", .arity = 3 },
    .{ .name = "build_stacktrace", .arity = 0 },
    .{ .name = "call", .arity = 2 },
    .{ .name = "call_ext", .arity = 2 },
    .{ .name = "call_ext_last", .arity = 3 },
    .{ .name = "call_ext_only", .arity = 2 },
    .{ .name = "call_fun", .arity = 1 },
    .{ .name = "call_fun2", .arity = 3 },
    .{ .name = "call_last", .arity = 3 },
    .{ .name = "call_only", .arity = 2 },
    .{ .name = "case_end", .arity = 1 },
    .{ .name = "catch", .arity = 2 },
    .{ .name = "catch_end", .arity = 1 },
    .{ .name = "deallocate", .arity = 1 },
    .{ .name = "debug_line", .arity = 4 },
    .{ .name = "executable_line", .arity = 2 },
    .{ .name = "fadd", .arity = 4 },
    .{ .name = "fconv", .arity = 2 },
    .{ .name = "fdiv", .arity = 4 },
    .{ .name = "fmove", .arity = 2 },
    .{ .name = "fmul", .arity = 4 },
    .{ .name = "fnegate", .arity = 3 },
    .{ .name = "fsub", .arity = 4 },
    .{ .name = "func_info", .arity = 3 },
    .{ .name = "gc_bif1", .arity = 5 },
    .{ .name = "gc_bif2", .arity = 6 },
    .{ .name = "gc_bif3", .arity = 7 },
    .{ .name = "get_hd", .arity = 2 },
    .{ .name = "get_list", .arity = 3 },
    .{ .name = "get_map_elements", .arity = 3 },
    .{ .name = "get_record_elements", .arity = 3 }, // E3.14
    .{ .name = "get_record_field", .arity = 5 }, // E3.14
    .{ .name = "get_tl", .arity = 2 },
    .{ .name = "get_tuple_element", .arity = 3 },
    .{ .name = "has_map_fields", .arity = 3 },
    .{ .name = "if_end", .arity = 0 },
    .{ .name = "init_yregs", .arity = 1 },
    .{ .name = "int_code_end", .arity = 0 },
    .{ .name = "is_any_native_record", .arity = 2 }, // E3.14
    .{ .name = "is_atom", .arity = 2 },
    .{ .name = "is_binary", .arity = 2 },
    .{ .name = "is_bitstr", .arity = 2 },
    .{ .name = "is_boolean", .arity = 2 },
    .{ .name = "is_eq", .arity = 3 },
    .{ .name = "is_eq_exact", .arity = 3 },
    .{ .name = "is_float", .arity = 2 },
    .{ .name = "is_function", .arity = 2 },
    .{ .name = "is_function2", .arity = 3 },
    .{ .name = "is_ge", .arity = 3 },
    .{ .name = "is_integer", .arity = 2 },
    .{ .name = "is_list", .arity = 2 },
    .{ .name = "is_lt", .arity = 3 },
    .{ .name = "is_map", .arity = 2 },
    .{ .name = "is_native_record", .arity = 4 }, // E3.14
    .{ .name = "is_ne", .arity = 3 },
    .{ .name = "is_ne_exact", .arity = 3 },
    .{ .name = "is_nil", .arity = 2 },
    .{ .name = "is_nonempty_list", .arity = 2 },
    .{ .name = "is_number", .arity = 2 },
    .{ .name = "is_pid", .arity = 2 },
    .{ .name = "is_port", .arity = 2 },
    .{ .name = "is_record_accessible", .arity = 3 }, // E3.14
    .{ .name = "is_reference", .arity = 2 },
    .{ .name = "is_tagged_tuple", .arity = 4 },
    .{ .name = "is_tuple", .arity = 2 },
    .{ .name = "jump", .arity = 1 },
    .{ .name = "label", .arity = 1 },
    .{ .name = "line", .arity = 1 },
    .{ .name = "loop_rec", .arity = 2 },
    .{ .name = "loop_rec_end", .arity = 1 },
    .{ .name = "make_fun3", .arity = 3 },
    .{ .name = "move", .arity = 2 },
    .{ .name = "nif_start", .arity = 0 },
    .{ .name = "on_load", .arity = 0 },
    .{ .name = "put_list", .arity = 3 },
    .{ .name = "put_map_assoc", .arity = 5 },
    .{ .name = "put_map_exact", .arity = 5 },
    .{ .name = "put_record", .arity = 6 }, // E3.14
    .{ .name = "put_tuple2", .arity = 2 },
    .{ .name = "raise", .arity = 2 },
    .{ .name = "raw_raise", .arity = 0 },
    .{ .name = "recv_marker_bind", .arity = 2 },
    .{ .name = "recv_marker_clear", .arity = 1 },
    .{ .name = "recv_marker_reserve", .arity = 1 },
    .{ .name = "recv_marker_use", .arity = 1 },
    .{ .name = "remove_message", .arity = 0 },
    .{ .name = "return", .arity = 0 },
    .{ .name = "select_tuple_arity", .arity = 3 },
    .{ .name = "select_val", .arity = 3 },
    .{ .name = "send", .arity = 0 },
    .{ .name = "set_tuple_element", .arity = 3 },
    .{ .name = "swap", .arity = 2 },
    .{ .name = "test_arity", .arity = 3 },
    .{ .name = "test_heap", .arity = 2 },
    .{ .name = "timeout", .arity = 0 },
    .{ .name = "trim", .arity = 2 },
    .{ .name = "try", .arity = 2 },
    .{ .name = "try_case", .arity = 1 },
    .{ .name = "try_case_end", .arity = 1 },
    .{ .name = "try_end", .arity = 1 },
    .{ .name = "update_record", .arity = 5 },
    .{ .name = "wait", .arity = 1 },
    .{ .name = "wait_timeout", .arity = 2 },
};

/// E1.3: map a unary BEAM `is_*` op name to its `TypeTestKind`, or null if the
/// name is not one of the 13 unary type tests. `is_function2` is NOT here — it
/// carries an arity operand and decodes to `is_function_arity`. This is the
/// single source pairing op names with kinds; the `.type_test` translate arm
/// keys on it.
fn typeTestKindOf(name: []const u8) ?ia.TypeTestKind {
    const eq = std.mem.eql;
    if (eq(u8, name, "is_integer")) return .integer;
    if (eq(u8, name, "is_float")) return .float;
    if (eq(u8, name, "is_number")) return .number;
    if (eq(u8, name, "is_atom")) return .atom;
    if (eq(u8, name, "is_pid")) return .pid;
    if (eq(u8, name, "is_reference")) return .reference;
    if (eq(u8, name, "is_port")) return .port;
    if (eq(u8, name, "is_binary")) return .binary;
    if (eq(u8, name, "is_list")) return .list;
    if (eq(u8, name, "is_map")) return .map;
    if (eq(u8, name, "is_boolean")) return .boolean;
    if (eq(u8, name, "is_function")) return .function;
    if (eq(u8, name, "is_bitstr")) return .bitstr;
    if (eq(u8, name, "is_tuple")) return .tuple;
    return null;
}

/// E1.4: map a binary compare op name to its `CmpTestKind`, or null if the
/// name is not one of the four. `is_lt`/`is_eq_exact` are NOT here — they
/// predate E1.4 and decode to `is_lt`/`test_eq` (their arms run first). This is
/// the single source pairing op names with kinds; the `.cmp_test` translate arm
/// keys on it.
fn cmpTestKindOf(name: []const u8) ?ia.CmpTestKind {
    const eq = std.mem.eql;
    if (eq(u8, name, "is_ge")) return .ge;
    if (eq(u8, name, "is_eq")) return .eq_arith;
    if (eq(u8, name, "is_ne")) return .ne_arith;
    if (eq(u8, name, "is_ne_exact")) return .ne_exact;
    return null;
}

/// True iff `name` is a generic op the translate dispatch implements. The
/// guard `translate` consults — the ONE place op support is decided.
pub fn capSupported(name: []const u8) bool {
    for (supported_ops) |c| {
        if (std.mem.eql(u8, c.name, name)) return true;
    }
    return false;
}

// ============================================================================
// Operands (compact term encoding)
// ============================================================================

pub const Operand = union(enum) {
    u: u64, //                unsigned literal
    i: i64, //                integer
    // triage-big-divergences: a signed integer operand WIDER than 8 bytes
    // (the compact encoding carries arbitrary sizes; erlc emits ints up to a
    // couple of words inline before switching to LitT). Pre-fix, decode
    // SILENTLY TRUNCATED these to the low 8 bytes — silent value corruption
    // (worse than a crash: `X = 12345678901234567890, X =:= X` compared two
    // identical junk values and "passed"). 9..16 bytes decode exactly here;
    // >16 bytes is a clean error.BadOperand (never emitted by erlc, which
    // uses LitT for genuinely big literals — documented cap, never silent).
    ibig: i128,
    // gap-bigint-operand (DIVERGENCE 593): an inline signed integer WIDER than i128
    // — erlc emits these as `bs_match`/inline operands (e.g. `2^128-1`, a positive
    // 128-bit value encoded in 17 bytes: 16 magnitude + 1 leading 0x00 for sign).
    // Pre-fix `decodeValueSigned`'s 16-byte cap made these a hard `BadOperand`
    // (whole-module load failure), and a 16-byte top-bit value was silently mis-
    // signed. Carries the sign + LITTLE-ENDIAN magnitude bytes (arena-owned), bounded
    // by the runtime bignum cap; materialized as a SMALL_BIG_EXT literal (srcOf).
    ibigbytes: struct { positive: bool, mag_le: []const u8 },
    // batch-4: an INLINE float operand (compact-term Z subtag 0: 8 IEEE-754
    // big-endian bytes follow). erlc emits these for float-constant fmove/
    // fconv operands; the decode previously rejected the whole module
    // (UnsupportedExtendedOperand — fleet finding: float_SUITE failed to LOAD).
    flt: f64,
    atom: u32, //             atom index (1-based in BEAM; 0 = nil-atom)
    x: u8,
    y: u8,
    fr: u8, //                E1.12: floating-point register (BEAM `{fr,N}`)
    f: u32, //                label
    char: u32,
    lit: u32, //              literal-table index (LitT — M9)
    tr: struct { base: TrBase, type_idx: u32 }, // typed register (Type chunk)
    alloc: []const [2]u64, // allocation list (pairs of kind, count)
    list: []const Operand, // select lists

    pub const TrBase = union(enum) { x: u8, y: u8 };
};

pub const Op = struct { opcode: u16, args: []const Operand };

/// W-15: one lambda-table (FunT chunk) entry. `make_fun`/`make_fun2`/`make_fun3`
/// name a closure by its INDEX into this table (an unsigned operand), NOT by a
/// raw code label; the entry's `label` is the closure's code offset. Only
/// `label` is needed to resolve a `make_fun3` target to a pc; the other fields
/// are carried faithfully (the FunT layout is a fixed 6×u32 record) so the
/// table round-trips and future closure work (arity/num_free checks) has them.
pub const Lambda = struct {
    atom: u32, //      atom index of the generated fun name
    arity: u32,
    label: u32, //     code label of the closure body
    index: u32,
    num_free: u32, //  captured-variable count (== make_fun3 env length)
    old_uniq: u32,
};

/// E3.11: one decoded `Line` chunk item — the pin's `BeamFile_LineTable.items[]`
/// entry. `line` is the source line number; `name_index` selects the filename
/// in `Module.line_names`.
pub const LineItem = struct { name_index: u32, line: u32 };

pub const Module = struct {
    arena: std.heap.ArenaAllocator,
    atoms: [][]const u8, //  1-based: atoms[0] unused
    imports: [][3]u32, //    {module atom, function atom, arity}
    exports: [][3]u32, //    {function atom, arity, label}
    code: []Op,
    code_bytes: []const u8, // the raw Code opcode stream (for round-trip)
    labels: u32,
    lambdas: []const Lambda = &.{}, // W-15: FunT chunk; empty when absent
    /// W-17: the LitT literal table — one raw external-format term byte slice
    /// per literal (per the pin, each carries its `131` version byte), each an
    /// arena-owned copy of the (inflated or verbatim) LitT blob so it lives
    /// exactly as long as the Module. Empty when the module has no LitT chunk.
    /// A `.lit N` operand resolves to `literals[N]`, decoded into the executing
    /// machine's heap by `materializeLiterals`.
    literals: [][]const u8 = &.{},
    /// E3.3: the `StrT` chunk — raw bytes, referenced by `bs_match_string`'s
    /// (Bits, Off) operand pair as a byte OFFSET (never length-framed on
    /// disk; the classic BEAM string table is just a flat byte blob). Empty
    /// when the module has no `StrT` chunk (most OTP-25+ modules; the
    /// unified `bs_match`'s `=:=` command has mostly superseded standalone
    /// literal-pattern matching, but `bs_match_string` remains a live
    /// genop — see `beam_loader`'s E3.3 module-doc addendum).
    strtab: []const u8 = &.{},
    /// E3.11: the `Line` chunk — decoded line-number table for cooked
    /// stacktraces (DIVERGENCE entry 2b). `line_items[N]` is what a `line N`
    /// opcode operand indexes: `{name_index, line}` (item 0 = the "undefined
    /// location" sentinel, per the pin's `parse_line_chunk`). `line_names[K]`
    /// is the source filename for `name_index = K`; index 0 is ALWAYS the
    /// synthesized `<module>.erl` (the pin's implicit entry), 1.. are the
    /// chunk's explicit `-include`d filenames. Empty when the module has no
    /// `Line` chunk (stripped/`+no_line_info` builds) — then a raise cooks a
    /// head frame with an EMPTY location list `[]` (BEAM's own no-line-info
    /// behaviour), never a panic.
    line_items: []const LineItem = &.{},
    line_names: []const []const u8 = &.{},
    /// E3.12b: the `Attr` chunk — the module's `-attribute(...)` proplist, held
    /// as its raw external-term-format (ETF) bytes (an arena-owned copy, like
    /// `literals`). The load-gating `on_load` info lives HERE in modern OTP
    /// (`{on_load,[{F,A}]}`), NOT in the `on_load/0` genop (the compiler no
    /// longer emits that opcode). `onLoadFun` decodes this to find the marked
    /// function. Empty when the module has no `Attr` chunk (or no attributes).
    attr_bytes: []const u8 = &.{},
    /// E4.2: the `CInf` chunk — the module's COMPILE-INFO proplist, held as its
    /// raw ETF bytes (arena copy, exactly like `attr_bytes`). `get_module_info(
    /// M, compile)` / `module_info(compile)` decode THIS. Empty when absent.
    compile_bytes: []const u8 = &.{},
    /// E4.2: the module's MD5 checksum, computed at parse time by `computeMd5`
    /// over the EXACT chunk set + order erts uses (`beam_file.c`: AtU8, Code,
    /// StrT, ImpT, ExpT, then FunT with `OldUniq` zeroed, LitT, Meta, Recs,
    /// DbgB) — the value `erlang:get_module_info(M, md5)` /
    /// `erts_internal:beamfile_module_md5/1` return. `has_md5` is false only
    /// for a synthetic Module (a hand-built test program with no chunk bytes).
    mod_md5: [16]u8 = [_]u8{0} ** 16,
    has_md5: bool = false,

    pub fn deinit(self: *Module) void {
        self.arena.deinit();
    }

    pub fn atomName(self: *const Module, idx: u32) []const u8 {
        return self.atoms[idx];
    }
};

const Reader = struct {
    buf: []const u8,
    pos: usize = 0,

    fn u8_(self: *Reader) !u8 {
        if (self.pos >= self.buf.len) return error.Truncated;
        const b = self.buf[self.pos];
        self.pos += 1;
        return b;
    }
    fn u32be(self: *Reader) !u32 {
        if (self.pos + 4 > self.buf.len) return error.Truncated;
        const v = std.mem.readInt(u32, self.buf[self.pos..][0..4], .big);
        self.pos += 4;
        return v;
    }
    fn bytes(self: *Reader, n: usize) ![]const u8 {
        if (self.pos + n > self.buf.len) return error.Truncated;
        const s = self.buf[self.pos .. self.pos + n];
        self.pos += n;
        return s;
    }
    fn done(self: *const Reader) bool {
        return self.pos >= self.buf.len;
    }
};

/// Decode one compact-term value (the tag has already been peeked).
fn decodeValue(r: *Reader, first: u8) !u64 {
    if (first & 0b1000 == 0) return first >> 4; // 4-bit immediate
    if (first & 0b10000 == 0) { // 11-bit: 3 high bits + next byte
        const lo = try r.u8_();
        return (@as(u64, first >> 5) << 8) | lo;
    }
    const size: u64 = if ((first >> 5) == 7) (try decodeValue(r, try r.u8_())) + 9 else (first >> 5) + 2;
    // triage-big-divergences: a >8-byte UNSIGNED operand cannot fit u64 — the
    // pre-fix loop silently kept only the low 8 bytes (the same corruption
    // class as the signed arm). A clean load error, never a truncated value.
    if (size > 8) return error.BadOperand;
    var v: u64 = 0;
    for (0..size) |_| {
        const b = try r.u8_();
        v = (v << 8) | b;
    }
    return v;
}

/// Same, but sign-extended (tag i can be negative, n-byte two's complement).
/// triage-big-divergences: decodes EXACTLY up to 16 bytes (returns i128; the
/// pre-fix i64 version silently dropped all but the low 8 bytes of a wider
/// int). Sizes > 16 bytes are error.BadOperand — erlc emits genuinely big
/// integers through LitT, never as >16-byte inline operands (documented cap,
/// a clean load error rather than silent corruption).
fn decodeValueSigned(r: *Reader, first: u8) !i128 {
    if (first & 0b1000 == 0) return first >> 4;
    if (first & 0b10000 == 0) {
        const lo = try r.u8_();
        return (@as(i128, first >> 5) << 8) | lo;
    }
    const size: u64 = if ((first >> 5) == 7) (try decodeValue(r, try r.u8_())) + 9 else (first >> 5) + 2;
    if (size > 16) return error.BadOperand;
    var v: u128 = 0;
    var neg = false;
    for (0..size) |k| {
        const b = try r.u8_();
        if (k == 0) neg = (b & 0x80) != 0;
        v = (v << 8) | b;
    }
    if (!neg or size == 16) return @bitCast(v);
    // negative, narrower than 16 bytes: sign-extend to the full 128-bit width
    const shift: u7 = @intCast(128 - 8 * @as(u32, @intCast(size)));
    return @as(i128, @bitCast(v << shift)) >> shift;
}

/// gap-bigint-operand (DIVERGENCE 593): decode a signed integer operand of ANY
/// width into `.i` / `.ibig` / `.ibigbytes` — the i128-capped `decodeValueSigned`
/// rejected a >16-byte inline int (`BadOperand`, whole-module load failure), but
/// erlc emits them (a positive 128-bit value like `2^128-1` is 17 bytes: 16
/// magnitude + a leading `0x00` for two's-complement positivity). ≤16 bytes keep
/// the fast i128 path; wider decodes to a (sign, little-endian magnitude) bignum
/// bounded by 255 bytes (erlc uses the literal table beyond → a clean cap).
fn decodeIntOperand(r: *Reader, first: u8, arena: std.mem.Allocator) !Operand {
    if (first & 0b1000 == 0) return .{ .i = @intCast(first >> 4) };
    if (first & 0b10000 == 0) {
        const lo = try r.u8_();
        return .{ .i = (@as(i64, first >> 5) << 8) | lo };
    }
    const size: usize = @intCast(if ((first >> 5) == 7) (try decodeValue(r, try r.u8_())) + 9 else (first >> 5) + 2);
    if (size > 255) return error.BadOperand; // inline bignum-operand cap (erlc uses LitT beyond)
    const be = try arena.alloc(u8, size);
    for (be) |*b| b.* = try r.u8_();
    const neg = (be[0] & 0x80) != 0;
    if (size <= 16) {
        // The classic i128 path (correct for every ≤16-byte erlc encoding).
        var v: u128 = 0;
        for (be) |b| v = (v << 8) | b;
        const val: i128 = if (!neg or size == 16) @bitCast(v) else blk: {
            const shift: u7 = @intCast(128 - 8 * @as(u32, @intCast(size)));
            break :blk @as(i128, @bitCast(v << shift)) >> shift;
        };
        if (val >= std.math.minInt(i64) and val <= std.math.maxInt(i64)) return .{ .i = @intCast(val) };
        return .{ .ibig = val };
    }
    // >16 bytes: an arbitrary-precision bignum. Magnitude = the bytes (positive) or
    // their two's-complement (negative), converted to little-endian; trim high zeros.
    const mag_le = try arena.alloc(u8, size);
    if (!neg) {
        for (0..size) |k| mag_le[k] = be[size - 1 - k];
    } else {
        var carry: u16 = 1;
        for (0..size) |k| {
            const s = (@as(u16, ~be[size - 1 - k]) & 0xFF) + carry;
            mag_le[k] = @truncate(s);
            carry = s >> 8;
        }
    }
    var n: usize = size;
    while (n > 0 and mag_le[n - 1] == 0) n -= 1;
    return .{ .ibigbytes = .{ .positive = !neg, .mag_le = mag_le[0..n] } };
}

const TAG_U = 0;
const TAG_I = 1;
const TAG_A = 2;
const TAG_X = 3;
const TAG_Y = 4;
const TAG_F = 5;
const TAG_H = 6;
const TAG_Z = 7;

fn decodeOperand(r: *Reader, arena: std.mem.Allocator) anyerror!Operand {
    const first = try r.u8_();
    const tag = first & 0b111;
    switch (tag) {
        TAG_U => return .{ .u = try decodeValue(r, first) },
        // triage-big-divergences + gap-bigint-operand: ≤i64 → `.i`; 9..16-byte →
        // `.ibig` (i128); >16-byte → `.ibigbytes` (arbitrary-precision bignum). srcOf
        // materializes `.ibig`/`.ibigbytes` as a synthesized literal — never truncated.
        TAG_I => return try decodeIntOperand(r, first, arena),
        TAG_A => return .{ .atom = @intCast(try decodeValue(r, first)) },
        TAG_X => return .{ .x = @intCast(try decodeValue(r, first)) },
        TAG_Y => return .{ .y = @intCast(try decodeValue(r, first)) },
        TAG_F => return .{ .f = @intCast(try decodeValue(r, first)) },
        TAG_H => return .{ .char = @intCast(try decodeValue(r, first)) },
        TAG_Z => {
            const subtag = first >> 4;
            switch (subtag) {
                0 => { // batch-4: inline float — 8 IEEE big-endian bytes
                    var b: [8]u8 = undefined;
                    for (&b) |*x| x.* = try r.u8_();
                    return .{ .flt = @bitCast(std.mem.readInt(u64, &b, .big)) };
                },
                2 => { // E1.12: floating-point register — {fr,N}, N a `u` operand
                    const b = try r.u8_();
                    return .{ .fr = @intCast(try decodeValue(r, b)) };
                },
                1 => { // select list: count then operands
                    const n = blk: {
                        const b = try r.u8_();
                        break :blk try decodeValue(r, b);
                    };
                    const ops = try arena.alloc(Operand, @intCast(n));
                    for (ops) |*o| o.* = try decodeOperand(r, arena);
                    return .{ .list = ops };
                },
                3 => { // allocation list: count then (kind, val) pairs
                    const n = blk: {
                        const b = try r.u8_();
                        break :blk try decodeValue(r, b);
                    };
                    const pairs = try arena.alloc([2]u64, @intCast(n));
                    for (pairs) |*p| {
                        const b1 = try r.u8_();
                        p[0] = try decodeValue(r, b1);
                        const b2 = try r.u8_();
                        p[1] = try decodeValue(r, b2);
                    }
                    return .{ .alloc = pairs };
                },
                4 => { // literal-table reference
                    const b = try r.u8_();
                    return .{ .lit = @intCast(try decodeValue(r, b)) };
                },
                5 => { // typed register: register operand + type index
                    const reg = try decodeOperand(r, arena);
                    const tyb = try r.u8_();
                    const ty: u32 = @intCast(try decodeValue(r, tyb));
                    return switch (reg) {
                        .x => |xr| .{ .tr = .{ .base = .{ .x = xr }, .type_idx = ty } },
                        .y => |yr| .{ .tr = .{ .base = .{ .y = yr }, .type_idx = ty } },
                        else => error.MalformedTypedRegister,
                    };
                },
                else => return error.UnsupportedExtendedOperand,
            }
        },
        else => unreachable,
    }
}

// ============================================================================
// parse
// ============================================================================

pub fn parse(gpa: std.mem.Allocator, file_bytes: []const u8) !Module {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();

    if (file_bytes.len < 12 or !std.mem.eql(u8, file_bytes[0..4], "FOR1") or
        !std.mem.eql(u8, file_bytes[8..12], "BEAM")) return error.NotABeamFile;

    var atoms: [][]const u8 = &.{};
    var imports: [][3]u32 = &.{};
    var exports: [][3]u32 = &.{};
    var code: []Op = &.{};
    var code_bytes: []const u8 = &.{};
    var labels: u32 = 0;
    var lambdas: []const Lambda = &.{};
    var literals: [][]const u8 = &.{};
    var strtab: []const u8 = &.{};
    var line_items: []const LineItem = &.{};
    var line_names: []const []const u8 = &.{};
    var attr_bytes: []const u8 = &.{};
    var compile_bytes: []const u8 = &.{};

    // E4.2: raw chunk payloads captured (as slices into `file_bytes`, alive
    // through parse) so `computeMd5` below can hash them in erts' fixed order,
    // independent of the on-disk chunk order.
    var md5 = Md5Chunks{};

    var pos: usize = 12;
    while (pos + 8 <= file_bytes.len) {
        const name = file_bytes[pos .. pos + 4];
        const size = std.mem.readInt(u32, file_bytes[pos + 4 ..][0..4], .big);
        if (size > file_bytes.len - (pos + 8)) return error.InvalidBytecode;
        const payload = file_bytes[pos + 8 .. pos + 8 + size];
        pos += 8 + ((size + 3) / 4) * 4;

        if (std.mem.eql(u8, name, "AtU8")) {
            md5.atu8 = payload;
            var r = Reader{ .buf = payload };
            const raw = try r.u32be();
            // Long-atom-table flag (OTP-28+): a NEGATIVE count field signals the
            // long form — |count| atoms, each length COMPACT-term encoded (so a
            // name may exceed 255 bytes). A non-negative count is the legacy
            // form: plain u8 length prefixes. One branch decides which; this is
            // what lets host-28 erlc-compiled modules (E0.6 corpus) load at all.
            const long_form = (raw & 0x8000_0000) != 0;
            const n: u32 = if (long_form) (~raw +% 1) else raw;
            const list = try a.alloc([]const u8, n + 1);
            list[0] = "";
            for (1..n + 1) |k| {
                const len: usize = if (long_form)
                    @intCast(try decodeValue(&r, try r.u8_()))
                else
                    try r.u8_();
                list[k] = try a.dupe(u8, try r.bytes(len));
            }
            atoms = list;
        } else if (std.mem.eql(u8, name, "ImpT")) {
            md5.impt = payload;
            var r = Reader{ .buf = payload };
            const n = try r.u32be();
            const list = try a.alloc([3]u32, n);
            for (list) |*row| {
                row[0] = try r.u32be();
                row[1] = try r.u32be();
                row[2] = try r.u32be();
            }
            imports = list;
        } else if (std.mem.eql(u8, name, "ExpT")) {
            md5.expt = payload;
            var r = Reader{ .buf = payload };
            const n = try r.u32be();
            const list = try a.alloc([3]u32, n);
            for (list) |*row| {
                row[0] = try r.u32be();
                row[1] = try r.u32be();
                row[2] = try r.u32be();
            }
            exports = list;
        } else if (std.mem.eql(u8, name, "Code")) {
            md5.code = payload;
            var r = Reader{ .buf = payload };
            const head_size = try r.u32be();
            _ = try r.u32be(); // instruction set version
            _ = try r.u32be(); // max opcode
            labels = try r.u32be();
            _ = try r.u32be(); // function count
            r.pos = 4 + head_size; // header is head_size bytes after the field
            code_bytes = try a.dupe(u8, payload[r.pos..]);
            var cr = Reader{ .buf = code_bytes };
            var ops: std.ArrayList(Op) = .empty;
            while (!cr.done()) {
                const opcode: u16 = try cr.u8_();
                const info = op_table[opcode] orelse return error.UnknownOpcode;
                const args = try a.alloc(Operand, info.arity);
                for (args) |*arg| arg.* = try decodeOperand(&cr, a);
                try ops.append(a, .{ .opcode = opcode, .args = args });
                if (std.mem.eql(u8, info.name, "int_code_end")) break;
            }
            code = try ops.toOwnedSlice(a);
        } else if (std.mem.eql(u8, name, "FunT")) {
            md5.funt = payload;
            // W-15: the lambda table. A `u32` count, then that many fixed 6×u32
            // records {atom, arity, label, index, num_free, old_uniq}. `make_fun*`
            // opcodes carry an INDEX into this table (an unsigned operand), so
            // without it the loader cannot resolve a closure's code label and
            // (pre-fix) mis-read the index as a raw label → panic on real modules.
            var r = Reader{ .buf = payload };
            const n = try r.u32be();
            const list = try a.alloc(Lambda, n);
            for (list) |*lam| lam.* = .{
                .atom = try r.u32be(),
                .arity = try r.u32be(),
                .label = try r.u32be(),
                .index = try r.u32be(),
                .num_free = try r.u32be(),
                .old_uniq = try r.u32be(),
            };
            lambdas = list;
        } else if (std.mem.eql(u8, name, "LitT")) {
            md5.litt = payload;
            // W-17: the literal table. Payload = `u32be uncompressed-size` then a
            // literal table framed as `u32be count` then, per literal, a `u32be
            // byte-size` + that many external-format bytes. The ON-DISK split is
            // ONLY compression (verified against erts/beam_file.c:
            // `parse_decompressed_literals`, which feeds `erts_decode_ext_size`
            // requiring VERSION_MAGIC in BOTH cases):
            //   * uncompressed-size == 0 → the table follows the field VERBATIM
            //     (OTP-28+ uncompressed form);
            //   * uncompressed-size  > 0 → the table is a zlib blob inflating to
            //     exactly that many bytes (classic erlang:term_to_binary framing).
            // Per the pin every literal carries its `131` VERSION byte in BOTH
            // forms. `materializeLiterals` still PEEKS the per-literal first byte
            // (`131` ⇒ version-ful `etf.decode`; else the version-less entry) —
            // defensive, and unambiguous since `131` is not a valid first term
            // tag. We reuse etf.zig's exact zlib decompressor — no new ETF
            // semantics here. The inflated bytes are copied into the arena (and
            // the compressed variant inflates through `gpa`, so the decoder's
            // scratch window is freed eagerly rather than retained until
            // `Module.deinit`); the uncompressed variant is duped into the arena
            // too, so — like `code_bytes` — `Module.literals` never aliases the
            // caller's `file_bytes`. A malformed chunk (truncated / bad zlib /
            // bad size) surfaces as a clean loader error via the propagated
            // `try`, never a panic.
            var r = Reader{ .buf = payload };
            const unc_size = try r.u32be();
            const table: []const u8 = if (unc_size == 0)
                try a.dupe(u8, payload[r.pos..])
            else blk: {
                const inflated = try etf.inflateZlib(gpa, payload[r.pos..], unc_size);
                defer gpa.free(inflated);
                break :blk try a.dupe(u8, inflated);
            };
            var lr = Reader{ .buf = table };
            const count = try lr.u32be();
            const list = try a.alloc([]const u8, count);
            for (list) |*litbytes| {
                const sz = try lr.u32be();
                litbytes.* = try lr.bytes(sz);
            }
            literals = list;
        } else if (std.mem.eql(u8, name, "StrT")) {
            md5.strt = payload;
            // E3.3: raw byte blob, no internal framing — `bs_match_string`'s
            // Off operand is a plain byte offset into it.
            strtab = try a.dupe(u8, payload);
        } else if (std.mem.eql(u8, name, "Line")) {
            // E3.11: the line-number table for cooked stacktraces. Format per
            // the pin's `beam_file.c` `parse_line_chunk`: version(u32,==0),
            // flags, instr_count, item_count, name_count (all u32be); then
            // `item_count` tagged items — TAG_a switches the current name_index
            // (no item slot), TAG_i is a line number at the current name_index
            // (one item slot); then `name_count` explicit filenames (u16-len +
            // bytes). Item 0 is the "undefined location" sentinel; name 0 is the
            // synthesized `<module>.erl`. A non-zero version is ignored (a
            // future format we don't decode — head frames then get `[]` loc).
            var r = Reader{ .buf = payload };
            const version = try r.u32be();
            if (version == 0) {
                _ = try r.u32be(); // flags
                _ = try r.u32be(); // instr_count (informational)
                const item_count = try r.u32be();
                const name_count = try r.u32be();
                // items[0] is the sentinel; explicit items are 1..item_count.
                const items = try a.alloc(LineItem, item_count + 1);
                items[0] = .{ .name_index = 0, .line = 0 };
                var name_index: u32 = 0;
                var i: usize = 1;
                while (i <= item_count) {
                    const first = try r.u8_();
                    const tag = first & 0b111;
                    const val = try decodeValue(&r, first);
                    if (tag == 2) { // TAG_a: switch filename, no item slot
                        name_index = @intCast(val);
                    } else if (tag == 1) { // TAG_i: a line at name_index
                        items[i] = .{ .name_index = name_index, .line = @intCast(val) };
                        i += 1;
                    } else return error.BadOperand;
                }
                // names[0] = synthesized `<module>.erl` (atoms[1] is the module
                // name by BEAM convention); names[1..] are read from the chunk.
                const names = try a.alloc([]const u8, name_count + 1);
                const mod_name = if (atoms.len > 1) atoms[1] else "";
                names[0] = try std.fmt.allocPrint(a, "{s}.erl", .{mod_name});
                for (1..name_count + 1) |k| {
                    if (r.pos + 2 > r.buf.len) return error.Truncated;
                    const nlen = std.mem.readInt(u16, r.buf[r.pos..][0..2], .big);
                    r.pos += 2;
                    names[k] = try a.dupe(u8, try r.bytes(nlen));
                }
                line_items = items;
                line_names = names;
            }
        } else if (std.mem.eql(u8, name, "Attr")) {
            // E3.12b: the attributes proplist as raw ETF bytes (arena copy so it
            // never aliases `file_bytes`). Decoded on demand by `onLoadFun` to
            // find `{on_load,[{F,A}]}` for load-gating. Never executed.
            attr_bytes = try a.dupe(u8, payload);
        } else if (std.mem.eql(u8, name, "CInf")) {
            // E4.2: the compile-info proplist as raw ETF bytes (arena copy).
            // `module_info(compile)` decodes THIS; not in the md5 hash set.
            compile_bytes = try a.dupe(u8, payload);
        } else if (std.mem.eql(u8, name, "Meta")) {
            md5.meta = payload;
        } else if (std.mem.eql(u8, name, "Recs")) {
            md5.recs = payload;
        } else if (std.mem.eql(u8, name, "DbgB")) {
            md5.dbg = payload;
        }
        // LocT/Dbgi/Type: not hashed (not in erts' checksum set), not needed to
        // run the M8/E1 subset. LitT/StrT/Line/Attr/CInf/Meta/Recs/DbgB above.
    }
    if (code.len == 0) return error.NoCodeChunk;
    // E4.2: the module md5 is defined only when the module carried real chunk
    // bytes (the AtU8 + Code path any erlc output takes). A synthetic Module
    // (hand-built Program, no chunks) has no md5 — `has_md5` guards the BIFs.
    const md5_val = if (md5.atu8.len != 0 or md5.code.len != 0) computeMd5(md5) else null;
    return .{
        .arena = arena,
        .atoms = atoms,
        .imports = imports,
        .exports = exports,
        .code = code,
        .code_bytes = code_bytes,
        .labels = labels,
        .lambdas = lambdas,
        .literals = literals,
        .strtab = strtab,
        .line_items = line_items,
        .line_names = line_names,
        .attr_bytes = attr_bytes,
        .compile_bytes = compile_bytes,
        .mod_md5 = md5_val orelse [_]u8{0} ** 16,
        .has_md5 = md5_val != null,
    };
}

/// E4.2: the raw chunk payloads that feed the module-md5 hash, captured during
/// `parse` as slices into the caller's `file_bytes` (alive for the whole parse).
const Md5Chunks = struct {
    atu8: []const u8 = &.{},
    code: []const u8 = &.{},
    strt: []const u8 = &.{},
    impt: []const u8 = &.{},
    expt: []const u8 = &.{},
    funt: []const u8 = &.{},
    litt: []const u8 = &.{},
    meta: []const u8 = &.{},
    recs: []const u8 = &.{},
    dbg: []const u8 = &.{},
};

/// E4.2: compute the module MD5 EXACTLY as `beam_file.c` does — AtU8, Code,
/// StrT, ImpT, ExpT unconditionally (a size-0 chunk is a no-op update), then
/// FunT/LitT/Meta/Recs/DbgB only when present. The FunT hash IGNORES each
/// entry's `OldUniq` word (the last 4 of every 24-byte record after the 4-byte
/// count): erts zeroes it because it is a broken endian-dependent hash, so a
/// module's checksum is stable across builds. This is the value
/// `erlang:get_module_info(M, md5)` returns.
fn computeMd5(c: Md5Chunks) [16]u8 {
    var h = std.crypto.hash.Md5.init(.{});
    h.update(c.atu8);
    h.update(c.code);
    h.update(c.strt);
    h.update(c.impt);
    h.update(c.expt);
    if (c.funt.len >= 4) {
        h.update(c.funt[0..4]); // the entry count
        var off: usize = 4;
        const zero = [_]u8{0} ** 4;
        while (off + 24 <= c.funt.len) : (off += 24) {
            h.update(c.funt[off .. off + 20]); // Function Arity Index NumFree
            h.update(&zero); // OldUniq zeroed
        }
    }
    if (c.litt.len != 0) h.update(c.litt);
    if (c.meta.len != 0) h.update(c.meta);
    if (c.recs.len != 0) h.update(c.recs);
    if (c.dbg.len != 0) h.update(c.dbg);
    var out: [16]u8 = undefined;
    h.final(&out);
    return out;
}

/// E5.2c (`erts_internal:beamfile_module_md5/1`, DIVERGENCE 75): the module MD5
/// of a WHOLE beam binary, computed by a TOTAL, bounds-checked IFF walk — safe
/// over a HOSTILE argument binary (unlike `parse`, which assumes a well-formed
/// container and may fault on truncation). Returns `null` when `bytes` is not a
/// well-formed FOR1/BEAM container carrying the md5-significant chunks (the erts
/// `beamfile_read`-fail → `undefined` path). For a well-formed beam it is BYTE-EQ
/// to `parse`'s `mod_md5`: both gather the SAME significant chunks (AtU8/Code/
/// StrT/ImpT/ExpT unconditionally + FunT/LitT/Meta/Recs/DbgB when present) into
/// the SAME `Md5Chunks` and feed the SAME `computeMd5`. The walk is the S15
/// container scan `beamfile_chunk`/`parse` share, factored to a hash-only pass.
pub fn beamModuleMd5(bytes: []const u8) ?[16]u8 {
    if (bytes.len < 12 or !std.mem.eql(u8, bytes[0..4], "FOR1") or
        !std.mem.eql(u8, bytes[8..12], "BEAM")) return null;
    var c = Md5Chunks{};
    var pos: usize = 12;
    while (pos + 8 <= bytes.len) {
        const name = bytes[pos .. pos + 4];
        const size = std.mem.readInt(u32, bytes[pos + 4 ..][0..4], .big);
        const data_start = pos + 8;
        if (data_start + size > bytes.len) return null; // truncated chunk → malformed
        const payload = bytes[data_start .. data_start + size];
        if (std.mem.eql(u8, name, "AtU8")) {
            c.atu8 = payload;
        } else if (std.mem.eql(u8, name, "Code")) {
            c.code = payload;
        } else if (std.mem.eql(u8, name, "StrT")) {
            c.strt = payload;
        } else if (std.mem.eql(u8, name, "ImpT")) {
            c.impt = payload;
        } else if (std.mem.eql(u8, name, "ExpT")) {
            c.expt = payload;
        } else if (std.mem.eql(u8, name, "FunT")) {
            c.funt = payload;
        } else if (std.mem.eql(u8, name, "LitT")) {
            c.litt = payload;
        } else if (std.mem.eql(u8, name, "Meta")) {
            c.meta = payload;
        } else if (std.mem.eql(u8, name, "Recs")) {
            c.recs = payload;
        } else if (std.mem.eql(u8, name, "DbgB")) {
            c.dbg = payload;
        }
        pos = data_start + ((size + 3) / 4) * 4; // 4-byte chunk alignment
    }
    if (c.atu8.len == 0 and c.code.len == 0) return null; // no md5-bearing chunks
    return computeMd5(c);
}

// ============================================================================
// emit — the assembler direction (minimal compact encoding, like beam_asm)
// ============================================================================

fn emitValue(out: *std.ArrayList(u8), gpa: std.mem.Allocator, tag: u3, value: u64) !void {
    if (value < 16) {
        try out.append(gpa, @intCast((value << 4) | tag));
    } else if (value < 2048) {
        try out.append(gpa, @intCast(((value >> 8) << 5) | 0b1000 | tag));
        try out.append(gpa, @truncate(value));
    } else {
        // n-byte big-endian, minimal length (no leading zero byte unless
        // needed for sign — unsigned here, so none)
        var tmp: [8]u8 = undefined;
        var n: usize = 0;
        var v = value;
        while (v > 0) : (v >>= 8) {
            tmp[n] = @truncate(v);
            n += 1;
        }
        try out.append(gpa, @intCast(((@as(u64, n) - 2) << 5) | 0b11000 | tag));
        while (n > 0) {
            n -= 1;
            try out.append(gpa, tmp[n]);
        }
    }
}

fn emitValueSigned(out: *std.ArrayList(u8), gpa: std.mem.Allocator, tag: u3, value: i64) !void {
    if (value >= 0) return emitValue(out, gpa, tag, @intCast(value));
    // negative: n-byte two's complement, minimal
    var n: usize = 1;
    while (n < 8) : (n += 1) {
        const shift: u6 = @intCast(64 - 8 * n);
        const trunc = (@as(i64, @bitCast(@as(u64, @bitCast(value)) << shift)) >> shift);
        if (trunc == value) break;
    }
    if (n < 2) n = 2;
    try out.append(gpa, @intCast(((@as(u64, n) - 2) << 5) | 0b11000 | tag));
    var k = n;
    while (k > 0) {
        k -= 1;
        try out.append(gpa, @truncate(@as(u64, @bitCast(value)) >> @intCast(8 * k)));
    }
}

/// triage-big-divergences: emit a 9..16-byte signed integer operand (the
/// `.ibig` decode partner) via the size-EXTENSION header form the decoder's
/// `(first >> 5) == 7` arm reads: header (7<<5)|0b11000|tag, then the extra
/// size (n-9) as a compact u value, then n big-endian two's-complement bytes.
fn emitValueSignedWide(out: *std.ArrayList(u8), gpa: std.mem.Allocator, tag: u3, value: i128) !void {
    // minimal byte length that round-trips the value (sign included)
    var n: usize = 1;
    while (n < 16) : (n += 1) {
        const shift: u7 = @intCast(128 - 8 * n);
        const trunc = (@as(i128, @bitCast(@as(u128, @bitCast(value)) << shift)) >> shift);
        if (trunc == value) break;
    }
    if (n <= 8) return emitValueSigned(out, gpa, tag, @intCast(value));
    try out.append(gpa, @intCast((7 << 5) | 0b11000 | @as(u64, tag)));
    try out.append(gpa, @intCast((n - 9) << 4)); // compact 4-bit-immediate u
    var k = n;
    while (k > 0) {
        k -= 1;
        try out.append(gpa, @truncate(@as(u128, @bitCast(value)) >> @intCast(8 * k)));
    }
}

/// gap-bigint-operand: re-emit an `.ibigbytes` operand (the decode partner) — the
/// big-endian two's-complement of (sign, LE magnitude), with a leading sign byte
/// when the magnitude's top bit is set (positivity/negativity), via the ≥9-byte
/// size-extension header. Round-trips every erlc-emitted wide inline int.
fn emitValueSignedBytes(out: *std.ArrayList(u8), gpa: std.mem.Allocator, tag: u3, positive: bool, mag_le: []const u8) !void {
    const nmag = mag_le.len;
    const need_sign = (mag_le[nmag - 1] & 0x80) != 0; // top magnitude bit → an extra sign byte
    const size = if (need_sign) nmag + 1 else nmag;
    var buf: [257]u8 = undefined;
    if (positive) {
        var off: usize = 0;
        if (need_sign) {
            buf[0] = 0;
            off = 1;
        }
        for (0..nmag) |k| buf[off + k] = mag_le[nmag - 1 - k]; // LE magnitude → BE
    } else {
        var tc: [257]u8 = undefined; // little-endian two's-complement
        var carry: u16 = 1;
        for (0..size) |k| {
            const mv: u8 = if (k < nmag) mag_le[k] else 0;
            const s = (@as(u16, ~mv) & 0xFF) + carry;
            tc[k] = @truncate(s);
            carry = s >> 8;
        }
        for (0..size) |k| buf[k] = tc[size - 1 - k]; // → big-endian
    }
    try out.append(gpa, @intCast((7 << 5) | 0b11000 | @as(u64, tag))); // (first>>5)==7 header
    try emitValue(out, gpa, TAG_U, @intCast(size - 9)); // the extra size, compact
    try out.appendSlice(gpa, buf[0..size]);
}

fn emitOperand(out: *std.ArrayList(u8), gpa: std.mem.Allocator, o: Operand) !void {
    switch (o) {
        .u => |v| try emitValue(out, gpa, TAG_U, v),
        .i => |v| try emitValueSigned(out, gpa, TAG_I, v),
        .ibig => |v| try emitValueSignedWide(out, gpa, TAG_I, v),
        .ibigbytes => |v| try emitValueSignedBytes(out, gpa, TAG_I, v.positive, v.mag_le),
        .flt => |v| { // Z subtag 0 + 8 IEEE big-endian bytes
            try out.append(gpa, (0 << 4) | TAG_Z);
            var b: [8]u8 = undefined;
            std.mem.writeInt(u64, &b, @bitCast(v), .big);
            try out.appendSlice(gpa, &b);
        },
        .atom => |v| try emitValue(out, gpa, TAG_A, v),
        .x => |v| try emitValue(out, gpa, TAG_X, v),
        .y => |v| try emitValue(out, gpa, TAG_Y, v),
        .fr => |v| { // E1.12: {fr,N} — Z-subtag 2 then N as a `u` operand
            try out.append(gpa, (2 << 4) | TAG_Z);
            try emitValue(out, gpa, TAG_U, v);
        },
        .f => |v| try emitValue(out, gpa, TAG_F, v),
        .char => |v| try emitValue(out, gpa, TAG_H, v),
        .lit => |v| {
            try out.append(gpa, (4 << 4) | TAG_Z);
            try emitValue(out, gpa, TAG_U, v);
        },
        .tr => |t| {
            try out.append(gpa, (5 << 4) | TAG_Z);
            switch (t.base) {
                .x => |xr| try emitValue(out, gpa, TAG_X, xr),
                .y => |yr| try emitValue(out, gpa, TAG_Y, yr),
            }
            try emitValue(out, gpa, TAG_U, t.type_idx);
        },
        .alloc => |pairs| {
            try out.append(gpa, (3 << 4) | TAG_Z);
            try emitValue(out, gpa, TAG_U, pairs.len);
            for (pairs) |p| {
                try emitValue(out, gpa, TAG_U, p[0]);
                try emitValue(out, gpa, TAG_U, p[1]);
            }
        },
        .list => |ops| {
            try out.append(gpa, (1 << 4) | TAG_Z);
            try emitValue(out, gpa, TAG_U, ops.len);
            for (ops) |sub| try emitOperand(out, gpa, sub);
        },
    }
}

/// Re-encode a parsed op stream. With minimal encodings on both sides this
/// must be BYTE-IDENTICAL to the compiler's output (the emit∘parse law).
pub fn emit(gpa: std.mem.Allocator, code: []const Op) !std.ArrayList(u8) {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (code) |op| {
        try out.append(gpa, @intCast(op.opcode));
        for (op.args) |arg| try emitOperand(&out, gpa, arg);
    }
    return out;
}

// ============================================================================
// translate — generic ops → the machine's instruction algebra
// ============================================================================

pub const Entry = struct { name: []const u8, arity: u32, pc: u32 };

pub const Translated = struct {
    prog: []ia.CInstr,
    /// label id → pc in prog
    label_pc: []u32,
    /// export (function-atom, arity) → entry pc
    entries: []Entry,
    /// E3.11: pc → source location (`{mfa, line, file}`), parallel to `prog`.
    /// Built from the `func_info` boundaries + the `Line` chunk. `Machine.locs`
    /// borrows this; `freeProg` frees it. Empty when the module has no code
    /// (never, `NoCodeChunk` guards) — otherwise one entry per instruction.
    locs: []ia.Loc = &.{},
};

const TranslateError = error{ OutOfMemory, UnsupportedOp, BadOperand, AtomTableFull };

/// E5.2 (DIVERGENCE 46 DISCHARGE): map a BEAM x-register index (`Operand.x`/`.tr`
/// base is a `u8`) into the ISA's x-register slot. The register file was a
/// 16-slot (`u4`) bank, so a module allocating a 17th x-register (`prim_inet`,
/// `prim_zip` reach x16) was REJECTED with `error.RegisterOverflow`. E5.2 widens
/// `ia.XReg` to `u8` with an `ia.x_reg_count`-slot backing bank — the FULL
/// decodable index range — so this narrowing is now TOTAL (every `u8` index is
/// representable, no overflow is reachable) and every well-formed preloaded
/// `.beam` loads. Kept as a documented named helper (rather than inlined) so the
/// "x-register decode" site stays one auditable point.
fn xReg(r: u8) ia.XReg {
    return r;
}

/// triage-big-divergences: an integer OPERAND outside the small range cannot be
/// an `.imm` — `Machine.resolve(.imm)` builds via `FinalTerms.int`, whose
/// fits-small assert is a REPRESENTATION invariant (the canonical small/big
/// boundary), so a (2^59, 2^63) operand PANICKED the VM and a wider one was
/// silently truncated at decode. The fix mirrors what erts itself does (bignum
/// operands live on a heap the loader prepares): synthesize a tiny ETF
/// SMALL_BIG_EXT blob into the module's literal table and emit `.literal` — the
/// existing W-17 literal machinery materializes it onto each executing heap.
/// Zero new runtime cost; `resolve` is untouched.
fn synthBigIntLiteral(mod: *Module, v: i128) TranslateError!ia.Src {
    const a = mod.arena.allocator();
    const mag: u128 = @abs(v);
    var bytes: [16]u8 = undefined;
    var n: usize = 0;
    var m = mag;
    while (m != 0) : (m >>= 8) {
        bytes[n] = @truncate(m);
        n += 1;
    }
    // [131, SMALL_BIG_EXT(110), n, sign, magnitude little-endian] — the exact
    // framing materializeLiterals/etf.decode already accept (W-17: literals
    // carry their version byte).
    const blob = try a.alloc(u8, 4 + n);
    blob[0] = 131;
    blob[1] = 110; // SMALL_BIG_EXT
    blob[2] = @intCast(n);
    blob[3] = if (v < 0) 1 else 0;
    @memcpy(blob[4..], bytes[0..n]);
    const grown = try a.alloc([]const u8, mod.literals.len + 1);
    @memcpy(grown[0..mod.literals.len], mod.literals);
    grown[mod.literals.len] = blob;
    mod.literals = grown;
    return .{ .literal = @intCast(mod.literals.len - 1) };
}

/// gap-bigint-operand: the arbitrary-precision sibling of `synthBigIntLiteral` — a
/// >i128 inline int operand materializes as a SMALL_BIG_EXT literal directly from
/// its (sign, little-endian magnitude) bytes (n ≤ 255, the decode cap).
fn synthBigIntLiteralBytes(mod: *Module, positive: bool, mag_le: []const u8) TranslateError!ia.Src {
    const a = mod.arena.allocator();
    const n = mag_le.len;
    const blob = try a.alloc(u8, 4 + n);
    blob[0] = 131;
    blob[1] = 110; // SMALL_BIG_EXT
    blob[2] = @intCast(n);
    blob[3] = if (positive) 0 else 1;
    @memcpy(blob[4..], mag_le);
    const grown = try a.alloc([]const u8, mod.literals.len + 1);
    @memcpy(grown[0..mod.literals.len], mod.literals);
    grown[mod.literals.len] = blob;
    mod.literals = grown;
    return .{ .literal = @intCast(mod.literals.len - 1) };
}

/// batch-4: the float sibling of `synthBigIntLiteral` — an inline float
/// operand materializes as a synthesized NEW_FLOAT_EXT literal (tag 70,
/// 8 IEEE-754 big-endian bytes), riding the same W-17 literal machinery.
fn synthFloatLiteral(mod: *Module, v: f64) TranslateError!ia.Src {
    const a = mod.arena.allocator();
    const blob = try a.alloc(u8, 10);
    blob[0] = 131;
    blob[1] = 70; // NEW_FLOAT_EXT
    std.mem.writeInt(u64, blob[2..10], @bitCast(v), .big);
    const grown = try a.alloc([]const u8, mod.literals.len + 1);
    @memcpy(grown[0..mod.literals.len], mod.literals);
    grown[mod.literals.len] = blob;
    mod.literals = grown;
    return .{ .literal = @intCast(mod.literals.len - 1) };
}

fn srcOf(mod: *Module, atoms: *AtomTable, o: Operand) TranslateError!ia.Src {
    return switch (o) {
        .x => |r| .{ .x = xReg(r) },
        .y => |r| .{ .y = r },
        .i => |v| if (ta.fitsSmall(v)) .{ .imm = v } else try synthBigIntLiteral(mod, v),
        .ibig => |v| try synthBigIntLiteral(mod, v),
        .ibigbytes => |v| try synthBigIntLiteralBytes(mod, v.positive, v.mag_le),
        .flt => |v| try synthFloatLiteral(mod, v),
        .u => |v| if (v < (1 << 59)) .{ .imm = @intCast(v) } else try synthBigIntLiteral(mod, v),
        .atom => |idx| blk: {
            if (idx == 0) break :blk .nil; // atom index 0 encodes []
            const ai = atoms.intern(mod.atomName(idx)) catch return error.AtomTableFull;
            break :blk .{ .atom_ = ai };
        },
        .tr => |t| switch (t.base) {
            .x => |r| .{ .x = xReg(r) },
            .y => |r| .{ .y = r },
        },
        // W-17: a `.lit N` operand names LitT slot N. Checked exactly like the
        // W-16 `uOf`/`labelIdOf` helpers: out of range → error.BadOperand, never
        // a raw union access. The term itself is decoded into the executing
        // machine's ctx later (`materializeLiterals`); here we carry only the
        // validated index so the same program can serve machines with distinct
        // heaps (the differential engine).
        .lit => |n| if (n < mod.literals.len) ia.Src{ .literal = n } else error.BadOperand,
        else => error.BadOperand,
    };
}

fn dstOf(o: Operand) TranslateError!ia.Dst {
    return switch (o) {
        .x => |r| .{ .x = xReg(r) },
        .y => |r| .{ .y = r },
        .tr => |t| switch (t.base) {
            .x => |r| .{ .x = xReg(r) },
            .y => |r| .{ .y = r },
        },
        else => error.BadOperand,
    };
}

fn xOf(o: Operand) TranslateError!ia.XReg {
    return switch (o) {
        .x => |r| xReg(r),
        .tr => |t| switch (t.base) {
            .x => |r| xReg(r),
            else => error.BadOperand,
        },
        else => error.BadOperand,
    };
}

/// E1.12: extract a floating-point register index (0..15) from an `.fr` operand.
/// The FR bank has 16 slots (`Machine.fregs`), so the index is a `u4`.
fn frOf(o: Operand) TranslateError!u4 {
    return switch (o) {
        .fr => |n| if (n < 16) @intCast(n) else error.BadOperand,
        else => error.BadOperand,
    };
}

/// E1.6: resolve a `select_val` key Operand to a ctx-free immediate Term. Keys
/// are compile-time literals (small integer / atom / nil); registers and
/// heap-needing literals are rejected (no case compiles a select on them). The
/// Term is built WITHOUT a Ctx — small ints and atoms are immediates whose
/// encoding never touches the heap — so it matches exactly what `execInstr`'s
/// `resolve` produces for the same Src at run time (thus `eqlExact` agrees).
fn selectKeyTerm(mod: *Module, atoms: *AtomTable, o: Operand) TranslateError!FinalTerms.Term {
    const src = try srcOf(mod, atoms, o);
    return switch (src) {
        .imm => |v| if (ta.fitsSmall(v)) FinalTerms.int(undefined, v) else error.BadOperand,
        .atom_ => |ai| FinalTerms.atomTerm(ai),
        .nil => FinalTerms.nil_term,
        // W-17: a heap-literal select key (a `.lit` naming a tuple/list/… term)
        // has no ctx-free immediate encoding, so it cannot be a select key under
        // the E1.6 immediate-key model — reject cleanly (E3 widens this). Small
        // int / atom / nil keys still arrive as `.imm`/`.atom_`/`.nil` above.
        .literal => error.BadOperand,
        else => error.BadOperand,
    };
}

/// E3.14: decode an atom operand to its ctx-free immediate Term (native-record
/// field names, module/name tags). A non-atom operand is `error.BadOperand`.
fn atomTermOf(mod: *Module, atoms: *AtomTable, o: Operand) TranslateError!FinalTerms.Term {
    const src = try srcOf(mod, atoms, o);
    return switch (src) {
        .atom_ => |ai| FinalTerms.atomTerm(ai),
        else => error.BadOperand,
    };
}

/// E1.6: extract a label id from an `.f` (label) Operand — the odd entries of a
/// select list. Fixed up to a pc by `translate`'s patch pass.
fn labelIdOf(o: Operand) TranslateError!u16 {
    return switch (o) {
        .f => |l| @intCast(l),
        else => error.BadOperand,
    };
}

/// W-16: extract an unsigned literal from a `.u` operand. Every translate arm
/// that reads an operand as a `.u` count/index/arity routes through here, so a
/// well-formed-but-differently-tagged operand yields `error.BadOperand` instead
/// of a "union field 'u' while field X is active" PANIC. Behavior-preserving on
/// the decode path: a real `.u` operand returns its value unchanged.
fn uOf(o: Operand) TranslateError!u64 {
    return switch (o) {
        .u => |v| v,
        else => error.BadOperand,
    };
}

/// W-19: extract a non-negative integer count/arity from EITHER a `.u`
/// (unsigned literal) OR a `.i` (signed integer literal) operand. Real erlc
/// emits most counts (allocate/trim/get_tuple_element/deallocate/…) via the
/// compact `.u` tag, but `is_function2`'s Arity operand is compiled through
/// the general integer-literal path and arrives as a signed `.i` — confirmed
/// by `beam_disasm` on the curated OTP corpus (`is_function2` args render as
/// `{integer,N}`, every other count/arity op above renders as a bare `.u`
/// count). A negative `.i` is not a valid count/arity, so it is
/// `error.BadOperand` (never a panic on well-formed-but-negative input,
/// mirroring the W-16 `uOf`/`labelIdOf`/`listOf` checked-helper shape). Any
/// other operand tag is likewise `error.BadOperand`.
fn intArgOf(o: Operand) TranslateError!u64 {
    return switch (o) {
        .u => |v| v,
        .i => |s| if (s >= 0) @intCast(s) else error.BadOperand,
        else => error.BadOperand,
    };
}

// E5.2 (DIVERGENCE 47 DISCHARGE): `get_map_elements`/`has_map_fields` keys are
// now runtime `Src`s decoded via `srcOf` (a literal OR a register key), resolved
// by `execInstr` at run time — so the former `isRegisterOperand` pre-check /
// `<op>-register-key` UnsupportedOp reject is gone (no key operand is rejected).

/// W-16: extract a select/env/element list from a `.list` operand. Same guard
/// rationale as `uOf`/`labelIdOf`: a non-`.list` operand is `error.BadOperand`,
/// never a panic. The returned slice is borrowed from `mod` (not owned).
fn listOf(o: Operand) TranslateError![]const Operand {
    return switch (o) {
        .list => |l| l,
        else => error.BadOperand,
    };
}

/// E1.13/E2.2: decode a `bif`/`gc_bif` form (INCLUDING `gc_bif2`) into ONE
/// `ia.bif_call` CInstr. The BIF import ref is resolved through the SINGLE
/// resolver `bif_dispatch.resolve` over the generated `bif_table`, keyed on the
/// full module+name+arity: an executable BIF → `.op`, anything else (stub/
/// justified/unknown) → `.unsupported` — NOT a load error, so the opcode is
/// TOTAL and traps `undef` at runtime (coverage is E2; the `apply` trap-vs-
/// reject precedent). E2.2 retired the old `gc_bif2` load-reject and the E1.13
/// `argc==2 && module=="erlang"` special-case: resolution is now arity- and
/// module-precise and identical across every `bif`/`gc_bif` form.
/// `fail_op` is the BEAM Fail label: absent (`bif0`) or `0`
/// ⇒ BODY context (`else_to = null`, failure crashes); non-zero ⇒ GUARD context
/// (`else_to = label`, failure branches). `live_op` is the `gc_bif` Live hint
/// (advisory; recorded, not acted on). `args` is a fixed inline `[3]Src` (arity
/// ≤ 3): NO owned slice, so `freeProg`/`peephole` need no new arm.
fn bifCallOf(
    mod: *Module,
    atoms: *AtomTable,
    bif_op: Operand,
    arg_ops: []const Operand,
    dst_op: Operand,
    fail_op: ?Operand,
    live_op: ?Operand,
) TranslateError!ia.CInstr {
    if (arg_ops.len > 3) return error.BadOperand;
    const bidx = switch (bif_op) {
        .u => |v| v,
        else => return error.BadOperand,
    };
    if (bidx >= mod.imports.len) return error.BadOperand;
    const imp = mod.imports[bidx];
    const module = mod.atomName(imp[0]);
    const fname = mod.atomName(imp[1]);
    const argc: u8 = @intCast(arg_ops.len);
    // E2.2: ONE resolver over the generated bif_table, keyed on the full
    // module+name+arity triple (`bif_dispatch.resolve`). An executable BIF → its
    // `.op`; anything else (stub/justified/unknown) → `.unsupported`, which the
    // executor traps as `undef` at RUNTIME — never a loader reject. This replaces
    // the E1.13 `argc==2 && module=="erlang"` special-case: resolution is now
    // arity- AND module-precise, and gc_bif2 shares this exact path.
    const ref: ia.BifRef = if (bif_dispatch.resolve(module, fname, argc)) |o|
        .{ .func = o }
    else
        .unsupported;
    var args: [3]ia.Src = .{ .nil, .nil, .nil };
    for (arg_ops, 0..) |a, k| args[k] = try srcOf(mod, atoms, a);
    const else_to: ?u32 = if (fail_op) |f| switch (f) {
        .f => |l| if (l == 0) null else @as(u16, @intCast(l)),
        else => return error.BadOperand,
    } else null;
    const gc_live: ?u8 = if (live_op) |l| switch (l) {
        .u => |v| @intCast(v),
        else => return error.BadOperand,
    } else null;
    return .{ .bif_call = .{
        .bif = ref,
        .args = args,
        .argc = argc,
        .dst = try dstOf(dst_op),
        .else_to = else_to,
        .gc_live = gc_live,
    } };
}

/// E3.3: decode a `bs_*` Flags operand (`erl_bits.h`'s `BSF_*`, cited against
/// the pin): bit0 `BSF_ALIGNED` (unused here — this VM's bitstrings are
/// ALWAYS canonically packed, see `bitstring_algebra`'s invariant, so
/// alignment is never a distinct code path); bit1 `BSF_LITTLE`; bit2
/// `BSF_SIGNED`; bit4 `BSF_NATIVE` (resolved to the HOST's actual
/// endianness right here, at translate time, so `execInstr` only ever
/// switches on the two concrete `BsEndian` values).
fn bsFlagsOf(o: Operand) TranslateError!struct { signed: bool, endian: ia.BsEndian } {
    const raw = try uOf(o);
    const native_little = @import("builtin").cpu.arch.endian() == .little;
    const little = (raw & 2) != 0 or ((raw & 16) != 0 and native_little);
    return .{ .signed = (raw & 4) != 0, .endian = if (little) .little else .big };
}

/// E3.3: decode a `bs_start_match3`/`bs_start_match4` Fail operand. Real
/// `bs_start_match3` always carries a numeric label (`.f`); `bs_start_match4`
/// (OTP 23+) may instead carry the atom `no_fail` or `resume` (the compiler's
/// static proof the match cannot fail / is resuming an existing context) —
/// per `beam_loader`'s existing `bif_call` convention (see `bifCallOf`), a
/// `.f` label of 0 OR either atom decodes to `else_to = null` ("cannot
/// fail" — the executor takes the unconditional success path).
fn bsStartFailOf(mod: *Module, atoms: *AtomTable, o: Operand) TranslateError!?u32 {
    return switch (o) {
        .f => |l| if (l == 0) null else @as(u16, @intCast(l)),
        .atom => |idx| blk: {
            _ = try srcOf(mod, atoms, Operand{ .atom = idx }); // validates the atom index
            break :blk null;
        },
        else => error.BadOperand,
    };
}

/// E3.3: decode `bs_match/3`'s `{commands, Commands}` operand — a FLAT
/// `.list` where each command tuple `{Tag, Field...}` is spliced as
/// `[{atom,Tag}, Field...]` (see `ia.BsCmd`'s doc comment for the pin
/// citation). Returns a gpa-owned `[]ia.BsCmd` (freed by `freeProg`/this
/// function's own `errdefer`, exactly like `put_tuple2.elems`). A malformed
/// list (wrong tag, wrong field count/type) is `error.BadOperand` — never a
/// panic on well-formed-but-differently-shaped input (W-16 discipline).
fn bsCommandsOf(gpa: std.mem.Allocator, mod: *Module, atoms: *AtomTable, list: []const Operand) TranslateError![]ia.BsCmd {
    var out: std.ArrayList(ia.BsCmd) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < list.len) {
        const tag_idx: u32 = switch (list[i]) {
            .atom => |a| a,
            else => return error.BadOperand,
        };
        const tag = mod.atomName(tag_idx);
        const eq = std.mem.eql;
        i += 1;
        if (eq(u8, tag, "ensure_at_least")) {
            if (i + 2 > list.len) return error.BadOperand;
            try out.append(gpa, .{ .ensure_at_least = .{
                .stride = @intCast(try uOf(list[i])),
                .unit = @intCast(try uOf(list[i + 1])),
            } });
            i += 2;
        } else if (eq(u8, tag, "ensure_exactly")) {
            if (i + 1 > list.len) return error.BadOperand;
            try out.append(gpa, .{ .ensure_exactly = .{ .stride = @intCast(try uOf(list[i])) } });
            i += 1;
        } else if (eq(u8, tag, "integer") or eq(u8, tag, "binary")) {
            // {integer|binary, Live, Flags, Size, Unit, Dst}. E3.3-fix
            // (discovered building E3.4's differential corpus): Flags here
            // is the OTP-25+ "field_flags" shape (nil / a literal atom-list
            // reference — `bsFieldFlagsOf`), NOT the OLDER `bs_get_integer2`-
            // style pre-packed `.u` bitmask `bsFlagsOf` decodes — `bs_match`
            // is itself an OTP-25+ instruction, confirmed against a freshly
            // `erlc`-compiled fixture LOADED THROUGH THIS LOADER (see the
            // E3.4 report). Using `bsFlagsOf` here always hit `error.BadOperand`
            // on real compiled code carrying a non-empty flags list (a `.lit`
            // operand, not `.u`) — this is what `--run-erl-corpus` surfaced.
            if (i + 5 > list.len) return error.BadOperand;
            const flags = try bsFieldFlagsOf(gpa, mod, atoms, list[i + 1]);
            const size = try srcOf(mod, atoms, list[i + 2]);
            const unit: u8 = @intCast(try uOf(list[i + 3]));
            const dst = try dstOf(list[i + 4]);
            if (eq(u8, tag, "integer")) {
                try out.append(gpa, .{ .integer = .{ .size = size, .unit = unit, .signed = flags.signed, .endian = flags.endian, .dst = dst } });
            } else {
                try out.append(gpa, .{ .binary = .{ .size = size, .unit = unit, .dst = dst } });
            }
            i += 5;
        } else if (eq(u8, tag, "skip")) {
            if (i + 1 > list.len) return error.BadOperand;
            try out.append(gpa, .{ .skip = .{ .stride = @intCast(try uOf(list[i])) } });
            i += 1;
        } else if (eq(u8, tag, "get_tail")) {
            // {get_tail, Live, Unit, Dst}
            if (i + 3 > list.len) return error.BadOperand;
            try out.append(gpa, .{ .get_tail = .{ .unit = @intCast(try uOf(list[i + 1])), .dst = try dstOf(list[i + 2]) } });
            i += 3;
        } else if (eq(u8, tag, "=:=")) {
            // {'=:=', Live, Size, Value}
            if (i + 3 > list.len) return error.BadOperand;
            const size: u32 = @intCast(try uOf(list[i + 1]));
            const value = try selectKeyTerm(mod, atoms, list[i + 2]);
            try out.append(gpa, .{ .eq = .{ .size = size, .value = value } });
            i += 3;
        } else return error.BadOperand;
    }
    return out.toOwnedSlice(gpa);
}

/// E3.4 (also an E3.3 fix — see the E3.4 report): decode a Flags operand in
/// the OTP-25+ "field_flags" on-disk shape — EITHER the bare atom `nil` (no
/// flags) OR a `.lit` (LitT-table) reference to a literal proper list of
/// atoms (`little`/`native`/`signed`) — confirmed against a freshly
/// `erlc`-compiled fixture LOADED THROUGH THIS LOADER (not just read off
/// `beam_disasm`'s symbolic output): `bs_create_bin`'s per-segment Flags
/// AND, discovered while building E3.4's differential corpus, `bs_match/3`'s
/// embedded `integer`/`binary` sub-command Flags (E3.3 wrongly assumed these
/// shared `bs_get_integer2`'s OLDER pre-packed `.u` BSF_* bitmask shape —
/// `bsFlagsOf` above, which remains correct for the standalone R12B-era ops
/// `bs_get_integer2`/`bs_get_float2`/`bs_get_binary2`/`bs_skip_bits2`, whose
/// flags genuinely ARE compile-time-packed to `.u`). The literal is decoded
/// through `etf.decode` into a throwaway `Ctx` (freed immediately after) —
/// the SAME external-term-format reader every other LitT literal in this
/// loader goes through (`materializeLiterals`), just invoked early, at
/// translate time, for this one small atom-list operand.
fn bsFieldFlagsOf(gpa: std.mem.Allocator, mod: *Module, atoms: *AtomTable, o: Operand) TranslateError!struct { signed: bool, endian: ia.BsEndian } {
    const native_little = @import("builtin").cpu.arch.endian() == .little;
    switch (o) {
        .atom => |idx| {
            if (idx != 0) return error.BadOperand; // must be nil ([])
            return .{ .signed = false, .endian = .big };
        },
        .lit => |n| {
            if (n >= mod.literals.len) return error.BadOperand;
            var ctx = FinalTerms.Ctx.init(gpa, atoms);
            defer ctx.deinit();
            const term = etf.decode(gpa, &ctx, mod.literals[n]) catch return error.BadOperand;
            var little = false;
            var signed = false;
            var cur = term;
            while (FinalTerms.kindOf(&ctx, cur) == .cons) {
                const h = FinalTerms.listHead(&ctx, cur);
                if (FinalTerms.repIsAtom(h)) {
                    const nm = atoms.nameOf(FinalTerms.atomIdxOf(h));
                    if (std.mem.eql(u8, nm, "little")) little = true;
                    if (std.mem.eql(u8, nm, "native") and native_little) little = true;
                    if (std.mem.eql(u8, nm, "signed")) signed = true;
                }
                cur = FinalTerms.listTail(&ctx, cur);
            }
            return .{ .signed = signed, .endian = if (little) .little else .big };
        },
        else => return error.BadOperand,
    }
}

/// E3.4: decode `bs_create_bin/6`'s `OpList` — a FLAT `.list` where each
/// logical segment `{Type,Seg,Unit,Flags,Val,Size}` is spliced as 6
/// consecutive operands (confirmed against `beam_disasm.erl`'s
/// `resolve_bs_create_bin_list/2` AND a freshly `erlc`-compiled fixture
/// disassembled with `beam_disasm:file/1` — see the E3.4 report for the
/// exact dump). `Seg` (args[i+1], a segment NUMBER used only for erts' own
/// error-message text) is decoded-and-discarded. Returns a gpa-owned
/// `[]ia.BsSeg` (freed by `freeProg`/this function's own `errdefer`,
/// mirroring `bsCommandsOf`).
fn bsCreateSegsOf(gpa: std.mem.Allocator, mod: *Module, atoms: *AtomTable, list: []const Operand) TranslateError![]ia.BsSeg {
    var out: std.ArrayList(ia.BsSeg) = .empty;
    errdefer {
        for (out.items) |s| switch (s) {
            .string => |st| gpa.free(st.bytes),
            else => {},
        };
        out.deinit(gpa);
    }
    var i: usize = 0;
    while (i < list.len) {
        if (i + 6 > list.len) return error.BadOperand;
        const type_idx: u32 = switch (list[i]) {
            .atom => |a| a,
            else => return error.BadOperand,
        };
        const type_name = mod.atomName(type_idx);
        _ = try uOf(list[i + 1]); // Seg: decoded-and-discarded
        const unit: u8 = @intCast(try uOf(list[i + 2]));
        const eq = std.mem.eql;
        if (eq(u8, type_name, "integer")) {
            const endian = (try bsFieldFlagsOf(gpa, mod, atoms, list[i + 3])).endian;
            const src = try srcOf(mod, atoms, list[i + 4]);
            const size = try srcOf(mod, atoms, list[i + 5]);
            try out.append(gpa, .{ .integer = .{ .src = src, .size = size, .unit = unit, .endian = endian } });
        } else if (eq(u8, type_name, "float")) {
            const endian = (try bsFieldFlagsOf(gpa, mod, atoms, list[i + 3])).endian;
            const src = try srcOf(mod, atoms, list[i + 4]);
            const size = try srcOf(mod, atoms, list[i + 5]);
            try out.append(gpa, .{ .float = .{ .src = src, .size = size, .unit = unit, .endian = endian } });
        } else if (eq(u8, type_name, "binary")) {
            const src = try srcOf(mod, atoms, list[i + 4]);
            const is_all = switch (list[i + 5]) {
                .atom => |a| eq(u8, mod.atomName(a), "all"),
                else => false,
            };
            if (is_all) {
                try out.append(gpa, .{ .binary_all = .{ .src = src } });
            } else {
                const size = try srcOf(mod, atoms, list[i + 5]);
                try out.append(gpa, .{ .binary = .{ .src = src, .size = size, .unit = unit } });
            }
        } else if (eq(u8, type_name, "utf8")) {
            const src = try srcOf(mod, atoms, list[i + 4]);
            try out.append(gpa, .{ .utf8 = .{ .src = src } });
        } else if (eq(u8, type_name, "utf16")) {
            const endian = (try bsFieldFlagsOf(gpa, mod, atoms, list[i + 3])).endian;
            const src = try srcOf(mod, atoms, list[i + 4]);
            try out.append(gpa, .{ .utf16 = .{ .src = src, .endian = endian } });
        } else if (eq(u8, type_name, "utf32")) {
            const endian = (try bsFieldFlagsOf(gpa, mod, atoms, list[i + 3])).endian;
            const src = try srcOf(mod, atoms, list[i + 4]);
            try out.append(gpa, .{ .utf32 = .{ .src = src, .endian = endian } });
        } else if (eq(u8, type_name, "string")) {
            // Val = a `.u` BYTE offset into the module's StrT chunk; Size =
            // the pattern's BYTE length (`intArgOf`: real .beam emits this
            // as `.i`, per the E3.4 report's erlc-fixture dump — tolerate
            // `.u` too, the same W-19 `intArgOf` precedent).
            const off: usize = @intCast(try uOf(list[i + 4]));
            const nbytes: usize = @intCast(try intArgOf(list[i + 5]));
            if (off + nbytes > mod.strtab.len) return error.BadOperand;
            const bytes = try gpa.dupe(u8, mod.strtab[off .. off + nbytes]);
            errdefer gpa.free(bytes);
            try out.append(gpa, .{ .string = .{ .bytes = bytes } });
        } else if (eq(u8, type_name, "append")) {
            const src = try srcOf(mod, atoms, list[i + 4]);
            try out.append(gpa, .{ .append = .{ .src = src } });
        } else if (eq(u8, type_name, "private_append")) {
            const src = try srcOf(mod, atoms, list[i + 4]);
            try out.append(gpa, .{ .private_append = .{ .src = src } });
        } else return error.BadOperand;
        i += 6;
    }
    return out.toOwnedSlice(gpa);
}

/// E1.2: the offending op, filled by `translate` immediately before it returns
/// `error.UnsupportedOp`, so a caller (namely `cli.checkLoad`) can name the op
/// without re-deriving it from the module. `arity` is the DECODED operand
/// count (`op.args.len`), which matches `op_table`'s declared arity for every
/// well-formed op — the same number `dump-caps`/`supported_ops` key on.
pub const UnsupportedOpInfo = struct { name: []const u8, arity: u32 };

pub fn translate(
    gpa: std.mem.Allocator,
    mod: *Module,
    atoms: *AtomTable,
    unsupported_out: ?*UnsupportedOpInfo,
) !Translated {
    var prog: std.ArrayList(ia.CInstr) = .empty;
    // On any error mid-translation, free both the ArrayList backing AND any
    // owned operand sub-slices (`put_tuple2.elems`, the select `pairs`,
    // `make_fun3.env`, the map slices, and `update_record.updates`) — the same
    // set `freeProg` releases on the success path.
    errdefer {
        for (prog.items) |ins| switch (ins) {
            .put_tuple2 => |p| gpa.free(p.elems),
            .select_val => |s| gpa.free(s.pairs),
            .select_tuple_arity => |s| gpa.free(s.pairs),
            .make_fun3 => |f| gpa.free(f.env), // E1.7: owned closure env
            .has_map_fields => |h| gpa.free(h.keys), // E1.10: owned map keys
            .get_map_elements => |g| gpa.free(g.pairs), // E1.10: owned map pairs
            .put_map => |p| gpa.free(p.kvs), // E1.10: owned map kvs
            .update_record => |u| gpa.free(u.updates), // E1.14: owned record updates
            .get_record_elements => |u| gpa.free(u.elems), // E3.14: owned elements
            .put_record => |u| gpa.free(u.updates), // E3.14: owned field updates
            .bs_match => |b| gpa.free(b.cmds), // E3.3: owned sub-command list
            .bs_match_string => |b| gpa.free(b.bytes), // E3.3: owned literal pattern
            .bs_create_bin => |b| freeBsSegs(gpa, b.segs), // E3.4: owned segment list
            else => {},
        };
        prog.deinit(gpa);
    }
    var label_pc = try gpa.alloc(u32, mod.labels + 1);
    errdefer gpa.free(label_pc);
    @memset(label_pc, 0);
    // fixups: prog indices whose u16 target is a LABEL id awaiting patch
    var fixups: std.ArrayList(u32) = .empty;
    defer fixups.deinit(gpa);

    // E3.11: source-location tracking for cooked stacktraces. `cur_loc` is the
    // current frame — its mfa set by `func_info`, its line/file by `line N`
    // (via the `Line` chunk). Each change is recorded as a `{pc, loc}` mark;
    // after translation the marks expand into the per-pc `locs` table.
    var cur_loc: ia.Loc = .{};
    var loc_marks: std.ArrayList(struct { pc: u32, loc: ia.Loc }) = .empty;
    defer loc_marks.deinit(gpa);

    for (mod.code) |op| {
        const name = opName(op.opcode);
        // SINGLE-SOURCE GUARD (E0.5): the dispatch chain below only handles ops
        // listed in `supported_ops`. Reject anything else HERE — before the
        // chain — so the table is the sole arbiter of what translate accepts,
        // and `dump-caps` (which prints the same table) cannot claim an op the
        // loader would refuse. The chain's trailing `else` remains as a
        // belt-and-suspenders assert (a table entry with no chain arm is a bug).
        if (!capSupported(name)) {
            if (unsupported_out) |u| u.* = .{ .name = name, .arity = @intCast(op.args.len) };
            std.debug.print("beam_loader: unsupported op `{s}` ({d})\n", .{ name, op.opcode });
            return error.UnsupportedOp;
        }
        const eql = struct {
            fn f(x: []const u8, y: []const u8) bool {
                return std.mem.eql(u8, x, y);
            }
        }.f;

        if (eql(name, "label")) {
            label_pc[try uOf(op.args[0])] = @intCast(prog.items.len);
        } else if (eql(name, "line")) {
            // E3.11: `line N` indexes the `Line` chunk's item table → the
            // {file, line} for the instructions that FOLLOW. Not emitted (no
            // runtime content — like today); it advances the loc cursor, marked
            // at the pc of the next instruction to be emitted.
            if (op.args.len >= 1) {
                const idx = uOf(op.args[0]) catch 0;
                if (idx < mod.line_items.len) {
                    const item = mod.line_items[idx];
                    cur_loc.line = item.line;
                    if (item.name_index < mod.line_names.len)
                        cur_loc.file = atoms.intern(mod.line_names[item.name_index]) catch return error.AtomTableFull;
                    // else: leave the previous file (or null) — never fabricate one.
                }
            }
            try loc_marks.append(gpa, .{ .pc = @intCast(prog.items.len), .loc = cur_loc });
        } else if (eql(name, "int_code_end")) {
            // no runtime content
        } else if (eql(name, "func_info")) {
            // E3.11: `func_info Module Function Arity` establishes the frame for
            // the code that follows (and crashes function_clause on fallthrough).
            // Its M/F atoms are interned into the RUNTIME atom table so a raise
            // can name the frame; A is the arity `.u`.
            if (op.args.len >= 3) {
                const mi: ?u32 = switch (op.args[0]) {
                    .atom => |x| x,
                    else => null,
                };
                const fi: ?u32 = switch (op.args[1]) {
                    .atom => |x| x,
                    else => null,
                };
                if (mi != null and fi != null and mi.? != 0 and fi.? != 0) {
                    cur_loc.m = atoms.intern(mod.atomName(mi.?)) catch return error.AtomTableFull;
                    cur_loc.f = atoms.intern(mod.atomName(fi.?)) catch return error.AtomTableFull;
                    cur_loc.a = @intCast(uOf(op.args[2]) catch 0);
                }
            }
            try loc_marks.append(gpa, .{ .pc = @intCast(prog.items.len), .loc = cur_loc });
            try prog.append(gpa, .func_info);
        } else if (eql(name, "fmove")) {
            // E1.12: fmove Arg1 Arg2. Direction is decided by which operand is
            // the fr: `fmove Reg FR` loads a float term's f64 into the FR bank;
            // `fmove FR Reg` boxes the FR back to a float term. Exactly one side
            // is an fr (the compiler never emits fr↔fr here).
            switch (op.args[1]) {
                .fr => |fd| try prog.append(gpa, .{ .fmove_to_f = .{
                    .src = try srcOf(mod, atoms, op.args[0]),
                    .fdst = if (fd < 16) @intCast(fd) else return error.BadOperand,
                } }),
                else => switch (op.args[0]) {
                    .fr => |fs| try prog.append(gpa, .{ .fmove_from_f = .{
                        .fsrc = if (fs < 16) @intCast(fs) else return error.BadOperand,
                        .dst = try dstOf(op.args[1]),
                    } }),
                    else => return error.BadOperand,
                },
            }
        } else if (eql(name, "fconv")) {
            // E1.12: fconv Src FDst — numeric term (int OR float) → f64 into FR.
            try prog.append(gpa, .{ .fconv = .{
                .src = try srcOf(mod, atoms, op.args[0]),
                .fdst = try frOf(op.args[1]),
            } });
        } else if (eql(name, "fadd") or eql(name, "fsub") or
            eql(name, "fmul") or eql(name, "fdiv"))
        {
            // E1.12: f<op> Fail FA FB FDst. Fail (args[0]) is the exception route;
            // E1 crashes badarith on a non-finite result (the gc_bif2 precedent:
            // the arith Fail label is not carried), so no label fixup is needed.
            const fa = try frOf(op.args[1]);
            const fb = try frOf(op.args[2]);
            const fd = try frOf(op.args[3]);
            if (eql(name, "fadd")) {
                try prog.append(gpa, .{ .fadd = .{ .a = fa, .b = fb, .fdst = fd } });
            } else if (eql(name, "fsub")) {
                try prog.append(gpa, .{ .fsub = .{ .a = fa, .b = fb, .fdst = fd } });
            } else if (eql(name, "fmul")) {
                try prog.append(gpa, .{ .fmul = .{ .a = fa, .b = fb, .fdst = fd } });
            } else {
                try prog.append(gpa, .{ .fdiv = .{ .a = fa, .b = fb, .fdst = fd } });
            }
        } else if (eql(name, "fnegate")) {
            // E1.12: fnegate Fail FA FDst. Like the binary FR ops, Fail is not
            // carried (E1 crash policy).
            try prog.append(gpa, .{ .fnegate = .{
                .a = try frOf(op.args[1]),
                .fdst = try frOf(op.args[2]),
            } });
        } else if (eql(name, "test_heap")) {
            // heap is dynamic: pure allocation hint, no instruction
        } else if (eql(name, "is_nonempty_list")) {
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .is_cons = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "is_nil")) {
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .test_eq = .{
                .a = try srcOf(mod, atoms, op.args[1]),
                .b = .nil,
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "is_eq_exact")) {
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .test_eq = .{
                .a = try srcOf(mod, atoms, op.args[1]),
                .b = try srcOf(mod, atoms, op.args[2]),
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "is_lt")) {
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .is_lt = .{
                .a = try srcOf(mod, atoms, op.args[1]),
                .b = try srcOf(mod, atoms, op.args[2]),
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (cmpTestKindOf(name)) |op_kind| {
            // E1.4: is_ge/is_eq/is_ne/is_ne_exact. genop order: Lbl, Src, Src.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .cmp_test = .{
                .op = op_kind,
                .a = try srcOf(mod, atoms, op.args[1]),
                .b = try srcOf(mod, atoms, op.args[2]),
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (typeTestKindOf(name)) |kind| {
            // E1.3: the 13 unary is_* guards. genop operand order: Lbl, Src.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .type_test = .{
                .kind = kind,
                .src = try srcOf(mod, atoms, op.args[1]),
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "is_function2")) {
            // is_function2 Lbl Fun Arity — tests fun-of-arity-N. W-19: real
            // erlc emits Arity as a SIGNED integer-literal operand (`.i`), not
            // the compact unsigned `.u` count used by every other arity/count
            // op in this loader (confirmed by beam_disasm on the curated OTP
            // corpus: `is_function2` renders `{integer,N}`, everything else
            // renders a bare count). Route through `intArgOf`, which accepts
            // BOTH tags and cleanly rejects a negative `.i` as BadOperand
            // (never a panic) — the pre-fix `uOf`-only decode already
            // rejected cleanly (no panic; `uOf` is the W-16 checked helper)
            // but stopped every real curated module (lists/maps/error_logger
            // all use is_function2) at a `load-reject`, since a well-formed
            // `.i` arity is not a `.u` operand.
            try fixups.append(gpa, @intCast(prog.items.len));
            // E6.8 (DIVERGENCE 97 (3a)): the Arity operand is USUALLY a compile-
            // time integer literal (`.i`/`.u`, W-19), but erlc also emits it as a
            // REGISTER when the arity is a runtime value — `is_function(F, X)`
            // where X is a variable (eunit_data's `check_arity/3`: a
            // `{tr,{x,1},{t_integer,{0,2}}}` typed register). A register operand
            // (`.x`/`.y`/`.tr`) routes through `srcOf` into `arity_src`; the
            // integer-literal form keeps the static `.arity` path unchanged.
            const arity_is_reg = switch (op.args[2]) {
                .x, .y, .tr => true,
                else => false,
            };
            if (arity_is_reg) {
                try prog.append(gpa, .{ .is_function_arity = .{
                    .src = try srcOf(mod, atoms, op.args[1]),
                    .arity = 0,
                    .arity_src = try srcOf(mod, atoms, op.args[2]),
                    .else_to = @intCast(try labelIdOf(op.args[0])),
                } });
            } else {
                try prog.append(gpa, .{ .is_function_arity = .{
                    .src = try srcOf(mod, atoms, op.args[1]),
                    .arity = @intCast(try intArgOf(op.args[2])),
                    .else_to = @intCast(try labelIdOf(op.args[0])),
                } });
            }
        } else if (eql(name, "allocate")) {
            try prog.append(gpa, .{ .alloc_y = .{ .n = @intCast(try uOf(op.args[0])) } });
        } else if (eql(name, "allocate_heap")) {
            // allocate_heap StackNeed HeapNeed Live — genop operand order.
            // HeapNeed (args[1]) is a moving-GC hint; this arena grows on
            // demand, so — like `test_heap` above — it is NOT carried.
            try prog.append(gpa, .{ .alloc_heap = .{
                .stack = @intCast(try uOf(op.args[0])),
                .live = @intCast(try uOf(op.args[2])),
            } });
        } else if (eql(name, "trim")) {
            // trim N Remaining — genop operand order. Remaining (args[1]) is
            // advisory, like Live; not carried (see the E1.9 module doc).
            try prog.append(gpa, .{ .trim = .{ .n = @intCast(try uOf(op.args[0])) } });
        } else if (eql(name, "deallocate")) {
            try prog.append(gpa, .{ .dealloc_y = .{ .n = @intCast(try uOf(op.args[0])) } });
        } else if (eql(name, "init_yregs")) {
            const ys = try listOf(op.args[0]);
            for (ys) |yo| {
                try prog.append(gpa, .{ .move2 = .{ .src = .nil, .dst = try dstOf(yo) } });
            }
        } else if (eql(name, "move")) {
            try prog.append(gpa, .{ .move2 = .{
                .src = try srcOf(mod, atoms, op.args[0]),
                .dst = try dstOf(op.args[1]),
            } });
        } else if (eql(name, "swap")) {
            // gap-swap-x15 (DIVERGENCE 730): a TRUE swap instruction. The prior
            // lowering exchanged the two registers via `x15` as a scratch slot on
            // the ASSUMPTION that x15 is never live ("never used by compiled code
            // we accept"). That assumption is FALSE for a 16-arity function, whose
            // arguments occupy x0..x15 — so a `swap` in e.g. gen_statem's
            // `loop_timeouts/16` clobbered x15 (its `TimeoutOpts` []), passing an
            // atom where `erlang:start_timer/4` demands a list → badarg → EVERY
            // gen_statem state/event timer silently died. A single `.swap`
            // instruction exchanges the pair with a native temp, no register reuse.
            try prog.append(gpa, .{ .swap = .{
                .a = try dstOf(op.args[0]),
                .b = try dstOf(op.args[1]),
            } });
        } else if (eql(name, "get_list")) {
            try prog.append(gpa, .{ .get_list = .{
                .src = try srcOf(mod, atoms, op.args[0]),
                .hd = try dstOf(op.args[1]),
                .tl = try dstOf(op.args[2]),
            } });
        } else if (eql(name, "get_hd")) {
            try prog.append(gpa, .{ .get_hd = .{
                .src = try srcOf(mod, atoms, op.args[0]),
                .dst = try dstOf(op.args[1]),
            } });
        } else if (eql(name, "get_tl")) {
            try prog.append(gpa, .{ .get_tl = .{
                .src = try srcOf(mod, atoms, op.args[0]),
                .dst = try dstOf(op.args[1]),
            } });
        } else if (eql(name, "get_tuple_element")) {
            // get_tuple_element Source Element(0-based) Destination
            try prog.append(gpa, .{ .get_tuple_elem = .{
                .src = try srcOf(mod, atoms, op.args[0]),
                .index = @intCast(try uOf(op.args[1])),
                .dst = try dstOf(op.args[2]),
            } });
        } else if (eql(name, "set_tuple_element")) {
            // set_tuple_element NewElement Tuple Position(0-based)
            try prog.append(gpa, .{ .set_tuple_elem = .{
                .newval = try srcOf(mod, atoms, op.args[0]),
                .tuple = try srcOf(mod, atoms, op.args[1]),
                .index = @intCast(try uOf(op.args[2])),
            } });
        } else if (eql(name, "put_tuple2")) {
            // put_tuple2 Destination {list of source elements}. The `elems`
            // slice is gpa-owned and lives as long as `t.prog`; `freeProg`
            // (and translate's own errdefer) release it — see freeProg.
            const list = try listOf(op.args[1]);
            const elems = try gpa.alloc(ia.Src, list.len);
            errdefer gpa.free(elems);
            for (list, 0..) |lo, k| elems[k] = try srcOf(mod, atoms, lo);
            try prog.append(gpa, .{ .put_tuple2 = .{
                .dst = try dstOf(op.args[0]),
                .elems = elems,
            } });
        } else if (eql(name, "update_record")) {
            // update_record Hint Size Src Dst {Index0,Value0,Index1,Value1,...}.
            // Hint (args[0], an in-place/copy heap-reuse atom) and Size (args[1],
            // the tuple arity, == source arity) are optimisation metadata the
            // interpreter does not need — it always copies and reads the source
            // arity, so both are dropped. The updates list (args[4]) is flat
            // (Index, Value) pairs; each Index is the BEAM 1-based tuple Offset,
            // stored 0-based (Offset−1) to match `tupleElem`/`setTupleElem`. The
            // `updates` slice is gpa-owned (lives as long as t.prog; freed by
            // freeProg / this errdefer, same ownership as put_tuple2.elems).
            const list = try listOf(op.args[4]);
            if (list.len % 2 != 0) return error.BadOperand;
            const n = list.len / 2;
            const updates = try gpa.alloc(ia.RecordUpdate, n);
            errdefer gpa.free(updates);
            for (0..n) |k| {
                const offset = try uOf(list[2 * k]);
                if (offset == 0) return error.BadOperand; // offset 0 is the header
                updates[k] = .{
                    .index = @intCast(offset - 1),
                    .value = try srcOf(mod, atoms, list[2 * k + 1]),
                };
            }
            try prog.append(gpa, .{ .update_record = .{
                .src = try srcOf(mod, atoms, op.args[2]),
                .dst = try dstOf(op.args[3]),
                .updates = updates,
            } });
        } else if (eql(name, "is_any_native_record")) {
            // is_any_native_record Lbl Term.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .is_any_native_record = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "is_native_record")) {
            // is_native_record Lbl Rec Module Name (Module/Name are atoms).
            const mt = try atomTermOf(mod, atoms, op.args[2]);
            const nt = try atomTermOf(mod, atoms, op.args[3]);
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .is_native_record = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .module = mt,
                .name = nt,
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "get_record_elements")) {
            // get_record_elements Lbl Rec [FieldName0,Reg0,FieldName1,Reg1,...].
            // The `elems` slice is gpa-owned (freed by freeProg / this errdefer).
            const list = try listOf(op.args[2]);
            if (list.len % 2 != 0) return error.BadOperand;
            const n = list.len / 2;
            const elems = try gpa.alloc(ia.RecordElem, n);
            errdefer gpa.free(elems);
            for (0..n) |k| {
                elems[k] = .{
                    .key = try atomTermOf(mod, atoms, list[2 * k]),
                    .dst = try dstOf(list[2 * k + 1]),
                };
            }
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .get_record_elements = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .elems = elems,
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "put_record")) {
            // put_record Lbl Id Src Dst Live [FieldName0,Val0,...]. Lbl is
            // reserved (== 0, no fixup); Live (GC hint) is dropped. `updates`
            // is gpa-owned. Id resolves to `{Module,Name}` (create; src == nil).
            const list = try listOf(op.args[5]);
            if (list.len % 2 != 0) return error.BadOperand;
            const n = list.len / 2;
            const updates = try gpa.alloc(ia.RecordFieldSrc, n);
            errdefer gpa.free(updates);
            for (0..n) |k| {
                updates[k] = .{
                    .key = try atomTermOf(mod, atoms, list[2 * k]),
                    .value = try srcOf(mod, atoms, list[2 * k + 1]),
                };
            }
            try prog.append(gpa, .{ .put_record = .{
                .id = try srcOf(mod, atoms, op.args[1]),
                .src = try srcOf(mod, atoms, op.args[2]),
                .dst = try dstOf(op.args[3]),
                .updates = updates,
            } });
        } else if (eql(name, "is_record_accessible")) {
            // is_record_accessible Lbl Rec Scope (Scope atom external|auto_local).
            const scope_src = try srcOf(mod, atoms, op.args[2]);
            const scope: ia.NrScope = switch (scope_src) {
                .atom_ => |ai| blk: {
                    const nm = atoms.nameOf(ai);
                    break :blk if (eql(nm, "external"))
                        ia.NrScope.external
                    else if (eql(nm, "auto_local"))
                        ia.NrScope.auto_local
                    else
                        return error.BadOperand;
                },
                else => return error.BadOperand,
            };
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .is_record_accessible = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .scope = scope,
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "get_record_field")) {
            // get_record_field Lbl Rec Id Field Dst. Lbl == 0 ⇒ raise on failure
            // (else_to null, no fixup); Lbl != 0 ⇒ branch. Id is `{Module,Name}`
            // or the atom `_`; Field is an atom.
            const lbl = try labelIdOf(op.args[0]);
            const has_fail = lbl != 0;
            if (has_fail) try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .get_record_field = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .id = try srcOf(mod, atoms, op.args[2]),
                .field = try atomTermOf(mod, atoms, op.args[3]),
                .dst = try dstOf(op.args[4]),
                .else_to = if (has_fail) @as(?u32, @intCast(lbl)) else null,
            } });
        } else if (eql(name, "test_arity")) {
            // test_arity Lbl Source Arity — guarded tuple-arity test.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .test_arity = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .arity = @intCast(try uOf(op.args[2])),
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "is_tagged_tuple")) {
            // is_tagged_tuple Lbl Source Arity Atom — the tag is resolved to a
            // term here (atoms are ctx-free immediates, so no heap is needed).
            const tag_src = try srcOf(mod, atoms, op.args[3]);
            const tag: FinalTerms.Term = switch (tag_src) {
                .atom_ => |ai| FinalTerms.atomTerm(ai),
                .nil => FinalTerms.nil_term,
                else => return error.BadOperand,
            };
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .is_tagged_tuple = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .arity = @intCast(try uOf(op.args[2])),
                .tag = tag,
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "select_val")) {
            // select_val Src FailLbl {Val0,Lbl0,Val1,Lbl1,...}. The pairs slice
            // is gpa-owned (lives as long as t.prog); freeProg (and translate's
            // errdefer) release it — same ownership as put_tuple2.elems. Keys
            // are literal Vals resolved to ctx-free immediate Terms (small int /
            // atom / nil); the labels are fixed up (label id → pc) below.
            const list = try listOf(op.args[2]);
            if (list.len % 2 != 0) return error.BadOperand;
            const n = list.len / 2;
            // batch-4: keys with NO ctx-free immediate encoding (floats — now
            // decoded as `.flt` and synthesized into literals — or literal
            // heap terms) cannot ride the E1.6 immediate-key jump table. The
            // pre-fix arm rejected the WHOLE MODULE (BadOperand — fleet
            // finding: float_SUITE failed to LOAD because erlc emits
            // `select_val` over float constants). LOWER such a select into
            // the semantically-identical eq-test chain instead: per pair, a
            // `cmp_test ne_exact src key -> else_to LBL` (the test FAILS
            // exactly when src =:= key, and a failed cmp_test JUMPS — so
            // else_to is the arm's label), falling through to the next pair,
            // ending in an unconditional jump to the fail label.
            var all_immediate = true;
            for (0..n) |k| {
                if (selectKeyTerm(mod, atoms, list[2 * k])) |_| {} else |_| {
                    all_immediate = false;
                    break;
                }
            }
            if (all_immediate) {
                const pairs = try gpa.alloc(ia.SelectValPair, n);
                errdefer gpa.free(pairs);
                for (0..n) |k| {
                    const key = try selectKeyTerm(mod, atoms, list[2 * k]);
                    pairs[k] = .{ .key = key, .to = try labelIdOf(list[2 * k + 1]) };
                }
                try fixups.append(gpa, @intCast(prog.items.len));
                try prog.append(gpa, .{ .select_val = .{
                    .src = try srcOf(mod, atoms, op.args[0]),
                    .fail_to = @intCast(try labelIdOf(op.args[1])),
                    .pairs = pairs,
                } });
            } else {
                const src = try srcOf(mod, atoms, op.args[0]);
                for (0..n) |k| {
                    try fixups.append(gpa, @intCast(prog.items.len));
                    try prog.append(gpa, .{ .cmp_test = .{
                        .op = .ne_exact,
                        .a = src,
                        .b = try srcOf(mod, atoms, list[2 * k]),
                        .else_to = @intCast(try labelIdOf(list[2 * k + 1])),
                    } });
                }
                try fixups.append(gpa, @intCast(prog.items.len));
                try prog.append(gpa, .{ .jump = .{ .to = @intCast(try labelIdOf(op.args[1])) } });
            }
        } else if (eql(name, "select_tuple_arity")) {
            // select_tuple_arity Src FailLbl {Arity0,Lbl0,Arity1,Lbl1,...}. Same
            // gpa-owned pairs ownership; each key is a tuple arity (a `.u`).
            const list = try listOf(op.args[2]);
            if (list.len % 2 != 0) return error.BadOperand;
            const n = list.len / 2;
            const pairs = try gpa.alloc(ia.SelectArityPair, n);
            errdefer gpa.free(pairs);
            for (0..n) |k| {
                const arity: u16 = switch (list[2 * k]) {
                    .u => |v| @intCast(v),
                    .i => |v| @intCast(v),
                    else => return error.BadOperand,
                };
                pairs[k] = .{ .arity = arity, .to = try labelIdOf(list[2 * k + 1]) };
            }
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .select_tuple_arity = .{
                .src = try srcOf(mod, atoms, op.args[0]),
                .fail_to = @intCast(try labelIdOf(op.args[1])),
                .pairs = pairs,
            } });
        } else if (eql(name, "has_map_fields")) {
            // has_map_fields FailLbl Src {Key0,Key1,...} — guarded test: fall
            // through iff the map has EVERY key, else jump FailLbl. E5.2
            // (DIVERGENCE 47): keys are runtime `Src`s decoded via `srcOf` — a
            // LITERAL key arrives as `.imm`/`.atom_`/`.nil`/`.literal`, a
            // REGISTER-valued key (`init`, `prim_net`, …) as `.x`/`.y`; both are
            // resolved by `execInstr` at run time. The `keys` slice is gpa-owned
            // (lives as long as t.prog; freed by freeProg / this errdefer).
            const list = try listOf(op.args[2]);
            const keys = try gpa.alloc(ia.Src, list.len);
            errdefer gpa.free(keys);
            for (list, 0..) |lo, k| keys[k] = try srcOf(mod, atoms, lo);
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .has_map_fields = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .keys = keys,
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "get_map_elements")) {
            // get_map_elements FailLbl Src {Key0,Dst0,Key1,Dst1,...} —
            // ALL-OR-NOTHING extract: if any key is absent jump FailLbl (writing
            // no dst), else write each value to its Dst. Keys are literals; Dsts
            // are registers. The `pairs` slice is gpa-owned (same ownership as
            // put_tuple2.elems / select pairs). FailLbl is fixed up below.
            const list = try listOf(op.args[2]);
            if (list.len % 2 != 0) return error.BadOperand;
            const n = list.len / 2;
            // E5.2 (DIVERGENCE 47): keys are runtime `Src`s (`srcOf`) — a LITERAL
            // OR a register-valued key, both resolved at execution. `init`,
            // `prim_net`, `prim_socket`, `socket_registry` carry register keys.
            const pairs = try gpa.alloc(ia.MapElemPair, n);
            errdefer gpa.free(pairs);
            for (0..n) |k| {
                pairs[k] = .{
                    .key = try srcOf(mod, atoms, list[2 * k]),
                    .dst = try dstOf(list[2 * k + 1]),
                };
            }
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .get_map_elements = .{
                .src = try srcOf(mod, atoms, op.args[1]),
                .pairs = pairs,
                .else_to = @intCast(try labelIdOf(op.args[0])),
            } });
        } else if (eql(name, "put_map_assoc") or eql(name, "put_map_exact")) {
            // put_map_{assoc,exact} FailLbl Map Dst Live {Key0,Val0,...}. `assoc`
            // inserts-or-updates (maps:put); `exact` updates only existing keys
            // (an absent key crashes badkey — the FailLbl is E3's error_handler
            // route; E1 raises {badkey,Key} directly). Live (args[3]) is a
            // GC/register-liveness hint — advisory, not carried. Keys AND values
            // are general Srcs (registers or literals). The `kvs` slice is
            // gpa-owned; NO label fixup (the crash path is a raise, not a jump),
            // but peephole still deep-copies it for free-once ownership.
            const list = try listOf(op.args[4]);
            if (list.len % 2 != 0) return error.BadOperand;
            const n = list.len / 2;
            const kvs = try gpa.alloc(ia.MapKV, n);
            errdefer gpa.free(kvs);
            for (0..n) |k| {
                kvs[k] = .{
                    .k = try srcOf(mod, atoms, list[2 * k]),
                    .v = try srcOf(mod, atoms, list[2 * k + 1]),
                };
            }
            try prog.append(gpa, .{ .put_map = .{
                .exact = eql(name, "put_map_exact"),
                .src = try srcOf(mod, atoms, op.args[1]),
                .dst = try dstOf(op.args[2]),
                .kvs = kvs,
            } });
        } else if (eql(name, "put_list")) {
            // put_list H T Dst — cons H onto T, store in Dst. `ia.put_list`'s dst
            // is an x-slot (`u4`), but real compiled modules (erlang, prim_inet,
            // erl_prim_loader) also `put_list` straight into a Y (stack) slot.
            // The cons semantics + a write to any Dst BOTH already exist (`move2`
            // writes x OR y), so this is a DECODE-ONLY widening: an x dst emits
            // `put_list` directly; a y dst conses into the x15 scratch slot then
            // `move2`s it to the stack — the exact idiom the `swap` arm uses
            // (x15 is never live in code we accept; H/T are resolved before the
            // scratch write, so a self-referential H/T is safe). No new runtime
            // semantics, no `ia` change.
            const h = try srcOf(mod, atoms, op.args[0]);
            const t = try srcOf(mod, atoms, op.args[1]);
            switch (try dstOf(op.args[2])) {
                .x => |r| try prog.append(gpa, .{ .put_list = .{ .h = h, .t = t, .dst = r } }),
                .y => |yr| {
                    try prog.append(gpa, .{ .put_list = .{ .h = h, .t = t, .dst = 15 } });
                    try prog.append(gpa, .{ .move2 = .{ .src = .{ .x = 15 }, .dst = .{ .y = yr } } });
                },
            }
        } else if (eql(name, "call")) {
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .call = .{ .to = @intCast(try labelIdOf(op.args[1])) } });
        } else if (eql(name, "call_only")) {
            // A TAIL CALL (no return frame) → a `.jump` marked `tail` so R2's
            // reduction-cost model charges it the OTP per-call way (1 reduction),
            // distinct from an intra-function branch. Jump semantics unchanged.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .jump = .{ .to = @intCast(try labelIdOf(op.args[1])), .tail = true } });
        } else if (eql(name, "call_last")) {
            try prog.append(gpa, .{ .dealloc_y = .{ .n = @intCast(try uOf(op.args[2])) } });
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .jump = .{ .to = @intCast(try labelIdOf(op.args[1])), .tail = true } });
        } else if (eql(name, "jump")) {
            // jump Lbl — unconditional intra-module branch. Label id fixed up
            // to a pc below (like `call`). Reuses the pre-existing `.jump` variant.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .jump = .{ .to = @intCast(try labelIdOf(op.args[0])) } });
        } else if (eql(name, "call_fun")) {
            // call_fun Arity — the fun is in x[Arity], args in x[0..Arity-1].
            // Reuses the pre-existing `.call_fun` variant (badfun if not a fun,
            // else push return + jump to the fun's label). No label fixup: the
            // target is a runtime closure value, not a static code label.
            try prog.append(gpa, .{ .call_fun = .{ .f = .{ .x = @intCast(try uOf(op.args[0])) } } });
        } else if (eql(name, "call_fun2")) {
            // call_fun2 Tag Arity Func — the modern arity-tagged fun call. `Tag`
            // is a compiler type hint (ignored); `Func` is the closure operand.
            try prog.append(gpa, .{ .call_fun2 = .{
                .f = try srcOf(mod, atoms, op.args[2]),
                .arity = @intCast(try uOf(op.args[1])),
            } });
        } else if (eql(name, "apply")) {
            // apply Arity — read m:f/a from x[Arity]/x[Arity+1]; args already in
            // x0..x[Arity-1]. E3.12: resolve M:F/arity DYNAMICALLY (BIF/code/undef)
            // via the `apply_op` arm, replacing the pre-E3.12 unconditional trap.
            try prog.append(gpa, .{ .apply_op = .{ .arity = @intCast(try uOf(op.args[0])), .tail = false } });
        } else if (eql(name, "apply_last")) {
            // apply_last Arity Dealloc — tail-call apply: deallocate `Dealloc`
            // y-slots FIRST, then apply, then `ret` (the tail-call lowering, so a
            // trapping process-effect BIF target resumes onto the `ret`).
            try prog.append(gpa, .{ .dealloc_y = .{ .n = @intCast(try uOf(op.args[1])) } });
            try prog.append(gpa, .{ .apply_op = .{ .arity = @intCast(try uOf(op.args[0])), .tail = true } });
            try prog.append(gpa, .ret);
        } else if (eql(name, "make_fun3")) {
            // make_fun3 LambdaIdx Dst {env} — build a closure over a gpa-owned
            // `env` slice (lives as long as t.prog; freed by freeProg / this
            // errdefer, same ownership as put_tuple2.elems and the select
            // `pairs`).
            //
            // W-15 root cause + fix: real BEAM emits operand[0] as an UNSIGNED
            // `.u` INDEX into the module's lambda table (FunT chunk), NOT a raw
            // code label `.f`. The pre-fix arm read `op.args[0].f`, which
            // PANICKED ("access of union field 'f' while field 'u' is active")
            // on every real module carrying a closure (e.g. maps.beam). The
            // synthetic E1.7 laws never caught it because they build the
            // `make_fun3` CInstr directly with a `.to` label, bypassing the
            // loader. Resolve the index against `mod.lambdas` to the closure's
            // code label here (fixed up to a pc below); a malformed operand or
            // an out-of-range index is a clean `error.BadOperand`, never a panic.
            const lidx = switch (op.args[0]) {
                .u => |v| v,
                else => return error.BadOperand,
            };
            if (lidx >= mod.lambdas.len) return error.BadOperand;
            const label = mod.lambdas[lidx].label;
            if (label > mod.labels) return error.BadOperand;
            // W-16 (CORRECTED by fix-closure-aliasing, 2026-07-23): the FunT
            // lambda-table `arity` field is the implementation function's TOTAL
            // arity (visible + num_free — see the compiled asm: a `fun() -> N end`
            // closure's `'-…-fun-0-'` is a 1-arity function). erts's own transform
            // derives the closure's VISIBLE arity by SUBTRACTING num_free
            // (generators.tab `MakeFun`: `a[2].val = $Arity - $NumFree`; the
            // `i_make_fun3` DEBUG assert `fun_arity(funp) == mfa->arity - num_free`
            // pins the same relation). The pre-fix arm stored the raw TOTAL, which
            // shifted the fun's visible arity AND the call_fun env-restore base by
            // num_free — the root cause behind `fun_SUITE` `c_closure_distinct`
            // returning `{#Fun,#Fun}` instead of `{1,2}`. A malformed table
            // (arity < num_free, or not fitting u8) ⇒ BadOperand.
            const lam = mod.lambdas[lidx];
            if (lam.arity > std.math.maxInt(u8) or lam.arity < lam.num_free)
                return error.BadOperand;
            const fun_arity: u8 = @intCast(lam.arity - lam.num_free);
            const list = switch (op.args[2]) {
                .list => |l| l,
                else => return error.BadOperand,
            };
            const env = try gpa.alloc(ia.Src, list.len);
            errdefer gpa.free(env);
            for (list, 0..) |lo, k| env[k] = try srcOf(mod, atoms, lo);
            // DIVERGENCE 727 (funmeta): carry the closure's FunT generated-name +
            // defining-module atoms, resolved into the SHARED atom table, so a
            // compiled `fun_info_mfa/1` / `fun_info(F, module|name)` is byte-EQ. The
            // FunT `atom` field is the generated name's MODULE-LOCAL atom index; the
            // module name is module-local atom[1] (the BEAM AtU8 convention).
            const name_g: u32 = if (lam.atom > 0 and lam.atom < mod.atoms.len)
                @intCast(atoms.intern(mod.atomName(lam.atom)) catch return error.AtomTableFull)
            else 0;
            const mod_g: u32 = if (mod.atoms.len > 1)
                @intCast(atoms.intern(mod.atomName(1)) catch return error.AtomTableFull)
            else 0;
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .make_fun3 = .{
                .to = @intCast(label),
                .arity = fun_arity,
                .dst = try dstOf(op.args[1]),
                .env = env,
                .name = name_g,
                .module = mod_g,
                // DIVERGENCE 740: the FunT Index + OldUniq (plain u32s from the
                // lambda-table record) → the `#Fun<Module.Index.OldUniq>` print shape.
                .index = lam.index,
                .old_uniq = lam.old_uniq,
            } });
        } else if (eql(name, "call_ext") or eql(name, "call_ext_only") or eql(name, "call_ext_last")) {
            // E3.12: STATIC multi-module dispatch. `call_ext Arity Import`
            // (`call_ext_last` adds a trailing `Dealloc`). Resolve the import to
            // `{module, func, arity}`; if it names an implemented BIF, bake it as
            // an atomic `call_ext_bif` (executed over x0..x[arity-1] → x0); else a
            // `call_ext_code` resolved at run time through `m.exports` (miss →
            // `error_handler`/`undef`). The tail forms (`_only`/`_last`) lower to
            // the atomic op + a trailing `ret` (preceded by a `dealloc_y` for
            // `_last`) so a process-effect BIF that TRAPS resumes onto the `ret`.
            const arity: u8 = @intCast(try uOf(op.args[0]));
            const bidx = switch (op.args[1]) {
                .u => |v| v,
                else => return error.BadOperand,
            };
            if (bidx >= mod.imports.len) return error.BadOperand;
            const imp = mod.imports[bidx];
            const modname = mod.atomName(imp[0]);
            const fname = mod.atomName(imp[1]);
            const is_last = eql(name, "call_ext_last");
            const is_only = eql(name, "call_ext_only");
            const tail = is_last or is_only;
            if (is_last) {
                try prog.append(gpa, .{ .dealloc_y = .{ .n = @intCast(try uOf(op.args[2])) } });
            }
            // erlang:apply/3 is a dynamic dispatcher (M:F/A live in registers),
            // NOT a plain BIF returning a value — lower it to the `apply3` arm.
            if (eql(modname, "erlang") and eql(fname, "apply") and arity == 3) {
                try prog.append(gpa, .{ .apply3 = .{ .tail = tail } });
            } else if (eql(modname, "erlang") and eql(fname, "apply") and arity == 2) {
                // gap-apply-fun (DIVERGENCE 733): erlang:apply/2 (Fun + a runtime Args
                // list) — a dynamic FUN dispatcher, NOT a BIF; lower to `apply_fun`.
                try prog.append(gpa, .{ .apply_fun = .{ .tail = tail } });
            } else if (bif_dispatch.resolve(modname, fname, arity)) |func| {
                try prog.append(gpa, .{ .call_ext_bif = .{ .func = func, .arity = arity, .size_class = bifSizeClassOf(modname, fname, arity) } });
            } else if (bif_dispatch.resolveLibrary(modname, fname, arity)) |func| {
                // E5.8 (Task 8): an erlang.erl library wrapper we expand inline
                // (spawn_monitor/1,3) — ledger-invisible, the apply/3 precedent.
                try prog.append(gpa, .{ .call_ext_bif = .{ .func = func, .arity = arity, .size_class = bifSizeClassOf(modname, fname, arity) } });
            } else {
                const m_idx = atoms.intern(modname) catch return error.AtomTableFull;
                const f_idx = atoms.intern(fname) catch return error.AtomTableFull;
                try prog.append(gpa, .{ .call_ext_code = .{
                    .module = m_idx,
                    .func = f_idx,
                    .arity = arity,
                    .push_ret = !tail,
                } });
            }
            if (tail) try prog.append(gpa, .ret);
        } else if (eql(name, "return")) {
            try prog.append(gpa, .ret);
        } else if (eql(name, "badmatch")) {
            // batch-4 (CORRECTS the coarse `.func_info` decode): `badmatch Src`
            // raises error:{badmatch, Value} — the failed body-match SUBJECT is
            // part of the reason (erts: BADMATCH + x0). The old decode made
            // EVERY body-match failure a function_clause (fleet finding:
            // `<<_:N,T/binary>> = <<137>>` raised function_clause instead of
            // {badmatch,<<137>>}).
            try prog.append(gpa, .{ .raise_reason = .{ .tag = .badmatch, .src = try srcOf(mod, atoms, op.args[0]) } });
        } else if (eql(name, "case_end")) {
            // `case_end Src` ⇒ error:{case_clause, Value}.
            try prog.append(gpa, .{ .raise_reason = .{ .tag = .case_clause, .src = try srcOf(mod, atoms, op.args[0]) } });
        } else if (eql(name, "if_end")) {
            // `if_end` ⇒ error:if_clause (bare atom, no value operand).
            try prog.append(gpa, .{ .raise_reason = .{ .tag = .if_clause, .src = null } });
        } else if (eql(name, "catch")) {
            // catch Dst Lbl — push a catch landing pad. Lbl is a code label
            // (fixed up below); Dst is the frame's y-slot marker.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .catch_ = .{
                .to = @intCast(try labelIdOf(op.args[1])),
                .dst = try dstOf(op.args[0]),
            } });
        } else if (eql(name, "catch_end")) {
            try prog.append(gpa, .{ .catch_end = .{ .dst = try dstOf(op.args[0]) } });
        } else if (eql(name, "try")) {
            // try Dst Lbl — push a try landing pad (class/reason/stacktrace land
            // at Lbl on an exception). Same operand shape as `catch`.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .try_ = .{
                .to = @intCast(try labelIdOf(op.args[1])),
                .dst = try dstOf(op.args[0]),
            } });
        } else if (eql(name, "try_end")) {
            try prog.append(gpa, .{ .try_end = .{ .dst = try dstOf(op.args[0]) } });
        } else if (eql(name, "try_case")) {
            try prog.append(gpa, .{ .try_case = .{ .dst = try dstOf(op.args[0]) } });
        } else if (eql(name, "try_case_end")) {
            try prog.append(gpa, .{ .try_case_end = .{ .src = try srcOf(mod, atoms, op.args[0]) } });
        } else if (eql(name, "raise")) {
            // raise Trace Value — re-raise (unwind to the nearest frame).
            try prog.append(gpa, .{ .raise = .{
                .trace = try srcOf(mod, atoms, op.args[0]),
                .value = try srcOf(mod, atoms, op.args[1]),
            } });
        } else if (eql(name, "raw_raise")) {
            try prog.append(gpa, .raw_raise);
        } else if (eql(name, "build_stacktrace")) {
            try prog.append(gpa, .build_stacktrace);
        } else if (eql(name, "badrecord")) {
            try prog.append(gpa, .{ .badrecord = .{ .src = try srcOf(mod, atoms, op.args[0]) } });
        } else if (eql(name, "bif0") or eql(name, "bif1") or eql(name, "bif2") or
            eql(name, "bif3") or eql(name, "gc_bif1") or eql(name, "gc_bif2") or
            eql(name, "gc_bif3"))
        {
            // E1.13/E2.2: the BIF-dispatch opcode MECHANICS. Every `bif`/`gc_bif`
            // form maps to ONE `ia.bif_call` — including `gc_bif2`, which E2.2
            // UNIFIED onto this trap-at-runtime path (it previously load-rejected
            // an unsupported BIF; now an unsupported `M:F/A` becomes a runtime
            // `undef` trap, exactly like the others). Only the operand layout
            // differs:
            //   bif0     Bif Reg                    (body: no fail label)
            //   bif1     Lbl Bif Arg Reg
            //   bif2     Lbl Bif A1 A2 Reg
            //   bif3     Lbl Bif A1 A2 A3 Reg
            //   gc_bif1  Lbl Live Bif Src Reg
            //   gc_bif2  Lbl Live Bif A1 A2 Reg
            //   gc_bif3  Lbl Live Bif A1 A2 A3 Reg
            // A GUARD form (non-zero Lbl) carries an else_to that needs a label→pc
            // fixup; register it (index BEFORE append) exactly like the test ops.
            const ci: ia.CInstr = if (eql(name, "bif0"))
                try bifCallOf(mod, atoms, op.args[0], op.args[1..1], op.args[1], null, null)
            else if (eql(name, "bif1"))
                try bifCallOf(mod, atoms, op.args[1], op.args[2..3], op.args[3], op.args[0], null)
            else if (eql(name, "bif2"))
                try bifCallOf(mod, atoms, op.args[1], op.args[2..4], op.args[4], op.args[0], null)
            else if (eql(name, "bif3"))
                try bifCallOf(mod, atoms, op.args[1], op.args[2..5], op.args[5], op.args[0], null)
            else if (eql(name, "gc_bif1"))
                try bifCallOf(mod, atoms, op.args[2], op.args[3..4], op.args[4], op.args[0], op.args[1])
            else if (eql(name, "gc_bif2"))
                try bifCallOf(mod, atoms, op.args[2], op.args[3..5], op.args[5], op.args[0], op.args[1])
            else // gc_bif3
                try bifCallOf(mod, atoms, op.args[2], op.args[3..6], op.args[6], op.args[0], op.args[1]);
            if (ci.bif_call.else_to != null) try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, ci);
        } else if (eql(name, "send")) {
            // send/0: x1 to the pid in x0, the message being the result (x0).
            // Reuses the M7 `.send_to` trap; operands are implicit registers.
            try prog.append(gpa, .send);
        } else if (eql(name, "remove_message")) {
            try prog.append(gpa, .remove_message);
        } else if (eql(name, "timeout")) {
            try prog.append(gpa, .timeout);
        } else if (eql(name, "loop_rec")) {
            // loop_rec Label Source — peek the mailbox save-pointer into the
            // Source register; on an empty/exhausted queue jump to Label (wait).
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .loop_rec = .{
                .else_to = @intCast(try labelIdOf(op.args[0])),
                .dst = try xOf(op.args[1]),
            } });
        } else if (eql(name, "loop_rec_end")) {
            // loop_rec_end Label — advance the save-pointer, retry loop_rec at Lbl.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .loop_rec_end = .{ .to = @intCast(try labelIdOf(op.args[0])) } });
        } else if (eql(name, "wait")) {
            // wait Label — suspend; resume at Lbl (E1: terminal `.suspended`).
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .wait = .{ .to = @intCast(try labelIdOf(op.args[0])) } });
        } else if (eql(name, "wait_timeout")) {
            // wait_timeout Label Time — wait up to Time ms; on timeout fall
            // through to the after-clause (Label is the resume point). Time is a
            // runtime Src (0 fires now; `infinity` suspends).
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .wait_timeout = .{
                .to = @intCast(try labelIdOf(op.args[0])),
                .src = try srcOf(mod, atoms, op.args[1]),
            } });
        } else if (eql(name, "recv_marker_bind")) {
            // Receive-queue optimization markers: SEMANTICALLY TRANSPARENT no-ops
            // (transparency law). Operands (marker/reference registers) are not
            // read — a real marker table is an E3 perf concern.
            try prog.append(gpa, .recv_marker_bind);
        } else if (eql(name, "recv_marker_clear")) {
            try prog.append(gpa, .recv_marker_clear);
        } else if (eql(name, "recv_marker_reserve")) {
            try prog.append(gpa, .recv_marker_reserve);
        } else if (eql(name, "recv_marker_use")) {
            try prog.append(gpa, .recv_marker_use);
        } else if (eql(name, "executable_line") or eql(name, "debug_line")) {
            // coverage/debug pseudo-ops: no runtime content
        } else if (eql(name, "on_load")) {
            // E1.15: real BEAM RUNS the module's on-load function at load time;
            // E1 does not (that is Epoch E4, "boot the world" — see
            // DIVERGENCE_LOG.md), so a transparent runtime no-op is the
            // E1-minimal honest translation. Decodes+executes as .nop — EQ on
            // the totality ledger; the on-load-CALLBACK behavior is deferred.
            try prog.append(gpa, .{ .nop = .{ .note = .on_load } });
        } else if (eql(name, "nif_start")) {
            // E1.15: NIF stub entry — a genuine no-op landing pad.
            try prog.append(gpa, .{ .nop = .{ .note = .nif_start } });
        } else if (eql(name, "bs_start_match3")) {
            // bs_start_match3 Fail Bin Live Dst — the genop.tab signature
            // (`bs_start_match3/4`, @spec `Fail Bin Live Dst`): Bin is arg[1],
            // Live is arg[2]. This DIFFERS from bs_start_match4 below, whose
            // @spec is `Fail Live Src Dst` (Live arg[1], Src arg[2]).
            //
            // vm-binmatch-gc FIX (DIVERGENCE 57/68): the E3.3 code read Src
            // from arg[2] for BOTH ops, assuming a shared `Fail Live Bin Dst`
            // shape. For bs_start_match4 that is correct; for bs_start_match3
            // it read Live (a `.u` small int) as the Src, so bs_start_match
            // built a MatchCtx over a bogus `int(Live)` instead of the real
            // binary — the match then jumped its Fail label (badmatch). This
            // never surfaced under E3.3/E3.4 because the OTP compiler emits
            // bs_start_match3 (with a real Fail label) ONLY when the source's
            // binary-ness is statically UNKNOWN — e.g. a receive-bound
            // variable; every in-function `<<..>> = <<..>>` uses the
            // no_fail bs_start_match4 path, which was correct. The E3.3
            // "confirmed against a fixture" note was true only of that
            // match4-emitting fixture. Confirmed here against an erlc
            // `spawn`+`receive`+`<<X:8>>=B` beam loaded through THIS loader:
            // raw args `[f(7), x(0)=Bin, u(1)=Live, x(1)=Dst]`.
            const else_to = try bsStartFailOf(mod, atoms, op.args[0]);
            const ci: ia.CInstr = .{ .bs_start_match = .{
                .src = try srcOf(mod, atoms, op.args[1]), // Bin (NOT arg[2] — that is Live)
                .ctx = try dstOf(op.args[3]),
                .else_to = else_to,
            } };
            if (else_to != null) try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, ci);
        } else if (eql(name, "bs_start_match4")) {
            // bs_start_match4 Fail Live Src Dst — genop.tab @spec. Src is
            // arg[2] (Live is arg[1]) — the ORDER DIFFERS from bs_start_match3
            // above (do not "unify" these two arms). Fail may additionally be
            // the atom `no_fail`/`resume` (bsStartFailOf).
            const else_to = try bsStartFailOf(mod, atoms, op.args[0]);
            const ci: ia.CInstr = .{ .bs_start_match = .{
                .src = try srcOf(mod, atoms, op.args[2]),
                .ctx = try dstOf(op.args[3]),
                .else_to = else_to,
            } };
            if (else_to != null) try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, ci);
        } else if (eql(name, "bs_get_integer2")) {
            // bs_get_integer2 Fail Ms Live Sz Unit Flags Dst — genop order
            // (confirmed against the pin's classic loader `ops.tab`).
            const flags = try bsFlagsOf(op.args[5]);
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_get_integer = .{
                .ctx = try dstOf(op.args[1]),
                .size = try srcOf(mod, atoms, op.args[3]),
                .unit = @intCast(try uOf(op.args[4])),
                .signed = flags.signed,
                .endian = flags.endian,
                .dst = try dstOf(op.args[6]),
                .else_to = try labelIdOf(op.args[0]),
            } });
        } else if (eql(name, "bs_get_float2")) {
            // bs_get_float2 Fail Ms Live Sz Unit Flags Dst — same order.
            const flags = try bsFlagsOf(op.args[5]);
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_get_float = .{
                .ctx = try dstOf(op.args[1]),
                .size = try srcOf(mod, atoms, op.args[3]),
                .unit = @intCast(try uOf(op.args[4])),
                .endian = flags.endian,
                .dst = try dstOf(op.args[6]),
                .else_to = try labelIdOf(op.args[0]),
            } });
        } else if (eql(name, "bs_get_binary2")) {
            // bs_get_binary2 Fail Ms Live Sz Unit Flags Dst — same order.
            _ = try bsFlagsOf(op.args[5]); // decoded for validation; binary
            // extraction is endianness-agnostic (a raw sub-bitstring copy).
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_get_binary = .{
                .ctx = try dstOf(op.args[1]),
                .size = try srcOf(mod, atoms, op.args[3]),
                .unit = @intCast(try uOf(op.args[4])),
                .dst = try dstOf(op.args[6]),
                .else_to = try labelIdOf(op.args[0]),
            } });
        } else if (eql(name, "bs_skip_bits2")) {
            // bs_skip_bits2 Fail Ms Sz Unit Flags — genop order.
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_skip_bits = .{
                .ctx = try dstOf(op.args[1]),
                .size = try srcOf(mod, atoms, op.args[2]),
                .unit = @intCast(try uOf(op.args[3])),
                .else_to = try labelIdOf(op.args[0]),
            } });
        } else if (eql(name, "bs_test_tail2")) {
            // bs_test_tail2 Fail Ms Bits — Bits is a COMPILE-TIME constant
            // (`.u`), never a register (confirmed against the pin's ops.tab:
            // `bs_test_tail2 Fail=f Ms=xy Bits=u`).
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_test_tail = .{
                .ctx = try srcOf(mod, atoms, op.args[1]),
                .bits = @intCast(try uOf(op.args[2])),
                .else_to = try labelIdOf(op.args[0]),
            } });
        } else if (eql(name, "bs_match_string")) {
            // bs_match_string Fail Ms Bits Off — Off is a BYTE offset into
            // the module's `StrT` chunk (confirmed against `beam_disasm.erl`
            // `resolve_inst({bs_match_string,...})`: both Bits and Off decode
            // as plain `.u` operands on disk, never the symbolic
            // `{string,Bin}` form). The pattern bytes are copied into a
            // gpa-owned slice at translate time (freed by `freeProg`).
            const bit_len: u32 = @intCast(try uOf(op.args[2]));
            const off: usize = @intCast(try uOf(op.args[3]));
            const nbytes = (bit_len + 7) / 8;
            if (off + nbytes > mod.strtab.len) return error.BadOperand;
            const bytes = try gpa.dupe(u8, mod.strtab[off .. off + nbytes]);
            errdefer gpa.free(bytes);
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_match_string = .{
                .ctx = try dstOf(op.args[1]),
                .bit_len = bit_len,
                .bytes = bytes,
                .else_to = try labelIdOf(op.args[0]),
            } });
        } else if (eql(name, "bs_get_tail")) {
            // bs_get_tail Ctx Dst Live — genop order (Live is advisory).
            try prog.append(gpa, .{ .bs_get_tail_ctx = .{
                .ctx = try srcOf(mod, atoms, op.args[0]),
                .dst = try dstOf(op.args[1]),
            } });
        } else if (eql(name, "bs_get_position")) {
            // bs_get_position Ctx Dst Live — genop order (Live advisory).
            try prog.append(gpa, .{ .bs_get_position = .{
                .ctx = try srcOf(mod, atoms, op.args[0]),
                .dst = try dstOf(op.args[1]),
            } });
        } else if (eql(name, "bs_set_position")) {
            // bs_set_position Ctx Pos — genop order.
            try prog.append(gpa, .{ .bs_set_position = .{
                .ctx = try dstOf(op.args[0]),
                .pos = try srcOf(mod, atoms, op.args[1]),
            } });
        } else if (eql(name, "bs_match")) {
            // bs_match Fail Ctx {commands,Commands} — genop order.
            const cmds = try bsCommandsOf(gpa, mod, atoms, try listOf(op.args[2]));
            errdefer gpa.free(cmds);
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_match = .{
                .ctx = try dstOf(op.args[1]),
                .fail_to = try labelIdOf(op.args[0]),
                .cmds = cmds,
            } });
        } else if (eql(name, "bs_init_writable")) {
            // bs_init_writable/0 — genuinely ZERO on-disk operands (confirmed
            // against the pin's `bs_instrs.tab`: `x(0) = erts_bs_init_writable(
            // c_p, x(0))`, always x0-in/x0-out; the compiler wraps a
            // `copy({x,0},Dst)` AFTER it when the result is needed elsewhere —
            // that `copy` decodes as an ordinary `move`, nothing special here).
            // This VM's construction model has no distinct "writable" capacity
            // hint to honor (see `BsSeg`'s doc comment), so x0's PRIOR value
            // (the real VM's size hint) is simply discarded.
            try prog.append(gpa, .{ .bs_init_writable = .{ .dst = .{ .x = 0 } } });
        } else if (eql(name, "bs_create_bin")) {
            // bs_create_bin Fail Alloc Live Unit Dst OpList — genop order
            // (CONFIRMED against a freshly `erlc`-compiled fixture, loaded
            // through THIS loader — see the E3.4 report). Alloc/Live/Unit are
            // advisory allocation hints, dropped like `alloc_heap`'s Heap
            // operand (E1.9 precedent). Fail's OPTIONAL-label convention
            // mirrors `bifCallOf`/`bsStartFailOf` ({f,0} ⇒ body context).
            const segs = try bsCreateSegsOf(gpa, mod, atoms, try listOf(op.args[5]));
            errdefer freeBsSegs(gpa, segs);
            const else_to: ?u32 = switch (op.args[0]) {
                .f => |l| if (l == 0) null else @as(u16, @intCast(l)),
                else => return error.BadOperand,
            };
            if (else_to != null) try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_create_bin = .{
                .dst = try dstOf(op.args[4]),
                .else_to = else_to,
                .segs = segs,
            } });
        } else if (eql(name, "bs_get_utf8") or eql(name, "bs_get_utf16") or eql(name, "bs_get_utf32")) {
            // bs_get_utf{8,16,32}/5 Fail Ctx Live Flags Dst — CONFIRMED
            // against a freshly `erlc`-compiled fixture (see the E3.4
            // report): Flags decodes as the CLASSIC `.u` BSF_* bitmask
            // (`bsFlagsOf`, the `bs_get_integer2` precedent) — NOT
            // `bs_create_bin`'s newer literal-list Flags shape, despite both
            // being on-disk atoms named similarly. `signed` is decoded (for
            // validation) but unused — UTF codepoints are never signed.
            const kind: ia.UtfKind = if (eql(name, "bs_get_utf8")) .utf8 else if (eql(name, "bs_get_utf16")) .utf16 else .utf32;
            const flags = try bsFlagsOf(op.args[3]);
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_get_utf = .{
                .ctx = try dstOf(op.args[1]),
                .kind = kind,
                .endian = flags.endian,
                .dst = try dstOf(op.args[4]),
                .else_to = try labelIdOf(op.args[0]),
            } });
        } else if (eql(name, "bs_skip_utf8") or eql(name, "bs_skip_utf16") or eql(name, "bs_skip_utf32")) {
            // bs_skip_utf{8,16,32}/4 Fail Ctx Live Flags — same Flags shape.
            const kind: ia.UtfKind = if (eql(name, "bs_skip_utf8")) .utf8 else if (eql(name, "bs_skip_utf16")) .utf16 else .utf32;
            const flags = try bsFlagsOf(op.args[3]);
            try fixups.append(gpa, @intCast(prog.items.len));
            try prog.append(gpa, .{ .bs_skip_utf = .{
                .ctx = try dstOf(op.args[1]),
                .kind = kind,
                .endian = flags.endian,
                .else_to = try labelIdOf(op.args[0]),
            } });
        } else {
            // Unreachable in practice: the capSupported guard above already
            // rejected any op absent from the table, so reaching here means a
            // supported_ops entry has no dispatch arm — a table/chain drift bug.
            if (unsupported_out) |u| u.* = .{ .name = name, .arity = @intCast(op.args.len) };
            std.debug.print("beam_loader: supported_ops entry `{s}` ({d}) has no translate arm\n", .{ name, op.opcode });
            return error.UnsupportedOp;
        }
    }

    // patch label ids → pcs
    for (fixups.items) |idx| {
        switch (prog.items[idx]) {
            .is_cons => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .test_eq => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .is_lt => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .type_test => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .cmp_test => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .is_function_arity => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .test_arity => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .is_tagged_tuple => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            // E1.6: select carries MULTIPLE label refs — fail_to plus each
            // pair's `to`. Patch them all. `pairs` is stored `[]const`; the
            // backing memory is genuinely gpa-mutable, so @constCast to renumber.
            .select_val => |*v| {
                v.fail_to = @intCast(label_pc[v.fail_to]);
                for (@constCast(v.pairs)) |*p| p.to = @intCast(label_pc[p.to]);
            },
            .select_tuple_arity => |*v| {
                v.fail_to = @intCast(label_pc[v.fail_to]);
                for (@constCast(v.pairs)) |*p| p.to = @intCast(label_pc[p.to]);
            },
            .has_map_fields => |*v| v.else_to = @intCast(label_pc[v.else_to]), // E1.10: fail label
            .get_map_elements => |*v| v.else_to = @intCast(label_pc[v.else_to]), // E1.10: fail label
            // E3.14: native-record guard-shaped ops. `get_record_field` fixes
            // up else_to ONLY when non-null (Lbl != 0), mirroring `bif_call`.
            .is_any_native_record => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .is_native_record => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .get_record_elements => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .is_record_accessible => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .get_record_field => |*v| v.else_to = @intCast(label_pc[v.else_to.?]),
            .call => |*v| v.to = @intCast(label_pc[v.to]),
            .jump => |*v| v.to = @intCast(label_pc[v.to]),
            .make_fun3 => |*v| v.to = @intCast(label_pc[v.to]), // E1.7: closure code label
            .catch_ => |*v| v.to = @intCast(label_pc[v.to]), // E1.8: recovery label
            .try_ => |*v| v.to = @intCast(label_pc[v.to]), // E1.8: recovery label
            // E1.13: a GUARD bif carries an OPTIONAL fail label (else_to != null
            // only for a guard form; body forms are never registered as fixups).
            .bif_call => |*v| v.else_to = @intCast(label_pc[v.else_to.?]),
            .loop_rec => |*v| v.else_to = @intCast(label_pc[v.else_to]), // E1.11: wait label
            .loop_rec_end => |*v| v.to = @intCast(label_pc[v.to]), // E1.11: retry label
            .wait => |*v| v.to = @intCast(label_pc[v.to]), // E1.11: resume label
            .wait_timeout => |*v| v.to = @intCast(label_pc[v.to]), // E1.11: resume label
            // E3.3: bit-syntax matching. `bs_start_match` only registers a
            // fixup when `else_to` is non-null (mirrors `bif_call` above).
            .bs_start_match => |*v| v.else_to = @intCast(label_pc[v.else_to.?]),
            .bs_get_integer => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .bs_get_float => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .bs_get_binary => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .bs_skip_bits => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .bs_test_tail => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .bs_match_string => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .bs_match => |*v| v.fail_to = @intCast(label_pc[v.fail_to]),
            .bs_create_bin => |*v| v.else_to = @intCast(label_pc[v.else_to.?]), // E3.4: optional Fail (bif_call precedent)
            .bs_get_utf => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            .bs_skip_utf => |*v| v.else_to = @intCast(label_pc[v.else_to]),
            else => unreachable,
        }
    }

    // entry table from exports
    var entries: std.ArrayList(Entry) = .empty;
    errdefer entries.deinit(gpa);
    for (mod.exports) |e| {
        try entries.append(gpa, .{
            .name = mod.atomName(e[0]),
            .arity = e[1],
            .pc = label_pc[e[2]],
        });
    }

    // E3.11: expand the loc marks into a per-pc table (`locs[pc]` = the loc of
    // the latest mark with `mark.pc <= pc`). Marks are in increasing-pc order,
    // so one linear pass suffices. An instruction before ANY mark (only the
    // module preamble, never real function code) keeps the default zero loc →
    // `{'',_,0,[]}` head frame, never a panic.
    const locs = try gpa.alloc(ia.Loc, prog.items.len);
    errdefer gpa.free(locs);
    {
        var cur: ia.Loc = .{};
        var mi: usize = 0;
        for (0..prog.items.len) |pc| {
            while (mi < loc_marks.items.len and loc_marks.items[mi].pc <= pc) {
                cur = loc_marks.items[mi].loc;
                mi += 1;
            }
            locs[pc] = cur;
        }
    }

    return .{
        .prog = try prog.toOwnedSlice(gpa),
        .label_pc = label_pc,
        .entries = try entries.toOwnedSlice(gpa),
        .locs = locs,
    };
}

pub fn entryOf(t: *const Translated, name: []const u8, arity: u32) ?u32 {
    for (t.entries) |e| {
        if (e.arity == arity and std.mem.eql(u8, e.name, name)) return e.pc;
    }
    return null;
}

/// W-17: decode the module's LitT literal table INTO `ctx` (the executing
/// machine's heap), returning a gpa-owned `[]Term` the caller assigns to
/// `Machine.literals` and frees. Each literal is the module's external-format
/// bytes fed to etf.zig's decoder (version-ful `decode` for the pin's `131`-
/// prefixed literals, `decodeNoVersion` as a defensive fallback), so compound
/// literals (tuples/lists/maps) land as `ctx` heap refs that
/// `resolve(.literal i)` can read directly. The
/// table is decoded PER machine (not shared through the program) because a heap
/// ref is only meaningful in the ctx that built it — this is what lets one
/// translated program run on two independent machines (the differential engine).
/// A malformed literal surfaces as a clean decode error, never a panic.
pub fn materializeLiterals(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    mod: *Module,
) ![]FinalTerms.Term {
    const out = try gpa.alloc(FinalTerms.Term, mod.literals.len);
    errdefer gpa.free(out);
    for (mod.literals, 0..) |litbytes, k| {
        // Per the pin every LitT literal carries its `131` version byte (in BOTH
        // the compressed and uncompressed framings — beam_file.c decodes both via
        // `erts_decode_ext_size`, which requires VERSION_MAGIC). We still PEEK the
        // first byte: `131` ⇒ the version-checking `decode`; otherwise the
        // version-less entry `decodeNoVersion` — a defensive tolerance that is
        // unambiguous because `131` is not a valid first term tag, so a
        // version-less term never begins with it.
        out[k] = if (litbytes.len > 0 and litbytes[0] == etf.VERSION_MAGIC)
            try etf.decode(gpa, ctx, litbytes)
        else
            try etf.decodeNoVersion(gpa, ctx, litbytes);
    }
    return out;
}

/// E1.5/E1.6/E1.7: free a translated program's instruction slice INCLUDING any
/// operand sub-slices the CInstrs own (`put_tuple2.elems`, the select jump-table
/// `pairs` of `select_val`/`select_tuple_arity`, `make_fun3.env`, the map
/// `keys`/`pairs`/`kvs`, and `update_record.updates` (E1.14), all
/// allocated by `translate` with the same `gpa`). Call this in place of `gpa.free(t.prog)`
/// at every owner site; for programs without those ops it is exactly
/// `gpa.free`. Must run AFTER any shallow consumer of `t.prog` (e.g. a
/// `dispatch.predecode` dup, which aliases the sub-slices) is itself torn down.
/// e5-dispatch-codeidx: free ONLY the owned operand sub-slices of a program's
/// instructions, WITHOUT freeing the instruction array itself. Used by the
/// runtime code space (`Machine.dyn_code`), which is a capacity-backed
/// `ArrayList` whose ARRAY must be released via its own `deinit` (a slice-of-
/// items passed to `freeProg` would mismatch the capacity-sized allocation).
pub fn freeProgOperands(gpa: std.mem.Allocator, prog: []const ia.CInstr) void {
    for (prog) |ins| switch (ins) {
        .put_tuple2 => |p| gpa.free(p.elems),
        .select_val => |s| gpa.free(s.pairs),
        .select_tuple_arity => |s| gpa.free(s.pairs),
        .make_fun3 => |f| gpa.free(f.env),
        .has_map_fields => |h| gpa.free(h.keys),
        .get_map_elements => |g| gpa.free(g.pairs),
        .put_map => |p| gpa.free(p.kvs),
        .update_record => |u| gpa.free(u.updates),
        .get_record_elements => |u| gpa.free(u.elems),
        .put_record => |u| gpa.free(u.updates),
        .bs_match => |b| gpa.free(b.cmds),
        .bs_match_string => |b| gpa.free(b.bytes),
        .bs_create_bin => |b| freeBsSegs(gpa, b.segs),
        else => {},
    };
}

pub fn freeProg(gpa: std.mem.Allocator, prog: []ia.CInstr) void {
    for (prog) |ins| switch (ins) {
        .put_tuple2 => |p| gpa.free(p.elems),
        .select_val => |s| gpa.free(s.pairs),
        .select_tuple_arity => |s| gpa.free(s.pairs),
        .make_fun3 => |f| gpa.free(f.env), // E1.7: owned closure env
        .has_map_fields => |h| gpa.free(h.keys), // E1.10: owned map keys
        .get_map_elements => |g| gpa.free(g.pairs), // E1.10: owned map pairs
        .put_map => |p| gpa.free(p.kvs), // E1.10: owned map kvs
        .update_record => |u| gpa.free(u.updates), // E1.14: owned record updates
        .get_record_elements => |u| gpa.free(u.elems), // E3.14: owned elements
        .put_record => |u| gpa.free(u.updates), // E3.14: owned field updates
        .bs_match => |b| gpa.free(b.cmds), // E3.3: owned sub-command list
        .bs_match_string => |b| gpa.free(b.bytes), // E3.3: owned literal pattern
        .bs_create_bin => |b| freeBsSegs(gpa, b.segs), // E3.4: owned segment list
        else => {},
    };
    gpa.free(prog);
}

/// E3.4: free a `bs_create_bin.segs` slice — EACH `.string` segment owns its
/// own `bytes` (a StrT-chunk copy, `bsCreateSegsOf`), so both levels must be
/// freed (the `put_tuple2.elems`/`bs_match.cmds` precedent, one level
/// deeper). Shared by `translate`'s errdefer and `freeProg`.
fn freeBsSegs(gpa: std.mem.Allocator, segs: []const ia.BsSeg) void {
    for (segs) |s| switch (s) {
        .string => |st| gpa.free(st.bytes),
        else => {},
    };
    gpa.free(segs);
}

// ============================================================================
// E3.12b: static multi-module LINKING — the loading homomorphism
//   load(A ++ B) == link(load A, load B)
// Each module is `translate`d into its OWN pc space AND its OWN literal-index
// space (both 0-based). Linking CONCATENATES their programs into one flat pc
// space, relocating (1) every intra-module pc TARGET by the module's pc offset
// and (2) every `.literal` operand INDEX by the module's literal offset, and
// builds the cross-module EXPORT index (`module:func/arity → global pc`) that
// `call_ext_code` resolves through. This is `boot.link`'s pc-fixup essence
// generalized to N modules, PLUS the literal-pool relocation that made
// concatenating real erlc `.beam`s the E3.12 genuine blocker — see the module
// doc's E3.12b addendum. UCA guard: a MIS-relocated pc/literal would silently
// dispatch or read the WRONG body/constant; the link laws + corpus pin against it.
// ============================================================================

/// One module to link. `mod` is BORROWED (the caller keeps it alive for atom
/// names, literal bytes, and entry-name slices). `t` is CONSUMED — `link` moves
/// its instructions into the combined program and frees its `label_pc`/
/// `entries`/`locs`/prog-ARRAY on success; the caller must NOT free those.
pub const LinkUnit = struct {
    mod: *Module,
    t: Translated,
};

/// The linked multi-module program: one flat pc space, one export index, one
/// per-module literal layout. Owns everything below; free via `deinit`.
pub const Linked = struct {
    prog: []ia.CInstr, //         concatenated + relocated; freed via freeProg
    locs: []ia.Loc, //            concatenated (Loc VALUES — no reloc needed)
    exports: []ia.Export, //      module:func/arity → GLOBAL pc (all modules)
    entries: []Entry, //          all modules' exported entries, GLOBAL pc; the
    //                            entry function resolves via `entryOf` (first hit)
    lit_offset: []u32, //         module k's literals begin at this combined index
    module_atom: []ta.AtomIdx, // module k's own name atom (== atoms[1] interned)

    pub fn deinit(self: *Linked, gpa: std.mem.Allocator) void {
        freeProg(gpa, self.prog);
        gpa.free(self.locs);
        gpa.free(self.exports);
        gpa.free(self.entries);
        gpa.free(self.lit_offset);
        gpa.free(self.module_atom);
    }
};

/// e5-dispatch-codeidx: relocate ONE instruction into a target pc/literal frame
/// (both `link`'s per-module fixups in one call). Used by the RUNTIME code
/// server (`bifs/code.zig` `prepare_loading/2`) to splice a freshly-translated
/// module's instructions into the executing machine's dynamic code space at
/// `pc_off`/`lit_off` — the exact same reloc `link` applies statically, made
/// callable at run time. PUBLIC wrapper over the private `relocPc`/`relocLits`.
pub fn relocInstr(ins: *ia.CInstr, pc_off: u32, lit_off: u32) void {
    relocPc(ins, pc_off);
    relocLits(ia.CInstr, ins, lit_off);
}

/// E3.12b: relocate one instruction's INTRA-MODULE pc targets by `off`. Mirrors
/// `translate`'s label-fixup switch (the authoritative list of pc-bearing
/// fields): every branch/jump/call target and select-pair target is shifted so
/// module k's code, appended at pc offset `off`, still jumps within itself. NO
/// cross-module control flow is a raw pc (`call_ext_code` resolves via exports),
/// so no target here ever crosses a module boundary.
fn relocPc(ins: *ia.CInstr, off: u32) void {
    switch (ins.*) {
        .is_cons => |*v| v.else_to += off,
        .test_eq => |*v| v.else_to += off,
        .is_lt => |*v| v.else_to += off,
        .type_test => |*v| v.else_to += off,
        .cmp_test => |*v| v.else_to += off,
        .is_function_arity => |*v| v.else_to += off,
        .test_arity => |*v| v.else_to += off,
        .is_tagged_tuple => |*v| v.else_to += off,
        .select_val => |*v| {
            v.fail_to += off;
            for (@constCast(v.pairs)) |*p| p.to += off;
        },
        .select_tuple_arity => |*v| {
            v.fail_to += off;
            for (@constCast(v.pairs)) |*p| p.to += off;
        },
        .has_map_fields => |*v| v.else_to += off,
        .get_map_elements => |*v| v.else_to += off,
        .call => |*v| v.to += off,
        .jump => |*v| v.to += off,
        .make_fun3 => |*v| v.to += off,
        .catch_ => |*v| v.to += off,
        .try_ => |*v| v.to += off,
        .bif_call => |*v| {
            if (v.else_to) |e| v.else_to = e + off;
        },
        .loop_rec => |*v| v.else_to += off,
        .loop_rec_end => |*v| v.to += off,
        .wait => |*v| v.to += off,
        .wait_timeout => |*v| v.to += off,
        .bs_start_match => |*v| {
            if (v.else_to) |e| v.else_to = e + off;
        },
        .bs_get_integer => |*v| v.else_to += off,
        .bs_get_float => |*v| v.else_to += off,
        .bs_get_binary => |*v| v.else_to += off,
        .bs_skip_bits => |*v| v.else_to += off,
        .bs_test_tail => |*v| v.else_to += off,
        .bs_match_string => |*v| v.else_to += off,
        .bs_match => |*v| v.fail_to += off,
        .bs_create_bin => |*v| {
            if (v.else_to) |e| v.else_to = e + off;
        },
        .bs_get_utf => |*v| v.else_to += off,
        .bs_skip_utf => |*v| v.else_to += off,
        else => {},
    }
}

/// E3.12b: relocate every `.literal` operand INDEX inside a value by `off`,
/// COMPTIME-reflectively — the walker recurses through structs, unions (the
/// active field), arrays, and non-`u8` slices, bumping every `Src.literal` it
/// reaches. Driven from `ia.CInstr` it covers EVERY Src-bearing operand
/// (direct, `[3]Src`, owned `[]const Src`, and Src nested in `BsSeg`/`BsCmd`/
/// `MapKV`/… slices) with no per-variant enumeration — future Src operands are
/// handled for free. Non-Src leaves (`Dst`, `Term`=u64, atom indices, byte
/// blobs, function pointers, enums) are skipped by type.
fn relocLits(comptime T: type, ptr: *T, off: u32) void {
    if (T == ia.Src) {
        switch (ptr.*) {
            .literal => |i| ptr.* = .{ .literal = i + off },
            else => {},
        }
        return;
    }
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            inline for (info.fields) |f| relocLits(f.type, &@field(ptr.*, f.name), off);
        },
        .@"union" => switch (ptr.*) {
            inline else => |*payload| relocLits(@TypeOf(payload.*), payload, off),
        },
        .array => |info| {
            for (ptr) |*e| relocLits(info.child, e, off);
        },
        .pointer => |info| {
            // Only owned slices whose element could carry an Src (skip `[]u8`
            // byte blobs and non-slice pointers like the `BifFn` function ptr).
            if (info.size == .slice and info.child != u8) {
                for (@constCast(ptr.*)) |*e| relocLits(info.child, e, off);
            }
        },
        else => {},
    }
}

/// E3.12b: link N translated modules into one `Linked` program. `atoms` is the
/// SHARED runtime atom table every unit was `translate`d against (so module/
/// function atoms and `call_ext_code`'s baked atoms coincide). On success the
/// units' `Translated`s are consumed (freed); on error they are left intact for
/// the caller to free normally (the combined array is freed SHALLOW, never
/// touching the still-caller-owned operand sub-slices). A combined program that
/// would exceed the u16 pc-target width is rejected cleanly (never a panic).
pub fn link(gpa: std.mem.Allocator, atoms: *AtomTable, units: []LinkUnit) !Linked {
    var total_prog: usize = 0;
    for (units) |u| total_prog += u.t.prog.len;
    // Intra-module branch targets are u16, so the combined pc space must fit.
    if (total_prog > @as(usize, std.math.maxInt(u32)) + 1) return error.ProgramTooLarge;

    const prog = try gpa.alloc(ia.CInstr, total_prog);
    errdefer gpa.free(prog); // SHALLOW: sub-slices remain owned by the units
    const locs = try gpa.alloc(ia.Loc, total_prog);
    errdefer gpa.free(locs);
    const lit_offset = try gpa.alloc(u32, units.len);
    errdefer gpa.free(lit_offset);
    const module_atom = try gpa.alloc(ta.AtomIdx, units.len);
    errdefer gpa.free(module_atom);

    var exports: std.ArrayList(ia.Export) = .empty;
    errdefer exports.deinit(gpa);
    var entries: std.ArrayList(Entry) = .empty;
    errdefer entries.deinit(gpa);

    var pc_off: u32 = 0;
    var total_lit: u32 = 0;
    for (units, 0..) |u, k| {
        const modname = if (u.mod.atoms.len > 1) u.mod.atoms[1] else "";
        const mod_idx = atoms.intern(modname) catch return error.AtomTableFull;
        module_atom[k] = mod_idx;
        lit_offset[k] = total_lit;
        const off32: u32 = @intCast(pc_off);
        for (u.t.prog, 0..) |ins, i| {
            var copy = ins;
            relocPc(&copy, off32);
            relocLits(ia.CInstr, &copy, total_lit);
            prog[pc_off + i] = copy;
            locs[pc_off + i] = u.t.locs[i];
        }
        for (u.t.entries) |e| {
            const f_idx = atoms.intern(e.name) catch return error.AtomTableFull;
            // CAST-23 (DIVERGENCE 599): `Entry.name` MUST point at the STABLE global
            // atom-table storage (`atoms.nameOf(f_idx)` — dupe'd into a segmented,
            // never-relocated store that lives the whole run), NOT the per-module
            // `e.name` slice (which points into the Module/beam and was the source of
            // an intermittent `entryOf` FunctionNotExported quotient leak). Constructive
            // determinism: the lookup no longer depends on the module pointer's fate.
            const stable_name = atoms.nameOf(f_idx);
            try exports.append(gpa, .{ .module = mod_idx, .func = f_idx, .arity = e.arity, .pc = e.pc + pc_off });
            try entries.append(gpa, .{ .name = stable_name, .arity = e.arity, .pc = e.pc + pc_off });
        }
        pc_off += @intCast(u.t.prog.len);
        total_lit += @intCast(u.mod.literals.len);
    }

    // Materialize the owned export/entry slices BEFORE consuming the units, so no
    // fallible op remains after the free loop (a post-free failure would leak the
    // sub-slices now referenced only by `prog`).
    const exports_slice = try exports.toOwnedSlice(gpa);
    errdefer gpa.free(exports_slice);
    const entries_slice = try entries.toOwnedSlice(gpa);
    errdefer gpa.free(entries_slice);

    // Success: consume each unit's Translated. The instruction sub-slices moved
    // into `prog` (freed later via `freeProg`); free only the shallow arrays.
    for (units) |u| {
        gpa.free(u.t.prog); // shallow — sub-slices now owned by `prog`
        gpa.free(u.t.label_pc);
        gpa.free(u.t.entries);
        gpa.free(u.t.locs);
    }

    return .{
        .prog = prog,
        .locs = locs,
        .exports = exports_slice,
        .entries = entries_slice,
        .lit_offset = lit_offset,
        .module_atom = module_atom,
    };
}

/// E3.12b: the `on_load` function a module declares, if any.
pub const OnLoad = struct { f: ta.AtomIdx, arity: u32 };

/// E3.12b: find the module's `on_load` function from its `Attr` proplist. Decodes
/// the attributes' ETF bytes into `ctx` and walks the `[{Key,Value}]` proplist
/// for `{on_load,[{F,A}|_]}`, returning `{F-atom, A}` (the atom index is in
/// `ctx.atoms`, the shared runtime table). null when the module has no `Attr`
/// chunk, no `on_load`, or a shape we don't recognise — a load with no on_load
/// gate, never a panic (a malformed chunk decodes to null via the caught error).
pub fn onLoadFun(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, mod: *Module) !?OnLoad {
    if (mod.attr_bytes.len == 0) return null;
    const term = etf.decode(gpa, ctx, mod.attr_bytes) catch return null;
    const F = FinalTerms;
    var cur = term;
    while (F.kindOf(ctx, cur) == .cons) : (cur = F.listTail(ctx, cur)) {
        const pair = F.listHead(ctx, cur);
        if (F.kindOf(ctx, pair) != .tuple or F.tupleArity(ctx, pair) != 2) continue;
        const key = F.tupleElem(ctx, pair, 0);
        if (F.kindOf(ctx, key) != .atom) continue;
        if (!std.mem.eql(u8, ctx.atoms.nameOf(F.atomIdxOf(key)), "on_load")) continue;
        const val = F.tupleElem(ctx, pair, 1);
        if (F.kindOf(ctx, val) != .cons) return null;
        const fa = F.listHead(ctx, val);
        if (F.kindOf(ctx, fa) != .tuple or F.tupleArity(ctx, fa) != 2) return null;
        const fatom = F.tupleElem(ctx, fa, 0);
        const aterm = F.tupleElem(ctx, fa, 1);
        if (F.kindOf(ctx, fatom) != .atom or F.kindOf(ctx, aterm) != .number) return null;
        return .{ .f = F.atomIdxOf(fatom), .arity = @intCast(F.smallValOf(aterm)) };
    }
    return null;
}

/// E3.12b: resolve `module:func/arity` to its callable entry pc by scanning the
/// linked `locs` table (which records the m/f/a of every pc — the first pc of a
/// function is its `func_info`, whose loc names it). The callable entry is that
/// pc advanced past the leading `func_info`. Used for `on_load`, whose function
/// is usually NOT exported, so it is absent from the export index. null when the
/// function is not present.
pub fn resolveLocal(prog: []const ia.CInstr, locs: []const ia.Loc, module: ta.AtomIdx, func: ta.AtomIdx, arity: u32) ?u32 {
    for (locs, 0..) |loc, pc| {
        if (loc.m == module and loc.f == func and loc.a == arity) {
            var e: u32 = @intCast(pc);
            if (prog[pc] == .func_info) e += 1;
            return e;
        }
    }
    return null;
}

// ============================================================================
// Tests — laws + gate G2
// ============================================================================

const fixture = @embedFile("mylists.beam"); // vendored copy; source of truth in fixtures/

// ---------------------------------------------------------------------------
// E0.5 totality laws: the capability list is SINGLE-SOURCED from `supported_ops`
// (the table `translate` itself consults). These laws pin that single source so
// `dump-caps` cannot drift from what the loader actually accepts.
// ---------------------------------------------------------------------------

test "LAW dump-caps totality over the translate dispatch: output round-trips supported_ops exactly" {
    const cli = @import("cli.zig");
    const gpa = std.testing.allocator;

    // Render the caps and slice out just the `op ` lines (dumpCaps also emits
    // `bif ` lines from instr_algebra; those are covered by their own law).
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try cli.dumpCaps(gpa, &buf);

    // Parse OUR OWN output back into (name, arity) pairs, in first-seen order.
    var got: std.ArrayList(OpCap) = .empty;
    defer got.deinit(gpa);
    var lines = std.mem.tokenizeScalar(u8, buf.items, '\n');
    while (lines.next()) |line| {
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        const kind = f.next().?;
        if (!std.mem.eql(u8, kind, "op")) continue; // skip bif lines
        const name = f.next().?;
        const arity = try std.fmt.parseInt(u8, f.next().?, 10);
        try got.append(gpa, .{ .name = name, .arity = arity });
    }

    // Exactly the table, no more, no fewer, and in the SAME sorted order the
    // table declares (so the printed order is itself pinned).
    try std.testing.expectEqual(supported_ops.len, got.items.len);
    for (supported_ops, got.items) |want, have| {
        try std.testing.expect(std.mem.eql(u8, want.name, have.name));
        try std.testing.expectEqual(want.arity, have.arity);
    }
}

test "LAW supported_ops is sorted and duplicate-free (name asc, then arity asc)" {
    for (supported_ops[1..], 0..) |cur, i| {
        const prev = supported_ops[i];
        const c = std.mem.order(u8, prev.name, cur.name);
        // strictly increasing on (name, arity): never equal, never descending
        try std.testing.expect(c == .lt or (c == .eq and prev.arity < cur.arity));
    }
}

test "LAW negative: an opcode absent from supported_ops is rejected by translate with error.UnsupportedOp" {
    const gpa = std.testing.allocator;
    // init/1 (opcode 17, `-init/1` in genop.tab) is a REAL generic op present
    // in genop.tab and in op_table, but it is OBSOLETE (the `-` marker: the
    // OTP 30-rc compiler no longer emits it) and hence never in
    // `supported_ops` — a permanently-unsupported fixture (E3.4 repointed
    // this test from `bs_create_bin`, which THIS task newly implements — the
    // E3.3 precedent for repointing a now-implemented example). Translate
    // must reject it; we build a one-instruction synthetic Module and
    // confirm the guard fires before any operand handling.
    try std.testing.expect(!capSupported("init"));
    const absent_opcode: u16 = blk: {
        for (op_table, 0..) |maybe, oc| {
            if (maybe) |info| if (std.mem.eql(u8, info.name, "init")) break :blk @intCast(oc);
        }
        unreachable;
    };

    // Minimal well-formed Module carrying one unsupported op. The Module owns
    // its arena (mod.deinit frees everything); the guard rejects on op NAME, so
    // the empty args slice is never inspected.
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "m";
    const code_arr = try a.alloc(Op, 1);
    code_arr[0] = .{ .opcode = absent_opcode, .args = &.{} };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 0,
    };
    defer mod.deinit();

    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    try std.testing.expectError(error.UnsupportedOp, translate(gpa, &mod, &atbl, null));
}

test "LAW E1.2 diagnostic: translate fills unsupported_out with the offending op's name and arity" {
    const gpa = std.testing.allocator;
    // Same synthetic unsupported-op module as the negative law above (`init/1`
    // — obsolete, permanently unsupported), but this time capture the
    // diagnostic out-param `checkLoad`/`check-load` relies on to print
    // `load-reject <op>/<arity>` without re-deriving anything.
    const absent_opcode: u16 = blk: {
        for (op_table, 0..) |maybe, oc| {
            if (maybe) |info| if (std.mem.eql(u8, info.name, "init")) break :blk @intCast(oc);
        }
        unreachable;
    };

    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "m";
    const code_arr = try a.alloc(Op, 1);
    const synth_args = try a.alloc(Operand, 1); // init/1
    code_arr[0] = .{ .opcode = absent_opcode, .args = synth_args };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 0,
    };
    defer mod.deinit();

    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    var diag: UnsupportedOpInfo = undefined;
    try std.testing.expectError(error.UnsupportedOp, translate(gpa, &mod, &atbl, &diag));
    try std.testing.expect(std.mem.eql(u8, diag.name, "init"));
    try std.testing.expectEqual(@as(u32, 1), diag.arity);
}

test "LAW E1.12 fr operand round-trips through decode∘emit ({fr,N})" {
    const gpa = std.testing.allocator;
    // Emit {fr,5} then decode it back — the Z-subtag-2 encoding must round-trip.
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try emitOperand(&out, gpa, .{ .fr = 5 });
    // Z-tag byte carries subtag 2 in the high nibble.
    try std.testing.expectEqual(@as(u8, (2 << 4) | TAG_Z), out.items[0]);
    var r = Reader{ .buf = out.items };
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const o = try decodeOperand(&r, arena.allocator());
    try std.testing.expect(o == .fr and o.fr == 5);
}

test "LAW gap-bigint-operand: a >16-byte inline signed int operand decodes to a bignum (.ibigbytes), round-trips through emit∘decode, and honours erlc's leading-sign-byte encoding — was BadOperand (DIVERGENCE 593)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const A = arena.allocator();

    // Each mag_le is a valid LITTLE-endian magnitude (highest-index byte non-zero) that
    // encodes to > 16 bytes (so the decoder takes the bignum path): 2^128-1 (16×0xFF,
    // positive → 17-byte encoding w/ a leading 0x00), its negative, and a 17-byte
    // magnitude with the top bit set (18-byte encoding).
    const ff16 = [_]u8{0xFF} ** 16;
    const b17 = [_]u8{0} ** 16 ++ [_]u8{0x80}; // 2^135 (17-byte mag, top bit set)
    const cases = [_]struct { pos: bool, mag: []const u8 }{
        .{ .pos = true, .mag = &ff16 },
        .{ .pos = false, .mag = &ff16 },
        .{ .pos = true, .mag = &b17 },
        .{ .pos = false, .mag = &b17 },
    };
    for (cases) |c| {
        const op = Operand{ .ibigbytes = .{ .positive = c.pos, .mag_le = c.mag } };
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try emitOperand(&out, gpa, op);
        var r = Reader{ .buf = out.items };
        const back = try decodeOperand(&r, A); // MUST NOT BadOperand (the pre-fix bug)
        try std.testing.expect(back == .ibigbytes); // > i128 → the bignum variant
        try std.testing.expectEqual(c.pos, back.ibigbytes.positive); // sign preserved
        try std.testing.expectEqualSlices(u8, c.mag, back.ibigbytes.mag_le); // magnitude exact
    }

    // OVER-CAP: a >255-byte inline int is a CLEAN BadOperand (never silent truncation).
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.append(gpa, (7 << 5) | 0b11000 | TAG_I); // (first>>5)==7 size-extension header
    try emitValue(&out, gpa, TAG_U, 300 - 9); // size = 300 bytes
    try out.appendSlice(gpa, &([_]u8{0x7F} ** 300));
    var r2 = Reader{ .buf = out.items };
    try std.testing.expectError(error.BadOperand, decodeOperand(&r2, A));
}

test "LAW E1.12 translate decodes the FR opcode family (fmove both directions, fconv, arith, fnegate)" {
    const gpa = std.testing.allocator;

    // fmove Reg FR: reg-source loads the FR bank.
    const to_f = try translateSingle(gpa, "fmove", &.{ Operand{ .x = 3 }, Operand{ .fr = 1 } });
    try std.testing.expect(to_f == .fmove_to_f);
    try std.testing.expect(to_f.fmove_to_f.src == .x and to_f.fmove_to_f.src.x == 3);
    try std.testing.expectEqual(@as(u4, 1), to_f.fmove_to_f.fdst);

    // fmove FR Reg: fr-source boxes back into a register.
    const from_f = try translateSingle(gpa, "fmove", &.{ Operand{ .fr = 2 }, Operand{ .x = 4 } });
    try std.testing.expect(from_f == .fmove_from_f);
    try std.testing.expectEqual(@as(u4, 2), from_f.fmove_from_f.fsrc);
    try std.testing.expect(from_f.fmove_from_f.dst == .x and from_f.fmove_from_f.dst.x == 4);

    // fconv Src FR.
    const cv = try translateSingle(gpa, "fconv", &.{ Operand{ .x = 0 }, Operand{ .fr = 3 } });
    try std.testing.expect(cv == .fconv);
    try std.testing.expectEqual(@as(u4, 3), cv.fconv.fdst);

    // fadd Fail FA FB FDst — the Fail label (args[0]) is NOT carried (crash policy).
    const add = try translateSingle(gpa, "fadd", &.{ Operand{ .f = 1 }, Operand{ .fr = 0 }, Operand{ .fr = 1 }, Operand{ .fr = 2 } });
    try std.testing.expect(add == .fadd);
    try std.testing.expectEqual(@as(u4, 0), add.fadd.a);
    try std.testing.expectEqual(@as(u4, 1), add.fadd.b);
    try std.testing.expectEqual(@as(u4, 2), add.fadd.fdst);

    // fsub/fmul/fdiv share the shape; spot-check fsub keeps operand order.
    const sub = try translateSingle(gpa, "fsub", &.{ Operand{ .f = 1 }, Operand{ .fr = 5 }, Operand{ .fr = 6 }, Operand{ .fr = 7 } });
    try std.testing.expect(sub == .fsub);
    try std.testing.expectEqual(@as(u4, 5), sub.fsub.a);
    try std.testing.expectEqual(@as(u4, 6), sub.fsub.b);

    // fnegate Fail FA FDst.
    const neg = try translateSingle(gpa, "fnegate", &.{ Operand{ .f = 1 }, Operand{ .fr = 8 }, Operand{ .fr = 9 } });
    try std.testing.expect(neg == .fnegate);
    try std.testing.expectEqual(@as(u4, 8), neg.fnegate.a);
    try std.testing.expectEqual(@as(u4, 9), neg.fnegate.fdst);
}

// E1.13/E2.4: translate the BIF-dispatch opcode family. A synthetic module
// carries a two-entry import table — `erlang:'+'/2` (executable) and
// `erlang:bit_size/1` (unimplemented `.stub`) — plus a defining `label 1`.
// Asserts: a `bif2` over `+` resolves to the `+`/2 family fn with the right
// args/dst; a GUARD form (non-zero Fail) carries a patched `else_to`, a BODY form
// (Fail 0) carries `null`; a `gc_bif1` over `bit_size` decodes to `.unsupported`
// and records its Live hint. This pins the DECODE + DISPATCH mechanics — coverage
// (what runs) grows in later E2 tasks.
test "LAW E1.13 translate decodes the bif family (supported +, guard/body Fail, unsupported → undef ref)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 4);
    atoms_arr[0] = "";
    atoms_arr[1] = "erlang";
    atoms_arr[2] = "+";
    atoms_arr[3] = "trace_delivered";
    const imports = try a.alloc([3]u32, 2);
    imports[0] = .{ 1, 2, 2 }; // import 0: erlang:'+'/2            (executable)
    imports[1] = .{ 1, 3, 1 }; // import 1: erlang:trace_delivered/1 (unimplemented, `.justified`
    //   deferred-trace-delivery — the trace DELIVERY surface). E3.2 flipped `bit_size/1`,
    //   E3.18 flipped `iolist_size/1`, E6.5 flipped `system_info/1`, and E7.6 flipped
    //   `seq_trace_info/1` (this test's PRIOR unimplemented examples) to `.implemented`
    //   — swapped to `trace_delivered/1`, which stays out of scope (the tracer-delivery
    //   slice), so the (3) assertion below keeps exercising the `.unsupported` arm.

    // Four ops: GUARD bif2 (+), BODY bif2 (+), gc_bif1 (trace_delivered), label 1.
    const code_arr = try a.alloc(Op, 4);
    code_arr[0] = .{ .opcode = opcodeByName("bif2"), .args = &.{
        Operand{ .f = 1 }, Operand{ .u = 0 }, Operand{ .x = 1 }, Operand{ .x = 2 }, Operand{ .x = 3 },
    } };
    code_arr[1] = .{ .opcode = opcodeByName("bif2"), .args = &.{
        Operand{ .f = 0 }, Operand{ .u = 0 }, Operand{ .x = 1 }, Operand{ .x = 2 }, Operand{ .x = 3 },
    } };
    code_arr[2] = .{ .opcode = opcodeByName("gc_bif1"), .args = &.{
        Operand{ .f = 0 }, Operand{ .u = 5 }, Operand{ .u = 1 }, Operand{ .x = 0 }, Operand{ .x = 4 },
    } };
    code_arr[3] = .{ .opcode = opcodeByName("label"), .args = &.{Operand{ .u = 1 }} };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = imports,
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 1,
    };
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer freeProg(gpa, t.prog);
    defer gpa.free(t.label_pc);
    defer gpa.free(t.entries);
    defer gpa.free(t.locs);

    // (1) GUARD bif2 +: resolved to .add, args x1/x2, dst x3, else_to patched to
    //     label 1's pc (= 3, the last instruction index).
    try std.testing.expect(t.prog[0] == .bif_call);
    const g = t.prog[0].bif_call;
    // Resolved to the `+`/2 family fn (E2.4: a fn pointer, not the old `.add` enum).
    try std.testing.expect(g.bif == .func and g.bif.func == bif_dispatch.resolve("erlang", "+", 2).?);
    try std.testing.expectEqual(@as(u8, 2), g.argc);
    try std.testing.expect(g.args[0] == .x and g.args[0].x == 1);
    try std.testing.expect(g.args[1] == .x and g.args[1].x == 2);
    try std.testing.expect(g.dst == .x and g.dst.x == 3);
    try std.testing.expectEqual(@as(?u32, 3), g.else_to); // guard: patched fail label
    try std.testing.expectEqual(@as(?u8, null), g.gc_live); // plain bif: no Live

    // (2) BODY bif2 + (Fail 0): same resolution, but else_to null (crash policy).
    const b = t.prog[1].bif_call;
    try std.testing.expect(b.bif == .func and b.bif.func == bif_dispatch.resolve("erlang", "+", 2).?);
    try std.testing.expectEqual(@as(?u32, null), b.else_to);

    // (3) gc_bif1 trace_delivered: NOT implemented (`.justified`) → .unsupported
    //     (traps undef at run); Live=5 recorded (advisory), single arg, dst x4.
    const u = t.prog[2].bif_call;
    try std.testing.expect(u.bif == .unsupported);
    try std.testing.expectEqual(@as(u8, 1), u.argc);
    try std.testing.expect(u.dst == .x and u.dst.x == 4);
    try std.testing.expectEqual(@as(?u8, 5), u.gc_live);
    try std.testing.expectEqual(@as(?u32, null), u.else_to);
}

// E2.2: gc_bif2 over an UNSUPPORTED BIF must be LOAD-TOTAL — the module loads and
// the BIF traps `undef` only when EXECUTED, exactly like bif0/1/2/3 + gc_bif1/3.
// This retires the E1.13 asymmetry where gc_bif2 REJECTED the module at load. The
// synthetic module carries a single import — `erlang:'/'/2`, a real gc_bif2 arith
// BIF the VM does NOT implement (`.stub` in the generated bif_table — float
// division is a later slice; `*`/`div`/`rem` landed in E2.4 but `/` did not) —
// behind a gc_bif2 op. Asserts: (1) translate SUCCEEDS (no UnsupportedOp reject);
// (2) the op decodes to a `bif_call` with `.unsupported`; (3) executing it crashes `undef`.
test "LAW E2.2 gc_bif2 with an unsupported BIF loads then traps undef at runtime" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 3);
    atoms_arr[0] = "";
    atoms_arr[1] = "erlang";
    atoms_arr[2] = "load_nif";
    const imports = try a.alloc([3]u32, 1);
    // import 0: erlang:load_nif/2 — a real BIF still justified (`out-of-scope`: a
    // NIF loader this pure-Zig node does not run) and NOT in the
    // dispatch-needed-deferred carve-out, so it resolves null → traps undef.
    // NOTE (e21-t2b / gap-processes-0 / gap-fun-info): the prior examples
    // process_info/2 [490-amend], then fun_info/2 [DIVERGENCE 652] each became
    // carve-out members (resolve executable), so this negative test keeps moving
    // to a still-null-resolving justified row. (E8.2k earlier moved off setnode/2.)
    imports[0] = .{ 1, 2, 2 };

    // gc_bif2 Fail Live BifImport Src1 Src2 Dst — BODY context (Fail 0).
    const code_arr = try a.alloc(Op, 1);
    code_arr[0] = .{ .opcode = opcodeByName("gc_bif2"), .args = &.{
        Operand{ .f = 0 }, Operand{ .u = 4 }, Operand{ .u = 0 },
        Operand{ .x = 1 }, Operand{ .x = 2 }, Operand{ .x = 3 },
    } };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = imports,
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 0,
    };
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();

    // (1) translate SUCCEEDS — the module is load-total (was: error.UnsupportedOp).
    var unsupported: UnsupportedOpInfo = undefined;
    const t = try translate(gpa, &mod, &atbl, &unsupported);
    defer freeProg(gpa, t.prog);
    defer gpa.free(t.label_pc);
    defer gpa.free(t.entries);
    defer gpa.free(t.locs);

    // (2) it decoded to a bif_call with an `.unsupported` ref (not `.op`), argc 2,
    //     dst x3, Live=4 recorded, BODY context (else_to null).
    try std.testing.expect(t.prog[0] == .bif_call);
    const c = t.prog[0].bif_call;
    try std.testing.expect(c.bif == .unsupported);
    try std.testing.expectEqual(@as(u8, 2), c.argc);
    try std.testing.expect(c.dst == .x and c.dst.x == 3);
    try std.testing.expectEqual(@as(?u8, 4), c.gc_live);
    try std.testing.expectEqual(@as(?u32, null), c.else_to);

    // (3) executing it traps `undef` at RUNTIME (numeric operands notwithstanding
    //     — an unimplemented BIF is undefined, never a computed/guard result).
    var m = try ia.Machine.init(gpa, &atbl);
    defer m.deinit();
    m.regs[1] = FinalTerms.int(&m.ctx, 6);
    m.regs[2] = FinalTerms.int(&m.ctx, 7);
    try ia.execInstr(&m, t.prog[0]);
    try std.testing.expect(m.status == .crashed);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.atom(&m.ctx, m.undef)));
}

// ---------------------------------------------------------------------------
// W-15 regression: make_fun3's FIRST operand is an UNSIGNED `.u` index into the
// module lambda table (FunT chunk), NOT a raw code label `.f`. The pre-fix arm
// read `op.args[0].f` and PANICKED ("access of union field 'f' while field 'u'
// is active") on real modules like maps.beam. The E1.7 laws missed it because
// they build the `make_fun3` CInstr directly (bypassing the loader). These laws
// pin the loader boundary: a `.u` index resolves to the closure's code label
// (via the lambda table, then the normal label→pc fixup), and every malformed
// shape is a CLEAN `error.BadOperand` — never a panic.
// ---------------------------------------------------------------------------

/// Build a one-closure module: `make_fun3 <arg0> x2 {env}` followed by `label 1`.
/// The single lambda-table entry points at label `lam_label`, so a correct
/// decode fixes `make_fun3.to` to that label's pc. Caller owns the returned
/// Module (`mod.deinit()`); `code`/`atoms`/`lambdas` live in its arena.
fn buildMakeFun3Mod(gpa: std.mem.Allocator, arg0: Operand, lam_arity: u32, lam_label: u32, env: []const Operand) !Module {
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 1);
    atoms_arr[0] = "";
    const lambdas = try a.alloc(Lambda, 1);
    // W-16: `arity` (visible fun arity) is set INDEPENDENTLY of `num_free`
    // (== env.len) so the decode law can prove the loader threads the lambda
    // arity — not the env length — into `make_fun3.arity`.
    lambdas[0] = .{ .atom = 0, .arity = lam_arity, .label = lam_label, .index = 0, .num_free = @intCast(env.len), .old_uniq = 0 };
    // Everything the returned Module references must outlive this frame → arena.
    const env_copy = try a.dupe(Operand, env);
    const mf_args = try a.alloc(Operand, 3);
    mf_args[0] = arg0;
    mf_args[1] = Operand{ .x = 2 };
    mf_args[2] = Operand{ .list = env_copy };
    const lbl_args = try a.alloc(Operand, 1);
    lbl_args[0] = Operand{ .u = 1 };
    const code_arr = try a.alloc(Op, 2);
    code_arr[0] = .{ .opcode = opcodeByName("make_fun3"), .args = mf_args };
    code_arr[1] = .{ .opcode = opcodeByName("label"), .args = lbl_args };
    return .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 1,
        .lambdas = lambdas,
    };
}

test "LAW W-15 make_fun3 decodes a `.u` lambda index to the closure code label (env captured)" {
    const gpa = std.testing.allocator;
    // make_fun3 {u,0} x2 {x0} — lambda 0's label is 1; label 1 sits at pc 1, so
    // the resolved+fixed-up target is pc 1. The `.x=0` env is captured verbatim.
    // fix-closure-aliasing (CORRECTS the original W-16 assertion): the FunT
    // lambda `arity` field (2 here) is the implementation function's TOTAL
    // arity; the closure's VISIBLE arity is `arity - num_free` = 2 - 1 = 1
    // (erts generators.tab `MakeFun`: `a[2].val = $Arity - $NumFree`; the
    // `i_make_fun3` DEBUG assert `fun_arity == mfa->arity - num_free`). The
    // decode must carry the VISIBLE arity 1 — still ≠ env.len as a concept
    // (a lambda with arity 5, num_free 1 decodes to 4), but derived by the
    // erts subtraction, not the raw table field. The pre-fix raw-field decode
    // shifted the call_fun env-restore base and broke real closures
    // (fun_SUITE c_closure_distinct: {#Fun,#Fun} instead of {1,2}).
    var mod = try buildMakeFun3Mod(gpa, Operand{ .u = 0 }, 2, 1, &.{Operand{ .x = 0 }});
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer freeProg(gpa, t.prog); // frees make_fun3.env
    defer gpa.free(t.label_pc);
    defer gpa.free(t.entries);
    defer gpa.free(t.locs);

    try std.testing.expect(t.prog[0] == .make_fun3);
    const f = t.prog[0].make_fun3;
    try std.testing.expectEqual(@as(u16, 1), f.to); // label 1 → pc 1 (resolved via lambda table + fixup)
    try std.testing.expect(f.dst == .x and f.dst.x == 2);
    try std.testing.expectEqual(@as(u8, 1), f.arity); // VISIBLE arity = lambda 2 - num_free 1
    try std.testing.expectEqual(@as(usize, 1), f.env.len);
    try std.testing.expect(f.env[0] == .x and f.env[0].x == 0);
}

test "LAW W-15 make_fun3 rejects malformed operand-0 with error.BadOperand (no panic)" {
    const gpa = std.testing.allocator;
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();

    // (a) operand-0 is a raw label `.f` (the pre-fix assumption): clean reject,
    //     NOT a union-field panic.
    {
        var mod = try buildMakeFun3Mod(gpa, Operand{ .f = 1 }, 0, 1, &.{});
        defer mod.deinit();
        try std.testing.expectError(error.BadOperand, translate(gpa, &mod, &atbl, null));
    }
    // (b) operand-0 is a `.u` index past the end of the lambda table: clean reject.
    {
        var mod = try buildMakeFun3Mod(gpa, Operand{ .u = 7 }, 0, 1, &.{});
        defer mod.deinit();
        try std.testing.expectError(error.BadOperand, translate(gpa, &mod, &atbl, null));
    }
    // (c) the lambda's label exceeds the module label count: clean reject.
    {
        var mod = try buildMakeFun3Mod(gpa, Operand{ .u = 0 }, 0, 99, &.{});
        defer mod.deinit();
        try std.testing.expectError(error.BadOperand, translate(gpa, &mod, &atbl, null));
    }
}

// ---------------------------------------------------------------------------
// E4-boot-residual: preloaded-module loader-coverage laws. Real erlc `.beam`s
// (erlang, erl_prim_loader, …) `put_list` straight into a Y (stack) slot; the
// `ia.put_list` dst is a `u4` x-slot, so the loader lowers a Y dst to a cons
// into the x15 scratch + a `move2` to the stack (the `swap` idiom). Register
// indices past the 16-slot bank and register-valued map keys are NAMED
// diagnostics — never a bare `error.BadOperand` and never a truncation panic.
// ---------------------------------------------------------------------------

/// Build a one-op module (`<op> args` then `label 1`) whose FULL translated
/// program the caller inspects — like `translateSingle` but for ops that lower
/// to SEVERAL CInstrs (put_list into a Y slot). Caller owns the Module.
fn buildOneOpMod(gpa: std.mem.Allocator, name: []const u8, args: []const Operand) !Module {
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "m";
    const args_copy = try a.dupe(Operand, args);
    const lbl_args = try a.alloc(Operand, 1);
    lbl_args[0] = Operand{ .u = 1 };
    const code_arr = try a.alloc(Op, 2);
    code_arr[0] = .{ .opcode = opcodeByName(name), .args = args_copy };
    code_arr[1] = .{ .opcode = opcodeByName("label"), .args = lbl_args };
    return .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 1,
    };
}

test "LAW E4-boot-residual put_list into an X slot decodes to ONE unchanged put_list" {
    const gpa = std.testing.allocator;
    var mod = try buildOneOpMod(gpa, "put_list", &.{ Operand{ .x = 0 }, Operand{ .x = 1 }, Operand{ .x = 2 } });
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expectEqual(@as(usize, 1), t.prog.len); // no scratch/move2 for an x dst
    try std.testing.expect(t.prog[0] == .put_list);
    try std.testing.expectEqual(@as(u4, 2), t.prog[0].put_list.dst);
}

test "LAW E4-boot-residual put_list into a Y slot = cons via x15 scratch then move2 to the stack (decode + exec)" {
    const gpa = std.testing.allocator;
    var mod = try buildOneOpMod(gpa, "put_list", &.{ Operand{ .x = 0 }, Operand{ .x = 1 }, Operand{ .y = 2 } });
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    // DECODE: two instrs — cons into x15, then move2 x15 → y2.
    try std.testing.expectEqual(@as(usize, 2), t.prog.len);
    try std.testing.expect(t.prog[0] == .put_list and t.prog[0].put_list.dst == 15);
    try std.testing.expect(t.prog[1] == .move2);
    try std.testing.expect(t.prog[1].move2.src == .x and t.prog[1].move2.src.x == 15);
    try std.testing.expect(t.prog[1].move2.dst == .y and t.prog[1].move2.dst.y == 2);

    // EXEC: with y0..y2 allocated and x0=7, x1=[], y2 must hold the cons [7|[]].
    var m = try ia.Machine.init(gpa, &atbl);
    defer m.deinit();
    try m.ystack.append(m.gpa, FinalTerms.nil(&m.ctx)); // y2 (deepest)
    try m.ystack.append(m.gpa, FinalTerms.nil(&m.ctx)); // y1
    try m.ystack.append(m.gpa, FinalTerms.nil(&m.ctx)); // y0
    m.regs[0] = FinalTerms.int(&m.ctx, 7);
    m.regs[1] = FinalTerms.nil(&m.ctx);
    try ia.execInstr(&m, t.prog[0]);
    try ia.execInstr(&m, t.prog[1]);
    const expected = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 7), FinalTerms.nil(&m.ctx));
    // y2 is the deepest slot: ystack.items[len-1-2] == items[0].
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.ystack.items[0], expected));
}

test "LAW E5.2 the x-register file spans the full decodable range (DIVERGENCE 46 discharged: x16..x255 LOAD, xReg total)" {
    const gpa = std.testing.allocator;
    // E5.2 (DIVERGENCE 46): xReg is TOTAL over every u8 — the identity into the
    // widened `ia.x_reg_count`-slot bank. x16..x255 (which the 16-slot bank
    // rejected) are now first-class slots, never RegisterOverflow, never a panic.
    try std.testing.expectEqual(@as(ia.XReg, 0), xReg(0));
    try std.testing.expectEqual(@as(ia.XReg, 15), xReg(15));
    try std.testing.expectEqual(@as(ia.XReg, 16), xReg(16));
    try std.testing.expectEqual(@as(ia.XReg, 255), xReg(255));
    // The bank is sized to cover the full u8 index range.
    try std.testing.expectEqual(@as(usize, 256), ia.x_reg_count);
    // End-to-end: `move x16 x0` LOADS (x16 is a valid slot now) and decodes to a
    // move whose src is the x16 register — no rejection, no truncation panic.
    var mod = try buildOneOpMod(gpa, "move", &.{ Operand{ .x = 16 }, Operand{ .x = 0 } });
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0] == .move2);
    try std.testing.expect(t.prog[0].move2.src == .x and t.prog[0].move2.src.x == 16);
    // EXEC end-to-end: x16 holds 7 → `move x16 x0` writes 7 into x0.
    var m = try ia.Machine.init(gpa, &atbl);
    defer m.deinit();
    m.regs[16] = FinalTerms.int(&m.ctx, 7);
    try ia.execInstr(&m, t.prog[0]);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.int(&m.ctx, 7)));
}

test "LAW E5.2 get_map_elements with a REGISTER key decodes to a runtime Src (DIVERGENCE 47 discharged)" {
    const gpa = std.testing.allocator;
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    // E5.2 (DIVERGENCE 47): get_map_elements Fail=1 Src=x0 {key=x1, dst=x2} — the
    // key is a REGISTER, now decoded as a runtime `.x` Src, resolved at execution
    // (no false rejection, no UnsupportedOp).
    const reg_list = [_]Operand{ Operand{ .x = 1 }, Operand{ .x = 2 } };
    var mod = try buildOneOpMod(gpa, "get_map_elements", &.{ Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .list = &reg_list } });
    defer mod.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0] == .get_map_elements);
    try std.testing.expectEqual(@as(usize, 1), t.prog[0].get_map_elements.pairs.len);
    try std.testing.expect(t.prog[0].get_map_elements.pairs[0].key == .x);
    try std.testing.expectEqual(@as(ia.XReg, 1), t.prog[0].get_map_elements.pairs[0].key.x);

    // A LITERAL (atom) key still decodes cleanly — as an `.atom_` Src.
    const lit_list = [_]Operand{ Operand{ .atom = 1 }, Operand{ .x = 2 } };
    var mod2 = try buildOneOpMod(gpa, "get_map_elements", &.{ Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .list = &lit_list } });
    defer mod2.deinit();
    const t2 = try translate(gpa, &mod2, &atbl, null);
    defer {
        freeProg(gpa, t2.prog);
        gpa.free(t2.label_pc);
        gpa.free(t2.entries);
        gpa.free(t2.locs);
    }
    try std.testing.expect(t2.prog[0] == .get_map_elements);
    try std.testing.expect(t2.prog[0].get_map_elements.pairs[0].key == .atom_);
}

test "LAW W-16 checked operand helpers reject a wrong-variant operand (no panic)" {
    // The helpers are the SINGLE guard every translate arm now routes through:
    // a well-formed-but-differently-tagged operand must yield error.BadOperand,
    // never a "union field X while field Y is active" panic. (A Zig test cannot
    // catch a panic, so the law proves the GUARD exists by exercising the else
    // arm directly + end-to-end through representative translate arms.)

    // --- direct: each helper accepts its variant and rejects the others.
    try std.testing.expectEqual(@as(u16, 3), try labelIdOf(Operand{ .f = 3 }));
    try std.testing.expectError(error.BadOperand, labelIdOf(Operand{ .u = 3 }));
    try std.testing.expectError(error.BadOperand, labelIdOf(Operand{ .x = 0 }));

    try std.testing.expectEqual(@as(u64, 5), try uOf(Operand{ .u = 5 }));
    try std.testing.expectError(error.BadOperand, uOf(Operand{ .f = 5 }));
    try std.testing.expectError(error.BadOperand, uOf(Operand{ .x = 0 }));

    const one_list = [_]Operand{Operand{ .x = 0 }};
    try std.testing.expectEqual(@as(usize, 1), (try listOf(Operand{ .list = &one_list })).len);
    try std.testing.expectError(error.BadOperand, listOf(Operand{ .f = 0 }));
    try std.testing.expectError(error.BadOperand, listOf(Operand{ .u = 0 }));

    const gpa = std.testing.allocator;
    // --- end-to-end: an else_to-LABEL arm (`is_nil Lbl Src`) fed a `.u` where a
    //     `.f` label is expected → BadOperand (was: panic on `.f` access).
    try std.testing.expectError(error.BadOperand, translateSingle(gpa, "is_nil", &.{
        Operand{ .u = 1 }, Operand{ .x = 0 },
    }));
    // --- a `.u` arm (`allocate StackNeed Live`) fed a `.f` → BadOperand.
    try std.testing.expectError(error.BadOperand, translateSingle(gpa, "allocate", &.{
        Operand{ .f = 1 }, Operand{ .u = 0 },
    }));
    // --- a `.list` arm (`init_yregs {list}`) fed a `.f` → BadOperand.
    try std.testing.expectError(error.BadOperand, translateSingle(gpa, "init_yregs", &.{
        Operand{ .f = 1 },
    }));
}

// E24-T4 (beam_loader hardening — the last dark loader helper). `xOf`, the
// operand→X-register converter used by the `loop_rec` receive-opcode translation
// (`beam_loader.zig:2471`), was DARK: zero coverage on BOTH its accept and reject
// arms, because the `loop_rec` translate branch was never exercised at the LOADER
// level. This law covers `xOf` directly (all four arms) AND the `loop_rec`
// translate-rejection end-to-end, matching the W-16/W-19 "checked operand helper
// rejects a wrong variant — no panic" pattern.
//
// SEMANTIC DOMAIN. `xOf(o)` is the partial projection Operand → XReg, DEFINED
// only on an `.x` register or a typed-register `.tr` whose base is `.x` (the two
// forms a BEAM `loop_rec Label Source` destination can take), and UNDEFINED
// (→ error.BadOperand, NEVER a union-field panic) on every other operand tag —
// the load-time TOTALITY guard that keeps a malformed `.beam` from crashing the
// loader.
//
// OTP-30 CORRELATION. `loop_rec/2` is BEAM opcode 23
// (`third_party/otp/lib/compiler/src/genop.tab`: `## @spec loop_rec Label
// Source` — "Loop over the message queue, if it is empty jump to Label"). The
// compiler emits `Source` as an x-register (`{x,0}`, the mailbox-peek slot), so
// `xOf`'s x-only acceptance matches the emission; OTP's loader likewise validates
// operand shapes at load time (a malformed operand is a load ERROR, not a VM
// crash). This law pins that totality for `loop_rec`'s destination.
//
// EVOLUTION NOTES. If a future opcode legitimately targets a Y register through
// `xOf`, widen `xOf` AND this law to accept `.y` / `.tr(.y)`; today only the
// x-form is emitted for `loop_rec`, so the y-arms are correctly rejections.
// Mutant MUTATION_LOG e24-t4 m1 (make `xOf` accept `.y`) reddens the reject arm.
test "LAW E24-T4 beam_loader xOf totality + loop_rec translate-rejection (OTP-30 genop.tab loop_rec/2, no panic)" {
    // DIRECT: `xOf` projects `.x` and `.tr(.x)` to the register index; every
    // other tag (including `.tr(.y)`) is a clean BadOperand.
    try std.testing.expectEqual(@as(ia.XReg, 2), try xOf(Operand{ .x = 2 }));
    try std.testing.expectEqual(@as(ia.XReg, 1), try xOf(Operand{ .tr = .{ .base = .{ .x = 1 }, .type_idx = 0 } }));
    try std.testing.expectError(error.BadOperand, xOf(Operand{ .y = 0 }));
    try std.testing.expectError(error.BadOperand, xOf(Operand{ .tr = .{ .base = .{ .y = 0 }, .type_idx = 0 } }));
    try std.testing.expectError(error.BadOperand, xOf(Operand{ .f = 0 }));
    try std.testing.expectError(error.BadOperand, xOf(Operand{ .u = 0 }));

    // END-TO-END: `loop_rec Label Source` with a NON-x `Source` (a y-register)
    // → BadOperand through the real translate arm (@2471), never a panic.
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.BadOperand, translateSingle(gpa, "loop_rec", &.{
        Operand{ .f = 1 }, Operand{ .y = 0 },
    }));
}

// ---------------------------------------------------------------------------
// E1.3 type-test operand laws (emit∘parse identity at the CInstr boundary).
// A synthetic one-op module is translated and the decoded CInstr variant +
// operands are asserted. Each op's `else_to` starts as a LABEL id and must be
// patched to the label's pc — the tests place the label so the patched value
// is observable.
// ---------------------------------------------------------------------------

fn opcodeByName(name: []const u8) u16 {
    for (op_table, 0..) |maybe, oc| {
        if (maybe) |info| if (std.mem.eql(u8, info.name, name)) return @intCast(oc);
    }
    unreachable;
}

/// Translate a single generic op (plus a defining `label 1` so `else_to`
/// patches to a real pc = 1) and return the first decoded CInstr. Caller owns
/// nothing extra; the Translated is freed here, the CInstr is a value copy.
fn translateSingle(gpa: std.mem.Allocator, name: []const u8, args: []const Operand) !ia.CInstr {
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "m";
    const code_arr = try a.alloc(Op, 2);
    code_arr[0] = .{ .opcode = opcodeByName(name), .args = args };
    code_arr[1] = .{ .opcode = opcodeByName("label"), .args = &.{Operand{ .u = 1 }} };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 1,
    };
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        gpa.free(t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    return t.prog[0];
}

test "LAW E1.3 translate decodes is_integer to a .integer type_test (Lbl→else_to, Arg→src)" {
    const gpa = std.testing.allocator;
    // is_integer f:1 x:3 → .type_test{ .integer, .x=3, else_to = pc(label 1) = 1 }
    const ins = try translateSingle(gpa, "is_integer", &.{ Operand{ .f = 1 }, Operand{ .x = 3 } });
    try std.testing.expect(ins == .type_test);
    try std.testing.expectEqual(ia.TypeTestKind.integer, ins.type_test.kind);
    try std.testing.expect(ins.type_test.src == .x and ins.type_test.src.x == 3);
    try std.testing.expectEqual(@as(u16, 1), ins.type_test.else_to);
}

test "LAW E1.3 translate maps each unary is_* op name to its TypeTestKind" {
    const gpa = std.testing.allocator;
    const cases = .{
        .{ "is_float", ia.TypeTestKind.float },
        .{ "is_number", ia.TypeTestKind.number },
        .{ "is_atom", ia.TypeTestKind.atom },
        .{ "is_pid", ia.TypeTestKind.pid },
        .{ "is_reference", ia.TypeTestKind.reference },
        .{ "is_port", ia.TypeTestKind.port },
        .{ "is_binary", ia.TypeTestKind.binary },
        .{ "is_list", ia.TypeTestKind.list },
        .{ "is_map", ia.TypeTestKind.map },
        .{ "is_boolean", ia.TypeTestKind.boolean },
        .{ "is_function", ia.TypeTestKind.function },
        .{ "is_bitstr", ia.TypeTestKind.bitstr },
    };
    inline for (cases) |c| {
        const ins = try translateSingle(gpa, c[0], &.{ Operand{ .f = 1 }, Operand{ .x = 0 } });
        try std.testing.expect(ins == .type_test);
        try std.testing.expectEqual(c[1], ins.type_test.kind);
    }
}

test "LAW E1.3 translate decodes is_function2 to is_function_arity carrying the arity operand" {
    const gpa = std.testing.allocator;
    // is_function2 f:1 x:2 u:7 → .is_function_arity{ .x=2, arity=7, else_to=1 }
    const ins = try translateSingle(gpa, "is_function2", &.{ Operand{ .f = 1 }, Operand{ .x = 2 }, Operand{ .u = 7 } });
    try std.testing.expect(ins == .is_function_arity);
    try std.testing.expect(ins.is_function_arity.src == .x and ins.is_function_arity.src.x == 2);
    try std.testing.expectEqual(@as(u32, 7), ins.is_function_arity.arity);
    try std.testing.expectEqual(@as(u16, 1), ins.is_function_arity.else_to);
}

test "LAW W-19 translate decodes is_function2 with a signed .i arity operand" {
    const gpa = std.testing.allocator;
    // Real erlc emits Arity as {integer,N} (a signed `.i` literal operand),
    // not the compact `.u` count used by every other arity/count op — see
    // the W-19 module-doc note and the `intArgOf` helper doc-comment.
    // is_function2 f:1 x:2 i:3 → .is_function_arity{ .x=2, arity=3, else_to=1 }
    const ins = try translateSingle(gpa, "is_function2", &.{ Operand{ .f = 1 }, Operand{ .x = 2 }, Operand{ .i = 3 } });
    try std.testing.expect(ins == .is_function_arity);
    try std.testing.expect(ins.is_function_arity.src == .x and ins.is_function_arity.src.x == 2);
    try std.testing.expectEqual(@as(u32, 3), ins.is_function_arity.arity);
    try std.testing.expectEqual(@as(u16, 1), ins.is_function_arity.else_to);
}

test "LAW W-19 translate rejects a negative .i arity operand cleanly (no panic)" {
    const gpa = std.testing.allocator;
    // is_function2 f:1 x:2 i:-1 → error.BadOperand, never a panic: a
    // negative arity is not a valid fun-arity count.
    try std.testing.expectError(error.BadOperand, translateSingle(gpa, "is_function2", &.{ Operand{ .f = 1 }, Operand{ .x = 2 }, Operand{ .i = -1 } }));
}

test "LAW E6.8 translate decodes is_function2 with a REGISTER arity operand to arity_src (put_list-to-Y precedent)" {
    const gpa = std.testing.allocator;
    // E6.8 (DIVERGENCE 97 (3a)): eunit_data's `check_arity/3` emits
    // `is_function2 {f,142} [{x,0},{tr,{x,1},{t_integer,{0,2}}}]` — the Arity
    // operand is a TYPED REGISTER (arity known only at runtime). A plain `.x`
    // register decodes to arity_src=x-reg with the static `.arity` field unused.
    const ins = try translateSingle(gpa, "is_function2", &.{ Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .x = 1 } });
    try std.testing.expect(ins == .is_function_arity);
    try std.testing.expect(ins.is_function_arity.src == .x and ins.is_function_arity.src.x == 0);
    try std.testing.expect(ins.is_function_arity.arity_src != null);
    try std.testing.expect(ins.is_function_arity.arity_src.? == .x and ins.is_function_arity.arity_src.?.x == 1);
    try std.testing.expectEqual(@as(u16, 1), ins.is_function_arity.else_to);
}

test "LAW E6.8 translate decodes is_function2 with a TYPED-REGISTER (.tr) arity operand (the eunit_data shape)" {
    const gpa = std.testing.allocator;
    // The exact operand form from eunit_data: {tr,{x,1},ty} — the typed
    // register unwraps to its base x-register as the arity source.
    const tr = Operand{ .tr = .{ .base = .{ .x = 1 }, .type_idx = 13 } };
    const ins = try translateSingle(gpa, "is_function2", &.{ Operand{ .f = 1 }, Operand{ .x = 0 }, tr });
    try std.testing.expect(ins == .is_function_arity);
    try std.testing.expect(ins.is_function_arity.arity_src != null);
    try std.testing.expect(ins.is_function_arity.arity_src.? == .x and ins.is_function_arity.arity_src.?.x == 1);
    // A y-register-based typed register unwraps to a y source.
    const tr_y = Operand{ .tr = .{ .base = .{ .y = 2 }, .type_idx = 0 } };
    const ins_y = try translateSingle(gpa, "is_function2", &.{ Operand{ .f = 1 }, Operand{ .x = 0 }, tr_y });
    try std.testing.expect(ins_y.is_function_arity.arity_src.? == .y and ins_y.is_function_arity.arity_src.?.y == 2);
}

test "LAW W-19 intArgOf accepts .u and non-negative .i, rejects negative .i and other tags" {
    try std.testing.expectEqual(@as(u64, 5), try intArgOf(Operand{ .u = 5 }));
    try std.testing.expectEqual(@as(u64, 3), try intArgOf(Operand{ .i = 3 }));
    try std.testing.expectEqual(@as(u64, 0), try intArgOf(Operand{ .i = 0 }));
    try std.testing.expectError(error.BadOperand, intArgOf(Operand{ .i = -1 }));
    try std.testing.expectError(error.BadOperand, intArgOf(Operand{ .f = 5 }));
    try std.testing.expectError(error.BadOperand, intArgOf(Operand{ .x = 0 }));
}

test "LAW E1.4 translate decodes is_ge to a .ge cmp_test (Lbl→else_to, Src,Src→a,b)" {
    const gpa = std.testing.allocator;
    // is_ge f:1 x:2 x:3 → .cmp_test{ .ge, .x=2, .x=3, else_to = pc(label 1) = 1 }
    const ins = try translateSingle(gpa, "is_ge", &.{ Operand{ .f = 1 }, Operand{ .x = 2 }, Operand{ .x = 3 } });
    try std.testing.expect(ins == .cmp_test);
    try std.testing.expectEqual(ia.CmpTestKind.ge, ins.cmp_test.op);
    try std.testing.expect(ins.cmp_test.a == .x and ins.cmp_test.a.x == 2);
    try std.testing.expect(ins.cmp_test.b == .x and ins.cmp_test.b.x == 3);
    try std.testing.expectEqual(@as(u16, 1), ins.cmp_test.else_to);
}

test "LAW E1.4 translate maps each binary compare op name to its CmpTestKind" {
    const gpa = std.testing.allocator;
    const cases = .{
        .{ "is_ge", ia.CmpTestKind.ge },
        .{ "is_eq", ia.CmpTestKind.eq_arith },
        .{ "is_ne", ia.CmpTestKind.ne_arith },
        .{ "is_ne_exact", ia.CmpTestKind.ne_exact },
    };
    inline for (cases) |c| {
        const ins = try translateSingle(gpa, c[0], &.{ Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .x = 1 } });
        try std.testing.expect(ins == .cmp_test);
        try std.testing.expectEqual(c[1], ins.cmp_test.op);
    }
}

// E1.5 tuple-op operand laws (emit∘parse identity at the CInstr boundary): a
// synthetic one-op module is translated and the decoded CInstr variant + fields
// are pinned. Operand orders are the genop.tab orders; indices stay 0-based.

test "LAW E1.5 translate decodes get_tuple_element (Src, 0-based Index, Dst)" {
    const gpa = std.testing.allocator;
    // get_tuple_element x:2 u:1 x:3 → .get_tuple_elem{ .x=2, index=1, .x=3 }
    const ins = try translateSingle(gpa, "get_tuple_element", &.{ Operand{ .x = 2 }, Operand{ .u = 1 }, Operand{ .x = 3 } });
    try std.testing.expect(ins == .get_tuple_elem);
    try std.testing.expect(ins.get_tuple_elem.src == .x and ins.get_tuple_elem.src.x == 2);
    try std.testing.expectEqual(@as(u16, 1), ins.get_tuple_elem.index);
    try std.testing.expect(ins.get_tuple_elem.dst == .x and ins.get_tuple_elem.dst.x == 3);
}

test "LAW E1.5 translate decodes set_tuple_element (NewVal, Tuple, 0-based Index)" {
    const gpa = std.testing.allocator;
    // set_tuple_element x:5 x:0 u:1 → .set_tuple_elem{ newval x:5, tuple x:0, index=1 }
    const ins = try translateSingle(gpa, "set_tuple_element", &.{ Operand{ .x = 5 }, Operand{ .x = 0 }, Operand{ .u = 1 } });
    try std.testing.expect(ins == .set_tuple_elem);
    try std.testing.expect(ins.set_tuple_elem.newval == .x and ins.set_tuple_elem.newval.x == 5);
    try std.testing.expect(ins.set_tuple_elem.tuple == .x and ins.set_tuple_elem.tuple.x == 0);
    try std.testing.expectEqual(@as(u16, 1), ins.set_tuple_elem.index);
}

test "LAW E1.5 translate decodes test_arity to a guarded test (Lbl→else_to, Src, Arity)" {
    const gpa = std.testing.allocator;
    // test_arity f:1 x:0 u:3 → .test_arity{ .x=0, arity=3, else_to = pc(label 1) = 1 }
    const ins = try translateSingle(gpa, "test_arity", &.{ Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .u = 3 } });
    try std.testing.expect(ins == .test_arity);
    try std.testing.expect(ins.test_arity.src == .x and ins.test_arity.src.x == 0);
    try std.testing.expectEqual(@as(u16, 3), ins.test_arity.arity);
    try std.testing.expectEqual(@as(u16, 1), ins.test_arity.else_to);
}

test "LAW E1.5 translate decodes is_tagged_tuple (Lbl→else_to, Src, Arity, atom tag)" {
    const gpa = std.testing.allocator;
    // is_tagged_tuple f:1 x:0 u:2 atom:1("m") → .is_tagged_tuple{...tag is an atom}
    const ins = try translateSingle(gpa, "is_tagged_tuple", &.{ Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .u = 2 }, Operand{ .atom = 1 } });
    try std.testing.expect(ins == .is_tagged_tuple);
    try std.testing.expect(ins.is_tagged_tuple.src == .x and ins.is_tagged_tuple.src.x == 0);
    try std.testing.expectEqual(@as(u16, 2), ins.is_tagged_tuple.arity);
    try std.testing.expectEqual(@as(u16, 1), ins.is_tagged_tuple.else_to);
    // The tag decoded to an atom term (the E1.5 addition: is_tuple is a type_test).
    try std.testing.expect(FinalTerms.repIsAtom(ins.is_tagged_tuple.tag));
}

test "LAW E1.5 translate decodes is_tuple to a .tuple type_test (Lbl→else_to, Src)" {
    const gpa = std.testing.allocator;
    // is_tuple f:1 x:4 → .type_test{ .tuple, .x=4, else_to = pc(label 1) = 1 }
    const ins = try translateSingle(gpa, "is_tuple", &.{ Operand{ .f = 1 }, Operand{ .x = 4 } });
    try std.testing.expect(ins == .type_test);
    try std.testing.expectEqual(ia.TypeTestKind.tuple, ins.type_test.kind);
    try std.testing.expect(ins.type_test.src == .x and ins.type_test.src.x == 4);
    try std.testing.expectEqual(@as(u16, 1), ins.type_test.else_to);
}

test "LAW E1.9 translate decodes allocate_heap (StackNeed→stack, Live→live; HeapNeed advisory/dropped)" {
    const gpa = std.testing.allocator;
    // allocate_heap u:3 u:50 u:1 → .alloc_heap{ .stack = 3, .live = 1 }.
    // HeapNeed (50) is a moving-GC hint this VM does not carry (arena grows
    // on demand) — same treatment as test_heap's HeapNeed operand.
    const ins = try translateSingle(gpa, "allocate_heap", &.{ Operand{ .u = 3 }, Operand{ .u = 50 }, Operand{ .u = 1 } });
    try std.testing.expect(ins == .alloc_heap);
    try std.testing.expectEqual(@as(u8, 3), ins.alloc_heap.stack);
    try std.testing.expectEqual(@as(u8, 1), ins.alloc_heap.live);
}

test "LAW E1.9 translate decodes trim (N→n; Remaining advisory/dropped)" {
    const gpa = std.testing.allocator;
    // trim u:2 u:3 → .trim{ .n = 2 }. Remaining (3) is advisory, like Live.
    const ins = try translateSingle(gpa, "trim", &.{ Operand{ .u = 2 }, Operand{ .u = 3 } });
    try std.testing.expect(ins == .trim);
    try std.testing.expectEqual(@as(u8, 2), ins.trim.n);
}

test "LAW E1.8 translate decodes the exception opcodes to their CInstr variants" {
    const gpa = std.testing.allocator;

    // catch Dst Lbl → .catch_{ to = pc(label 1) = 1, dst = y2 }. Operand order is
    // (Dst, Lbl): args[0]=Dst, args[1]=Lbl.
    const c = try translateSingle(gpa, "catch", &.{ Operand{ .y = 2 }, Operand{ .f = 1 } });
    try std.testing.expect(c == .catch_);
    try std.testing.expectEqual(@as(u16, 1), c.catch_.to); // Lbl fixed up to pc 1
    try std.testing.expect(c.catch_.dst == .y and c.catch_.dst.y == 2);

    // try Dst Lbl → .try_ (same operand shape).
    const t = try translateSingle(gpa, "try", &.{ Operand{ .y = 0 }, Operand{ .f = 1 } });
    try std.testing.expect(t == .try_);
    try std.testing.expectEqual(@as(u16, 1), t.try_.to);

    // single-Dst pops.
    try std.testing.expect((try translateSingle(gpa, "catch_end", &.{Operand{ .y = 1 }})) == .catch_end);
    try std.testing.expect((try translateSingle(gpa, "try_end", &.{Operand{ .y = 1 }})) == .try_end);
    try std.testing.expect((try translateSingle(gpa, "try_case", &.{Operand{ .y = 1 }})) == .try_case);

    // guard-failure crashes + re-raise + no-operand ops.
    try std.testing.expect((try translateSingle(gpa, "try_case_end", &.{Operand{ .x = 0 }})) == .try_case_end);
    try std.testing.expect((try translateSingle(gpa, "badrecord", &.{Operand{ .x = 0 }})) == .badrecord);
    const r = try translateSingle(gpa, "raise", &.{ Operand{ .x = 2 }, Operand{ .x = 3 } });
    try std.testing.expect(r == .raise);
    try std.testing.expect(r.raise.trace == .x and r.raise.trace.x == 2);
    try std.testing.expect(r.raise.value == .x and r.raise.value.x == 3);
    try std.testing.expect((try translateSingle(gpa, "raw_raise", &.{})) == .raw_raise);
    try std.testing.expect((try translateSingle(gpa, "build_stacktrace", &.{})) == .build_stacktrace);
}

test "LAW E1.5 translate decodes put_tuple2 into a gpa-owned elems slice (no leak)" {
    const gpa = std.testing.allocator;
    // put_tuple2 x:0 {x:1, u:7, atom:0([])} — a 3-element tuple build. Translate
    // directly (not translateSingle) so the owned `elems` slice survives to be
    // inspected, then release it with freeProg (the zero-leak law).
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "m";
    const list = try a.alloc(Operand, 3);
    list[0] = .{ .x = 1 };
    list[1] = .{ .u = 7 };
    list[2] = .{ .atom = 0 }; // [] / nil
    const code_arr = try a.alloc(Op, 1);
    code_arr[0] = .{ .opcode = opcodeByName("put_tuple2"), .args = &.{ Operand{ .x = 0 }, Operand{ .list = list } } };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 0,
    };
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0] == .put_tuple2);
    const p = t.prog[0].put_tuple2;
    try std.testing.expect(p.dst == .x and p.dst.x == 0);
    try std.testing.expectEqual(@as(usize, 3), p.elems.len);
    try std.testing.expect(p.elems[0] == .x and p.elems[0].x == 1);
    try std.testing.expect(p.elems[1] == .imm and p.elems[1].imm == 7);
    try std.testing.expect(p.elems[2] == .nil);
}

test "LAW E1.14 translate decodes update_record: Offset→0-based index, drops Hint/Size, gpa-owned (no leak)" {
    const gpa = std.testing.allocator;
    // update_record Hint=atom(inplace) Size=3 Src=x1 Dst=x0
    //   {Offset2→x2, Offset4→u:7}  → updates[0]={index=1,x2}, [1]={index=3,imm7}.
    // The 1-based BEAM Offsets 2 and 4 must decode to 0-based indices 1 and 3;
    // Hint and Size are dropped. Translate directly so the owned slice survives.
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "inplace";
    const list = try a.alloc(Operand, 4);
    list[0] = .{ .u = 2 }; // Offset 2 → index 1
    list[1] = .{ .x = 2 };
    list[2] = .{ .u = 4 }; // Offset 4 → index 3
    list[3] = .{ .u = 7 };
    const code_arr = try a.alloc(Op, 1);
    code_arr[0] = .{ .opcode = opcodeByName("update_record"), .args = &.{
        Operand{ .atom = 1 }, // Hint (dropped)
        Operand{ .u = 3 }, //    Size (dropped)
        Operand{ .x = 1 }, //    Src
        Operand{ .x = 0 }, //    Dst
        Operand{ .list = list },
    } };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 0,
    };
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0] == .update_record);
    const u = t.prog[0].update_record;
    try std.testing.expect(u.src == .x and u.src.x == 1);
    try std.testing.expect(u.dst == .x and u.dst.x == 0);
    try std.testing.expectEqual(@as(usize, 2), u.updates.len);
    try std.testing.expectEqual(@as(u16, 1), u.updates[0].index);
    try std.testing.expect(u.updates[0].value == .x and u.updates[0].value.x == 2);
    try std.testing.expectEqual(@as(u16, 3), u.updates[1].index);
    try std.testing.expect(u.updates[1].value == .imm and u.updates[1].value.imm == 7);
}

test "LAW E1.14 translate errdefer frees update_record.updates on mid-translation failure (zero-leak)" {
    // FIX 1 regression law: an `update_record` (whose `.updates` slice is gpa-owned)
    // is appended, THEN a later op fails translation. The errdefer must release
    // `updates` — under `std.testing.allocator` a leak fails the test. Removing the
    // `.update_record => |u| gpa.free(u.updates)` arm from translate's errdefer
    // makes THIS test leak and fail (the mutant), so the arm is pinned here.
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "inplace";
    const list = try a.alloc(Operand, 4);
    list[0] = .{ .u = 2 }; // Offset 2 → index 1
    list[1] = .{ .x = 2 };
    list[2] = .{ .u = 4 }; // Offset 4 → index 3
    list[3] = .{ .u = 7 };
    // op0: a VALID update_record (allocates the gpa-owned updates slice, appended).
    // op1: `init/1` — a real but OBSOLETE opcode (the `-init/1` genop.tab
    //      marker) the loader does NOT support (E3.4 repointed this from
    //      `bs_create_bin`, which THIS task newly implements), so translate's
    //      single-source guard returns error.UnsupportedOp AFTER op0 is
    //      already appended, exercising the errdefer.
    const code_arr = try a.alloc(Op, 2);
    code_arr[0] = .{ .opcode = opcodeByName("update_record"), .args = &.{
        Operand{ .atom = 1 }, // Hint (dropped)
        Operand{ .u = 3 }, //    Size (dropped)
        Operand{ .x = 1 }, //    Src
        Operand{ .x = 0 }, //    Dst
        Operand{ .list = list },
    } };
    code_arr[1] = .{ .opcode = opcodeByName("init"), .args = &.{} };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 0,
    };
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    // translate MUST fail (the unsupported op) — and MUST NOT leak `updates`.
    try std.testing.expectError(error.UnsupportedOp, translate(gpa, &mod, &atbl, null));
}

test "LAW E3.14 translate decodes put_record + get_record_field (gpa-owned, no leak)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 5);
    atoms_arr[0] = "";
    atoms_arr[1] = "mod";
    atoms_arr[2] = "point";
    atoms_arr[3] = "x";
    atoms_arr[4] = "y";
    // put_record Lbl=f0 Id=x9 Src=x0 Dst=x3 Live=u0 {x=x1, y=x2}
    const upd = try a.alloc(Operand, 4);
    upd[0] = .{ .atom = 3 }; // x
    upd[1] = .{ .x = 1 };
    upd[2] = .{ .atom = 4 }; // y
    upd[3] = .{ .x = 2 };
    const code_arr = try a.alloc(Op, 2);
    code_arr[0] = .{ .opcode = opcodeByName("put_record"), .args = &.{
        Operand{ .f = 0 }, //   Lbl (reserved, 0)
        Operand{ .x = 9 }, //   Id
        Operand{ .x = 0 }, //   Src
        Operand{ .x = 3 }, //   Dst
        Operand{ .u = 0 }, //   Live (dropped)
        Operand{ .list = upd },
    } };
    // get_record_field Lbl=f0 Rec=x0 Id=x9 Field=atom(x) Dst=x2 → else_to null.
    code_arr[1] = .{ .opcode = opcodeByName("get_record_field"), .args = &.{
        Operand{ .f = 0 },
        Operand{ .x = 0 },
        Operand{ .x = 9 },
        Operand{ .atom = 3 },
        Operand{ .x = 2 },
    } };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 0,
    };
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0] == .put_record);
    const p = t.prog[0].put_record;
    try std.testing.expect(p.id == .x and p.id.x == 9);
    try std.testing.expectEqual(@as(usize, 2), p.updates.len);
    try std.testing.expect(t.prog[1] == .get_record_field);
    try std.testing.expect(t.prog[1].get_record_field.else_to == null); // Lbl==0 ⇒ raise form
}

test "LAW E1.6 translate decodes select_val into a gpa-owned pairs slice (keys + label fixup, no leak)" {
    const gpa = std.testing.allocator;
    // Filler func_info ops keep the three labels at DISTINCT pcs so the label
    // fixup (label id → pc) is observable. select_val x0 fail=L3 {10→L1, 20→L2}.
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "m";
    const list = try a.alloc(Operand, 4);
    list[0] = .{ .i = 10 };
    list[1] = .{ .f = 1 };
    list[2] = .{ .i = 20 };
    list[3] = .{ .f = 2 };
    const code_arr = try a.alloc(Op, 7);
    const fi = opcodeByName("func_info");
    const lbl = opcodeByName("label");
    code_arr[0] = .{ .opcode = fi, .args = &.{} }; // prog[0]
    code_arr[1] = .{ .opcode = lbl, .args = &.{Operand{ .u = 1 }} }; // label_pc[1]=1
    code_arr[2] = .{ .opcode = fi, .args = &.{} }; // prog[1]
    code_arr[3] = .{ .opcode = lbl, .args = &.{Operand{ .u = 2 }} }; // label_pc[2]=2
    code_arr[4] = .{ .opcode = fi, .args = &.{} }; // prog[2]
    code_arr[5] = .{ .opcode = lbl, .args = &.{Operand{ .u = 3 }} }; // label_pc[3]=3
    code_arr[6] = .{ .opcode = opcodeByName("select_val"), .args = &.{
        Operand{ .x = 0 }, Operand{ .f = 3 }, Operand{ .list = list },
    } };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 3,
    };
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog); // frees the pairs slice — the zero-leak law
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[3] == .select_val);
    const s = t.prog[3].select_val;
    try std.testing.expect(s.src == .x and s.src.x == 0);
    try std.testing.expectEqual(@as(u16, 3), s.fail_to); // L3 → pc 3
    try std.testing.expectEqual(@as(usize, 2), s.pairs.len);
    try std.testing.expectEqual(FinalTerms.int(undefined, 10), s.pairs[0].key);
    try std.testing.expectEqual(@as(u16, 1), s.pairs[0].to); // L1 → pc 1
    try std.testing.expectEqual(FinalTerms.int(undefined, 20), s.pairs[1].key);
    try std.testing.expectEqual(@as(u16, 2), s.pairs[1].to); // L2 → pc 2
}

test "LAW E1.6 translate decodes select_tuple_arity into a gpa-owned pairs slice (no leak)" {
    const gpa = std.testing.allocator;
    // select_tuple_arity x0 fail=L1 {2→L1, 3→L1}. One label suffices here — the
    // decode law only checks arity keys + gpa ownership; label fixup is proven
    // by the select_val law above and the differential/G2 gates.
    var arena = std.heap.ArenaAllocator.init(gpa);
    const a = arena.allocator();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "m";
    const list = try a.alloc(Operand, 4);
    list[0] = .{ .u = 2 };
    list[1] = .{ .f = 1 };
    list[2] = .{ .u = 3 };
    list[3] = .{ .f = 1 };
    const code_arr = try a.alloc(Op, 2);
    code_arr[0] = .{ .opcode = opcodeByName("select_tuple_arity"), .args = &.{
        Operand{ .x = 0 }, Operand{ .f = 1 }, Operand{ .list = list },
    } };
    code_arr[1] = .{ .opcode = opcodeByName("label"), .args = &.{Operand{ .u = 1 }} };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 1,
    };
    defer mod.deinit();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0] == .select_tuple_arity);
    const s = t.prog[0].select_tuple_arity;
    try std.testing.expect(s.src == .x and s.src.x == 0);
    try std.testing.expectEqual(@as(usize, 2), s.pairs.len);
    try std.testing.expectEqual(@as(u16, 2), s.pairs[0].arity);
    try std.testing.expectEqual(@as(u16, 3), s.pairs[1].arity);
}

test "parse: chunks, atoms, exports land" {
    var mod = try parse(std.testing.allocator, fixture);
    defer mod.deinit();
    try std.testing.expect(std.mem.eql(u8, mod.atomName(1), "mylists"));
    try std.testing.expect(mod.exports.len == 6); // 4 + module_info/0,1
    try std.testing.expect(mod.code.len > 30);
}

test "LAW E4.2 module-md5 determinism + metadata retention (real erlc fixture)" {
    // PARSE-DETERMINISM: the module checksum is a pure function of the file
    // bytes — two independent parses of the SAME .beam produce the SAME md5.
    var m1 = try parse(std.testing.allocator, fixture);
    defer m1.deinit();
    var m2 = try parse(std.testing.allocator, fixture);
    defer m2.deinit();
    try std.testing.expect(m1.has_md5);
    try std.testing.expectEqualSlices(u8, &m1.mod_md5, &m2.mod_md5);
    // a real erlc module is never the all-zero md5 (the empty-hash sentinel).
    try std.testing.expect(!std.mem.eql(u8, &m1.mod_md5, &([_]u8{0} ** 16)));
    // RETENTION: mylists carries a CInf chunk (erlc always emits compile info);
    // the raw ETF bytes are held for module_info(compile), version-prefixed.
    try std.testing.expect(m1.compile_bytes.len > 0);
    try std.testing.expectEqual(@as(u8, 131), m1.compile_bytes[0]); // ETF version magic
    // ORDER-INDEPENDENCE of the hash set: computeMd5 over the SAME chunk slices
    // is stable regardless of on-disk chunk order (it hashes in erts' fixed
    // order), so a second computeMd5 with the captured chunks equals the first.
    // (Proven transitively by the two-parse equality above.)
}

test "LAW E4.2 module-md5 == erts checksum (FunT OldUniq ignored)" {
    // computeMd5 must IGNORE each FunT entry's OldUniq word (erts zeroes it).
    // Build a 1-entry FunT: 4-byte count + 24-byte record; flipping ONLY the
    // last 4 bytes (OldUniq) must NOT change the md5.
    var funt_a = [_]u8{0} ** 28;
    funt_a[3] = 1; // count = 1
    // bytes 4..24 are Function/Arity/Index/NumFree (kept); 24..28 = OldUniq
    for (4..24) |i| funt_a[i] = @intCast(i);
    var funt_b = funt_a;
    funt_b[24] = 0xAA; // perturb OldUniq only
    funt_b[27] = 0xFF;
    const a = computeMd5(.{ .atu8 = "atoms", .code = "code", .funt = &funt_a });
    const b = computeMd5(.{ .atu8 = "atoms", .code = "code", .funt = &funt_b });
    try std.testing.expectEqualSlices(u8, &a, &b);
    // …but perturbing a KEPT FunT byte DOES change the md5 (the hash is live).
    var funt_c = funt_a;
    funt_c[5] = 0x99;
    const c = computeMd5(.{ .atu8 = "atoms", .code = "code", .funt = &funt_c });
    try std.testing.expect(!std.mem.eql(u8, &a, &c));
}

test "LAW emit∘parse = id: re-encoded Code section is byte-identical" {
    var mod = try parse(std.testing.allocator, fixture);
    defer mod.deinit();
    var out = try emit(std.testing.allocator, mod.code);
    defer out.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.eql(u8, mod.code_bytes[0..out.items.len], out.items));
    // trailing bytes after int_code_end are chunk padding only
    try std.testing.expect(mod.code_bytes.len - out.items.len < 4);
}

// ---------------------------------------------------------------------------
// E0.6 AtU8 long-atom law. OTP-28+ erlc writes the atom-table chunk in a "long
// atom names" variant: a NEGATIVE i32 count field (magnitude = atom count)
// signals that each atom's length is COMPACT-term encoded rather than a plain
// u8 (so names may exceed 255 bytes). The legacy form (still emitted by the
// vendored OTP-30 fixture) is a positive u32 count with u8 lengths. parse must
// accept BOTH and decode the SAME atom table — this is what lets host-28
// erlc-compiled corpus modules load at all (§E0.6 differential corpus).
// ---------------------------------------------------------------------------

/// Assemble a minimal FOR1/BEAM image carrying exactly two chunks: an AtU8 with
/// the given atom names, encoded in either the long or legacy form, plus a
/// one-instruction Code chunk (int_code_end) so parse does not reject on an
/// empty code section. Returns owned bytes.
fn buildAtomOnlyBeam(
    gpa: std.mem.Allocator,
    names: []const []const u8,
    long_form: bool,
) !std.ArrayList(u8) {
    var atu8: std.ArrayList(u8) = .empty;
    defer atu8.deinit(gpa);
    if (long_form) {
        // count = -(n) as i32 big-endian (the long-atom sentinel).
        const neg: u32 = @bitCast(-@as(i32, @intCast(names.len)));
        try atu8.append(gpa, @truncate(neg >> 24));
        try atu8.append(gpa, @truncate(neg >> 16));
        try atu8.append(gpa, @truncate(neg >> 8));
        try atu8.append(gpa, @truncate(neg));
        for (names) |nm| {
            try emitValue(&atu8, gpa, TAG_U, nm.len); // compact length
            try atu8.appendSlice(gpa, nm);
        }
    } else {
        const n: u32 = @intCast(names.len);
        try atu8.append(gpa, @truncate(n >> 24));
        try atu8.append(gpa, @truncate(n >> 16));
        try atu8.append(gpa, @truncate(n >> 8));
        try atu8.append(gpa, @truncate(n));
        for (names) |nm| {
            try atu8.append(gpa, @intCast(nm.len)); // plain u8 length
            try atu8.appendSlice(gpa, nm);
        }
    }
    // Code chunk: 20-byte header (subsz=16, iset=0, opmax=0, nlabels=0,
    // nfuncs=0) then a single int_code_end (opcode 3, arity 0).
    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(gpa);
    const hdr = [_]u32{ 16, 0, 0, 0, 0 };
    for (hdr) |h| {
        try code.append(gpa, @truncate(h >> 24));
        try code.append(gpa, @truncate(h >> 16));
        try code.append(gpa, @truncate(h >> 8));
        try code.append(gpa, @truncate(h));
    }
    try code.append(gpa, 3); // int_code_end

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const appendChunk = struct {
        fn f(o: *std.ArrayList(u8), g: std.mem.Allocator, tag: []const u8, body: []const u8) !void {
            try o.appendSlice(g, tag);
            const sz: u32 = @intCast(body.len);
            try o.append(g, @truncate(sz >> 24));
            try o.append(g, @truncate(sz >> 16));
            try o.append(g, @truncate(sz >> 8));
            try o.append(g, @truncate(sz));
            try o.appendSlice(g, body);
            while ((o.items.len % 4) != 0) try o.append(g, 0); // 4-byte pad
        }
    }.f;
    try out.appendSlice(gpa, "FOR1");
    try out.appendSlice(gpa, &.{ 0, 0, 0, 0 }); // size placeholder (unused by parse)
    try out.appendSlice(gpa, "BEAM");
    try appendChunk(&out, gpa, "AtU8", atu8.items);
    try appendChunk(&out, gpa, "Code", code.items);
    return out;
}

test "LAW AtU8 long-atom form decodes identically to the legacy form" {
    const gpa = std.testing.allocator;
    // Short names representable in BOTH forms: the long/legacy decoders must
    // agree exactly on them.
    const names = [_][]const u8{ "mylists", "sum_list", "erlang", "+" };

    var legacy = try buildAtomOnlyBeam(gpa, &names, false);
    defer legacy.deinit(gpa);
    var long = try buildAtomOnlyBeam(gpa, &names, true);
    defer long.deinit(gpa);

    var m_leg = try parse(gpa, legacy.items);
    defer m_leg.deinit();
    var m_long = try parse(gpa, long.items);
    defer m_long.deinit();

    // Same count (1-based: index 0 is the reserved empty atom) and same names.
    try std.testing.expectEqual(m_leg.atoms.len, m_long.atoms.len);
    try std.testing.expectEqual(names.len + 1, m_long.atoms.len);
    for (names, 1..) |want, i| {
        try std.testing.expect(std.mem.eql(u8, m_long.atomName(@intCast(i)), want));
        try std.testing.expect(std.mem.eql(u8, m_leg.atomName(@intCast(i)), want));
    }

    // The long form's raison d'être: an atom name longer than 255 bytes, which
    // the legacy u8-length form cannot physically encode. Decodes via the
    // multi-byte compact length.
    const big = "z" ** 300;
    const long_names = [_][]const u8{ "erlang", big, "ok" };
    var beam = try buildAtomOnlyBeam(gpa, &long_names, true);
    defer beam.deinit(gpa);
    var m_big = try parse(gpa, beam.items);
    defer m_big.deinit();
    try std.testing.expectEqual(long_names.len + 1, m_big.atoms.len);
    try std.testing.expect(std.mem.eql(u8, m_big.atomName(2), big));
    try std.testing.expect(std.mem.eql(u8, m_big.atomName(3), "ok"));
}

test "LAW parse∘emit = id on synthetic operand torture (all forms)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // one op with every operand shape and boundary values (label/1 has
    // arity 1; we synthesize a fake op stream: opcode 64 = move/2 pairs)
    const cases = [_]Operand{
        .{ .u = 0 },      .{ .u = 15 },     .{ .u = 16 },    .{ .u = 2047 },
        .{ .u = 2048 },   .{ .u = 70000 },  .{ .i = -1 },    .{ .i = -300 },
        .{ .i = 123456 }, .{ .atom = 3 },   .{ .x = 7 },     .{ .y = 200 },
        .{ .f = 1234 },   .{ .char = 65 },
    };
    var k: usize = 0;
    while (k + 1 < cases.len) : (k += 2) {
        const ops = [_]Op{.{ .opcode = 64, .args = cases[k .. k + 2] }};
        var bytes = try emit(gpa, &ops);
        defer bytes.deinit(gpa);
        var r = Reader{ .buf = bytes.items };
        const opcode = try r.u8_();
        try std.testing.expectEqual(@as(u16, 64), opcode);
        for (cases[k .. k + 2]) |want| {
            const got = try decodeOperand(&r, a);
            try std.testing.expect(std.meta.activeTag(got) == std.meta.activeTag(want));
            switch (want) {
                .u => |v| try std.testing.expectEqual(v, got.u),
                .i => |v| try std.testing.expectEqual(v, got.i),
                .atom => |v| try std.testing.expectEqual(v, got.atom),
                .x => |v| try std.testing.expectEqual(v, got.x),
                .y => |v| try std.testing.expectEqual(v, got.y),
                .f => |v| try std.testing.expectEqual(v, got.f),
                .char => |v| try std.testing.expectEqual(v, got.char),
                else => unreachable,
            }
        }
    }
}

test "ORACLE: opcode-name sequence equals OTP's beam_disasm listing" {
    var mod = try parse(std.testing.allocator, fixture);
    defer mod.deinit();
    const oracle = @embedFile("opnames.txt");

    // flatten our parsed names, skipping structure lines and pseudo-ops the
    // disassembler folds away (label / line / int_code_end)
    var ours: std.ArrayList([]const u8) = .empty;
    defer ours.deinit(std.testing.allocator);
    for (mod.code) |op| {
        const n = opName(op.opcode);
        if (std.mem.eql(u8, n, "label") or std.mem.eql(u8, n, "line") or
            std.mem.eql(u8, n, "int_code_end")) continue;
        try ours.append(std.testing.allocator, n);
    }
    var idx: usize = 0;
    var it = std.mem.tokenizeScalar(u8, oracle, '\n');
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "FUNCTION")) continue;
        if (std.mem.startsWith(u8, line, "{label")) continue;
        var name = line;
        // beam_disasm name forms: is_nonempty_list, {gc_bif,'+'} → gc_bif2
        if (std.mem.startsWith(u8, line, "{gc_bif")) name = "gc_bif2";
        if (std.mem.eql(u8, line, "label")) continue;
        try std.testing.expect(idx < ours.items.len);
        // disasm names test ops by their test name; ours match exactly
        try std.testing.expect(std.mem.eql(u8, ours.items[idx], name));
        idx += 1;
    }
    try std.testing.expectEqual(ours.items.len, idx); // exact coverage
}

test "NEGATE law: n + (-n) == 0 over generated numbers" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    var prng = std.Random.DefaultPrng.init(0x9E6A);

    for (0..100) |_| {
        const n = try ta.genNumberMixed(FinalTerms, prng.random(), &ctx);
        const neg = try FinalTerms.negate(&ctx, n);
        const sum = FinalTerms.add(&ctx, n, neg) catch unreachable;
        const v = try FinalTerms.denote(&ctx, sa, sum);
        switch (v.*) {
            .int => |b| try std.testing.expect(b.orderAgainstScalar(0) == .eq),
            .float => |f| try std.testing.expect(f == 0),
            else => unreachable,
        }
    }
}

/// Build an Erlang integer list term on a machine heap.
fn buildList(m: *ia.Machine, xs: []const i64) !FinalTerms.Term {
    var acc = FinalTerms.nil(&m.ctx);
    var k = xs.len;
    while (k > 0) {
        k -= 1;
        acc = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, xs[k]), acc);
    }
    return acc;
}

fn callEntry(m: *ia.Machine, prog: ia.Program, pc: u32, arg0: FinalTerms.Term) !void {
    m.status = .running;
    m.pc = pc;
    m.regs[0] = arg0;
    m.stack.clearRetainingCapacity();
    m.ystack.clearRetainingCapacity();
    // drive in small slices: REAL compiled code under preemption.
    // Bounded so a broken translation FAILS instead of hanging.
    var slices: usize = 0;
    while (m.status == .running) : (slices += 1) {
        if (slices > 100_000) return error.GateDidNotTerminate;
        try ia.run(m, prog, 13);
    }
}

test "LAW gap-reduction-size-weight: bifSizeClassOf maps each heavy list BIF to the arg it SCANS (DIVERGENCE 603)" {
    // reverse(List,Tail) scans x0; member(Elem,List) scans x1; keyfind/keymember/
    // keysearch(Key,N,TupleList) scan x2 — the size-weight must read the RIGHT arg,
    // or the reduction charge is off (a soft-real-time fidelity bug). A non-heavy BIF
    // stays .none. Kills a mutant that classifies member as list0 (wrong arg).
    try std.testing.expectEqual(ia.BifSizeClass.list0_elems, bifSizeClassOf("lists", "reverse", 2));
    try std.testing.expectEqual(ia.BifSizeClass.list1_elems, bifSizeClassOf("lists", "member", 2));
    try std.testing.expectEqual(ia.BifSizeClass.list2_elems, bifSizeClassOf("lists", "keyfind", 3));
    try std.testing.expectEqual(ia.BifSizeClass.list2_elems, bifSizeClassOf("lists", "keymember", 3));
    try std.testing.expectEqual(ia.BifSizeClass.list2_elems, bifSizeClassOf("lists", "keysearch", 3));
    // gap-reduction-bytes-weight (DIVERGENCE 604): the binary BIFs.
    try std.testing.expectEqual(ia.BifSizeClass.bytes0_elems, bifSizeClassOf("erlang", "binary_to_list", 1));
    try std.testing.expectEqual(ia.BifSizeClass.list0_elems, bifSizeClassOf("erlang", "list_to_binary", 1));
    // arity/module discrimination + the non-heavy default.
    try std.testing.expectEqual(ia.BifSizeClass.none, bifSizeClassOf("lists", "member", 3)); // wrong arity
    try std.testing.expectEqual(ia.BifSizeClass.none, bifSizeClassOf("erlang", "binary_to_list", 3)); // /3 has an opts range, not sized here
    try std.testing.expectEqual(ia.BifSizeClass.none, bifSizeClassOf("erlang", "self", 0));
    try std.testing.expectEqual(ia.BifSizeClass.none, bifSizeClassOf("ets", "member", 2)); // ets, not lists
}

test "LAW CAST-23 loader entries[].name stable: entryOf resolves AFTER the source Module is deinit'd (DIVERGENCE 599 — constructive determinism, name in the global atom table not the module)" {
    // Before the fix, link copied Entry.name = the per-module `mod.atomName` slice
    // (into the Module/beam). This law FREES the source module after link, then
    // resolves entryOf — which reads entries[].name. If the name still pointed into
    // the freed module, this is a use-after-free (caught by testing.allocator / a
    // wrong result); with the fix it points into the run-lifetime global atom table.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var mod = try parse(gpa, fixture);
    const t = try translate(gpa, &mod, &atoms, null);
    var units = [_]LinkUnit{.{ .mod = &mod, .t = t }};
    var linked = try link(gpa, &atoms, units[0..]); // consumes t (its sub-slices move into linked.prog)
    defer linked.deinit(gpa);
    // The source module (and its atom table) are now GONE.
    mod.deinit();
    const lt = Translated{ .prog = linked.prog, .label_pc = &.{}, .entries = linked.entries, .locs = linked.locs };
    // entryOf must STILL resolve every export — no dangle, deterministic.
    try std.testing.expect(entryOf(&lt, "len", 1) != null);
    try std.testing.expect(entryOf(&lt, "sum", 1) != null);
    try std.testing.expect(entryOf(&lt, "seq", 1) != null);
    try std.testing.expect(entryOf(&lt, "nosuch", 1) == null); // a genuine miss stays a miss
}

test "G2 GATE: real erlc output loads, translates, and runs correctly" {
    const gpa = std.testing.allocator;
    var mod = try parse(gpa, fixture);
    defer mod.deinit();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var t = try translate(gpa, &mod, &atoms, null);
    defer {
        gpa.free(t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    // expected results computed by the REAL node (fixtures/expected.txt):
    // sum([1..5]) = 15, len([9,9,9,9]) = 4, rev([1,2,3]) = [3,2,1],
    // seq(5) = [5,4,3,2,1], sum(seq(20)) = 210.

    // sum/1
    try callEntry(&m, t.prog, entryOf(&t, "sum", 1).?, try buildList(&m, &.{ 1, 2, 3, 4, 5 }));
    try std.testing.expectEqual(ia.Status.halted, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.int(&m.ctx, 15)));

    // len/1
    try callEntry(&m, t.prog, entryOf(&t, "len", 1).?, try buildList(&m, &.{ 9, 9, 9, 9 }));
    try std.testing.expectEqual(ia.Status.halted, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.int(&m.ctx, 4)));

    // rev/1
    try callEntry(&m, t.prog, entryOf(&t, "rev", 1).?, try buildList(&m, &.{ 1, 2, 3 }));
    try std.testing.expectEqual(ia.Status.halted, m.status);
    const want_rev = try buildList(&m, &.{ 3, 2, 1 });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, want_rev));

    // seq/1
    try callEntry(&m, t.prog, entryOf(&t, "seq", 1).?, FinalTerms.int(&m.ctx, 5));
    try std.testing.expectEqual(ia.Status.halted, m.status);
    const want_seq = try buildList(&m, &.{ 5, 4, 3, 2, 1 });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, want_seq));

    // sum(seq(20)) — chained through the heap, exactly like the node did it
    try callEntry(&m, t.prog, entryOf(&t, "seq", 1).?, FinalTerms.int(&m.ctx, 20));
    try std.testing.expectEqual(ia.Status.halted, m.status);
    const twenty = m.result;
    try callEntry(&m, t.prog, entryOf(&t, "sum", 1).?, twenty);
    try std.testing.expectEqual(ia.Status.halted, m.status);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.int(&m.ctx, 210)));

    // function_clause: sum(not_a_list) crashes exactly like the real VM
    try callEntry(&m, t.prog, entryOf(&t, "sum", 1).?, FinalTerms.atom(&m.ctx, try atoms.intern("oops")));
    try std.testing.expectEqual(ia.Status.crashed, m.status);
    const fc = FinalTerms.atom(&m.ctx, try atoms.intern("function_clause"));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, fc));
    _ = sa;
}

// ---------------------------------------------------------------------------
// W-17 LitT literal-operand law. Real stdlib modules carry compile-time
// constants as `.lit` operands (an index into the LitT chunk). The chunk is a
// `u32be uncompressed-size` + (when > 0) a zlib blob of `u32be count` then, per
// literal, a `u32be byte-size` and that many external-format bytes. Per the pin
// each literal carries its `131` version byte in both framings; the decoder's
// per-literal peek also TOLERATES a version-less literal, so this law
// deliberately exercises that defensive path with a version-less `[1,2,3]` (the
// `parse decodes an uncompressed, version-prefixed LitT literal` law below
// covers the pin's actual `131`-prefixed form). `parse` decodes into
// `Module.literals` (reusing etf.zig's zlib + term decoder), `srcOf` resolves a
// `.lit N` operand to `Src.literal(N)`, and `materializeLiterals` decodes the
// term into the executing machine's heap so `resolve` reads it like any other
// source.
// ---------------------------------------------------------------------------

/// A single stored-block zlib stream wrapping `data` — a compressor-free way for
/// the test to emit a byte-exact zlib blob the SAME inflater the loader uses
/// accepts (RFC-1950 header + one BFINAL stored deflate block + Adler-32).
fn zlibStore(gpa: std.mem.Allocator, data: []const u8) !std.ArrayList(u8) {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, &.{ 0x78, 0x01 }); // zlib header (0x7801 % 31 == 0)
    try out.append(gpa, 0x01); // deflate stored block: BFINAL=1, BTYPE=00
    const len: u16 = @intCast(data.len);
    try out.append(gpa, @truncate(len));
    try out.append(gpa, @truncate(len >> 8));
    const nlen = ~len;
    try out.append(gpa, @truncate(nlen));
    try out.append(gpa, @truncate(nlen >> 8));
    try out.appendSlice(gpa, data);
    const adler = std.hash.Adler32.hash(data); // big-endian footer (RFC 1950)
    try out.append(gpa, @truncate(adler >> 24));
    try out.append(gpa, @truncate(adler >> 16));
    try out.append(gpa, @truncate(adler >> 8));
    try out.append(gpa, @truncate(adler));
    return out;
}

fn be32(o: *std.ArrayList(u8), g: std.mem.Allocator, v: u32) !void {
    try o.append(g, @truncate(v >> 24));
    try o.append(g, @truncate(v >> 16));
    try o.append(g, @truncate(v >> 8));
    try o.append(g, @truncate(v));
}

/// Assemble a minimal FOR1/BEAM image with an AtU8 chunk, a Code chunk carrying
/// `code_bytes` (a compact op stream), and a LitT chunk holding `literals` (each
/// a version-less ETF term). `nlabels` sizes the Code header.
fn buildLitTBeam(
    gpa: std.mem.Allocator,
    code_bytes: []const u8,
    nlabels: u32,
    literals: []const []const u8,
    compress: bool,
) !std.ArrayList(u8) {
    var atu8: std.ArrayList(u8) = .empty; // one dummy atom, legacy form
    defer atu8.deinit(gpa);
    try atu8.appendSlice(gpa, &.{ 0, 0, 0, 1 });
    try atu8.append(gpa, 1);
    try atu8.append(gpa, 'm');

    var code: std.ArrayList(u8) = .empty; // 20-byte header + op stream
    defer code.deinit(gpa);
    const hdr = [_]u32{ 16, 0, 0, nlabels, 0 };
    for (hdr) |h| try be32(&code, gpa, h);
    try code.appendSlice(gpa, code_bytes);

    var blob: std.ArrayList(u8) = .empty; // u32be count + (u32be size, bytes)*
    defer blob.deinit(gpa);
    try be32(&blob, gpa, @intCast(literals.len));
    for (literals) |lit| {
        try be32(&blob, gpa, @intCast(lit.len));
        try blob.appendSlice(gpa, lit);
    }
    var litt: std.ArrayList(u8) = .empty;
    defer litt.deinit(gpa);
    if (compress) {
        // classic: u32be uncompressed-size + a zlib blob of the table
        var z = try zlibStore(gpa, blob.items);
        defer z.deinit(gpa);
        try be32(&litt, gpa, @intCast(blob.items.len));
        try litt.appendSlice(gpa, z.items);
    } else {
        // modern: u32be uncompressed-size == 0 sentinel + the table verbatim
        try be32(&litt, gpa, 0);
        try litt.appendSlice(gpa, blob.items);
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const appendChunk = struct {
        fn f(o: *std.ArrayList(u8), g: std.mem.Allocator, tag: []const u8, body: []const u8) !void {
            try o.appendSlice(g, tag);
            try be32(o, g, @intCast(body.len));
            try o.appendSlice(g, body);
            while ((o.items.len % 4) != 0) try o.append(g, 0);
        }
    }.f;
    try out.appendSlice(gpa, "FOR1");
    try out.appendSlice(gpa, &.{ 0, 0, 0, 0 });
    try out.appendSlice(gpa, "BEAM");
    try appendChunk(&out, gpa, "AtU8", atu8.items);
    try appendChunk(&out, gpa, "Code", code.items);
    try appendChunk(&out, gpa, "LitT", litt.items);
    return out;
}

test "translate resolves a .lit operand to its LitT term" {
    const gpa = std.testing.allocator;

    // The literal [1,2,3] as a VERSION-LESS external term: LIST_EXT(108),
    // u32 len=3, three SMALL_INTEGER_EXT(97,v), NIL_EXT(106) tail.
    const lit_123 = [_]u8{ 108, 0, 0, 0, 3, 97, 1, 97, 2, 97, 3, 106 };

    var stream = try emit(gpa, &.{
        .{ .opcode = opcodeByName("move"), .args = &.{ Operand{ .lit = 0 }, Operand{ .x = 0 } } },
        .{ .opcode = opcodeByName("int_code_end"), .args = &.{} },
    });
    defer stream.deinit(gpa);

    var beam = try buildLitTBeam(gpa, stream.items, 0, &.{&lit_123}, true);
    defer beam.deinit(gpa);

    var mod = try parse(gpa, beam.items);
    defer mod.deinit();
    try std.testing.expectEqual(@as(usize, 1), mod.literals.len);

    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const t = try translate(gpa, &mod, &atoms, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }

    // The move's src decoded to LitT slot 0 — NOT rejected as BadOperand.
    try std.testing.expect(t.prog[0] == .move2);
    try std.testing.expect(t.prog[0].move2.src == .literal);
    try std.testing.expectEqual(@as(u32, 0), t.prog[0].move2.src.literal);

    // Materialized into a machine heap, the literal resolves to [1,2,3].
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    m.literals = try materializeLiterals(gpa, &m.ctx, &mod);
    defer gpa.free(m.literals);

    const got = m.resolve(.{ .literal = 0 });
    const want = try buildList(&m, &.{ 1, 2, 3 });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got, want));
}

test "parse decodes an uncompressed, version-prefixed LitT literal (the modern erlc form)" {
    const gpa = std.testing.allocator;

    // Modern erlc writes LitT with uncompressed-size == 0 and each literal as a
    // FULL external term carrying its 131 version byte. Two literals: the atom
    // `ok` (131, ATOM_UTF8(118), u16 len=2, "ok") and the tuple `{}` (131,
    // SMALL_TUPLE(104), arity 0).
    const lit_ok = [_]u8{ 131, 118, 0, 2, 'o', 'k' };
    const lit_empty_tuple = [_]u8{ 131, 104, 0 };

    var stream = try emit(gpa, &.{
        .{ .opcode = opcodeByName("move"), .args = &.{ Operand{ .lit = 0 }, Operand{ .x = 0 } } },
        .{ .opcode = opcodeByName("move"), .args = &.{ Operand{ .lit = 1 }, Operand{ .x = 1 } } },
        .{ .opcode = opcodeByName("int_code_end"), .args = &.{} },
    });
    defer stream.deinit(gpa);

    var beam = try buildLitTBeam(gpa, stream.items, 0, &.{ &lit_ok, &lit_empty_tuple }, false);
    defer beam.deinit(gpa);

    var mod = try parse(gpa, beam.items);
    defer mod.deinit();
    try std.testing.expectEqual(@as(usize, 2), mod.literals.len);

    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const t = try translate(gpa, &mod, &atoms, null);
    defer {
        freeProg(gpa, t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0].move2.src == .literal and t.prog[0].move2.src.literal == 0);
    try std.testing.expect(t.prog[1].move2.src == .literal and t.prog[1].move2.src.literal == 1);

    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    m.literals = try materializeLiterals(gpa, &m.ctx, &mod);
    defer gpa.free(m.literals);

    // literal 0 == the atom `ok`
    const want_ok = FinalTerms.atom(&m.ctx, try atoms.intern("ok"));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.resolve(.{ .literal = 0 }), want_ok));
    // literal 1 == the empty tuple {}
    const want_empty = try FinalTerms.tuple(&m.ctx, &.{});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.resolve(.{ .literal = 1 }), want_empty));
}

// ============================================================================
// E3.3: bit-syntax matching operand-decode laws (emit∘parse identity)
// ============================================================================

// vm-binmatch-gc REGRESSION LAW (DIVERGENCE 57/68): bs_start_match3's genop
// @spec is `Fail Bin Live Dst` — Bin is arg[1], Live arg[2]. The old E3.3
// code (and its test) enshrined the WRONG `Fail Live Bin Dst` order (reading
// Src from arg[2]=Live), so a real receive-bound `<<X:8>>=B` match jumped its
// Fail label. Operand order confirmed against an erlc `spawn`+`receive` beam
// loaded through THIS loader: raw args `[f(7), x(0)=Bin, u(1)=Live, x(1)=Dst]`.
// MUTANT vm-binmatch-gc m1: reading Src from arg[2] here reddens this law.
test "LAW vm-binmatch-gc translate decodes bs_start_match3 (Fail,Bin,Live,Dst) — Src is arg[1] (Bin), NOT arg[2] (Live)" {
    const gpa = std.testing.allocator;
    // bs_start_match3 f:1 x:0(Bin) u:0(Live, dropped) x:1(Dst) → src=x0,
    // ctx=x1, else_to=pc(label1)=1.
    const ins = try translateSingle(gpa, "bs_start_match3", &.{
        Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .u = 0 }, Operand{ .x = 1 },
    });
    try std.testing.expect(ins == .bs_start_match);
    try std.testing.expect(ins.bs_start_match.src == .x and ins.bs_start_match.src.x == 0);
    try std.testing.expect(ins.bs_start_match.ctx == .x and ins.bs_start_match.ctx.x == 1);
    try std.testing.expectEqual(@as(u16, 1), ins.bs_start_match.else_to.?);
}

// The COMPANION law pinning bs_start_match4's DIFFERENT order `Fail Live Src
// Dst` (Src is arg[2]) — so the two arms are never wrongly "unified" again.
// Here Bin is arg[2]=x0 and Live is arg[1]=u0; a shared decoder that read
// arg[1] for BOTH ops (the mirror mistake) would misread Live(0) as Src.
test "LAW vm-binmatch-gc translate decodes bs_start_match4 (Fail,Live,Src,Dst) — Src is arg[2], distinct from match3" {
    const gpa = std.testing.allocator;
    const ins = try translateSingle(gpa, "bs_start_match4", &.{
        Operand{ .f = 0 }, Operand{ .u = 0 }, Operand{ .x = 0 }, Operand{ .x = 1 },
    });
    try std.testing.expect(ins == .bs_start_match);
    try std.testing.expect(ins.bs_start_match.src == .x and ins.bs_start_match.src.x == 0);
    try std.testing.expect(ins.bs_start_match.ctx == .x and ins.bs_start_match.ctx.x == 1);
}

test "LAW E3.3 translate decodes bs_get_integer2 (Fail,Ms,Live,Sz,Unit,Flags,Dst) with signed+little flags" {
    const gpa = std.testing.allocator;
    // bs_get_integer2 f:1 x:0 u:0 u:16 u:1 u:6(little|signed) x:2
    const ins = try translateSingle(gpa, "bs_get_integer2", &.{
        Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .u = 0 },
        Operand{ .u = 16 }, Operand{ .u = 1 }, Operand{ .u = 6 }, Operand{ .x = 2 },
    });
    try std.testing.expect(ins == .bs_get_integer);
    const g = ins.bs_get_integer;
    try std.testing.expect(g.ctx == .x and g.ctx.x == 0);
    try std.testing.expect(g.size == .imm and g.size.imm == 16);
    try std.testing.expectEqual(@as(u8, 1), g.unit);
    try std.testing.expect(g.signed);
    try std.testing.expectEqual(ia.BsEndian.little, g.endian);
    try std.testing.expect(g.dst == .x and g.dst.x == 2);
    try std.testing.expectEqual(@as(u16, 1), g.else_to);
}

test "LAW E3.3 translate decodes bs_test_tail2 (Fail,Ms,Bits) with Bits a compile-time .u constant" {
    const gpa = std.testing.allocator;
    const ins = try translateSingle(gpa, "bs_test_tail2", &.{
        Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .u = 8 },
    });
    try std.testing.expect(ins == .bs_test_tail);
    try std.testing.expect(ins.bs_test_tail.ctx == .x and ins.bs_test_tail.ctx.x == 0);
    try std.testing.expectEqual(@as(u32, 8), ins.bs_test_tail.bits);
    try std.testing.expectEqual(@as(u16, 1), ins.bs_test_tail.else_to);
}

test "LAW E3.4 translate decodes bs_init_writable/0 (genuinely ZERO on-disk operands, hardcoded x0 dst)" {
    const gpa = std.testing.allocator;
    const ins = try translateSingle(gpa, "bs_init_writable", &.{});
    try std.testing.expect(ins == .bs_init_writable);
    try std.testing.expect(ins.bs_init_writable.dst == .x and ins.bs_init_writable.dst.x == 0);
}

test "LAW E3.4 translate decodes bs_get_utf16/bs_skip_utf32 (Fail,Ctx,Live,Flags[,Dst]) via the CLASSIC .u BSF_LITTLE bitmask" {
    const gpa = std.testing.allocator;
    // bs_get_utf16 f:1 x:0 u:0 u:2(little) x:1 — CONFIRMED against a freshly
    // erlc-compiled fixture (see the E3.4 report): Flags is the SAME `.u`
    // bitmask `bs_get_integer2` uses, not `bs_create_bin`'s literal-list.
    const g = try translateSingle(gpa, "bs_get_utf16", &.{
        Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .u = 0 }, Operand{ .u = 2 }, Operand{ .x = 1 },
    });
    try std.testing.expect(g == .bs_get_utf);
    try std.testing.expectEqual(ia.UtfKind.utf16, g.bs_get_utf.kind);
    try std.testing.expectEqual(ia.BsEndian.little, g.bs_get_utf.endian);
    try std.testing.expect(g.bs_get_utf.ctx == .x and g.bs_get_utf.ctx.x == 0);
    try std.testing.expect(g.bs_get_utf.dst == .x and g.bs_get_utf.dst.x == 1);
    try std.testing.expectEqual(@as(u16, 1), g.bs_get_utf.else_to);

    // bs_skip_utf32 f:1 x:0 u:0 u:0(big) — NO Dst operand (arity 4).
    const s = try translateSingle(gpa, "bs_skip_utf32", &.{
        Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .u = 0 }, Operand{ .u = 0 },
    });
    try std.testing.expect(s == .bs_skip_utf);
    try std.testing.expectEqual(ia.UtfKind.utf32, s.bs_skip_utf.kind);
    try std.testing.expectEqual(ia.BsEndian.big, s.bs_skip_utf.endian);
    try std.testing.expectEqual(@as(u16, 1), s.bs_skip_utf.else_to);
}

test "LAW E3.4 translate decodes bs_create_bin/6's segment-list grammar (integer/binary_all/float/utf8/utf16-little-via-literal/string), CONFIRMED against an erlc fixture shape" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();

    // atom table: [0]="" [1]="integer" [2]="binary" [3]="all" [4]="float"
    // [5]="utf8" [6]="utf16" [7]="string" [8]="m"
    const atoms_arr = try a.alloc([]const u8, 9);
    atoms_arr[0] = "";
    atoms_arr[1] = "integer";
    atoms_arr[2] = "binary";
    atoms_arr[3] = "all";
    atoms_arr[4] = "float";
    atoms_arr[5] = "utf8";
    atoms_arr[6] = "utf16";
    atoms_arr[7] = "string";
    atoms_arr[8] = "m";

    // LitT slot 0: a proper list `[little]`, external-term-format encoded —
    // the on-disk shape `bs_create_bin`'s Flags takes for a non-nil flag set
    // (see `bsFieldFlagsOf`'s doc comment).
    var scratch_atoms = AtomTable.init(gpa);
    defer scratch_atoms.deinit();
    var scratch_ctx = FinalTerms.Ctx.init(gpa, &scratch_atoms);
    defer scratch_ctx.deinit();
    const little_ai = try scratch_atoms.intern("little");
    const little_list = try FinalTerms.cons(&scratch_ctx, FinalTerms.atomTerm(little_ai), FinalTerms.nil(&scratch_ctx));
    var enc = try etf.encode(gpa, &scratch_ctx, little_list);
    defer enc.deinit(gpa);
    const literals_arr = try a.alloc([]const u8, 1);
    literals_arr[0] = try a.dupe(u8, enc.items);

    const strtab = "..XY"; // the 'string' segment's bytes live at offset 2, length 2

    const seg_list = try a.alloc(Operand, 5 * 6);
    var k: usize = 0;
    // {integer, Seg=1, Unit=1, Flags=nil, Val=x0, Size=16}
    seg_list[k] = .{ .atom = 1 };
    k += 1;
    seg_list[k] = .{ .u = 1 };
    k += 1;
    seg_list[k] = .{ .u = 1 };
    k += 1;
    seg_list[k] = .{ .atom = 0 };
    k += 1;
    seg_list[k] = .{ .x = 0 };
    k += 1;
    seg_list[k] = .{ .i = 16 };
    k += 1;
    // {binary, Seg=2, Unit=8, Flags=nil, Val=x1, Size=all}
    seg_list[k] = .{ .atom = 2 };
    k += 1;
    seg_list[k] = .{ .u = 2 };
    k += 1;
    seg_list[k] = .{ .u = 8 };
    k += 1;
    seg_list[k] = .{ .atom = 0 };
    k += 1;
    seg_list[k] = .{ .x = 1 };
    k += 1;
    seg_list[k] = .{ .atom = 3 };
    k += 1;
    // {float, Seg=3, Unit=1, Flags=nil, Val=x2, Size=32}
    seg_list[k] = .{ .atom = 4 };
    k += 1;
    seg_list[k] = .{ .u = 3 };
    k += 1;
    seg_list[k] = .{ .u = 1 };
    k += 1;
    seg_list[k] = .{ .atom = 0 };
    k += 1;
    seg_list[k] = .{ .x = 2 };
    k += 1;
    seg_list[k] = .{ .i = 32 };
    k += 1;
    // {utf16, Seg=4, Unit=0, Flags=lit0([little]), Val=x3, Size=undefined(atom 0, ignored)}
    seg_list[k] = .{ .atom = 6 };
    k += 1;
    seg_list[k] = .{ .u = 4 };
    k += 1;
    seg_list[k] = .{ .u = 0 };
    k += 1;
    seg_list[k] = .{ .lit = 0 };
    k += 1;
    seg_list[k] = .{ .x = 3 };
    k += 1;
    seg_list[k] = .{ .atom = 0 };
    k += 1;
    // {string, Seg=0, Unit=8, Flags=nil, Val=Offset(2), Size=Len(2 bytes, .i)}
    seg_list[k] = .{ .atom = 7 };
    k += 1;
    seg_list[k] = .{ .u = 0 };
    k += 1;
    seg_list[k] = .{ .u = 8 };
    k += 1;
    seg_list[k] = .{ .atom = 0 };
    k += 1;
    seg_list[k] = .{ .u = 2 };
    k += 1;
    seg_list[k] = .{ .i = 2 };
    k += 1;
    try std.testing.expectEqual(seg_list.len, k);

    const code_arr = try a.alloc(Op, 2);
    code_arr[0] = .{ .opcode = opcodeByName("bs_create_bin"), .args = &.{
        Operand{ .f = 0 }, Operand{ .u = 0 }, Operand{ .u = 4 }, Operand{ .u = 8 },
        Operand{ .x = 9 }, Operand{ .list = seg_list },
    } };
    code_arr[1] = .{ .opcode = opcodeByName("label"), .args = &.{Operand{ .u = 1 }} };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 1,
        .literals = literals_arr,
        .strtab = strtab,
    };
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog); // owns bs_create_bin.segs (+ its .string bytes)
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0] == .bs_create_bin);
    const c = t.prog[0].bs_create_bin;
    try std.testing.expect(c.dst == .x and c.dst.x == 9);
    try std.testing.expectEqual(@as(?u32, null), c.else_to); // {f,0}: body context
    try std.testing.expectEqual(@as(usize, 5), c.segs.len);

    try std.testing.expect(c.segs[0] == .integer);
    try std.testing.expect(c.segs[0].integer.src == .x and c.segs[0].integer.src.x == 0);
    try std.testing.expect(c.segs[0].integer.size == .imm and c.segs[0].integer.size.imm == 16);
    try std.testing.expectEqual(ia.BsEndian.big, c.segs[0].integer.endian);

    try std.testing.expect(c.segs[1] == .binary_all);
    try std.testing.expect(c.segs[1].binary_all.src == .x and c.segs[1].binary_all.src.x == 1);

    try std.testing.expect(c.segs[2] == .float);
    try std.testing.expect(c.segs[2].float.size == .imm and c.segs[2].float.size.imm == 32);

    try std.testing.expect(c.segs[3] == .utf16);
    try std.testing.expect(c.segs[3].utf16.src == .x and c.segs[3].utf16.src.x == 3);
    try std.testing.expectEqual(ia.BsEndian.little, c.segs[3].utf16.endian); // decoded from the LitT [little] literal

    try std.testing.expect(c.segs[4] == .string);
    try std.testing.expectEqualSlices(u8, "XY", c.segs[4].string.bytes);
}

test "LAW E3.3 translate decodes bs_match/3's {commands,Commands} sub-command list (ensure_at_least, integer, skip, get_tail, '=:=')" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();

    // atom table: [0]="" (unused), [1]="ensure_at_least", [2]="integer",
    // [3]="skip", [4]="get_tail", [5]="=:=", [6]="label"(unused name), [7]="m"
    const atoms_arr = try a.alloc([]const u8, 7);
    atoms_arr[0] = "";
    atoms_arr[1] = "ensure_at_least";
    atoms_arr[2] = "integer";
    atoms_arr[3] = "skip";
    atoms_arr[4] = "get_tail";
    atoms_arr[5] = "=:=";
    atoms_arr[6] = "m";

    const cmds_list = try a.alloc(Operand, 3 + 6 + 2 + 4 + 4);
    var k: usize = 0;
    // {ensure_at_least, 4, 8}
    cmds_list[k] = Operand{ .atom = 1 };
    k += 1;
    cmds_list[k] = Operand{ .u = 4 };
    k += 1;
    cmds_list[k] = Operand{ .u = 8 };
    k += 1;
    // {integer, Live=0, Flags=nil(big,unsigned), Size=8, Unit=1, Dst=x1} —
    // Flags is the OTP-25+ field_flags shape (nil atom idx 0), NOT a `.u`
    // bitmask (E3.3-fix — see `bsFieldFlagsOf`'s doc comment).
    cmds_list[k] = Operand{ .atom = 2 };
    k += 1;
    cmds_list[k] = Operand{ .u = 0 };
    k += 1;
    cmds_list[k] = Operand{ .atom = 0 };
    k += 1;
    cmds_list[k] = Operand{ .u = 8 };
    k += 1;
    cmds_list[k] = Operand{ .u = 1 };
    k += 1;
    cmds_list[k] = Operand{ .x = 1 };
    k += 1;
    // {skip, 8}
    cmds_list[k] = Operand{ .atom = 3 };
    k += 1;
    cmds_list[k] = Operand{ .u = 8 };
    k += 1;
    // {get_tail, Live=0, Unit=1, Dst=x2}
    cmds_list[k] = Operand{ .atom = 4 };
    k += 1;
    cmds_list[k] = Operand{ .u = 0 };
    k += 1;
    cmds_list[k] = Operand{ .u = 1 };
    k += 1;
    cmds_list[k] = Operand{ .x = 2 };
    k += 1;
    // {'=:=', Live=0, Size=8, Value=5}
    cmds_list[k] = Operand{ .atom = 5 };
    k += 1;
    cmds_list[k] = Operand{ .u = 0 };
    k += 1;
    cmds_list[k] = Operand{ .u = 8 };
    k += 1;
    cmds_list[k] = Operand{ .i = 5 };
    k += 1;
    try std.testing.expectEqual(cmds_list.len, k);

    const code_arr = try a.alloc(Op, 2);
    code_arr[0] = .{ .opcode = opcodeByName("bs_match"), .args = &.{
        Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .list = cmds_list },
    } };
    code_arr[1] = .{ .opcode = opcodeByName("label"), .args = &.{Operand{ .u = 1 }} };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 1,
    };
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog); // owns bs_match.cmds
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0] == .bs_match);
    const bm = t.prog[0].bs_match;
    try std.testing.expect(bm.ctx == .x and bm.ctx.x == 0);
    try std.testing.expectEqual(@as(u16, 1), bm.fail_to);
    try std.testing.expectEqual(@as(usize, 5), bm.cmds.len);
    try std.testing.expect(bm.cmds[0] == .ensure_at_least);
    try std.testing.expectEqual(@as(u32, 4), bm.cmds[0].ensure_at_least.stride);
    try std.testing.expectEqual(@as(u8, 8), bm.cmds[0].ensure_at_least.unit);
    try std.testing.expect(bm.cmds[1] == .integer);
    try std.testing.expect(!bm.cmds[1].integer.signed);
    try std.testing.expectEqual(ia.BsEndian.big, bm.cmds[1].integer.endian);
    try std.testing.expect(bm.cmds[1].integer.dst == .x and bm.cmds[1].integer.dst.x == 1);
    try std.testing.expect(bm.cmds[2] == .skip);
    try std.testing.expectEqual(@as(u32, 8), bm.cmds[2].skip.stride);
    try std.testing.expect(bm.cmds[3] == .get_tail);
    try std.testing.expect(bm.cmds[3].get_tail.dst == .x and bm.cmds[3].get_tail.dst.x == 2);
    try std.testing.expect(bm.cmds[4] == .eq);
    try std.testing.expectEqual(@as(u32, 8), bm.cmds[4].eq.size);
}

test "LAW E3.3 translate decodes bs_match_string, copying its literal pattern out of the module's StrT chunk" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();

    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "m";
    // StrT chunk bytes; the pattern "AB" lives at offset 3.
    const strtab = "xxxAB";
    const code_arr = try a.alloc(Op, 2);
    code_arr[0] = .{ .opcode = opcodeByName("bs_match_string"), .args = &.{
        Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .u = 16 }, Operand{ .u = 3 },
    } };
    code_arr[1] = .{ .opcode = opcodeByName("label"), .args = &.{Operand{ .u = 1 }} };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 1,
        .strtab = strtab,
    };
    const t = try translate(gpa, &mod, &atbl, null);
    defer {
        freeProg(gpa, t.prog); // owns bs_match_string.bytes
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    try std.testing.expect(t.prog[0] == .bs_match_string);
    const s = t.prog[0].bs_match_string;
    try std.testing.expect(s.ctx == .x and s.ctx.x == 0);
    try std.testing.expectEqual(@as(u32, 16), s.bit_len);
    try std.testing.expectEqualSlices(u8, "AB", s.bytes);
    try std.testing.expectEqual(@as(u16, 1), s.else_to);
}

test "LAW E3.3 translate rejects bs_match_string with an out-of-range StrT offset with error.BadOperand (no panic)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();
    const atoms_arr = try a.alloc([]const u8, 2);
    atoms_arr[0] = "";
    atoms_arr[1] = "m";
    const code_arr = try a.alloc(Op, 1);
    code_arr[0] = .{ .opcode = opcodeByName("bs_match_string"), .args = &.{
        Operand{ .f = 1 }, Operand{ .x = 0 }, Operand{ .u = 8 }, Operand{ .u = 99 },
    } };
    var mod: Module = .{
        .arena = arena,
        .atoms = atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = code_arr,
        .code_bytes = &.{},
        .labels = 0,
        .strtab = "",
    };
    try std.testing.expectError(error.BadOperand, translate(gpa, &mod, &atbl, null));
}


// ============================================================================
// E3.12b: static multi-module LINKING laws (the loading homomorphism +
// literal-pool relocation — the E3.12 "genuine blocker"). These build TWO
// synthetic modules by hand (so the law is hermetic — no @embedFile), link
// them, and pin BOTH the structural relocation (pc + literal indices) AND the
// end-to-end cross-module dispatch: `moda:goa/0` calls `modb:valb/0`, which
// returns ITS OWN literal (222), not the entry module's (111). A broken
// literal relocation would read `combined[0]==111`; a broken pc relocation
// would jump inside the WRONG module. The REAL-erlc end-to-end EQ is proven
// separately by the harness `--run-erl-corpus` cross-module case.
// ============================================================================

/// Test helper: a minimal hand-built `Module` for the linker laws — only the
/// fields `link`/`materializeLiterals` read (name atom at index 1; the LitT
/// literal bytes). All slices are gpa-owned; free via `freeTestMod`.
fn buildTestMod(gpa: std.mem.Allocator, name: []const u8, lit_val: u8) !Module {
    const atoms = try gpa.alloc([]const u8, 2);
    atoms[0] = "";
    atoms[1] = name;
    const lits = try gpa.alloc([]const u8, 1);
    const litbytes = try gpa.alloc(u8, 3);
    litbytes[0] = etf.VERSION_MAGIC; // 131
    litbytes[1] = 97; // SMALL_INTEGER_EXT
    litbytes[2] = lit_val;
    lits[0] = litbytes;
    return Module{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .atoms = atoms,
        .imports = &.{},
        .exports = &.{},
        .code = &.{},
        .code_bytes = &.{},
        .labels = 0,
        .literals = lits,
    };
}

fn freeTestMod(gpa: std.mem.Allocator, mod: *Module) void {
    gpa.free(mod.literals[0]);
    gpa.free(mod.literals);
    gpa.free(mod.atoms);
    mod.arena.deinit();
}

test "LAW E3.12b link: pc + literal-index relocation is a homomorphism; cross-module dispatch reads the callee's OWN literal" {
    const gpa = std.testing.allocator;
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();

    var moda = try buildTestMod(gpa, "moda", 111);
    defer freeTestMod(gpa, &moda);
    var modb = try buildTestMod(gpa, "modb", 222);
    defer freeTestMod(gpa, &modb);

    const modb_atom = try atbl.intern("modb");
    const valb_atom = try atbl.intern("valb");

    // Module A (entry): goa/0 = call modb:valb/0 (push return), then halt x0.
    const progA = try gpa.alloc(ia.CInstr, 2);
    progA[0] = .{ .call_ext_code = .{ .module = modb_atom, .func = valb_atom, .arity = 0, .push_ret = true } };
    progA[1] = .{ .halt = .{ .src = .{ .x = 0 } } };
    const entriesA = try gpa.alloc(Entry, 1);
    entriesA[0] = .{ .name = "goa", .arity = 0, .pc = 0 };
    const ta_ = Translated{ .prog = progA, .label_pc = try gpa.alloc(u32, 0), .entries = entriesA, .locs = try gpa.alloc(ia.Loc, 2) };

    // Module B (dep): valb/0 = move literal[0] -> x0; jump to local pc 2 (the
    // ret); ret. The jump exercises pc relocation; the move exercises literal-
    // index relocation (B's `.literal 0` must become combined index 1).
    const progB = try gpa.alloc(ia.CInstr, 3);
    progB[0] = .{ .move2 = .{ .src = .{ .literal = 0 }, .dst = .{ .x = 0 } } };
    progB[1] = .{ .jump = .{ .to = 2 } };
    progB[2] = .ret;
    const entriesB = try gpa.alloc(Entry, 1);
    entriesB[0] = .{ .name = "valb", .arity = 0, .pc = 0 };
    const locsB = try gpa.alloc(ia.Loc, 3);
    @memset(locsB, .{});
    const tb_ = Translated{ .prog = progB, .label_pc = try gpa.alloc(u32, 0), .entries = entriesB, .locs = locsB };

    var units = [_]LinkUnit{ .{ .mod = &moda, .t = ta_ }, .{ .mod = &modb, .t = tb_ } };
    var linked = try link(gpa, &atbl, &units);
    defer linked.deinit(gpa);

    // Structural: module B's code is appended at pc offset 2, literal offset 1.
    try std.testing.expectEqual(@as(u32, 0), linked.lit_offset[0]);
    try std.testing.expectEqual(@as(u32, 1), linked.lit_offset[1]);
    // literal-index relocation: B's `.literal 0` -> combined `.literal 1`.
    try std.testing.expectEqual(@as(u32, 1), linked.prog[2].move2.src.literal);
    // pc relocation: B's `jump to 2` -> global `jump to 4`.
    try std.testing.expectEqual(@as(u16, 4), linked.prog[3].jump.to);
    // export index: GLOBAL pcs (entry module first, dep offset applied).
    var found_goa: ?u32 = null;
    var found_valb: ?u32 = null;
    for (linked.exports) |e| {
        if (e.func == try atbl.intern("goa")) found_goa = e.pc;
        if (e.func == valb_atom) found_valb = e.pc;
    }
    try std.testing.expectEqual(@as(?u32, 0), found_goa);
    try std.testing.expectEqual(@as(?u32, 2), found_valb);

    // End-to-end: materialize the COMBINED literal pool [111, 222] into one ctx,
    // run goa/0, and assert x0 == 222 (B's own literal, via the cross-module
    // call + the relocated literal index) — NOT 111 (A's literal at index 0).
    var m = try ia.Machine.init(gpa, &atbl);
    defer m.deinit();
    const litA = try materializeLiterals(gpa, &m.ctx, &moda);
    defer gpa.free(litA);
    const litB = try materializeLiterals(gpa, &m.ctx, &modb);
    defer gpa.free(litB);
    const combined = try gpa.alloc(FinalTerms.Term, 2);
    defer gpa.free(combined);
    combined[0] = litA[0];
    combined[1] = litB[0];
    m.literals = combined;
    m.exports = linked.exports;
    m.locs = linked.locs;
    m.pc = 0;
    var guard: usize = 0;
    while (m.status == .running) : (guard += 1) {
        if (guard > 1000) return error.DidNotHalt;
        try ia.run(&m, linked.prog, 10);
    }
    try std.testing.expectEqual(FinalTerms.smallValOf(m.result), @as(i64, 222));
}

test "LAW E3.12b on_load: onLoadFun finds the attribute's {F,A}; resolveLocal lands past func_info" {
    const gpa = std.testing.allocator;
    var atbl = AtomTable.init(gpa);
    defer atbl.deinit();

    // Attr proplist [{on_load,[{init,0}]}] as version-ful ETF:
    //   131, LIST_EXT(108) len=1, {on_load,[{init,0}]}, NIL_EXT tail.
    // tuple2 = SMALL_TUPLE_EXT(104) 2, atom on_load, list [ {init,0} ].
    const attr = [_]u8{
        131, // VERSION_MAGIC
        108, 0, 0, 0, 1, // LIST_EXT, 1 element
        104, 2, // SMALL_TUPLE_EXT 2  -> {on_load, [...]}
        119, 7, 'o', 'n', '_', 'l', 'o', 'a', 'd', // SMALL_ATOM_UTF8_EXT
        108, 0, 0, 0, 1, // LIST_EXT 1 element
        104, 2, // SMALL_TUPLE_EXT 2  -> {init, 0}
        119, 4, 'i', 'n', 'i', 't', // atom init
        97, 0, // SMALL_INTEGER_EXT 0
        106, // NIL (inner list tail)
        106, // NIL (outer list tail)
    };
    var atoms_arr = [_][]const u8{ "", "m" };
    var mod = Module{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .atoms = &atoms_arr,
        .imports = &.{},
        .exports = &.{},
        .code = &.{},
        .code_bytes = &.{},
        .labels = 0,
        .attr_bytes = &attr,
    };
    defer mod.arena.deinit();

    var m = try ia.Machine.init(gpa, &atbl);
    defer m.deinit();
    const ol = (try onLoadFun(gpa, &m.ctx, &mod)) orelse return error.NoOnLoadFound;
    try std.testing.expectEqualStrings("init", atbl.nameOf(ol.f));
    try std.testing.expectEqual(@as(u32, 0), ol.arity);

    // resolveLocal: a two-instruction module `init/0` = func_info; move ok -> x0.
    const prog = [_]ia.CInstr{ .func_info, .{ .move2 = .{ .src = .nil, .dst = .{ .x = 0 } } } };
    const modatom = try atbl.intern("m");
    var locs = [_]ia.Loc{ .{ .m = modatom, .f = ol.f, .a = 0 }, .{ .m = modatom, .f = ol.f, .a = 0 } };
    const entry = resolveLocal(&prog, &locs, modatom, ol.f, 0) orelse return error.NotResolved;
    // The callable entry skips the leading func_info (pc 0) -> pc 1.
    try std.testing.expectEqual(@as(u32, 1), entry);
    // A missing function resolves to null (no false entry).
    try std.testing.expectEqual(@as(?u32, null), resolveLocal(&prog, &locs, modatom, try atbl.intern("nope"), 0));
}

test "LAW E8.4 CT large-module capacity: link supports >64k combined instructions without overflow" {
    var gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    const fake_prog = try gpa.alloc(ia.CInstr, 70000);
    errdefer gpa.free(fake_prog);
    for (fake_prog, 0..) |*ins, i| ins.* = .{ .jump = .{ .to = @intCast(i) } };
    
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var mod = Module{
        .arena = arena,
        .atoms = @constCast(&[_][]const u8{ "fake1", "mod1" }),
        .imports = @constCast(&[_][3]u32{}),
        .exports = @constCast(&[_][3]u32{}),
        .code = @constCast(&[_]Op{}),
        .code_bytes = "",
        .labels = 0,
    };
    const fake_locs = try gpa.alloc(ia.Loc, 70000); errdefer gpa.free(fake_locs); const tu = Translated{ .locs = fake_locs,
        .prog = fake_prog,
        .label_pc = @constCast(&[_]u32{}),
        .entries = @constCast(&[_]Entry{}),
    };
    var link_units = [_]LinkUnit{.{ .mod = &mod, .t = tu }};
    var linked = try link(gpa, &atoms, &link_units);
    defer linked.deinit(gpa);
    
    try std.testing.expectEqual(@as(usize, 70000), linked.prog.len);
    try std.testing.expectEqual(@as(u32, 69999), linked.prog[69999].jump.to);
}

// ── e21-t7: FUZZ target — malformed .beam module surface ───────────────────
// SEMANTIC DOMAIN: `parse` is a partial function `bytes ⇀ Module`. Its safety
// obligation mirrors the ETF decoder's: an adversarial or truncated IFF/BEAM
// container must yield a named error, never a crash/over-read/leak. LAW
// (rejection/totality-of-safety): ∀ b . parse(b) ∈ {Ok(Module)} ∪ error, and
// on the Ok branch `Module.deinit` balances every allocation.
fn fuzzLenPrefix(comptime raw: []const u8) []const u8 {
    const n: u32 = @intCast(raw.len);
    const pre = [_]u8{
        @intCast(n & 0xFF),        @intCast((n >> 8) & 0xFF),
        @intCast((n >> 16) & 0xFF), @intCast((n >> 24) & 0xFF),
    };
    return pre ++ raw;
}
fn fuzzBeamParse(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [1024]u8 = undefined;
    const n = smith.sliceWithHash(&buf, 0xB3A3_10AD);
    const gpa = std.testing.allocator;
    var mod = parse(gpa, buf[0..n]) catch return;
    mod.deinit();
}

test "FUZZ e21-t7: BEAM loader is safe/total on adversarial containers (corpus replay under gate)" {
    try std.testing.fuzz({}, fuzzBeamParse, .{ .corpus = &.{
        fuzzLenPrefix(&[_]u8{}), // empty
        fuzzLenPrefix("FOR1"), // truncated IFF header
        fuzzLenPrefix(&[_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 4, 'B', 'E', 'A', 'M' }), // header only
        fuzzLenPrefix(&[_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 12, 'B', 'E', 'A', 'M', 'A', 't', 'U', '8', 0, 0, 0, 0 }), // empty AtU8 chunk
        fuzzLenPrefix(&[_]u8{ 'X', 'X', 'X', 'X', 0, 0, 0, 0, 'B', 'E', 'A', 'M' }), // bad magic
    } });
}
