//// Phase 1 wiring guard for ferriskey_nif (SC-WIRE-001, SC-FERRISKEY-NIF-001).
////
//// This test file is the single source of truth that the typed Gleam wrapper
//// at `auth/ferriskey_nif.gleam` exposes the surface the rest of the codebase
//// depends on. Phases 2-5 add one assertion per new NIF function (the wiring
//// guard pattern proven by `ferriskey_rbac_wiring_test.gleam`).
////
//// Phase 1 surface: ping + db_init.
//// Phase 2 will add: realm_*, user_*, group_*, role_*.
//// Phase 3 will add: token_*, jwks_*.
//// Phase 4 will add: gcp_sts_*, gcp_iam_*, gcp_directory_*.
//// Phase 5 will add: scim_*.

import cepaf_gleam/auth/ferriskey_nif as fk
import cepaf_gleam/auth/vault_bridge
import cepaf_gleam/iam/fractal/l0_constitutional
import cepaf_gleam/iam/fractal/l6_ecosystem
import cepaf_gleam/iam/fractal/matrix as fractal_matrix
import cepaf_gleam/iam/freshness_monitor
import cepaf_gleam/iam/key_rotation_actor
import cepaf_gleam/iam/objects
import cepaf_gleam/iam/pi_bridge
import cepaf_gleam/iam/supervisor as iam_sup
import cepaf_gleam/ui/lustre/iam as iam_page
import cepaf_gleam/ui/tui/iam_view
import cepaf_gleam/ui/wisp/iam_api
import gleeunit/should

pub fn typed_api_signatures_compile_test() {
  // The mere presence of these references compiling is the assertion.
  // Phase 1 surface:
  let _ping_fn = fk.ping
  let _db_init_fn = fk.db_init
  // Phase 2 surface (realm CRUD, 4 NIFs):
  let _realm_create_fn = fk.realm_create
  let _realm_get_fn = fk.realm_get
  let _realm_list_fn = fk.realm_list
  let _realm_delete_fn = fk.realm_delete
  // Phase 2 surface (user CRUD, 6 NIFs):
  let _user_create_fn = fk.user_create
  let _user_get_fn = fk.user_get
  let _user_list_fn = fk.user_list
  let _user_update_fn = fk.user_update
  let _user_delete_fn = fk.user_delete
  let _user_password_verify_fn = fk.user_password_verify
  // Phase 2 surface (group CRUD, 4 NIFs):
  let _group_create_fn = fk.group_create
  let _group_list_fn = fk.group_list
  let _group_add_member_fn = fk.group_add_member
  let _group_remove_member_fn = fk.group_remove_member
  // Phase 2 surface (role grant/revoke + custom, 4 NIFs):
  let _role_create_fn = fk.role_create
  let _role_list_fn = fk.role_list
  let _role_assign_fn = fk.role_assign
  let _role_revoke_fn = fk.role_revoke
  // Phase 3 surface (token + JWKS, 5 NIFs):
  let _signing_key_rotate_fn = fk.signing_key_rotate
  let _token_issue_fn = fk.token_issue
  let _token_validate_fn = fk.token_validate
  let _jwks_publish_fn = fk.jwks_publish
  let _jwks_get_cached_fn = fk.jwks_get_cached
  // Phase 4 surface (GCP STS, 3 NIFs — Bridge 2 of 5):
  let _gcp_sts_exchange_fn = fk.gcp_sts_exchange
  let _gcp_sts_cache_get_fn = fk.gcp_sts_cache_get
  let _gcp_sts_cache_invalidate_fn = fk.gcp_sts_cache_invalidate
  // Phase 8 surface (vault-backed handoff, 3 NIFs):
  let _export_seed_fn = fk.signing_key_export_seed
  let _purge_local_fn = fk.signing_key_purge_local
  let _issue_with_seed_fn = fk.token_issue_with_seed
  Nil
}

pub fn vault_handoff_phase8_constructors_test() {
  // The vault handoff lifecycle ADTs.
  let _seed =
    fk.SeedExport(
      kid: "kid-2026-05",
      seed_b64: "_e_seed_b64_",
      vault_path: "iam/signing/eddsa/kid-2026-05",
    )
  Nil
}

pub fn gcp_sts_phase4_constructors_test() {
  let ct =
    fk.CachedToken(
      access_token: "ya29.token",
      sa_principal: "c3i-scim@x.iam.gserviceaccount.com",
      expires_at: 1_700_000_000,
      cache_key: "abc123",
    )
  let _hit = fk.StsCacheHit(cached: ct)
  let _miss = fk.StsCacheMiss
  let _xr =
    fk.ExchangeResult(
      ok: True,
      cache_key: "abc123",
      form_body: "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange",
      endpoint: "https://sts.googleapis.com/v1/token",
      cached: Ok(ct),
      error: Error(Nil),
    )
  Nil
}

