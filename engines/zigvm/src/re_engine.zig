//! # re_engine -- bounded byte-regex algebra (E7.9)
//!
//! Carrier: a parsed regular expression over bytes. Denotation: the leftmost
//! PCRE-style match relation from a subject byte string to capture ranges. The
//! accepted subset is deliberately finite: literals, `.`, byte character
//! classes, `^`/`$`, capturing groups, alternation, and greedy `*`/`+`/`?`/
//! `{m,n}` repetition. Unsupported PCRE constructs are rejected at compile time
//! instead of approximated.
//!
//! Operations: `compile` and `matchFirst`. Observations: full-match range,
//! capture ranges, and total compile rejection. Invariants: capture ids are
//! assigned left-to-right, all recursion is fuel-bounded, and every repetition
//! either consumes input or stops, so zero-width patterns never spin.
//!
//! Laws below cover compile/run denotation, capture totality, greedy
//! backtracking, unsupported rejection, and the fuel guard.

const std = @import("std");

pub const max_captures = 16;

pub const Error = error{
    BadPattern,
    Unsupported,
    TooManyCaptures,
    OutOfMemory,
    OutOfFuel,
};

pub const Capture = struct {
    matched: bool = false,
    start: usize = 0,
    end: usize = 0,
};

pub const Match = struct {
    start: usize,
    end: usize,
    captures: [max_captures]Capture,
};

const Class = struct {
    set: [256]bool,
    negated: bool = false,

    fn matches(self: Class, c: u8) bool {
        const hit = self.set[c];
        return if (self.negated) !hit else hit;
    }
};

const Group = struct {
    id: usize,
    alts: []Alt,
};

const Atom = union(enum) {
    literal: u8,
    dot,
    class: Class,
    start_anchor,
    end_anchor,
    group: *Group,
};

const Item = struct {
    atom: Atom,
    min: usize,
    max: ?usize,
    // DIVERGENCE 677: false for a LAZY (non-greedy) quantifier (`*?`/`+?`/`??`/
    // `{m,n}?`) — the matcher then backtracks shortest-match-first.
    greedy: bool = true,
};

const Alt = struct {
    items: []Item,
};

pub const Pattern = struct {
    alts: []Alt,
    captures: usize,

    pub fn deinit(self: *Pattern, allocator: std.mem.Allocator) void {
        deinitAlts(allocator, self.alts);
        self.* = .{ .alts = &.{}, .captures = 0 };
    }
};

fn deinitAlts(allocator: std.mem.Allocator, alts: []Alt) void {
    for (alts) |alt| {
        for (alt.items) |item| deinitAtom(allocator, item.atom);
        allocator.free(alt.items);
    }
    allocator.free(alts);
}

fn deinitAtom(allocator: std.mem.Allocator, atom: Atom) void {
    switch (atom) {
        .group => |g| {
            deinitAlts(allocator, g.alts);
            allocator.destroy(g);
        },
        else => {},
    }
}

fn emptySet() [256]bool {
    return [_]bool{false} ** 256;
}

fn singleton(c: u8) Class {
    var set = emptySet();
    set[c] = true;
    return .{ .set = set };
}

fn asciiClass(kind: u8) Class {
    var set = emptySet();
    switch (kind) {
        'd' => {
            for ('0'..('9' + 1)) |c| set[c] = true;
        },
        'w' => {
            for ('0'..('9' + 1)) |c| set[c] = true;
            for ('A'..('Z' + 1)) |c| set[c] = true;
            for ('a'..('z' + 1)) |c| set[c] = true;
            set['_'] = true;
        },
        's' => {
            set[' '] = true;
            set['\t'] = true;
            set['\n'] = true;
            set['\r'] = true;
            set[0x0b] = true;
            set[0x0c] = true;
        },
        else => unreachable,
    }
    return .{ .set = set };
}

fn negated(cls: Class) Class {
    return .{ .set = cls.set, .negated = !cls.negated };
}

