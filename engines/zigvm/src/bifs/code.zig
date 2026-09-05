//! # bifs/code — the code-index QUERY BIF family (E2.12)
//!
//! ## Signature
//! Same contract as every other family module: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term`. This family
//! wires the `erlang:` module-introspection BIFs to the Machine-owned
//! `code_index.CodeIndex` (M10 — the same `current`/`old` two-version model
//! `boot.zig` drives), added here as `Machine.code_index` (the SAME shape as
//! E2.9's `Machine.ets`/E2.10's `Machine.pterm`/`Machine.atomics`: an owned
//! registry, initialized empty, freed in `deinit`).
//!
//! ## Scope — query vs load (the split the task brief asks for)
//! Most of the pin's `bif.tab` code-loading surface is now LIVE here:
//! `check_old_code/1` + `delete_module/1` (E5.2b), `prepare_loading/2` +
//! `finish_loading/1` (e5-dispatch-codeidx), `purge_module/2` + the litarea pair
//! (E6.3), and the on_load STAGING trio `has_prepared_code_on_load/1` +
//! `call_on_load_function/1` + `finish_after_on_load/2` (E7.2, DIVERGENCE 147 —
//! driven end-to-end over an EMBEDDED on_load beam blob, the `onload_call` corpus
//! case). Only `load_nif/2` stays `deferred-nif` (real native dynamic code behind
//! the Stratum-C seam — the native-code epoch). See `harness/bif_gen.ml`'s
//! per-entry map for the precise classification.
//!
//! ## E4.2b: the ONE reachable code-loading-metadata BIF
//! `erts_internal:beamfile_chunk/2` (below) is the exception: it is PURE over a
//! RAW beam-binary ARGUMENT — it never touches the mutable code table — so a
//! compiled `.beam` can build a synthetic IFF container inline and observe the
//! extracted chunk end-to-end on both VMs (the synthetic-IFF corpus). Task 3's
//! full boot being infeasible (E4.3) does not block it. Its sibling
//! `beamfile_module_md5/1` is NOT reachable (it needs a WELL-FORMED whole beam,
//! not constructible inline) and stays `deferred-E4-loadbin`.
//!
//! `code:ensure_loaded/1`, `code:is_loaded/1`, `code:which/1`,
//! `code:get_object_code/1`, `code:all_loaded/0`, `code:module_md5/1`,
//! `code:make_stub_module/3` named in the task brief are NOT actually
//! `bif.tab` entries on this pin — they are `code.erl`/`code_server`
//! LIBRARY/gen_server functions built ATOP the real BIFs below (confirmed by
//! grepping the pinned `bif.tab`: the only `code:` rows are the unrelated
//! coverage/debug-info family — `code:coverage_support/0`,
//! `code:get_coverage/2`, etc. — out of scope for this slice, `justified:
//! deferred-E5`, the tooling epoch). The REAL, `bif.tab`-backed
//! module-introspection surface is three `erlang:` BIFs implemented here:
//!   `erlang:loaded/0`         every module name currently in `code_index`,
//!                    sorted (HashMap iteration order must never leak — the
//!                    same order-freedom discipline as `term_hash.zig`'s map
//!                    law), as a list of atoms.
//!   `erlang:module_loaded/1`  `code_index.slots.get(Name) != null`.
//!   `erlang:pre_loaded/0`     the constant `[]` — this VM does not bake in
//!                    erts's preloaded module set (`erlang`, `erts_internal`,
//!                    `init`, …); the boot path (`boot.zig`) loads its ONE
//!                    module directly into a CodeIndex, never through a
//!                    "preloaded" channel. Same shape as `procsys.zig`'s
//!                    `nodes/0`: a PROVABLY-empty constant over this VM's
//!                    current surface, not a shortcut (NOTE: `registered/0`
//!                    left this bucket at e4-registered0 — it is now
//!                    registry-backed, since `register/2` is no longer
//!                    `.stub`).
//!
//! ## Laws (see the suite below)
//!   - CODE QUERY: after `code_index.load(Name, Prog)`, `module_loaded(Name)
//!     == true` and `Name ∈ loaded()`; an unloaded name is `false` and
//!     absent from `loaded()`.
//!   - ORDER-FREEDOM: `loaded()` is sorted — independent of load order.
//!   - PRE_LOADED: always `[]`.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const loader = @import("../beam_loader.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

fn boolTerm(m: *Machine, cond: bool) Term {
    return FinalTerms.atom(&m.ctx, if (cond) m.bool_true else m.bool_false);
}

/// `erlang:loaded/0` — every currently-loaded module name, sorted.
pub fn loaded_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(m.gpa);
    var it = m.code_index.slots.keyIterator();
    while (it.next()) |k| names.append(m.gpa, k.*) catch return error.OutOfMemory;

    std.mem.sort([]const u8, names.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    var acc = FinalTerms.nil(&m.ctx);
    var i = names.items.len;
    while (i > 0) {
        i -= 1;
        const idx = m.ctx.atoms.intern(names.items[i]) catch return error.OutOfMemory;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, idx), acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// `erlang:module_loaded/1` — is `Mod` (an atom) in the code index?
pub fn module_loaded_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    return boolTerm(m, m.code_index.slots.get(name) != null);
}

/// `erlang:pre_loaded/0` — no preloaded module set is baked into this VM
/// (see module doc comment); always `[]`.
pub fn pre_loaded_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.nil(&m.ctx);
}

// ============================================================================
// E5.2b (Task 2 CONTINUATION, DIVERGENCE 61): the runtime two-version QUERY
// BIFs — `check_old_code/1` and `delete_module/1` — over the mutable code table
// (code_index.zig's E5.2b `checkOldCode`/`deleteModule`). Reachable end-to-end:
// `cli.runMulti` registers every linked module into `Machine.code_index`, so a
// compiled `.beam` observes and mutates the SAME table the oracle does. The
// staged prepare/finish/on_load half lives in `code_server.zig` (law-proven,
// BIF rows re-bound — no second-beam runtime term without the boot/file world).
// ============================================================================

/// `erlang:check_old_code(Module)` — is there a retired `old` version of the
/// module in the code table? `false` for an unloaded module (erts).
pub fn check_old_code_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    return boolTerm(m, m.code_index.checkOldCode(name));
}

/// `erlang:delete_module(Module)` — retire the module's current version to
/// `old` (external calls fail until reload). `true` on success, `undefined`
/// when the module is absent, and a `badarg` when there is no current version
/// to retire or an unpurged `old` (erts' "not purged" rule). Mirrors the host
/// exactly (verified: loaded->true, absent->undefined, twice->error:badarg).
pub fn delete_module_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    return switch (m.code_index.deleteModule(name)) {
        .deleted => FinalTerms.atom(&m.ctx, m.bool_true),
        .absent => FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("undefined") catch return error.OutOfMemory),
        .badarg => error.Badarg,
    };
}

// gap-hot-load-code-lib (DIVERGENCE 600): the `code:` LIBRARY hot-load surface,
// reachable from a COMPILED beam. code_index already has the oracle-pinned
// two-version library-purge methods (`purgeForce`/`softPurge`) + `deleteModule`,
// but they were HANDLER-PROVEN ONLY (code_server/code_index laws call them directly)
// — a compiled `code:purge/1` etc. resolved to NEITHER bif table → `undef`
// (FM-DISPATCH-DEAD). These BifFns operate on the SAME `m.code_index` runtime table
// a compiled beam observes, wired via resolveLibrary (module `code`).

/// `code:purge/1` — purge the module's OLD version, KILLING any process lingering
/// on it. `true` iff a process was killed (old code existed with a holder), else
/// `false` (no old code / no holder). Maps to `code_index.purgeForce`.
pub fn purge_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    return boolTerm(m, m.code_index.purgeForce(name));
}

