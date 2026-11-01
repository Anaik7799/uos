const std = @import("std");
const linux = std.os.linux;

extern fn zlp_v3_boot(out_epfd: *c_int, out_heavy_efd: *c_int) callconv(.c) c_int;
extern fn zlp_v3_shutdown() callconv(.c) void;
extern fn zlp_epoll_wait_one(epfd: c_int, out_fd: *c_int, out_events: *u32, timeout_ms: c_int) callconv(.c) c_int;
extern fn zlp_enqueue_heavy(req_id: u64, rounds: u32, bytes: [*]const u8, len: usize) callconv(.c) c_int;
extern fn zlp_pop_heavy_done(out_req_id: *u64, out_digest: *u64) callconv(.c) c_int;

extern fn zlp_alloc_slab(cap: usize) callconv(.c) *anyopaque;
extern fn zlp_slab_ptr(slab: *anyopaque) callconv(.c) [*]u8;
extern fn zlp_set_size(slab: *anyopaque, len: usize) callconv(.c) void;
extern fn zlp_is_exclusive(slab: *anyopaque) callconv(.c) u8;
extern fn zlp_eval_retain_slab(slab: *anyopaque) callconv(.c) u64;
extern fn zlp_guard_topic_retain_slab(topic_slab: *anyopaque, topic: [*]const u8, len: usize) callconv(.c) u8;
extern fn zlp_get_pid() callconv(.c) u32;

extern fn zlp_zenoh_open_sse(epfd: c_int, topic: [*]const u8, topic_len: usize) callconv(.c) c_int;
extern fn zlp_zenoh_put(topic: [*]const u8, topic_len: usize, body: [*]const u8, body_len: usize) callconv(.c) c_int;
extern fn zlp_zenoh_get(topic: [*]const u8, topic_len: usize, out_buf: [*]u8, max_out: usize) callconv(.c) c_int;

extern fn uos_zlp_sliding_replay_check(high_seq: u64, bitmap: u64, seq: u64) callconv(.c) u64;
extern fn uos_zlp_sliding_replay_advance(high_seq: u64, bitmap: u64, seq: u64) callconv(.c) u64;
extern fn uos_zlp_lyapunov_q16_gate(prev_energy: u64, curr_val: u64, target_val: u64) callconv(.c) u64;
extern fn uos_zlp_scale_budget_gate(writers: u32, reviewers: u32, is_writer: u8, spent_uusd: u64, now_us: u64, lease_us: u64) callconv(.c) u8;
extern fn uos_zlp_risk_priority_score(safety_rdy: u8, dep_rdy: u8, crit: u32, stpa: u32, fmea: u32, dep: u32, impact: u32) callconv(.c) u64;

const MAX_PAYLOAD: usize = 1_048_576;

const Status = enum(u8) {
    ok = 0,
    bad_header = 1,
    simd512_nul_trap = 2,
    simd_depth_overflow = 3,
    replay_or_expired = 4,
    policy_refused = 5,
    scale_or_risk_refused = 6,
    zenoh_io_error = 7,
    heavy_queue_full = 8,
    zenoh_push_event = 0x83,
    ok_with_body = 0x84,
};

fn readExact(fd: i32, buf: [*]u8, len: usize) bool {
    var off: usize = 0;
    while (off < len) {
        const rc = linux.read(fd, buf + off, len - off);
        const signed: isize = @bitCast(rc);
        if (signed <= 0) {
            if (signed < 0 and (-signed) == 4) continue;
            return false;
        }
        off += rc;
    }
    return true;
}

fn writeExact(fd: i32, buf: [*]const u8, len: usize) bool {
    var off: usize = 0;
    while (off < len) {
        const rc = linux.write(fd, buf + off, len - off);
        const signed: isize = @bitCast(rc);
        if (signed <= 0) {
            if (signed < 0 and (-signed) == 4) continue;
            return false;
        }
        off += rc;
    }
    return true;
}

fn sendReply24(st: Status, excl: u8, sub: u8, req_id: u64, val: u64) bool {
    var resp: [24]u8 = undefined;
    std.mem.writeInt(u32, resp[0..4], 20, .big);
    resp[4] = 0x55;
    resp[5] = @intFromEnum(st);
    resp[6] = excl;
    resp[7] = sub;
    std.mem.writeInt(u64, resp[8..16], req_id, .big);
    std.mem.writeInt(u64, resp[16..24], val, .big);
    return writeExact(1, &resp, 24);
}

