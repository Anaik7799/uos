// tools/c3i_watcher_kernel.zig
// =============================================================================
// [C3I-SIL6-MSTS] C3I / UOS Deterministic Watcher & Hot-Reload Zig Kernel
// =============================================================================
// ZERO C | ZERO PYTHON | ZERO NODE.JS | PURE ZIG 0.16.0 KERNEL BACKEND
// Exports C-ABI functions for Modular MAX Mojo 1.0.0 and native OCaml bindings.
// =============================================================================

const std = @import("std");

// -----------------------------------------------------------------------------
// POSIX & Linux Kernel Definitions
// -----------------------------------------------------------------------------
pub const IN_MODIFY: u32 = 0x00000002;
pub const IN_CLOSE_WRITE: u32 = 0x00000008;
pub const IN_MOVED_TO: u32 = 0x00000080;
pub const IN_CREATE: u32 = 0x00000100;
pub const WATCH_MASK: u32 = IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE; // 0x0000018A

pub const IN_NONBLOCK: c_int = 0x00000800;
pub const IN_CLOEXEC: c_int = 0x00080000;

pub const pollfd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

pub const timespec = extern struct {
    tv_sec: c_long,
    tv_nsec: c_long,
};

pub const timeval = extern struct {
    tv_sec: c_long,
    tv_usec: c_long,
};

pub const inotify_event = extern struct {
    wd: c_int,
    mask: u32,
    cookie: u32,
    len: u32,
};

pub const sockaddr_in = extern struct {
    sin_family: u16,
    sin_port: u16,
    sin_addr: u32,
    sin_zero: [8]u8 = [_]u8{0} ** 8,
};

