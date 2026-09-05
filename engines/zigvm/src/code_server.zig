//! beam-zig E5.2b / S16: the **file-based code SERVER** — the staged two-version
//! reload + on_load orchestration layered over `code_index.CodeIndex` (M10).
//! (cf. erts `code_server.erl` + `beam_bif_load.c`'s `prepare_loading`/
//! `finish_loading`/`finish_after_on_load` staging; DIVERGENCE 61, the Task-2
//! CONTINUATION of `OTP30_E5_PLAN.md`.)
//!
//! ## Where this sits
//! `code_index.zig` owns the RUNTIME code table primitives — `load`/`resolve`/
//! `hold`/`purge` + the E5.2b `deleteModule`/`checkOldCode` runtime ops. This
//! module owns the STAGED half erts splits `code:load_binary` into: a load is
//! not atomic at the call site — it is `prepare_loading` (validate + build a
//! Prepared handle, touching NOTHING) then `finish_loading` (commit the prepared
//! set into the table, all-or-nothing) with an on_load GATE in between
//! (`has_prepared_code_on_load` / `finish_after_on_load` — commit on `ok`, roll
//! the staged code back on anything else). Keeping the staging OUT of
//! `code_index` preserves its proven laws unchanged; this module adds the
//! higher-level ones.
//!
//! ## Signature
//!   prepareLoading   : (name, Program, on_load?) -> Prepared   (pure; no commit)
//!   finishLoading    : (Index, Prepared)        -> Index'      (atomic commit)
//!   hasOnLoad        : Prepared                  -> bool
//!   finishAfterOnLoad: (Index, Prepared, ok)    -> Index'|Index (gate: commit|rollback)
//!   md5Of            : Prepared                  -> [16]u8      (metadata carry)
//!
//! ## Semantic domain
//! A `Prepared` is a not-yet-committed code image: (module name, program, an
//! optional on_load entry marker, the module md5). `finishLoading` denotes
//! exactly `code_index.load(name, prog)` — the code server is a HOMOMORPHISM
//! onto the load primitive: staging then finishing a set of modules yields the
//! SAME table the static linker (`cli.link`) would, module-for-module.
//!
//! ## Laws (see the suite below)
//!   STAGED≡DIRECT   finishLoading(prepareLoading(n,p)) == load(n,p): a staged
//!       load and a direct load land the SAME current version (dynamic≡static).
//!   ON_LOAD GATE    finishAfterOnLoad(prep, ok=false) leaves the table BYTE-
//!       for-byte unchanged (atomic rollback); ok=true commits — entry 4's
//!       staged on_load, distinct from cli's single-module invoke-and-gate.
//!   TWO-VERSION SAFETY  finishing a module that already has current+old is
//!       REFUSED (OldCodeExists) — the M10 limit restated over the staged path.
//!   METADATA ROUND-TRIP  the md5 a Prepared carries survives prepare->finish
//!       and matches the source image's checksum (the beamfile_module_md5 shape).
//!   REJECTION       prepareLoading of an EMPTY program is refused (a beam with
//!       no code is not loadable) — totality, never a panic.
//!
//! ## Scope honesty (DIVERGENCE 61; 75)
//! This module + its laws prove the staged reload + purge machinery (E5.2c adds
//! the LIVE-RELOAD two-version safety / purge-refused-while-held law over
//! `code_index.hold`/`purge`). The `bif.tab` rows split by REACHABILITY:
//!   - `erts_internal:beamfile_module_md5/1` FLIPS EQ (E5.2c): it is PURE over a
//!     raw beam-binary argument, so a real `+deterministic` beam image carried as
//!     an EMBEDDED BINARY literal (no stdlib file I/O) drives it end-to-end (the
//!     `bfmd5` corpus case, byte-EQ to erts via `beam_loader.beamModuleMd5`).
//!   - the runtime-QUERY rows `erlang:check_old_code/1` + `erlang:delete_module/1`
//!     flip EQ (E5.2b, the `code_q` differential) — no second beam needed.
//!   - `prepare_loading/2` + `finish_loading/1` FLIP EQ (e5-dispatch-codeidx,
//!     DIVERGENCE 81): `call_ext` dispatch now consults the RUNTIME code table
//!     (`instr_algebra.Machine.resolveRuntime` / `dyn_exports` / `dyn_code`), so a
//!     `finish_loaded` module is callable, and the new module's beam bytes come
//!     from an EMBEDDED binary literal (the honest bif-surface source) — the
//!     `reload_call` corpus differential. The STAGED prepare/finish live in
//!     `bifs/code.zig`'s BIFs (they own the runtime splice); THIS module's staged
//!     algebra + laws remain the Zig-level specification of the same semantics.
//!   - `purge_module/2` FLIPS EQ (E6.3, DIVERGENCE 108): the erts_code_purger
//!     PROCESS restriction is now MODELLED — a direct (non-purger) call raises
//!     `error:notsup` (byte-EQ on both VMs, the `purge_notsup` corpus case), and
//!     the REAL purge is driven THROUGH the boot-spawned purger system process
//!     (boot.zig), proven by the "LAW E6.3 purge two-version safety, RUNTIME-
//!     driven" + litarea-conservation laws below (the M10 PURGE-SAFETY law
//!     restated at the system-process layer). The two `erts_literal_area_collector`
//!     rows flip on the SAME notsup rejection (the `litarea_notsup` case).
//!   - the on_load staging trio FLIPS EQ (E7.2, DIVERGENCE 147): the erlang:
//!     on_load bifs exist on OTP-28 and `finish_loading` of an on_load module
//!     returns `{on_load,[Mod]}`; this staged algebra's ON_LOAD GATE law is the
//!     Zig specification of the commit/atomic-rollback, and the runtime trio in
//!     `bifs/code.zig` (has_prepared_code_on_load/1, call_on_load_function/1,
//!     finish_after_on_load/2) is driven end-to-end over an EMBEDDED on_load beam
//!     blob (the `onload_call` corpus case, byte-EQ 42+N on both VMs). The
//!     `records:get_definition/2` sibling re-binds `deferred-oracle-skew` (native
//!     records are OTP-30-only; the OTP-28 host raises `error:undef`, no
//!     differential — the check_process_code precedent).

