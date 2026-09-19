//! beam-zig E5.4 / S25: **the live os-port driver** — CA-14's OS half.
//!
//! ## Stratum
//! **Stratum C (substrate)** — the ONLY module in the port subsystem allowed to
//! touch a real OS process. Everything above it (the S25 port ENDPOINT algebra
//! in `port_algebra.zig`, its command/reply/port-death/info-totality laws) is
//! Stratum A/B and NEVER depends on this file; a `port_algebra` law may not read
//! an fd. This module is the seam `open_port({spawn,Cmd},…)` crosses to reach a
//! real child (`cat`, a shell command), and the E4.5 endpoint algebra treats it
//! as ONE driver among two (the fixture echo being the other).
//!
//! ## Signature (a live external program behind a pipe pair)
//!   spawnShell : (cmd) -> LivePort            fork+exec `/bin/sh -c cmd`
//!   command    : (LivePort, bytes, fuel) -> echoed bytes   write→read-back
//!   closeStdin : (LivePort) -> ()             EOF to the child
//!   wait       : (LivePort, fuel) -> ExitStatus   reap, bounded (kill on fuel)
//!
//! ## Semantic domain
//! A LivePort denotes a running child with a byte pipe in each direction. The
//! echo driver's meaning is the IDENTITY on bytes: `command(p, b)` returns
//! exactly `b` back for a `cat` child (BYTE CONSERVATION across the pipe). A
//! child that has consumed EOF and exited denotes an ExitStatus; a child that
//! never answers denotes `error.Fuel` — every fd/process interaction is
//! FUEL-BOUNDED, so a wedged child is a FAILED LAW (an `error.Fuel` return),
//! never a hung suite ("a hang is a failed law").
//!
//! ## Laws (exercised here over a REAL `cat`/silent child; the differential
//!         twin `port_algebra` + the harness erl-corpus lacked pre-E5)
//!   BYTE CONSERVATION   command(p, seeded) == seeded, for every seeded payload
//!                       (echoed byte-for-byte through the OS pipe).
//!   PORT DEATH / EXIT   closeStdin → the child reads EOF, exits; `wait` reaps
//!                       EXACTLY the child's status (exited 0 for `cat`).
//!   BOUNDED             a silent child (`cat >/dev/null`) that never answers a
//!                       read returns `error.Fuel` on the budget — it does not
//!                       hang; `wait` kills a still-running child at the bound.
//!
//! ## Scope
//! Linux only (raw `std.os.linux` syscalls: fork/pipe2/dup2/execve/waitpid/kill;
//! `std.os.linux.poll`/read/write). The pin's host is Linux; a non-Linux port is
//! out of scope. Payloads are kept below the pipe buffer (64 KiB) so a
//! write-then-read echo never self-deadlocks (the driver writes the whole
//! payload before reading it back — safe for the bounded payloads the endpoint
//! algebra and corpus use).

const std = @import("std");
const linux = std.os.linux;

pub const LiveError = error{ SpawnFailed, WriteFailed, ReadFailed, Fuel };

/// The reaped disposition of a child — the port-death reason source.
pub const ExitStatus = union(enum) {
    exited: u8, //     normal termination with this code (0 == `normal`)
    signalled: u8, //  killed by this signal number
};

/// A signed view of a raw linux syscall return: < 0 is `-errno`.
fn sig(rc: usize) isize {
    return @bitCast(rc);
}

const KillSig = @typeInfo(@TypeOf(linux.kill)).@"fn".params[1].type.?;

fn sigKill() KillSig {
    return switch (@typeInfo(KillSig)) {
        .@"enum" => .KILL,
        else => 9,
    };
}

fn sigCode(v: anytype) u8 {
    return switch (@typeInfo(@TypeOf(v))) {
        .@"enum" => @intCast(@intFromEnum(v)),
        else => @intCast(v),
    };
}

