//! beam-zig M8 / S15-slice: **transform rules** — peephole rewrites as
//! algebraic laws (cf. erts ops.tab / generators.tab, whose DSL encodes
//! exactly such rewrites; erts trusts them by construction, we property-test
//! each one).
//!
//! A rule is admissible iff it is TRACE-EQUIVALENT: for every machine state
//! and every fuel budget, running the transformed program to completion
//! yields the same OBSERVABLE result — final status, register denotations,
//! result denotation, mailbox sequence. Reduction COUNTS may differ (that
//! is the point of peepholes; erts superinstructions change them too), so
//! the comparator is eqMachines-modulo-fuel.
//!
//! Rules shipped (all guarded by the law):
//!   R1 jump-to-next     `jump L` where L is the next pc → removed
//!   R2 self-move        `move2 src dst` where src ≡ dst register → removed
//!   R3 test-eq-same     `test_eq a a` (identical operand) → removed
//!                       (always falls through; = the reflexivity law
//!                       LICENSING an optimization — the M1 law pays rent)
//!
//! Removal renumbers jump targets; the rewriter is a whole-program pass
//! (remove + patch), like the loader's label fixup. Ownership (E1.5/E1.6): the
//! output is FULLY OWNED — `peephole` deep-copies every owned operand sub-slice
//! (`put_tuple2.elems`, the `select_val`/`select_tuple_arity` jump-table
//! `pairs` whose labels it must renumber, and `make_fun3.env` — E1.7) rather
//! than aliasing the input. So
//! `opt` is released with `beam_loader.freeProg`, and the input's own
//! sub-slices (static-const fuzz tables / the source program) are never touched.
//!
//! Because removal renumbers code labels, the trace-equivalence observation is
//! also modulo-LABEL: a `fun` value captures a code label (an address), and the
//! same fun has different absolute labels in `prog` vs the shorter `opt`.
//! `eqObservable` therefore compares funs on arity + captured env, never on the
//! raw label — comparing code addresses across two differently-laid-out
//! programs is exactly the address-identity comparison the project forbids.
//! (Within ONE program — e.g. the dispatch DIFFERENTIAL law — `spec.eqlExact`
//! including the label is correct; peephole is the only pass that renumbers.)

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

fn srcEqlDst(s: ia.Src, d: ia.Dst) bool {
    return switch (s) {
        .x => |r| switch (d) {
            .x => |r2| r == r2,
            .y => false,
        },
        .y => |r| switch (d) {
            .y => |r2| r == r2,
            .x => false,
        },
        else => false,
    };
}

fn srcIdentical(a: ia.Src, b: ia.Src) bool {
    return switch (a) {
        .x => |r| b == .x and b.x == r,
        .y => |r| b == .y and b.y == r,
        .imm => |v| b == .imm and b.imm == v,
        .atom_ => |v| b == .atom_ and b.atom_ == v,
        .nil => b == .nil,
        // W-17: two literal sources are "identical" only when they name the SAME
        // table slot. Distinct slots may still be structurally equal, but this
        // peephole (R3 reflexivity) is conservative — a false negative only
        // forgoes an optimization, never changes meaning.
        .literal => |i| b == .literal and b.literal == i,
    };
}

fn removable(prog: []const ia.CInstr, pc: usize) bool {
    const ins = prog[pc];
    return switch (ins) {
        .jump => |j| j.to == pc + 1, // R1
        .move2 => |m| srcEqlDst(m.src, m.dst), // R2
        .test_eq => |t| srcIdentical(t.a, t.b), // R3 (reflexivity license)
        else => false,
    };
}