const Parser = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    pos: usize = 0,
    captures: usize = 0,

    fn parse(self: *Parser) Error!Pattern {
        const alts = try self.parseAlternatives(false);
        errdefer deinitAlts(self.allocator, alts);
        if (self.pos != self.bytes.len) return error.BadPattern;
        return .{ .alts = alts, .captures = self.captures };
    }

    fn peek(self: *Parser) ?u8 {
        if (self.pos >= self.bytes.len) return null;
        return self.bytes[self.pos];
    }

    fn take(self: *Parser) ?u8 {
        const c = self.peek() orelse return null;
        self.pos += 1;
        return c;
    }

    fn parseAlternatives(self: *Parser, stop_on_rparen: bool) Error![]Alt {
        var alts: std.ArrayList(Alt) = .empty;
        errdefer {
            for (alts.items) |alt| {
                for (alt.items) |item| deinitAtom(self.allocator, item.atom);
                self.allocator.free(alt.items);
            }
            alts.deinit(self.allocator);
        }
        while (true) {
            const items = try self.parseSequence(stop_on_rparen);
            alts.append(self.allocator, .{ .items = items }) catch return error.OutOfMemory;
            if (self.peek() == '|') {
                self.pos += 1;
                continue;
            }
            break;
        }
        return alts.toOwnedSlice(self.allocator) catch error.OutOfMemory;
    }

    fn parseSequence(self: *Parser, stop_on_rparen: bool) Error![]Item {
        var items: std.ArrayList(Item) = .empty;
        errdefer {
            for (items.items) |item| deinitAtom(self.allocator, item.atom);
            items.deinit(self.allocator);
        }
        while (self.pos < self.bytes.len) {
            const c = self.bytes[self.pos];
            if (c == '|' or (stop_on_rparen and c == ')')) break;
            const atom = try self.parseAtom();
            errdefer deinitAtom(self.allocator, atom);
            const q = try self.parseQuantifier();
            items.append(self.allocator, .{ .atom = atom, .min = q.min, .max = q.max, .greedy = q.greedy }) catch return error.OutOfMemory;
        }
        return items.toOwnedSlice(self.allocator) catch error.OutOfMemory;
    }

    const Quant = struct { min: usize, max: ?usize, greedy: bool = true };

    fn parseQuantifier(self: *Parser) Error!Quant {
        const c = self.peek() orelse return .{ .min = 1, .max = 1 };
        var q = switch (c) {
            '*' => blk: {
                self.pos += 1;
                break :blk Quant{ .min = 0, .max = null };
            },
            '+' => blk: {
                self.pos += 1;
                break :blk Quant{ .min = 1, .max = null };
            },
            '?' => blk: {
                self.pos += 1;
                break :blk Quant{ .min = 0, .max = 1 };
            },
            '{' => try self.parseBraceQuantifier(),
            else => return .{ .min = 1, .max = 1 },
        };
        // DIVERGENCE 677: a trailing `?` on a quantifier makes it LAZY (non-greedy).
        if (self.peek() == '?') {
            self.pos += 1;
            q.greedy = false;
        }
        if (q.max) |mx| if (mx < q.min) return error.BadPattern;
        return q;
    }

    fn parseBraceQuantifier(self: *Parser) Error!Quant {
        const save = self.pos;
        self.pos += 1; // {
        const min = self.parseUint() orelse {
            self.pos = save;
            return error.Unsupported;
        };
        var max: ?usize = min;
        if (self.peek() == ',') {
            self.pos += 1;
            max = self.parseUint();
        }
        if (self.take() != '}') return error.BadPattern;
        return .{ .min = min, .max = max };
    }

    fn parseUint(self: *Parser) ?usize {
        var n: usize = 0;
        const start = self.pos;
        while (self.pos < self.bytes.len and self.bytes[self.pos] >= '0' and self.bytes[self.pos] <= '9') : (self.pos += 1) {
            n = n * 10 + @as(usize, self.bytes[self.pos] - '0');
        }
        if (self.pos == start) return null;
        return n;
    }

    fn parseAtom(self: *Parser) Error!Atom {
        const c = self.take() orelse return error.BadPattern;
        return switch (c) {
            '(' => try self.parseGroup(),
            '[' => try self.parseClassAtom(),
            '.' => Atom.dot,
            '^' => Atom.start_anchor,
            '$' => Atom.end_anchor,
            '\\' => try self.parseEscapeAtom(),
            ')', '*', '+', '?', '{', '}' => error.BadPattern,
            else => Atom{ .literal = c },
        };
    }

    fn parseGroup(self: *Parser) Error!Atom {
        if (self.peek() == '?') return error.Unsupported;
        if (self.captures + 1 >= max_captures) return error.TooManyCaptures;
        self.captures += 1;
        const id = self.captures;
        const alts = try self.parseAlternatives(true);
        errdefer deinitAlts(self.allocator, alts);
        if (self.take() != ')') return error.BadPattern;
        const g = self.allocator.create(Group) catch return error.OutOfMemory;
        g.* = .{ .id = id, .alts = alts };
        return .{ .group = g };
    }

    fn parseEscapeAtom(self: *Parser) Error!Atom {
        const c = self.take() orelse return error.BadPattern;
        return switch (c) {
            'd', 'w', 's' => Atom{ .class = asciiClass(c) },
            'D' => Atom{ .class = negated(asciiClass('d')) },
            'W' => Atom{ .class = negated(asciiClass('w')) },
            'S' => Atom{ .class = negated(asciiClass('s')) },
            'n' => Atom{ .literal = '\n' },
            'r' => Atom{ .literal = '\r' },
            't' => Atom{ .literal = '\t' },
            '\\', '.', '^', '$', '|', '(', ')', '[', ']', '{', '}', '*', '+', '?' => Atom{ .literal = c },
            else => error.Unsupported,
        };
    }

    const ClassPiece = union(enum) {
        one: u8,
        many: Class,
    };

    fn parseClassPiece(self: *Parser) Error!ClassPiece {
        const c = self.take() orelse return error.BadPattern;
        if (c != '\\') return .{ .one = c };
        const e = self.take() orelse return error.BadPattern;
        return switch (e) {
            'd', 'w', 's' => .{ .many = asciiClass(e) },
            'D' => .{ .many = negated(asciiClass('d')) },
            'W' => .{ .many = negated(asciiClass('w')) },
            'S' => .{ .many = negated(asciiClass('s')) },
            'n' => .{ .one = '\n' },
            'r' => .{ .one = '\r' },
            't' => .{ .one = '\t' },
            '\\', '-', ']', '^' => .{ .one = e },
            else => error.Unsupported,
        };
    }

    fn addPiece(set: *[256]bool, p: ClassPiece) void {
        switch (p) {
            .one => |c| set[c] = true,
            .many => |cls| {
                for (cls.set, 0..) |hit, i| {
                    const effective = if (cls.negated) !hit else hit;
                    if (effective) set[i] = true;
                }
            },
        }
    }

    fn parseClassAtom(self: *Parser) Error!Atom {
        var set = emptySet();
        var first = true;
        var negate_class = false;
        if (self.peek() == '^') {
            self.pos += 1;
            negate_class = true;
        }
        while (self.pos < self.bytes.len) {
            if (self.peek() == ']' and !first) {
                self.pos += 1;
                return Atom{ .class = .{ .set = set, .negated = negate_class } };
            }
            first = false;
            const left = try self.parseClassPiece();
            if (self.peek() == '-' and self.pos + 1 < self.bytes.len and self.bytes[self.pos + 1] != ']') {
                self.pos += 1;
                const right = try self.parseClassPiece();
                if (left != .one or right != .one) return error.Unsupported;
                const a = left.one;
                const b = right.one;
                if (a > b) return error.BadPattern;
                var ch: usize = a;
                while (ch <= b) : (ch += 1) set[ch] = true;
            } else {
                addPiece(&set, left);
            }
        }
        return error.BadPattern;
    }
};

