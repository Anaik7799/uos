//! beam-zig / erl_cli_surface: a bounded Erlang EXPRESSION reader — the `-eval`
//! consumer of the term-evaluation spine (`erl_scan` + `erl_parse` + the value
//! fragment of `erl_eval`, restricted).
//!
//! ## Signature
//!   read : source-text → Result
//!     Result = .silent                       (a bare expression — erl evaluates
//!                                              and DISCARDS; no output)
//!            | .display Term                 (`erlang:display(E)` → print `%T`)
//!            | error.Unsupported / error.Syntax
//!
//! ## Semantic domain
//! `-eval "Expr."` in erl is `erl_scan:string → erl_parse:parse_exprs →
//! erl_eval:exprs`; output is observable ONLY through a side-effecting call
//! (`erlang:display/1` prints the `%T` rendering + newline; a bare term prints
//! nothing). This module tokenizes + parses the VALUE fragment (integers, atoms,
//! strings, lists, tuples, `+ - *` with precedence, unary minus, parentheses)
//! into a `FinalTerms.Term`, and classifies the top-level form: `erlang:display(E)`
//! → `.display eval(E)`, any other bare expression → `.silent` (evaluated for
//! well-formedness, output discarded — byte-EQ with erl's empty output).
//!
//! ## Oracle vs final (a SEMANTIC-PRECURSOR / reader slice)
//! The tokenizer+parser+evaluator IS the encoding; the binding law is the LIVE
//! differential — `zigvm eval "E"` byte-EQ against `erl -noshell -eval "E" -s
//! init stop` (fixtures/erl + the CLI). The arithmetic delegates to the same
//! `FinalTerms.add/mul/negate` the `erlang` BIFs use, so `2*3-1 == 5` here is the
//! same denotation the VM gives.
//!
//! ## Laws
//!   PARSE-EVAL      parsing + evaluating a literal/arithmetic expression yields
//!                   the term built directly (int/atom/string/list/tuple/`+-*`)
//!   PRECEDENCE      `*` binds tighter than `+`/`-`; left-assoc; parens override
//!   DISPLAY-FORM    `erlang:display(E)` → `.display eval(E)`; a bare expr → .silent
//!   TOTALITY        malformed input → error.Syntax (never a panic); an
//!                   unsupported call (io:format, a variable) → error.Unsupported
//!
//! ## Scope (increment 1 — documented remainder)
//! Covered: the value grammar above + `erlang:display/1`. Deferred (honest EQUIV
//! remainder in the ledger): `io:format/1,2` (needs the Machine sink), variables
//! + bindings, `div`/`rem`/comparison/boolean operators, function calls other
//! than `erlang:display/1`, floats, quoted atoms, char literals `$c`, binaries,
//! maps, and multi-expression `-eval` (comma/`,`-sequenced side effects).

const std = @import("std");
const ta = @import("term_algebra.zig");

const FinalTerms = ta.FinalTerms;

pub const Result = union(enum) {
    silent,
    display: FinalTerms.Term,
    format: Format,

    pub const Format = struct { fmt: FinalTerms.Term, args: FinalTerms.Term };
};

pub const ReadError = error{ Syntax, Unsupported, OutOfMemory, Badarith };

// ── tokenizer ───────────────────────────────────────────────────────────────

const Tok = union(enum) {
    int: i64,
    atom: []const u8, // slice into the source (unquoted) or a decoded buffer
    string: []const u8, // decoded bytes (arena-owned)
    lparen,
    rparen,
    lbracket,
    rbracket,
    lbrace,
    rbrace,
    comma,
    colon,
    dot,
    plus,
    minus,
    star,
    eof,
};

