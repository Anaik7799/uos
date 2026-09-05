//! # bifs/file — the `prim_file:`/`file:` native-name codec BIF family (E4.4)
//!
//! ## Signature
//! Same contract as every other family module: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term`. Wired to
//! `unicode.zig` (M9 — `encodeCp`/`decodeCp`/`normalizeUtf8`, the strict UTF-8
//! codec) over the FILENAME domain.
//!
//! ## Scope — the pin's ACTUAL `prim_file:`/`file:` bif.tab rows
//! Grepping the pinned `bif.tab` shows EXACTLY FIVE rows across these two
//! modules, and ALL FIVE are the native-name codec (not file I/O):
//!   - `prim_file:internal_name2native/1`   — Name (charlist|binary) → native binary
//!   - `prim_file:internal_native2name/1`   — native binary → Name (charlist)
//!   - `prim_file:internal_normalize_utf8/1`— UTF-8 binary → normalized charlist
//!   - `prim_file:is_translatable/1`        — binary → bool (valid in native enc?)
//!   - `file:native_name_encoding/0`        → the atom `utf8` (this host's locale)
//! The real FILE OPERATIONS (`open`/`read`/`write`/`read_file`/`write_file`/…)
//! are NOT bif.tab BIFs on this pin — they are the `prim_file` NIF/driver
//! surface `file.erl` rides, with NO ledger row. That algebra lives in
//! `src/prim_file.zig` (the Stratum-C real-fd seam); this module is only the
//! codec BIFs, the honestly call_ext-reachable EQ flips (DIVERGENCE entry 36).
//!
//! ## Native encoding — the `utf8` path (documented bound)
//! `file:native_name_encoding()` is `utf8` on this Linux/UTF-8-locale host (and
//! the overwhelming common case on modern systems). The `latin1` encoding —
//! selected only by `+fnl` or a non-UTF-8 locale (chiefly legacy/Windows) — is
//! NOT modeled: every codec here assumes UTF-8, matching the pinned host oracle.
//! A future locale-parametric slice would add the latin1 arm; until then the
//! bounding laws below assert the utf8-encoding behavior only.
//!
//! ## Observed oracle semantics (pinned empirically on the OTP host)
//!   - `internal_name2native(Name)` UTF-8-encodes each codepoint of a charlist
//!     (or passes a binary's bytes through as already-native) and APPENDS a NUL
//!     terminator: `"abc" → <<97,98,99,0>>`, `[955,956] → <<206,187,206,188,0>>`,
//!     `"" → <<0>>`. A non-list/non-binary, an improper list, or a bad codepoint
//!     element → `badarg`.
//!   - `internal_native2name(Bin)` DECODES the bytes as UTF-8 to a codepoint list
//!     and does NOT strip a trailing NUL (NUL decodes to codepoint 0), so the
//!     round-trip APPENDS a 0: `native2name(name2native("abc")) == [97,98,99,0]`.
//!     Invalid UTF-8 → `{error, warning}` (a tuple, NOT badarg); non-binary →
//!     badarg.
//!   - `internal_normalize_utf8(Bin)` validates strict UTF-8 and returns the
//!     (NFC-normalized) codepoint list; invalid UTF-8 or a non-binary → badarg.
//!   - `is_translatable(Bin)` is `true` iff `Bin` is valid in the native
//!     encoding (valid UTF-8); a non-binary → badarg.
//!
//! ## Laws (see the suite below)
//!   - NAME-CODEC ROUND-TRIP: `native2name(name2native(N)) == N ++ [0]` for every
//!     valid name N (the NUL-append is the pinned oracle behavior, not an
//!     idealized identity).
//!   - ENCODING: `native_name_encoding() == utf8` (matches the host oracle).
//!   - ERROR TOTALITY: a bad codepoint / non-binary / invalid UTF-8 yields
//!     `badarg` or `{error,warning}` — never a panic.
//!   - IS-TRANSLATABLE: `true` iff valid UTF-8; non-binary → badarg.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const uni = @import("../unicode.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

fn atomByName(m: *Machine, name: []const u8) BifError!Term {
    const idx = m.ctx.atoms.intern(name) catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

fn boolTerm(m: *Machine, cond: bool) Term {
    return FinalTerms.atom(&m.ctx, if (cond) m.bool_true else m.bool_false);
}

/// Build a codepoint list term from a slice of already-validated codepoints.
fn cpsToList(m: *Machine, cps: []const u21) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var k = cps.len;
    while (k > 0) {
        k -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, cps[k]), acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// `file:native_name_encoding/0` — the atom `utf8` on this host (see the module
/// doc comment's encoding bound).
pub fn native_name_encoding_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return atomByName(m, "utf8");
}

