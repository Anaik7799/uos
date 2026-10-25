//! # Zenoh NIF for Elixir
//!
//! Native Zenoh bindings for the Indrajaal safety-critical system.
//!
//! ## IMPORTANT: NIF Function Naming Convention
//! 
//! The Rust function names MUST match the Elixir wrapper function names exactly.
//! Rustler exports functions by their Rust function name, and Elixir looks up
//! functions by name. MISMATCHED NAMES CAUSE "Function not found" errors at runtime.
//!
//! ## Function Name Mapping (Rust -> Elixir)
//!
//! | Rust Function Name              | Elixir Function Name              | Status  |
//! |--------------------------------|----------------------------------|---------|
//! | zenoh_verify_proof_token       | zenoh_verify_proof_token         | CORRECT |
//! | zenoh_verify_session_token      | zenoh_verify_session_token       | CORRECT |
//! | zenoh_classify_tier            | zenoh_classify_tier             | CORRECT |
//!
//! ## Common Mistakes to Avoid
//!
//! WRONG: Using `_nif` suffix in function name
//! ```rust
//! fn verify_proof_token_nif(...)  // WRONG - Elixir expects zenoh_verify_proof_token
//! ```
//!
//! CORRECT: Match Elixir wrapper name
//! ```rust
//! fn zenoh_verify_proof_token(...)  // CORRECT - matches Elixir wrapper
//! ```
//!
//! ## STAMP Constraints
//! - SC-NIF-001: NIF functions must not block BEAM scheduler
//! - SC-NIF-002: Resource cleanup on process exit
//! - SC-NIF-003: Error propagation to Elixir
//! - SC-NIF-004: Rustler version synchronised with mix.exs {:rustler, "~> 0.37"}
//! - SC-NIF-005: ProofToken enforcement at NIF boundary for control-plane keys
//! - SC-NIF-010: Tiered enforcement (Bypass/Session/Full) at NIF boundary
//! - SC-NIF-011: Session token caching with 60s TTL for inference-plane keys
//! - SC-NIF-012: Latency benchmark targets: Tier 0 <1us, Tier 1 <5us, Tier 2 <10us

mod session;
mod publisher;
mod subscriber;
mod types;
mod proof_token;

// Re-export session resource for use in publisher/subscriber modules
pub use session::ZenohSessionResource;
pub use subscriber::ZenohSubscriptionResource;

// SC-NIF-003 + RCA-116503330407891617: catch_unwind helpers at FFI boundary.
// zenoh-rs / tokio internals can panic (e.g. tracing::set_global_default,
// runtime init under runtime.block_on inside a dirty NIF). Workspace sets
// panic="unwind" but unwinding across FFI is UB and surfaces as SIGSEGV in
// BEAM (signal 11). catch_unwind converts the panic into a recoverable Err.
fn ffi_guard_term<'a, F>(env: rustler::Env<'a>, label: &'static str, f: F) -> rustler::NifResult<rustler::Term<'a>>
where
    F: FnOnce() -> rustler::NifResult<rustler::Term<'a>>,
{
    use rustler::Encoder;
    use std::panic::{catch_unwind, AssertUnwindSafe};
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(panic) => {
            let msg = panic_msg(&panic);
            log::error!("[zenoh_nif] PANIC caught in {}: {}", label, msg);
            let error_atom = rustler::types::atom::Atom::from_str(env, "error").unwrap();
            Ok((error_atom, format!("{} panic: {}", label, msg)).encode(env))
        }
    }
}

fn ffi_guard_atom<F>(label: &'static str, f: F) -> rustler::NifResult<rustler::Atom>
where
    F: FnOnce() -> rustler::NifResult<rustler::Atom>,
{
    use std::panic::{catch_unwind, AssertUnwindSafe};
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(panic) => {
            let msg = panic_msg(&panic);
            log::error!("[zenoh_nif] PANIC caught in {}: {}", label, msg);
            Err(rustler::Error::Term(Box::new(format!("{} panic: {}", label, msg))))
        }
    }
}

fn panic_msg(panic: &Box<dyn std::any::Any + Send>) -> String {
    if let Some(s) = panic.downcast_ref::<String>() {
        s.clone()
    } else if let Some(s) = panic.downcast_ref::<&'static str>() {
        (*s).to_string()
    } else {
        "(non-string panic payload)".to_string()
    }
}