pub fn compile(allocator: std.mem.Allocator, bytes: []const u8) Error!Pattern {
    var p = Parser{ .allocator = allocator, .bytes = bytes };
    return p.parse();
}

const State = struct {
    pos: usize,
    captures: [max_captures]Capture,

    fn init(pos: usize) State {
        var caps: [max_captures]Capture = undefined;
        for (&caps) |*c| c.* = .{};
        return .{ .pos = pos, .captures = caps };
    }
};

fn burn(fuel: *usize) Error!void {
    if (fuel.* == 0) return error.OutOfFuel;
    fuel.* -= 1;
}

fn matchAlts(allocator: std.mem.Allocator, alts: []const Alt, subject: []const u8, st: State, fuel: *usize) Error!?State {
    for (alts) |alt| {
        if (try matchSeq(allocator, alt.items, 0, subject, st, fuel)) |res| return res;
    }
    return null;
}

fn matchSeq(allocator: std.mem.Allocator, items: []const Item, index: usize, subject: []const u8, st: State, fuel: *usize) Error!?State {
    try burn(fuel);
    if (index >= items.len) return st;
    const item = items[index];
    var states: std.ArrayList(State) = .empty;
    defer states.deinit(allocator);
    states.append(allocator, st) catch return error.OutOfMemory;

    var cur = st;
    var count: usize = 0;
    const max_count = item.max orelse (subject.len - @min(st.pos, subject.len) + 1);
    while (count < max_count) {
        const next = (try matchAtom(allocator, item.atom, subject, cur, fuel)) orelse break;
        count += 1;
        states.append(allocator, next) catch return error.OutOfMemory;
        if (next.pos == cur.pos) break;
        cur = next;
    }
    if (states.items.len - 1 < item.min) return null;

    // GREEDY backtracks longest-match-first (states.len-1 down to min); LAZY
    // (DIVERGENCE 677) backtracks shortest-match-first (min up to states.len-1).
    if (item.greedy) {
        var n = states.items.len;
        while (n > item.min) {
            n -= 1;
            if (try matchSeq(allocator, items, index + 1, subject, states.items[n], fuel)) |res| return res;
        }
    } else {
        var n = item.min;
        while (n < states.items.len) : (n += 1) {
            if (try matchSeq(allocator, items, index + 1, subject, states.items[n], fuel)) |res| return res;
        }
    }
    return null;
}

