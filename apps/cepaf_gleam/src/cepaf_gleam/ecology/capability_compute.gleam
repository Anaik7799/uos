//// Real bounded pure computations behind the common ecology capability port.
//// Inputs describe model data, never runtime authority. No IO occurs here.
//// SC-HOLON-001, SC-PROVENANCE-001; #fractal-l2 #fractal-l5 #fractal-l8 #zero-muda

import cepaf_gleam/ecology/capability_twin as twin
import cepaf_gleam/ecology/multiway
import cepaf_gleam/fpp/domain
import cepaf_gleam/fpp/homeostasis_fprime as fprime
import cepaf_gleam/fpp/interp
import cepaf_gleam/intent/denotational
import cepaf_gleam/math/bayesian
import cepaf_gleam/math/rete
import cepaf_gleam/semantics/algebraic_atlas as atlas
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string

pub type Computation {
  Computation(evidence: String, detail: Json)
}

pub fn run(capability: String, input: String) -> Result(Computation, String) {
  case string.byte_size(input) > 16_384 {
    True -> Error("input exceeds 16384 bytes")
    False ->
      case capability {
        "bayesian" -> posterior(input)
        "fprime" -> state_machine(input)
        "rete_ul" -> production_rules(input)
        "stm" -> transaction(input, False)
        "formal_twin" -> transaction(input, True)
        "ruliad" -> rewrite(input)
        "denotational" -> intent(input)
        "algebraic_atlas" -> chart_gluing(input)
        _ -> Error("no pure computation for " <> capability)
      }
  }
}

fn parse(input: String, decoder: decode.Decoder(a)) -> Result(a, String) {
  json.parse(input, decoder)
  |> result.map_error(fn(_) { "invalid capability JSON schema" })
}

fn posterior(input: String) -> Result(Computation, String) {
  let tokens =
    input
    |> string.replace("\n", " ")
    |> string.replace("\t", " ")
    |> string.replace("\r", " ")
    |> string.split(" ")
    |> list.filter(fn(t) { t != "" })
  case
    list.is_empty(tokens)
    || list.length(tokens) > 2048
    || !list.all(tokens, fn(t) {
      list.contains(["ok", "pass", "fail", "error"], t)
    })
  {
    True ->
      Error("Bayesian observations require 1..2048 ok/pass/fail/error tokens")
    False -> {
      let distribution =
        list.fold(tokens, bayesian.beta_new(1.0, 1.0), fn(prior, token) {
          bayesian.beta_update(prior, token == "ok" || token == "pass")
        })
      let mean = bayesian.beta_mean(distribution)
      Ok(Computation(
        "posterior mean " <> float.to_string(mean),
        json.object([
          #("alpha", json.float(distribution.alpha)),
          #("beta", json.float(distribution.beta_param)),
          #("posterior_mean", json.float(mean)),
          #("observations", json.int(list.length(tokens))),
          #(
            "prior",
            json.string(
              "Beta(1,1) per request; caller supplies observation history",
            ),
          ),
        ]),
      ))
    }
  }
}

