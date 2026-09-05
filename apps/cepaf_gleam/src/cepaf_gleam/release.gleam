//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/release</module>
////     <fsharp-lineage>None — BEAM-native release metadata (Phase 5.1)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Release version metadata — single authoritative source of truth
////       for the current C3I build identity.  Consumed by the health
////       endpoint, TUI header, and OTel span attributes.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>NON-SAFETY — read-only metadata</criticality>
////     <stamp-controls>
////       SC-MUDA-001, SC-ARCH-SPLIT-002, SC-GLM-UI-004
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Compile-time string constants ≅ runtime String values.
////       Gleam pub const is inlined by the compiler; zero information loss.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// RELEASE VERSION AND METADATA
//// ज्ञान — Jnana (Wisdom): the release codename for v22.12.0
////
//// This module is the single authoritative source for:
////   - Semantic version string (SemVer 2.0)
////   - Release codename (Sanskrit philosophical term)
////   - Composed version and info strings used by TUI, REST /health, OTel
////
//// When releasing a new version, update `version` and `codename` here ONLY.
//// All other modules derive their display from version_string/0 and full_info/0.
////
//// STAMP: SC-MUDA-001 — single canonical source, no duplication.

/// Semantic version string — SemVer 2.0 (major.minor.patch).
pub const version = "22.12.0"

/// Release codename — Sanskrit philosophical concept.
pub const codename = "JNANA"

/// Sanskrit script of the codename — used in TUI headers and OTel attributes.
pub const sanskrit = "ज्ञान"

/// Build a short version string: "v22.12.0-JNANA"
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     version × codename ≅ "v" <> version <> "-" <> codename
///   </morphism>
///   <formal-proof>
///     <P> Pre: version and codename are non-empty compile-time strings. </P>
///     <C> version_string/0 </C>
///     <Q> Post: result starts with "v", contains version, contains codename. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn version_string() -> String {
  "v" <> version <> "-" <> codename
}

/// Build the full release info line for health endpoints and TUI headers.
///
/// Format: "C3I v22.12.0-JNANA (ज्ञान — Wisdom) | Tests: 5253 | Modules: 65+ | Rules: 30 | CA: 10"
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     version_string × sanskrit × metrics ≅ full_info string
///   </morphism>
///   <formal-proof>
///     <P> Pre: version_string/0 is non-empty. </P>
///     <C> full_info/0 </C>
///     <Q> Post: result contains "C3I", version_string, sanskrit, and metric counts. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn full_info() -> String {
  "C3I "
  <> version_string()
  <> " ("
  <> sanskrit
  <> " \u{2014} Wisdom)"
  <> " | Tests: 5253 | Modules: 65+ | Rules: 30 | CA: 10"
}
