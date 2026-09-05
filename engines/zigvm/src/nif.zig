//! gap-nif-real-abi: the enif_* TERM-MARSHALLING ABI, bound to the REAL term
//! algebra. A native NIF converts between C values and BEAM terms through this
//! surface (`enif_make_int`/`enif_get_int`/`enif_make_atom`/`enif_make_binary`/
//! `enif_get_binary`/`enif_make_tuple`), matching erl_nif.c's contract:
//!   - `enif_make_*` build a genuine VM term on the env's heap.
//!   - `enif_get_*` return a BOOL (1 on the right type, 0 otherwise — NEVER a
//!     wrong value / crash on a type mismatch) and write the extracted C value.
//! The `dlopen`/native-code LOADER stays quarantined by design (nif_env.zig).
const std = @import("std");
const FinalTerms = @import("term_algebra.zig").FinalTerms;
pub const env = @import("nif_env.zig");
pub const epmd_bridge = @import("epmd_bridge.zig");
pub const ErlNifEnv = env.ErlNifEnv;

pub const ERL_NIF_TERM = FinalTerms.Term;

/// enif_make_int (ErlNifSInt = C `int`, 32-bit → always fits a small).
pub fn enif_make_int(e: *ErlNifEnv, i: i32) ERL_NIF_TERM {
    return FinalTerms.int(e.ctx, i);
}

/// enif_get_int → 1 iff `term` is a small integer in the C-`int` range; writes
/// the value. 0 (no write) on a non-int OR an out-of-range int — erl_nif.c's
/// exact contract (a bignum or a float is NOT an int).
pub fn enif_get_int(e: *ErlNifEnv, term: ERL_NIF_TERM, out: *i32) bool {
    _ = e;
    if (!FinalTerms.repIsSmall(term)) return false;
    const v = FinalTerms.smallValOf(term);
    if (v < std.math.minInt(i32) or v > std.math.maxInt(i32)) return false;
    out.* = @intCast(v);
    return true;
}

/// enif_make_atom (interns into the shared atom table).
pub fn enif_make_atom(e: *ErlNifEnv, name: []const u8) !ERL_NIF_TERM {
    return FinalTerms.atom(e.ctx, try e.ctx.atoms.intern(name));
}

/// enif_make_binary (a real off-heap/on-heap binary per the size threshold).
pub fn enif_make_binary(e: *ErlNifEnv, bytes: []const u8) !ERL_NIF_TERM {
    return try FinalTerms.binary(e.ctx, bytes);
}

/// enif_get_binary → 1 iff `term` is a binary; writes its bytes (a borrowed view
/// through the read choke point). 0 on a non-binary.
pub fn enif_get_binary(e: *ErlNifEnv, term: ERL_NIF_TERM, out: *[]const u8) bool {
    if (!FinalTerms.repIsBinary(e.ctx, term)) return false;
    out.* = FinalTerms.binBytes(e.ctx, term);
    return true;
}

/// enif_make_tuple.
pub fn enif_make_tuple(e: *ErlNifEnv, terms: []const ERL_NIF_TERM) !ERL_NIF_TERM {
    return try FinalTerms.tuple(e.ctx, terms);
}

const AtomTable = @import("atom_table.zig").AtomTable;

test "LAW gap-nif-real-abi enif term-marshalling ABI: make/get ROUND-TRIP on REAL terms; get_* returns 0 (never a wrong value) on a type mismatch; matches erl_nif.c" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();
    var e = ErlNifEnv.init(&ctx);

    // (1) int ROUND-TRIP over the full C-int range, seeded.
    var prng = std.Random.DefaultPrng.init(0x1F_A81_C0DE);
    const rnd = prng.random();
    var k: usize = 0;
    while (k < 256) : (k += 1) {
        const i: i32 = rnd.int(i32);
        const t = enif_make_int(&e, i);
        var got: i32 = undefined;
        try std.testing.expect(enif_get_int(&e, t, &got)); // a real small int
        try std.testing.expectEqual(i, got); // round-trips exactly
    }

    // (2) binary ROUND-TRIP (incl. a ≥64B ProcBin — get reads through binBytes).
    const payload = "enif marshalled binary — long enough to be an off-heap ProcBin refc!";
    const bt = try enif_make_binary(&e, payload);
    var bytes: []const u8 = undefined;
    try std.testing.expect(enif_get_binary(&e, bt, &bytes));
    try std.testing.expectEqualStrings(payload, bytes);

    // (3) TYPE-SAFETY (erl_nif.c: get_* returns 0 on a mismatch, never a wrong
    //     value or a crash — the mutant target). An atom is neither int nor
    //     binary; a binary is not an int; an int is not a binary.
    const atom = try enif_make_atom(&e, "an_atom");
    var scratch_i: i32 = 12345;
    try std.testing.expect(!enif_get_int(&e, atom, &scratch_i)); // atom is not an int
    try std.testing.expectEqual(@as(i32, 12345), scratch_i); // NO write on failure
    try std.testing.expect(!enif_get_int(&e, bt, &scratch_i)); // binary is not an int
    var scratch_b: []const u8 = undefined;
    try std.testing.expect(!enif_get_binary(&e, atom, &scratch_b)); // atom is not a binary
    try std.testing.expect(!enif_get_binary(&e, enif_make_int(&e, 7), &scratch_b)); // int is not a binary

    // (4) tuple builds a real 2-tuple observable via the term algebra.
    const tup = try enif_make_tuple(&e, &.{ enif_make_int(&e, 1), atom });
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&ctx, tup)); // a real 2-tuple
    // its elements marshal back: element 0 is the int 1.
    var e0: i32 = undefined;
    try std.testing.expect(enif_get_int(&e, FinalTerms.tupleElem(&ctx, tup, 0), &e0));
    try std.testing.expectEqual(@as(i32, 1), e0);
}