/// `code:soft_purge/1` — purge OLD only if no process lingers on it. `true` (old
/// absent, or removed with no holder) / `false` (a process still runs old code,
/// old left in place). Maps to `code_index.softPurge`.
pub fn soft_purge_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    return boolTerm(m, m.code_index.softPurge(name));
}

/// `code:delete/1` — retire the module's CURRENT version to `old`. `true` iff
/// there WAS a current version to retire, else `false` (absent / unpurged old) —
/// the boolean `code.erl` wrapper over `delete_module` (which raises/returns tags).
pub fn delete_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    return boolTerm(m, m.code_index.deleteModule(name) == .deleted);
}

/// `code:modified_modules/0` — modules whose on-disk beam differs from the loaded
/// one. This closed-world VM never rewrites beams on disk → always `[]` (byte-EQ to
/// a freshly-booted OTP node with no recompilation).
pub fn modified_modules_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.nil(&m.ctx);
}

// ============================================================================
// E4.2b: `erts_internal:beamfile_chunk/2` — the ONE code-LOADING-metadata BIF
// reachable end-to-end this epoch (no booted code server, Task 3 infeasible).
//
// It is PURE over a RAW beam binary ARGUMENT — it never touches the mutable
// code table — so a compiled `.beam` can build a synthetic IFF container inline
// and observe the extracted chunk on BOTH VMs (differential corpus `bfc`/
// `bfc_absent`). Mirrors erts `beam_bif_load.c:erts_internal_beamfile_chunk_2`
// exactly: `read_iff_list` (a 4-byte-list tag) → `iff_init` (FOR1/BEAM header)
// → `iff_read_chunk` (chunk found with size>0 → its payload sub-binary, else
// `undefined`). The IFF-scan is the SAME container walk `beam_loader.parse`
// runs (S15), factored to the argument-binary case. `beamfile_module_md5/1`
// and the staged-load family stay deferred — they need a WELL-FORMED beam /
// the mutable code table a compiled `.beam` cannot reach here (bif_gen.ml).
// ============================================================================

/// `erts_internal:beamfile_chunk(Bin, ChunkName)` — the named IFF chunk's raw
/// payload bytes as a binary, or the atom `undefined` when `Bin` is not a
/// well-formed IFF/BEAM container or the chunk is absent/empty. Badargs ONLY on
/// a malformed chunk-name (not exactly a 4-byte list) or a non-binary `Bin`
/// (erts: `read_iff_list` false / `erts_get_aligned_binary_bytes` NULL).
pub fn beamfile_chunk_2(m: *Machine, args: []const Term) BifError!Term {
    // read_iff_list: EXACTLY a 4-element list of bytes → the 4-char chunk tag.
    var tag: [4]u8 = undefined;
    var cur = args[1];
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (FinalTerms.kindOf(&m.ctx, cur) != .cons) return error.Badarg;
        const h = FinalTerms.listHead(&m.ctx, cur);
        if (!FinalTerms.repIsSmall(h)) return error.Badarg;
        const v = FinalTerms.smallValOf(h);
        if (v < 0 or v > 255) return error.Badarg;
        tag[i] = @intCast(v);
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg; // trailing junk

    // erts_get_aligned_binary_bytes: Bin must be a (byte-aligned) binary.
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    const bytes = FinalTerms.binBytes(&m.ctx, args[0]);

    const undef = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("undefined") catch return error.OutOfMemory);

    // iff_init: a `FOR1`<u32 size>`BEAM` header. A short/non-IFF binary → the
    // chunk is simply not found (erts leaves `res = am_undefined`, no badarg).
    if (bytes.len < 12 or !std.mem.eql(u8, bytes[0..4], "FOR1") or !std.mem.eql(u8, bytes[8..12], "BEAM"))
        return undef;

    // E6.8 (DIVERGENCE 108 discharge): erts' `iff_init`/`scan_iff` reader is
    // STRICT over the FORM-SIZE field, not a lenient lazy walk. The `FOR1` u32
    // at bytes[4..8] is the FORM SIZE; the IFF body is EXACTLY `[12, 8+form_size)`
    // and the whole chunk list within it must be well-formed BEFORE any lookup:
    //   * `8 + form_size > bytes.len`      → the form claims bytes we don't have
    //                                        → `undefined` (empirically pinned on
    //                                        the OTP-28 host: fs=24/total28).
    //   * a chunk header/body overrunning `form_end`, or leftover bytes making the
    //     4-aligned walk NOT land exactly on `form_end` → the file is malformed
    //     → `undefined` — even if the REQUESTED chunk already appeared earlier
    //     (fs=20/total28 finds "Atom" yet erts still returns `undefined`), so the
    //     match is only honored after a FULL clean walk. Trailing bytes AFTER
    //     `form_end` are ignored (fs=16/total28 → the chunk IS returned). A real
    //     erlc beam has `8+form_size == byte_size` and lands exactly on form_end
    //     (verified over eunit_data.beam's full chunk list), so this tightening
    //     leaves every well-formed `.beam` unchanged — only malformed inputs, on
    //     which zigvm's old lenient walk DIVERGED, now match erts.
    const form_size = std.mem.readInt(u32, bytes[4..8], .big);
    const form_end: usize = 8 + @as(usize, form_size);
    if (form_end > bytes.len) return undef; // form claims more than present

    var matched: ?[]const u8 = null;
    var pos: usize = 12;
    while (pos < form_end) {
        if (pos + 8 > form_end) return undef; // truncated chunk header
        const name = bytes[pos .. pos + 4];
        const size = std.mem.readInt(u32, bytes[pos + 4 ..][0..4], .big);
        const data_start = pos + 8;
        const data_end = data_start + size;
        if (data_end > form_end) return undef; // chunk body overruns the form
        // erts: a matching chunk with `size > 0` is the result — but recorded,
        // not returned early: the remaining chunk list must still validate.
        if (matched == null and std.mem.eql(u8, name, &tag) and size > 0)
            matched = bytes[data_start..data_end];
        pos = data_start + ((size + 3) / 4) * 4; // 4-byte chunk alignment
    }
    if (pos != form_end) return undef; // misaligned / leftover bytes inside form
    if (matched) |slice|
        return FinalTerms.binary(&m.ctx, slice) catch return error.OutOfMemory;
    return undef;
}

// ============================================================================
// E5.2c (Task 2 RELOAD half, DIVERGENCE 75): `erts_internal:beamfile_module_md5/1`
// — the module MD5 of a WHOLE beam binary. Like `beamfile_chunk/2` it is PURE
// over a raw beam-binary ARGUMENT (it never touches the mutable code table), so
// a compiled `.beam` carrying a real beam image as a runtime BINARY (an embedded
// literal — the honest bif-surface source, no stdlib file I/O) observes it
// end-to-end on BOTH VMs. Mirrors erts `beam_bif_load.c:beamfile_module_md5_1`:
// a full `beamfile_read`/validate then the module checksum. The checksum itself
// is `beam_loader.computeMd5`, ALREADY loader-proven byte-EQ to erts (E4.2,
// `mi_md5` — `beamfile_module_md5(Bin) =:= Mod:module_info(md5)`, host-verified),
// and is VERSION-INDEPENDENT (a hash of the significant chunks, not the volatile
// compile/debug info — so the same bytes hash identically on OTP-28 and the pin).
// A binary that is not a well-formed / md5-bearing beam → the atom `undefined`
// (erts `beamfile_read` fail path), never a panic; a non-binary → badarg.
// ============================================================================