const Lexer = struct {
    src: []const u8,
    i: usize = 0,
    arena: std.mem.Allocator,

    fn peekCh(self: *Lexer) ?u8 {
        return if (self.i < self.src.len) self.src[self.i] else null;
    }

    fn next(self: *Lexer) ReadError!Tok {
        // skip whitespace
        while (self.i < self.src.len and (self.src[self.i] == ' ' or self.src[self.i] == '\t' or
            self.src[self.i] == '\n' or self.src[self.i] == '\r')) : (self.i += 1)
        {}
        if (self.i >= self.src.len) return .eof;
        const c = self.src[self.i];
        switch (c) {
            '(' => {
                self.i += 1;
                return .lparen;
            },
            ')' => {
                self.i += 1;
                return .rparen;
            },
            '[' => {
                self.i += 1;
                return .lbracket;
            },
            ']' => {
                self.i += 1;
                return .rbracket;
            },
            '{' => {
                self.i += 1;
                return .lbrace;
            },
            '}' => {
                self.i += 1;
                return .rbrace;
            },
            ',' => {
                self.i += 1;
                return .comma;
            },
            ':' => {
                self.i += 1;
                return .colon;
            },
            '.' => {
                self.i += 1;
                return .dot;
            },
            '+' => {
                self.i += 1;
                return .plus;
            },
            '-' => {
                self.i += 1;
                return .minus;
            },
            '*' => {
                self.i += 1;
                return .star;
            },
            '"' => return self.string(),
            else => {
                if (c >= '0' and c <= '9') return self.integer();
                if (c >= 'a' and c <= 'z') return self.atomName();
                return error.Syntax; // uppercase (variable), '$', digits-lead handled above, etc.
            },
        }
    }

    fn integer(self: *Lexer) ReadError!Tok {
        const start = self.i;
        while (self.i < self.src.len and self.src[self.i] >= '0' and self.src[self.i] <= '9') : (self.i += 1) {}
        const v = std.fmt.parseInt(i64, self.src[start..self.i], 10) catch return error.Syntax;
        return .{ .int = v };
    }

    fn atomName(self: *Lexer) ReadError!Tok {
        const start = self.i;
        while (self.i < self.src.len) : (self.i += 1) {
            const c = self.src[self.i];
            const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
                (c >= '0' and c <= '9') or c == '_' or c == '@';
            if (!ok) break;
        }
        return .{ .atom = self.src[start..self.i] };
    }

    fn string(self: *Lexer) ReadError!Tok {
        self.i += 1; // opening quote
        var buf: std.ArrayList(u8) = .empty;
        while (self.i < self.src.len) : (self.i += 1) {
            const c = self.src[self.i];
            if (c == '"') {
                self.i += 1;
                return .{ .string = buf.toOwnedSlice(self.arena) catch return error.OutOfMemory };
            }
            if (c == '\\') {
                self.i += 1;
                if (self.i >= self.src.len) return error.Syntax;
                const e = self.src[self.i];
                const decoded: u8 = switch (e) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '\\' => '\\',
                    '"' => '"',
                    else => e,
                };
                buf.append(self.arena, decoded) catch return error.OutOfMemory;
            } else {
                buf.append(self.arena, c) catch return error.OutOfMemory;
            }
        }
        return error.Syntax; // unterminated string
    }
};

// ── parser + evaluator (single pass: parse straight to a Term) ────────────────