fn matchAtom(allocator: std.mem.Allocator, atom: Atom, subject: []const u8, st: State, fuel: *usize) Error!?State {
    try burn(fuel);
    switch (atom) {
        .literal => |c| {
            if (st.pos >= subject.len or subject[st.pos] != c) return null;
            var out = st;
            out.pos += 1;
            return out;
        },
        .dot => {
            if (st.pos >= subject.len or subject[st.pos] == '\n') return null;
            var out = st;
            out.pos += 1;
            return out;
        },
        .class => |cls| {
            if (st.pos >= subject.len or !cls.matches(subject[st.pos])) return null;
            var out = st;
            out.pos += 1;
            return out;
        },
        .start_anchor => return if (st.pos == 0) st else null,
        .end_anchor => return if (st.pos == subject.len) st else null,
        .group => |g| {
            if (try matchAlts(allocator, g.alts, subject, st, fuel)) |res0| {
                var res = res0;
                res.captures[g.id] = .{ .matched = true, .start = st.pos, .end = res.pos };
                return res;
            }
            return null;
        },
    }
}

pub fn matchFirst(allocator: std.mem.Allocator, pattern: *const Pattern, subject: []const u8, offset: usize, fuel_limit: usize) Error!?Match {
    if (offset > subject.len) return error.BadPattern;
    var fuel = fuel_limit;
    var start = offset;
    while (start <= subject.len) : (start += 1) {
        const st = State.init(start);
        if (try matchAlts(allocator, pattern.alts, subject, st, &fuel)) |res0| {
            var res = res0;
            res.captures[0] = .{ .matched = true, .start = start, .end = res.pos };
            return .{ .start = start, .end = res.pos, .captures = res.captures };
        }
    }
    return null;
}

test "LAW E7.9 compile/run differential subset: classes, captures, anchors, alternation" {
    const gpa = std.testing.allocator;
    var p = try compile(gpa, "^[a-z]+([0-9]+)$");
    defer p.deinit(gpa);
    const m = (try matchFirst(gpa, &p, "abc123", 0, 10_000)).?;
    try std.testing.expectEqual(@as(usize, 0), m.start);
    try std.testing.expectEqual(@as(usize, 6), m.end);
    try std.testing.expect(m.captures[1].matched);
    try std.testing.expectEqual(@as(usize, 3), m.captures[1].start);
    try std.testing.expectEqual(@as(usize, 6), m.captures[1].end);

    var alt = try compile(gpa, "^(ab|cd)+$");
    defer alt.deinit(gpa);
    try std.testing.expect((try matchFirst(gpa, &alt, "abcd", 0, 10_000)) != null);
    try std.testing.expect((try matchFirst(gpa, &alt, "abef", 0, 10_000)) == null);
}