/// `erts_internal:beamfile_module_md5(Bin)` — the 16-byte module MD5 of the whole
/// beam `Bin`, or `undefined` when `Bin` is not a well-formed / md5-bearing beam.
/// Badarg ONLY on a non-binary argument (erts `erts_get_aligned_binary_bytes`
/// NULL). PURE: parses a throwaway `Module` (the S15 container walk) purely to
/// read its `computeMd5` value, then frees it — the code table is untouched.
pub fn beamfile_module_md5_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    const bytes = FinalTerms.binBytes(&m.ctx, args[0]);
    // A malformed / non-beam binary is NOT a badarg — erts leaves `res =
    // am_undefined` (the beamfile_read validate fail). `beamModuleMd5` is TOTAL
    // (bounds-checked) so a hostile binary can never fault the VM.
    const md5 = loader.beamModuleMd5(bytes) orelse
        return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("undefined") catch return error.OutOfMemory);
    return FinalTerms.binary(&m.ctx, &md5) catch return error.OutOfMemory;
}

// ============================================================================
// e5-dispatch-codeidx (Task 2 RELOAD half, DIVERGENCE 81): the runtime code
// SERVER's LOADING surface — `erts_internal:prepare_loading/2` +
// `erlang:finish_loading/1` — made reachable end-to-end now that `call_ext`
// dispatch consults the runtime code table (`Machine.resolveRuntime`).
//
// The host semantics (empirically verified on the OTP-28 oracle):
//   prepare_loading(Mod, Bin) -> a MAGIC-REF handle (an opaque reference) on a
//       valid beam whose module name matches `Mod`; `{error, badfile}` (a TERM,
//       never a raise) on a corrupt beam or a module-name mismatch.
//   finish_loading([Handle]) -> `ok` (a LIST of prepared handles; `[]` -> ok),
//       after which the modules are callable; a non-list, or a reused/unknown/
//       non-ref handle, is a `badarg`.
//
// The zigvm realization: `prepare_loading` translates the beam and SPLICES its
// (relocated) code into `Machine.dyn_code` immediately — an UNOBSERVABLE detail,
// since dispatch is gated on `dyn_exports`/`code_index`, which only
// `finish_loading` writes. `finish_loading` commits each staged module's
// exports into `dyn_exports` and registers it in `code_index` (so the QUERY
// BIFs + `resolveRuntime`'s currency gate see it). The beam-bytes source is an
// EMBEDDED BINARY (no stdlib file I/O / boot) — the honest bif-surface source
// the `reload_call` corpus case uses (a real `+deterministic` zmini blob).
// ============================================================================

/// The magic word tag distinguishing a prepared-loading handle from any other
/// reference (encoded into word[0] of the ref; word[1]/word[2] carry the id).
const PREP_MAGIC: u32 = 0x50524550; // "PREP"

fn errorBadfile(m: *Machine) BifError!Term {
    const err = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("error") catch return error.OutOfMemory);
    const badfile = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("badfile") catch return error.OutOfMemory);
    return FinalTerms.tuple(&m.ctx, &.{ err, badfile }) catch return error.OutOfMemory;
}

/// `erts_internal:prepare_loading(Module, Bin)` — validate + stage a beam.
pub fn prepare_loading_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg; // Module must be an atom
    if (!FinalTerms.repIsBinary(&m.ctx, args[1])) return error.Badarg; // erts: aligned-bin NULL
    const mod_atom = FinalTerms.atomIdxOf(args[0]);
    const src_bytes = FinalTerms.binBytes(&m.ctx, args[1]);
    const si = stageBeam(m, mod_atom, src_bytes) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Badfile => return errorBadfile(m),
    };
    const ref_id = m.staged.items[si].ref;
    // The magic handle: a reference carrying the staged id (word[0] = PREP magic).
    return FinalTerms.ref(&m.ctx, .{ PREP_MAGIC, @truncate(ref_id), @truncate(ref_id >> 32) }) catch return error.OutOfMemory;
}

/// The staging core shared by `prepare_loading_2` and `loadBeamBytes`
/// (gap-fs-autoloader): validate + translate + SPLICE a beam into `dyn_code`,
/// record its (uncommitted) staged entry. Returns the `m.staged` index.
fn stageBeam(m: *Machine, mod_atom: ta.AtomIdx, src_bytes: []const u8) error{ OutOfMemory, Badfile }!usize {
    // `parse` BORROWS its byte argument (the Module holds slices into it), so the
    // bytes must outlive the Module: dup them, free on exit (everything we KEEP —
    // relocated instrs, materialized literals, interned entry atoms — is copied
    // out of the Module before this returns).
    const bytes = m.gpa.dupe(u8, src_bytes) catch return error.OutOfMemory;
    defer m.gpa.free(bytes);

    var mod = loader.parse(m.gpa, bytes) catch return error.Badfile;
    defer mod.deinit();
    // Module-name match (erts: "module name in object code is X" -> {error,badfile}).
    const want = m.ctx.atoms.nameOf(mod_atom);
    const got = if (mod.atoms.len > 1) mod.atoms[1] else "";
    if (!std.mem.eql(u8, want, got)) return error.Badfile;

    const t = loader.translate(m.gpa, &mod, m.ctx.atoms, null) catch return error.Badfile;
    // From here we OWN `t`; free it (shallow prog array + label_pc + entries +
    // locs) once its instructions are moved into `dyn_code`. `defer` guards the
    // early-return (OOM/limit) paths; on the success path we free explicitly and
    // disarm by setting the slices empty.
    var freed = false;
    defer if (!freed) {
        m.gpa.free(t.prog);
        m.gpa.free(t.label_pc);
        m.gpa.free(t.entries);
        m.gpa.free(t.locs);
    };

    // The unified pc frame this module's code lands at (append-only). Every code
    // target (`Export.pc`, jump/branch `.to`/`.else_to`, `relocInstr`'s `pc_off`)
    // is `u32` and the interpreter's `pc` is `usize`, so the combined dynamic pc
    // space is u32-wide — the SAME space the static link already fills (the stock
    // stdlib preload alone occupies ~123k instruction slots). gap-autoload-u32
    // (DIVERGENCE 679): this cap was historically `maxInt(u16)`, a STALE beam
    // intra-module label limit that has nothing to do with the unified runtime pc;
    // it silently rejected EVERY autoload once the preload pushed `code_base` past
    // 65535, so `--code-path`/behaviour modules all failed `badfile`.
    const base_u: usize = m.code_base + m.dyn_code.items.len;
    if (base_u + t.prog.len > @as(usize, std.math.maxInt(u32)) + 1) return error.Badfile;
    const pc_off: u32 = @intCast(base_u);
    const lit_off: u32 = @intCast(m.literals.len + m.dyn_literals.items.len);

    // Materialize this module's literals into `ctx` and append to the unified
    // dynamic literal pool (relocated by `lit_off` in the instructions below).
    const lits = loader.materializeLiterals(m.gpa, &m.ctx, &mod) catch return error.OutOfMemory;
    defer m.gpa.free(lits);
    m.dyn_literals.appendSlice(m.gpa, lits) catch return error.OutOfMemory;

    // Splice: relocate + append every instruction into `dyn_code` (the operand
    // sub-slices are MOVED — shared with `t.prog`, which we free SHALLOW below, so
    // `dyn_code` becomes their owner, released by `Machine.deinit`'s `freeProg`).
    m.dyn_code.ensureUnusedCapacity(m.gpa, t.prog.len) catch return error.OutOfMemory;
    for (t.prog) |ins| {
        var copy = ins;
        loader.relocInstr(&copy, pc_off, lit_off);
        m.dyn_code.appendAssumeCapacity(copy);
    }

    // The module's exported entries, relocated to the unified pc space — staged,
    // committed into `dyn_exports` only by `finish_loading`.
    const entries = m.gpa.alloc(ia.Export, t.entries.len) catch return error.OutOfMemory;
    for (t.entries, 0..) |e, i| {
        const fidx = m.ctx.atoms.intern(e.name) catch return error.OutOfMemory;
        entries[i] = .{ .module = mod_atom, .func = fidx, .arity = e.arity, .pc = pc_off + e.pc };
    }

    // E7.2 (DIVERGENCE 147): resolve the module's `-on_load` function to a GLOBAL
    // (unified) pc, so `has_prepared_code_on_load/1` can report it and `call_on_
    // load_function/1` can run it. The compiler (beam_asm.erl `insert_on_load_
    // instruction`) DELETES on_load from the module attributes and inserts an
    // `on_load` OPCODE right after the on_load function's entry label — translated
    // to `.nop{.note=.on_load}` (beam_loader). So the on_load callable entry is the
    // pc of that transparent nop (the function body starts there); scanning the
    // just-translated code for it is exact. `null` when the module carries no
    // on_load (the load has no gate) — never a panic. Relocated by the SAME
    // `pc_off` the spliced code got.
    var on_load_pc: ?u32 = null;
    for (t.prog, 0..) |ins, i| {
        if (ins == .nop and ins.nop.note == .on_load) {
            on_load_pc = pc_off + @as(u32, @intCast(i));
            break;
        }
    }

    const ref_id = m.next_prepared;
    m.next_prepared += 1;
    m.staged.append(m.gpa, .{ .ref = ref_id, .module = mod_atom, .entries = entries, .on_load_pc = on_load_pc }) catch {
        m.gpa.free(entries);
        return error.OutOfMemory;
    };

    // Free the transient Translated SHALLOW (sub-slices now owned by `dyn_code`).
    m.gpa.free(t.prog);
    m.gpa.free(t.label_pc);
    m.gpa.free(t.entries);
    m.gpa.free(t.locs);
    freed = true;

    return m.staged.items.len - 1;
}

