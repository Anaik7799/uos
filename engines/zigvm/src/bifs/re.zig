//! # bifs/re -- Erlang `re:` BIF adapter over `re_engine.zig` (E7.9)
//!
//! Carrier: Erlang terms at the BIF boundary. Denotation: the supported
//! `re_engine` byte-regex match relation, re-encoded as OTP's `re:run` result
//! terms. Operations: `version/0`, `compile/1,2`, `run/2,3`,
//! `internal_run/4`, `inspect/2`, and `import/1`.
//!
//! Invariants: compiled patterns are transparent tagged terms
//! `{re_pattern,Captures,0,0,PatternBinary}`; exported patterns carry the source
//! and options in `{re_exported_pattern,Header,Pattern,Options,Encoded}` and
//! import recompiles them. Unsupported PCRE syntax is rejected, never treated as
//! a no-match. Capture output supports `all`, `all_but_first`, `first`, `none`
//! and `index | binary | list`, with `global` and `{offset,N}`.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const engine = @import("../re_engine.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;
const AtomTable = ta.AtomTable;

const compiled_tag = "re_pattern";
const exported_tag = "re_exported_pattern";
const version_string = "10.47 2025-10-21";

fn atom(m: *Machine, name: []const u8) BifError!Term {
    return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern(name) catch return error.OutOfMemory);
}

fn atomNameIs(m: *Machine, w: Term, name: []const u8) bool {
    if (!FinalTerms.repIsAtom(w)) return false;
    return std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(w)), name);
}

fn boolName(m: *Machine, w: Term) ?bool {
    if (atomNameIs(m, w, "true")) return true;
    if (atomNameIs(m, w, "false")) return false;
    return null;
}

fn tuple2(m: *Machine, a: Term, b: Term) BifError!Term {
    return FinalTerms.tuple(&m.ctx, &.{ a, b }) catch error.OutOfMemory;
}

fn tuple3(m: *Machine, a: Term, b: Term, c: Term) BifError!Term {
    return FinalTerms.tuple(&m.ctx, &.{ a, b, c }) catch error.OutOfMemory;
}

fn tuple5(m: *Machine, a: Term, b: Term, c: Term, d: Term, e: Term) BifError!Term {
    return FinalTerms.tuple(&m.ctx, &.{ a, b, c, d, e }) catch error.OutOfMemory;
}

fn charlist(m: *Machine, bytes: []const u8) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = bytes.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, bytes[i]), acc) catch return error.OutOfMemory;
    }
    return acc;
}

fn termToBytes(m: *Machine, w: Term) BifError![]u8 {
    switch (FinalTerms.kindOf(&m.ctx, w)) {
        .binary => return m.gpa.dupe(u8, FinalTerms.binBytes(&m.ctx, w)) catch error.OutOfMemory,
        .nil => return m.gpa.dupe(u8, &.{}) catch error.OutOfMemory,
        .cons => {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(m.gpa);
            var cur = w;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (!FinalTerms.repIsSmall(h)) return error.Badarg;
                const v = FinalTerms.smallValOf(h);
                if (v < 0 or v > 255) return error.Badarg;
                out.append(m.gpa, @intCast(v)) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
            return out.toOwnedSlice(m.gpa) catch error.OutOfMemory;
        },
        else => return error.Badarg,
    }
}

fn compileErrorTerm(m: *Machine, e: engine.Error, report_run: bool) BifError!Term {
    const reason_text = switch (e) {
        error.Unsupported => "unsupported",
        error.TooManyCaptures => "too_many_captures",
        error.OutOfFuel => "match_limit",
        error.OutOfMemory => return error.OutOfMemory,
        else => "bad_pattern",
    };
    const reason = try charlist(m, reason_text);
    const pos = FinalTerms.int(&m.ctx, 0);
    const spec = try tuple2(m, reason, pos);
    const error_atom = try atom(m, "error");
    if (!report_run) return tuple2(m, error_atom, spec);
    const compile_atom = try atom(m, "compile");
    return tuple2(m, error_atom, try tuple2(m, compile_atom, spec));
}

