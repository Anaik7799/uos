//! # bifs/application — `application:get_env` native intercept (gap-app-boot-engine)
//!
//! Stock OTP apps (ranch/cowboy) read `application:get_env` during their supervisor
//! init. The real `application` module routes that to the `application_controller`
//! process (an `ets:lookup` on `ac_tab`), which zigvm does not boot — so a real
//! Cowboy tree hit `{badarg}`/`{noproc}` before serving (DIVERGENCE 579).
//!
//! These BifFns intercept `application:get_env/1,2,3` at LOAD time (via
//! `dispatch.resolveLibrary`, the `io:put_chars`/`gen_tcp` precedent), so a compiled
//! `call application:get_env` lowers to a native call that never touches the
//! controller. The value is OTP-FAITHFUL for a node with no loaded application env:
//! `get_env(Key)`/`get_env(App,Key)` → `undefined`, `get_env(App,Key,Default)` →
//! `Default` — exactly what OTP returns when the key is unset, so ranch/cowboy fall
//! back to their documented defaults. (Config the caller passes to
//! `cowboy:start_clear/ranch:start_listener` directly is unaffected — it never goes
//! through app env.)
//!
//! SCOPE (honest): this is the READ side only. The full application lifecycle
//! (`ensure_all_started`/`load`/`start`/`set_env`) stays with `app_controller.zig`
//! (the native release-boot engine) or a future booted `application_controller`; a
//! stock app that STORES then reads back its own env is the named residual.

const std = @import("std");
const ta = @import("../term_algebra.zig");
const ia = @import("../instr_algebra.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

fn undefinedAtom(m: *Machine) BifError!Term {
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("undefined"));
}

/// `application:get_env(Key)` → `undefined` (no loaded env → OTP returns undefined).
pub fn get_env_1(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return undefinedAtom(m);
}

/// `application:get_env(App, Key)` → `undefined`.
pub fn get_env_2(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return undefinedAtom(m);
}

/// `application:get_env(App, Key, Default)` → `Default` (arg 2) — the unset-key
/// contract callers rely on.
pub fn get_env_3(m: *Machine, args: []const Term) BifError!Term {
    _ = m;
    return args[2];
}

/// `code:ensure_loaded(Module)` → `{module, Module}` | `{error, nofile}`. It must
/// NOT route to the unbooted `code_server` (`code_server:get_mode` → badarg), AND
/// it must ACTUALLY load the module — a stock app then calls
/// `erlang:function_exported(Module, F, A)`, which fails if the module is only
/// lazily-scheduled and not yet in the code space. So this TRAPS to the Vm (which
/// owns the `--code-path` autoloader) to load the module NOW, then renders the
/// result. Returns a placeholder; the Vm overwrites x0.
pub fn code_ensure_loaded_1(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .code_ensure_loaded = .{ .module = args[0] } };
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("undefined"));
}
