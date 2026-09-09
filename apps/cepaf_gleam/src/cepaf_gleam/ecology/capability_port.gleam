//// =============================================================================
//// [C3I-SIL6-MSTS] UOS SUPER-AGENT CAPABILITY PORT -- HONEST BACKEND BOUNDARY
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ecology/capability_port</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////     <mesh-domain>Capability Dispatch, Backend Probing & Fail-Closed Evidence</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / FAIL-CLOSED</criticality>
////     <stamp-controls>
////       SC-HOLON-001, SC-TOOLCHAIN-INPROJECT-001, SC-PROVENANCE-001, SC-ZERO-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Invocation receipts bind input-sensitive computation, atomic ETS operations
//// or bounded inference to a holon's active mask. Discovery probes carry no
//// execution credit. Pure model evaluation states its limited scope; it never
//// issues a live lease, deploys a controller or grants admission. A timeout
//// outcome does not establish that an external effect rolled back.

import cepaf_gleam/ecology/capability_compute
import cepaf_gleam/ecology/super_agent.{type CapabilityMask}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/string

// =============================================================================
// 1. Outcome algebra
// =============================================================================

/// The result of asking a holon to actually use one of its capabilities.
pub type Outcome {
  /// The backend evaluated the request. Rejected model transitions are computed
  /// results too; detail states their verdict and the bounded scope.
  Engaged(capability: String, backend: String, evidence: String, detail: Json)
  /// The request was invalid, absent or failed. This is not a rollback receipt:
  /// an external timeout can have an unknown effect outcome.
  Unavailable(capability: String, reason: String)
  /// The holon's mask has this capability switched off. Not a failure: a choice.
  Masked(capability: String)
}

pub fn outcome_engaged(o: Outcome) -> Bool {
  case o {
    Engaged(..) -> True
    _ -> False
  }
}

pub fn outcome_to_json(o: Outcome) -> Json {
  case o {
    Engaged(c, b, e, d) ->
      json.object([
        #("capability", json.string(c)),
        #("status", json.string("engaged")),
        #("backend", json.string(b)),
        #("evidence", json.string(e)),
        #("detail", d),
      ])
    Unavailable(c, r) ->
      json.object([
        #("capability", json.string(c)),
        #("status", json.string("unavailable")),
        #("reason", json.string(r)),
      ])
    Masked(c) ->
      json.object([
        #("capability", json.string(c)),
        #("status", json.string("masked")),
      ])
  }
}

// =============================================================================
// 2. Backend availability -- probed, not declared
// =============================================================================

pub type Backend {
  /// Runs entirely on the BEAM in this process. Always reachable.
  InProcess(name: String)
  /// An in-project executable (SC-TOOLCHAIN-INPROJECT-001).
  Executable(name: String, path: String)
  /// A dynamically loaded NIF that reports its own load state.
  Nif(name: String)
  /// A network service gated on a credential.
  Network(name: String, credential_env: String)
  /// A client whose actual availability is established only by a request.
  Service(name: String)
}

pub fn backend_name(b: Backend) -> String {
  case b {
    InProcess(n) -> n
    Executable(n, _) -> n
    Nif(n) -> n
    Network(n, _) -> n
    Service(n) -> n
  }
}

/// Live probe of one backend. Never cached: a toolchain can be removed between
/// two ticks and the holon must notice.
pub fn probe(b: Backend) -> Result(String, String) {
  case b {
    InProcess("ets") ->
      case ffi_ets_probe() {
        True -> Ok("ets round-trip verified")
        False -> Error("ETS round-trip failed")
      }
    InProcess(n) -> Ok(n <> " in-process")
    Executable(n, path) ->
      case ffi_probe_executable(path) {
        True -> Ok(n <> " present at " <> path)
        False -> Error(n <> " absent at " <> path)
      }
    Nif(_) ->
      case ffi_km_nif_loaded() {
        True -> Ok("uos_km_nif loaded")
        False ->
          Error(
            "uos_km_nif not loaded (priv/uos_km_nif.so absent or ABI mismatch)",
          )
      }
    Network(n, env) ->
      case ffi_env_present(env) {
        True -> Ok(n <> " credential present in " <> env)
        False -> Error(n <> " credential absent: " <> env <> " unset")
      }
    Service(n) -> Error(n <> " availability requires an actual bounded request")
  }
}

/// The in-project toolchain paths (SC-TOOLCHAIN-INPROJECT-001). Resolved from
/// the running application's root so no machine path is baked into source.
pub fn toolchain(rel: String) -> String {
  ffi_uos_root() <> "/" <> rel
}