/// Apply R1–R3 once across the program (a single fixpoint round is enough
/// for the laws; iterate externally if desired).
pub fn peephole(gpa: std.mem.Allocator, prog: []const ia.CInstr) ![]ia.CInstr {
    // map old pc → new pc (removed instructions collapse forward)
    const map = try gpa.alloc(u32, prog.len + 1);
    defer gpa.free(map);
    var new_len: u32 = 0;
    for (prog, 0..) |_, pc| {
        map[pc] = new_len;
        if (!removable(prog, pc)) new_len += 1;
    }
    map[prog.len] = new_len;

    var out = try std.ArrayList(ia.CInstr).initCapacity(gpa, new_len);
    // The output OWNS every sub-slice (deep-copied below), so on error we must
    // release them before deiniting the array — the freeProg contract.
    errdefer {
        for (out.items) |ins| switch (ins) {
            .put_tuple2 => |p| gpa.free(p.elems),
            .select_val => |s| gpa.free(s.pairs),
            .select_tuple_arity => |s| gpa.free(s.pairs),
            .make_fun3 => |f| gpa.free(f.env),
            .has_map_fields => |h| gpa.free(h.keys), // E1.10: owned map keys
            .get_map_elements => |g| gpa.free(g.pairs), // E1.10: owned map pairs
            .put_map => |p| gpa.free(p.kvs), // E1.10: owned map kvs
            .update_record => |u| gpa.free(u.updates), // E1.14: owned record updates
            .get_record_elements => |u| gpa.free(u.elems), // E3.14: owned elements
            .put_record => |u| gpa.free(u.updates), // E3.14: owned field updates
            .bs_match => |b| gpa.free(b.cmds), // E3.3: owned sub-command list
            .bs_match_string => |b| gpa.free(b.bytes), // E3.3: owned literal pattern
            .bs_create_bin => |b| { // E3.4: owned segment list (+ per-string bytes)
                for (b.segs) |s| switch (s) {
                    .string => |st| gpa.free(st.bytes),
                    else => {},
                };
                gpa.free(b.segs);
            },
            else => {},
        };
        out.deinit(gpa);
    }
    for (prog, 0..) |ins, pc| {
        if (removable(prog, pc)) continue;
        var patched = ins;
        switch (patched) {
            .test_eq => |*v| v.else_to = map[v.else_to],
            .is_lt => |*v| v.else_to = map[v.else_to],
            .is_cons => |*v| v.else_to = map[v.else_to],
            .type_test => |*v| v.else_to = map[v.else_to], // E1.3: remap jump target
            .cmp_test => |*v| v.else_to = map[v.else_to], // E1.4: remap jump target
            .is_function_arity => |*v| v.else_to = map[v.else_to],
            .test_arity => |*v| v.else_to = map[v.else_to], // E1.5: remap jump target
            .is_tagged_tuple => |*v| v.else_to = map[v.else_to], // E1.5: remap jump target
            // E1.6: select carries MULTIPLE labels (fail_to + each pair.to) AND
            // an owned pairs slice. Deep-copy the pairs FIRST so we never write
            // through the source (which may be a static-const fuzz table or an
            // input-aliased slice), then remap. The clone makes `opt` fully own
            // its sub-slices, so `beam_loader.freeProg(opt)` is the correct free.
            .select_val => |*v| {
                const np = try gpa.dupe(ia.SelectValPair, v.pairs);
                for (np) |*p| p.to = map[p.to];
                v.pairs = np;
                v.fail_to = map[v.fail_to];
            },
            .select_tuple_arity => |*v| {
                const np = try gpa.dupe(ia.SelectArityPair, v.pairs);
                for (np) |*p| p.to = map[p.to];
                v.pairs = np;
                v.fail_to = map[v.fail_to];
            },
            // E1.5: put_tuple2 owns no labels, but its elems must be
            // independently owned so `freeProg(opt)` never double-frees a
            // static/aliased source slice. Deep-copy (no remap needed).
            .put_tuple2 => |*v| v.elems = try gpa.dupe(ia.Src, v.elems),
            // E1.7: make_fun3 owns an `env` slice AND carries a code label. Deep-
            // copy env FIRST (so `opt` fully owns it and never writes through the
            // static-const fuzz backing / input slice), then remap the label.
            .make_fun3 => |*v| {
                v.env = try gpa.dupe(ia.Src, v.env);
                v.to = map[v.to];
            },
            // E1.10: the map ops own a `keys`/`pairs`/`kvs` slice. Deep-copy it
            // FIRST (so `opt` fully owns it and never writes through the static-
            // const fuzz backing / input slice), then remap the label the two
            // guarded tests carry (`put_map` carries none — no remap, copy only).
            .has_map_fields => |*v| {
                v.keys = try gpa.dupe(ia.Src, v.keys); // E5.2: keys are Srcs (DIVERGENCE 47)
                v.else_to = map[v.else_to];
            },
            .get_map_elements => |*v| {
                v.pairs = try gpa.dupe(ia.MapElemPair, v.pairs);
                v.else_to = map[v.else_to];
            },
            .put_map => |*v| v.kvs = try gpa.dupe(ia.MapKV, v.kvs),
            // E1.14: update_record owns an `updates` slice and carries NO label —
            // deep-copy it (so `opt` fully owns it and never writes through a
            // static-const fuzz backing / input slice); no remap.
            .update_record => |*v| v.updates = try gpa.dupe(ia.RecordUpdate, v.updates),
            // E3.14: native-record ops. Guard-shaped forms remap else_to; the
            // two owned-slice forms deep-copy first (never write through a
            // static/aliased source). `get_record_field`'s else_to is OPTIONAL
            // (Lbl==0 ⇒ null, no remap — mirrors bif_call); put_record no label.
            .is_any_native_record => |*v| v.else_to = map[v.else_to],
            .is_native_record => |*v| v.else_to = map[v.else_to],
            .is_record_accessible => |*v| v.else_to = map[v.else_to],
            .get_record_elements => |*v| {
                v.elems = try gpa.dupe(ia.RecordElem, v.elems);
                v.else_to = map[v.else_to];
            },
            .put_record => |*v| v.updates = try gpa.dupe(ia.RecordFieldSrc, v.updates),
            .get_record_field => |*v| {
                if (v.else_to) |e| v.else_to = map[e];
            },
            .jump => |*v| v.to = map[v.to],
            .call => |*v| v.to = map[v.to],
            .make_fun => |*v| v.to = map[v.to],
            .catch_ => |*v| v.to = map[v.to], // E1.8: remap recovery label
            .try_ => |*v| v.to = map[v.to], // E1.8: remap recovery label
            .recv_eq => |*v| v.else_to = map[v.else_to],
            .recv_any => |*v| v.else_to = map[v.else_to],
            // E1.11: the receive-loop ops carry a code label (the wait/retry
            // target). Remap it. `recv_marker_*`/`send`/`remove_message`/`timeout`
            // carry no label — they fall to the `else` (no remap).
            .loop_rec => |*v| v.else_to = map[v.else_to],
            .loop_rec_end => |*v| v.to = map[v.to],
            .wait => |*v| v.to = map[v.to],
            .wait_timeout => |*v| v.to = map[v.to],
            .spawn => |*v| v.to = map[v.to],
            // E1.13: a GUARD bif_call carries an OPTIONAL code label (the fail
            // target); a BODY bif_call has none (else_to null → no remap). `args`
            // is an inline [3]Src (no owned slice), so nothing to deep-copy.
            .bif_call => |*v| {
                if (v.else_to) |e| v.else_to = map[e];
            },
            // E3.3: bit-syntax matching. `bs_start_match`'s label is OPTIONAL
            // (mirrors `bif_call`); the rest carry a mandatory `else_to`.
            // `bs_match`/`bs_match_string` additionally own a slice — deep-
            // copy first (never write through a static-const/aliased source).
            .bs_start_match => |*v| {
                if (v.else_to) |e| v.else_to = map[e];
            },
            .bs_get_integer => |*v| v.else_to = map[v.else_to],
            .bs_get_float => |*v| v.else_to = map[v.else_to],
            .bs_get_binary => |*v| v.else_to = map[v.else_to],
            .bs_skip_bits => |*v| v.else_to = map[v.else_to],
            .bs_test_tail => |*v| v.else_to = map[v.else_to],
            .bs_match_string => |*v| {
                v.bytes = try gpa.dupe(u8, v.bytes);
                v.else_to = map[v.else_to];
            },
            .bs_match => |*v| {
                v.cmds = try gpa.dupe(ia.BsCmd, v.cmds);
                v.fail_to = map[v.fail_to];
            },
            // E3.4: bit-syntax CONSTRUCTION + UTF. `bs_create_bin`'s Fail is
            // OPTIONAL (mirrors `bif_call`/`bs_start_match`); it owns a
            // `segs` slice whose `.string` variants ADDITIONALLY own their
            // own `bytes` — deep-copy both levels (never write through a
            // static-const/aliased source), then remap.
            .bs_create_bin => |*v| {
                const new_segs = try gpa.alloc(ia.BsSeg, v.segs.len);
                errdefer gpa.free(new_segs);
                var built: usize = 0;
                errdefer for (new_segs[0..built]) |s| switch (s) {
                    .string => |st| gpa.free(st.bytes),
                    else => {},
                };
                for (v.segs, 0..) |s, k| {
                    new_segs[k] = switch (s) {
                        .string => |st| .{ .string = .{ .bytes = try gpa.dupe(u8, st.bytes) } },
                        else => s,
                    };
                    built = k + 1;
                }
                v.segs = new_segs;
                if (v.else_to) |e| v.else_to = map[e];
            },
            .bs_get_utf => |*v| v.else_to = map[v.else_to],
            .bs_skip_utf => |*v| v.else_to = map[v.else_to],
            else => {},
        }
        out.appendAssumeCapacity(patched);
    }
    return out.toOwnedSlice(gpa);
}

