//// UOS-CORE-EVO: Fully Functional Holonic Hive Operations Algebra
//// (`SC-HARNESS-MCP-001`, `SC-JIDOKA-001`, `SC-TMR-001`, `#fractal-l0..l9`)
////
//// Implements a Zero-Muda, pure-functional 5-Caste Holonic Hive Engine:
//// 1. `QueenConductor` (`AGY`): < 2% token burn, wave admission & <= 512 B digests.
//// 2. `ForagerBuilder` (`Pi + DeepSeek Flash`): high-throughput parallel TDD/dev.
//// 3. `NurseDiagnostician` (`Pi + DeepSeek Pro`): Attempt-2 ACH RCA & Poka-Yoke healing.
//// 4. `ArchitectSynthesizer` (`Pi + Argon`): STPA/FMEA wrong-path TPS redesign & journals.
//// 5. `SovereignSentinel` (`Codex`): 2oo3 constitutional quorum, Gate W1.5 & W2 cutover audit.
////
//// Coordinates stigmergically via signed Zenoh pheromone trails (`uos/v1/hive/**`)
//// with half-life decay, Heijunka leveled WIP pull-queues, and 2oo3 quorum voting.

import cepaf_gleam/ecology/core_evolution.{
  type Engine, type QuotaSnapshot, AgyThinConductor, CodexCli, PiArgonGoogle,
  PiDeepSeekFlash, PiDeepSeekPro, QuotaAdmitted, QuotaHoldMargin40Pct,
  ZeroOpenRouterAndBatchedWakeups, ZeroOpenRouterShift,
}
import cepaf_gleam/zenoh/safety.{
  type TmrChannel, ChannelA, ChannelB, ChannelC, Disagreement, Majority,
  Unanimous,
}
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/string

pub type HiveCaste {
  QueenConductor
  ForagerBuilder
  NurseDiagnostician
  ArchitectSynthesizer
  SovereignSentinel
}

pub fn caste_name(caste: HiveCaste) -> String {
  case caste {
    QueenConductor -> "queen_conductor"
    ForagerBuilder -> "forager_builder"
    NurseDiagnostician -> "nurse_diagnostician"
    ArchitectSynthesizer -> "architect_synthesizer"
    SovereignSentinel -> "sovereign_sentinel"
  }
}

/// Bind each Hive caste to its optimal engine under live 40%-margin quota mode.
pub fn caste_engine(caste: HiveCaste, quota: QuotaSnapshot) -> Result(Engine, String) {
  case core_evolution.evaluate_quota_margin(quota) {
    QuotaHoldMargin40Pct(violated) ->
      Error("HOLD_MARGIN_40PCT:" <> string.join(violated, ","))
    QuotaAdmitted(mode, _, _) -> {
      let zero_or = case mode {
        ZeroOpenRouterShift | ZeroOpenRouterAndBatchedWakeups -> True
        _ -> False
      }
      case caste, zero_or {
        QueenConductor, _ -> Ok(AgyThinConductor)
        SovereignSentinel, _ -> Ok(CodexCli)
        ArchitectSynthesizer, _ -> Ok(PiArgonGoogle)
        ForagerBuilder, False -> Ok(PiDeepSeekFlash)
        ForagerBuilder, True -> Ok(PiArgonGoogle)
        NurseDiagnostician, False -> Ok(PiDeepSeekPro)
        NurseDiagnostician, True -> Ok(PiArgonGoogle)
      }
    }
  }
}

/// Heijunka leveled WIP limits per caste (prevents stampede, `/tmp` exhaustion,
/// and SQLite lock contention while saturating disjoint Jujutsu sibling workspaces).
pub fn caste_wip_limit(caste: HiveCaste) -> Int {
  case caste {
    QueenConductor -> 1
    ForagerBuilder -> 4
    NurseDiagnostician -> 2
    ArchitectSynthesizer -> 2
    SovereignSentinel -> 2
  }
}

pub type PheromoneKind {
  TrailSuccess
  TrailHazardWarning
  TrailCorruptionQuarantine
  TrailReadyPull
}

/// Stigmergic Zenoh pheromone signal (`uos/v1/hive/pheromone/{cell}`) measured
/// in integer basis points (`0..10_000`) for deterministic, float-drift-free decay.
pub type PheromoneSignal {
  PheromoneSignal(
    cell_id: String,
    kind: PheromoneKind,
    intensity_bps: Int,
    emitted_at_s: Int,
    half_life_s: Int,
  )
}