pub const LivePort = struct {
    pid: i32,
    /// write end of the child's stdin (we write commands here)
    stdin_fd: i32,
    /// read end of the child's stdout (we read echoed bytes here)
    stdout_fd: i32,
    /// false once `wait`/`deinit` has reaped the child (idempotence guard)
    reaped: bool = false,
    is_tty: bool = false,
    status: ?ExitStatus = null,

    /// Spawn `/bin/sh -c cmd` with piped stdin/stdout. The child's PATH is set so
    /// a bare program name (`cat`) resolves. Returns a LivePort owning both pipe
    /// ends. On any syscall failure the half-built state is torn down and
    /// `error.SpawnFailed` is returned (never a leaked fd or zombie).
    pub fn spawnShell(cmd: [*:0]const u8) LiveError!LivePort {
        return spawnShellOpts(cmd, false);
    }

    /// gap-open-port-stderr (Slice D): `spawnShell` with an explicit `merge_stderr`
    /// flag. When true, the child's stderr (fd 2) is dup'd onto the SAME pipe as its
    /// stdout (fd 1) — the `open_port(_, [stderr_to_stdout])` contract, so both
    /// streams reach the port's single data stream. Default (via `spawnShell`) is
    /// false: stderr is inherited (goes to the tty), matching os:cmd/1 + a plain port.
    pub fn spawnShellOpts(cmd: [*:0]const u8, merge_stderr: bool) LiveError!LivePort {
        const cmd_str = std.mem.span(cmd);
        if (std.mem.startsWith(u8, cmd_str, "tty_sl")) {
            return .{
                .pid = 0,
                .stdin_fd = 1,
                .stdout_fd = 0,
                .is_tty = true,
                .status = .{ .exited = 0 },
            };
        }
        // stdin pipe: parent writes [1], child reads [0].
        var in_fds: [2]i32 = undefined;
        // stdout pipe: child writes [1], parent reads [0].
        var out_fds: [2]i32 = undefined;
        if (sig(linux.pipe2(&in_fds, .{})) < 0) return error.SpawnFailed;
        if (sig(linux.pipe2(&out_fds, .{})) < 0) {
            _ = linux.close(in_fds[0]);
            _ = linux.close(in_fds[1]);
            return error.SpawnFailed;
        }

        const rc = linux.fork();
        if (sig(rc) < 0) {
            _ = linux.close(in_fds[0]);
            _ = linux.close(in_fds[1]);
            _ = linux.close(out_fds[0]);
            _ = linux.close(out_fds[1]);
            return error.SpawnFailed;
        }
        if (rc == 0) {
            // CHILD: wire stdin<-in[0], stdout->out[1], drop all pipe fds, exec.
            _ = linux.dup2(in_fds[0], 0);
            _ = linux.dup2(out_fds[1], 1);
            // gap-open-port-stderr (Slice D): stderr_to_stdout → fd2 also → the pipe,
            // so the child's stderr merges into the port's single data stream.
            if (merge_stderr) _ = linux.dup2(out_fds[1], 2);
            _ = linux.close(in_fds[0]);
            _ = linux.close(in_fds[1]);
            _ = linux.close(out_fds[0]);
            _ = linux.close(out_fds[1]);
            const argv = [_:null]?[*:0]const u8{ "/bin/sh", "-c", cmd };
            const envp = [_:null]?[*:0]const u8{"PATH=/usr/bin:/bin:/usr/local/bin"};
            _ = linux.execve("/bin/sh", &argv, &envp);
            linux.exit(127); // exec failed
        }
        // PARENT: keep the write-end of stdin and the read-end of stdout.
        _ = linux.close(in_fds[0]);
        _ = linux.close(out_fds[1]);
        return .{
            .pid = @intCast(rc),
            .stdin_fd = in_fds[1],
            .stdout_fd = out_fds[0],
        };
    }

    /// Write the whole slice to the child's stdin. Bounded: a short write loops
    /// until all bytes are sent or `error.WriteFailed`.
    pub fn writeAll(self: *LivePort, bytes: []const u8) LiveError!void {
        if (self.is_tty) return;
        var off: usize = 0;
        while (off < bytes.len) {
            const n = linux.write(self.stdin_fd, bytes.ptr + off, bytes.len - off);
            const s = sig(n);
            if (s <= 0) return error.WriteFailed;
            off += @intCast(s);
        }
    }

    /// Read EXACTLY `out.len` bytes back, fuel-bounded. Each poll unit waits up
    /// to 10ms; after `fuel` idle units with no data the read returns
    /// `error.Fuel` (a wedged/silent child — a FAILED LAW, never a hang). An EOF
    /// before `out.len` bytes is `error.ReadFailed` (the child died early).
    pub fn readExact(self: *LivePort, out: []u8, fuel: usize) LiveError!void {
        var got: usize = 0;
        var idle: usize = 0;
        while (got < out.len) {
            if (idle >= fuel) return error.Fuel;
            var pfd = [_]linux.pollfd{.{ .fd = self.stdout_fd, .events = linux.POLL.IN, .revents = 0 }};
            const pr = linux.poll(&pfd, 1, 10);
            if (sig(pr) < 0) return error.ReadFailed;
            if (pr == 0) {
                idle += 1; // timeout — spend a fuel unit, keep waiting
                continue;
            }
            if (pfd[0].revents & linux.POLL.IN != 0) {
                const n = linux.read(self.stdout_fd, out.ptr + got, out.len - got);
                const s = sig(n);
                if (s < 0) return error.ReadFailed;
                if (s == 0) return error.ReadFailed; // EOF short of the ask
                got += @intCast(s);
            } else {
                return error.ReadFailed; // HUP/ERR with no readable bytes
            }
        }
    }

    /// e49-real-ports-io: drain the child's stdout UNTIL EOF (the os:cmd
    /// shape — collect everything the command prints, then stop at pipe
    /// close). BOUNDED twice: `cap` bytes (over-cap → error.Fuel, never
    /// unbounded growth) and `fuel` idle poll ticks (a silent child that
    /// never closes → error.Fuel, never a hang). Caller owns the result.
    pub fn readToEof(self: *LivePort, gpa: std.mem.Allocator, cap: usize, fuel: usize) LiveError![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(gpa);
        var idle: usize = 0;
        var chunk: [4096]u8 = undefined;
        while (true) {
            if (idle >= fuel) return error.Fuel;
            var pfd = [_]linux.pollfd{.{ .fd = self.stdout_fd, .events = linux.POLL.IN, .revents = 0 }};
            const pr = linux.poll(&pfd, 1, 10);
            if (sig(pr) < 0) return error.ReadFailed;
            if (pr == 0) {
                idle += 1;
                continue;
            }
            if (pfd[0].revents & linux.POLL.IN != 0) {
                const n = linux.read(self.stdout_fd, &chunk, chunk.len);
                const sn = sig(n);
                if (sn < 0) return error.ReadFailed;
                if (sn == 0) break; // EOF — the command finished its output
                if (buf.items.len + @as(usize, @intCast(sn)) > cap) return error.Fuel;
                buf.appendSlice(gpa, chunk[0..@intCast(sn)]) catch return error.ReadFailed;
                idle = 0;
            } else if (pfd[0].revents & (linux.POLL.HUP | linux.POLL.ERR) != 0) {
                break; // pipe closed with nothing readable — EOF
            } else {
                idle += 1;
            }
        }
        return buf.toOwnedSlice(gpa) catch error.ReadFailed;
    }

    /// The echo command: write `bytes`, read the same count back into `out`
    /// (which must be `>= bytes.len`); returns the echoed slice `out[0..len]`.
    pub fn command(self: *LivePort, bytes: []const u8, out: []u8, fuel: usize) LiveError![]u8 {
        std.debug.assert(out.len >= bytes.len);
        try self.writeAll(bytes);
        try self.readExact(out[0..bytes.len], fuel);
        return out[0..bytes.len];
    }

    /// Close the child's stdin — an EOF that lets a filter (`cat`) drain and exit.
    pub fn closeStdin(self: *LivePort) void {
        if (self.is_tty) return;
        if (self.stdin_fd >= 0) {
            _ = linux.close(self.stdin_fd);
            self.stdin_fd = -1;
        }
    }

    /// Reap the child, capturing its ExitStatus. Bounded: after `fuel` idle
    /// `WNOHANG` polls the child is force-killed (`SIGKILL`) and then reaped
    /// blocking. Idempotent — a second call returns the captured status.
    pub fn wait(self: *LivePort, fuel: usize) ExitStatus {
        if (self.reaped) return self.status.?;
        if (self.is_tty) {
            self.reaped = true;
            return self.status.?;
        }
        self.closeStdin(); // ensure EOF so a filter can exit on its own
        var idle: usize = 0;
        var wstatus: u32 = 0;
        while (true) {
            const rc = linux.waitpid(self.pid, &wstatus, linux.W.NOHANG);
            const s = sig(rc);
            if (s < 0) {
                // no such child / already reaped — treat as normal exit 0
                self.status = .{ .exited = 0 };
                break;
            }
            if (rc == 0) {
                // still running
                if (idle >= fuel) {
                    _ = linux.kill(self.pid, sigKill());
                    _ = linux.waitpid(self.pid, &wstatus, 0); // blocking reap
                    self.status = decode(wstatus);
                    break;
                }
                idle += 1;
                var pfd = [_]linux.pollfd{.{ .fd = -1, .events = 0, .revents = 0 }};
                _ = linux.poll(&pfd, 0, 5); // 5ms nap, no fd
                continue;
            }
            self.status = decode(wstatus);
            break;
        }
        self.reaped = true;
        return self.status.?;
    }

    fn decode(wstatus: u32) ExitStatus {
        if (linux.W.IFEXITED(wstatus)) return .{ .exited = linux.W.EXITSTATUS(wstatus) };
        if (linux.W.IFSIGNALED(wstatus)) return .{ .signalled = sigCode(linux.W.TERMSIG(wstatus)) };
        return .{ .exited = 0 };
    }

    /// Release all OS resources: close both pipe ends and reap the child. Safe to
    /// call after `wait` (idempotent).
    pub fn deinit(self: *LivePort) void {
        self.closeStdin();
        if (!self.is_tty and self.stdout_fd >= 0) {
            _ = linux.close(self.stdout_fd);
            self.stdout_fd = -1;
        }
        _ = self.wait(64);
    }
};