fn sendBodyFrame(st: Status, excl: u8, sub: u8, req_id: u64, digest: u64, body_slice: []const u8) bool {
    var hdr: [24]u8 = undefined;
    const frame_len: u32 = @intCast(20 + body_slice.len);
    std.mem.writeInt(u32, hdr[0..4], frame_len, .big);
    hdr[4] = 0x55;
    hdr[5] = @intFromEnum(st);
    hdr[6] = excl;
    hdr[7] = sub;
    std.mem.writeInt(u64, hdr[8..16], req_id, .big);
    std.mem.writeInt(u64, hdr[16..24], digest, .big);
    if (!writeExact(1, &hdr, 24)) return false;
    if (body_slice.len > 0) {
        if (!writeExact(1, body_slice.ptr, body_slice.len)) return false;
    }
    return true;
}

/// Zen 5 512-bit AVX-512 (@Vector(64, u8)) NUL-byte trap + JSON depth <= 32 gatekeeper
fn simd512Gatekeep(ptr: [*]const u8, len: usize, check_json_depth: bool) Status {
    const Vec64 = @Vector(64, u8);
    const zero: Vec64 = @splat(0);
    var i: usize = 0;
    while (i + 64 <= len) : (i += 64) {
        const chunk: Vec64 = ptr[i..][0..64].*;
        if (@reduce(.Or, chunk == zero)) return .simd512_nul_trap;
    }
    while (i < len) : (i += 1) {
        if (ptr[i] == 0) return .simd512_nul_trap;
    }
    if (check_json_depth) {
        var depth: i32 = 0;
        var in_str: bool = false;
        var esc: bool = false;
        var j: usize = 0;
        while (j < len) : (j += 1) {
            const c = ptr[j];
            if (in_str) {
                if (esc) {
                    esc = false;
                } else if (c == '\\') {
                    esc = true;
                } else if (c == '"') {
                    in_str = false;
                }
            } else {
                if (c == '"') {
                    in_str = true;
                } else if (c == '{' or c == '[') {
                    depth += 1;
                    if (depth > 32) return .simd_depth_overflow;
                } else if (c == '}' or c == ']') {
                    depth -= 1;
                    if (depth < 0) return .simd_depth_overflow;
                }
            }
        }
        if (depth != 0 or in_str) return .simd_depth_overflow;
    }
    return .ok;
}

const MAX_SSE_SUBS = 16;
const SseSlot = struct {
    fd: i32 = -1,
    used: usize = 0,
    buf: [65536]u8 = undefined,
};

var g_get_buf: [262144]u8 = undefined;

