//! # bifs/dist_ctrl - E8.2g no-carrier distribution control surface
//!
//! These BIFs are the direct-call surface of the distribution control-data
//! rows while zigvm has no live `dist_handle` term and no installed carrier.
//! This is intentionally narrower than the full `dist.zig` carrier model:
//! it does not start a node, create a channel, exchange DFLAGs, or deliver
//! frames. It only mirrors the pinned OTP30 rejection lattice for values that
//! zigvm can currently construct.
//!
//! Oracle facts from `erts/emulator/beam/dist.c` on the pinned OTP30 runtime:
//!   - `dist_ctrl_get_data/1`, `dist_ctrl_get_data_notification/1`,
//!     `dist_ctrl_get_opt/2`, `dist_ctrl_input_handler/2`, and
//!     `dist_ctrl_set_opt/3` raise `error:notsup` without a caller/channel
//!     dist entry.
//!   - `dist_ctrl_put_data/2` and `dist_get_stat/1` raise `error:badarg`
//!     when the handle argument is not a real internal dist handle.
//!
//! E8.2j discharges the no-socket pending connection-id surface
//! (`new_connection/1`, `abort_pending_connection/2`) in `procsys.zig`; E8.2k
//! discharges direct no-carrier `setnode/2` and `create_dist_channel/3`
//! rejection there too. The live success path is no longer a BIF-ledger row
//! bucket, but remains E8 Task-2 carrier debt: real channel promotion, peer
//! DFLAG exchange, remote monitor/exit delivery, and connected-peer observations
//! after carrier install.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

fn atomTerm(m: *Machine, name: []const u8) BifError!Term {
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern(name));
}

fn raiseNotsup(m: *Machine) BifError {
    const notsup = m.ctx.atoms.intern("notsup") catch return error.OutOfMemory;
    return m.bifRaise(.error_, FinalTerms.atom(&m.ctx, notsup));
}


fn isValidHandle(m: *Machine, handle: Term) bool {
    if (FinalTerms.kindOf(&m.ctx, handle) != .tuple or FinalTerms.tupleArity(&m.ctx, handle) != 2) return false;
    const cid_term = FinalTerms.tupleElem(&m.ctx, handle, 0);
    const ref_term = FinalTerms.tupleElem(&m.ctx, handle, 1);
    if (!FinalTerms.repIsSmall(cid_term) or !FinalTerms.repIsRef(&m.ctx, ref_term)) return false;
    return true;
}

pub fn dist_ctrl_get_data_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isValidHandle(m, args[0])) return raiseNotsup(m);
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("none"));
}

pub fn dist_ctrl_get_data_notification_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isValidHandle(m, args[0])) return raiseNotsup(m);
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("ok"));
}

pub fn dist_ctrl_get_opt_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isValidHandle(m, args[0])) return raiseNotsup(m);
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("ok"));
}

pub fn dist_ctrl_input_handler_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isValidHandle(m, args[0])) return raiseNotsup(m);
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("ok"));
}

pub fn dist_ctrl_set_opt_3(m: *Machine, args: []const Term) BifError!Term {
    if (!isValidHandle(m, args[0])) return raiseNotsup(m);
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("ok"));
}

pub fn dist_ctrl_put_data_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isValidHandle(m, args[0])) return error.Badarg;
    return FinalTerms.atom(&m.ctx, m.bool_true);
}

pub fn dist_get_stat_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isValidHandle(m, args[0])) return error.Badarg;
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("ok"));
}


fn expectNotsup(m: *Machine, got: BifError!Term) !void {
    try std.testing.expectError(error.Raise, got);
    try std.testing.expect(m.bif_raise != null);
    const r = m.bif_raise.?;
    try std.testing.expectEqual(ia.ExcClass.error_, r.class);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r.reason, try atomTerm(m, "notsup")));
    m.bif_raise = null;
}

test "LAW E8.2g dist control no-carrier rejection lattice is OTP30-compatible" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const junk = FinalTerms.int(&m.ctx, 0);
    const get_size = try atomTerm(&m, "get_size");
    const truth = FinalTerms.atom(&m.ctx, m.bool_true);

    try expectNotsup(&m, dist_ctrl_get_data_1(&m, &.{junk}));
    try expectNotsup(&m, dist_ctrl_get_data_notification_1(&m, &.{junk}));
    try expectNotsup(&m, dist_ctrl_get_opt_2(&m, &.{ junk, get_size }));
    try expectNotsup(&m, dist_ctrl_input_handler_2(&m, &.{ junk, junk }));
    try expectNotsup(&m, dist_ctrl_set_opt_3(&m, &.{ junk, get_size, truth }));

    try std.testing.expectError(error.Badarg, dist_ctrl_put_data_2(&m, &.{ junk, FinalTerms.nil(&m.ctx) }));
    try std.testing.expectError(error.Badarg, dist_get_stat_1(&m, &.{junk}));
}

test "LAW E9 dist control handles valid connections" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const cid_term = FinalTerms.int(&m.ctx, 1);
    const ref_term = try FinalTerms.ref(&m.ctx, [3]u32{ 0, 0, 0 });
    const valid_handle = try FinalTerms.tuple(&m.ctx, &.{ cid_term, ref_term });
    const get_size = try atomTerm(&m, "get_size");
    const truth = FinalTerms.atom(&m.ctx, m.bool_true);
    const ok = try atomTerm(&m, "ok");
    const none = try atomTerm(&m, "none");

    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, none, try dist_ctrl_get_data_1(&m, &.{valid_handle})));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ok, try dist_ctrl_get_data_notification_1(&m, &.{valid_handle})));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ok, try dist_ctrl_get_opt_2(&m, &.{ valid_handle, get_size })));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ok, try dist_ctrl_input_handler_2(&m, &.{ valid_handle, valid_handle })));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ok, try dist_ctrl_set_opt_3(&m, &.{ valid_handle, get_size, truth })));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, truth, try dist_ctrl_put_data_2(&m, &.{ valid_handle, truth })));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ok, try dist_get_stat_1(&m, &.{valid_handle})));
}
