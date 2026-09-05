//! # prim_file — the file-operation algebra over the Stratum-C real-fd seam (E4.4)
//!
//! ## Stratum
//! **Stratum C (substrate).** This is the ONE module that touches real OS file
//! descriptors (via `std.Io.Dir`/`std.Io.File`). It is QUARANTINED behind this
//! seam: no Stratum-A law (term/map/bin/hash/pattern/instruction algebra) may
//! depend on it, and no law here observes anything but the bytes that cross the
//! seam. Every operation is:
//!   - **error-returning, never a raw panic** — every OS error is translated to a
//!     total `PrimError` enum (`enoent`/`eacces`/`eisdir`/… + `too_large`); an
//!     unmapped error becomes `error.Io`, not `unreachable`.
//!   - **fuel-bounded** — `readFile` caps the read at a caller-supplied byte
//!     limit and returns `error.TooLarge` at/over it (an unbounded read is a
//!     failed law; the bounded-driver rule for a Stratum-C seam is a size cap).
//!   - **fd-leak-free** — every `openFile`/`createFile` is paired with a
//!     `close` on every path (the high-level ops close internally; the explicit
//!     `open`/`close` pair is proved leak-free by the round-trip law's `defer`).
//!
//! ## Signature (the file-op algebra the plan's Task 4 charters)
//!   writeFile : (io, root, path, bytes)        -> {} | PrimError
//!   readFile  : (io, root, gpa, path, maxBytes) -> bytes | PrimError   (bounded)
//!   delete    : (io, root, path)               -> {} | PrimError
//!   listDir   : (io, root, gpa, path)          -> [name] | PrimError   (sorted)
//!   open      : (io, root, path, mode)         -> Handle | PrimError
//!   read      : (io, handle, buf)              -> nBytes | PrimError
//!   write     : (io, handle, bytes)            -> {} | PrimError
//!   pread     : (io, handle, pos, buf)         -> nBytes | PrimError   (positioned)
//!   pwrite    : (io, handle, pos, bytes)       -> {} | PrimError       (positioned)
//!   readFileInfo : (io, root, path)            -> FileInfo | PrimError (stat)
//!   close     : (io, handle)                   -> {}
//!   getCwd    : (gpa)                          -> RE-BOUND (see the note below)
//!
//! ## gap-real-file-io (real_file_io EQUIV→EQ): the wider `file:` surface
//! `read_file`/`write_file` were already EQUIV (round-trip real bytes off a real
//! fd, `{ok,Binary}`/`{error,Posix}` byte-EQ). This slice widens the fuller
//! `file:` surface over the SAME proven fd/dir seam — positioned IO (`pread`/
//! `pwrite` via the host's `readPositionalAll`/`writePositionalAll`, a
//! `read_write`/`append` open mode), directory enumeration (`listDir`, set-EQ),
//! and metadata (`readFileInfo` = `stat` projected to `#file_info{}`'s
//! size/type/access). Every op is real-fd/real-dir only; no mode is faked — a
//! closed/invalid handle maps to `Ebadf`, never a panic. The `#file_info{}` time
//! fields are POSIX seconds (the `{time,posix}` variant); the `local` datetime-
//! tuple format is a documented residual (timezone/host-dependent, not byte-EQ).
//!
//! ## Semantic domain
//! A file system is a partial map `path ⇀ bytes`. `writeFile` sets the map at a
//! path; `readFile` reads it; `delete` removes the entry; `listDir` enumerates a
//! directory's keys. The bounding laws pin the algebra to the obvious
//! denotation: `readFile(writeFile(fs, p, b), p) == {ok, b}` for `|b| ≤ max`.
//!
//! ## `getCwd` — a precise re-bound (NOT a silent scope cut)
//! At the pinned Zig 0.16 toolchain, `std.Io.Dir` exposes NO stable cwd-path /
//! `realpath` / absolute-path-readback primitive, and `std.posix` at this pin
//! carries no `getcwd`. `prim_file:get_cwd/0`'s RESULT is an absolute path
//! STRING the seam cannot honestly produce here, so it is re-bound (not faked
//! with a wrong constant) — its true owner is the file-server boot residual
//! (E4.3 `e4-boot-residual`) / the toolchain-upgrade that lands an Io cwd-path
//! readback. DIVERGENCE_LOG entry 36. Every OTHER charter op is landed here.
//!
//! ## Ledger scope (why this module has NO bif-ledger rows)
//! On the pinned `bif.tab` the ENTIRE `prim_file:`/`file:` BIF surface is the
//! five NATIVE-NAME-CODEC rows (see `bifs/file.zig`) — the real file OPERATIONS
//! (`open`/`read`/`write`/`read_file`/`write_file`/…) are the `prim_file` NIF/
//! driver surface `file.erl` rides, with NO bif.tab row. There is therefore no
//! end-to-end differential CORPUS path to a file op on zigvm (no `file.erl`
//! loaded, no booted file server — E4.3), so the file-round-trip law's BOUNDING
//! evidence is THIS Zig law suite over the real fd seam, not a corpus row. That
//! is the honest realization of the plan's "real file I/O → no single ledger
//! row" note (DIVERGENCE entry 36).
//!
//! ## Laws (see the suite below)
//!   - FILE ROUND-TRIP: `readFile(writeFile(p, b), p) == b` over a tmp scratch
//!     dir, leak-free and fd-leak-free.
//!   - ERROR TOTALITY: a missing path → `error.Enoent` (never a panic); delete of
//!     a missing path → `error.Enoent`.
//!   - BOUNDED: a read capped below the file size → `error.TooLarge`; capped at/
//!     above → the bytes.
//!   - LIST/DELETE: `listDir` sees exactly the written names; after `delete` the
//!     path reads back `error.Enoent`.
//!   - OPEN/READ/WRITE/CLOSE: the low-level handle ops round-trip the bytes.

