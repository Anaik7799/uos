//! beam-zig M5 / S19: the **mailbox algebra** (cf. erts erl_message.c and
//! the modern in-transit/inner queue split of erl_proc_sig_queue.c).
//!
//! Signature:
//!   empty    : () -> Mbox
//!   deliver  : (Mbox, sender, Term) -> Mbox       (constructor action)
//!   recvMatch: (Mbox, Pattern) -> ?(Msg, Bindings)  + removal (observation)
//!   toSeq    : Mbox -> [Msg]                      (the semantic domain)
//!   peekAt   : (Mbox, cursor) -> ?Msg             (E1.11: read at the BEAM
//!              receive save-pointer, NO removal — a pure observation over toSeq)
//!   removeAt : (Mbox, cursor) -> ()               (E1.11: commit the peeked pop;
//!              a cursor past the queue is a no-op — never removes a phantom)
//!
//! Semantic domain: the arrival-ordered message sequence. Every law is a
//! statement about toSeq.
//!
//! Laws:
//!   FIFO-PER-SENDER   the subsequence from any one sender preserves its
//!                     delivery order (projection of the signal-order law,
//!                     THE erts invariant, adopted verbatim at M7)
//!   FIRST-MATCH       recvMatch returns the FIRST message in arrival order
//!                     that matches the pattern
//!   REMOVE-EXACTLY-ONE the remaining sequence is the original minus that
//!                     one message; prefix and suffix verbatim, order intact
//!   NO-MATCH-UNTOUCHED a failing recvMatch returns null and the mailbox
//!                     sequence is unchanged
//!   HOMOMORPHISM      initial (flat arrival log — the oracle) and final
//!                     (erts-shaped: per-sender in-transit buffers merged
//!                     into an inner queue on receive) denote the same
//!                     sequence after every operation
//!   PEEK/REMOVE-AT    (E1.11) peekAt returns the SAME message on both
//!                     encodings; removeAt drops EXACTLY that one (count −1,
//!                     suffix preserved) and keeps the twins denoting the same
//!                     sequence — the save-pointer receive is a pure operation
//!
//! The final encoding is deliberately erts-shaped: `deliver` appends to a
//! per-sender buffer (cheap, contention-free in the real VM); `recvMatch`
//! first MERGES buffered messages into the inner queue by global arrival
//! stamp, then scans. The merge is exactly the part that can silently break
//! FIFO — which is why the laws exist.

const std = @import("std");
const ta = @import("term_algebra.zig");
const pat = @import("pattern_algebra.zig");

const AtomTable = ta.AtomTable;
const InitialTerms = ta.InitialTerms;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const Sender = u32;

pub fn Msg(comptime Impl: type) type {
    return struct { sender: Sender, stamp: u64, payload: Impl.Term };
}

/// INITIAL ENCODING — the oracle: a flat arrival log. deliver appends;
/// recvMatch is a linear scan + remove. Cannot be wrong.
pub fn InitialMbox(comptime Impl: type) type {
    return struct {
        const Self = @This();
        pub const M = Msg(Impl);

        gpa: std.mem.Allocator,
        log: std.ArrayList(M),
        next_stamp: u64 = 0,

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .gpa = gpa, .log = .empty };
        }
        pub fn deinit(self: *Self) void {
            self.log.deinit(self.gpa);
        }

        pub fn deliver(self: *Self, sender: Sender, payload: Impl.Term) !void {
            try self.log.append(self.gpa, .{ .sender = sender, .stamp = self.next_stamp, .payload = payload });
            self.next_stamp += 1;
        }

        pub const Recv = struct { msg: M, bindings: pat.Bindings(Impl) };

        pub fn recvMatch(self: *Self, ctx: *Impl.Ctx, p: *const pat.Pattern(Impl)) ?Recv {
            for (self.log.items, 0..) |m, i| {
                var b = pat.Bindings(Impl){};
                if (pat.match(Impl, ctx, p, m.payload, &b)) {
                    _ = self.log.orderedRemove(i);
                    return .{ .msg = m, .bindings = b };
                }
            }
            return null;
        }

        /// The denotation: arrival-ordered sequence (borrowed slice).
        pub fn toSeq(self: *Self, buf: []M) []const M {
            @memcpy(buf[0..self.log.items.len], self.log.items);
            return buf[0..self.log.items.len];
        }
        pub fn len(self: *const Self) usize {
            return self.log.items.len;
        }

        /// E1.11: PEEK the message at position `cursor` in the arrival sequence
        /// WITHOUT removing it (the BEAM receive save-pointer). A pure observation
        /// over the denotation; null iff the cursor is past the queue.
        pub fn peekAt(self: *Self, cursor: usize) ?M {
            if (cursor >= self.log.items.len) return null;
            return self.log.items[cursor];
        }
        /// E1.11: REMOVE the message at `cursor` (commit the peeked pop). Guarded:
        /// a cursor past the queue is a no-op — this never removes a phantom.
        pub fn removeAt(self: *Self, cursor: usize) void {
            if (cursor >= self.log.items.len) return;
            _ = self.log.orderedRemove(cursor);
        }
    };
}