/// `prim_file:internal_name2native/1` — Name (charlist of codepoints, or a
/// binary of already-native bytes) → a NUL-terminated native binary.
pub fn internal_name2native_1(m: *Machine, args: []const Term) BifError!Term {
    const name = args[0];
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(m.gpa);

    switch (FinalTerms.kindOf(&m.ctx, name)) {
        .binary => {
            // A binary is already native (UTF-8) bytes; pass them through.
            const bytes = FinalTerms.binBytes(&m.ctx, name);
            out.appendSlice(m.gpa, bytes) catch return error.OutOfMemory;
        },
        .nil => {}, // "" → <<0>>
        .cons => {
            var cur = name;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (!FinalTerms.repIsSmall(h)) return error.Badarg;
                const v = FinalTerms.smallValOf(h);
                if (v < 0 or v > 0x10FFFF or (v >= 0xD800 and v <= 0xDFFF)) return error.Badarg;
                var buf: [4]u8 = undefined;
                const n = uni.encodeCp(@intCast(v), &buf) catch return error.Badarg;
                out.appendSlice(m.gpa, buf[0..n]) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            // An improper list (non-nil tail) is not a valid name.
            if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
        },
        else => return error.Badarg,
    }

    out.append(m.gpa, 0) catch return error.OutOfMemory; // NUL terminator
    return FinalTerms.binary(&m.ctx, out.items) catch error.OutOfMemory;
}

/// `prim_file:internal_native2name/1` — a native (UTF-8) binary → a codepoint
/// list. Trailing NUL is NOT stripped (it decodes to codepoint 0). Invalid
/// UTF-8 → `{error, warning}` (a tuple, not badarg — the pinned oracle shape).
pub fn internal_native2name_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    // Dupe off-heap: the `cons`/`tuple`/`atom` builds below can grow ctx.words
    // and dangle the `binBytes` slice (the E2.5+ lifetime lesson).
    const owned = m.gpa.dupe(u8, FinalTerms.binBytes(&m.ctx, args[0])) catch return error.OutOfMemory;
    defer m.gpa.free(owned);

    var cps: std.ArrayList(u21) = .empty;
    defer cps.deinit(m.gpa);
    var pos: usize = 0;
    while (pos < owned.len) {
        const r = uni.decodeCp(owned[pos..]) catch {
            // Invalid native bytes → {error, warning} (the pinned oracle shape).
            const err_atom = try atomByName(m, "error");
            const warn_atom = try atomByName(m, "warning");
            return FinalTerms.tuple(&m.ctx, &.{ err_atom, warn_atom }) catch error.OutOfMemory;
        };
        cps.append(m.gpa, r.cp) catch return error.OutOfMemory;
        pos += r.len;
    }
    return cpsToList(m, cps.items);
}

/// `prim_file:internal_normalize_utf8/1` — a UTF-8 binary → the (NFC-normalized)
/// codepoint list. Invalid UTF-8 or a non-binary → badarg.
pub fn internal_normalize_utf8_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    const src = m.gpa.dupe(u8, FinalTerms.binBytes(&m.ctx, args[0])) catch return error.OutOfMemory;
    defer m.gpa.free(src);
    // NFC-normalize over unicode.zig's canonical slice, then decode to a list.
    const norm = uni.normalizeUtf8(m.gpa, src, .nfc) catch return error.Badarg;
    defer m.gpa.free(norm);

    var cps: std.ArrayList(u21) = .empty;
    defer cps.deinit(m.gpa);
    var pos: usize = 0;
    while (pos < norm.len) {
        const r = uni.decodeCp(norm[pos..]) catch return error.Badarg;
        cps.append(m.gpa, r.cp) catch return error.OutOfMemory;
        pos += r.len;
    }
    return cpsToList(m, cps.items);
}

/// `prim_file:is_translatable/1` — `true` iff the binary is valid in the native
/// (UTF-8) encoding. A non-binary → badarg.
pub fn is_translatable_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    const bytes = FinalTerms.binBytes(&m.ctx, args[0]);
    var pos: usize = 0;
    while (pos < bytes.len) {
        const r = uni.decodeCp(bytes[pos..]) catch return boolTerm(m, false);
        pos += r.len;
    }
    return boolTerm(m, true);
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;

fn expectAtomName(m: *Machine, w: Term, want: []const u8) !void {
    try std.testing.expect(FinalTerms.repIsAtom(w));
    try std.testing.expectEqualStrings(want, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(w)));
}

fn listOfCps(m: *Machine, cps: []const u21) !Term {
    var acc = FinalTerms.nil(&m.ctx);
    var k = cps.len;
    while (k > 0) {
        k -= 1;
        acc = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, cps[k]), acc);
    }
    return acc;
}