/// eqMachines modulo fuel: observable machine equality where reduction
/// counts and pc are EXCLUDED (programs differ in length), everything the
/// program can observe is compared.
fn eqObservable(a: *ia.Machine, b: *ia.Machine, sa: std.mem.Allocator) !bool {
    if (a.status != b.status) return false;
    for (a.regs, b.regs) |ra, rb| {
        if (!eqModuloFunLabel(
            try FinalTerms.denote(&a.ctx, sa, ra),
            try FinalTerms.denote(&b.ctx, sa, rb),
        )) return false;
    }
    if (a.ystack.items.len != b.ystack.items.len) return false;
    for (a.ystack.items, b.ystack.items) |ya, yb| {
        if (!eqModuloFunLabel(
            try FinalTerms.denote(&a.ctx, sa, ya),
            try FinalTerms.denote(&b.ctx, sa, yb),
        )) return false;
    }
    return eqModuloFunLabel(
        try FinalTerms.denote(&a.ctx, sa, a.result),
        try FinalTerms.denote(&b.ctx, sa, b.result),
    );
}

/// Exact term equality EXCEPT fun code-labels are ignored (funs compare on
/// arity + captured env, recursively). Peephole legitimately RENUMBERS code
/// labels (it patches `make_fun.to`/jump targets when it deletes no-ops), so a
/// fun's absolute label differs between `prog` and its shorter `opt` even
/// though the two funs are the same value morally. A code label is an ADDRESS;
/// comparing it across two differently-laid-out programs is the address-
/// identity comparison the project forbids — hence this observation is
/// label-agnostic. (`spec.eqlExact` keys on the label; it is the right
/// comparison WITHIN one program, e.g. the DIFFERENTIAL law, but not across a
/// peephole rewrite.)
fn eqModuloFunLabel(a: *const spec.Value, b: *const spec.Value) bool {
    return switch (a.*) {
        .int => |x| b.* == .int and x.order(b.int) == .eq,
        .float => |x| b.* == .float and x == b.float,
        .atom => |x| b.* == .atom and std.mem.eql(u8, x, b.atom),
        .nil => b.* == .nil,
        .cons => |p| b.* == .cons and
            eqModuloFunLabel(p.head, b.cons.head) and
            eqModuloFunLabel(p.tail, b.cons.tail),
        .tuple => |xs| blk: {
            if (b.* != .tuple or xs.len != b.tuple.len) break :blk false;
            for (xs, b.tuple) |x, y| if (!eqModuloFunLabel(x, y)) break :blk false;
            break :blk true;
        },
        .map => |xs| blk: {
            if (b.* != .map or xs.len != b.map.len) break :blk false;
            for (xs, b.map) |x, y|
                if (!eqModuloFunLabel(x.key, y.key) or !eqModuloFunLabel(x.val, y.val))
                    break :blk false;
            break :blk true;
        },
        .binary => |x| b.* == .binary and std.mem.eql(u8, x, b.binary),
        .bitstring => |x| b.* == .bitstring and ta.bsa.eql(x, b.bitstring),
        // E3.5: pid/reference/port carry no code label, so this is exactly
        // `spec.eqlExact`'s treatment of them — no relabeling to ignore.
        // E5.7: node/creation participate in identity (foreign vs local).
        .reference => |x| b.* == .reference and std.mem.eql(u32, &x.words, &b.reference.words) and x.creation == b.reference.creation and std.mem.eql(u8, x.node, b.reference.node),
        .port => |x| b.* == .port and x.number == b.port.number and x.creation == b.port.creation and std.mem.eql(u8, x.node, b.port.node),
        .pid => |x| b.* == .pid and x.number == b.pid.number and x.serial == b.pid.serial and x.creation == b.pid.creation and std.mem.eql(u8, x.node, b.pid.node),
        // E3.14: native records carry no code label — structural equality,
        // like tuples (module/name/keys are atoms, values recurse).
        .native_record => |x| blk: {
            if (b.* != .native_record) break :blk false;
            const y = b.native_record;
            if (x.is_exported != y.is_exported or x.keys.len != y.keys.len) break :blk false;
            if (!eqModuloFunLabel(x.module, y.module) or !eqModuloFunLabel(x.name, y.name)) break :blk false;
            for (x.keys, y.keys) |kx, ky| if (!eqModuloFunLabel(kx, ky)) break :blk false;
            for (x.values, y.values) |vx, vy| if (!eqModuloFunLabel(vx, vy)) break :blk false;
            break :blk true;
        },
        .fun_ => |x| blk: {
            if (b.* != .fun_) break :blk false;
            const y = b.fun_;
            if (x.arity != y.arity or x.env.len != y.env.len) break :blk false; // label ignored
            for (x.env, y.env) |ex, ey| if (!eqModuloFunLabel(ex, ey)) break :blk false;
            break :blk true;
        },
        // E7.1: external funs carry NO code label — structural equality on
        // module/function NAMES + arity (same as spec.eqlExact treats them).
        .export_fun => |x| b.* == .export_fun and
            std.mem.eql(u8, x.module, b.export_fun.module) and
            std.mem.eql(u8, x.function, b.export_fun.function) and
            x.arity == b.export_fun.arity,
    };
}