/// gap-fs-autoloader: ONE-STEP load — stage + commit fused (`prepare_loading` +
/// `finish_loading` semantics with no handle round-trip), for the Vm's
/// `ensure_loaded` autoload path. SCOPE LIMIT: a module carrying `-on_load` is
/// NOT auto-committed (running the gate needs the in-process `run_on_load`
/// machinery the code server drives) — it returns `error.OnLoad` and the
/// caller's dispatch falls through to `undef`, never a half-loaded module.
pub fn loadBeamBytes(m: *Machine, mod_atom: ta.AtomIdx, bytes: []const u8) error{ OutOfMemory, Badfile, OnLoad }!void {
    const si = try stageBeam(m, mod_atom, bytes);
    if (m.staged.items[si].on_load_pc != null) return error.OnLoad;
    commitStaged(m, si) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Badfile,
    };
}

/// Extract a prepared-handle id from a term, or null if it is not a PREP ref.
fn prepId(m: *Machine, t: Term) ?u64 {
    if (!FinalTerms.repIsRef(&m.ctx, t)) return null;
    const w = FinalTerms.refWords(&m.ctx, t);
    if (w[0] != PREP_MAGIC) return null;
    return @as(u64, w[1]) | (@as(u64, w[2]) << 32);
}

/// Find the index into `m.staged` of an as-yet-uncommitted prepared handle.
fn stagedIdx(m: *Machine, id: u64) ?usize {
    for (m.staged.items, 0..) |s, i| {
        if (s.ref == id and !s.committed) return i;
    }
    return null;
}

/// `erlang:finish_loading(PreparedList)` — commit staged modules into the runtime
/// code table (all-or-nothing: validate the WHOLE list before committing any).
pub fn finish_loading_1(m: *Machine, args: []const Term) BifError!Term {
    // Pass 1 — validate the list shape and every handle (erts commits atomically).
    var cur = args[0];
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        const id = prepId(m, h) orelse return error.Badarg; // non-ref / non-PREP
        if (stagedIdx(m, id) == null) return error.Badarg; // reused / unknown
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg; // improper list

    // Pass 2 — commit each staged module into the runtime dispatch table, and
    // collect any that carry an `-on_load` gate (E7.2, DIVERGENCE 147).
    var onload_mods: std.ArrayList(ta.AtomIdx) = .empty;
    defer onload_mods.deinit(m.gpa);
    cur = args[0];
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        const id = prepId(m, h).?;
        const si = stagedIdx(m, id).?;
        try commitStaged(m, si);
        if (m.staged.items[si].on_load_pc != null) {
            m.staged.items[si].on_load_pending = true;
            onload_mods.append(m.gpa, m.staged.items[si].module) catch return error.OutOfMemory;
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }

    // erts: `finish_loading/1` of a set with any on_load module returns
    // `{on_load, [Mod]}` (the code is loaded but each on_load must still run and
    // GATE via finish_after_on_load/2); an all-plain set returns the atom `ok`.
    if (onload_mods.items.len == 0)
        return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("ok") catch return error.OutOfMemory);

    var list = FinalTerms.nil(&m.ctx);
    var i = onload_mods.items.len;
    while (i > 0) {
        i -= 1;
        list = FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, onload_mods.items[i]), list) catch return error.OutOfMemory;
    }
    const on_load_atom = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("on_load") catch return error.OutOfMemory);
    return FinalTerms.tuple(&m.ctx, &.{ on_load_atom, list }) catch return error.OutOfMemory;
}

// ============================================================================
// E7.2 (DIVERGENCE 147): the on_load STAGING trio — has_prepared_code_on_load/1,
// call_on_load_function/1, finish_after_on_load/2 — made reachable end-to-end
// now that prepare records the on_load entry and finish returns {on_load,[Mod]}.
//
// The host protocol (empirically verified on the OTP-28 oracle, `onload_call`
// corpus case): prepare_loading(Mod,Bin) -> ref; has_prepared_code_on_load(Ref)
// -> true iff the beam carries `-on_load`; finish_loading([Ref]) -> {on_load,
// [Mod]}; call_on_load_function(Mod) RUNS the on_load and returns its value
// (`ok` for a succeeding one); finish_after_on_load(Mod, Keep) -> true, where
// Keep = (OnLoadResult =:= ok) COMMITS (true) or PURGES the just-loaded code
// (false). The code_server.zig staged algebra is the Zig-level specification of
// the same ON_LOAD GATE (commit-on-ok / atomic-rollback) laws.
// ============================================================================

/// Find a COMMITTED staged module by its module atom (the on_load trio keys on
/// the module, not the prepared handle — erts' on_load state is module-indexed).
fn committedIdxOfModule(m: *Machine, mod: ta.AtomIdx) ?usize {
    for (m.staged.items, 0..) |s, i| {
        if (s.committed and s.module == mod) return i;
    }
    return null;
}

/// `erlang:has_prepared_code_on_load(PreparedCode)` — does the staged image
/// carry an `-on_load` function that must run and GATE before the load is kept?
/// A non-PREP handle or an unknown/reused id is a `badarg` (erts).
pub fn has_prepared_code_on_load_1(m: *Machine, args: []const Term) BifError!Term {
    const id = prepId(m, args[0]) orelse return error.Badarg;
    const si = stagedIdx(m, id) orelse return error.Badarg;
    return boolTerm(m, m.staged.items[si].on_load_pc != null);
}

/// `erlang:call_on_load_function(Module)` — run the just-loaded module's on_load
/// function in the CALLING process; its return VALUE becomes this BIF's value.
/// A control-flow trap (`.run_on_load`): the scheduler jumps to the resolved
/// on_load entry and the on_load's `ret` lands its result in x0. A `badarg` when
/// `Module` is not an atom or has no pending on_load (erts).
pub fn call_on_load_function_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const mod = FinalTerms.atomIdxOf(args[0]);
    const si = committedIdxOfModule(m, mod) orelse return error.Badarg;
    const s = &m.staged.items[si];
    if (!s.on_load_pending) return error.Badarg;
    const entry = s.on_load_pc orelse return error.Badarg;
    // Trap: run the on_load. `runBifInto0` writes a placeholder to x0 that the
    // on_load's actual return VALUE overwrites when it rets to the continuation.
    m.pending = .{ .run_on_load = .{ .entry = entry } };
    return FinalTerms.nil(&m.ctx);
}