fn collectCps(m: *Machine, list: Term, buf: *std.ArrayList(u21)) !void {
    var cur = list;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        try std.testing.expect(FinalTerms.repIsSmall(h));
        try buf.append(m.gpa, @intCast(FinalTerms.smallValOf(h)));
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
}

test "LAW E4.4 native_name_encoding/0 is utf8 (matches the host oracle)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    try expectAtomName(&m, try native_name_encoding_0(&m, &.{}), "utf8");
}

test "LAW E4.4 name-codec ROUND-TRIP: native2name(name2native(N)) == N ++ [0]" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // ASCII + Latin-1 + Greek + supplementary-plane, the four UTF-8 width classes.
    const names = [_][]const u21{
        &.{ 'a', 'b', 'c' },
        &.{},
        &.{ 65, 233, 945, 66560 },
    };
    for (names) |cps| {
        const name = try listOfCps(&m, cps);
        const native = try internal_name2native_1(&m, &.{name});
        // name2native NUL-terminates: last byte is 0.
        const nbytes = FinalTerms.binBytes(&m.ctx, native);
        try std.testing.expect(nbytes.len >= 1 and nbytes[nbytes.len - 1] == 0);

        const back = try internal_native2name_1(&m, &.{native});
        var got: std.ArrayList(u21) = .empty;
        defer got.deinit(gpa);
        try collectCps(&m, back, &got);
        // Expected: the original codepoints followed by the NUL codepoint 0.
        try std.testing.expectEqual(cps.len + 1, got.items.len);
        for (cps, 0..) |c, i| try std.testing.expectEqual(c, got.items[i]);
        try std.testing.expectEqual(@as(u21, 0), got.items[cps.len]);
    }
}

test "LAW E4.4 name2native passes a binary's bytes through + NUL-terminates" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, "abc");
    const native = try internal_name2native_1(&m, &.{bin});
    try std.testing.expect(std.mem.eql(u8, &.{ 'a', 'b', 'c', 0 }, FinalTerms.binBytes(&m.ctx, native)));
}

test "LAW E4.4 normalize_utf8 decodes a valid UTF-8 binary to codepoints" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // λμ in UTF-8 → [955, 956].
    const bin = try FinalTerms.binary(&m.ctx, &.{ 0xCE, 0xBB, 0xCE, 0xBC });
    const list = try internal_normalize_utf8_1(&m, &.{bin});
    var got: std.ArrayList(u21) = .empty;
    defer got.deinit(gpa);
    try collectCps(&m, list, &got);
    try std.testing.expectEqualSlices(u21, &.{ 955, 956 }, got.items);
}

test "LAW E4.4 is_translatable: true iff valid UTF-8; error totality (never a panic)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const good = try FinalTerms.binary(&m.ctx, &.{ 0xCE, 0xBB }); // λ
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try is_translatable_1(&m, &.{good})));
    const bad = try FinalTerms.binary(&m.ctx, &.{ 0xFF, 0xFE });
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try is_translatable_1(&m, &.{bad})));

    // Non-binary args are a total badarg across the family (never a panic).
    const int_arg = FinalTerms.int(&m.ctx, 123);
    try std.testing.expectError(error.Badarg, is_translatable_1(&m, &.{int_arg}));
    try std.testing.expectError(error.Badarg, internal_name2native_1(&m, &.{int_arg}));
    try std.testing.expectError(error.Badarg, internal_native2name_1(&m, &.{int_arg}));
    try std.testing.expectError(error.Badarg, internal_normalize_utf8_1(&m, &.{int_arg}));

    // Invalid UTF-8 → normalize badarg; native2name {error,warning} (not badarg).
    const badbin = try FinalTerms.binary(&m.ctx, &.{0xFF});
    try std.testing.expectError(error.Badarg, internal_normalize_utf8_1(&m, &.{badbin}));
    const n2n = try internal_native2name_1(&m, &.{badbin});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, n2n) == .tuple);
    try expectAtomName(&m, FinalTerms.tupleElem(&m.ctx, n2n, 0), "error");
    try expectAtomName(&m, FinalTerms.tupleElem(&m.ctx, n2n, 1), "warning");
}


/// e49-wire-real-file-io: `file:read_file/1` — a file.erl LIBRARY wrapper over
/// the prim_file driver; here it traps `.file_read` to the Vm's proven fd seam.
/// → {ok, Binary} | {error, Reason}.
pub fn read_file_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_read = .{ .path = args[0] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the result to x0
}

