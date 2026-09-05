//! Semantic Domain: OTLP Telemetry (W3C Trace Context + OTLP span emission)
//! ==========================================================================
//!
//! A *span* is a node in a distributed-trace tree. Its identity is a W3C
//! trace-context triple:
//!
//!   TraceContext = ( trace_id : 16 bytes    -- the trace this span belongs to
//!                  , span_id  :  8 bytes    -- this span's identity
//!                  , flags    :  1 byte )   -- sampled/… bitfield
//!
//! and a span additionally carries an OPTIONAL parent_span_id (null ⇒ root),
//! a name, a kind, and a [start,end] nanosecond interval. Spans of one trace
//! form a TREE keyed on span_id with edges child.parent_span_id → parent.span_id;
//! every span in the tree shares the SAME trace_id (trace cohesion).
//!
//! Final Encoding (the wire): the `traceparent` HTTP header
//!
//!   "00" "-" hex(trace_id) "-" hex(span_id) "-" hex(flags)
//!
//! is exactly 55 lowercase-hex bytes (`formatW3C`), and OTLP export renders a
//! span set as a JSON payload (`serializeSpans`).
//!
//! Oracle: the logical trace tree (the `TraceContext`/`Span` structs).
//! Final:  the 55-byte header + the JSON payload.
//!
//! ── Algebraic Laws (named after the property, verified below) ──────────────
//!   * TRACEPARENT ROUND-TRIP (retraction):  parseW3C ∘ formatW3C = id.
//!         encode then decode recovers the exact context, byte for byte.
//!   * WELL-FORMEDNESS (rejection):  a valid traceparent parses; a corrupt one
//!         (wrong length, non-hex, wrong version, all-zero id) is rejected.
//!   * TREE / TRACE-COHESION (homomorphism):  every child derived from a parent
//!         keeps the parent's trace_id and sets parent_span_id = parent.span_id;
//!         a nesting chain has one trace_id at every depth.
//!   * ESCAPE FAITHFULNESS (retraction) + INJECTION SAFETY:
//!         jsonUnescape ∘ jsonEscape = id, AND the escaped body carries no raw
//!         control byte and no unescaped `"`/`\` — an attacker-chosen span name
//!         can never break out of its JSON string.
//!   * SERIALIZATION HOMOMORPHISM:  the JSON payload contains, verbatim, the
//!         hex(trace_id)/hex(span_id) of every span it renders — structure is
//!         preserved across the term→wire boundary.
//!   * TRACING TRANSPARENCY (inherited from trace.zig): emitting spans off a
//!         trace sink never changes program denotation; the wiring test drives
//!         the REAL scheduler trace path and maps its events to spans.
//!
//! Scope limits: Stratum B/C integration. No Stratum-A law depends on it. The
//! Exporter is an in-process sink (captures the payload); no real socket I/O.

const std = @import("std");
const config = @import("config.zig");
const ta = @import("term_algebra.zig");

const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const TRACEPARENT_LEN: usize = 55;