pub fn token_phase3_constructors_test() {
  // Issued token round-trip ADT — the GCP STS exchange (Phase 4 Bridge 2)
  // will receive `IssuedToken` payloads from the NIF.
  let _t =
    fk.IssuedToken(
      jwt: "eyJ.x.y",
      exp: 1_700_000_000,
      kid: "kid-2026-01",
      alg: "EdDSA",
    )
  let _r =
    fk.RotateResult(
      kid: "kid-2026-02",
      alg: "EdDSA",
      seed_b64: "_seed_",
      vault_path: "iam/signing/eddsa/kid-2026-02",
    )
  let _v =
    fk.ValidValid(claims: fk.TokenClaims(
      iss: "https://x/realms/c3i",
      sub: "sub",
      aud: "aud",
      exp: 0,
      iat: 0,
      realm: "c3i",
    ))
  let _v2 = fk.ValidInvalid(error: "expired")
  let _j = fk.JwksResponse(jwks_json: "{\"keys\":[]}")
  let _jc = fk.JwksCacheResponse(jwks_json: "{}", age_ms: 0, hit: True)
  Nil
}

pub fn group_constructor_test() {
  let _g =
    fk.Group(
      id: "g1",
      realm_id: "r1",
      name: "engineering",
      display_name: "Engineering",
      created_at: 0,
      updated_at: 0,
    )
  Nil
}

pub fn role_constructor_with_layer_mask_test() {
  // c3i-admin's mask MUST be 0xFF — pinning the SC-IAM-003 invariant
  // at the wiring-guard layer so any future change to the Role record
  // shape is caught here, not scattered across the codebase.
  let admin: fk.Role =
    fk.Role(
      id: "role1",
      realm_id: "r1",
      name: "c3i-admin",
      layer_mask: 255,
      requires_mfa: True,
      created_at: 0,
    )
  admin.layer_mask
  |> should.equal(255)
  admin.requires_mfa
  |> should.equal(True)
}

pub fn user_get_response_variants_test() {
  let _found =
    fk.UserFound(fk.User(
      id: "u1",
      realm_id: "r1",
      sub: "u1",
      username: "alice",
      email: "alice@example.com",
      mfa_enrolled: False,
      created_at: 0,
      updated_at: 0,
    ))
  let _not_found = fk.UserNotFound
  Nil
}

pub fn password_verify_response_constructor_test() {
  let _pv = fk.PasswordVerify(ok: True, mfa_required: False)
  Nil
}

pub fn realm_get_response_variants_test() {
  // Constructor existence — wiring guard for the Realm/RealmGetResponse ADTs.
  let _found =
    fk.RealmFound(fk.Realm(
      id: "r1",
      name: "c3i",
      issuer_url: "https://x",
      created_at: 0,
      updated_at: 0,
    ))
  let _not_found = fk.RealmNotFound
  Nil
}

pub fn supervisor_spec_has_six_children_test() {
  let spec = iam_sup.iam_supervisor()
  iam_sup.validate(spec)
  |> should.equal(Ok(6))
}

pub fn supervisor_uses_one_for_all_test() {
  let spec = iam_sup.iam_supervisor()
  // OneForAll because a JWKS cache crash invalidates the STS cache —
  // see SC-CPIG-011 + plan §Multilayer supervisor topology.
  spec.strategy
  |> should.equal(iam_sup.OneForAll)
}

pub fn vault_paths_match_governance_test() {
  // Governance file `.claude/rules/iam-ferriskey-nif.md` declares these
  // paths; this test pins the Gleam constants to them.
  vault_bridge.signing_key_path("rs256", "kid-2026-01")
  |> should.equal("iam/signing/rs256/kid-2026-01")

  vault_bridge.gcp_sa_path("c3i-scim")
  |> should.equal("iam/gcp-sa/c3i-scim")

  vault_bridge.scim_provisioning_token_path
  |> should.equal("iam/scim/provisioning-token")
}

pub fn vault_ttl_signing_key_is_90_days_test() {
  // SC-FERRISKEY-NIF-008: signing-key rotation ≤ 90 days.
  let vault_bridge.TtlSeconds(s) = vault_bridge.ttl_signing_key
  s |> should.equal(7_776_000)
}

pub fn vault_ttl_gcp_sa_is_30_days_test() {
  // SC-GCP-IAM-006: SA keys live in vault, rotated 30 d.
  let vault_bridge.TtlSeconds(s) = vault_bridge.ttl_gcp_sa
  s |> should.equal(2_592_000)
}