const CompileOpts = struct {
    export_pattern: bool = false,
};

fn parseCompileOpts(m: *Machine, opts_term: Term) BifError!CompileOpts {
    var opts = CompileOpts{};
    var cur = opts_term;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        if (atomNameIs(m, h, "export")) {
            opts.export_pattern = true;
        } else {
            return error.Badarg;
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
    return opts;
}

fn compileCount(m: *Machine, bytes: []const u8) engine.Error!usize {
    var p = try engine.compile(m.gpa, bytes);
    defer p.deinit(m.gpa);
    return p.captures;
}

fn compiledPattern(m: *Machine, bytes: []const u8, captures: usize) BifError!Term {
    const tag = try atom(m, compiled_tag);
    const src = FinalTerms.binary(&m.ctx, bytes) catch return error.OutOfMemory;
    return tuple5(m, tag, FinalTerms.int(&m.ctx, @intCast(captures)), FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, 0), src);
}

fn exportedPattern(m: *Machine, bytes: []const u8, opts_term: Term) BifError!Term {
    const tag = try atom(m, exported_tag);
    const header = FinalTerms.binary(&m.ctx, "zigvm-re-PCRE2") catch return error.OutOfMemory;
    const src = FinalTerms.binary(&m.ctx, bytes) catch return error.OutOfMemory;
    const encoded = FinalTerms.binary(&m.ctx, bytes) catch return error.OutOfMemory;
    return tuple5(m, tag, header, src, opts_term, encoded);
}

fn compileImpl(m: *Machine, pattern_term: Term, opts_term: Term) BifError!Term {
    const opts = try parseCompileOpts(m, opts_term);
    const bytes = try termToBytes(m, pattern_term);
    defer m.gpa.free(bytes);
    const captures = compileCount(m, bytes) catch |e| return compileErrorTerm(m, e, false);
    const ok = try atom(m, "ok");
    const body = if (opts.export_pattern)
        try exportedPattern(m, bytes, opts_term)
    else
        try compiledPattern(m, bytes, captures);
    return tuple2(m, ok, body);
}

pub fn compile_1(m: *Machine, args: []const Term) BifError!Term {
    return compileImpl(m, args[0], FinalTerms.nil(&m.ctx));
}

pub fn compile_2(m: *Machine, args: []const Term) BifError!Term {
    return compileImpl(m, args[0], args[1]);
}

pub fn version_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.binary(&m.ctx, version_string) catch error.OutOfMemory;
}

fn sourceFromRe(m: *Machine, re_term: Term) BifError![]u8 {
    if (FinalTerms.kindOf(&m.ctx, re_term) == .tuple and
        FinalTerms.tupleArity(&m.ctx, re_term) == 5 and
        atomNameIs(m, FinalTerms.tupleElem(&m.ctx, re_term, 0), compiled_tag))
    {
        return termToBytes(m, FinalTerms.tupleElem(&m.ctx, re_term, 4));
    }
    return termToBytes(m, re_term);
}

const CaptureSpec = enum { all, all_but_first, first, none };
const CaptureType = enum { index, binary, list };

const RunOpts = struct {
    global: bool = false,
    offset: usize = 0,
    report_errors: bool = false,
    notempty_atstart: bool = false,
    spec: CaptureSpec = .all,
    typ: CaptureType = .index,
};

fn parseCaptureSpec(m: *Machine, w: Term) BifError!CaptureSpec {
    if (atomNameIs(m, w, "all")) return .all;
    if (atomNameIs(m, w, "all_but_first")) return .all_but_first;
    if (atomNameIs(m, w, "first")) return .first;
    if (atomNameIs(m, w, "none")) return .none;
    return error.Badarg;
}

fn parseCaptureType(m: *Machine, w: Term) BifError!CaptureType {
    if (atomNameIs(m, w, "index")) return .index;
    if (atomNameIs(m, w, "binary")) return .binary;
    if (atomNameIs(m, w, "list")) return .list;
    return error.Badarg;
}