fn state_machine(input: String) -> Result(Computation, String) {
  let guard_decoder = {
    use name <- decode.field("name", decode.string)
    use holds <- decode.field("holds", decode.bool)
    decode.success(#(name, holds))
  }
  let decoder = {
    use name <- decode.field("machine", decode.string)
    use signals <- decode.field("signals", decode.list(decode.string))
    use guards <- decode.optional_field(
      "guards",
      [],
      decode.list(guard_decoder),
    )
    decode.success(#(name, signals, guards))
  }
  use request <- result.try(parse(input, decoder))
  let #(name, signals, guards) = request
  use machine <- result.try(case name {
    "ooda" -> Ok(fprime.ooda_swarm_fprime())
    "breaker" -> Ok(fprime.prajna_breaker_fprime())
    "watchdog" -> Ok(fprime.deadman_watchdog_fprime())
    "evolution" -> Ok(fprime.evolution_gate_fprime())
    "tolerance" -> Ok(fprime.tolerance_envelope_fprime())
    _ -> Error("unknown FPP machine")
  })
  let assert domain.InternalMachine(
    _,
    declared_signals,
    declared_guards,
    _,
    _,
    _,
    _,
  ) = machine
  case
    list.is_empty(signals)
    || list.length(signals) > 64
    || list.length(guards) > 32
    || !list.all(signals, fn(s) {
      list.any(declared_signals, fn(d) { d.signal_name == s })
    })
    || !list.all(guards, fn(g) { list.contains(declared_guards, g.0) })
    || list.length(list.unique(list.map(guards, fn(g) { g.0 })))
    != list.length(guards)
  {
    True ->
      Error(
        "FPP signals/guards outside declared model or bounds (1..64 signals, <=32 distinct guards)",
      )
    False -> {
      use initial <- result.try(interp.init_machine(machine))
      use final <- result.try(
        list.try_fold(signals, initial, fn(s, signal) {
          interp.dispatch_signal(machine, guards, s, signal)
        }),
      )
      Ok(Computation(
        "FPP " <> name <> ": " <> initial.current <> " -> " <> final.current,
        json.object([
          #("initial", json.string(initial.current)),
          #("final", json.string(final.current)),
          #("signals_evaluated", json.int(list.length(signals))),
          #("action_trace", json.array(final.log, json.string)),
          #(
            "scope",
            json.string(
              "pure FPP interpreter; action names recorded, no controller side effects or NASA certification",
            ),
          ),
        ]),
      ))
    }
  }
}

fn production_rules(input: String) -> Result(Computation, String) {
  let fact_decoder = {
    use key <- decode.field("key", decode.string)
    use value <- decode.field("value", decode.string)
    decode.success(#(key, value))
  }
  let decoder = {
    use name <- decode.field("domain", decode.string)
    use facts <- decode.field("facts", decode.list(fact_decoder))
    decode.success(#(name, facts))
  }
  use request <- result.try(parse(input, decoder))
  let #(name, facts) = request
  use selected <- result.try(case name {
    "ooda" -> Ok(rete.ooda_domain())
    "governor" -> Ok(rete.governor_domain())
    "symbiosis" -> Ok(rete.symbiosis_domain())
    "tensor" -> Ok(rete.tensor_domain())
    "perception" -> Ok(rete.perception_domain())
    "self_healing" -> Ok(rete.self_healing_domain())
    "swarm_coordination" -> Ok(rete.swarm_coordination_domain())
    "safety" -> Ok(rete.safety_domain())
    "knowledge" -> Ok(rete.knowledge_domain())
    "matrix" -> Ok(rete.matrix_domain())
    _ -> Error("unknown production-rule domain")
  })
  case
    list.is_empty(facts)
    || list.length(facts) > 64
    || list.length(list.unique(list.map(facts, fn(f) { f.0 })))
    != list.length(facts)
    || !list.all(facts, fn(f) {
      f.0 != "" && string.byte_size(f.0) <= 64 && string.byte_size(f.1) <= 256
    })
  {
    True ->
      Error(
        "working memory requires 1..64 unique facts, keys <=64 bytes, values <=256 bytes",
      )
    False -> {
      let memory =
        list.fold(facts, rete.memory_new(), fn(wm, f) {
          rete.memory_set(wm, f.0, f.1)
        })
      let #(_, fired) = rete.evaluate_domain(selected, memory)
      Ok(Computation(
        "production decision " <> fired.decision,
        json.object([
          #("decision", json.string(fired.decision)),
          #("rule", json.string(fired.rule_name)),
          #("salience", json.int(fired.salience)),
          #("facts_matched", json.int(fired.facts_matched)),
          #("rules_evaluated", json.int(list.length(selected.rules))),
          #("reason", json.string(fired.reason)),
          #("effect_authority", json.bool(False)),
          #(
            "scope",
            json.string(
              "pure BEAM salience production engine; no UL variable unification or forward closure",
            ),
          ),
        ]),
      ))
    }
  }
}

fn transaction(
  input: String,
  differential: Bool,
) -> Result(Computation, String) {
  let decoder = {
    use version <- decode.field("version", decode.int)
    use value <- decode.field("value", decode.string)
    use owner <- decode.field("owner", decode.int)
    use epoch <- decode.field("epoch", decode.int)
    use expires <- decode.field("expires", decode.int)
    use telemetry <- decode.optional_field("telemetry", 0, decode.int)
    use actor <- decode.field("actor", decode.int)
    use token <- decode.field("token", decode.int)
    use snapshot <- decode.field("snapshot", decode.int)
    use now <- decode.field("now", decode.int)
    use write <- decode.field("write", decode.string)
    decode.success(#(
      twin.Snapshot(version, value, owner, epoch, expires, telemetry),
      twin.Transaction(actor, token, snapshot, now, write),
    ))
  }
  use request <- result.try(parse(input, decoder))
  let #(before, tx) = request
  case
    string.byte_size(before.value) > 1024 || string.byte_size(tx.write) > 1024
  {
    True -> Error("STM model values exceed 1024 bytes")
    False -> {
      let verdict = twin.commit(before, tx)
      let after = result.unwrap(verdict, before)
      let observed = twin.observe(before)
      let matches = after == twin.reference(before, tx)
      let isolated =
        twin.Snapshot(..observed, telemetry: before.telemetry) == before
      let decision = case verdict {
        Ok(_) -> "committed"
        Error(r) -> twin.reject_name(r)
      }
      case differential && !{ matches && isolated } {
        True -> Error("runtime/reference twin disagreement")
        False ->
          Ok(Computation(
            case differential {
              True -> "bounded transaction twin agrees: " <> decision
              False -> "transaction model: " <> decision
            },
            json.object([
              #("decision", json.string(decision)),
              #("committed", json.bool(result.is_ok(verdict))),
              #("version", json.int(after.version)),
              #("value", json.string(after.value)),
              #("owner", json.int(after.owner)),
              #("epoch", json.int(after.epoch)),
              #("reference_agrees", json.bool(matches)),
              #("observation_noninterference", json.bool(isolated)),
              #(
                "scope",
                json.string(
                  "pure request-specific two-lattice model; no shared store or live lease; theorem checks separate",
                ),
              ),
              #("effect_authority", json.bool(False)),
            ]),
          ))
      }
    }
  }
}

