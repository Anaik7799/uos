//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/substrate/beam_cache</module>
////     <fsharp-lineage>N/A — BEAM-native: no F# equivalent</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-FUNC-004, SC-MUDA-001, SC-ARCH-SPLIT-002</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Erlang ETS named table ≅ Gleam beam_cache.EtsCache type.
////       Zero information loss — all ETS operations map 1:1 via FFI.
////     </morphism>
////     <morphism type="injective">
////       Erlang persistent_term ↪ Gleam ConfigStore abstraction.
////       The BEAM-global namespace is surfaced as a typed Gleam API.
////       The {c3i_config, Key} tuple namespace is hidden behind the FFI.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// F07: ETS Shared State Cache
////   Concurrent read access for dashboard data without actor message passing.
////   Uses a public named ETS table with {read_concurrency, true} — all BEAM
////   processes can read in parallel without any locking or mailbox overhead.
////
//// F08: persistent_term Hot Config
////   Globally accessible configuration at O(1) cost.  Writes trigger a process
////   GC scan (use sparingly), reads are essentially free — ideal for system
////   version strings, feature flags, and infrequently-changing tunables.
////
//// STAMP: SC-FUNC-004 (state recoverable), SC-MUDA-001 (zero waste),
////        SC-ARCH-SPLIT-002 (BEAM primitives in Gleam layer)
////
//// अक्षरं ब्रह्म परमम् — The imperishable is the supreme Brahman (Gita 8.3)

// ---------------------------------------------------------------------------
// ETS Cache (F07) — concurrent read, O(1) access, no actor bottleneck
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">ETS named_table ≅ init/0</morphism>
///   <formal-proof>
///     <P> Pre-condition: c3i_cache table does not exist OR already exists. </P>
///     <C> ets_init() — create or skip </C>
///     <Q> Post-condition: c3i_cache ETS table exists, public, read_concurrency. </Q>
///   </formal-proof>
/// </c3i-atomic>
@external(erlang, "beam_cache_ffi", "ets_init")
pub fn init() -> Result(Nil, String)

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">ets:insert ≅ put/2</morphism>
///   <formal-proof>
///     <P> Pre-condition: c3i_cache table exists (init called). </P>
///     <C> ets_put(key, value) </C>
///     <Q> Post-condition: get(key) == Ok(value). Previous binding overwritten. </Q>
///   </formal-proof>
/// </c3i-atomic>
@external(erlang, "beam_cache_ffi", "ets_put")
pub fn put(key: String, value: String) -> Result(Nil, String)

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">ets:lookup ≅ get/1</morphism>
///   <formal-proof>
///     <P> Pre-condition: c3i_cache table exists. </P>
///     <C> ets_get(key) </C>
///     <Q> Post-condition: Ok(value) when key present; Error("not_found") otherwise. </Q>
///   </formal-proof>
/// </c3i-atomic>
@external(erlang, "beam_cache_ffi", "ets_get")
pub fn get(key: String) -> Result(String, String)

/// [C3I-SIL6] ATOMIC CONTRACT — remove a key; idempotent if key absent
@external(erlang, "beam_cache_ffi", "ets_delete")
pub fn delete(key: String) -> Result(Nil, String)

/// Return all keys currently held in the cache.
@external(erlang, "beam_cache_ffi", "ets_keys")
pub fn keys() -> List(String)

/// Return the number of entries in the cache.
@external(erlang, "beam_cache_ffi", "ets_size")
pub fn size() -> Int

// ---------------------------------------------------------------------------
// persistent_term Config Store (F08) — O(1) read, no message passing
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">persistent_term:put ↪ set_config/2</morphism>
///   <formal-proof>
///     <P> Pre-condition: key is a valid string config identifier. </P>
///     <C> pt_set(key, value) — triggers GC scan of all processes </C>
///     <Q> Post-condition: get_config(key) == Ok(value). </Q>
///   </formal-proof>
/// </c3i-atomic>
@external(erlang, "beam_cache_ffi", "pt_set")
pub fn set_config(key: String, value: String) -> Result(Nil, String)

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">persistent_term:get ↪ get_config/1</morphism>
///   <formal-proof>
///     <P> Pre-condition: any (key may or may not exist). </P>
///     <C> pt_get(key) — O(1), no message passing, no lock </C>
///     <Q> Post-condition: Ok(value) when key present; Error("not_found") otherwise. </Q>
///   </formal-proof>
/// </c3i-atomic>
@external(erlang, "beam_cache_ffi", "pt_get")
pub fn get_config(key: String) -> Result(String, String)

/// Store the system version string for cache busting.
/// This is a thin wrapper over set_config with the canonical "version" key.
pub fn set_version(version: String) -> Result(Nil, String) {
  set_config("version", version)
}

/// Retrieve the system version string.
/// Returns "unknown" when no version has been set yet.
pub fn get_version() -> String {
  case get_config("version") {
    Ok(v) -> v
    Error(_) -> "unknown"
  }
}