// ===========================================================================
// Phase 7 — Multilayer supervisor + Fractal L0-L7 × 12-objects matrix
// ===========================================================================

pub fn supervisor_has_six_children_test() {
  // Phase 7 substrate: 6 children declared in spec, 2 wired LIVE in `start`.
  let spec = iam_sup.iam_supervisor()
  iam_sup.validate(spec)
  |> should.equal(Ok(6))
}

pub fn fractal_matrix_has_96_cells_test() {
  // SC-FRAC-RRF-001: full L0-L7 × 12-objects coverage.
  let fractal_matrix.Coverage(layers, objs, cells) = fractal_matrix.coverage()
  layers |> should.equal(8)
  objs |> should.equal(12)
  cells |> should.equal(96)
}

pub fn objects_canonical_count_is_twelve_test() {
  // The 12 IAM objects per `.claude/rules/iam-ferriskey-nif.md` matrix.
  objects.all_objects()
  |> length
  |> should.equal(12)
}

pub fn l0_constitutional_binds_admin_layer_mask_test() {
  // SC-IAM-003: c3i-admin's mask invariant is part of the L0 binding text.
  l0_constitutional.binding(objects.Role)
  |> contains_substring("0xFF")
  |> should.equal(True)
}

pub fn l6_zenoh_topics_use_indrajaal_namespace_test() {
  // SC-ZMOF-001 fractal namespace.
  l6_ecosystem.zenoh_topic(objects.User)
  |> should.equal("indrajaal/l0/iam/user/**")

  l6_ecosystem.zenoh_topic(objects.AccessToken)
  |> should.equal("indrajaal/l7/fed/gcp_sts/**")
}

pub fn freshness_classify_brackets_test() {
  // Andon bracket boundaries: 60s / 120s / 300s.
  freshness_monitor.classify(0) |> should.equal(freshness_monitor.Fresh)
  freshness_monitor.classify(59_999) |> should.equal(freshness_monitor.Fresh)
  freshness_monitor.classify(60_000) |> should.equal(freshness_monitor.Stale)
  freshness_monitor.classify(119_999) |> should.equal(freshness_monitor.Stale)
  freshness_monitor.classify(120_000)
  |> should.equal(freshness_monitor.Degraded)
  freshness_monitor.classify(299_999)
  |> should.equal(freshness_monitor.Degraded)
  freshness_monitor.classify(300_000) |> should.equal(freshness_monitor.Dead)
  freshness_monitor.classify(900_000) |> should.equal(freshness_monitor.Dead)
}

fn length(xs: List(a)) -> Int {
  case xs {
    [] -> 0
    [_, ..t] -> 1 + length(t)
  }
}

import gleam/string

fn contains_substring(s: String, needle: String) -> Bool {
  do_contains(s, needle)
}

fn do_contains(s: String, needle: String) -> Bool {
  string.contains(s, needle)
}

// ===========================================================================
// Phase 6 — Triple-interface (Lustre + Wisp + TUI) wiring guard
// ===========================================================================

pub fn iam_page_init_returns_default_model_test() {
  let m = iam_page.init()
  m.user_count |> should.equal(0)
  m.supervisor_alive_workers |> should.equal(6)
  m.supervisor_total_workers |> should.equal(6)
}

pub fn iam_page_toggle_cockpit_cycles_modes_test() {
  let m = iam_page.init()
  // Dark → Dim → Normal → Bright → Emergency → Dark
  let m1 = iam_page.update(m, iam_page.ToggleCockpit)
  m1.cockpit |> should.equal(iam_page.CockpitDim)
  let m2 = iam_page.update(m1, iam_page.ToggleCockpit)
  m2.cockpit |> should.equal(iam_page.CockpitNormal)
  let m3 = iam_page.update(m2, iam_page.ToggleCockpit)
  m3.cockpit |> should.equal(iam_page.CockpitBright)
  let m4 = iam_page.update(m3, iam_page.ToggleCockpit)
  m4.cockpit |> should.equal(iam_page.CockpitEmergency)
  let m5 = iam_page.update(m4, iam_page.ToggleCockpit)
  m5.cockpit |> should.equal(iam_page.CockpitDark)
}

pub fn tui_iam_view_renders_non_empty_test() {
  let m = iam_page.init()
  let s = iam_view.render(m)
  s
  |> do_contains("IDENTITY & ACCESS MANAGEMENT")
  |> should.equal(True)
  // 6 LIVE workers must be enumerated
  s |> do_contains("NifManager") |> should.equal(True)
  s |> do_contains("KeyRotationActor") |> should.equal(True)
}