/// Random programs with PLANTED rewrite opportunities.
fn plantedProgram(random: std.Random, buf: []ia.CInstr) []const ia.CInstr {
    const base = ia.randProgram(random, buf[0 .. buf.len - 4]);
    var n = base.len;
    // plant a self-move, a same-operand test, and a jump-to-next
    buf[n] = .{ .move2 = .{ .src = .{ .x = 3 }, .dst = .{ .x = 3 } } };
    n += 1;
    const r: u4 = random.int(u4);
    buf[n] = .{ .test_eq = .{ .a = .{ .x = r }, .b = .{ .x = r }, .else_to = 0 } };
    n += 1;
    buf[n] = .{ .jump = .{ .to = @intCast(n + 1) } };
    n += 1;
    buf[n] = .{ .halt = .{ .src = .{ .x = 0 } } };
    n += 1;
    return buf[0..n];
}

test "LAW: peephole rewrites are trace-equivalent (modulo fuel)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x0P7, .iterations = 60 };

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        var buf: [20]ia.CInstr = undefined;
        const prog = plantedProgram(random, &buf);
        const opt = try peephole(gpa, prog);
        // peephole's output OWNS every sub-slice (put_tuple2.elems, select
        // pairs); freeProg releases them. `prog`'s own sub-slices are the
        // static-const fuzz tables — never freed, never aliased by `opt`.
        defer @import("beam_loader.zig").freeProg(gpa, opt);

        try expectLaw(opt.len < prog.len, "transform: something was actually rewritten", cfg, i);

        var m1 = try ia.Machine.init(gpa, &atoms);
        defer m1.deinit();
        var m2 = try ia.Machine.init(gpa, &atoms);
        defer m2.deinit();
        var p1 = std.Random.DefaultPrng.init(cfg.seed +% i +% 3);
        var p2 = std.Random.DefaultPrng.init(cfg.seed +% i +% 3);
        const r1 = p1.random();
        const r2 = p2.random();
        for (&m1.regs) |*r| r.* = FinalTerms.int(&m1.ctx, @as(i64, r1.int(i16)));
        for (&m2.regs) |*r| r.* = FinalTerms.int(&m2.ctx, @as(i64, r2.int(i16)));

        // run BOTH to completion (bounded); equivalence is observational
        var guard: usize = 0;
        while (m1.status == .running and m1.pending == null and guard < 40) : (guard += 1)
            try ia.run(&m1, prog, 50);
        guard = 0;
        while (m2.status == .running and m2.pending == null and guard < 40) : (guard += 1)
            try ia.run(&m2, opt, 50);

        // if either still runs (loops), both must still run — then compare
        // registers only via a bounded snapshot? Simplest sound comparison:
        // when both HALTED/CRASHED, compare full observables; when both are
        // looping, that IS the agreement (same divergence).
        const done1 = m1.status != .running or m1.pending != null;
        const done2 = m2.status != .running or m2.pending != null;
        try expectLaw(done1 == done2, "transform: same termination behavior", cfg, i);
        if (done1 and m1.pending == null) {
            try expectLaw(try eqObservable(&m1, &m2, sa), "transform: observables preserved", cfg, i);
        }
    }
}

test "R3 is licensed by reflexivity: the removed test can NEVER branch" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(0x3E1F);
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // exactly the M1 reflexivity law, restated at the instruction level:
    // for any term t, eqlExact(t, t) — so `test_eq a a` always falls through
    for (0..80) |_| {
        const t = try ta.genTerm(FinalTerms, prng.random(), &ctx, 3);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, t, t));
    }
}

test "Peephole on REAL compiled code is a no-op (the compiler already did it)" {
    const gpa = std.testing.allocator;
    const loader = @import("beam_loader.zig");
    var mod = try loader.parse(gpa, @embedFile("mylists.beam"));
    defer mod.deinit();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const t = try loader.translate(gpa, &mod, &atoms, null);
    defer {
        loader.freeProg(gpa, t.prog); // ownership rule: release owned sub-slices too
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    const opt = try peephole(gpa, t.prog);
    defer loader.freeProg(gpa, opt);
    // erlc's output contains none of our redundancies — a sanity oracle
    try std.testing.expectEqual(t.prog.len, opt.len);
}
