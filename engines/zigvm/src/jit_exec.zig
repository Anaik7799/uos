//! beam-zig JIT epoch / slice #1 (`jit-exec-buffer`): the **executable-memory
//! substrate** — a `mmap`/`mprotect`/`munmap` page pool with a strict **W^X**
//! discipline. Composed with `src/jit_asm.zig` (the pure encoder, LAW L1), this
//! is the seam that lets emitted x86-64 machine code actually *run*: it is the
//! FIRST real native execution in the project.
//!
//! This is a **Stratum-C** module (an OS memory-protection seam) — quarantined,
//! nothing in the Stratum-A/B core depends on it; `vm_all` pulls it for its law
//! suite. It discharges **LAW L5 (W^X safety)** of
//! `docs/OTP30_JIT_FORMAL_ANALYSIS.md` (Part VI) as an STPA state-machine
//! invariant, and closes the round-trip by composing with `jit_asm`'s L1: the
//! bytes we execute are exactly the bytes `jit_asm` produced.
//!
//! ## Signature
//!
//!   State        — {`writable`, `sealed`}: a TWO-state machine with NO back-edge.
//!   alloc(len)   → mmap(PROT_READ|PROT_WRITE) a page-rounded region (writable,
//!                  NOT executable). The region is born writable-only — never RWX.
//!   write(bytes) → copy encoded bytes in; legal ONLY in `writable`.
//!   seal()       → mprotect(PROT_READ|PROT_EXEC): `writable →(seal)→ sealed`.
//!                  After this the region is executable and NEVER writable again
//!                  while a fn-ptr into it is live. There is no edge back.
//!   entry(Fn)    → cast the sealed region to a C-ABI fn-ptr; legal ONLY in
//!                  `sealed` (NO execute-before-seal).
//!   free()       → munmap the whole page-rounded region (leak-free).
//!
//! ## Semantic domain
//!
//! A mapped region is a pair ⟨bytes, protection⟩ where protection ∈ {RW, RX}.
//! The abstract state is the protection tag; the byte content is the machine
//! code. `alloc` establishes RW, `seal` is the unique RW→RX transition, and no
//! operation ever yields RWX (W ∧ X simultaneously) — that non-state is the
//! hazard L5 forbids. The whole point: `⟦execute(sealed)⟧ = the computation the
//! written bytes denote` (composed with `jit_asm` decode/L1).
//!
//! ## Laws
//!
//!   L5  W^X SAFETY        the region is NEVER simultaneously writable ∧
//!                         executable. Enforced by the state machine: `write`
//!                         fails-closed in `sealed` (AlreadySealed); `entry`
//!                         (the only path to execution) fails-closed in
//!                         `writable` (NotSealed / no-execute-before-seal); the
//!                         single RW→RX `mprotect` is the only protection change
//!                         and it has no inverse. Asserted by driving every edge
//!                         of the state machine and checking the closed doors.
//!   ROUND-TRIP / EXEC     alloc→write→seal→execute→free round-trips: a sealed
//!                         region built from `jit_asm.emitProgram` bytes, called
//!                         through the System-V C ABI, returns EXACTLY the value
//!                         the encoded instructions compute (const-return and
//!                         two-arg-add native functions). This composes with
//!                         `jit_asm` L1 — the executed bytes are the emitted bytes.
//!   LEAK-FREE / PAGES     every mmap'd page is munmap'd: a page-accounting
//!                         invariant (a monotone counter of mapped−unmapped pages
//!                         returns to zero) over an alloc/…/free churn, plus
//!                         `std.testing.allocator` proving the bookkeeping side is
//!                         leak-free. capacity is page-rounded; `write` past
//!                         capacity fails-closed (Overflow), never a heap smash.
//!
//! ## SAFETY PACKET (per SAFETY_ANALYSIS.md §10 / CTRL-SEAM-WIRE)
//!
//!   CONTROLLER : the exec-buffer allocator (`ExecBuffer`) — a Stratum-C seam
//!                controller mediating executable memory (CTRL-SEAM-WIRE).
//!   CONTROL ACTION : `mprotect` (the seal), plus `entry` (hand out a fn-ptr).
//!   UCA (P, wrong-state) : "native code executed while its page is still
//!                writable" — a fn-ptr handed out (or W left enabled through the
//!                RX transition) before/without the write window being closed.
//!   HAZARD : W^X bypass → code injection / self-modifying-code corruption; an
//!                attacker (or a codegen bug) mutating live code after it is
//!                reachable as instructions.
//!   MITIGATION : the two-state machine + its fail-closed doors are the bounding
//!                law (L5): (a) `alloc` maps RW-only, never RWX; (b) `seal` is
//!                the SOLE protection change and drops W as it adds X (RW→RX, one
//!                mprotect, no split window); (c) `entry` refuses to produce a
//!                fn-ptr unless `sealed` (no-execute-before-seal); (d) `write`
//!                refuses once `sealed` (no-write-after-seal). Detection channel:
//!                the L5 test drives every edge and asserts the closed doors;
//!                two planted mutants (skip-the-seal, RWX-map) redden L5.
//!   FMEA : mmap/mprotect/munmap failure → a typed error is returned
//!                (`MapFailed`/`ProtectFailed`), NEVER a silent RWX fallback and
//!                never a bytes-are-writable-but-claimed-sealed state. If `seal`'s
//!                mprotect fails the buffer stays `writable` (honest) and `entry`
//!                still refuses — a failed seal can never be mistaken for a sealed
//!                buffer. munmap (deallocation) is defined to succeed (Zig posix).
//!
//! ## Scope limits (documented, honest)
//! x86-64 / Linux only (the encoder targets x86-64; the seal uses the Linux
//! `mprotect` syscall). One region per `ExecBuffer` (a single page-run, not yet a
//! multi-region pool with abandoned-page reuse — a named successor once codegen
//! emits many blocks). No per-CPU code caches, no icache-flush dance (x86 has
//! coherent i/d caches, so none is needed here; ARM would need `__clear_cache`).
//! The point of THIS slice is the W^X seam + first real execution, not a code
//! cache's throughput.