/// Binding of each of the 11 capabilities to the backend that actually performs it.
pub fn backend_for(capability: String) -> Result(Backend, String) {
  case capability {
    "fprime" -> Ok(InProcess("pure_fpp_interpreter"))
    "bayesian" -> Ok(InProcess("beta_conjugate"))
    "ets" -> Ok(InProcess("ets"))
    "stm" -> Ok(InProcess("two_lattice_transaction_model"))
    "ruliad" -> Ok(InProcess("multiway_rewriter"))
    "denotational" -> Ok(InProcess("pure_intent_valuation"))
    "algebraic_atlas" -> Ok(InProcess("finite_chart_atlas"))
    "rete_ul" -> Ok(InProcess("beam_salience_production_engine"))
    "formal_twin" -> Ok(InProcess("bounded_transaction_differential_twin"))
    "modular_max" -> Ok(Service("supervised_max_daemon"))
    "openrouter_free" -> Ok(Service("openrouter_free_policy_client"))
    other -> Error("unknown capability: " <> other)
  }
}

pub const all_capabilities: List(String) = [
  "fprime", "bayesian", "rete_ul", "ets", "stm", "modular_max",
  "openrouter_free", "ruliad", "formal_twin", "denotational", "algebraic_atlas",
]

/// Probe every capability. This is the holon's honest self-knowledge: what it
/// can actually do right now, as opposed to what it was declared to possess.
pub fn probe_all() -> List(#(String, Result(String, String))) {
  list.map(all_capabilities, fn(c) {
    case backend_for(c) {
      Error(e) -> #(c, Error(e))
      Ok(b) -> #(c, probe(b))
    }
  })
}

pub fn probe_report_json() -> Json {
  json.object([
    #("contract", json.string("SC-HOLON-001")),
    #("probed_live", json.bool(True)),
    #(
      "scope",
      json.string(
        "backend discovery only; service availability requires invocation; no execution credit",
      ),
    ),
    #(
      "capabilities",
      json.array(probe_all(), fn(pair) {
        let #(name, res) = pair
        case res {
          Ok(ev) ->
            json.object([
              #("capability", json.string(name)),
              #("available", json.bool(True)),
              #("evidence", json.string(ev)),
            ])
          Error(why) ->
            json.object([
              #("capability", json.string(name)),
              #("available", json.bool(False)),
              #("reason", json.string(why)),
            ])
        }
      }),
    ),
  ])
}

// =============================================================================
// 3. Mask gate
// =============================================================================

pub fn mask_allows(mask: CapabilityMask, capability: String) -> Bool {
  case capability {
    "fprime" -> mask.fprime
    "bayesian" -> mask.bayesian
    "rete_ul" -> mask.rete_ul
    "ets" -> mask.ets
    "stm" -> mask.stm
    "modular_max" -> mask.modular_max
    "openrouter_free" -> mask.openrouter_free
    "ruliad" -> mask.ruliad
    "formal_twin" -> mask.formal_twin
    "denotational" -> mask.denotational
    "algebraic_atlas" -> mask.algebraic_atlas
    _ -> False
  }
}

// =============================================================================
// 4. Invocation -- the honest replacement for counter-bumping
// =============================================================================

/// Invoke a capability for real.
///
/// Mask first, bounded input second, actual request third. Discovery probes
/// never count as execution and do not establish an external service result.
pub fn invoke(
  mask: CapabilityMask,
  capability: String,
  input: String,
) -> Outcome {
  case mask_allows(mask, capability) {
    False -> Masked(capability)
    True ->
      case string.byte_size(input) > 16_384 {
        True -> Unavailable(capability, "input exceeds 16384 bytes")
        False ->
          case backend_for(capability) {
            Error(e) -> Unavailable(capability, e)
            Ok(b) -> perform(capability, b, input)
          }
      }
  }
}

fn perform(capability: String, b: Backend, input: String) -> Outcome {
  case capability {
    "ets" -> external_outcome(capability, b, ffi_ets_request(input))
    "stm" -> {
      let decoder = {
        use operation <- decode.optional_field("operation", "", decode.string)
        decode.success(operation)
      }
      case json.parse(input, decoder) {
        Ok("compare_exchange") ->
          external_outcome(
            capability,
            InProcess("ets_single_key_compare_exchange"),
            ffi_ets_request(input),
          )
        Ok("") -> pure_outcome(capability, b, input)
        Ok(_) ->
          Unavailable(
            capability,
            "STM store operation supports compare_exchange only",
          )
        Error(_) -> Unavailable(capability, "invalid STM request schema")
      }
    }
    "modular_max" | "openrouter_free" ->
      external_outcome(capability, b, ffi_invoke_external(capability, input))
    _ -> pure_outcome(capability, b, input)
  }
}