/// `erlang:finish_after_on_load(Module, Keep)` — the on_load GATE. `Keep` is
/// `OnLoadResult =:= ok`: `true` COMMITS the just-loaded code (already in the
/// dispatch table — clear the pending flag); `false` ROLLS IT BACK atomically
/// (retire the module so it is no longer callable — a failed on_load). Returns
/// `true`. A `badarg` on a non-atom Module, a non-bool Keep, or no pending
/// on_load for Module (erts).
pub fn finish_after_on_load_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    if (!FinalTerms.repIsAtom(args[1])) return error.Badarg;
    const keep = if (FinalTerms.atomIdxOf(args[1]) == m.bool_true)
        true
    else if (FinalTerms.atomIdxOf(args[1]) == m.bool_false)
        false
    else
        return error.Badarg;
    const mod = FinalTerms.atomIdxOf(args[0]);
    const si = committedIdxOfModule(m, mod) orelse return error.Badarg;
    const s = &m.staged.items[si];
    if (!s.on_load_pending) return error.Badarg;
    s.on_load_pending = false;
    if (!keep) {
        // Atomic rollback: drop the module's committed exports (uncallable) and
        // retire its code_index slot (a failed on_load is PURGED — erts).
        var i: usize = 0;
        while (i < m.dyn_exports.items.len) {
            if (m.dyn_exports.items[i].module == mod) {
                _ = m.dyn_exports.swapRemove(i);
            } else i += 1;
        }
        _ = m.code_index.deleteModule(m.ctx.atoms.nameOf(mod));
    }
    return FinalTerms.atom(&m.ctx, m.bool_true);
}

/// Commit one staged module: repoint `dyn_exports` at its (new) version and
/// register it in `code_index` (a RELOAD rotates current→old there, which the
/// M10 hold/purge accounting and the QUERY BIFs observe). Old return pcs stay
/// valid — `dyn_code` is append-only — so a running continuation is undisturbed.
fn commitStaged(m: *Machine, si: usize) BifError!void {
    const s = &m.staged.items[si];
    // Reload: drop the module's prior committed exports (NEW code wins). A saved
    // return pc into the OLD version's code range is unaffected (it dispatches
    // through no export — it is a raw pc into `dyn_code`).
    var i: usize = 0;
    while (i < m.dyn_exports.items.len) {
        if (m.dyn_exports.items[i].module == s.module) {
            _ = m.dyn_exports.swapRemove(i);
        } else i += 1;
    }
    m.dyn_exports.appendSlice(m.gpa, s.entries) catch return error.OutOfMemory;
    // Register in the runtime code_index (presence/version for the QUERY BIFs and
    // `resolveRuntime`'s currency gate). The stored program is a presence sentinel
    // — dispatch executes via `dyn_exports`' unified pcs, never this slice.
    const name = m.ctx.atoms.nameOf(s.module);
    m.code_index.load(name, &.{}) catch return error.OutOfMemory;
    s.committed = true;
}

// ============================================================================
// E6.3 (DIVERGENCE 108, amending 75/81): the erts_code_purger PROCESS restriction
// ============================================================================
//
// `erts_internal:purge_module/2` and the two `erts_literal_area_collector` BIFs
// are RESTRICTED to their dedicated SYSTEM process — a direct call from any OTHER
// process raises `error:notsup` on the host oracle (empirically confirmed on the
// OTP-28 host: `purge_module(_,_)`, `release_area_switch/0`, `send_copy_request/3`
// all raise `error:notsup` from a normal process, and the process check DOMINATES
// arg validation — `purge_module(123, notabool)` still raises `notsup`). This is
// the LAST blocker DIVERGENCE 75 named: the two flips before this one
// (prepare/finish, E5.2b/81) discharged the runtime-dispatch + beam-bytes
// blockers; THIS row is the process-restriction itself.
//
// A corpus case runs from a NORMAL (non-purger) process on BOTH VMs, so the
// observable surface of every one of these BIFs is exactly `error:notsup` —
// byte-EQ, no representation leak (the `purge_notsup`/`litarea_notsup` corpus
// cases). The REAL purge/literal-copy work is driven THROUGH the purger system
// process (boot.zig spawns it; the `erts_code_purger`/`erts_literal_area_collector`
// system-process set is the head of the boot set), and its two-version safety +
// literal conservation are proven by the RUNTIME-driven laws in `code_server.zig`
// and `proc.zig` — the M10 PURGE-SAFETY law restated at the system-process layer.
// No false EQ: the bif-surface differential is honest (notsup on both), and the
// engine-level purge is law-proven, exactly as erts splits the two.

/// Raise `error:notsup` — the process-restriction rejection every purger/
/// collector BIF returns to a non-system caller (host-verified).
fn raiseNotsup(m: *Machine) BifError {
    const notsup = m.ctx.atoms.intern("notsup") catch return error.OutOfMemory;
    return m.bifRaise(.error_, FinalTerms.atom(&m.ctx, notsup));
}

/// `erts_internal:purge_module(Module, Bool)` — RESTRICTED to the erts_code_purger
/// system process. Any direct (non-purger) call raises `error:notsup` — the
/// process check dominates arg validation, so BOTH args are irrelevant to the
/// observable result. The actual purge (drop the retired `old` version, refused
/// while a process holds a continuation into it) is `code_server.purgeModule`,
/// driven through the boot-spawned purger and proven by the RUNTIME-driven
/// purge-safety law. DIVERGENCE 75/81/108.
pub fn purge_module_2(m: *Machine, args: []const Term) BifError!Term {
    _ = args; // the process restriction dominates: any caller → notsup
    return raiseNotsup(m);
}

/// `erts_literal_area_collector:release_area_switch/0` — RESTRICTED to the
/// literal-area collector system process; a non-collector call raises
/// `error:notsup`. The area switch it coordinates (release a retired literal
/// area once every process has copied its references off) preserves `denote`
/// of every live heap — the litarea-conservation law. DIVERGENCE 108.
pub fn release_area_switch_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return raiseNotsup(m);
}