pub const TraceContext = struct {
    trace_id: [16]u8,
    span_id: [8]u8,
    trace_flags: u8,

    /// Final encoding: the 55-byte W3C `traceparent` header value.
    pub fn formatW3C(self: TraceContext, buf: *[TRACEPARENT_LEN]u8) []const u8 {
        return std.fmt.bufPrint(buf, "00-{s}-{s}-{s}", .{
            std.fmt.bytesToHex(self.trace_id, .lower),
            std.fmt.bytesToHex(self.span_id, .lower),
            std.fmt.bytesToHex([1]u8{self.trace_flags}, .lower),
        }) catch unreachable;
    }

    /// Decode a `traceparent` header back into a context. Total on the wire:
    /// returns null for any malformed header (the rejection half of the law).
    /// Lenient on all-zero ids (round-trip must hold for every context);
    /// zero-id validity is a separate `isWellFormed` judgement.
    pub fn parseW3C(s: []const u8) ?TraceContext {
        if (s.len != TRACEPARENT_LEN) return null;
        if (s[2] != '-' or s[35] != '-' or s[52] != '-') return null;
        var ver: [1]u8 = undefined;
        _ = std.fmt.hexToBytes(&ver, s[0..2]) catch return null;
        if (ver[0] != 0) return null; // only version 00 is defined
        var ctx: TraceContext = undefined;
        _ = std.fmt.hexToBytes(&ctx.trace_id, s[3..35]) catch return null;
        _ = std.fmt.hexToBytes(&ctx.span_id, s[36..52]) catch return null;
        var fl: [1]u8 = undefined;
        _ = std.fmt.hexToBytes(&fl, s[53..55]) catch return null;
        ctx.trace_flags = fl[0];
        return ctx;
    }

    /// W3C validity: an all-zero trace_id or span_id is invalid (never a real
    /// trace). Round-trip does not need this; propagation/export does.
    pub fn isWellFormed(self: TraceContext) bool {
        return !isZero(&self.trace_id) and !isZero(&self.span_id);
    }

    /// Derive an in-trace child context: same trace_id + flags, fresh span_id.
    pub fn childContext(self: TraceContext, new_span_id: [8]u8) TraceContext {
        return .{ .trace_id = self.trace_id, .span_id = new_span_id, .trace_flags = self.trace_flags };
    }
};

fn isZero(bytes: []const u8) bool {
    for (bytes) |b| if (b != 0) return false;
    return true;
}

pub const Span = struct {
    trace_id: [16]u8,
    span_id: [8]u8,
    parent_span_id: ?[8]u8 = null,
    name: []const u8,
    kind: u8 = 1,
    start_time_unix_nano: u64,
    end_time_unix_nano: u64,

    /// The context that identifies this span.
    pub fn context(self: Span, flags: u8) TraceContext {
        return .{ .trace_id = self.trace_id, .span_id = self.span_id, .trace_flags = flags };
    }

    /// Build a child span nested under `parent`: it stays in the parent's
    /// trace and records parent.span_id as its parent edge (the TREE law).
    pub fn childOf(
        parent: TraceContext,
        new_span_id: [8]u8,
        name: []const u8,
        start: u64,
        end: u64,
    ) Span {
        return .{
            .trace_id = parent.trace_id,
            .span_id = new_span_id,
            .parent_span_id = parent.span_id,
            .name = name,
            .start_time_unix_nano = start,
            .end_time_unix_nano = end,
        };
    }

    pub fn isRoot(self: Span) bool {
        return self.parent_span_id == null;
    }
};

pub const Metric = struct {
    name: []const u8,
    description: []const u8,
    unit: []const u8,
    value: i64,
};

// ============================================================================
// JSON escaping — injection-safe attribute rendering
// ============================================================================

/// Append `s` as a QUOTED, escaped JSON string. Every `"`/`\`/control byte is
/// escaped so an attacker-chosen name cannot terminate the string early.
pub fn jsonEscape(out: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) !void {
    try out.append(gpa, '"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice(gpa, "\\\""),
            '\\' => try out.appendSlice(gpa, "\\\\"),
            '\n' => try out.appendSlice(gpa, "\\n"),
            '\r' => try out.appendSlice(gpa, "\\r"),
            '\t' => try out.appendSlice(gpa, "\\t"),
            0x08 => try out.appendSlice(gpa, "\\b"),
            0x0c => try out.appendSlice(gpa, "\\f"),
            else => if (c < 0x20) {
                var b: [8]u8 = undefined;
                const e = std.fmt.bufPrint(&b, "\\u{x:0>4}", .{@as(u16, c)}) catch unreachable;
                try out.appendSlice(gpa, e);
            } else {
                try out.append(gpa, c);
            },
        }
    }
    try out.append(gpa, '"');
}