fn rewrite(input: String) -> Result(Computation, String) {
  let rule_decoder = {
    use from <- decode.field("from", decode.string)
    use to <- decode.field("to", decode.string)
    decode.success(multiway.Rule(from, to))
  }
  let decoder = {
    use seed <- decode.field("seed", decode.string)
    use rules <- decode.field("rules", decode.list(rule_decoder))
    use steps <- decode.optional_field("steps", 1, decode.int)
    decode.success(#(seed, rules, steps))
  }
  use request <- result.try(
    case string.starts_with(string.trim_start(input), "{") {
      True -> parse(input, decoder)
      False -> {
        let tokens =
          input
          |> string.split(" ")
          |> list.filter(fn(t) { t != "" })
          |> list.unique
        Ok(#(input, list.map(tokens, fn(t) { multiway.Rule(t, t <> t) }), 1))
      }
    },
  )
  let #(seed, rules, steps) = request
  use graph <- result.try(multiway.explore(seed, rules, steps))
  Ok(Computation(
    "branchial width " <> int.to_string(list.length(graph.frontier)),
    json.object([
      #("steps", json.int(graph.steps)),
      #("branchial_width", json.int(list.length(graph.frontier))),
      #("states", json.array(graph.states, json.string)),
      #("successors", json.array(graph.frontier, json.string)),
      #(
        "edges",
        json.array(graph.edges, fn(e) {
          json.object([
            #("source", json.string(e.source)),
            #("target", json.string(e.target)),
            #("rule", json.int(e.rule)),
            #("offset", json.int(e.offset)),
          ])
        }),
      ),
      #(
        "scope",
        json.string(
          "finite supplied string-rewrite system within explicit bounds; not the total Ruliad",
        ),
      ),
    ]),
  ))
}