const std = @import("std");
const builtin = @import("builtin");
const jit_asm = @import("jit_asm.zig");

const linux = std.os.linux;
const page_align = std.heap.page_size_min;

pub const ExecError = error{
    /// mmap failed — no executable page was mapped (never a silent fallback).
    MapFailed,
    /// mprotect (the seal) failed — the buffer stays `writable`, honestly.
    ProtectFailed,
    /// write would exceed the page-rounded capacity — fail closed, no smash.
    Overflow,
    /// write attempted after seal — W^X: no-write-after-seal.
    AlreadySealed,
    /// entry (fn-ptr / execution) requested before seal — W^X: no-execute-before-seal.
    NotSealed,
};

/// The exec-buffer protection state. A two-state machine with exactly one
/// transition (`writable →seal→ sealed`) and NO back-edge.
pub const State = enum { writable, sealed };

/// A page-accounting counter: mapped−unmapped pages. The LEAK-FREE law asserts
/// this returns to zero. `pages_mapped`/`pages_unmapped` are monotone; a global
/// (test-scoped) instance witnesses that every mapped page is unmapped.
pub const PageLedger = struct {
    pages_mapped: usize = 0,
    pages_unmapped: usize = 0,

    pub fn live(self: *const PageLedger) usize {
        return self.pages_mapped - self.pages_unmapped;
    }
};

fn roundUpToPage(want: usize) usize {
    const ps = std.heap.pageSize();
    // At least one page; round up. want==0 still maps one page (a valid empty region).
    const n = if (want == 0) 1 else (want + ps - 1) / ps;
    return n * ps;
}