/// Inverse of `jsonEscape` over the escapes it produces (the retraction half).
/// `s` is the FULL quoted token (leading+trailing `"`). Returns the decoded
/// body; caller owns it. Returns error.Invalid on a malformed token.
pub fn jsonUnescape(out: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) !void {
    if (s.len < 2 or s[0] != '"' or s[s.len - 1] != '"') return error.Invalid;
    const body = s[1 .. s.len - 1];
    var i: usize = 0;
    while (i < body.len) {
        const c = body[i];
        if (c == '\\') {
            if (i + 1 >= body.len) return error.Invalid;
            const e = body[i + 1];
            switch (e) {
                '"' => try out.append(gpa, '"'),
                '\\' => try out.append(gpa, '\\'),
                'n' => try out.append(gpa, '\n'),
                'r' => try out.append(gpa, '\r'),
                't' => try out.append(gpa, '\t'),
                'b' => try out.append(gpa, 0x08),
                'f' => try out.append(gpa, 0x0c),
                'u' => {
                    if (i + 6 > body.len) return error.Invalid;
                    var raw: [2]u8 = undefined;
                    _ = std.fmt.hexToBytes(&raw, body[i + 2 .. i + 6]) catch return error.Invalid;
                    // only the \u00XX control range is emitted by jsonEscape
                    if (raw[0] != 0) return error.Invalid;
                    try out.append(gpa, raw[1]);
                    i += 6;
                    continue;
                },
                else => return error.Invalid,
            }
            i += 2;
        } else {
            try out.append(gpa, c);
            i += 1;
        }
    }
}

/// INJECTION-SAFETY predicate on an escaped body (the bytes between the two
/// framing quotes): no raw control byte, and every `"`/`\` is a valid escape.
fn bodyIsSafe(body: []const u8) bool {
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        const c = body[i];
        if (c < 0x20) return false; // raw control byte would break the string
        if (c == '"') return false; // a bare quote would terminate the string
        if (c == '\\') {
            if (i + 1 >= body.len) return false;
            i += 1; // skip the escaped char — it is intentional, not a break
        }
    }
    return true;
}

// ============================================================================
// Exporter — OTLP JSON span emission (in-process sink)
// ============================================================================

pub const Exporter = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    last_payload: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) Exporter {
        return .{ .allocator = allocator, .endpoint = endpoint, .last_payload = null };
    }

    pub fn deinit(self: *Exporter) void {
        if (self.last_payload) |p| self.allocator.free(p);
        self.last_payload = null;
    }

    /// Render `spans` to an OTLP-shaped JSON payload and capture it. Gated on
    /// `experimental_otlp` (the invariant from the module spec).
    pub fn exportSpans(self: *Exporter, spans: []const Span) !void {
        if (!config.experimental_otlp) return;
        const payload = try serializeSpans(self.allocator, spans);
        if (self.last_payload) |p| self.allocator.free(p);
        self.last_payload = payload;
    }

    pub fn exportMetrics(self: *Exporter, metrics: []const Metric) !void {
        if (!config.experimental_otlp) return;
        _ = self;
        _ = metrics;
    }
};

/// Serialize a span set to an OTLP JSON payload. Caller owns the bytes.
/// ids render as lowercase hex (per OTLP/JSON); names are `jsonEscape`d.
pub fn serializeSpans(gpa: std.mem.Allocator, spans: []const Span) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "{\"resourceSpans\":[{\"scopeSpans\":[{\"spans\":[");
    for (spans, 0..) |sp, idx| {
        if (idx != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"traceId\":\"");
        try out.appendSlice(gpa, &std.fmt.bytesToHex(sp.trace_id, .lower));
        try out.appendSlice(gpa, "\",\"spanId\":\"");
        try out.appendSlice(gpa, &std.fmt.bytesToHex(sp.span_id, .lower));
        try out.appendSlice(gpa, "\",\"parentSpanId\":\"");
        if (sp.parent_span_id) |pid| {
            try out.appendSlice(gpa, &std.fmt.bytesToHex(pid, .lower));
        }
        try out.appendSlice(gpa, "\",\"name\":");
        try jsonEscape(&out, gpa, sp.name);
        var num: [64]u8 = undefined;
        const kline = std.fmt.bufPrint(&num, ",\"kind\":{d},\"startTimeUnixNano\":\"{d}\",\"endTimeUnixNano\":\"{d}\"}}", .{ sp.kind, sp.start_time_unix_nano, sp.end_time_unix_nano }) catch unreachable;
        try out.appendSlice(gpa, kline);
    }
    try out.appendSlice(gpa, "]}]}]}");
    return out.toOwnedSlice(gpa);
}