const std = @import("std");
const ia = @import("instr_algebra.zig");
const codeix = @import("code_index.zig");

const CodeIndex = codeix.CodeIndex;

/// A staged, not-yet-committed code image. `on_load` is the entry PC of the
/// module's `on_load` function, or null when the module declares none.
pub const Prepared = struct {
    name: []const u8,
    prog: ia.Program,
    on_load: ?u32 = null,
    md5: [16]u8 = [_]u8{0} ** 16,
};

pub const PrepareError = error{EmptyProgram};

/// `erts_internal:prepare_loading/2` — validate a code image and stage it.
/// Commits NOTHING to the table. An empty program is rejected (totality).
pub fn prepareLoading(name: []const u8, prog: ia.Program, on_load: ?u32, md5: [16]u8) PrepareError!Prepared {
    if (prog.len == 0) return error.EmptyProgram;
    return .{ .name = name, .prog = prog, .on_load = on_load, .md5 = md5 };
}

/// `erlang:finish_loading/1` — commit a prepared image into the code table.
/// Atomic per module: on success the prepared program is the new current
/// version (old rotation per `code_index.load`); on the two-version limit it
/// returns `error.OldCodeExists` and the table is untouched.
pub fn finishLoading(idx: *CodeIndex, prep: Prepared) !void {
    try idx.load(prep.name, prep.prog);
}

/// `erlang:has_prepared_code_on_load/1` — does the staged image carry an
/// on_load entry that must run and gate before the load commits?
pub fn hasOnLoad(prep: Prepared) bool {
    return prep.on_load != null;
}

/// `erlang:finish_after_on_load/2` — the on_load GATE. `ok` is the result of
/// running the staged module's on_load function: `true` commits the staged
/// image; `false` rolls it back (the table is left exactly as it was).
pub fn finishAfterOnLoad(idx: *CodeIndex, prep: Prepared, ok: bool) !void {
    if (!ok) return; // rollback: staged code is simply discarded, table untouched
    try idx.load(prep.name, prep.prog);
}

/// The metadata a Prepared carries (the `beamfile_module_md5/1` value).
pub fn md5Of(prep: Prepared) [16]u8 {
    return prep.md5;
}