// ============================================================================
// Laws — over a REAL child (`cat`, a silent `cat >/dev/null`, an exiting shell)
// ============================================================================

test "LAW E5.4 BYTE CONSERVATION: a live `cat` echoes every seeded payload byte-for-byte" {
    var lp = try LivePort.spawnShell("exec cat");
    defer lp.deinit();

    var buf: [256]u8 = undefined;
    var out: [256]u8 = undefined;
    for (0..40) |iter| {
        var prng = std.Random.DefaultPrng.init(0xCA7 +% iter);
        const random = prng.random();
        const n = 1 + random.uintLessThan(usize, 200);
        for (buf[0..n]) |*b| b.* = random.int(u8);
        const echoed = try lp.command(buf[0..n], &out, 100);
        try std.testing.expectEqualSlices(u8, buf[0..n], echoed);
    }
}

test "LAW E5.4 PORT DEATH / EXIT: closeStdin lets `cat` drain and exit 0; wait reaps exactly that" {
    var lp = try LivePort.spawnShell("exec cat");
    // one round-trip proves it is alive
    var out: [8]u8 = undefined;
    _ = try lp.command("hi", &out, 100);
    // EOF → cat exits 0
    lp.closeStdin();
    const st = lp.wait(200);
    try std.testing.expectEqual(ExitStatus{ .exited = 0 }, st);
    // idempotent
    try std.testing.expectEqual(ExitStatus{ .exited = 0 }, lp.wait(200));
    lp.deinit();
}