// ============================================================================
// Trace-path bridge — maps a live scheduler trace event to an OTLP span, so
// otlp is REACHABLE from the real VM trace surface (not dormant).
// ============================================================================

/// Build a child span for one traced slice under `root`. The span_id is
/// derived deterministically from (pid, seq) so distinct events get distinct,
/// non-zero span_ids while staying in the root's trace.
pub fn spanFromTraceEvent(
    root: TraceContext,
    pid: u32,
    seq: u32,
    reductions: u64,
    start: u64,
    end: u64,
    name: []const u8,
) Span {
    var sid: [8]u8 = undefined;
    // mix pid/seq/reductions; +1 guarantees non-zero low byte
    std.mem.writeInt(u32, sid[0..4], pid ^ 0x9e3779b9, .big);
    std.mem.writeInt(u32, sid[4..8], (seq +% 1) ^ @as(u32, @truncate(reductions)), .big);
    if (isZero(&sid)) sid[7] = 1;
    return Span.childOf(root, sid, name, start, end);
}

// ============================================================================
// Generators
// ============================================================================

fn genContext(prng: *std.Random.DefaultPrng) TraceContext {
    const r = prng.random();
    var ctx: TraceContext = undefined;
    r.bytes(&ctx.trace_id);
    r.bytes(&ctx.span_id);
    ctx.trace_flags = r.int(u8);
    // keep ids well-formed for the propagation/export laws
    if (isZero(&ctx.trace_id)) ctx.trace_id[0] = 1;
    if (isZero(&ctx.span_id)) ctx.span_id[0] = 1;
    return ctx;
}

// ============================================================================
// Laws
// ============================================================================

test "OTLP existing: W3C Trace Context vector" {
    const ctx = TraceContext{
        .trace_id = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
        .span_id = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 },
        .trace_flags = 1,
    };
    var buf: [TRACEPARENT_LEN]u8 = undefined;
    const str = ctx.formatW3C(&buf);
    try std.testing.expectEqualStrings("00-0102030405060708090a0b0c0d0e0f10-0102030405060708-01", str);
}

test "LAW traceparent round-trip: parseW3C ∘ formatW3C = id" {
    const cfg = LawConfig{ .seed = 0x07217 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const ctx = genContext(&prng);
        var buf: [TRACEPARENT_LEN]u8 = undefined;
        const hdr = ctx.formatW3C(&buf);
        try expectLaw(hdr.len == TRACEPARENT_LEN, "traceparent is exactly 55 bytes", cfg, i);
        const back = TraceContext.parseW3C(hdr) orelse {
            try expectLaw(false, "traceparent re-parses", cfg, i);
            unreachable;
        };
        try expectLaw(std.mem.eql(u8, &ctx.trace_id, &back.trace_id), "trace_id preserved", cfg, i);
        try expectLaw(std.mem.eql(u8, &ctx.span_id, &back.span_id), "span_id preserved", cfg, i);
        try expectLaw(ctx.trace_flags == back.trace_flags, "flags preserved", cfg, i);
    }
}