/// Pure integer half-life decay: after `k` full half-lives, intensity decays by
/// `2^k` (bounded monotonically in `[0, intensity_bps]`).
pub fn decayed_intensity_bps(signal: PheromoneSignal, now_s: Int) -> Int {
  case signal.intensity_bps <= 0 || signal.half_life_s <= 0 || now_s <= signal.emitted_at_s {
    True -> int.max(0, signal.intensity_bps)
    False -> {
      let elapsed = now_s - signal.emitted_at_s
      let half_lives = int.min(16, elapsed / signal.half_life_s)
      div_pow2(signal.intensity_bps, half_lives)
    }
  }
}

pub type HiveCellTask {
  HiveCellTask(
    task_id: String,
    caste: HiveCaste,
    priority_score: Int,
    disjoint_workspace: Bool,
    deps_ready: Bool,
  )
}

pub type HeijunkaPullSchedule {
  HeijunkaPullSchedule(
    admitted_tasks: List(#(HiveCellTask, Engine)),
    deferred_wip_tasks: List(String),
    blocked_tasks: List(String),
  )
}

/// Deterministic Heijunka leveled pull-queue scheduler:
/// 1. Filters out tasks with unmet dependencies or overlapping file locks.
/// 2. Vetoes cells marked with active `TrailCorruptionQuarantine` pheromones (`>= 1000` bps).
/// 3. Sorts by descending risk/priority score (+ `TrailReadyPull` boost) and caps
///    each caste strictly at `caste_wip_limit(caste)`.
pub fn schedule_heijunka_wave(
  candidates: List(HiveCellTask),
  pheromones: List(PheromoneSignal),
  active_by_caste: List(#(HiveCaste, Int)),
  quota: QuotaSnapshot,
  now_s: Int,
) -> Result(HeijunkaPullSchedule, String) {
  case core_evolution.evaluate_quota_margin(quota) {
    QuotaHoldMargin40Pct(violated) ->
      Error("HOLD_HIVE_MARGIN_40PCT:" <> string.join(violated, ","))
    QuotaAdmitted(_, _, _) -> {
      let quarantined_cells =
        pheromones
        |> list.filter(fn(p) {
          case p.kind {
            TrailCorruptionQuarantine -> decayed_intensity_bps(p, now_s) >= 1000
            _ -> False
          }
        })
        |> list.map(fn(p) { p.cell_id })

      let #(eligible, blocked) =
        list.partition(candidates, fn(t) {
          t.deps_ready
          && t.disjoint_workspace
          && !list.contains(quarantined_cells, t.task_id)
        })

      let ranked =
        list.sort(eligible, fn(a, b) {
          int.compare(
            effective_score(b, pheromones, now_s),
            effective_score(a, pheromones, now_s),
          )
        })

      let initial_counts = dict.from_list(active_by_caste)
      let #(_, admitted_rev, deferred_rev) =
        list.fold(ranked, #(initial_counts, [], []), fn(acc, task) {
          let #(counts, adm, def) = acc
          let cur = case dict.get(counts, task.caste) {
            Ok(n) -> n
            Error(_) -> 0
          }
          let limit = caste_wip_limit(task.caste)
          case cur < limit, caste_engine(task.caste, quota) {
            True, Ok(eng) -> #(
              dict.insert(counts, task.caste, cur + 1),
              [#(task, eng), ..adm],
              def,
            )
            _, _ -> #(counts, adm, [task.task_id, ..def])
          }
        })

      Ok(HeijunkaPullSchedule(
        admitted_tasks: list.reverse(admitted_rev),
        deferred_wip_tasks: list.reverse(deferred_rev),
        blocked_tasks: list.map(blocked, fn(t) { t.task_id }),
      ))
    }
  }
}

pub type HiveQuorumVerdict {
  QuorumAdmittedUnanimous(digest: String)
  QuorumAdmitted2oo3(digest: String, dissenter: TmrChannel)
  QuorumAdmitted2oo4(digest: String, approving_models: Int)
  QuorumFailClosedHold(reason: String)
}

/// Generalized 2-of-4 Model Families + Operator Ratification Quorum
/// (`SC-PROVENANCE-001`): any 2 distinct model families out of
/// `{Codex, AGY, Claude, Pi+OpenRouter+Gemini+Argon}` agreeing on a non-empty,
/// non-`HOLD` candidate digest, plus mandatory `operator_approved == True`.
pub fn evaluate_two_of_four_model_quorum(
  codex_digest: String,
  agy_digest: String,
  claude_digest: String,
  pi_argon_digest: String,
  operator_approved: Bool,
) -> HiveQuorumVerdict {
  let raw_digests = [codex_digest, agy_digest, claude_digest, pi_argon_digest]
  let any_explicit_hold = list.any(raw_digests, fn(d) { d == "HOLD" })
  case !operator_approved, any_explicit_hold {
    True, _ -> QuorumFailClosedHold("operator_ratification_missing")
    _, True -> QuorumFailClosedHold("sovereign_model_explicit_hold")
    False, False -> {
      let valid_digests =
        list.filter(raw_digests, fn(d) { d != "" && d != "HOLD" })
      let matching =
        list.find_map(valid_digests, fn(candidate) {
          let count = list.count(valid_digests, fn(d) { d == candidate })
          case count >= 2 {
            True -> Ok(#(candidate, count))
            False -> Error(Nil)
          }
        })
      case matching {
        Ok(#(agreed_digest, 4)) -> QuorumAdmittedUnanimous(agreed_digest)
        Ok(#(agreed_digest, count)) -> QuorumAdmitted2oo4(agreed_digest, count)
        Error(Nil) ->
          QuorumFailClosedHold("quorum_fewer_than_2_of_4_models_agree")
      }
    }
  }
}

/// 2oo3 Tri-Sovereign Hive Quorum (`QueenConductor`/`AGY`, `SovereignSentinel`/`Codex`,
/// `ArchitectSynthesizer`/`Pi+Argon`) using `cepaf_gleam/zenoh/safety.vote`.
pub fn evaluate_sovereign_quorum(
  queen_digest: String,
  sentinel_digest: String,
  architect_digest: String,
) -> HiveQuorumVerdict {
  case
    queen_digest == ""
    || sentinel_digest == ""
    || architect_digest == ""
    || queen_digest == "HOLD"
    || sentinel_digest == "HOLD"
  {
    // Fail closed if either Sovereign authority (AGY or Codex) explicitly votes HOLD
    True -> QuorumFailClosedHold("sovereign_hold_or_empty_vote")
    False -> {
      let votes =
        dict.from_list([
          #(ChannelA, queen_digest),
          #(ChannelB, sentinel_digest),
          #(ChannelC, architect_digest),
        ])
      case safety.vote(votes) {
        Unanimous(d) -> QuorumAdmittedUnanimous(d)
        Majority(d, dissenter) -> QuorumAdmitted2oo3(d, dissenter)
        Disagreement(_) -> QuorumFailClosedHold("quorum_3way_disagreement")
      }
    }
  }
}

pub fn encode_hive_status_json(schedule: HeijunkaPullSchedule) -> String {
  json.object([
    #("schema", json.string("uos.core_evo.hive.v1")),
    #(
      "admitted",
      json.array(schedule.admitted_tasks, fn(pair) {
        let #(task, eng) = pair
        json.object([
          #("task_id", json.string(task.task_id)),
          #("caste", json.string(caste_name(task.caste))),
          #("engine", json.string(core_evolution.engine_id(eng))),
        ])
      }),
    ),
    #("deferred_wip", json.array(schedule.deferred_wip_tasks, json.string)),
    #("blocked", json.array(schedule.blocked_tasks, json.string)),
  ])
  |> json.to_string
}

fn effective_score(
  task: HiveCellTask,
  pheromones: List(PheromoneSignal),
  now_s: Int,
) -> Int {
  let delta =
    list.fold(pheromones, 0, fn(acc, p) {
      case p.cell_id == task.task_id {
        False -> acc
        True -> {
          let strength = decayed_intensity_bps(p, now_s)
          case p.kind {
            TrailReadyPull | TrailSuccess -> acc + { strength / 100 }
            TrailHazardWarning -> acc - { strength / 50 }
            TrailCorruptionQuarantine -> acc - 100_000
          }
        }
      }
    })
  task.priority_score + delta
}

fn div_pow2(value: Int, shifts: Int) -> Int {
  case shifts <= 0 || value <= 0 {
    True -> value
    False -> div_pow2(value / 2, shifts - 1)
  }
}
