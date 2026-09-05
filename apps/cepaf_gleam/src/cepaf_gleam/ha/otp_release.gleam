//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/otp_release</module>
////     <fsharp-lineage>None — novel BEAM-native OTP release infrastructure</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       OTP release packaging — .rel and .appup typed representations for
////       hot code upgrade planning.  Provides typed wrappers for Erlang/OTP
////       release specification concepts without executing any VM operations.
////       Companion to ha/hot_reload.gleam which performs the actual reload.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-RELOAD-001, SC-HA-001, SC-FUNC-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Erlang .rel file format ↪ ReleaseSpec type.
////       .rel is a flat Erlang term; ReleaseSpec embeds it as a typed Gleam value.
////       No information is lost; all fields map 1:1.
////     </morphism>
////     <morphism type="injective">
////       Erlang .appup file format ↪ AppUpSpec type.
////       upgrade_from and downgrade_to lists map to List(UpgradeInstruction).
////       Erlang atoms (add_module, load_module, etc.) map to ADT variants.
////     </morphism>
////     <morphism type="surjective" loss="runtime module identity">
////       Erlang module atoms ↪ String.
////       Erlang represents module names as atoms; Gleam uses String.
////       Mitigation: callers are responsible for ensuring String matches the
////       actual BEAM module atom at runtime.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// OTP Release Specification Types (SC-HA-RELOAD-001)
////
//// Provides typed representations of .rel and .appup files for hot code
//// upgrade planning.  Does NOT perform live VM operations — use ha/hot_reload
//// for the actual code:load_file/soft_purge sequences.
////
//// .rel layout (Erlang term):
////   {release, {Name, Vsn}, {erts, ErtsVsn},
////    [{AppName, AppVsn, AppType}, ...]}
////
//// .appup layout (Erlang term):
////   {Vsn,
////    [{FromVsn, [Instruction, ...]}],  %% upgrade_from
////    [{ToVsn,   [Instruction, ...]}]}  %% downgrade_to
////
//// STAMP: SC-HA-RELOAD-001, SC-HA-001

import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types — ReleaseSpec (.rel)
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Erlang .rel term ↪ ReleaseSpec</morphism>
///   <formal-proof>
///     <P> Pre-condition: name, version, erts_version are non-empty strings;
///         applications is a well-formed list. </P>
///     <C> ReleaseSpec is a pure value — no side effects. </C>
///     <Q> Post-condition: field values equal the supplied arguments. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub type ReleaseSpec {
  ReleaseSpec(
    /// Name of the release (e.g. "cepaf_gleam").
    name: String,
    /// Release version string (e.g. "22.12.0").
    version: String,
    /// ERTS version this release was built against (e.g. "15.0").
    erts_version: String,
    /// Ordered list of OTP applications included in the release.
    applications: List(AppSpec),
  )
}

/// OTP application descriptor — one entry in the .rel applications list.
pub type AppSpec {
  AppSpec(
    /// Application name, e.g. "kernel", "stdlib", "cepaf_gleam".
    name: String,
    /// Application version string.
    version: String,
    /// OTP start type — controls supervisor restart behaviour.
    type_: AppType,
  )
}

/// OTP application start type.
///
/// Permanent — if this app terminates, the node terminates.
/// Transient — if this app terminates abnormally, the node terminates;
///             normal exit is tolerated.
/// Temporary — app termination (normal or abnormal) is silently tolerated.
pub type AppType {
  Permanent
  Transient
  Temporary
}

// ---------------------------------------------------------------------------
// Public types — AppUpSpec (.appup)
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Erlang .appup term ↪ AppUpSpec</morphism>
///   <formal-proof>
///     <P> Pre-condition: version is a non-empty string; instruction lists
///         are well-formed. </P>
///     <C> AppUpSpec is a pure value — no side effects. </C>
///     <Q> Post-condition: all three fields equal the supplied arguments. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub type AppUpSpec {
  AppUpSpec(
    /// New version string this appup applies to.
    version: String,
    /// Upgrade instructions to apply when upgrading FROM an older version.
    upgrade_from: List(UpgradeInstruction),
    /// Downgrade instructions to apply when reverting TO a previous version.
    downgrade_to: List(UpgradeInstruction),
  )
}

/// A single instruction in an .appup upgrade or downgrade list.
///
/// Maps directly to the corresponding Erlang appup instruction atom/tuple.
pub type UpgradeInstruction {
  /// Load a new module (first time — module was not present before).
  /// Erlang: {add_module, Module}
  AddModule(module: String)
  /// Load a changed module — equivalent to code:load_file.
  /// Erlang: {load_module, Module}
  LoadModule(module: String)
  /// Update a module using the code_change/3 callback (soft upgrade).
  /// Erlang: {update, Module}
  UpdateModule(module: String)
  /// Remove a module that no longer exists in the new version.
  /// Erlang: {delete_module, Module}
  DeleteModule(module: String)
  /// Restart an entire application (last resort for incompatible changes).
  /// Erlang: {restart_application, Application}
  Restart(application: String)
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

/// Generate a ReleaseSpec for the current C3I system.
///
/// Includes the standard OTP kernel set plus cepaf_gleam itself.
/// ERTS version is pinned to "15.0" — update when upgrading OTP.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">() ≅ ReleaseSpec for C3I 22.12.0</morphism>
///   <formal-proof>
///     <P> Pre-condition: none. </P>
///     <C> Returns a constant ReleaseSpec reflecting the current release. </C>
///     <Q> Post-condition: result.name == "cepaf_gleam" and
///         result.version == "22.12.0". </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn current_release() -> ReleaseSpec {
  ReleaseSpec(
    name: "cepaf_gleam",
    version: "22.12.0",
    erts_version: "15.0",
    applications: [
      AppSpec(name: "kernel", version: "10.0", type_: Permanent),
      AppSpec(name: "stdlib", version: "6.0", type_: Permanent),
      AppSpec(name: "sasl", version: "4.2", type_: Permanent),
      AppSpec(name: "cepaf_gleam", version: "22.12.0", type_: Permanent),
    ],
  )
}