fn pure_outcome(capability: String, b: Backend, input: String) -> Outcome {
  case capability_compute.run(capability, input) {
    Ok(computed) ->
      Engaged(capability, backend_name(b), computed.evidence, computed.detail)
    Error(reason) -> Unavailable(capability, reason)
  }
}

fn external_outcome(
  capability: String,
  b: Backend,
  result: Result(String, String),
) -> Outcome {
  case result {
    Error(reason) -> Unavailable(capability, reason)
    Ok(output) ->
      case json.parse(output, decode.dynamic) {
        Error(_) ->
          Unavailable(
            capability,
            "backend returned an invalid JSON receipt; effect outcome unknown",
          )
        Ok(_) ->
          Engaged(
            capability,
            backend_name(b),
            "bounded request returned a backend receipt",
            json.object([
              #("backend_result_json", json.string(output)),
            ]),
          )
      }
  }
}

/// Explicit bounded diagnostic inputs. Autonomous callers should replace these
/// with observations when available and label fixed diagnostic runs as such.
pub fn default_input(capability: String) -> String {
  case capability {
    "bayesian" -> "ok"
    "fprime" -> "{\"machine\":\"watchdog\",\"signals\":[\"heartbeat_tick\"]}"
    "rete_ul" ->
      "{\"domain\":\"ooda\",\"facts\":[{\"key\":\"drift_detected\",\"value\":\"false\"},{\"key\":\"missing_critical\",\"value\":\"false\"}]}"
    "ets" ->
      "{\"operation\":\"put\",\"namespace\":\"ecology-diagnostics\",\"key\":\"bounded-check\",\"value\":\"diagnostic\"}"
    "stm" | "formal_twin" ->
      "{\"version\":1,\"snapshot\":1,\"owner\":1,\"actor\":1,\"epoch\":1,\"token\":1,\"now\":0,\"expires\":10,\"value\":\"before\",\"write\":\"after\"}"
    "ruliad" ->
      "{\"seed\":\"a\",\"rules\":[{\"from\":\"a\",\"to\":\"ab\"},{\"from\":\"a\",\"to\":\"ba\"}],\"steps\":2}"
    "denotational" ->
      "{\"authority\":\"sa-plan\",\"target_drive_serial\":\"model-only\",\"criticality\":\"DAL-B\",\"add_topics\":[\"ecology/diagnostic\"]}"
    "algebraic_atlas" ->
      "{\"sections\":[{\"chart\":0,\"value\":\"bounded\"},{\"chart\":1,\"value\":\"bounded\"}],\"overlaps\":[{\"source\":0,\"target\":1,\"value\":\"bounded\"}],\"path\":[0,1,2]}"
    "modular_max" ->
      "{\"operation\":\"linear_softmax\",\"features\":[2.0,-1.0],\"weights\":[[1.0,0.0],[0.0,1.0]],\"bias\":[0.5,-0.5]}"
    "openrouter_free" ->
      "{\"model\":\"openrouter/free\",\"prompt\":\"Describe one bounded observation an autonomous supervisor should record.\",\"max_tokens\":128}"
    _ -> ""
  }
}

// =============================================================================
// 5. FFI -- honest probes and bounded execution
// =============================================================================

@external(erlang, "ecology_capability_ffi", "uos_root")
fn ffi_uos_root() -> String

@external(erlang, "ecology_capability_ffi", "probe_executable")
fn ffi_probe_executable(path: String) -> Bool

@external(erlang, "ecology_capability_ffi", "ets_backend_probe")
fn ffi_ets_probe() -> Bool

@external(erlang, "ecology_capability_ffi", "km_nif_loaded")
fn ffi_km_nif_loaded() -> Bool

@external(erlang, "ecology_capability_ffi", "env_present")
fn ffi_env_present(name: String) -> Bool

@external(erlang, "ecology_capability_ffi", "ets_request")
fn ffi_ets_request(input: String) -> Result(String, String)

@external(erlang, "ecology_capability_ffi", "invoke_external")
fn ffi_invoke_external(
  capability: String,
  input: String,
) -> Result(String, String)