test "LAW well-formedness rejection: corrupt traceparents are rejected" {
    const cfg = LawConfig{ .seed = 0x0B33F };
    // a canonical valid header parses
    const good = "00-0102030405060708090a0b0c0d0e0f10-0102030405060708-01";
    try expectLaw(TraceContext.parseW3C(good) != null, "valid header parses", cfg, 0);
    // wrong length
    try expectLaw(TraceContext.parseW3C("00-00-00") == null, "short header rejected", cfg, 1);
    // non-hex where hex required (a 'g' at position 3)
    try expectLaw(TraceContext.parseW3C("00-g102030405060708090a0b0c0d0e0f10-0102030405060708-01") == null, "non-hex rejected", cfg, 2);
    // unknown version (ff)
    try expectLaw(TraceContext.parseW3C("ff-0102030405060708090a0b0c0d0e0f10-0102030405060708-01") == null, "unknown version rejected", cfg, 3);
    // misplaced delimiter
    try expectLaw(TraceContext.parseW3C("0001-02030405060708090a0b0c0d0e0f10-0102030405060708-01") == null, "bad delimiter rejected", cfg, 4);
    // all-zero id is a valid ROUND-TRIP but not well-formed
    const z = TraceContext{ .trace_id = [_]u8{0} ** 16, .span_id = [_]u8{0} ** 8, .trace_flags = 0 };
    try expectLaw(!z.isWellFormed(), "all-zero context is not well-formed", cfg, 5);
    var buf: [TRACEPARENT_LEN]u8 = undefined;
    try expectLaw(TraceContext.parseW3C(z.formatW3C(&buf)) != null, "all-zero still round-trips", cfg, 6);
    // a generated non-zero context is well-formed
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        try expectLaw(genContext(&prng).isWellFormed(), "non-zero context well-formed", cfg, 7 + i);
    }
}

test "LAW tree / trace-cohesion: a nesting chain keeps one trace_id" {
    const cfg = LawConfig{ .seed = 0x77EE5 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const r = prng.random();
    var root = genContext(&prng);
    // build a depth-8 nesting chain
    var parent = root;
    var depth: usize = 0;
    while (depth < 8) : (depth += 1) {
        var sid: [8]u8 = undefined;
        r.bytes(&sid);
        if (isZero(&sid)) sid[0] = 1;
        const child = Span.childOf(parent, sid, "work", depth, depth + 1);
        // cohesion: same trace_id at every depth
        try expectLaw(std.mem.eql(u8, &child.trace_id, &root.trace_id), "child stays in the trace", cfg, depth);
        // tree edge: child's parent == parent's span
        try expectLaw(child.parent_span_id != null, "non-root has a parent edge", cfg, depth);
        try expectLaw(std.mem.eql(u8, &child.parent_span_id.?, &parent.span_id), "parent edge = parent span_id", cfg, depth);
        try expectLaw(!child.isRoot(), "derived span is not a root", cfg, depth);
        parent = child.context(root.trace_flags);
    }
}

test "LAW escape faithfulness + injection safety" {
    const gpa = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x1FEED };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const r = prng.random();
    // adversarial alphabet: quotes, backslashes, control bytes, newlines
    const alphabet = [_]u8{ '"', '\\', '\n', '\r', '\t', 0x00, 0x01, 0x1f, 'a', 'Z', '0', ' ', '{', '}' };
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const n = r.uintLessThan(usize, 24);
        var name: std.ArrayList(u8) = .empty;
        defer name.deinit(gpa);
        var k: usize = 0;
        while (k < n) : (k += 1) try name.append(gpa, alphabet[r.uintLessThan(usize, alphabet.len)]);

        var esc: std.ArrayList(u8) = .empty;
        defer esc.deinit(gpa);
        try jsonEscape(&esc, gpa, name.items);

        // framing: starts and ends with a quote
        try expectLaw(esc.items.len >= 2 and esc.items[0] == '"' and esc.items[esc.items.len - 1] == '"', "escaped token is quoted", cfg, i);
        // injection safety: the body cannot break out of the string
        try expectLaw(bodyIsSafe(esc.items[1 .. esc.items.len - 1]), "escaped body is injection-safe", cfg, i);

        // faithfulness: unescape recovers the original bytes exactly
        var dec: std.ArrayList(u8) = .empty;
        defer dec.deinit(gpa);
        try jsonUnescape(&dec, gpa, esc.items);
        try expectLaw(std.mem.eql(u8, dec.items, name.items), "jsonUnescape ∘ jsonEscape = id", cfg, i);
    }
}

