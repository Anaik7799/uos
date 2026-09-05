//// =============================================================================
//// [C3I-SIL6-MSTS] iam/pi_bridge — Pi runtime symbiosis bridge for IAM events
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/pi_bridge</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-PI-AUTO-001..008, SC-FERRISKEY-NIF-006</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// Bridges IAM audit events to/from the Pi-mono runtime (when active) so that
//// Claude / Pi agents observing the mesh can react to:
////   - signing_key.rotate / signing_key.purge_local (key lifecycle)
////   - gcp_sts.exchange / gcp_iam.policy_set (federation activity)
////   - scim.outbound.enqueue / scim.inbound.apply (provisioning)
////   - user.password_verify (auth events)
////
//// Mapping IAM audit topics ↔ AG-UI events ↔ Pi runtime hooks. The Zenoh
//// publish is the canonical transport (SC-ZMOF-001); this module declares
//// the typed mapping table and the per-event sensitivity classification.

pub type IamEventClass {
  /// L0 — auth/key/policy. Routed to Guardian for high-value alerts.
  Constitutional
  /// L7 — GCP federation activity. Routed to ops dashboard.
  Federation
  /// Routine — provisioning / queue drain. Counter only.
  Routine
}

pub type IamPiEvent {
  IamPiEvent(
    audit_action: String,
    zenoh_topic: String,
    agui_event_kind: String,
    pi_hook: String,
    class: IamEventClass,
    pii_scrubbed: Bool,
  )
}

/// Canonical mapping table — one row per audit event the Pi runtime cares
/// about. Mirrors the rule file's L6_ECOSYSTEM zenoh_topic helper but adds
/// the Pi-hook / AG-UI binding so the symbiosis is end-to-end typed.
pub fn event_table() -> List(IamPiEvent) {
  [
    IamPiEvent(
      audit_action: "signing_key.rotate",
      zenoh_topic: "indrajaal/l0/iam/jwks/rotate",
      agui_event_kind: "MetaEvent",
      pi_hook: "session_shutdown",
      class: Constitutional,
      pii_scrubbed: True,
    ),
    IamPiEvent(
      audit_action: "signing_key.purge_local",
      zenoh_topic: "indrajaal/l0/iam/jwks/purge",
      agui_event_kind: "Custom",
      pi_hook: "before_tool_call",
      class: Constitutional,
      pii_scrubbed: True,
    ),
    IamPiEvent(
      audit_action: "gcp_sts.exchange.ok",
      zenoh_topic: "indrajaal/l7/fed/gcp_sts/ok",
      agui_event_kind: "ToolCallResult",
      pi_hook: "after_provider_response",
      class: Federation,
      pii_scrubbed: True,
    ),
    IamPiEvent(
      audit_action: "gcp_iam.policy_set.ok",
      zenoh_topic: "indrajaal/l7/fed/gcp_iam/policy/set",
      agui_event_kind: "ToolCallResult",
      pi_hook: "after_tool_call",
      class: Constitutional,
      pii_scrubbed: True,
    ),
    IamPiEvent(
      audit_action: "gcp_iam.deny_policy.ok",
      zenoh_topic: "indrajaal/l7/fed/gcp_iam/deny/applied",
      agui_event_kind: "MetaEvent",
      pi_hook: "session_shutdown",
      class: Constitutional,
      pii_scrubbed: True,
    ),
    IamPiEvent(
      audit_action: "scim.outbound.enqueue",
      zenoh_topic: "indrajaal/l7/fed/scim/outbound/enqueue",
      agui_event_kind: "ActivityDelta",
      pi_hook: "after_provider_response",
      class: Routine,
      pii_scrubbed: True,
    ),
    IamPiEvent(
      audit_action: "scim.outbound.done",
      zenoh_topic: "indrajaal/l7/fed/scim/outbound/done",
      agui_event_kind: "ActivityDelta",
      pi_hook: "after_provider_response",
      class: Routine,
      pii_scrubbed: True,
    ),
    IamPiEvent(
      audit_action: "user.password_verify",
      zenoh_topic: "indrajaal/l0/iam/user/auth",
      agui_event_kind: "Custom",
      pi_hook: "before_tool_call",
      class: Constitutional,
      pii_scrubbed: True,
    ),
    IamPiEvent(
      audit_action: "user.create",
      zenoh_topic: "indrajaal/l0/iam/user/create",
      agui_event_kind: "ActivitySnapshot",
      pi_hook: "after_provider_response",
      class: Routine,
      pii_scrubbed: True,
    ),
    IamPiEvent(
      audit_action: "user.delete",
      zenoh_topic: "indrajaal/l0/iam/user/delete",
      agui_event_kind: "MetaEvent",
      pi_hook: "session_shutdown",
      class: Constitutional,
      pii_scrubbed: True,
    ),
  ]
}

/// Find an event by audit action — returns `Error(Nil)` for unknown actions
/// so the caller can choose to publish anyway with `Routine` defaults.
pub fn lookup(audit_action: String) -> Result(IamPiEvent, Nil) {
  do_find(audit_action, event_table())
}

fn do_find(needle: String, xs: List(IamPiEvent)) -> Result(IamPiEvent, Nil) {
  case xs {
    [] -> Error(Nil)
    [h, ..rest] ->
      case h.audit_action == needle {
        True -> Ok(h)
        False -> do_find(needle, rest)
      }
  }
}

pub fn event_count() -> Int {
  do_len(event_table())
}

fn do_len(xs: List(IamPiEvent)) -> Int {
  case xs {
    [] -> 0
    [_, ..rest] -> 1 + do_len(rest)
  }
}

/// Group events by class for SC-IAM-004 sensitivity policing.
pub fn count_by_class(class: IamEventClass) -> Int {
  do_count_class(event_table(), class, 0)
}

fn do_count_class(xs: List(IamPiEvent), c: IamEventClass, acc: Int) -> Int {
  case xs {
    [] -> acc
    [h, ..rest] ->
      case h.class == c {
        True -> do_count_class(rest, c, acc + 1)
        False -> do_count_class(rest, c, acc)
      }
  }
}