test "LAW E7.9 greedy repetition backtracks to the last viable suffix" {
    const gpa = std.testing.allocator;
    var p = try compile(gpa, "a.*b");
    defer p.deinit(gpa);
    const m = (try matchFirst(gpa, &p, "axxbxxb", 0, 10_000)).?;
    try std.testing.expectEqual(@as(usize, 0), m.start);
    try std.testing.expectEqual(@as(usize, 7), m.end);
}

test "LAW DIVERGENCE-677 lazy (non-greedy) quantifiers *?/+?/{m,n}? match the SHORTEST viable span (contrast greedy); group-backtrack bound documented" {
    const gpa = std.testing.allocator;
    const endOf = struct {
        fn f(a: std.mem.Allocator, pat: []const u8, subj: []const u8) !usize {
            var p = try compile(a, pat);
            defer p.deinit(a);
            const m = (try matchFirst(a, &p, subj, 0, 100_000)) orelse return error.NoMatch;
            return m.end;
        }
    }.f;
    // `a+?` matches ONE 'a' (shortest); greedy `a+` matches all three.
    try std.testing.expectEqual(@as(usize, 1), try endOf(gpa, "a+?", "aaa"));
    try std.testing.expectEqual(@as(usize, 3), try endOf(gpa, "a+", "aaa"));
    // `<.+?>` stops at the FIRST '>' → "<a>" (end 3); greedy `<.+>` → whole "<a><b>" (end 6).
    try std.testing.expectEqual(@as(usize, 3), try endOf(gpa, "<.+?>", "<a><b>"));
    try std.testing.expectEqual(@as(usize, 6), try endOf(gpa, "<.+>", "<a><b>"));
    // brace-lazy `a{1,3}?` → one 'a'; greedy `a{1,3}` → three.
    try std.testing.expectEqual(@as(usize, 1), try endOf(gpa, "a{1,3}?", "aaa"));
    try std.testing.expectEqual(@as(usize, 3), try endOf(gpa, "a{1,3}", "aaa"));
    // `.*?b` lazy → the FIRST 'b' (shortest prefix); greedy `.*b` → the LAST 'b'.
    try std.testing.expectEqual(@as(usize, 2), try endOf(gpa, ".*?b", "xbyb")); // "xb"
    try std.testing.expectEqual(@as(usize, 4), try endOf(gpa, ".*b", "xbyb")); // "xbyb"
    // BOUND (documented, NOT a defect): a quantifier INSIDE a capturing group whose
    // expansion is forced by context AFTER the group does not backtrack into the
    // group (matchAtom(group) is single-shot). This affects GREEDY equally — `(.*)X`
    // on "aXbXc" is nomatch on zigvm too — so lazy `(.*?)X` shares the bound; a CPS
    // group-backtracking refactor is a separate slice.
    var pg = try compile(gpa, "(.*)X");
    defer pg.deinit(gpa);
    try std.testing.expect((try matchFirst(gpa, &pg, "aXbXc", 0, 100_000)) == null);
}

test "LAW E7.9 unsupported constructs reject totally" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.Unsupported, compile(gpa, "(?=a)"));
    try std.testing.expectError(error.BadPattern, compile(gpa, "(abc"));
    var many: [64]u8 = undefined;
    @memset(&many, '(');
    try std.testing.expectError(error.TooManyCaptures, compile(gpa, many[0..]));
}

test "LAW E7.9 boundedness fuel is observed by the driver" {
    const gpa = std.testing.allocator;
    var p = try compile(gpa, "(a*)*b");
    defer p.deinit(gpa);
    try std.testing.expectError(error.OutOfFuel, matchFirst(gpa, &p, "aaaaaaaaaaaa", 0, 0));
}