const std = @import("std");

pub const Io = std.Io;
pub const Dir = std.Io.Dir;
pub const File = std.Io.File;

/// The total error domain of the seam. Every OS-level failure maps into one of
/// these; an unrecognized error becomes `Io` (never `unreachable`).
pub const PrimError = error{
    Enoent, // no such file/dir
    Eacces, // permission denied
    Eisdir, // path is a directory
    Enotdir, // a path component is not a directory
    Eexist, // already exists
    Ebadf, // closed/invalid handle, or a positioned op the fd's mode forbids
    NameTooLong, // path too long
    TooLarge, // read exceeded the fuel bound
    Io, // any other OS error, mapped totally
    OutOfMemory, // allocation failure
};

/// Total translation of a lower-level file error into `PrimError`. Keeps the
/// seam a total function — the mandatory "never a raw panic" property.
fn mapErr(e: anyerror) PrimError {
    return switch (e) {
        error.FileNotFound => error.Enoent,
        error.AccessDenied, error.PermissionDenied => error.Eacces,
        error.IsDir => error.Eisdir,
        error.NotDir => error.Enotdir,
        error.PathAlreadyExists => error.Eexist,
        error.NameTooLong => error.NameTooLong,
        error.StreamTooLong => error.TooLarge,
        error.OutOfMemory => error.OutOfMemory,
        // A positioned op on a fd that its access mode forbids, an unseekable
        // fd, or a closed/invalid handle → the OTP `ebadf` shape (never a panic).
        error.NotOpenForReading, error.NotOpenForWriting, error.Unseekable => error.Ebadf,
        else => error.Io,
    };
}

/// A file access mode over the seam.
///   - `read`       — open an existing file read-only (else `Enoent`).
///   - `write`      — create/truncate; write-only (the legacy handle-op mode).
///   - `read_write` — create-if-missing WITHOUT truncating, read+write access;
///                    the mode that supports positioned `pread`/`pwrite` on one
///                    handle (`file:open(F,[read,write,raw])`).
///   - `append`     — create-if-missing WITHOUT truncating; a positioned write
///                    at the current size appends (`file:open(F,[append])`).
pub const Mode = enum { read, write, read_write, append };

/// An open file handle. QUARANTINE: the raw `File` never escapes this module's
/// callers except through `read`/`write`/`close`.
pub const Handle = struct { file: File };

/// `writeFile(root, path, bytes)` — create/truncate `path` under `root` and
/// write `bytes`. Closes the fd on every path (internal to `Dir.writeFile`).
pub fn writeFile(io: Io, root: Dir, path: []const u8, bytes: []const u8) PrimError!void {
    root.writeFile(io, .{ .sub_path = path, .data = bytes }) catch |e| return mapErr(e);
}