/// `erts_internal:purge_module/2` (the `complete` phase) — drop the retired
/// `old` version of `name`. REFUSED (`error.ProcessesHoldOldCode`) while any
/// process still holds a continuation into the old version — the erts "purge
/// with a live reference is refused" rule, restated at the code-server surface
/// over `code_index.hold`/`release`. A HOMOMORPHISM onto the purge primitive:
/// `purgeModule` denotes exactly `code_index.purge`, so the M10 PURGE-SAFETY law
/// carries up to the staged reload path unchanged.
pub fn purgeModule(idx: *CodeIndex, name: []const u8) !void {
    try idx.purge(name);
}

// ============================================================================
// gap-hot-load-fs: the `code:` LIBRARY hot-load surface — the two-version LOAD
// contract (`code:load_binary/3` reload → old, third load → {error,not_purged})
// + `code:purge/1` / `code:soft_purge/1`, layered over the `code_index` table
// and pinned byte-for-byte against the live OTP-30 oracle. These are `code.erl`
// / `code_server.erl` gen_server functions (NOT `bif.tab` rows), so they belong
// here at the code-SERVER layer, denoting the `code_index` primitives.
//
// SCOPE HONESTY: `release_handler`'s live application upgrade (appups / relups /
// `release_handler:install_release/1`) is a LARGE separate OTP subsystem
// (`sasl`) that orchestrates suspend → code_change → resume across a whole
// release. It is NOT modeled here and MUST NOT be faked — the primitive it is
// built on (purge/soft_purge + the two-version reload) is what this slice
// proves; the orchestration layer is left honestly unimplemented.
// ============================================================================

/// The OTP `code:load_binary/3` result shape, restricted to the two outcomes the
/// two-version model produces: a successful (re)load → `{module, Module}`, or a
/// refused third load while old code is unpurged → `{error, not_purged}`.
pub const LoadResult = enum { module, not_purged };

/// `code:load_binary/3` (two-version half) — commit `prog` as the new current
/// version of `name`. A reload rotates the prior current to `old`; a THIRD
/// (re)load while an unpurged `old` still occupies the second slot is REFUSED
/// as `{error, not_purged}` (the OTP contract, oracle-pinned), leaving the
/// table untouched. Denotes `code_index.load`, mapping its two-version limit
/// error onto the OTP term shape.
pub fn loadBinary(idx: *CodeIndex, name: []const u8, prog: ia.Program) !LoadResult {
    idx.load(name, prog) catch |e| switch (e) {
        error.OldCodeExists => return .not_purged,
        else => return e,
    };
    return .module;
}

/// `code:purge/1` — force-purge old code, killing any lingering process.
/// Returns whether a process WAS killed (oracle-pinned). Denotes
/// `code_index.purgeForce`.
pub fn purge(idx: *CodeIndex, name: []const u8) bool {
    return idx.purgeForce(name);
}

/// `code:soft_purge/1` — purge old code only if no process lingers on it.
/// Returns true unless a process still runs old code (oracle-pinned). Denotes
/// `code_index.softPurge`.
pub fn softPurge(idx: *CodeIndex, name: []const u8) bool {
    return idx.softPurge(name);
}

// ============================================================================
// Laws
// ============================================================================

const prog_x: ia.Program = &.{
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } },
    .{ .halt = .{ .src = .{ .x = 0 } } },
};
const prog_y: ia.Program = &.{
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 2 }, .dst = 0 } },
    .{ .halt = .{ .src = .{ .x = 0 } } },
};
const prog_empty: ia.Program = &.{};

