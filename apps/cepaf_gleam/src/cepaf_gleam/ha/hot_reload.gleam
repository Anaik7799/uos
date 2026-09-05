//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/hot_reload</module>
////     <fsharp-lineage>None — novel Gleam/BEAM infrastructure</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Zero-downtime bytecode upgrade via BEAM code server</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>CRITICAL</criticality>
////     <stamp-controls>SC-HA-001, SC-HA-002, SC-FUNC-001, SC-OODA-ACCEL-003</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Gleam types → Erlang code server API (code:load_file/1, code:soft_purge/1)
////       BEAM VM supports 2 module versions simultaneously (current + old)
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// BEAM Hot Code Reload for Zero-Downtime Evolution
//// अविनाशि तु तद्विद्धि येन सर्वमिदं ततम् — That which pervades all is indestructible (Gita 2.17)
////
//// PROTOCOL (प्रोतोकॉल):
////   1. `gleam build` — compile changed .gleam to .beam bytecode
////   2. `reload_changed()` — discover modules with different on-disk MD5
////   3. `soft_purge` — safely remove old version (only if no processes reference it)
////   4. `load_file` — load new .beam from code path
////   5. Verify — module_info accessible, exports unchanged
////
//// SAFETY (सुरक्षा):
////   - ALWAYS uses soft_purge (never hard purge which kills processes)
////   - Verifies MD5 changed before/after reload
////   - Falls back gracefully if old code still in use
////   - NIFs (.so files) are NOT hot-reloadable — server restart required for NIF changes
////
//// STAMP: SC-HA-001, SC-HA-002, SC-FUNC-001

/// Result of a hot reload operation
pub type ReloadResult {
  ReloadOk(module_name: String)
  ReloadFreshLoad(module_name: String)
  ReloadChanged(module_name: String, bytecode_changed: Bool)
  ReloadError(reason: String)
}

/// Reload a single Gleam module by name (e.g., "cepaf_gleam@ui@web@page_views")
/// Uses soft_purge for safety — will NOT kill running processes
pub fn reload_module(module_name: String) -> ReloadResult {
  case do_reload_module(module_name) {
    Ok(name) -> ReloadOk(name)
    Error(reason) -> ReloadError(reason)
  }
}

/// Reload all changed modules in the cepaf_gleam application
/// Discovers changes by comparing loaded MD5 with on-disk .beam MD5
/// This is the PRIMARY entry point for hot code upgrade
pub fn reload_changed() -> Result(String, String) {
  case do_reload_gleam_app() {
    Ok(msg) -> Ok(msg)
    Error(reason) -> Error(reason)
  }
}

/// Safe reload with pre/post verification checks
/// 1. Checks module is loaded
/// 2. Records current MD5
/// 3. Soft purges old code
/// 4. Loads new beam file
/// 5. Verifies MD5 changed
/// 6. Runs sanity check (module_info accessible)
pub fn safe_reload(module_name: String) -> ReloadResult {
  case do_safe_reload(module_name) {
    Ok(#("fresh_load", name)) -> ReloadFreshLoad(name)
    Ok(#("reloaded", name)) -> ReloadChanged(name, True)
    Ok(#(_, name)) -> ReloadOk(name)
    Error(reason) -> ReloadError(reason)
  }
}

/// Build and reload — runs `gleam build` then reloads changed modules
/// This is the FULL hot upgrade cycle
pub fn build_and_reload() -> Result(String, String) {
  case do_compile_and_reload("") {
    Ok(msg) -> Ok(msg)
    Error(reason) -> Error(reason)
  }
}

/// Get list of all loaded cepaf_gleam modules
pub fn list_loaded_modules() -> List(String) {
  do_get_loaded_modules()
}

/// Check if a specific module is loaded in the BEAM VM
pub fn is_loaded(module_name: String) -> Bool {
  do_is_module_loaded(module_name)
}

/// Get the MD5 checksum of a loaded module's bytecode
pub fn module_md5(module_name: String) -> String {
  do_get_module_md5(module_name)
}

/// Get the .beam file path for a module
pub fn beam_path(module_name: String) -> Result(String, String) {
  do_get_beam_path(module_name)
}

/// Get human-readable module info (exports count, path)
pub fn module_info(module_name: String) -> Result(String, String) {
  do_get_module_info(module_name)
}

// ---------------------------------------------------------------------------
// Erlang FFI bindings — hot_reload_ffi.erl
// ---------------------------------------------------------------------------

@external(erlang, "hot_reload_ffi", "reload_module")
fn do_reload_module(name: String) -> Result(String, String)

@external(erlang, "hot_reload_ffi", "reload_gleam_app")
fn do_reload_gleam_app() -> Result(String, String)

@external(erlang, "hot_reload_ffi", "safe_reload_with_check")
fn do_safe_reload(name: String) -> Result(#(String, String), String)

@external(erlang, "hot_reload_ffi", "compile_and_reload")
fn do_compile_and_reload(file: String) -> Result(String, String)

@external(erlang, "hot_reload_ffi", "get_loaded_modules")
fn do_get_loaded_modules() -> List(String)

@external(erlang, "hot_reload_ffi", "is_module_loaded")
fn do_is_module_loaded(name: String) -> Bool

@external(erlang, "hot_reload_ffi", "get_module_md5")
fn do_get_module_md5(name: String) -> String

@external(erlang, "hot_reload_ffi", "get_beam_path")
fn do_get_beam_path(name: String) -> Result(String, String)

@external(erlang, "hot_reload_ffi", "get_module_info")
fn do_get_module_info(name: String) -> Result(String, String)