fn parseSmallOffset(w: Term) BifError!usize {
    if (!FinalTerms.repIsSmall(w)) return error.Badarg;
    const v = FinalTerms.smallValOf(w);
    if (v < 0) return error.Badarg;
    return @intCast(v);
}

fn parseRunOpts(m: *Machine, opts_term: Term) BifError!RunOpts {
    var opts = RunOpts{};
    var cur = opts_term;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        if (atomNameIs(m, h, "global")) {
            opts.global = true;
        } else if (atomNameIs(m, h, "report_errors")) {
            opts.report_errors = true;
        } else if (atomNameIs(m, h, "notempty_atstart")) {
            opts.notempty_atstart = true;
        } else if (FinalTerms.kindOf(&m.ctx, h) == .tuple and FinalTerms.tupleArity(&m.ctx, h) == 2 and
            atomNameIs(m, FinalTerms.tupleElem(&m.ctx, h, 0), "offset"))
        {
            opts.offset = try parseSmallOffset(FinalTerms.tupleElem(&m.ctx, h, 1));
        } else if (FinalTerms.kindOf(&m.ctx, h) == .tuple and FinalTerms.tupleArity(&m.ctx, h) == 2 and
            atomNameIs(m, FinalTerms.tupleElem(&m.ctx, h, 0), "capture"))
        {
            opts.spec = try parseCaptureSpec(m, FinalTerms.tupleElem(&m.ctx, h, 1));
            opts.typ = .index;
        } else if (FinalTerms.kindOf(&m.ctx, h) == .tuple and FinalTerms.tupleArity(&m.ctx, h) == 3 and
            atomNameIs(m, FinalTerms.tupleElem(&m.ctx, h, 0), "capture"))
        {
            opts.spec = try parseCaptureSpec(m, FinalTerms.tupleElem(&m.ctx, h, 1));
            opts.typ = try parseCaptureType(m, FinalTerms.tupleElem(&m.ctx, h, 2));
        } else {
            return error.Badarg;
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
    return opts;
}

fn captureTerm(m: *Machine, subject: []const u8, cap: engine.Capture, typ: CaptureType) BifError!Term {
    const len = cap.end - cap.start;
    return switch (typ) {
        .index => tuple2(m, FinalTerms.int(&m.ctx, @intCast(cap.start)), FinalTerms.int(&m.ctx, @intCast(len))),
        .binary => FinalTerms.binary(&m.ctx, subject[cap.start..cap.end]) catch error.OutOfMemory,
        .list => charlist(m, subject[cap.start..cap.end]),
    };
}

fn includeCapture(spec: CaptureSpec, i: usize) bool {
    return switch (spec) {
        .all => true,
        .all_but_first => i != 0,
        .first => i == 0,
        .none => false,
    };
}

fn captureList(m: *Machine, subject: []const u8, mat: engine.Match, capture_count: usize, opts: RunOpts) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = @min(capture_count, engine.max_captures - 1) + 1;
    while (i > 0) {
        i -= 1;
        if (!includeCapture(opts.spec, i)) continue;
        const cap = mat.captures[i];
        if (!cap.matched) continue;
        const t = try captureTerm(m, subject, cap, opts.typ);
        acc = FinalTerms.cons(&m.ctx, t, acc) catch return error.OutOfMemory;
    }
    return acc;
}