/// `erts_literal_area_collector:send_copy_request/3` — RESTRICTED to the
/// literal-area collector; a non-collector call raises `error:notsup` (the
/// process check dominates: atom args still raise notsup, host-verified).
pub fn send_copy_request_3(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return raiseNotsup(m);
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;
const codeix = @import("../code_index.zig");

const prog_a: ia.Program = &.{.{ .halt = .{ .src = .nil } }};

test "LAW E6.3 purger/collector PROCESS-RESTRICTION: a non-system caller raises error:notsup (arg-independent)" {
    // The observable surface of the purger/collector BIFs from a NORMAL process
    // is EXACTLY `error:notsup` — the host-verified rejection differential that
    // flips these rows EQ (`purge_notsup`/`litarea_notsup` corpus cases). The
    // process check DOMINATES arg validation, so the reason is `notsup`
    // regardless of the (here deliberately ill-typed) arguments.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const notsup = try atoms.intern("notsup");
    const junk = FinalTerms.int(&m.ctx, 123);
    // Each call stages `m.bif_raise`, so check-and-clear inline (a pre-built array
    // would overwrite the stage before we could observe it).
    const expectNotsup = struct {
        fn f(mm: *Machine, ns: ta.AtomIdx, got: BifError!Term) !void {
            try std.testing.expectError(error.Raise, got);
            const staged = mm.bif_raise orelse return error.TestUnexpectedResult;
            mm.bif_raise = null;
            try std.testing.expectEqual(ia.ExcClass.error_, staged.class);
            try std.testing.expect(FinalTerms.eqlExact(&mm.ctx, staged.reason, FinalTerms.atom(&mm.ctx, ns)));
        }
    }.f;
    try expectNotsup(&m, notsup, purge_module_2(&m, &.{ junk, junk }));
    try expectNotsup(&m, notsup, release_area_switch_0(&m, &.{}));
    try expectNotsup(&m, notsup, send_copy_request_3(&m, &.{ junk, junk, junk }));
}

test "LAW E2.12 code query: loaded/0 sorted, module_loaded/1 tracks the index, pre_loaded/0 is []" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // pre_loaded/0 always [].
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try pre_loaded_0(&m, &.{}), FinalTerms.nil(&m.ctx)));

    // nothing loaded yet.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try loaded_0(&m, &.{}), FinalTerms.nil(&m.ctx)));
    const zeta = FinalTerms.atom(&m.ctx, try atoms.intern("zeta"));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try module_loaded_1(&m, &.{zeta})));

    // load out of alphabetical order — loaded/0 must still come back sorted.
    try m.code_index.load("zeta", prog_a);
    try m.code_index.load("alpha", prog_a);
    try m.code_index.load("mid", prog_a);

    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try module_loaded_1(&m, &.{zeta})));
    const unloaded = FinalTerms.atom(&m.ctx, try atoms.intern("nope"));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try module_loaded_1(&m, &.{unloaded})));

    const got = try loaded_0(&m, &.{});
    const alpha = FinalTerms.atom(&m.ctx, try atoms.intern("alpha"));
    const mid = FinalTerms.atom(&m.ctx, try atoms.intern("mid"));
    const want = try FinalTerms.cons(&m.ctx, alpha, try FinalTerms.cons(&m.ctx, mid, try FinalTerms.cons(&m.ctx, zeta, FinalTerms.nil(&m.ctx))));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got, want));

    // rejection: a non-atom argument.
    try std.testing.expectError(error.Badarg, module_loaded_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
}

test "LAW E5.2b check_old_code/delete_module: table query + retire, matching the host" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const undef_idx = try atoms.intern("undefined");
    const mmod = FinalTerms.atom(&m.ctx, try atoms.intern("m"));
    const absent = FinalTerms.atom(&m.ctx, try atoms.intern("nope"));

    // absent: check_old_code -> false, delete_module -> undefined (host-verified).
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try check_old_code_1(&m, &.{absent})));
    try std.testing.expectEqual(undef_idx, FinalTerms.atomIdxOf(try delete_module_1(&m, &.{absent})));

    // loaded, no old: check_old_code false; delete -> true; check_old_code true.
    try m.code_index.load("m", prog_a);
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try check_old_code_1(&m, &.{mmod})));
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try delete_module_1(&m, &.{mmod})));
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try check_old_code_1(&m, &.{mmod})));
    // deleting again with no current version is a badarg (erts).
    try std.testing.expectError(error.Badarg, delete_module_1(&m, &.{mmod}));
    // rejection: non-atom argument.
    try std.testing.expectError(error.Badarg, check_old_code_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
}

test "LAW gap-hot-load-code-lib: code:purge/soft_purge/delete/modified_modules truth table over the runtime code table (DIVERGENCE 600 — the compiled-reachable code: library surface)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const A = struct {
        fn a(mm: *Machine, at: *AtomTable, s: []const u8) Term {
            return FinalTerms.atom(&mm.ctx, at.intern(s) catch unreachable);
        }
    };
    const absent = A.a(&m, &atoms, "nope");

    // (1) absent module: soft_purge -> true (nothing to hold back); purge -> false
    // (no proc killed); delete -> false (nothing to retire). Byte-EQ vs OTP-30.
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try soft_purge_1(&m, &.{absent})));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try purge_1(&m, &.{absent})));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try delete_1(&m, &.{absent})));
    // (2) modified_modules/0 -> [] (closed world) always.
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, try modified_modules_0(&m, &.{})) == .nil);

    // (3) loaded, no old: delete -> true (current retired to old); soft_purge -> true
    // (drops the retired old, no holder).
    try m.code_index.load("m", prog_a);
    const mm = A.a(&m, &atoms, "m");
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try delete_1(&m, &.{mm})));
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try soft_purge_1(&m, &.{mm})));

    // (4) old code WITH a lingering holder: soft_purge REFUSES (false, old left in
    // place); purge KILLS (true). This is the code:purge vs code:soft_purge boundary
    // — kills a mutant that maps code:purge -> softPurge (which returns false here).
    try m.code_index.load("h", prog_a);
    _ = m.code_index.hold("h").?; // a process enters the current version (v1)
    try m.code_index.load("h", prog_a); // v1 -> old (the holder now lingers on OLD); v2 current
    const hh = A.a(&m, &atoms, "h");
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try soft_purge_1(&m, &.{hh})));
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try purge_1(&m, &.{hh})));
    // rejection: a non-atom arg is badarg on every verb.
    try std.testing.expectError(error.Badarg, purge_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
}

test "LAW E5.2c beamfile_module_md5: whole-beam checksum (byte-EQ to erts), undefined/badarg totality" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // A REAL, `+deterministic`-compiled beam of `-module(zmini). z() -> 0.` (520
    // bytes). Its module MD5 is host-verified (OTP-28 `beamfile_module_md5/1`
    // AND `zmini:module_info(md5)`) as the 16 bytes below — the SAME value the
    // erl-corpus `bfmd5` case observes over the SAME bytes. This pins that
    // `computeMd5` (E4.2) is byte-EQ over a WHOLE beam argument, not just the
    // embedded-fixture path — the metadata-round-trip differential's Zig anchor.
    const zmini_beam = [_]u8{
        70, 79, 82, 49, 0, 0, 2, 0, 66, 69, 65, 77, 65, 116, 85, 56, 0, 0, 0, 47, 255, 255, 255, 251, 80, 122, 109, 105, 110, 105, 16, 122, 176, 109, 111, 100, 117, 108, 101, 95, 105, 110, 102, 111, 96, 101, 114, 108, 97, 110, 103, 240, 103, 101, 116, 95, 109, 111, 100, 117, 108, 101, 95, 105, 110, 102, 111, 0, 67, 111, 100, 101, 0, 0, 0, 70, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 177, 0, 0, 0, 7, 0, 0, 0, 3, 1, 16, 153, 16, 2, 18, 34, 0, 1, 32, 64, 1, 3, 19, 1, 48, 153, 0, 2, 18, 50, 0, 1, 64, 64, 18, 3, 78, 16, 0, 1, 80, 153, 0, 2, 18, 50, 16, 1, 96, 64, 3, 19, 64, 18, 3, 78, 32, 16, 3, 0, 0, 83, 116, 114, 84, 0, 0, 0, 0, 73, 109, 112, 84, 0, 0, 0, 28, 0, 0, 0, 2, 0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0, 2, 69, 120, 112, 84, 0, 0, 0, 40, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 6, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 2, 77, 101, 116, 97, 0, 0, 0, 45, 131, 108, 0, 0, 0, 1, 104, 2, 119, 16, 101, 110, 97, 98, 108, 101, 100, 95, 102, 101, 97, 116, 117, 114, 101, 115, 108, 0, 0, 0, 1, 119, 10, 109, 97, 121, 98, 101, 95, 101, 120, 112, 114, 106, 106, 0, 0, 0, 76, 111, 99, 84, 0, 0, 0, 4, 0, 0, 0, 0, 65, 116, 116, 114, 0, 0, 0, 39, 131, 108, 0, 0, 0, 1, 104, 2, 119, 3, 118, 115, 110, 108, 0, 0, 0, 1, 110, 16, 0, 220, 235, 165, 195, 200, 54, 14, 99, 63, 230, 9, 153, 112, 43, 136, 221, 106, 106, 0, 67, 73, 110, 102, 0, 0, 0, 26, 131, 108, 0, 0, 0, 1, 104, 2, 119, 7, 118, 101, 114, 115, 105, 111, 110, 107, 0, 5, 57, 46, 48, 46, 52, 106, 0, 0, 68, 98, 103, 105, 0, 0, 0, 66, 131, 104, 3, 119, 13, 100, 101, 98, 117, 103, 95, 105, 110, 102, 111, 95, 118, 49, 119, 17, 101, 114, 108, 95, 97, 98, 115, 116, 114, 97, 99, 116, 95, 99, 111, 100, 101, 104, 2, 119, 4, 110, 111, 110, 101, 108, 0, 0, 0, 1, 119, 13, 100, 101, 116, 101, 114, 109, 105, 110, 105, 115, 116, 105, 99, 106, 0, 0, 76, 105, 110, 101, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 49, 0, 0, 0, 84, 121, 112, 101, 0, 0, 0, 10, 0, 0, 0, 3, 0, 0, 0, 1, 15, 255, 0, 0,
    };
    const want_md5 = [_]u8{ 221, 136, 43, 112, 153, 9, 230, 63, 99, 14, 54, 200, 195, 165, 235, 220 };

    const bin = try FinalTerms.binary(&m.ctx, &zmini_beam);
    const got = try beamfile_module_md5_1(&m, &.{bin});
    try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, got));
    try std.testing.expectEqualSlices(u8, &want_md5, FinalTerms.binBytes(&m.ctx, got));

    // Totality: a truncated/non-beam binary → the atom `undefined` (never a
    // panic — erts `beamfile_read` fail), a non-binary → badarg.
    const undef = FinalTerms.atom(&m.ctx, try atoms.intern("undefined"));
    const short = try FinalTerms.binary(&m.ctx, zmini_beam[0..20]);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try beamfile_module_md5_1(&m, &.{short}), undef));
    const junk = try FinalTerms.binary(&m.ctx, "not a beam");
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try beamfile_module_md5_1(&m, &.{junk}), undef));
    try std.testing.expectError(error.Badarg, beamfile_module_md5_1(&m, &.{FinalTerms.int(&m.ctx, 7)}));
}