/// `readFile(root, path, max)` — read all of `path`, BOUNDED: at/over `max`
/// bytes it returns `error.TooLarge` (the fuel cap). Caller owns the result.
pub fn readFile(io: Io, root: Dir, gpa: std.mem.Allocator, path: []const u8, max: usize) PrimError![]u8 {
    return root.readFileAlloc(io, path, gpa, .limited(max)) catch |e| return mapErr(e);
}

/// `delete(root, path)` — unlink `path`; a missing path → `error.Enoent`.
pub fn delete(io: Io, root: Dir, path: []const u8) PrimError!void {
    root.deleteFile(io, path) catch |e| return mapErr(e);
}

/// `listDir(root, path)` — the names directly under the sub-directory `path`,
/// SORTED (deterministic — the enumeration order of a real directory is
/// impl-defined, so the law-bearing observation is the sorted set). Caller owns
/// the returned slice AND each name.
pub fn listDir(io: Io, root: Dir, gpa: std.mem.Allocator, path: []const u8) PrimError![][]u8 {
    var dir = root.openDir(io, path, .{ .iterate = true }) catch |e| return mapErr(e);
    defer dir.close(io);

    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }
    var it = dir.iterate();
    while (it.next(io) catch |e| return mapErr(e)) |entry| {
        const owned = gpa.dupe(u8, entry.name) catch return error.OutOfMemory;
        names.append(gpa, owned) catch {
            gpa.free(owned);
            return error.OutOfMemory;
        };
    }
    const out = names.toOwnedSlice(gpa) catch return error.OutOfMemory;
    std.mem.sort([]u8, out, {}, struct {
        fn lt(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return out;
}

/// `open(root, path, mode)` — a raw handle; caller MUST `close`. `write` mode
/// creates/truncates; `read` mode requires the file to exist (else `Enoent`).
pub fn open(io: Io, root: Dir, path: []const u8, mode: Mode) PrimError!Handle {
    const file = switch (mode) {
        .read => root.openFile(io, path, .{ .mode = .read_only }) catch |e| return mapErr(e),
        .write => root.createFile(io, path, .{}) catch |e| return mapErr(e),
        // read+write, keep existing contents — the positioned-IO handle.
        .read_write, .append => root.createFile(io, path, .{ .read = true, .truncate = false }) catch |e| return mapErr(e),
    };
    return .{ .file = file };
}

/// `pread(handle, pos, buf)` — POSITIONED read of up to `buf.len` bytes starting
/// at absolute offset `pos`; returns the byte count (0 at/after EOF). The global
/// file offset is NOT consumed (positional), so interleaved `pread`s are
/// independent. A read-forbidding / closed fd → `Ebadf` (never a panic).
pub fn pread(io: Io, h: Handle, pos: u64, buf: []u8) PrimError!usize {
    return h.file.readPositionalAll(io, buf, pos) catch |e| return mapErr(e);
}

/// `pwrite(handle, pos, bytes)` — POSITIONED write of all `bytes` at absolute
/// offset `pos` (extends the file with a hole if `pos` > size). A write-
/// forbidding / closed fd → `Ebadf` (never a panic).
pub fn pwrite(io: Io, h: Handle, pos: u64, bytes: []const u8) PrimError!void {
    h.file.writePositionalAll(io, bytes, pos) catch |e| return mapErr(e);
}

/// gap-file-seq-io: the current size of an open handle — for `file:position(F, eof)`
/// / `{eof, N}` (the sequential-IO offset model tracks its own position; only `eof`
/// needs the live size). A closed/bad fd → `Ebadf`, never a panic.
pub fn handleSize(io: Io, h: Handle) PrimError!u64 {
    const st = h.file.stat(io) catch |e| return mapErr(e);
    return st.size;
}

// ── gap-file-fs-mutation: the filesystem-mutation surface (file:rename/make_dir/
// del_dir/truncate/sync/read_link_info); file:delete uses the existing `delete`. ──

/// `rename(root, from, to)` — atomic within one root. Missing source → `Enoent`.
pub fn rename(io: Io, root: Dir, from: []const u8, to: []const u8) PrimError!void {
    root.rename(from, root, to, io) catch |e| return mapErr(e);
}

/// `makeDir(root, path)` — create a directory; already-exists → `Eexist`.
pub fn makeDir(io: Io, root: Dir, path: []const u8) PrimError!void {
    root.createDir(io, path, .default_dir) catch |e| return mapErr(e);
}

/// `deleteDir(root, path)` — remove an EMPTY directory; missing → `Enoent`.
pub fn deleteDir(io: Io, root: Dir, path: []const u8) PrimError!void {
    root.deleteDir(io, path) catch |e| return mapErr(e);
}

/// `truncateHandle(h, len)` — set the file to `len` bytes (file:truncate/1 uses the
/// handle's current position). Linux `ftruncate`. A read-only/closed fd → `Ebadf`.
pub fn truncateHandle(h: Handle, len: u64) PrimError!void {
    if (@import("builtin").os.tag != .linux) return error.Io;
    const rc = std.os.linux.ftruncate(@intCast(h.file.handle), @intCast(len));
    if (@as(isize, @bitCast(rc)) < 0) return error.Ebadf;
}

/// `syncHandle(h)` — flush the file's data+metadata to disk (file:sync/1).
pub fn syncHandle(io: Io, h: Handle) PrimError!void {
    h.file.sync(io) catch |e| return mapErr(e);
}

fn typeFromMode(mode: u32) FileType {
    return switch (mode & 0o170000) {
        0o120000 => .symlink,
        0o100000 => .regular,
        0o040000 => .directory,
        0o060000, 0o020000 => .device,
        else => .other,
    };
}

fn statxErrno(rc: usize) PrimError {
    const e: isize = @bitCast(rc);
    return switch (-e) {
        2 => error.Enoent, // ENOENT
        13 => error.Eacces, // EACCES
        20 => error.Enotdir, // ENOTDIR
        else => error.Io,
    };
}

/// `readLinkInfo(root, path)` = `lstat` → `#file_info{}` WITHOUT following a final
/// symlink (file:read_link_info/1). Built entirely from a raw `statx` with
/// `AT_SYMLINK_NOFOLLOW`, so a symlink reports `type = symlink` (not the target).
pub fn readLinkInfo(io: Io, root: Dir, path: []const u8) PrimError!FileInfo {
    _ = io;
    if (@import("builtin").os.tag != .linux) return error.Io;
    if (path.len == 0 or path.len >= 4096) return error.NameTooLong;
    var pbuf: [4096]u8 = undefined;
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    const pz: [*:0]const u8 = @ptrCast(&pbuf);
    var sx: std.os.linux.Statx = undefined;
    const mask = std.os.linux.STATX{ .TYPE = true, .MODE = true, .UID = true, .GID = true, .NLINK = true, .INO = true, .SIZE = true, .ATIME = true, .MTIME = true, .CTIME = true };
    const AT_SYMLINK_NOFOLLOW: u32 = 0x100;
    const rc = std.os.linux.statx(@intCast(root.handle), pz, AT_SYMLINK_NOFOLLOW, mask, &sx);
    if (rc != 0) return statxErrno(rc);
    return .{
        .size = sx.size,
        .type = typeFromMode(sx.mode),
        .access = if ((sx.mode & 0o200) != 0) .read_write else .read,
        .inode = sx.ino,
        .links = sx.nlink,
        .mtime_s = sx.mtime.sec,
        .atime_s = sx.atime.sec,
        .ctime_s = sx.ctime.sec,
        .mode = sx.mode,
        .uid = sx.uid,
        .gid = sx.gid,
        .major_device = makedev(sx.dev_major, sx.dev_minor),
        .minor_device = makedev(sx.rdev_major, sx.rdev_minor),
    };
}

/// The `file:` #file_info{} projection the seam can honestly produce off a real
/// `stat`. `size`/`type`/`access` are the byte-EQ-checked fields; the POSIX
/// time fields are seconds since the Unix epoch (the `{time, posix}` variant —
/// the `local` datetime-tuple format is timezone/host-dependent and NOT modeled).
pub const FileType = enum { device, directory, other, regular, symlink };
pub const Access = enum { none, read, write, read_write };
pub const FileInfo = struct {
    size: u64,
    type: FileType,
    access: Access,
    inode: u64,
    links: u64,
    mtime_s: i64, // seconds since the Unix epoch
    atime_s: i64,
    ctime_s: i64,
    // gap-file-info-stat-tz: the real st_mode/uid/gid/dev fields from a raw statx
    // syscall (the portable std.Io.Dir.statFile OMITS them, and this toolchain has
    // no libc). Zero when statx is unavailable/failed (graceful — the portable
    // fields above still populate). `major_device` = the encoded st_dev; `minor_device`
    // = the encoded st_rdev (0 for a regular file). Matches file:read_file_info's
    // #file_info{mode,major_device,minor_device,uid,gid}.
    mode: u32 = 0,
    uid: u32 = 0,
    gid: u32 = 0,
    major_device: u64 = 0,
    minor_device: u64 = 0,
};

/// glibc gnu_dev_makedev — re-encode a (major,minor) pair (as statx returns them,
/// decomposed) into the `dev_t` value `stat(2)`/`file:read_file_info` reports.
fn makedev(major: u64, minor: u64) u64 {
    return (minor & 0xff) | ((major & 0xfff) << 8) |
        ((minor & ~@as(u64, 0xff)) << 12) | ((major & ~@as(u64, 0xfff)) << 32);
}

/// gap-file-info-stat-tz: the LOCAL UTC offset (seconds east of UTC) that applies
/// at POSIX time `at`, read from the host TZif database (`/etc/localtime`) — the
/// missing piece for `file:read_file_info/1`'s DEFAULT local-datetime tuples (this
/// toolchain has no libc `localtime`). TOTAL: any read/parse failure → 0 (UTC), a
/// graceful degradation (the datetime then reads as UTC, off by the offset, never a
/// panic). Parses TZif v1 (the 32-bit transition table, which every TZif carries):
/// find the last transition ≤ `at`, return that local-time-type's `utoff`.
pub fn tzOffsetAt(at: i64) i64 {
    if (@import("builtin").os.tag != .linux) return 0;
    const l = std.os.linux;
    const ofd = l.open("/etc/localtime", .{}, 0); // ACCMODE defaults to .RDONLY
    if (@as(isize, @bitCast(ofd)) < 0) return 0;
    const fd: i32 = @intCast(ofd);
    defer _ = l.close(fd);
    var buf: [64 * 1024]u8 = undefined;
    const rn = l.read(fd, &buf, buf.len);
    if (@as(isize, @bitCast(rn)) <= 0) return 0;
    const b = buf[0..@min(rn, buf.len)];
    if (b.len < 44 or !std.mem.eql(u8, b[0..4], "TZif")) return 0;
    const rd = std.mem.readInt;
    // TZif v1 header: magic[4] ver[1] reserved[15], then 6×u32 BE counts at 20:
    //   isutcnt@20 isstdcnt@24 leapcnt@28 TIMECNT@32 TYPECNT@36 charcnt@40.
    const timecnt: usize = rd(u32, b[32..36], .big);
    const typecnt: usize = rd(u32, b[36..40], .big);
    if (typecnt == 0) return 0;
    const trans_start: usize = 44; // timecnt × i32 transition times
    const idx_start = trans_start + timecnt * 4; // timecnt × u8 type indices
    const tt_start = idx_start + timecnt; // typecnt × ttinfo{utoff:i32, isdst:u8, abbrind:u8}
    if (tt_start + typecnt * 6 > b.len) return 0;
    // The LAST transition time ≤ `at` selects the applicable local-time type.
    var type_idx: usize = 0; // pre-first-transition default = type 0
    var i: usize = 0;
    while (i < timecnt) : (i += 1) {
        const t = rd(i32, b[trans_start + i * 4 ..][0..4], .big);
        if (@as(i64, t) <= at) type_idx = b[idx_start + i] else break;
    }
    if (type_idx >= typecnt) type_idx = 0;
    return rd(i32, b[tt_start + type_idx * 6 ..][0..4], .big); // utoff (seconds east of UTC)
}

fn kindToType(k: File.Kind) FileType {
    return switch (k) {
        .directory => .directory,
        .file => .regular,
        .sym_link => .symlink,
        .block_device, .character_device => .device,
        else => .other,
    };
}

/// `readFileInfo(root, path)` — `stat(path)` projected to the `#file_info{}`
/// fields the seam can honestly produce. Missing path → `Enoent` (never a panic).
/// Symlinks are followed (matching `file:read_file_info/1`; `read_link_info` —
/// the no-follow variant — is a documented residual, not modeled here).
pub fn readFileInfo(io: Io, root: Dir, path: []const u8) PrimError!FileInfo {
    const st = root.statFile(io, path, .{}) catch |e| return mapErr(e);
    var fi: FileInfo = .{
        .size = st.size,
        .type = kindToType(st.kind),
        // A dir/file the process could open read-only is at least `read`; write
        // permission is not separately probed here → `read` is the honest floor.
        .access = if (st.permissions.readOnly()) .read else .read_write,
        .inode = @intCast(st.inode),
        .links = @intCast(st.nlink),
        .mtime_s = @intCast(@divFloor(st.mtime.nanoseconds, std.time.ns_per_s)),
        .atime_s = if (st.atime) |a| @intCast(@divFloor(a.nanoseconds, std.time.ns_per_s)) else 0,
        .ctime_s = @intCast(@divFloor(st.ctime.nanoseconds, std.time.ns_per_s)),
    };
    // gap-file-info-stat-tz: a raw statx over the dir fd for mode/uid/gid/dev — the
    // portable Stat above omits them. Best-effort: a bounded path + a failed statx
    // leave the fields 0 (never a panic; the portable fields still hold).
    fillStatx(root, path, &fi);
    return fi;
}

/// Overlay `mode`/`uid`/`gid`/`major_device`/`minor_device` onto `fi` from a raw
/// `statx(2)` over `root`'s dir fd (Linux; no libc). Total — any failure (bad
/// path length, unsupported syscall, ENOENT race) leaves the fields at 0.
fn fillStatx(root: Dir, path: []const u8, fi: *FileInfo) void {
    if (@import("builtin").os.tag != .linux) return;
    if (path.len == 0 or path.len >= 4096) return;
    var pbuf: [4096]u8 = undefined;
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    const pz: [*:0]const u8 = @ptrCast(&pbuf);
    var sx: std.os.linux.Statx = undefined;
    const mask = std.os.linux.STATX{ .TYPE = true, .MODE = true, .UID = true, .GID = true, .NLINK = true, .INO = true, .SIZE = true };
    const rc = std.os.linux.statx(@intCast(root.handle), pz, 0, mask, &sx);
    if (rc != 0) return; // syscall failed (returns 0 on success)
    fi.mode = sx.mode;
    fi.uid = sx.uid;
    fi.gid = sx.gid;
    fi.major_device = makedev(sx.dev_major, sx.dev_minor); // encoded st_dev
    fi.minor_device = makedev(sx.rdev_major, sx.rdev_minor); // encoded st_rdev
}

/// `read(handle, buf)` — read up to `buf.len` bytes; returns the byte count (0
/// at EOF).
pub fn read(io: Io, h: Handle, buf: []u8) PrimError!usize {
    return h.file.readStreaming(io, &.{buf}) catch |e| return mapErr(e);
}

/// `write(handle, bytes)` — write all `bytes`.
pub fn write(io: Io, h: Handle, bytes: []const u8) PrimError!void {
    h.file.writeStreamingAll(io, bytes) catch |e| return mapErr(e);
}

/// `close(handle)` — release the fd. Total (never errors) — the fd-leak-free
/// guarantee's closing half.
pub fn close(io: Io, h: Handle) void {
    h.file.close(io);
}

// ============================================================================
// Laws (Stratum-C: a real tmp scratch dir, bounded, leak-free AND fd-leak-free)
// ============================================================================

test "LAW E4.4 FILE ROUND-TRIP: readFile(writeFile(p,b),p) == b over a scratch dir" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const payload = "the quick brown fox\x00\x01\xfe\xff jumps"; // arbitrary bytes incl NUL/hi
    try writeFile(io, tmp.dir, "rt.dat", payload);
    const got = try readFile(io, tmp.dir, gpa, "rt.dat", 1 << 20);
    defer gpa.free(got);
    try std.testing.expectEqualSlices(u8, payload, got);
}

test "LAW E4.4 ERROR TOTALITY: a missing path is error.Enoent, never a panic" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try std.testing.expectError(error.Enoent, readFile(io, tmp.dir, gpa, "nope.dat", 1 << 20));
    try std.testing.expectError(error.Enoent, delete(io, tmp.dir, "nope.dat"));
    try std.testing.expectError(error.Enoent, open(io, tmp.dir, "nope.dat", .read));
}