test "LAW serialization homomorphism: payload carries every span's ids" {
    const gpa = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x5E812 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const r = prng.random();
    const root = genContext(&prng);

    var spans: std.ArrayList(Span) = .empty;
    defer spans.deinit(gpa);
    const count = 1 + r.uintLessThan(usize, 8);
    var s: usize = 0;
    while (s < count) : (s += 1) {
        spans.append(gpa, spanFromTraceEvent(root, @intCast(s), @intCast(s * 3), s, s, s + 10, "slice")) catch unreachable;
    }

    var exp = Exporter.init(gpa, "http://localhost:4318/v1/traces");
    defer exp.deinit();
    try exp.exportSpans(spans.items);
    const payload = exp.last_payload orelse {
        try expectLaw(false, "export produced a payload", cfg, 0);
        unreachable;
    };

    for (spans.items, 0..) |sp, idx| {
        var tbuf: [48]u8 = undefined; // "traceId":" + 32 hex + framing
        const thex = std.fmt.bufPrint(&tbuf, "\"traceId\":\"{s}\"", .{std.fmt.bytesToHex(sp.trace_id, .lower)}) catch unreachable;
        try expectLaw(std.mem.indexOf(u8, payload, thex) != null, "payload carries trace_id hex", cfg, idx);
        var sbuf: [30]u8 = undefined;
        const shex = std.fmt.bufPrint(&sbuf, "\"spanId\":\"{s}\"", .{std.fmt.bytesToHex(sp.span_id, .lower)}) catch unreachable;
        try expectLaw(std.mem.indexOf(u8, payload, shex) != null, "payload carries span_id hex", cfg, idx);
        // trace cohesion is visible on the wire too
        try expectLaw(std.mem.eql(u8, &sp.trace_id, &root.trace_id), "wire span shares the trace", cfg, idx);
    }
}

// ============================================================================
// WIRING: otlp reachable from the REAL scheduler trace path (trace.zig).
// Drives the live traced scheduler, maps each TraceEvent to an OTLP span, and
// exports — proving otlp is no longer dormant while inheriting TRANSPARENCY.
// ============================================================================

test "WIRING: live trace events emit well-formed OTLP spans under one trace" {
    const proc = @import("proc.zig");
    const trace = @import("trace.zig");
    const AtomTable = ta.AtomTable;
    const gpa = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x0A71E };

    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();

    // a self-halting process so the scheduler produces trace slices
    const prog: @import("instr_algebra.zig").Program = &.{
        .{ .add = .{ .a = .{ .imm = 1 }, .b = .{ .imm = 2 }, .dst = 0 } },
        .{ .halt = .{ .src = .{ .x = 0 } } },
    };
    _ = try vm.spawn(prog, 0, null);

    var sink: std.ArrayList(trace.TraceEvent) = .empty;
    defer sink.deinit(gpa);
    try trace.driveTraced(&vm, .round_robin, 8, 64, &sink, gpa);
    try expectLaw(sink.items.len > 0, "live trace produced events", cfg, 0);

    // a root trace-context for this run
    const root = TraceContext{
        .trace_id = [_]u8{0xAB} ** 16,
        .span_id = [_]u8{0xCD} ** 8,
        .trace_flags = 1,
    };
    try expectLaw(root.isWellFormed(), "root context well-formed", cfg, 1);

    var spans: std.ArrayList(Span) = .empty;
    defer spans.deinit(gpa);
    for (sink.items, 0..) |ev, i| {
        const sp = spanFromTraceEvent(root, ev.pid, @intCast(i), ev.reductions, ev.reductions, ev.reductions + 1, "grant");
        // every emitted span is in the root's trace, is a child, non-zero id
        try expectLaw(std.mem.eql(u8, &sp.trace_id, &root.trace_id), "span in run trace", cfg, i);
        try expectLaw(!sp.isRoot(), "span parented on the run root", cfg, i);
        try expectLaw(sp.context(1).isWellFormed(), "emitted span id well-formed", cfg, i);
        spans.append(gpa, sp) catch unreachable;
    }

    var exp = Exporter.init(gpa, "http://localhost:4318/v1/traces");
    defer exp.deinit();
    try exp.exportSpans(spans.items);
    try expectLaw(exp.last_payload != null and exp.last_payload.?.len > 0, "OTLP payload emitted from live trace", cfg, 0);
}