// ---- E7.2 (DIVERGENCE 147): the on_load STAGING trio law -------------------

/// A real `+deterministic` erlc build of `-module(zonload). -export([z/0]).
/// -on_load(init/0). init() -> ok. z() -> 42.` (560 bytes) — an EMBEDDED beam
/// blob carrying an `-on_load` attribute. The SAME bytes the `onload_call`
/// corpus case reads (fixtures/erl/corpus_seed.erl `onload_beam/0`).
const zonload_beam = [_]u8{
    70,79,82,49,0,0,2,40,66,69,65,77,65,116,85,56,0,0,0,57,255,255,255,249,112,122,111,110,108,111,97,100,64,105,110,105,116,32,111,107,16,122,176,109,111,100,117,108,101,95,105,110,102,111,96,101,114,108,97,110,103,240,103,101,116,95,109,111,100,117,108,101,95,105,110,102,111,0,0,0,67,111,100,101,0,0,0,86,0,0,0,16,0,0,0,0,0,0,0,177,0,0,0,9,0,0,0,4,1,16,153,16,2,18,34,0,1,32,149,64,50,3,19,1,48,153,32,2,18,66,0,1,64,64,9,42,3,19,1,80,153,0,2,18,82,0,1,96,64,18,3,78,16,0,1,112,153,0,2,18,82,16,1,128,64,3,19,64,18,3,78,32,16,3,0,0,83,116,114,84,0,0,0,0,73,109,112,84,0,0,0,28,0,0,0,2,0,0,0,6,0,0,0,7,0,0,0,1,0,0,0,6,0,0,0,7,0,0,0,2,69,120,112,84,0,0,0,40,0,0,0,3,0,0,0,5,0,0,0,1,0,0,0,8,0,0,0,5,0,0,0,0,0,0,0,6,0,0,0,4,0,0,0,0,0,0,0,4,77,101,116,97,0,0,0,45,131,108,0,0,0,1,104,2,119,16,101,110,97,98,108,101,100,95,102,101,97,116,117,114,101,115,108,0,0,0,1,119,10,109,97,121,98,101,95,101,120,112,114,106,106,0,0,0,76,111,99,84,0,0,0,16,0,0,0,1,0,0,0,2,0,0,0,0,0,0,0,2,65,116,116,114,0,0,0,39,131,108,0,0,0,1,104,2,119,3,118,115,110,108,0,0,0,1,110,16,0,163,45,90,18,85,165,192,82,3,63,75,90,98,41,208,7,106,106,0,67,73,110,102,0,0,0,26,131,108,0,0,0,1,104,2,119,7,118,101,114,115,105,111,110,107,0,5,57,46,48,46,52,106,0,0,68,98,103,105,0,0,0,66,131,104,3,119,13,100,101,98,117,103,95,105,110,102,111,95,118,49,119,17,101,114,108,95,97,98,115,116,114,97,99,116,95,99,111,100,101,104,2,119,4,110,111,110,101,108,0,0,0,1,119,13,100,101,116,101,114,109,105,110,105,115,116,105,99,106,0,0,76,105,110,101,0,0,0,22,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,2,0,0,0,0,65,81,0,0,84,121,112,101,0,0,0,10,0,0,0,3,0,0,0,1,15,255,0,0,
};

test "LAW E7.2 on_load-GATE atomic-rollback: prepare->has_prepared->finish{on_load}->call->finish_after (commit vs rollback)" {
    // The runtime-level ON_LOAD GATE law over the Machine's staged code state
    // (the code_server.zig CodeIndex algebra proves the same commit/rollback at
    // the pure layer). A staged on_load module: prepare records its on_load
    // entry; has_prepared_code_on_load reports it; finish_loading returns
    // {on_load,[zonload]} (NOT `ok`) and marks it pending; call_on_load_function
    // TRAPS to run it; finish_after_on_load(_,true) COMMITS (module stays
    // callable) while (_,false) ROLLS BACK atomically (module uncallable).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    const zmod = try atoms.intern("zonload");

    // ---- commit branch (Keep=true): the module stays committed --------------
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        const mod_atom = FinalTerms.atom(&m.ctx, zmod);
        const bin = try FinalTerms.binary(&m.ctx, &zonload_beam);

        const prep = try prepare_loading_2(&m, &.{ mod_atom, bin });
        try std.testing.expect(FinalTerms.repIsRef(&m.ctx, prep));
        // has_prepared_code_on_load: this beam CARRIES on_load.
        try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try has_prepared_code_on_load_1(&m, &.{prep})));

        // finish_loading returns {on_load,[zonload]} (not `ok`).
        const fr = try finish_loading_1(&m, &.{try FinalTerms.cons(&m.ctx, prep, FinalTerms.nil(&m.ctx))});
        try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, fr));
        try std.testing.expect(std.mem.eql(u8, "on_load", m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&m.ctx, fr, 0)))));
        const head = FinalTerms.listHead(&m.ctx, FinalTerms.tupleElem(&m.ctx, fr, 1));
        try std.testing.expectEqual(zmod, FinalTerms.atomIdxOf(head));
        // the module IS committed + callable (z/0 resolves in the runtime table).
        const zfun = try atoms.intern("z");
        try std.testing.expect(m.resolveRuntime(zmod, zfun, 0) != null);

        // call_on_load_function TRAPS to run the on_load (mutant 2: skip the run).
        _ = try call_on_load_function_1(&m, &.{mod_atom});
        try std.testing.expect(m.pending != null);
        try std.testing.expect(m.pending.? == .run_on_load);
        m.pending = null; // (the scheduler would jump to the entry; not run here)

        // finish_after_on_load(_, true): COMMIT — z/0 stays callable.
        try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try finish_after_on_load_2(&m, &.{ mod_atom, FinalTerms.atom(&m.ctx, m.bool_true) })));
        try std.testing.expect(m.resolveRuntime(zmod, zfun, 0) != null);
    }

    // ---- rollback branch (Keep=false): the module is retired (mutant 1) ------
    {
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();
        const mod_atom = FinalTerms.atom(&m.ctx, zmod);
        const bin = try FinalTerms.binary(&m.ctx, &zonload_beam);
        const prep = try prepare_loading_2(&m, &.{ mod_atom, bin });
        _ = try finish_loading_1(&m, &.{try FinalTerms.cons(&m.ctx, prep, FinalTerms.nil(&m.ctx))});
        const zfun = try atoms.intern("z");
        try std.testing.expect(m.resolveRuntime(zmod, zfun, 0) != null); // committed

        // finish_after_on_load(_, false): ATOMIC ROLLBACK — z/0 no longer callable.
        try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try finish_after_on_load_2(&m, &.{ mod_atom, FinalTerms.atom(&m.ctx, m.bool_false) })));
        try std.testing.expect(m.resolveRuntime(zmod, zfun, 0) == null);

        // totality: the trio badargs on garbage (a non-PREP handle / no pending).
        try std.testing.expectError(error.Badarg, has_prepared_code_on_load_1(&m, &.{FinalTerms.int(&m.ctx, 7)}));
        try std.testing.expectError(error.Badarg, call_on_load_function_1(&m, &.{mod_atom})); // no pending on_load now
        try std.testing.expectError(error.Badarg, finish_after_on_load_2(&m, &.{ mod_atom, FinalTerms.atom(&m.ctx, m.bool_true) }));
    }
}