pub fn main() void {
    var epfd: c_int = -1;
    var heavy_efd: c_int = -1;
    if (zlp_v3_boot(&epfd, &heavy_efd) != 0) linux.exit_group(10);

    const slab = zlp_alloc_slab(MAX_PAYLOAD);
    const slab_ptr = zlp_slab_ptr(slab);
    const topic_slab = zlp_alloc_slab(1024);

    var sse_slots: [MAX_SSE_SUBS]SseSlot = [_]SseSlot{.{}} ** MAX_SSE_SUBS;
    var active_sse_count: u32 = 0;
    var in_flight_heavy: u32 = 0;

    var high_seq: u64 = 0;
    var replay_bitmap: u64 = 0;
    var prev_lyap_energy: u64 = 1_000_000;

    var len_be: [4]u8 = undefined;
    var hdr: [20]u8 = undefined;

    var running = true;
    while (running) {
        var ready_fd: c_int = -1;
        var revents: u32 = 0;
        const n = zlp_epoll_wait_one(epfd, &ready_fd, &revents, -1);
        if (n <= 0) continue;

        if (ready_fd == heavy_efd) {
            var h_req: u64 = 0;
            var h_dig: u64 = 0;
            while (zlp_pop_heavy_done(&h_req, &h_dig) == 1) {
                if (in_flight_heavy > 0) in_flight_heavy -= 1;
                if (!sendReply24(.ok, zlp_is_exclusive(slab), 2, h_req, h_dig)) {
                    running = false;
                    break;
                }
            }
        } else if (ready_fd == 0) {
            if (!readExact(0, &len_be, 4)) break;
            const frame_len = std.mem.readInt(u32, &len_be, .big);
            if (frame_len < 20 or frame_len > MAX_PAYLOAD + 20) break;
            if (!readExact(0, &hdr, 20)) break;

            const magic = hdr[0];
            const opcode = hdr[1];
            const flags = std.mem.readInt(u16, hdr[2..4], .big);
            const req_id = std.mem.readInt(u64, hdr[4..12], .big);
            const seq_id = std.mem.readInt(u64, hdr[12..20], .big);
            const payload_len: usize = @as(usize, frame_len) - 20;
            if (magic != 0x55) break;

            if (payload_len > 0) {
                if (!readExact(0, slab_ptr, payload_len)) break;
            }

            if (opcode == 0x01) {
                const check_depth = (flags & 1) != 0;
                var st = simd512Gatekeep(slab_ptr, payload_len, check_depth);
                var digest: u64 = 0;
                if (st == .ok) {
                    if (seq_id != 0) {
                        if (uos_zlp_sliding_replay_check(high_seq, replay_bitmap, seq_id) == 0) {
                            st = .replay_or_expired;
                        } else {
                            replay_bitmap = uos_zlp_sliding_replay_advance(high_seq, replay_bitmap, seq_id);
                            if (seq_id > high_seq) high_seq = seq_id;
                        }
                    }
                    if (st == .ok) {
                        const lyap = uos_zlp_lyapunov_q16_gate(prev_lyap_energy, 1000, 1000);
                        prev_lyap_energy = lyap & 0x3FFFFFFFFFFFFFFF;
                        zlp_set_size(slab, payload_len);
                        digest = zlp_eval_retain_slab(slab);
                        if (digest == 0) st = .policy_refused;
                    }
                }
                if (!sendReply24(st, zlp_is_exclusive(slab), 1, req_id, digest)) break;
            } else if (opcode == 0x02) {
                if (payload_len != 55) {
                    if (!sendReply24(.bad_header, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                } else {
                    const w = std.mem.readInt(u32, slab_ptr[0..4], .big);
                    const r = std.mem.readInt(u32, slab_ptr[4..8], .big);
                    const is_w = slab_ptr[8];
                    const spent = std.mem.readInt(u64, slab_ptr[9..17], .big);
                    const now_u = std.mem.readInt(u64, slab_ptr[17..25], .big);
                    const lease_u = std.mem.readInt(u64, slab_ptr[25..33], .big);
                    const safe_r = slab_ptr[33];
                    const dep_r = slab_ptr[34];
                    const crit = std.mem.readInt(u32, slab_ptr[35..39], .big);
                    const stpa = std.mem.readInt(u32, slab_ptr[39..43], .big);
                    const fmea = std.mem.readInt(u32, slab_ptr[43..47], .big);
                    const dep  = std.mem.readInt(u32, slab_ptr[47..51], .big);
                    const imp  = std.mem.readInt(u32, slab_ptr[51..55], .big);

                    const scale_ok = uos_zlp_scale_budget_gate(w, r, is_w, spent, now_u, lease_u);
                    const risk_score = uos_zlp_risk_priority_score(safe_r, dep_r, crit, stpa, fmea, dep, imp);
                    const st: Status = if (scale_ok == 1 and risk_score > 0) .ok else .scale_or_risk_refused;
                    if (!sendReply24(st, zlp_is_exclusive(slab), scale_ok, req_id, risk_score)) break;
                }
            } else if (opcode == 0x05) {
                const st = simd512Gatekeep(slab_ptr, payload_len, false);
                if (st != .ok) {
                    if (!sendReply24(st, zlp_is_exclusive(slab), 2, req_id, 0)) break;
                } else {
                    const rounds: u32 = if (seq_id == 0) 2000 else @intCast(@min(seq_id, 5_000_000));
                    if (zlp_enqueue_heavy(req_id, rounds, slab_ptr, payload_len) != 0) {
                        if (!sendReply24(.heavy_queue_full, zlp_is_exclusive(slab), 2, req_id, 0)) break;
                    } else {
                        in_flight_heavy += 1;
                    }
                }
            } else if (opcode == 0x03) {
                if (simd512Gatekeep(slab_ptr, payload_len, false) != .ok or
                    zlp_guard_topic_retain_slab(topic_slab, slab_ptr, payload_len) == 0)
                {
                    if (!sendReply24(.policy_refused, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                } else {
                    var slot_idx: ?usize = null;
                    for (&sse_slots, 0..) |*s, idx| {
                        if (s.fd < 0) {
                            slot_idx = idx;
                            break;
                        }
                    }
                    if (slot_idx == null) {
                        if (!sendReply24(.zenoh_io_error, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                    } else {
                        const sfd = zlp_zenoh_open_sse(epfd, slab_ptr, payload_len);
                        if (sfd < 0) {
                            if (!sendReply24(.zenoh_io_error, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                        } else {
                            sse_slots[slot_idx.?].fd = sfd;
                            sse_slots[slot_idx.?].used = 0;
                            active_sse_count += 1;
                            if (!sendReply24(.ok, zlp_is_exclusive(slab), @intCast(active_sse_count), req_id, @intCast(sfd))) break;
                        }
                    }
                }
            } else if (opcode == 0x13) {
                if (payload_len < 3) {
                    if (!sendReply24(.bad_header, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                } else {
                    const tlen: usize = @intCast(std.mem.readInt(u16, slab_ptr[0..2], .big));
                    if (2 + tlen >= payload_len) {
                        if (!sendReply24(.bad_header, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                    } else {
                        const tptr = slab_ptr + 2;
                        const bptr = slab_ptr + 2 + tlen;
                        const blen = payload_len - 2 - tlen;
                        const body_st = simd512Gatekeep(bptr, blen, true);
                        if (body_st != .ok) {
                            if (!sendReply24(body_st, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                        } else if (zlp_guard_topic_retain_slab(topic_slab, tptr, tlen) == 0) {
                            if (!sendReply24(.policy_refused, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                        } else {
                            const prc = zlp_zenoh_put(tptr, tlen, bptr, blen);
                            const st: Status = if (prc == 0) .ok else .zenoh_io_error;
                            if (!sendReply24(st, zlp_is_exclusive(slab), 1, req_id, @intCast(blen))) break;
                        }
                    }
                }
            } else if (opcode == 0x14) {
                // Live Zenoh GET Query (payload = topic key expression)
                if (simd512Gatekeep(slab_ptr, payload_len, false) != .ok or
                    zlp_guard_topic_retain_slab(topic_slab, slab_ptr, payload_len) == 0)
                {
                    if (!sendReply24(.policy_refused, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                } else {
                    const grc = zlp_zenoh_get(slab_ptr, payload_len, &g_get_buf, g_get_buf.len);
                    if (grc < 0) {
                        if (!sendReply24(.zenoh_io_error, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                    } else {
                        const glen: usize = @intCast(grc);
                        if (glen == 0) {
                            if (!sendBodyFrame(.ok_with_body, zlp_is_exclusive(slab), 1, req_id, 1, g_get_buf[0..0])) break;
                        } else if (simd512Gatekeep(&g_get_buf, glen, false) != .ok) {
                            if (!sendReply24(.simd512_nul_trap, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                        } else {
                            @memcpy(slab_ptr[0..glen], g_get_buf[0..glen]);
                            zlp_set_size(slab, glen);
                            const dig = zlp_eval_retain_slab(slab);
                            if (dig == 0) {
                                if (!sendReply24(.policy_refused, zlp_is_exclusive(slab), 0, req_id, 0)) break;
                            } else {
                                if (!sendBodyFrame(.ok_with_body, zlp_is_exclusive(slab), 1, req_id, dig, g_get_buf[0..glen])) break;
                            }
                        }
                    }
                }
            } else if (opcode == 0x0C) {
                const packed_info: u64 = (@as(u64, zlp_get_pid()) << 32) |
                                         (@as(u64, active_sse_count) << 16) |
                                         @as(u64, in_flight_heavy);
                if (!sendReply24(.ok, zlp_is_exclusive(slab), 0, req_id, packed_info)) break;
            } else if (opcode == 0xFF) {
                high_seq = 0;
                replay_bitmap = 0;
                if (!sendReply24(.ok, zlp_is_exclusive(slab), 0, req_id, 0)) break;
            } else {
                if (!sendReply24(.bad_header, zlp_is_exclusive(slab), 0, req_id, 0)) break;
            }
        } else {
            for (&sse_slots) |*slot| {
                if (slot.fd == ready_fd) {
                    while (true) {
                        if (slot.used >= slot.buf.len - 1) slot.used = 0;
                        const rc = linux.read(slot.fd, slot.buf[slot.used..].ptr, slot.buf.len - slot.used);
                        const signed: isize = @bitCast(rc);
                        if (signed <= 0) break;
                        slot.used += rc;

                        var start: usize = 0;
                        var pos: usize = 0;
                        while (pos < slot.used) : (pos += 1) {
                            if (slot.buf[pos] == '\n') {
                                var line = slot.buf[start..pos];
                                if (line.len > 0 and line[line.len - 1] == '\r') {
                                    line = line[0 .. line.len - 1];
                                }
                                if (line.len > 5 and std.mem.eql(u8, line[0..5], "data:")) {
                                    const json_data = std.mem.trimStart(u8, line[5..], " ");
                                    if (json_data.len > 0 and json_data.len <= MAX_PAYLOAD) {
                                        if (simd512Gatekeep(json_data.ptr, json_data.len, false) == .ok) {
                                            @memcpy(slab_ptr[0..json_data.len], json_data);
                                            zlp_set_size(slab, json_data.len);
                                            const dig = zlp_eval_retain_slab(slab);
                                            if (dig != 0) {
                                                if (!sendBodyFrame(.zenoh_push_event, zlp_is_exclusive(slab), 1, 0, dig, json_data)) {
                                                    running = false;
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                }
                                start = pos + 1;
                            }
                        }
                        if (start > 0) {
                            const rem = slot.used - start;
                            if (rem > 0) {
                                std.mem.copyForwards(u8, slot.buf[0..rem], slot.buf[start..slot.used]);
                            }
                            slot.used = rem;
                        }
                    }
                    break;
                }
            }
        }
    }
    zlp_v3_shutdown();
    linux.exit_group(0);
}