/// FINAL ENCODING — erts-shaped: per-sender in-transit buffers, merged into
/// the inner queue (by arrival stamp) when the receiver looks.
pub fn FinalMbox(comptime Impl: type) type {
    return struct {
        const Self = @This();
        pub const M = Msg(Impl);
        const max_senders = 8;

        gpa: std.mem.Allocator,
        inner: std.ArrayList(M),
        in_transit: [max_senders]std.ArrayList(M),
        // e50-eep76: the PRIORITY lane — messages sent to a priority alias.
        // flush() drains this FIRST (ahead of the normal k-way merge), so a
        // priority message is received before any non-priority message
        // regardless of arrival order (EEP-76). Front-of-mailbox semantics.
        prio: std.ArrayList(M),
        next_stamp: u64 = 0,

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .gpa = gpa, .inner = .empty, .in_transit = @splat(.empty), .prio = .empty };
        }
        pub fn deinit(self: *Self) void {
            self.inner.deinit(self.gpa);
            for (&self.in_transit) |*q| q.deinit(self.gpa);
            self.prio.deinit(self.gpa);
        }
        /// e50-eep76: deliver a PRIORITY message (sent to a priority alias) —
        /// it jumps ahead of all normal messages in the mailbox.
        pub fn deliverPrio(self: *Self, sender: Sender, payload: Impl.Term) !void {
            try self.prio.append(self.gpa, .{ .sender = sender, .stamp = self.next_stamp, .payload = payload });
            self.next_stamp += 1;
        }

        pub fn deliver(self: *Self, sender: Sender, payload: Impl.Term) !void {
            const lane = sender % max_senders;
            try self.in_transit[lane].append(self.gpa, .{
                .sender = sender,
                .stamp = self.next_stamp,
                .payload = payload,
            });
            self.next_stamp += 1;
        }

        /// Merge all in-transit buffers into the inner queue, by stamp.
        /// Each buffer is already stamp-ascending (append order), so this is
        /// a k-way merge; the LAWS are what force it to be correct.
        fn flush(self: *Self) !void {
            // e50-eep76: PRIORITY messages first — prepend the prio lane (in
            // stamp order) ahead of the merged normal queue, so a receive sees
            // them before any non-priority message (EEP-76 front-of-mailbox).
            if (self.prio.items.len > 0) {
                try self.inner.insertSlice(self.gpa, 0, self.prio.items);
                self.prio.clearRetainingCapacity();
            }
            var heads: [max_senders]usize = @splat(0);
            while (true) {
                var best: ?usize = null;
                for (0..max_senders) |lane| {
                    const q = self.in_transit[lane].items;
                    if (heads[lane] >= q.len) continue;
                    if (best == null or q[heads[lane]].stamp < self.in_transit[best.?].items[heads[best.?]].stamp)
                        best = lane;
                }
                const lane = best orelse break;
                try self.inner.append(self.gpa, self.in_transit[lane].items[heads[lane]]);
                heads[lane] += 1;
            }
            for (&self.in_transit) |*q| q.clearRetainingCapacity();
        }

        pub const Recv = struct { msg: M, bindings: pat.Bindings(Impl) };

        pub fn recvMatch(self: *Self, ctx: *Impl.Ctx, p: *const pat.Pattern(Impl)) !?Recv {
            try self.flush();
            for (self.inner.items, 0..) |m, i| {
                var b = pat.Bindings(Impl){};
                if (pat.match(Impl, ctx, p, m.payload, &b)) {
                    _ = self.inner.orderedRemove(i);
                    return .{ .msg = m, .bindings = b };
                }
            }
            return null;
        }

        /// Denotation: inner queue followed by merged in-transit — i.e. what
        /// flush would produce, WITHOUT mutating (observation stays pure).
        pub fn toSeq(self: *Self, buf: []M) []const M {
            var n: usize = 0;
            for (self.inner.items) |m| {
                buf[n] = m;
                n += 1;
            }
            const start = n;
            for (self.in_transit) |q| {
                for (q.items) |m| {
                    buf[n] = m;
                    n += 1;
                }
            }
            // stable-sort the in-transit tail by stamp (merge semantics)
            std.sort.insertion(M, buf[start..n], {}, struct {
                fn less(_: void, x: M, y: M) bool {
                    return x.stamp < y.stamp;
                }
            }.less);
            return buf[0..n];
        }
        pub fn len(self: *const Self) usize {
            var n = self.inner.items.len + self.prio.items.len;
            for (self.in_transit) |q| n += q.items.len;
            return n;
        }

        /// E1.11: PEEK the message at `cursor` in the arrival sequence WITHOUT
        /// removing it. FLUSH first (merge in-transit into the inner queue by
        /// stamp — denotation-preserving), then index; null iff past the queue.
        pub fn peekAt(self: *Self, cursor: usize) !?M {
            try self.flush();
            if (cursor >= self.inner.items.len) return null;
            return self.inner.items[cursor];
        }
        /// E1.11: REMOVE the message at `cursor` (commit the peeked pop). Flush,
        /// then remove. Guarded: a cursor past the queue is a no-op — never
        /// removes a phantom message.
        pub fn removeAt(self: *Self, cursor: usize) !void {
            try self.flush();
            if (cursor >= self.inner.items.len) return;
            _ = self.inner.orderedRemove(cursor);
        }
    };
}