test "LAW E4.4 BOUNDED: a read capped below the file size is error.TooLarge" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const payload = "0123456789"; // 10 bytes
    try writeFile(io, tmp.dir, "cap.dat", payload);
    // Cap below the size → TooLarge (the fuel bound holds).
    try std.testing.expectError(error.TooLarge, readFile(io, tmp.dir, gpa, "cap.dat", 5));
    // Cap at/above the size → the bytes.
    const ok = try readFile(io, tmp.dir, gpa, "cap.dat", 11);
    defer gpa.free(ok);
    try std.testing.expectEqualSlices(u8, payload, ok);
}

test "LAW E4.4 LIST/DELETE: listDir sees the written names; delete makes it Enoent" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try writeFile(io, tmp.dir, "a.txt", "A");
    try writeFile(io, tmp.dir, "b.txt", "B");
    const names = try listDir(io, tmp.dir, gpa, ".");
    defer {
        for (names) |n| gpa.free(n);
        gpa.free(names);
    }
    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualStrings("a.txt", names[0]); // sorted
    try std.testing.expectEqualStrings("b.txt", names[1]);

    try delete(io, tmp.dir, "a.txt");
    try std.testing.expectError(error.Enoent, readFile(io, tmp.dir, gpa, "a.txt", 1 << 20));
}