fn intent(input: String) -> Result(Computation, String) {
  let decoder = {
    use authority <- decode.field("authority", decode.string)
    use serial <- decode.field("target_drive_serial", decode.string)
    use criticality <- decode.optional_field(
      "criticality",
      "DAL-A",
      decode.string,
    )
    use approved <- decode.optional_field(
      "guardian_approved",
      False,
      decode.bool,
    )
    use delta <- decode.optional_field("delta_coord", 0.0, decode.float)
    use containers <- decode.optional_field(
      "add_containers",
      [],
      decode.list(decode.string),
    )
    use topics <- decode.optional_field(
      "add_topics",
      [],
      decode.list(decode.string),
    )
    use ev <- decode.optional_field("ev_cycle", 93, decode.int)
    decode.success(#(
      denotational.Intent(
        authority,
        serial,
        criticality,
        approved,
        delta,
        containers,
        topics,
      ),
      ev,
    ))
  }
  use request <- result.try(parse(input, decoder))
  let #(intent, ev) = request
  case
    list.length(intent.add_containers) > 64
    || list.length(intent.add_topics) > 64
    || ev < 0
  {
    True ->
      Error("denotational request exceeds bounds or has negative EV identifier")
    False -> {
      let state = case intent.delta_coord == 0.0 {
        False -> denotational.bottom("TRACE_COORDINATE_DRIFT")
        True ->
          denotational.evaluate_with_provenance(
            intent,
            denotational.initial_state(),
            ev,
          )
      }
      Ok(Computation(
        case state.is_bottom {
          True -> "denotational veto: " <> state.error_reason
          False -> "denotational value version " <> int.to_string(state.version)
        },
        json.object([
          #("is_bottom", json.bool(state.is_bottom)),
          #("reason", json.string(state.error_reason)),
          #("version", json.int(state.version)),
          #("trace_coords", json.array(state.trace_coords, json.float)),
          #("containers", json.array(state.active_containers, json.string)),
          #("topics", json.array(state.zenoh_topics, json.string)),
          #("effect_authority", json.bool(False)),
          #(
            "scope",
            json.string(
              "pure intent valuation from canonical baseline; no runtime mutation",
            ),
          ),
        ]),
      ))
    }
  }
}

fn chart_gluing(input: String) -> Result(Computation, String) {
  let section_decoder = {
    use chart <- decode.field("chart", decode.int)
    use value <- decode.field("value", decode.string)
    decode.success(#(chart, value))
  }
  let overlap_decoder = {
    use source <- decode.field("source", decode.int)
    use target <- decode.field("target", decode.int)
    use value <- decode.field("value", decode.string)
    decode.success(#(source, target, value))
  }
  let decoder = {
    use sections <- decode.field("sections", decode.list(section_decoder))
    use overlaps <- decode.field("overlaps", decode.list(overlap_decoder))
    use path <- decode.field("path", decode.list(decode.int))
    decode.success(#(sections, overlaps, path))
  }
  use request <- result.try(parse(input, decoder))
  let #(sections, overlaps, path) = request
  case
    list.is_empty(sections)
    || list.length(sections) > 10
    || list.length(overlaps) > 45
    || list.length(path) < 2
    || list.length(path) > 10
    || list.length(list.unique(list.map(sections, fn(s) { s.0 })))
    != list.length(sections)
  {
    True ->
      Error(
        "atlas bounds: 1..10 unique sections, <=45 overlaps, path of 2..10 charts",
      )
    False -> {
      use sections <- result.try(
        list.try_map(sections, fn(s) {
          use chart <- result.try(atlas.int_to_chart(s.0))
          Ok(#(chart, s.1))
        }),
      )
      use overlaps <- result.try(
        list.try_map(overlaps, fn(o) {
          use source <- result.try(atlas.int_to_chart(o.0))
          use target <- result.try(atlas.int_to_chart(o.1))
          Ok(#(source, target, o.2))
        }),
      )
      use charts <- result.try(list.try_map(path, atlas.int_to_chart))
      let assert [first, ..rest] = charts
      use composition <- result.try(
        list.try_fold(rest, atlas.identity_morphism(first), fn(m, target) {
          atlas.compose_morphisms(
            m,
            atlas.chart_transition_morphism(m.target_chart, target),
          )
        }),
      )
      let gluing = atlas.verify_sheaf_gluing(sections, overlaps)
      Ok(Computation(
        case gluing {
          Ok(_) -> "atlas overlap constraints satisfied"
          Error(_) -> "atlas overlap constraints rejected"
        },
        json.object([
          #("compatible", json.bool(result.is_ok(gluing))),
          #(
            "reason",
            json.string(case gluing {
              Ok(_) -> "all supplied overlaps agree"
              Error(e) -> e
            }),
          ),
          #("sections_checked", json.int(list.length(sections))),
          #("overlaps_checked", json.int(list.length(overlaps))),
          #("source", json.int(atlas.chart_to_int(composition.source_chart))),
          #("target", json.int(atlas.chart_to_int(composition.target_chart))),
          #("composition_compatible", json.bool(composition.is_compatible)),
          #(
            "scope",
            json.string(
              "finite L0..L9 chart composition and supplied overlap equality; no global sheaf completeness claim",
            ),
          ),
        ]),
      ))
    }
  }
}