// ============================================================================
// Law suite
// ============================================================================

const MAXQ = 128;

fn seqEq(
    comptime Impl: type,
    ctx: *Impl.Ctx,
    a: []const Msg(Impl),
    b: []const Msg(Impl),
) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x.sender != y.sender or x.stamp != y.stamp) return false;
        if (!Impl.eqlExact(ctx, x.payload, y.payload)) return false;
    }
    return true;
}

pub fn verifyMailboxLaws(gpa: std.mem.Allocator, cfg: LawConfig) !void {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var oracle = InitialMbox(FinalTerms).init(gpa);
        defer oracle.deinit();
        var final = FinalMbox(FinalTerms).init(gpa);
        defer final.deinit();

        var buf_a: [MAXQ]Msg(FinalTerms) = undefined;
        var buf_b: [MAXQ]Msg(FinalTerms) = undefined;

        // Random op walk: deliveries from random senders (payload = tagged
        // int so first-match is checkable), interleaved with selective
        // receives; the two encodings run in lockstep.
        for (0..60) |_| {
            if (random.uintLessThan(u8, 3) != 0) { // deliver
                const sender: Sender = random.uintLessThan(Sender, 5);
                const val = random.uintLessThan(u16, 8);
                const payload = FinalTerms.int(&ctx, val);
                try oracle.deliver(sender, payload);
                try final.deliver(sender, payload);
            } else { // selective receive of a random value class
                const want = random.uintLessThan(u16, 8);
                const litp = pat.Pattern(FinalTerms){ .plit = FinalTerms.int(&ctx, want) };
                // ORACLE ANSWER: first arrival-ordered match
                const before = oracle.toSeq(&buf_a);
                var expect_stamp: ?u64 = null;
                for (before) |m| {
                    if (FinalTerms.eqlExact(&ctx, m.payload, FinalTerms.int(&ctx, want))) {
                        expect_stamp = m.stamp;
                        break;
                    }
                }
                const ro = oracle.recvMatch(&ctx, &litp);
                const rf = try final.recvMatch(&ctx, &litp);
                try expectLaw((ro == null) == (rf == null), "mailbox: twin verdicts agree", cfg, i);
                if (ro) |r| {
                    try expectLaw(expect_stamp != null and r.msg.stamp == expect_stamp.?, "mailbox: FIRST match in arrival order (oracle)", cfg, i);
                    try expectLaw(rf.?.msg.stamp == expect_stamp.?, "mailbox: FIRST match in arrival order (final)", cfg, i);
                } else {
                    try expectLaw(expect_stamp == null, "mailbox: null iff nothing matches", cfg, i);
                }
            }
            // HOMOMORPHISM: sequences agree after every single op
            try expectLaw(seqEq(
                FinalTerms,
                &ctx,
                oracle.toSeq(&buf_a),
                final.toSeq(&buf_b),
            ), "mailbox: oracle and erts-shaped queue denote the same sequence", cfg, i);
        }

        // FIFO PER SENDER on the final state
        const seq = final.toSeq(&buf_b);
        var last_stamp: [8]?u64 = @splat(null);
        for (seq) |m| {
            const lane = m.sender % 8;
            if (last_stamp[lane]) |prev|
                try expectLaw(m.stamp > prev, "mailbox: FIFO per sender", cfg, i);
            last_stamp[lane] = m.stamp;
        }

        // E1.11 PEEK/REMOVE-AT HOMOMORPHISM: a save-pointer cursor peek/pop is a
        // pure operation over the arrival sequence, so the two encodings agree.
        // For a random in-range cursor: peekAt returns the SAME message on both,
        // and removeAt drops EXACTLY that one (count −1, suffix preserved, twins
        // still denote the same sequence). A cursor past the queue is a no-op.
        {
            const n0 = final.len();
            const cur: usize = if (n0 == 0) 0 else random.uintLessThan(usize, n0 + 1);
            const po = oracle.peekAt(cur);
            const pf = try final.peekAt(cur);
            try expectLaw((po == null) == (pf == null), "mailbox: peekAt agreement (present/absent)", cfg, i);
            if (po) |mo| try expectLaw(
                mo.stamp == pf.?.stamp and mo.sender == pf.?.sender and
                    FinalTerms.eqlExact(&ctx, mo.payload, pf.?.payload),
                "mailbox: peekAt returns the same message on both encodings",
                cfg,
                i,
            );
            oracle.removeAt(cur);
            try final.removeAt(cur);
            try expectLaw(oracle.len() == final.len(), "mailbox: removeAt keeps the twins the same length", cfg, i);
            const expect_len = if (cur < n0) n0 - 1 else n0;
            try expectLaw(final.len() == expect_len, "mailbox: removeAt drops exactly one iff cursor in range", cfg, i);
            try expectLaw(seqEq(FinalTerms, &ctx, oracle.toSeq(&buf_a), final.toSeq(&buf_b)), "mailbox: removeAt preserves the homomorphism", cfg, i);
        }

        // REMOVE-EXACTLY-ONE: take a snapshot, receive, diff — on BOTH
        // encodings so the twins stay in lockstep.
        const snap_n = final.len();
        if (snap_n > 0) {
            var snap: [MAXQ]Msg(FinalTerms) = undefined;
            const before = final.toSeq(&snap);
            const first = before[0];
            const anyp = pat.Pattern(FinalTerms){ .pwild = {} };
            const r = (try final.recvMatch(&ctx, &anyp)).?;
            const ro = oracle.recvMatch(&ctx, &anyp).?;
            try expectLaw(r.msg.stamp == first.stamp, "mailbox: wildcard receive takes the oldest", cfg, i);
            try expectLaw(ro.msg.stamp == first.stamp, "mailbox: wildcard receive takes the oldest (oracle)", cfg, i);
            const after = final.toSeq(&buf_b);
            try expectLaw(after.len == snap_n - 1, "mailbox: receive removes exactly one", cfg, i);
            for (after, before[1..]) |x, y| {
                try expectLaw(x.stamp == y.stamp, "mailbox: suffix undisturbed after receive", cfg, i);
            }
        }

        // NO-MATCH-UNTOUCHED
        const nope = pat.Pattern(FinalTerms){ .plit = FinalTerms.atom(&ctx, try atoms.intern("never_sent")) };
        const before2 = oracle.toSeq(&buf_a);
        try expectLaw(oracle.recvMatch(&ctx, &nope) == null, "mailbox: no-match returns null (oracle)", cfg, i);
        try expectLaw((try final.recvMatch(&ctx, &nope)) == null, "mailbox: no-match returns null (final)", cfg, i);
        try expectLaw(seqEq(FinalTerms, &ctx, before2, final.toSeq(&buf_b)), "mailbox: no-match leaves the sequence untouched", cfg, i);
    }
}

test "Laws: mailbox — FIFO per sender, first-match, remove-one, homomorphism" {
    try verifyMailboxLaws(std.testing.allocator, .{ .iterations = 60 });
}

test "Selective receive: takes the middle message, leaves order intact" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var mbox = FinalMbox(FinalTerms).init(gpa);
    defer mbox.deinit();

    try mbox.deliver(1, FinalTerms.int(&ctx, 10));
    try mbox.deliver(2, FinalTerms.int(&ctx, 20));
    try mbox.deliver(1, FinalTerms.int(&ctx, 30));

    const p20 = pat.Pattern(FinalTerms){ .plit = FinalTerms.int(&ctx, 20) };
    const r = (try mbox.recvMatch(&ctx, &p20)).?;
    try std.testing.expect(FinalTerms.eqlExact(&ctx, r.msg.payload, FinalTerms.int(&ctx, 20)));

    var buf: [8]Msg(FinalTerms) = undefined;
    const rest = mbox.toSeq(&buf);
    try std.testing.expectEqual(@as(usize, 2), rest.len);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, rest[0].payload, FinalTerms.int(&ctx, 10)));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, rest[1].payload, FinalTerms.int(&ctx, 30)));
}