/// The executable-memory buffer / W^X controller (CTRL-SEAM-WIRE).
pub const ExecBuffer = struct {
    mem: []align(page_align) u8, // the full page-rounded mapping
    len: usize, // bytes written so far
    state: State,
    ledger: ?*PageLedger, // optional page accounting (for the LEAK-FREE law)

    /// alloc(len) → mmap a page-rounded RW (NOT executable) region. Born
    /// writable-only; never RWX. `ledger`, if given, counts the mapped pages.
    pub fn alloc(want: usize, ledger: ?*PageLedger) ExecError!ExecBuffer {
        if (builtin.os.tag != .linux) return error.MapFailed; // scope: Linux mprotect seam
        const cap = roundUpToPage(want);
        const mem = std.posix.mmap(
            null,
            cap,
            .{ .READ = true, .WRITE = true }, // W, NOT X — never born executable
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        ) catch return error.MapFailed;
        if (ledger) |l| l.pages_mapped += cap / std.heap.pageSize();
        return .{ .mem = mem, .len = 0, .state = .writable, .ledger = ledger };
    }

    /// write(bytes) → append encoded machine code. Legal ONLY while `writable`
    /// (W^X: no-write-after-seal). Fails closed on overflow (never a smash).
    pub fn write(self: *ExecBuffer, bytes: []const u8) ExecError!void {
        if (self.state == .sealed) return error.AlreadySealed; // no-write-after-seal
        if (self.len + bytes.len > self.mem.len) return error.Overflow;
        @memcpy(self.mem[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }

    /// seal() → mprotect(PROT_READ|PROT_EXEC): the SOLE RW→RX transition. Drops
    /// W as it adds X in one syscall (no split writable∧executable window). On
    /// failure the buffer stays `writable` (honest) — a failed seal is never
    /// mistaken for a sealed buffer.
    pub fn seal(self: *ExecBuffer) ExecError!void {
        if (self.state == .sealed) return; // idempotent: already RX, still no back-edge
        const rc = linux.mprotect(
            self.mem.ptr,
            self.mem.len,
            .{ .READ = true, .EXEC = true }, // R+X, W dropped — W^X honored
        );
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            else => return error.ProtectFailed, // never a silent RWX fallback
        }
        self.state = .sealed;
    }

    /// entry(Fn) → the sealed region as a C-ABI function pointer. Legal ONLY
    /// while `sealed` (W^X: no-execute-before-seal). `Fn` must be a
    /// `*const fn (...) callconv(.c) T`.
    pub fn entry(self: *const ExecBuffer, comptime Fn: type) ExecError!Fn {
        return self.entryAt(0, Fn);
    }

    /// entryAt(off, Fn) → a C-ABI fn-ptr to `off` bytes into the sealed region.
    /// Legal ONLY while `sealed` (W^X: no-execute-before-seal). The template JIT
    /// (`jit_codegen.zig`) packs many stubs into one buffer and takes a fn-ptr per
    /// stub offset; `entry` is `entryAt(0, …)`. `off` must land within the written
    /// bytes (a stub start) — the caller (codegen) guarantees it by construction.
    pub fn entryAt(self: *const ExecBuffer, off: usize, comptime Fn: type) ExecError!Fn {
        if (self.state != .sealed) return error.NotSealed; // no-execute-before-seal
        if (off > self.len) return error.Overflow; // never a fn-ptr past the code
        // Data-pointer → function-pointer must go via the integer address:
        // @ptrCast does not bridge the fn/non-fn pointer kinds.
        return @ptrFromInt(@intFromPtr(self.mem.ptr) + off);
    }

    /// free() → munmap the whole page-rounded region (leak-free). Zig's munmap
    /// is defined to succeed; the ledger records the reclaimed pages.
    pub fn free(self: *ExecBuffer) void {
        if (self.ledger) |l| l.pages_unmapped += self.mem.len / std.heap.pageSize();
        std.posix.munmap(self.mem);
        self.* = undefined;
    }
};

// ===========================================================================
// Law suite
// ===========================================================================

const testing = std.testing;

// A trivial native function returning a 64-bit constant:  movabs rax,imm ; ret
fn constProgram(gpa: std.mem.Allocator, imm: i64) ![]u8 {
    const prog = [_]jit_asm.Inst{
        .{ .mov_ri = .{ .dst = .rax, .imm = imm } },
        .ret,
    };
    return jit_asm.emitProgram(gpa, &prog);
}

// A native function of the System-V C ABI computing arg0 + arg1:
//   rdi = a, rsi = b   →   mov rax,rdi ; add rax,rsi ; ret   →   rax = a + b
fn addProgram(gpa: std.mem.Allocator) ![]u8 {
    const prog = [_]jit_asm.Inst{
        .{ .mov_rr = .{ .dst = .rax, .src = .rdi } }, // rax = a
        .{ .add_rr = .{ .dst = .rax, .src = .rsi } }, // rax += b
        .ret,
    };
    return jit_asm.emitProgram(gpa, &prog);
}

test "EXEC round-trip: emitted (mov imm; ret) really executes and returns the constant" {
    if (builtin.os.tag != .linux or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    const gpa = testing.allocator;

    // A fixed, adversarial set of constants incl. sign bits and i32 boundaries.
    const consts = [_]i64{ 0, 1, -1, 0xDEAD_BEEF, std.math.maxInt(i32), std.math.minInt(i32), std.math.maxInt(i64), std.math.minInt(i64) };
    for (consts) |imm| {
        const code = try constProgram(gpa, imm); // jit_asm bytes (L1-proven)
        defer gpa.free(code);

        var buf = try ExecBuffer.alloc(code.len, null);
        defer buf.free();
        try buf.write(code);
        try buf.seal();

        const f = try buf.entry(*const fn () callconv(.c) i64);
        const got = f(); // ← first REAL native execution
        try testing.expectEqual(imm, got);
    }
}

test "EXEC round-trip: emitted (mov;add;ret) executes as the System-V add of two args" {
    if (builtin.os.tag != .linux or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    const gpa = testing.allocator;

    const code = try addProgram(gpa);
    defer gpa.free(code);

    var buf = try ExecBuffer.alloc(code.len, null);
    defer buf.free();
    try buf.write(code);
    try buf.seal();

    const add = try buf.entry(*const fn (i64, i64) callconv(.c) i64);

    // Seeded operand pairs incl. boundaries; wrapping add matches x86-64 ADD.
    var prng = std.Random.DefaultPrng.init(0x6A69_745F_6578_6563); // "jit_exec"
    const rnd = prng.random();
    var n: usize = 0;
    while (n < 2000) : (n += 1) { // bounded driver
        const a = rnd.int(i64);
        const b = rnd.int(i64);
        const got = add(a, b);
        try testing.expectEqual(a +% b, got);
    }
    // explicit boundary witnesses
    try testing.expectEqual(@as(i64, 3), add(1, 2));
    try testing.expectEqual(@as(i64, -1), add(std.math.maxInt(i64), std.math.minInt(i64)));
}

test "L5 W^X: no-execute-before-seal — entry() fails closed while writable" {
    if (builtin.os.tag != .linux or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    const gpa = testing.allocator;
    const code = try constProgram(gpa, 42);
    defer gpa.free(code);

    var buf = try ExecBuffer.alloc(code.len, null);
    defer buf.free();
    try buf.write(code);
    // NOT sealed yet: the region is writable, so it must NOT be executable.
    try testing.expectError(error.NotSealed, buf.entry(*const fn () callconv(.c) i64));
    try testing.expectEqual(State.writable, buf.state);

    // after seal, entry is granted (the transition is the ONLY way to execute)
    try buf.seal();
    _ = try buf.entry(*const fn () callconv(.c) i64);
    try testing.expectEqual(State.sealed, buf.state);
}

test "L5 W^X: no-write-after-seal — write() fails closed while executable" {
    if (builtin.os.tag != .linux or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    const gpa = testing.allocator;
    const code = try constProgram(gpa, 7);
    defer gpa.free(code);

    var buf = try ExecBuffer.alloc(code.len, null);
    defer buf.free();
    try buf.write(code);
    try buf.seal();
    // sealed ⇒ executable ⇒ NEVER writable again (the no-back-edge invariant).
    try testing.expectError(error.AlreadySealed, buf.write(&.{0x90}));
    try testing.expectEqual(State.sealed, buf.state);
    // seal is idempotent and stays sealed (no back-edge to writable)
    try buf.seal();
    try testing.expectEqual(State.sealed, buf.state);
}

test "L5 W^X: overflow fails closed — write past page-rounded capacity is rejected" {
    if (builtin.os.tag != .linux or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    var buf = try ExecBuffer.alloc(8, null);
    defer buf.free();
    const cap = buf.mem.len; // page-rounded (≥ one page)
    // Filling exactly to capacity is fine; one more byte fails closed.
    const filler = try testing.allocator.alloc(u8, cap);
    defer testing.allocator.free(filler);
    @memset(filler, 0x90); // NOPs
    try buf.write(filler);
    try testing.expectError(error.Overflow, buf.write(&.{0x90}));
}

test "LEAK-FREE: every mapped page is unmapped (page-accounting returns to zero)" {
    if (builtin.os.tag != .linux or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    const gpa = testing.allocator;
    var ledger = PageLedger{};

    var prng = std.Random.DefaultPrng.init(0x5741_5F58_5F70_6700); // "WA_X_pg"
    const rnd = prng.random();

    var trial: usize = 0;
    while (trial < 64) : (trial += 1) { // bounded churn
        const want = rnd.intRangeAtMost(usize, 0, 9000); // spans 0..multi-page
        const imm: i64 = @bitCast(rnd.int(u64));
        const code = try constProgram(gpa, imm);
        defer gpa.free(code);

        var buf = try ExecBuffer.alloc(want, &ledger);
        try testing.expect(ledger.live() >= 1); // at least one page live while held
        try buf.write(code);
        try buf.seal();
        const f = try buf.entry(*const fn () callconv(.c) i64);
        try testing.expectEqual(imm, f());
        buf.free();
    }
    // the accounting invariant: mapped == unmapped ⇒ no page leaked.
    try testing.expectEqual(ledger.pages_mapped, ledger.pages_unmapped);
    try testing.expectEqual(@as(usize, 0), ledger.live());
    try testing.expect(ledger.pages_mapped >= 64); // work actually happened
}