test "LAW E5.2b code-server: STAGED≡DIRECT + REJECTION + METADATA round-trip" {
    const gpa = std.testing.allocator;

    // REJECTION: an empty program is not preparable (totality, no panic).
    try std.testing.expectError(error.EmptyProgram, prepareLoading("m", prog_empty, null, undefined));

    // METADATA round-trip: the md5 survives prepare unchanged.
    const md5 = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    const prep = try prepareLoading("m", prog_x, null, md5);
    try std.testing.expectEqualSlices(u8, &md5, &md5Of(prep));

    // STAGED≡DIRECT: staged prepare->finish lands the SAME current version a
    // direct code_index.load would (dynamic≡static homomorphism).
    var staged = CodeIndex.init(gpa);
    defer staged.deinit();
    try finishLoading(&staged, prep);

    var direct = CodeIndex.init(gpa);
    defer direct.deinit();
    try direct.load("m", prog_x);

    // Both resolve to the SAME program pointer (the prepared image), and neither
    // has old code — observationally identical tables.
    try std.testing.expectEqual(direct.resolve("m").?.ptr, staged.resolve("m").?.ptr);
    try std.testing.expect(!staged.checkOldCode("m") and !direct.checkOldCode("m"));
}

test "LAW E5.2b code-server: ON_LOAD GATE (commit on ok, atomic rollback on failure)" {
    const gpa = std.testing.allocator;
    var idx = CodeIndex.init(gpa);
    defer idx.deinit();

    // A staged image WITH an on_load entry.
    const prep = try prepareLoading("m", prog_x, 0, undefined);
    try std.testing.expect(hasOnLoad(prep));

    // GATE, ok=false: the on_load failed -> rollback, the module never appears.
    try finishAfterOnLoad(&idx, prep, false);
    try std.testing.expect(idx.resolve("m") == null);
    try std.testing.expect(!idx.checkOldCode("m"));

    // GATE, ok=true: commit -> the module is now current.
    try finishAfterOnLoad(&idx, prep, true);
    try std.testing.expect(idx.resolve("m") != null);

    // A staged image WITHOUT on_load gates nothing.
    const prep2 = try prepareLoading("n", prog_y, null, undefined);
    try std.testing.expect(!hasOnLoad(prep2));
}

test "LAW E5.2c code-server: LIVE-RELOAD two-version safety + purge-refused-while-held (end-to-end)" {
    const gpa = std.testing.allocator;
    var idx = CodeIndex.init(gpa);
    defer idx.deinit();

    // A full RELOAD cycle through the code server: stage+finish v1, then a live
    // process enters it, then stage+finish v2 (v1 becomes `old`), then PURGE.
    try finishLoading(&idx, try prepareLoading("m", prog_x, null, undefined)); // v1 current
    var held = idx.hold("m").?; // a process executing v1 holds a continuation
    try finishLoading(&idx, try prepareLoading("m", prog_y, null, undefined)); // v2 current, v1 old

    // RELOAD HOMOMORPHISM: after the reload the CURRENT version is v2 (prog_y);
    // resolve() denotes exactly a direct code_index.load of the same sequence.
    var direct = CodeIndex.init(gpa);
    defer direct.deinit();
    try direct.load("m", prog_x);
    try direct.load("m", prog_y);
    try std.testing.expectEqual(direct.resolve("m").?.ptr, idx.resolve("m").?.ptr);

    // PURGE-REFUSED-WHILE-HELD: a purge of the old version is refused at the code-
    // server surface while the live reference is held (the erts rule) — the
    // NAMED error, never a silent drop, never a panic.
    try std.testing.expectError(error.ProcessesHoldOldCode, purgeModule(&idx, "m"));
    // check_old_code still observes the retired version (it is NOT gone).
    try std.testing.expect(idx.checkOldCode("m"));

    // Release the continuation → purge succeeds → the old version is gone.
    held.release();
    try purgeModule(&idx, "m");
    try std.testing.expect(!idx.checkOldCode("m"));
    // …and a fresh reload is admitted again (the two-version slot is free).
    try finishLoading(&idx, try prepareLoading("m", prog_x, null, undefined));
    try std.testing.expect(idx.checkOldCode("m")); // v2 retired to old again
}

test "LAW E5.2b code-server: TWO-VERSION SAFETY over the staged path" {
    const gpa = std.testing.allocator;
    var idx = CodeIndex.init(gpa);
    defer idx.deinit();

    try finishLoading(&idx, try prepareLoading("m", prog_x, null, undefined)); // current
    try finishLoading(&idx, try prepareLoading("m", prog_y, null, undefined)); // current+old
    // a THIRD staged finish while old exists is refused (M10 two-version limit).
    try std.testing.expectError(error.OldCodeExists, finishLoading(&idx, try prepareLoading("m", prog_x, null, undefined)));
}

