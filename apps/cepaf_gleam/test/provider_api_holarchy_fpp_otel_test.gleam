import cepaf_gleam/bridge/pi_session
import cepaf_gleam/harness/agent_ecology.{
  FailoverToLocalQwenOrDeepSeek, InjectBase64ThoughtSigWaiver, ProceedNominal,
  SynthesizeAbortedToolResult, TripPrajnaCircuitBreakerAndRetry,
  all_fractal_layers, all_sovereign_agent_capabilities, all_system_aspects,
  canonical_provider_api_fpp_registry, determine_provider_api_recovery_action,
  emit_provider_api_otel_fractal_span, expected_system_directory_kind_id,
  resolve_provider_api_recovery, select_supervisor_or_failover_with_agy,
  verify_provider_api_transition, verify_system_directory_object,
  verify_uos_service_mesh_binding,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn all_7_provider_apis_and_6_agents_17_aspects_10_layers_test() {
  let apis = canonical_provider_api_fpp_registry()
  list.length(apis) |> should.equal(7)

  let agents = all_sovereign_agent_capabilities()
  list.length(agents) |> should.equal(6)

  let layers = all_fractal_layers()
  list.length(layers) |> should.equal(10)

  let aspects = all_system_aspects()
  list.length(aspects) |> should.equal(17)
}

pub fn exhaustive_392_state_provider_api_transition_table_test() {
  let states = [0, 1, 2, 3, 4, 5, 6]
  let bools = [False, True]
  let total_verified =
    list.fold(states, 0, fn(acc_prev, prev_s) {
      list.fold(states, acc_prev, fn(acc_next, next_s) {
        list.fold(bools, acc_next, fn(acc_alt, req_alt) {
          list.fold(bools, acc_alt, fn(acc_prov, prov_ok) {
            list.fold(bools, acc_prov, fn(acc_cap, cap_ok) {
              let actual =
                verify_provider_api_transition(
                  prev_s,
                  next_s,
                  req_alt,
                  prov_ok,
                  cap_ok,
                )
              let expected = case cap_ok {
                False -> next_s == 6
                True ->
                  case next_s {
                    2 ->
                      prov_ok && { !req_alt || prev_s == 1 || prev_s == 3 }
                    3 -> prev_s == 2
                    5 -> prov_ok && { prev_s == 3 || prev_s == 1 }
                    _ -> True
                  }
              }
              should.equal(actual, expected)
              acc_cap + 1
            })
          })
        })
      })
    })
  total_verified |> should.equal(392)
}

pub fn resilient_error_recovery_and_failover_protocol_test() {
  // 1. OpenRouter HTTP 402 credit-cap breach -> FailoverToLocalQwenOrDeepSeek
  determine_provider_api_recovery_action(1, 2, False, True, False, 402)
  |> should.equal(FailoverToLocalQwenOrDeepSeek)

  // 2. Strict-alternation consecutive ToolCallEmitted -> SynthesizeAbortedToolResult
  determine_provider_api_recovery_action(2, 2, True, False, True, 400)
  |> should.equal(SynthesizeAbortedToolResult)

  // 3. Cross-model missing thoughtSignature -> InjectBase64ThoughtSigWaiver
  determine_provider_api_recovery_action(1, 2, True, False, True, 400)
  |> should.equal(InjectBase64ThoughtSigWaiver)

  // 4. Rate-limit HTTP 429 or transient 500/503 -> TripPrajnaCircuitBreakerAndRetry
  determine_provider_api_recovery_action(1, 2, False, True, True, 429)
  |> should.equal(TripPrajnaCircuitBreakerAndRetry)
  determine_provider_api_recovery_action(1, 2, False, True, True, 500)
  |> should.equal(TripPrajnaCircuitBreakerAndRetry)

  // 5. Nominal valid transition -> ProceedNominal
  determine_provider_api_recovery_action(1, 2, True, True, True, 200)
  |> should.equal(ProceedNominal)

  // 6. AGY & DeepSeek priority over Pi+OpenRouter+Gemini+Argon
  select_supervisor_or_failover_with_agy(
    True,
    True,
    True,
    True,
    True,
    True,
    True,
  )
  |> should.equal(Ok("agy"))
  select_supervisor_or_failover_with_agy(
    True,
    False,
    True,
    True,
    True,
    True,
    True,
  )
  |> should.equal(Ok("deepseek_v3_2"))
  select_supervisor_or_failover_with_agy(
    False,
    False,
    False,
    False,
    False,
    True,
    False,
  )
  |> should.equal(Ok("local_qwen"))
}

pub fn w3c_otel_fractal_span_and_pi_session_provenance_test() {
  let trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"
  let span_id = "00f067aa0ba902b7"
  string.length(trace_id) |> should.equal(32)
  string.length(span_id) |> should.equal(16)

  let span_json =
    emit_provider_api_otel_fractal_span(
      2,
      "pi",
      1,
      2,
      True,
      True,
      True,
      200,
      1420,
      trace_id,
      span_id,
    )
  string.contains(span_json, "\"trace_id\":\"4bf92f3577b34da6a3ce929d0e0e4736\"")
  |> should.be_true()
  string.contains(span_json, "\"span_id\":\"00f067aa0ba902b7\"")
  |> should.be_true()
  string.contains(span_json, "\"fractal_layer\":\"L7_SWARM_SESSION\"")
  |> should.be_true()
  string.contains(span_json, "\"aspects_covered\":17")
  |> should.be_true()
  string.contains(span_json, "\"transition_admissible\":true")
  |> should.be_true()

  // Verify pi_session thought-signature provenance & fold gate v2
  pi_session.verify_tool_call_provenance(True, False, True, False, True)
  |> should.be_false()
  pi_session.verify_tool_call_provenance(True, False, True, True, True)
  |> should.be_true()
  pi_session.should_fold_context_v2(85, 80, True)
  |> should.be_true()
  pi_session.should_fold_context_v2(85, 80, False)
  |> should.be_false()
}

pub fn exhaustive_64_state_provider_api_recovery_table_test() {
  let classes = [0, 1, 2, 3]
  let bools = [False, True]
  let total_recovery_states =
    list.fold(classes, 0, fn(acc_c, st) {
      list.fold(bools, acc_c, fn(acc_aff, aff) {
        list.fold(bools, acc_aff, fn(acc_alt, alt) {
          list.fold(bools, acc_alt, fn(acc_g, g_avail) {
            list.fold(bools, acc_g, fn(acc_q, q_avail) {
              let act =
                resolve_provider_api_recovery(st, aff, alt, g_avail, q_avail)
              // Total & bounded (0 <= act <= 6)
              should.be_true(act >= 0 && act <= 6)
              // Resilient non-halt guarantee: whenever g_avail or q_avail is True, act < 6
              case g_avail || q_avail {
                True -> should.be_true(act < 6)
                False -> Nil
              }
              acc_q + 1
            })
          })
        })
      })
    })
  total_recovery_states |> should.equal(64)
}

pub fn exhaustive_192_state_service_mesh_and_2080_state_system_directory_test() {
  let svc_ids = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  let bools = [False, True]
  let total_svc_states =
    list.fold(svc_ids, 0, fn(acc_s, s_id) {
      list.fold(bools, acc_s, fn(acc_f, fpp_ok) {
        list.fold(bools, acc_f, fn(acc_z, zen_ok) {
          list.fold(bools, acc_z, fn(acc_m, mcp_ok) {
            list.fold(bools, acc_m, fn(acc_c, cabi_ok) {
              let ok =
                verify_uos_service_mesh_binding(
                  s_id,
                  fpp_ok,
                  zen_ok,
                  mcp_ok,
                  cabi_ok,
                )
              let expected = fpp_ok && zen_ok && mcp_ok && cabi_ok
              ok |> should.equal(expected)
              acc_c + 1
            })
          })
        })
      })
    })
  total_svc_states |> should.equal(192)

  let dir_ids = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
    40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,
  ]
  let kind_ids = [0, 1, 2, 3, 4]
  let total_dir_states =
    list.fold(dir_ids, 0, fn(acc_d, d_id) {
      list.fold(kind_ids, acc_d, fn(acc_k, k_id) {
        list.fold(bools, acc_k, fn(acc_h, hol_ok) {
          list.fold(bools, acc_h, fn(acc_f, fzmo_ok) {
            list.fold(bools, acc_f, fn(acc_a, asp_ok) {
              let ok =
                verify_system_directory_object(
                  d_id,
                  k_id,
                  hol_ok,
                  fzmo_ok,
                  asp_ok,
                )
              let exp_kind = expected_system_directory_kind_id(d_id)
              let expected =
                k_id == exp_kind && hol_ok && fzmo_ok && asp_ok
              ok |> should.equal(expected)
              acc_a + 1
            })
          })
        })
      })
    })
  total_dir_states |> should.equal(2080)
}