// -----------------------------------------------------------------------------
// Standard Libc System Calls (Bound via Zig extern "c")
// -----------------------------------------------------------------------------
extern "c" fn inotify_init1(flags: c_int) c_int;
extern "c" fn inotify_add_watch(fd: c_int, pathname: [*:0]const u8, mask: u32) c_int;
extern "c" fn poll(fds: [*]pollfd, nfds: c_ulong, timeout: c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
extern "c" fn connect(sockfd: c_int, addr: *const anyopaque, addrlen: u32) c_int;
extern "c" fn setsockopt(sockfd: c_int, level: c_int, optname: c_int, optval: *const anyopaque, optlen: u32) c_int;
extern "c" fn clock_gettime(clk_id: c_int, tp: *timespec) c_int;
extern "c" fn sysconf(name: c_int) c_long;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(stream: *anyopaque) c_int;
extern "c" fn fscanf(stream: *anyopaque, format: [*:0]const u8, ...) c_int;
extern "c" fn system(command: [*:0]const u8) c_int;
extern "c" fn pthread_create(thread: *usize, attr: ?*const anyopaque, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int;
extern "c" fn pthread_join(thread: usize, retval: ?*?*anyopaque) c_int;

// -----------------------------------------------------------------------------
// Pure Zig Core Implementation Functions (C-ABI Compatible)
// -----------------------------------------------------------------------------

pub export fn c3i_inotify_create() callconv(.c) c_int {
    return inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
}

pub export fn c3i_inotify_watch(ifd: c_int, path: [*:0]const u8) callconv(.c) c_int {
    if (ifd < 0) return -1;
    return inotify_add_watch(ifd, path, WATCH_MASK);
}

pub export fn c3i_inotify_poll(ifd: c_int, timeout_ms: c_int) callconv(.c) c_int {
    if (ifd < 0) return -1;
    var pfd = [1]pollfd{.{
        .fd = ifd,
        .events = 0x0001, // POLLIN
        .revents = 0,
    }};
    return poll(&pfd, 1, timeout_ms);
}

pub export fn c3i_inotify_drain(ifd: c_int) callconv(.c) c_int {
    if (ifd < 0) return 0;
    var buf: [16384]u8 align(@alignOf(inotify_event)) = undefined;
    var total_events: c_int = 0;
    while (true) {
        const len = read(ifd, &buf, buf.len);
        if (len <= 0) break;
        const ulen: usize = @intCast(len);
        var offset: usize = 0;
        while (offset < ulen) {
            if (offset + @sizeOf(inotify_event) > ulen) break;
            const ev: *const inotify_event = @ptrCast(@alignCast(&buf[offset]));
            total_events += 1;
            offset += @sizeOf(inotify_event) + ev.len;
        }
    }
    return total_events;
}

pub export fn c3i_get_time_nanos() callconv(.c) i64 {
    var ts: timespec = undefined;
    _ = clock_gettime(1, &ts); // CLOCK_MONOTONIC = 1
    return @as(i64, ts.tv_sec) * 1_000_000_000 + @as(i64, ts.tv_nsec);
}

pub export fn c3i_get_rss_kb() callconv(.c) i64 {
    const f = fopen("/proc/self/statm", "r") orelse return 0;
    defer _ = fclose(f);
    var dummy: c_long = 0;
    var rss_pages: c_long = 0;
    if (fscanf(f, "%ld %ld", &dummy, &rss_pages) != 2) return 0;
    const page_size = sysconf(30); // _SC_PAGESIZE = 30
    return @divTrunc(@as(i64, rss_pages) * @as(i64, page_size), 1024);
}

pub export fn c3i_http_reload(port: c_int, out_buf: ?[*]u8, out_buf_len: c_int) callconv(.c) i64 {
    const t0 = c3i_get_time_nanos();
    const sock = socket(2, 1, 0); // AF_INET = 2, SOCK_STREAM = 1
    if (sock < 0) return -1;
    defer _ = close(sock);

    const tv = timeval{ .tv_sec = 2, .tv_usec = 0 };
    _ = setsockopt(sock, 1, 20, &tv, @sizeOf(timeval)); // SOL_SOCKET=1, SO_RCVTIMEO=20
    _ = setsockopt(sock, 1, 21, &tv, @sizeOf(timeval)); // SOL_SOCKET=1, SO_SNDTIMEO=21

    const uport: u16 = @intCast(port);
    const net_port = (uport << 8) | (uport >> 8); // htons
    const addr = sockaddr_in{
        .sin_family = 2, // AF_INET
        .sin_port = net_port,
        .sin_addr = 0x0100007F, // 127.0.0.1
    };

    if (connect(sock, &addr, @sizeOf(sockaddr_in)) != 0) {
        return -2;
    }

    const req = "GET /api/v1/reload HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n";
    const w = write(sock, req, req.len);
    if (w <= 0) return -3;

    if (out_buf) |buf| {
        if (out_buf_len > 0) {
            const ulen: usize = @intCast(out_buf_len);
            @memset(buf[0..ulen], 0);
            _ = read(sock, buf, ulen - 1);
        }
    } else {
        var dump: [2048]u8 = undefined;
        _ = read(sock, &dump, dump.len);
    }

    const t1 = c3i_get_time_nanos();
    return @divTrunc(t1 - t0, 1000); // Elapsed microseconds
}

pub export fn c3i_trigger_build(dir: ?[*:0]const u8) callconv(.c) c_int {
    const d = dir orelse return -1;
    var cmd_buf: [1024]u8 = undefined;
    const cmd = std.fmt.bufPrintZ(&cmd_buf, "cd {s} && gleam build >/dev/null 2>&1", .{d}) catch return -2;
    return system(cmd.ptr);
}

// -----------------------------------------------------------------------------
// Zig Concurrency Benchmark Workers
// -----------------------------------------------------------------------------

const ReloadBenchTask = extern struct {
    port: c_int,
    latency_us: i64,
};

fn reload_thread_worker(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const task: *ReloadBenchTask = @ptrCast(@alignCast(arg orelse return null));
    task.latency_us = c3i_http_reload(task.port, null, 0);
    return null;
}

pub export fn c3i_bench_concurrent_reload(port: c_int, thread_count: c_int) callconv(.c) i64 {
    if (thread_count <= 0 or thread_count > 64) return -1;
    const count: usize = @intCast(thread_count);
    var threads: [64]usize = undefined;
    var tasks: [64]ReloadBenchTask = undefined;

    const t0 = c3i_get_time_nanos();

    var i: usize = 0;
    while (i < count) : (i += 1) {
        tasks[i].port = port;
        tasks[i].latency_us = 0;
        _ = pthread_create(&threads[i], null, reload_thread_worker, &tasks[i]);
    }

    i = 0;
    while (i < count) : (i += 1) {
        _ = pthread_join(threads[i], null);
    }

    const t1 = c3i_get_time_nanos();
    return @divTrunc(t1 - t0, 1000);
}

test "c3i watcher kernel initialization, monotonic clock and non-blocking inotify" {
    // 1. Monotonic clock test
    const t_nano = c3i_get_time_nanos();
    try std.testing.expect(t_nano > 0);

    // 2. Inotify non-blocking init
    const ifd = c3i_inotify_create();
    try std.testing.expect(ifd >= 0);
    defer _ = close(ifd);

    // 3. Add watch on /tmp
    const wd = c3i_inotify_watch(ifd, "/tmp");
    try std.testing.expect(wd >= 0);

    // 4. Poll with 0 timeout (non-blocking)
    const p = c3i_inotify_poll(ifd, 0);
    try std.testing.expect(p >= 0);

    // 5. Memory RSS measurement
    const rss = c3i_get_rss_kb();
    try std.testing.expect(rss > 0);
}