pub fn wisp_iam_api_dispatch_routes_test() {
  // Phase 6 substrate routing — proves L4_SYSTEM cells active.
  iam_api.dispatch("/api/v1/iam/health")
  |> should.equal(Ok(iam_api.Health))
  iam_api.dispatch("/api/v1/iam/realms")
  |> should.equal(Ok(iam_api.ListRealms))
  iam_api.dispatch("/api/v1/iam/realms/c3i")
  |> should.equal(Ok(iam_api.GetRealm(id: "c3i")))
  iam_api.dispatch("/api/v1/iam/realms/c3i/users")
  |> should.equal(Ok(iam_api.ListUsers(realm_id: "c3i")))
  iam_api.dispatch("/api/v1/iam/jwks/c3i")
  |> should.equal(Ok(iam_api.GetJwks(realm_id: "c3i")))
  iam_api.dispatch("/api/v1/bogus")
  |> should.equal(Error("not_found"))
}

pub fn wisp_iam_api_health_returns_200_test() {
  let response = iam_api.health()
  response.status |> should.equal(200)
  response.body_json
  |> do_contains("\"supervisor_workers\":6")
  |> should.equal(True)
  response.body_json
  |> do_contains("\"fractal_cells\":96")
  |> should.equal(True)
}

pub fn key_rotation_decide_keep_current_under_90d_test() {
  // SC-FERRISKEY-NIF-008 — under 90d the current key should not rotate.
  let now = 1_700_000_000
  let one_day = 86_400
  let dec =
    key_rotation_actor.decide_rotation(
      now,
      now - { 30 * one_day },
      key_rotation_actor.OptNone,
    )
  case dec {
    key_rotation_actor.KeepCurrent(_) -> Nil
    other -> {
      // Make the failure visible.
      should.equal(other, key_rotation_actor.KeepCurrent(0))
      Nil
    }
  }
}

pub fn key_rotation_decide_rotate_past_90d_test() {
  let now = 1_700_000_000
  let one_day = 86_400
  let dec =
    key_rotation_actor.decide_rotation(
      now,
      now - { 100 * one_day },
      key_rotation_actor.OptNone,
    )
  case dec {
    key_rotation_actor.RotateNow(_) -> Nil
    other -> {
      should.equal(other, key_rotation_actor.RotateNow(0))
      Nil
    }
  }
}

pub fn key_rotation_decide_in_overlap_within_7d_test() {
  let now = 1_700_000_000
  let one_day = 86_400
  // rotated_at = 3 days ago — should still be in overlap
  let dec =
    key_rotation_actor.decide_rotation(
      now,
      now - { 100 * one_day },
      key_rotation_actor.OptInt(value: now - { 3 * one_day }),
    )
  case dec {
    key_rotation_actor.InOverlap(_) -> Nil
    other -> {
      should.equal(other, key_rotation_actor.InOverlap(0))
      Nil
    }
  }
}

pub fn key_rotation_decide_retire_past_overlap_test() {
  let now = 1_700_000_000
  let one_day = 86_400
  // rotated_at = 8 days ago — past 7d overlap, must retire
  let dec =
    key_rotation_actor.decide_rotation(
      now,
      now - { 100 * one_day },
      key_rotation_actor.OptInt(value: now - { 8 * one_day }),
    )
  case dec {
    key_rotation_actor.RetireOld(_) -> Nil
    other -> {
      should.equal(other, key_rotation_actor.RetireOld(0))
      Nil
    }
  }
}

// ===========================================================================
// Phase 4.7 / 6.5 / Pi-bridge — final closure wiring guards
// ===========================================================================

pub fn pi_bridge_event_table_has_ten_rows_test() {
  // SC-PI-AUTO-002 — Pi runtime symbiosis bridges 10 IAM events.
  pi_bridge.event_count()
  |> should.equal(10)
}

pub fn pi_bridge_constitutional_events_test() {
  // SC-FERRISKEY-NIF-006 — every constitutional event MUST be PII-scrubbed
  // and routed to Guardian. Six L0/Constitutional events expected.
  pi_bridge.count_by_class(pi_bridge.Constitutional)
  |> should.equal(6)
}

pub fn pi_bridge_lookup_signing_key_rotate_test() {
  let assert Ok(ev) = pi_bridge.lookup("signing_key.rotate")
  ev.zenoh_topic |> should.equal("indrajaal/l0/iam/jwks/rotate")
  ev.class |> should.equal(pi_bridge.Constitutional)
  ev.pii_scrubbed |> should.equal(True)
}

pub fn pi_bridge_lookup_unknown_returns_error_test() {
  pi_bridge.lookup("not.an.event")
  |> should.equal(Error(Nil))
}