// -----------------------------------------------------------------------------
// Session Functions
// -----------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn zenoh_open_session(env: rustler::Env, config_json: String) -> rustler::NifResult<rustler::Term> {
    ffi_guard_term(env, "zenoh_open_session", || session::zenoh_open_session(env, config_json))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn close_session(session: rustler::ResourceArc<ZenohSessionResource>) -> rustler::Atom {
    session::zenoh_close_session(session)
}

#[rustler::nif]
fn session_info(env: rustler::Env, session: rustler::ResourceArc<ZenohSessionResource>) -> rustler::NifResult<rustler::Term> {
    ffi_guard_term(env, "session_info", || session::zenoh_session_info(env, session))
}

#[rustler::nif]
fn session_status(env: rustler::Env, session: rustler::ResourceArc<ZenohSessionResource>) -> rustler::NifResult<rustler::Term> {
    ffi_guard_term(env, "session_status", || session::zenoh_session_status(env, session))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn get(env: rustler::Env, session: rustler::ResourceArc<ZenohSessionResource>, key_expr: String) -> rustler::NifResult<rustler::Term> {
    ffi_guard_term(env, "get", || session::zenoh_get(env, session, key_expr))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn get_timeout(env: rustler::Env, session: rustler::ResourceArc<ZenohSessionResource>, key_expr: String, timeout_ms: u64) -> rustler::NifResult<rustler::Term> {
    ffi_guard_term(env, "get_timeout", || session::zenoh_get_timeout(env, session, key_expr, timeout_ms))
}

// -----------------------------------------------------------------------------
// Publisher Functions
// -----------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn publish(session: rustler::ResourceArc<ZenohSessionResource>, key: String, payload: rustler::Binary) -> rustler::NifResult<rustler::Atom> {
    ffi_guard_atom("publish", || publisher::zenoh_publish(session, key, payload))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn put(session: rustler::ResourceArc<ZenohSessionResource>, key: String, payload: rustler::Binary) -> rustler::NifResult<rustler::Atom> {
    ffi_guard_atom("put", || publisher::zenoh_put(session, key, payload))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn delete(session: rustler::ResourceArc<ZenohSessionResource>, key: String) -> rustler::NifResult<rustler::Atom> {
    ffi_guard_atom("delete", || publisher::zenoh_delete(session, key))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn publish_batch(env: rustler::Env, session: rustler::ResourceArc<ZenohSessionResource>, messages: Vec<types::BatchPublishRequest>) -> rustler::NifResult<rustler::Term> {
    ffi_guard_term(env, "publish_batch", || publisher::zenoh_publish_batch(env, session, messages))
}

// -----------------------------------------------------------------------------
// ProofToken Verification NIF (SC-NIF-005)
// -----------------------------------------------------------------------------

/// Fast-path ProofToken verification callable from Elixir.
///
/// Allows the Elixir layer to verify a proof token at the Rust level without
/// performing a full publish.  This is useful for pre-validation before
/// constructing a full control-plane message.
///
/// ## Parameters
/// - `token_binary` — Raw JSON bytes of the outer payload containing `proof_token`
///
/// ## Returns
/// - `{:ok, :valid}` — Token is present and signature is correct
/// - `{:error, reason}` — Token is absent, malformed, or signature is invalid
#[rustler::nif]
fn zenoh_verify_proof_token<'a>(env: rustler::Env<'a>, token_binary: rustler::Binary<'a>) -> rustler::NifResult<rustler::Term<'a>> {
    use rustler::Encoder;
    match proof_token::verify_from_payload(token_binary.as_slice()) {
        Ok(()) => {
            let ok_atom = rustler::types::atom::Atom::from_str(env, "ok").unwrap();
            let valid_atom = rustler::types::atom::Atom::from_str(env, "valid").unwrap();
            Ok((ok_atom, valid_atom).encode(env))
        }
        Err(e) => {
            let error_atom = rustler::types::atom::Atom::from_str(env, "error").unwrap();
            Ok((error_atom, format!("{}", e)).encode(env))
        }
    }
}

// -----------------------------------------------------------------------------
// Session Token Verification NIF (SC-NIF-011)
// -----------------------------------------------------------------------------

/// Fast-path session token verification for inference-plane keys.
///
/// Uses the cached session token (60s TTL) to avoid full HMAC computation
/// on every inference request.  Falls back to full verification and caches
/// the result on success.
///
/// ## Parameters
/// - `token_binary` — Raw JSON bytes of the payload containing `proof_token`
///
/// ## Returns
/// - `{:ok, :valid}` — Token is present and signature is correct (possibly cached)
/// - `{:error, reason}` — Token is absent, malformed, or signature is invalid
#[rustler::nif]
fn zenoh_verify_session_token<'a>(env: rustler::Env<'a>, token_binary: rustler::Binary<'a>) -> rustler::NifResult<rustler::Term<'a>> {
    use rustler::Encoder;
    match proof_token::verify_session(token_binary.as_slice()) {
        Ok(()) => {
            let ok_atom = rustler::types::atom::Atom::from_str(env, "ok").unwrap();
            let valid_atom = rustler::types::atom::Atom::from_str(env, "valid").unwrap();
            Ok((ok_atom, valid_atom).encode(env))
        }
        Err(e) => {
            let error_atom = rustler::types::atom::Atom::from_str(env, "error").unwrap();
            Ok((error_atom, format!("{}", e)).encode(env))
        }
    }
}

// -----------------------------------------------------------------------------
// Tier Classification NIF (SC-NIF-010)
// -----------------------------------------------------------------------------

/// Classify a key expression into its enforcement tier.
///
/// Returns the tier as an atom: `:bypass`, `:session`, or `:full`.
/// Useful for Elixir-side routing decisions without performing actual verification.
#[rustler::nif]
fn zenoh_classify_tier<'a>(env: rustler::Env<'a>, key_expr: String) -> rustler::NifResult<rustler::Term<'a>> {
    use rustler::Encoder;
    let tier = match proof_token::classify_tier(&key_expr) {
        proof_token::EnforcementTier::Bypass => "bypass",
        proof_token::EnforcementTier::Session => "session",
        proof_token::EnforcementTier::Full => "full",
    };
    let atom = rustler::types::atom::Atom::from_str(env, tier).unwrap();
    Ok(atom.encode(env))
}

// -----------------------------------------------------------------------------
// Subscriber Functions
// -----------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn subscribe(env: rustler::Env, session: rustler::ResourceArc<ZenohSessionResource>, key_expr: String, callback_pid: rustler::LocalPid) -> rustler::NifResult<rustler::Term> {
    ffi_guard_term(env, "subscribe", || subscriber::zenoh_subscribe(env, session, key_expr, callback_pid))
}

#[rustler::nif]
fn unsubscribe(subscription: rustler::ResourceArc<ZenohSubscriptionResource>) -> rustler::Atom {
    subscriber::zenoh_unsubscribe(subscription)
}

#[rustler::nif]
fn poll_messages(env: rustler::Env, subscription: rustler::ResourceArc<ZenohSubscriptionResource>, max_messages: usize) -> rustler::NifResult<rustler::Term> {
    ffi_guard_term(env, "poll_messages", || subscriber::zenoh_poll_messages(env, subscription, max_messages))
}

#[rustler::nif]
fn subscription_stats(env: rustler::Env, subscription: rustler::ResourceArc<ZenohSubscriptionResource>) -> rustler::NifResult<rustler::Term> {
    ffi_guard_term(env, "subscription_stats", || subscriber::zenoh_subscription_stats(env, subscription))
}

// Rustler 0.37+ auto-discovers NIF functions via #[rustler::nif] attribute
// SC-NIF-004: Rustler version synchronized with mix.exs {:rustler, "~> 0.37"}
rustler::init!("Elixir.Indrajaal.Native.Zenoh", load = load);

/// NIF load callback — initialises resources
/// SC-NIF-002: Resource cleanup on process exit
fn load(env: rustler::Env, _info: rustler::Term) -> bool {
    // Register resources for Rustler 0.37+
    // These use the Resource trait impl for proper lifecycle management
    env.register::<ZenohSessionResource>().is_ok()
        && env.register::<ZenohSubscriptionResource>().is_ok()
}