fn runCompiled(m: *Machine, subject: []const u8, pattern_bytes: []const u8, opts: RunOpts) BifError!Term {
    if (opts.offset > subject.len) return error.Badarg;
    var pat = engine.compile(m.gpa, pattern_bytes) catch |e| {
        if (opts.report_errors) return compileErrorTerm(m, e, true);
        return switch (e) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.Badarg,
        };
    };
    defer pat.deinit(m.gpa);
    const match_atom = try atom(m, "match");
    const nomatch_atom = try atom(m, "nomatch");
    if (opts.global) {
        var found: std.ArrayList(engine.Match) = .empty;
        defer found.deinit(m.gpa);
        var off = opts.offset;
        while (off <= subject.len) {
            const maybe = engine.matchFirst(m.gpa, &pat, subject, off, 100_000 + subject.len * 512 + pattern_bytes.len * 512) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.Badarg,
            };
            const mat = maybe orelse break;
            if (opts.notempty_atstart and mat.start == off and mat.end == off) break;
            found.append(m.gpa, mat) catch return error.OutOfMemory;
            const next = if (mat.end > mat.start) mat.end else mat.start + 1;
            if (next <= off) break;
            off = next;
        }
        if (found.items.len == 0) return nomatch_atom;
        if (opts.spec == .none) return match_atom;
        var outer = FinalTerms.nil(&m.ctx);
        var i = found.items.len;
        while (i > 0) {
            i -= 1;
            const caps = try captureList(m, subject, found.items[i], pat.captures, opts);
            outer = FinalTerms.cons(&m.ctx, caps, outer) catch return error.OutOfMemory;
        }
        return tuple2(m, match_atom, outer);
    }

    const maybe = engine.matchFirst(m.gpa, &pat, subject, opts.offset, 100_000 + subject.len * 512 + pattern_bytes.len * 512) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Badarg,
    };
    const mat = maybe orelse return nomatch_atom;
    if (opts.notempty_atstart and mat.start == opts.offset and mat.end == opts.offset) return nomatch_atom;
    if (opts.spec == .none) return match_atom;
    return tuple2(m, match_atom, try captureList(m, subject, mat, pat.captures, opts));
}

fn runImpl(m: *Machine, subject_term: Term, re_term: Term, opts_term: Term) BifError!Term {
    const opts = try parseRunOpts(m, opts_term);
    const subject = try termToBytes(m, subject_term);
    defer m.gpa.free(subject);
    const pattern = try sourceFromRe(m, re_term);
    defer m.gpa.free(pattern);
    return runCompiled(m, subject, pattern, opts);
}

pub fn run_2(m: *Machine, args: []const Term) BifError!Term {
    return runImpl(m, args[0], args[1], FinalTerms.nil(&m.ctx));
}

pub fn run_3(m: *Machine, args: []const Term) BifError!Term {
    return runImpl(m, args[0], args[1], args[2]);
}

pub fn internal_run_4(m: *Machine, args: []const Term) BifError!Term {
    _ = boolName(m, args[3]) orelse return error.Badarg;
    return runImpl(m, args[0], args[1], args[2]);
}

pub fn inspect_2(m: *Machine, args: []const Term) BifError!Term {
    if (!(FinalTerms.kindOf(&m.ctx, args[0]) == .tuple and
        FinalTerms.tupleArity(&m.ctx, args[0]) == 5 and
        atomNameIs(m, FinalTerms.tupleElem(&m.ctx, args[0], 0), compiled_tag))) return error.Badarg;
    if (!atomNameIs(m, args[1], "namelist")) return error.Badarg;
    return tuple2(m, try atom(m, "namelist"), FinalTerms.nil(&m.ctx));
}

pub fn import_1(m: *Machine, args: []const Term) BifError!Term {
    const t = args[0];
    if (!(FinalTerms.kindOf(&m.ctx, t) == .tuple and FinalTerms.tupleArity(&m.ctx, t) == 5 and
        atomNameIs(m, FinalTerms.tupleElem(&m.ctx, t, 0), exported_tag))) return error.Badarg;
    const source = try termToBytes(m, FinalTerms.tupleElem(&m.ctx, t, 2));
    defer m.gpa.free(source);
    const captures = compileCount(m, source) catch |e| return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.Badarg,
    };
    return compiledPattern(m, source, captures);
}

fn listFromAtoms(m: *Machine, names: []const []const u8) !Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = names.len;
    while (i > 0) {
        i -= 1;
        acc = try FinalTerms.cons(&m.ctx, try atom(m, names[i]), acc);
    }
    return acc;
}