const Parser = struct {
    lex: Lexer,
    cur: Tok,
    ctx: *FinalTerms.Ctx,

    fn init(arena: std.mem.Allocator, ctx: *FinalTerms.Ctx, src: []const u8) ReadError!Parser {
        var lex = Lexer{ .src = src, .arena = arena };
        const first = try lex.next();
        return .{ .lex = lex, .cur = first, .ctx = ctx };
    }

    fn advance(self: *Parser) ReadError!void {
        self.cur = try self.lex.next();
    }

    fn expect(self: *Parser, comptime tag: std.meta.Tag(Tok)) ReadError!void {
        if (self.cur != tag) return error.Syntax;
        try self.advance();
    }

    // additive := multiplic (('+'|'-') multiplic)*
    fn additive(self: *Parser) ReadError!FinalTerms.Term {
        var acc = try self.multiplic();
        while (self.cur == .plus or self.cur == .minus) {
            const is_plus = self.cur == .plus;
            try self.advance();
            const rhs = try self.multiplic();
            acc = if (is_plus)
                try self.arith(acc, rhs, .add)
            else
                try self.arith(acc, rhs, .sub);
        }
        return acc;
    }

    // multiplic := unary ('*' unary)*
    fn multiplic(self: *Parser) ReadError!FinalTerms.Term {
        var acc = try self.unary();
        while (self.cur == .star) {
            try self.advance();
            const rhs = try self.unary();
            acc = try self.arith(acc, rhs, .mul);
        }
        return acc;
    }

    const ArithOp = enum { add, sub, mul };
    fn arith(self: *Parser, x: FinalTerms.Term, y: FinalTerms.Term, op: ArithOp) ReadError!FinalTerms.Term {
        // Numeric operands only (the BIFs assert numeric — a non-number is badarith).
        if (FinalTerms.kindOf(self.ctx, x) != .number or FinalTerms.kindOf(self.ctx, y) != .number)
            return error.Badarith;
        return switch (op) {
            .add => FinalTerms.add(self.ctx, x, y),
            .sub => FinalTerms.add(self.ctx, x, try FinalTerms.negate(self.ctx, y)),
            .mul => FinalTerms.mul(self.ctx, x, y),
        } catch |e| switch (e) {
            error.OutOfMemory => error.OutOfMemory,
            error.Badarith => error.Badarith,
        };
    }

    // unary := '-' unary | primary
    fn unary(self: *Parser) ReadError!FinalTerms.Term {
        if (self.cur == .minus) {
            try self.advance();
            const v = try self.unary();
            if (FinalTerms.kindOf(self.ctx, v) != .number) return error.Badarith;
            return FinalTerms.negate(self.ctx, v) catch error.OutOfMemory;
        }
        return self.primary();
    }

    fn primary(self: *Parser) ReadError!FinalTerms.Term {
        switch (self.cur) {
            .int => |v| {
                try self.advance();
                return FinalTerms.int(self.ctx, v);
            },
            .string => |s| {
                try self.advance();
                return self.stringTerm(s);
            },
            .atom => |nm| {
                // An atom may begin an `M:F(...)` / `F(...)` call — but calls are
                // only valid at the TOP level (handled by `read`); inside an
                // expression an atom is a literal atom.
                const idx = self.ctx.atoms.intern(nm) catch return error.OutOfMemory;
                try self.advance();
                if (self.cur == .colon or self.cur == .lparen) return error.Unsupported; // a call in arg position
                return FinalTerms.atom(self.ctx, idx);
            },
            .lparen => {
                try self.advance();
                const e = try self.additive();
                try self.expect(.rparen);
                return e;
            },
            .lbracket => return self.listTerm(),
            .lbrace => return self.tupleTerm(),
            else => return error.Syntax,
        }
    }

    fn stringTerm(self: *Parser, s: []const u8) ReadError!FinalTerms.Term {
        // "abc" is the list [$a,$b,$c] (a proper list of char codes), right-fold.
        var acc = FinalTerms.nil(self.ctx);
        var k: usize = s.len;
        while (k > 0) {
            k -= 1;
            acc = FinalTerms.cons(self.ctx, FinalTerms.int(self.ctx, s[k]), acc) catch return error.OutOfMemory;
        }
        return acc;
    }

    fn listTerm(self: *Parser) ReadError!FinalTerms.Term {
        try self.expect(.lbracket);
        if (self.cur == .rbracket) {
            try self.advance();
            return FinalTerms.nil(self.ctx);
        }
        var items: std.ArrayList(FinalTerms.Term) = .empty;
        defer items.deinit(self.lex.arena);
        items.append(self.lex.arena, try self.additive()) catch return error.OutOfMemory;
        while (self.cur == .comma) {
            try self.advance();
            items.append(self.lex.arena, try self.additive()) catch return error.OutOfMemory;
        }
        try self.expect(.rbracket);
        // right-fold into a proper list
        var acc = FinalTerms.nil(self.ctx);
        var k: usize = items.items.len;
        while (k > 0) {
            k -= 1;
            acc = FinalTerms.cons(self.ctx, items.items[k], acc) catch return error.OutOfMemory;
        }
        return acc;
    }

    fn tupleTerm(self: *Parser) ReadError!FinalTerms.Term {
        try self.expect(.lbrace);
        if (self.cur == .rbrace) {
            try self.advance();
            return FinalTerms.tuple(self.ctx, &.{}) catch error.OutOfMemory;
        }
        var items: std.ArrayList(FinalTerms.Term) = .empty;
        defer items.deinit(self.lex.arena);
        items.append(self.lex.arena, try self.additive()) catch return error.OutOfMemory;
        while (self.cur == .comma) {
            try self.advance();
            items.append(self.lex.arena, try self.additive()) catch return error.OutOfMemory;
        }
        try self.expect(.rbrace);
        return FinalTerms.tuple(self.ctx, items.items) catch error.OutOfMemory;
    }
};