/// Generate an AppUpSpec from a list of changed module names.
///
/// Applies a simple policy:
///   - All changed modules get `LoadModule` instructions.
///   - Symmetric instructions are generated for downgrade_to.
///
/// For modules requiring state migration (code_change/3), callers should
/// replace LoadModule with UpdateModule in the returned spec.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">
///     (version: String, changed_modules: List(String)) ↪ AppUpSpec
///   </morphism>
///   <formal-proof>
///     <P> Pre-condition: version is non-empty; changed_modules may be empty. </P>
///     <C> Maps each module name to a LoadModule instruction for upgrade and
///         a symmetric LoadModule for downgrade (reload the old bytecode). </C>
///     <Q> Post-condition:
///         result.version == version;
///         list.length(result.upgrade_from) == list.length(changed_modules);
///         list.length(result.downgrade_to) == list.length(changed_modules). </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn appup_from_changes(
  version: String,
  changed_modules: List(String),
) -> AppUpSpec {
  let instructions = list.map(changed_modules, LoadModule)
  AppUpSpec(
    version: version,
    upgrade_from: instructions,
    downgrade_to: instructions,
  )
}

// ---------------------------------------------------------------------------
// Formatters
// ---------------------------------------------------------------------------

/// Format a ReleaseSpec as an Erlang term string suitable for a .rel file.
///
/// Output format:
///   {release, {"Name", "Vsn"}, {erts, "ErtsVsn"},
///    [{app1, "1.0", permanent}, ...]}.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="surjective" loss="Gleam type information">
///     ReleaseSpec ↠ String.
///     The Gleam AppType ADT is serialised to an Erlang atom; the reverse
///     parse is not guaranteed lossless for non-standard types.
///     Mitigation: only canonical AppType variants are produced.
///   </morphism>
///   <formal-proof>
///     <P> Pre-condition: spec is well-formed. </P>
///     <C> Formats each field as an Erlang term substring and concatenates. </C>
///     <Q> Post-condition: result starts with "{release," and ends with "}.". </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn format_rel(spec: ReleaseSpec) -> String {
  let apps_str =
    spec.applications
    |> list.map(format_app_spec)
    |> string.join(", ")

  "{"
  <> "release, "
  <> "{\""
  <> spec.name
  <> "\", \""
  <> spec.version
  <> "\"}, "
  <> "{erts, \""
  <> spec.erts_version
  <> "\"}, "
  <> "["
  <> apps_str
  <> "]}."
}

/// Format an AppUpSpec as an Erlang term string suitable for an .appup file.
///
/// Output format:
///   {"Vsn",
///    [{".*", [Instructions...]}],
///    [{".*", [Instructions...]}]}.
///
/// The wildcard pattern ".*" matches any previous version, which is safe
/// for rolling upgrades within the same major release series.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="surjective" loss="Gleam type information">
///     AppUpSpec ↠ String.
///     UpgradeInstruction ADT variants → Erlang tuple strings.
///     Mitigation: format_instruction/1 covers all known variants exhaustively.
///   </morphism>
///   <formal-proof>
///     <P> Pre-condition: spec is well-formed. </P>
///     <C> Formats each instruction list and wraps in Erlang term syntax. </C>
///     <Q> Post-condition: result starts with "{\"" and ends with "}.". </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn format_appup(spec: AppUpSpec) -> String {
  let upgrade_str = format_instruction_list(spec.upgrade_from)
  let downgrade_str = format_instruction_list(spec.downgrade_to)

  "{\""
  <> spec.version
  <> "\",\n"
  <> " [{\".*\", "
  <> upgrade_str
  <> "}],\n"
  <> " [{\".*\", "
  <> downgrade_str
  <> "}]}."
}

// ---------------------------------------------------------------------------
// Helpers — AppType atom serialisation
// ---------------------------------------------------------------------------

/// Serialise AppType to its Erlang atom string.
pub fn app_type_to_string(t: AppType) -> String {
  case t {
    Permanent -> "permanent"
    Transient -> "transient"
    Temporary -> "temporary"
  }
}

/// Parse an Erlang atom string back to AppType.
/// Returns Temporary as the safe default for unrecognised values.
pub fn app_type_from_string(s: String) -> AppType {
  case s {
    "permanent" -> Permanent
    "transient" -> Transient
    _ -> Temporary
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn format_app_spec(app: AppSpec) -> String {
  "{"
  <> app.name
  <> ", \""
  <> app.version
  <> "\", "
  <> app_type_to_string(app.type_)
  <> "}"
}

fn format_instruction(instr: UpgradeInstruction) -> String {
  case instr {
    AddModule(m) -> "{add_module, " <> m <> "}"
    LoadModule(m) -> "{load_module, " <> m <> "}"
    UpdateModule(m) -> "{update, " <> m <> "}"
    DeleteModule(m) -> "{delete_module, " <> m <> "}"
    Restart(app) -> "{restart_application, " <> app <> "}"
  }
}

fn format_instruction_list(instrs: List(UpgradeInstruction)) -> String {
  "[" <> string.join(list.map(instrs, format_instruction), ", ") <> "]"
}