test "LAW gap-hot-load-fs: two-version LOAD state machine (load→old→not_purged→purge→reload), oracle-pinned" {
    // The `code:load_binary/3` two-version contract as a small state machine,
    // every transition pinned byte-for-byte to the live OTP-30 oracle:
    //   S0 (no module)         --load-->        S1 {module}, no old
    //   S1 (current, no old)   --reload-->       S2 {module}, current→old
    //   S2 (current + old)     --load-->         {error, not_purged}  (REFUSED)
    //   S2 --soft_purge(true)--> S1 (old dropped) --load--> S2 again  (admitted)
    const gpa = std.testing.allocator;
    var idx = CodeIndex.init(gpa);
    defer idx.deinit();

    // S0 → S1: first load is {module}, no old code yet.
    try std.testing.expectEqual(LoadResult.module, try loadBinary(&idx, "m", prog_x));
    try std.testing.expect(!idx.checkOldCode("m"));

    // S1 → S2: a reload rotates current → old (check_old_code becomes true).
    try std.testing.expectEqual(LoadResult.module, try loadBinary(&idx, "m", prog_y));
    try std.testing.expect(idx.checkOldCode("m"));

    // S2: a THIRD load without purging the old version is REFUSED as
    // {error, not_purged} — the table is untouched, old still present.
    try std.testing.expectEqual(LoadResult.not_purged, try loadBinary(&idx, "m", prog_x));
    try std.testing.expect(idx.checkOldCode("m"));

    // S2 → S1: soft_purge (no process on old) removes old and returns true.
    try std.testing.expect(softPurge(&idx, "m"));
    try std.testing.expect(!idx.checkOldCode("m"));

    // S1 → S2: with the slot free, the reload is admitted again ({module}).
    try std.testing.expectEqual(LoadResult.module, try loadBinary(&idx, "m", prog_x));
    try std.testing.expect(idx.checkOldCode("m"));
}

test "LAW gap-hot-load-fs: purge/soft_purge return-value truth table (byte-EQ vs live erl oracle)" {
    // The full oracle-pinned truth table for the two library purge surfaces. Each
    // row is a state (absent / old-absent / old+no-proc / old+proc) crossed with
    // the two ops; the boolean is the EXACT value `code:purge/1` /
    // `code:soft_purge/1` return on the pinned OTP-30 `erl`.
    const gpa = std.testing.allocator;

    // --- ABSENT module: purge=false, soft_purge=true ---
    {
        var idx = CodeIndex.init(gpa);
        defer idx.deinit();
        try std.testing.expect(!purge(&idx, "m")); //  code:purge(absent)     -> false
        try std.testing.expect(softPurge(&idx, "m")); // code:soft_purge(absent) -> true
    }

    // --- LOADED, NO OLD: purge=false (no-op), soft_purge=true (no-op) ---
    {
        var idx = CodeIndex.init(gpa);
        defer idx.deinit();
        _ = try loadBinary(&idx, "m", prog_x);
        try std.testing.expect(!purge(&idx, "m"));
        try std.testing.expect(idx.resolve("m") != null); // current untouched
        try std.testing.expect(softPurge(&idx, "m"));
        try std.testing.expect(idx.resolve("m") != null);
    }

    // --- OLD present, NO process on it: purge=false BUT removes old;
    //     soft_purge=true and removes old ---
    {
        var idx = CodeIndex.init(gpa);
        defer idx.deinit();
        _ = try loadBinary(&idx, "m", prog_x);
        _ = try loadBinary(&idx, "m", prog_y); // current→old, no holder
        try std.testing.expect(idx.checkOldCode("m"));
        // code:purge/1 returns false (no process killed) yet STILL drops old.
        try std.testing.expect(!purge(&idx, "m"));
        try std.testing.expect(!idx.checkOldCode("m"));

        // rebuild the old-present state for the soft_purge row.
        _ = try loadBinary(&idx, "m", prog_x); // current→old again
        try std.testing.expect(idx.checkOldCode("m"));
        try std.testing.expect(softPurge(&idx, "m")); // true, drops old
        try std.testing.expect(!idx.checkOldCode("m"));
    }

    // --- OLD present, a process LINGERING on it (holders>0) ---
    {
        // soft_purge: must REFUSE (false), leave old in place, kill NOTHING.
        var idx = CodeIndex.init(gpa);
        defer idx.deinit();
        _ = try loadBinary(&idx, "m", prog_x);
        var held = idx.hold("m").?; // a process enters v1
        _ = try loadBinary(&idx, "m", prog_y); // v1 → old, still held
        try std.testing.expect(!softPurge(&idx, "m")); // refused: process on old
        try std.testing.expect(idx.checkOldCode("m")); // old LEFT in place
        try std.testing.expectEqual(@as(u32, 1), held.version.holders); // not killed
        held.release();
        // now no process lingers → soft_purge succeeds.
        try std.testing.expect(softPurge(&idx, "m"));
        try std.testing.expect(!idx.checkOldCode("m"));
    }
    {
        // code:purge/1: KILLS the lingering process → returns TRUE, drops old.
        // (After purgeForce the held version is dead by contract — never deref
        // it, exactly as a killed process would never resume.)
        var idx = CodeIndex.init(gpa);
        defer idx.deinit();
        _ = try loadBinary(&idx, "m", prog_x);
        var held = idx.hold("m").?;
        _ = &held; // held is a killed continuation after the force-purge below
        _ = try loadBinary(&idx, "m", prog_y); // v1 → old, held
        try std.testing.expect(purge(&idx, "m")); // true: a process was killed
        try std.testing.expect(!idx.checkOldCode("m")); // old removed
        // purge again with nothing to kill → false.
        try std.testing.expect(!purge(&idx, "m"));
    }
}

