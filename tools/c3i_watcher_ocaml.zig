// tools/c3i_watcher_ocaml.zig
// =============================================================================
// [C3I-SIL6-MSTS] C3I / UOS Native OCaml CAMLprim Bindings in Pure Zig
// =============================================================================
// ZERO C | ZERO PYTHON | ZERO NODE.JS | PURE ZIG 0.16.0
// =============================================================================

const std = @import("std");
const kernel = @import("c3i_watcher_kernel.zig");

// Libc functions needed for inotify read and strings
extern "c" fn inotify_init1(flags: c_int) c_int;
extern "c" fn inotify_add_watch(fd: c_int, pathname: [*:0]const u8, mask: u32) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;

// OCaml Runtime Primitives
extern "c" fn caml_copy_int64(i64) isize;
extern "c" fn caml_copy_string([*:0]const u8) isize;
extern "c" fn caml_alloc(usize, u8) isize;

export fn caml_c3i_inotify_create(_: isize) callconv(.c) isize {
    const fd = kernel.c3i_inotify_create();
    return (@as(isize, fd) << 1) | 1;
}

export fn caml_c3i_inotify_init(_: isize) callconv(.c) isize {
    const fd = kernel.c3i_inotify_create();
    return (@as(isize, fd) << 1) | 1;
}

export fn caml_c3i_inotify_watch(v_fd: isize, v_path: isize) callconv(.c) isize {
    const ifd: c_int = @intCast(v_fd >> 1);
    const path: [*:0]const u8 = @ptrFromInt(@as(usize, @bitCast(v_path)));
    const wd = kernel.c3i_inotify_watch(ifd, path);
    return (@as(isize, wd) << 1) | 1;
}

export fn caml_c3i_inotify_add_watch(v_fd: isize, v_path: isize, v_mask: isize) callconv(.c) isize {
    const ifd: c_int = @intCast(v_fd >> 1);
    const path: [*:0]const u8 = @ptrFromInt(@as(usize, @bitCast(v_path)));
    const mask: u32 = @intCast(v_mask >> 1);
    const wd = inotify_add_watch(ifd, path, mask);
    return (@as(isize, wd) << 1) | 1;
}

export fn caml_c3i_inotify_poll(v_fd: isize, v_timeout_ms: isize) callconv(.c) isize {
    const ifd: c_int = @intCast(v_fd >> 1);
    const ms: c_int = @intCast(v_timeout_ms >> 1);
    const rc = kernel.c3i_inotify_poll(ifd, ms);
    return (@as(isize, rc) << 1) | 1;
}

export fn caml_c3i_inotify_drain(v_fd: isize) callconv(.c) isize {
    const ifd: c_int = @intCast(v_fd >> 1);
    const count = kernel.c3i_inotify_drain(ifd);
    return (@as(isize, count) << 1) | 1;
}

export fn caml_c3i_inotify_read_names(v_fd: isize) callconv(.c) isize {
    const ifd: c_int = @intCast(v_fd >> 1);
    var list: isize = 1; // Val_emptylist = Val_int(0) = 1
    var buf: [16384]u8 align(@alignOf(kernel.inotify_event)) = undefined;

    while (true) {
        const len = read(ifd, &buf, buf.len);
        if (len <= 0) break;
        const ulen: usize = @intCast(len);
        var offset: usize = 0;
        while (offset < ulen) {
            if (offset + @sizeOf(kernel.inotify_event) > ulen) break;
            const ev: *const kernel.inotify_event = @ptrCast(@alignCast(&buf[offset]));
            if (ev.len > 0) {
                const name_ptr: [*:0]const u8 = @ptrCast(&buf[offset + @sizeOf(kernel.inotify_event)]);
                const s = caml_copy_string(name_ptr);
                const cell = caml_alloc(2, 0);
                const p: [*]isize = @ptrFromInt(@as(usize, @bitCast(cell)));
                p[0] = s;
                p[1] = list;
                list = cell;
            }
            offset += @sizeOf(kernel.inotify_event) + ev.len;
        }
    }
    return list;
}

export fn caml_c3i_get_time_nanos(_: isize) callconv(.c) isize {
    return caml_copy_int64(kernel.c3i_get_time_nanos());
}

export fn caml_c3i_get_rss_kb(_: isize) callconv(.c) isize {
    return caml_copy_int64(kernel.c3i_get_rss_kb());
}

export fn caml_c3i_http_reload(v_port: isize) callconv(.c) isize {
    const port: c_int = @intCast(v_port >> 1);
    const lat = kernel.c3i_http_reload(port, null, 0);
    return caml_copy_int64(lat);
}

export fn caml_c3i_bench_concurrent_reload(v_port: isize, v_threads: isize) callconv(.c) isize {
    const port: c_int = @intCast(v_port >> 1);
    const threads: c_int = @intCast(v_threads >> 1);
    const lat = kernel.c3i_bench_concurrent_reload(port, threads);
    return caml_copy_int64(lat);
}