/// e49-wire-real-file-io: `file:write_file/2` — traps `.file_write`.
/// → ok | {error, Reason}.
pub fn write_file_2(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_write = .{ .path = args[0], .data = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// gap-real-file-io: `file:list_dir/1` — traps `.file_list_dir` to the proven
/// prim_file dir seam. → {ok, [Name]} | {error, Reason}.
pub fn list_dir_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_list_dir = .{ .path = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

/// gap-real-file-io: `file:read_file_info/1` — traps `.file_read_file_info` to
/// the proven prim_file stat seam. → {ok, #file_info{}} | {error, Reason}.
pub fn read_file_info_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_read_file_info = .{ .path = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

// ── gap-file-handle-io: the LIVE-Fd handle API (file.erl wrappers over prim_file) ──
// Each traps to the Vm's RunFd table (proc.zig doFile{Open,Pread,Pwrite,Close}) —
// the gen_udp name-dispatch precedent. IoDevice = {file_descriptor, prim_file, N}.

/// `file:open(Path, Modes)` → `{ok, IoDevice}` | `{error, Reason}`. Modes is a
/// proper list (`[read,write,raw,binary,append,...]`).
pub fn open_2(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_open = .{ .path = args[0], .modes = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// `file:pread(IoDevice, Location, Number)` → `{ok, Data}` | `eof` | `{error, R}`.
pub fn pread_3(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_pread = .{ .fd = args[0], .pos = args[1], .len = args[2] } };
    return FinalTerms.nil(&m.ctx);
}

/// `file:pwrite(IoDevice, Location, Bytes)` → `ok` | `{error, Reason}`.
pub fn pwrite_3(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_pwrite = .{ .fd = args[0], .pos = args[1], .data = args[2] } };
    return FinalTerms.nil(&m.ctx);
}

/// `file:close(IoDevice)` → `ok` (idempotent).
pub fn close_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_close = .{ .fd = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

// ── gap-file-seq-io: the SEQUENTIAL fd surface ──

/// `file:read(IoDevice, Number)` → `{ok, Data}` | `eof` | `{error, R}`. Reads at
/// the tracked offset and ADVANCES it.
pub fn read_2(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_read_seq = .{ .fd = args[0], .len = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// `file:write(IoDevice, Bytes)` → `ok` | `{error, R}`. Writes at the tracked
/// offset and ADVANCES it (sequential append within one handle).
pub fn write_2(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_write_seq = .{ .fd = args[0], .data = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// `file:position(IoDevice, Location)` → `{ok, NewPos}` | `{error, R}`.
/// Location = Integer | bof|cur|eof | {bof|cur|eof, Offset}.
pub fn position_2(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_position = .{ .fd = args[0], .loc = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// `file:read_file_info(Path, Opts)` → `{ok, #file_info{}}` | `{error, R}`. Opts
/// carries `{time, posix|local|universal}`.
pub fn read_file_info_2(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_read_info_opts = .{ .path = args[0], .opts = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

// ── gap-file-fs-mutation: the filesystem-mutation surface ──

/// `file:delete(Path)` → `ok` | `{error, R}`.
pub fn delete_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_delete = .{ .path = args[0] } };
    return FinalTerms.nil(&m.ctx);
}
/// `file:rename(From, To)` → `ok` | `{error, R}`.
pub fn rename_2(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_rename = .{ .from = args[0], .to = args[1] } };
    return FinalTerms.nil(&m.ctx);
}
/// `file:make_dir(Dir)` → `ok` | `{error, eexist|...}`.
pub fn make_dir_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_make_dir = .{ .path = args[0] } };
    return FinalTerms.nil(&m.ctx);
}
/// `file:del_dir(Dir)` → `ok` | `{error, R}`.
pub fn del_dir_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_del_dir = .{ .path = args[0] } };
    return FinalTerms.nil(&m.ctx);
}
/// `file:truncate(IoDevice)` → `ok` | `{error, R}` (truncates at the tracked pos).
pub fn truncate_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_truncate = .{ .fd = args[0] } };
    return FinalTerms.nil(&m.ctx);
}
/// `file:sync(IoDevice)` → `ok` | `{error, R}`.
pub fn sync_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_sync = .{ .fd = args[0] } };
    return FinalTerms.nil(&m.ctx);
}
/// `file:read_link_info(Path[, Opts])` → `{ok, #file_info{}}` | `{error, R}`
/// (lstat — a symlink reports type=symlink).
pub fn read_link_info_1(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_read_link_info = .{ .path = args[0], .opts = FinalTerms.nil(&m.ctx) } };
    return FinalTerms.nil(&m.ctx);
}
pub fn read_link_info_2(m: *ia.Machine, args: []const Term) ia.BifError!Term {
    m.pending = .{ .file_read_link_info = .{ .path = args[0], .opts = args[1] } };
    return FinalTerms.nil(&m.ctx);
}