// ---- E4.2b: beamfile_chunk/2 laws ------------------------------------------

/// Build a byte-list (charlist) term for a 4-char chunk name.
fn tagList(m: *Machine, name: []const u8) !Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = name.len;
    while (i > 0) {
        i -= 1;
        acc = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, name[i]), acc);
    }
    return acc;
}

test "LAW E4.2b beamfile_chunk: EXTRACTION (a found chunk's payload) + ABSENCE (undefined)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // A minimal well-formed IFF/BEAM container carrying ONE chunk "Atom" with
    // payload <<1,2,3,4>>: "FOR1" <16:u32be> "BEAM" "Atom" <4:u32be> 01 02 03 04.
    const beam = [_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 16, 'B', 'E', 'A', 'M', 'A', 't', 'o', 'm', 0, 0, 0, 4, 1, 2, 3, 4 };
    const bin = try FinalTerms.binary(&m.ctx, &beam);
    const undef = FinalTerms.atom(&m.ctx, try atoms.intern("undefined"));

    // EXTRACTION: the found chunk's payload bytes, verbatim.
    const got = try beamfile_chunk_2(&m, &.{ bin, try tagList(&m, "Atom") });
    try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, got));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, FinalTerms.binBytes(&m.ctx, got));

    // ABSENCE: a chunk not present → undefined (NOT badarg).
    const absent = try beamfile_chunk_2(&m, &.{ bin, try tagList(&m, "AtU8") });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, absent, undef));

    // A non-IFF binary → undefined (iff_init fails, no badarg).
    const junk = try FinalTerms.binary(&m.ctx, "not a beam file at all");
    const j = try beamfile_chunk_2(&m, &.{ junk, try tagList(&m, "Atom") });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, j, undef));
}

test "LAW E4.2b beamfile_chunk: REJECTION (bad chunk-name / non-binary)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const beam = [_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 4, 'B', 'E', 'A', 'M' };
    const bin = try FinalTerms.binary(&m.ctx, &beam);

    // A 3-char chunk name (not a 4-byte list) → badarg.
    try std.testing.expectError(error.Badarg, beamfile_chunk_2(&m, &.{ bin, try tagList(&m, "Ato") }));
    // A 5-char chunk name (trailing junk after 4) → badarg.
    try std.testing.expectError(error.Badarg, beamfile_chunk_2(&m, &.{ bin, try tagList(&m, "Atomz") }));
    // A non-binary Bin argument → badarg.
    try std.testing.expectError(error.Badarg, beamfile_chunk_2(&m, &.{ FinalTerms.int(&m.ctx, 7), try tagList(&m, "Atom") }));
}

test "LAW E6.8 beamfile_chunk: STRICT form-size reader (DIVERGENCE 108 discharge — matches erts, empirically pinned)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const undef = FinalTerms.atom(&m.ctx, try atoms.intern("undefined"));
    const tag = try tagList(&m, "Atom");
    // Header + one "Atom" chunk (size 4, payload <<1,2,3,4>>). The FORM-SIZE
    // byte is bytes[7]. All expected outcomes below were captured from the real
    // OTP-28 host `erts_internal:beamfile_chunk/2`.
    // fs=16, total=24 (exact): the chunk IS found.
    {
        const b = [_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 16, 'B', 'E', 'A', 'M', 'A', 't', 'o', 'm', 0, 0, 0, 4, 1, 2, 3, 4 };
        const got = try beamfile_chunk_2(&m, &.{ try FinalTerms.binary(&m.ctx, &b), tag });
        try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, FinalTerms.binBytes(&m.ctx, got));
    }
    // fs=16, total=28 (trailing bytes AFTER form_end are ignored): STILL found.
    {
        const b = [_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 16, 'B', 'E', 'A', 'M', 'A', 't', 'o', 'm', 0, 0, 0, 4, 1, 2, 3, 4, 9, 9, 9, 9 };
        const got = try beamfile_chunk_2(&m, &.{ try FinalTerms.binary(&m.ctx, &b), tag });
        try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, FinalTerms.binBytes(&m.ctx, got));
    }
    // fs=20, total=28 (form claims a trailing 4-byte region that is a truncated
    // chunk header): the match is found FIRST but the walk is malformed → undef.
    {
        const b = [_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 20, 'B', 'E', 'A', 'M', 'A', 't', 'o', 'm', 0, 0, 0, 4, 1, 2, 3, 4, 9, 9, 9, 9 };
        const got = try beamfile_chunk_2(&m, &.{ try FinalTerms.binary(&m.ctx, &b), tag });
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got, undef));
    }
    // fs=24, total=28 (form_end=32 > byte_size): the form claims bytes we don't
    // have → undef.
    {
        const b = [_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 24, 'B', 'E', 'A', 'M', 'A', 't', 'o', 'm', 0, 0, 0, 4, 1, 2, 3, 4, 9, 9, 9, 9 };
        const got = try beamfile_chunk_2(&m, &.{ try FinalTerms.binary(&m.ctx, &b), tag });
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got, undef));
    }
    // fs=8, total=24 (form_end=16 truncates the chunk header) → undef.
    {
        const b = [_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 8, 'B', 'E', 'A', 'M', 'A', 't', 'o', 'm', 0, 0, 0, 4, 1, 2, 3, 4 };
        const got = try beamfile_chunk_2(&m, &.{ try FinalTerms.binary(&m.ctx, &b), tag });
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got, undef));
    }
    // fs=12, total=24 (form_end=20 cuts the chunk body) → undef.
    {
        const b = [_]u8{ 'F', 'O', 'R', '1', 0, 0, 0, 12, 'B', 'E', 'A', 'M', 'A', 't', 'o', 'm', 0, 0, 0, 4, 1, 2, 3, 4 };
        const got = try beamfile_chunk_2(&m, &.{ try FinalTerms.binary(&m.ctx, &b), tag });
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got, undef));
    }
}