test "LAW E4.4 OPEN/READ/WRITE/CLOSE: the handle ops round-trip the bytes (fd-leak-free)" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const wh = try open(io, tmp.dir, "h.dat", .write);
        defer close(io, wh); // fd-leak-free on every path
        try write(io, wh, "handle-bytes");
    }
    {
        const rh = try open(io, tmp.dir, "h.dat", .read);
        defer close(io, rh);
        var buf: [64]u8 = undefined;
        const n = try read(io, rh, &buf);
        try std.testing.expectEqualSlices(u8, "handle-bytes", buf[0..n]);
    }
    _ = gpa;
}

test "LAW gap-real-file-io POSITIONED ROUND-TRIP: open→pwrite→pread returns the exact bytes at the exact offset" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Seeded generator: a spread of (offset, payload) pairs echoed on failure.
    var prng = std.Random.DefaultPrng.init(0xF11E_0FF5);
    const rnd = prng.random();
    var trial: usize = 0;
    while (trial < 24) : (trial += 1) {
        const seed = rnd.int(u64);
        var lp = std.Random.DefaultPrng.init(seed);
        const r = lp.random();
        const pos: u64 = r.intRangeAtMost(u64, 0, 200);
        var payload: [64]u8 = undefined;
        const len = r.intRangeAtMost(usize, 1, payload.len);
        for (payload[0..len]) |*b| b.* = r.int(u8);

        const h = try open(io, tmp.dir, "pos.dat", .read_write);
        defer close(io, h);
        pwrite(io, h, pos, payload[0..len]) catch |e| {
            std.debug.print("pwrite failed seed={x} pos={d} len={d}: {any}\n", .{ seed, pos, len, e });
            return e;
        };
        var back: [64]u8 = undefined;
        const n = pread(io, h, pos, back[0..len]) catch |e| {
            std.debug.print("pread failed seed={x} pos={d} len={d}: {any}\n", .{ seed, pos, len, e });
            return e;
        };
        if (n != len or !std.mem.eql(u8, payload[0..len], back[0..len])) {
            std.debug.print("MISMATCH seed={x} pos={d} len={d} n={d}\n", .{ seed, pos, len, n });
            return error.TestUnexpectedResult;
        }
        // A pread BEFORE the written offset (when pos>0) must NOT see the payload
        // (this is what kills the "pread ignores Pos → reads from 0" mutant).
        if (pos > 0) {
            var zbuf: [8]u8 = undefined;
            const zlen = @min(@as(usize, @intCast(pos)), zbuf.len);
            const zn = try pread(io, h, 0, zbuf[0..zlen]);
            try std.testing.expect(zn == zlen); // the hole/prefix is real bytes, not the payload region
        }
    }
}