/// Read + evaluate a single `-eval` expression. `arena` owns any decoded string
/// scratch; the resulting terms live in `ctx`.
/// gap-app-boot-keystone (DIVERGENCE 681): parse a single Erlang VALUE term from
/// TEXT and RETURN it (unlike `read`, which discards a bare value as `.silent`).
/// This is the `file:consult`-of-one-term primitive the `.app` resource reader
/// needs: `{application, Name, [Opts]}.` is a bare value expression the existing
/// `Parser` already handles (nested tuples/lists/strings/atoms/ints), and a
/// trailing `.` is consumed by `endOfProgram`. Terms are built in `ctx`; `arena`
/// owns the tokenizer scratch. A malformed term is `error.Syntax` (fail-closed).
pub fn readValue(arena: std.mem.Allocator, ctx: *FinalTerms.Ctx, src: []const u8) ReadError!FinalTerms.Term {
    var p = try Parser.init(arena, ctx, src);
    const t = try p.additive();
    try endOfProgram(&p);
    return t;
}

pub fn read(arena: std.mem.Allocator, ctx: *FinalTerms.Ctx, src: []const u8) ReadError!Result {
    var p = try Parser.init(arena, ctx, src);

    // A top-level `M:F(Args…)` call is the only OBSERVABLE form; a leading atom
    // NOT followed by `:` is a bare value expression (→ .silent).
    if (try tryTopCall(&p)) |r| return r;

    // A bare value expression: evaluate for well-formedness; output discarded.
    _ = try p.additive();
    try endOfProgram(&p);
    return .silent;
}

/// Detect + classify a top-level `M:F(Arg…)` call using a lookahead copy (the
/// `Parser`/`Lexer` are value types, so the copy is an independent cursor). An
/// atom NOT followed by `:` is not a call → `null` (the caller parses a bare
/// expr). A recognized call → its `Result`; a call we do not model → Unsupported.
fn tryTopCall(p: *Parser) ReadError!?Result {
    if (p.cur != .atom) return null;
    var probe = p.*;
    const m_nm = probe.cur.atom;
    try probe.advance();
    if (probe.cur != .colon) return null; // a bare atom (or the start of an expr)
    try probe.advance();
    if (probe.cur != .atom) return error.Syntax;
    const f_nm = probe.cur.atom;
    try probe.advance();
    if (probe.cur != .lparen) return error.Syntax;
    try probe.advance();

    var args: [4]FinalTerms.Term = undefined;
    var n: usize = 0;
    if (probe.cur != .rparen) {
        args[0] = try probe.additive();
        n = 1;
        while (probe.cur == .comma) {
            try probe.advance();
            if (n >= args.len) return error.Unsupported; // arity beyond what we model
            args[n] = try probe.additive();
            n += 1;
        }
    }
    try probe.expect(.rparen);
    try endOfProgram(&probe);

    const eql = std.mem.eql;
    if (eql(u8, m_nm, "erlang") and eql(u8, f_nm, "display") and n == 1)
        return .{ .display = args[0] };
    if (eql(u8, m_nm, "io") and eql(u8, f_nm, "format")) {
        if (n == 1) return .{ .format = .{ .fmt = args[0], .args = FinalTerms.nil(probe.ctx) } };
        if (n == 2) return .{ .format = .{ .fmt = args[0], .args = args[1] } };
    }
    return error.Unsupported; // a call we do not (yet) model
}

/// After the expression, only an optional trailing `.` then EOF is allowed.
fn endOfProgram(p: *Parser) ReadError!void {
    if (p.cur == .dot) try p.advance();
    if (p.cur != .eof) return error.Syntax;
}

// ============================================================================
// Laws
// ============================================================================

fn evalTerm(arena: std.mem.Allocator, ctx: *FinalTerms.Ctx, src: []const u8) !FinalTerms.Term {
    // helper for the laws: parse a bare expression and RETURN its term (bypasses
    // the .silent discard) by wrapping it in erlang:display(...) and reading.
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(arena);
    try buf.appendSlice(arena, "erlang:display(");
    try buf.appendSlice(arena, src);
    try buf.append(arena, ')');
    const r = try read(arena, ctx, buf.items);
    return switch (r) {
        .display => |t| t,
        .silent, .format => unreachable,
    };
}

