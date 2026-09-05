//! nif_env — the NIF environment bound to the real term heap (the module
//! specification follows immediately below on the `ErlNifEnv` declaration and
//! is the authority for this module's domain, encodings and scope limits).
const std = @import("std");
const FinalTerms = @import("term_algebra.zig").FinalTerms;

/// gap-nif-real-abi: the NIF environment, bound to the REAL term heap.
///
/// erts' `ErlNifEnv` wraps the calling process's heap; a NIF marshals C values
/// into/out of it via `enif_make_*` / `enif_get_*`. Here the env borrows a
/// `FinalTerms.Ctx` — the SAME term representation the VM uses — so the enif ABI
/// builds and reads GENUINE VM terms (not the prior mock ad-hoc tags). What
/// stays out of scope, BY DESIGN (Stratum-C quarantine, exactly like the harness
/// staying OCaml-only): `dlopen`ing a real `.so` and running its native code —
/// arbitrary native execution breaks the pure-Zig-semantics boundary and the
/// sandbox. The ABI SURFACE (term marshalling) is real and law-governed; the
/// native-code LOADER is the deliberate boundary.
pub const ErlNifEnv = struct {
    ctx: *FinalTerms.Ctx,

    pub fn init(ctx: *FinalTerms.Ctx) ErlNifEnv {
        return .{ .ctx = ctx };
    }
};