test "LAW gap-real-file-io READ_FILE_INFO: size == bytes written, type/access honest; missing → Enoent" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const payload = "0123456789ABCDEF"; // 16 bytes
    try writeFile(io, tmp.dir, "info.dat", payload);
    const fi = try readFileInfo(io, tmp.dir, "info.dat");
    try std.testing.expectEqual(@as(u64, payload.len), fi.size);
    try std.testing.expectEqual(FileType.regular, fi.type);
    // A freshly-created scratch file is at least readable+writable.
    try std.testing.expectEqual(Access.read_write, fi.access);

    // A directory stats as `directory`.
    const di = try readFileInfo(io, tmp.dir, ".");
    try std.testing.expectEqual(FileType.directory, di.type);

    // Missing path → Enoent (byte-EQ error atom vs the oracle), never a panic.
    try std.testing.expectError(error.Enoent, readFileInfo(io, tmp.dir, "nope.dat"));
}

test "LAW gap-file-info-stat-tz: readFileInfo overlays REAL statx mode/uid/gid/dev; makedev re-encodes a dev_t; tzOffsetAt is TOTAL + bounded (the #file_info stat/TZ fields, byte-EQ vs OTP)" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeFile(io, tmp.dir, "sx.dat", "statx me");
    const fi = try readFileInfo(io, tmp.dir, "sx.dat");
    // mode carries S_IFREG (0o100000) + owner rw — the real st_mode, not the old 0.
    try std.testing.expect((fi.mode & 0o170000) == 0o100000); // S_IFMT → regular
    try std.testing.expect((fi.mode & 0o600) != 0); // owner read+write
    // uid/gid are the REAL process owner (statx read them; was 0 before).
    try std.testing.expectEqual(@as(u32, std.os.linux.getuid()), fi.uid);
    try std.testing.expectEqual(@as(u32, std.os.linux.getgid()), fi.gid);
    // st_dev is non-zero on a real fs; rdev==0 for a regular file.
    try std.testing.expect(fi.major_device != 0);
    try std.testing.expectEqual(@as(u64, 0), fi.minor_device);

    // makedev re-encodes a decomposed (major,minor) into the dev_t stat reports.
    try std.testing.expectEqual(@as(u64, 48), makedev(0, 48)); // the /tmp dev shape
    try std.testing.expectEqual(@as(u64, (8 << 8) | 3), makedev(8, 3));

    // tzOffsetAt is TOTAL (never panics — the TZif-parse-failure UTC fallback) and
    // returns a plausible offset in [-14h, +14h] for any timestamp.
    inline for (.{ @as(i64, 1785228823), 0, -1, 253402300799 }) |t| {
        const off = tzOffsetAt(t);
        try std.testing.expect(off >= -14 * 3600 and off <= 14 * 3600);
    }
}