fn captureOpt(m: *Machine, spec: []const u8, typ: ?[]const u8) !Term {
    const cap = try atom(m, "capture");
    const s = try atom(m, spec);
    if (typ) |t| return tuple3(m, cap, s, try atom(m, t));
    return tuple2(m, cap, s);
}

fn expectAtom(m: *Machine, got: Term, name: []const u8) !void {
    try std.testing.expect(atomNameIs(m, got, name));
}

test "LAW E7.9 re:version/0 and compile/run capture index output" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const ver = try version_0(&m, &.{});
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, ver), version_string));

    const subject = try FinalTerms.binary(&m.ctx, "abc123");
    const pattern = try FinalTerms.binary(&m.ctx, "([a-z]+)([0-9]+)");
    const got = try run_2(&m, &.{ subject, pattern });
    const match_atom = FinalTerms.tupleElem(&m.ctx, got, 0);
    try expectAtom(&m, match_atom, "match");
    const caps = FinalTerms.tupleElem(&m.ctx, got, 1);
    const c0 = FinalTerms.listHead(&m.ctx, caps);
    try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, c0, 0)));
    try std.testing.expectEqual(@as(i64, 6), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, c0, 1)));
}

test "LAW E7.9 capture matrix: first, all_but_first, none, binary/list, global" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const subject = try FinalTerms.binary(&m.ctx, "abcabc");
    const pattern = try FinalTerms.binary(&m.ctx, "a(b)c");
    const global = try atom(&m, "global");
    const cap_bin = try captureOpt(&m, "all_but_first", "binary");
    const opts = try FinalTerms.cons(&m.ctx, global, try FinalTerms.cons(&m.ctx, cap_bin, FinalTerms.nil(&m.ctx)));
    const got = try run_3(&m, &.{ subject, pattern, opts });
    try expectAtom(&m, FinalTerms.tupleElem(&m.ctx, got, 0), "match");
    const rows = FinalTerms.tupleElem(&m.ctx, got, 1);
    const first_row = FinalTerms.listHead(&m.ctx, rows);
    const first_cap = FinalTerms.listHead(&m.ctx, first_row);
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, first_cap), "b"));

    const none = try captureOpt(&m, "none", null);
    const none_opts = try FinalTerms.cons(&m.ctx, none, FinalTerms.nil(&m.ctx));
    try expectAtom(&m, try run_3(&m, &.{ subject, pattern, none_opts }), "match");
}

test "LAW E7.9 compile export/import round-trip and inspect namelist totality" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const pattern = try FinalTerms.binary(&m.ctx, "abc");
    const opts = try listFromAtoms(&m, &.{"export"});
    const compiled_export = try compile_2(&m, &.{ pattern, opts });
    const exported = FinalTerms.tupleElem(&m.ctx, compiled_export, 1);
    const imported = try import_1(&m, &.{exported});
    const subject = try FinalTerms.binary(&m.ctx, "xxabc");
    const got = try run_2(&m, &.{ subject, imported });
    try expectAtom(&m, FinalTerms.tupleElem(&m.ctx, got, 0), "match");
    const info = try inspect_2(&m, &.{ imported, try atom(&m, "namelist") });
    try expectAtom(&m, FinalTerms.tupleElem(&m.ctx, info, 0), "namelist");
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, FinalTerms.tupleElem(&m.ctx, info, 1)) == .nil);
}

test "LAW E7.9 unsupported compile reports error; run rejects instead of nomatch" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bad = try FinalTerms.binary(&m.ctx, "(?=a)");
    const c = try compile_1(&m, &.{bad});
    try expectAtom(&m, FinalTerms.tupleElem(&m.ctx, c, 0), "error");
    const subject = try FinalTerms.binary(&m.ctx, "a");
    try std.testing.expectError(error.Badarg, run_2(&m, &.{ subject, bad }));
}