test "LAW E6.3 purge two-version safety, RUNTIME-driven (system-process layer) + litarea conservation" {
    // E6.3 (DIVERGENCE 108, amending 75/81): the M10 PURGE-SAFETY law restated at
    // the erts_code_purger SYSTEM-PROCESS layer. `erts_internal:purge_module/2` is
    // RESTRICTED to the boot-spawned purger (boot.zig), a `system=true` process
    // whose LIVENESS across a supervision-tree crash is proven by proc.zig's
    // no-kill-cascade law; this law proves the purge it drives is SAFE: a live
    // continuation into the retired `old` version REFUSES the purge, and the copy
    // the literal-area collector coordinates CONSERVES every live denotation.
    const gpa = std.testing.allocator;
    var idx = CodeIndex.init(gpa);
    defer idx.deinit();

    // v1 current; a running process ENTERS it (holds a continuation).
    try finishLoading(&idx, try prepareLoading("m", prog_x, null, undefined));
    const v1_denote = idx.resolve("m").?.ptr; // denote(current) == prog_x
    var held = idx.hold("m").?;
    // reload → v2 current, v1 retired to old (still referenced by `held`).
    try finishLoading(&idx, try prepareLoading("m", prog_y, null, undefined));
    const v2_denote = idx.resolve("m").?.ptr; // denote(current) == prog_y

    // PURGE-SAFETY (RUNTIME-driven): the purger REFUSES to drop old while the
    // continuation is held — the M10 rule, now the purger system process's job.
    try std.testing.expectError(error.ProcessesHoldOldCode, purgeModule(&idx, "m"));

    // LITAREA CONSERVATION: the refused purge (a literal-area copy round) leaves
    // `denote` of BOTH live versions byte-for-byte unchanged — resolve(current)
    // still denotes prog_y, and the held old version still denotes prog_x. The
    // retiring area's referenced literals are conserved, never corrupted mid-copy.
    try std.testing.expectEqual(v2_denote, idx.resolve("m").?.ptr);
    try std.testing.expect(idx.checkOldCode("m")); // old (prog_x) survives intact
    try std.testing.expect(v1_denote != v2_denote); // the two versions are distinct

    // The collector completes (the holder releases) → the purger's purge succeeds,
    // and denote(current) is STILL conserved (only the dead old area is released).
    held.release();
    try purgeModule(&idx, "m");
    try std.testing.expectEqual(v2_denote, idx.resolve("m").?.ptr);
    try std.testing.expect(!idx.checkOldCode("m"));
}