test "LAW E5.4 EXIT STATUS: a non-zero shell exit is captured verbatim" {
    var lp = try LivePort.spawnShell("exit 3");
    const st = lp.wait(200);
    try std.testing.expectEqual(ExitStatus{ .exited = 3 }, st);
    lp.deinit();
}

test "LAW E5.4 BOUNDED: a silent child that never answers a read returns error.Fuel, never a hang" {
    // `sleep` holds our stdout pipe open (no HUP) but never writes — the wedged
    // child a bounded read must give up on. deinit force-kills it at the bound.
    var lp = try LivePort.spawnShell("exec sleep 30");
    defer lp.deinit();
    try lp.writeAll("ping");
    var out: [4]u8 = undefined;
    try std.testing.expectError(error.Fuel, lp.readExact(&out, 20));
}

// LAW E26-T1 — the DARK LivePort error/exit/tty arms (E26 Task 1). The E5.4 laws
// cover BYTE-CONSERVATION / clean-exit / Fuel; the EOF-short-read `error.ReadFailed`
// arm, the `wait` FORCE-KILL→`signalled` arm, and the `tty_sl` short-circuit port
// were never driven. These are SYSCALL arms — a fake/loopback port that bypasses
// the fds could not exercise them, so they are covered DIRECTLY over real children
// (the honest refinement of the "os-port seam" idea: the seam adds nothing a real
// child does not, for THESE arms). Every interaction stays fuel-bounded.
//
// OTP-30 CORRELATION. erts's port driver reports a port that EOFs early / dies by
// signal distinctly from a clean exit (`{'EXIT',Port,Reason}` carries the signal),
// and a tty/nosync port is a real erts port kind; this pins the driver's ExitStatus
// + read-error observables the S25 endpoint algebra denotes.
//
// Mutants MUTATION_LOG e26-t1 m1 (readExact treats the HUP/ERR poll arm as idle,
// not ReadFailed — the arm this EOF actually hits; `s==0` is EQUIVALENT here since
// `printf ab`'s EOF surfaces as POLLHUP-without-POLLIN) / m2 (wait's force-kill
// decodes `exited 0` not the real SIGKILL signal).
test "LAW E26-T1 dark LivePort arms: EOF-short read → ReadFailed; wait force-kill → signalled; tty port short-circuits" {
    // (1) EOF-SHORT READ. `printf ab` writes exactly 2 bytes then EOFs; a read
    //     asking for 4 gets the 2 then hits EOF → error.ReadFailed (NOT Fuel: the
    //     pipe HUPs, it does not merely go quiet).
    {
        var lp = try LivePort.spawnShell("printf ab");
        defer lp.deinit();
        var out: [4]u8 = undefined;
        try std.testing.expectError(error.ReadFailed, lp.readExact(&out, 100));
    }

    // (2) FORCE-KILL → SIGNALLED. `sleep 30` is still running; `wait(0)` exhausts
    //     the fuel immediately, force-kills (SIGKILL=9), and reaps the SIGNALLED
    //     status verbatim — NOT a fabricated `exited 0`.
    {
        var lp = try LivePort.spawnShell("exec sleep 30");
        const st = lp.wait(0);
        try std.testing.expectEqual(ExitStatus{ .signalled = 9 }, st);
        try std.testing.expectEqual(st, lp.wait(0)); // idempotent
        lp.deinit();
    }

    // (3) TTY SHORT-CIRCUIT. A `tty_sl` port is the terminal-backed port kind:
    //     spawn returns is_tty with a captured `exited 0`, `wait` returns it
    //     WITHOUT touching a pipe, and `closeStdin` is a no-op (never closes fd 1).
    {
        var lp = try LivePort.spawnShell("tty_sl /dev/tty");
        try std.testing.expect(lp.is_tty);
        try std.testing.expectEqual(ExitStatus{ .exited = 0 }, lp.wait(8));
        lp.closeStdin(); // no-op: must NOT close the real stdout fd (1)
        try std.testing.expect(lp.stdin_fd == 1); // untouched
    }
}