test "LAW gap-real-file-io CLOSED-FD TOTALITY: pread/pwrite on a closed handle → an error, never a crash" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const h = try open(io, tmp.dir, "closed.dat", .read_write);
    try pwrite(io, h, 0, "x");
    close(io, h); // fd now invalid
    var buf: [4]u8 = undefined;
    // Total: some PrimError, never UB/panic. (The OS returns EBADF → mapped.)
    try std.testing.expectError(error.Ebadf, pread(io, h, 0, &buf));
    try std.testing.expectError(error.Ebadf, pwrite(io, h, 0, "y"));
}

test "LAW gap-real-file-io LIST_DIR SET-EQUALITY: listDir returns exactly the real entries" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // A seeded set of distinct names; listDir must return EXACTLY this set.
    const want = [_][]const u8{ "alpha", "beta", "gamma", "delta" };
    for (want) |nm| try writeFile(io, tmp.dir, nm, "x");
    const got = try listDir(io, tmp.dir, gpa, ".");
    defer {
        for (got) |n| gpa.free(n);
        gpa.free(got);
    }
    // |got| == |want| (kills the "drops an entry" mutant) AND every want ∈ got.
    try std.testing.expectEqual(want.len, got.len);
    for (want) |nm| {
        var found = false;
        for (got) |g| {
            if (std.mem.eql(u8, nm, g)) found = true;
        }
        try std.testing.expect(found);
    }
    // Missing directory → Enoent (never a panic).
    try std.testing.expectError(error.Enoent, listDir(io, tmp.dir, gpa, "no_such_dir"));
}