test "LAW erl-expr parse-eval: literals + arithmetic build the direct term" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // 1+2 == 3 ; 2*3-1 == 5 (precedence) ; 2*(3-1) == 4 (parens) ; -5+2 == -3
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try evalTerm(a, &ctx, "1+2"), FinalTerms.int(&ctx, 3)));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try evalTerm(a, &ctx, "2*3-1"), FinalTerms.int(&ctx, 5)));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try evalTerm(a, &ctx, "2*(3-1)"), FinalTerms.int(&ctx, 4)));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try evalTerm(a, &ctx, "-5+2"), FinalTerms.int(&ctx, -3)));

    // atom, tuple, list, string
    const foo = FinalTerms.atom(&ctx, try ctx.atoms.intern("foo"));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try evalTerm(a, &ctx, "foo"), foo));
    const abc = try FinalTerms.tuple(&ctx, &.{ FinalTerms.atom(&ctx, try ctx.atoms.intern("a")), FinalTerms.atom(&ctx, try ctx.atoms.intern("b")), FinalTerms.int(&ctx, 42) });
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try evalTerm(a, &ctx, "{a,b,42}"), abc));
    const l123 = try list3(&ctx, 1, 2, 3);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try evalTerm(a, &ctx, "[1,2,3]"), l123));
    // "hi" == [104,105]
    const hi = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 104), try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 105), FinalTerms.nil(&ctx)));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try evalTerm(a, &ctx, "\"hi\""), hi));
    // nested: {a,[1,2]}
    const nested = try FinalTerms.tuple(&ctx, &.{ foo, try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 1), try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 2), FinalTerms.nil(&ctx))) });
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try evalTerm(a, &ctx, "{foo,[1,2]}"), nested));
}

fn list3(ctx: *FinalTerms.Ctx, x: i64, y: i64, z: i64) !FinalTerms.Term {
    return FinalTerms.cons(ctx, FinalTerms.int(ctx, x), try FinalTerms.cons(ctx, FinalTerms.int(ctx, y), try FinalTerms.cons(ctx, FinalTerms.int(ctx, z), FinalTerms.nil(ctx))));
}

test "LAW erl-expr display-form vs bare-expr classification" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // erlang:display(E) → .display eval(E)
    switch (try read(a, &ctx, "erlang:display(1+2).")) {
        .display => |t| try std.testing.expect(FinalTerms.eqlExact(&ctx, t, FinalTerms.int(&ctx, 3))),
        else => return error.TestUnexpectedResult,
    }
    // a bare expression → .silent (erl evaluates + discards; no output)
    try std.testing.expect((try read(a, &ctx, "1+2.")) == .silent);
    try std.testing.expect((try read(a, &ctx, "{a,b}.")) == .silent);
    // trailing dot optional
    switch (try read(a, &ctx, "erlang:display(foo)")) {
        .display => {},
        else => return error.TestUnexpectedResult,
    }
    // io:format/2 → .format{fmt="~p~n" args=[3]} ; io:format/1 → args=[]
    switch (try read(a, &ctx, "io:format(\"~p~n\",[1+2]).")) {
        .format => |f| {
            // fmt is the charlist "~p~n"; args is the list [3]
            const three = FinalTerms.int(&ctx, 3);
            const args1 = try FinalTerms.cons(&ctx, three, FinalTerms.nil(&ctx));
            try std.testing.expect(FinalTerms.eqlExact(&ctx, f.args, args1));
        },
        else => return error.TestUnexpectedResult,
    }
    switch (try read(a, &ctx, "io:format(\"hi~n\").")) {
        .format => |f| try std.testing.expect(FinalTerms.eqlExact(&ctx, f.args, FinalTerms.nil(&ctx))),
        else => return error.TestUnexpectedResult,
    }
}

test "LAW erl-expr totality: malformed → Syntax, unsupported call → Unsupported, never a panic" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expectError(error.Syntax, read(a, &ctx, "1+"));
    try std.testing.expectError(error.Syntax, read(a, &ctx, "{a,b"));
    try std.testing.expectError(error.Syntax, read(a, &ctx, "(1+2"));
    // a variable (uppercase) is unsupported syntax in this increment
    try std.testing.expectError(error.Syntax, read(a, &ctx, "X+1."));
    // io:format is an unsupported call (a call in arg position / non-display top)
    try std.testing.expectError(error.Unsupported, read(a, &ctx, "erlang:display(io:format(\"x\"))."));
    // arithmetic on a non-number is a clean badarith, never a panic
    try std.testing.expectError(error.Badarith, read(a, &ctx, "erlang:display(1+foo)."));
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
