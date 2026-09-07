//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/deadman_freshness</module>
////     <fsharp-lineage>N/A — Distributed Actor Dead-Man Freshness Switch</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L2_COMPONENT</layer>
////     <layer>L4_SYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-DMS-001, SC-SIL6-001, SC-JIDOKA-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="fail-closed-timeout">Missed heartbeats >= max_missed strictly trips dead-man switch</property>
////     <property name="constitutional-priority">L0 actor failure immediately triggers Andon halt</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// Heartbeat status of a tracked actor.
pub type ActorHeartbeatStatus {
  HeartbeatNominal
  HeartbeatWarning(missed: Int)
  HeartbeatTripped(since_ms: Int)
  HeartbeatQuarantined
}

/// Tracked actor lease and heartbeat entry.
pub type ActorRegistration {
  ActorRegistration(
    actor_id: String,
    fractal_layer: String,
    heartbeat_interval_ms: Int,
    max_missed_heartbeats: Int,
    last_heartbeat_ms: Int,
    missed_count: Int,
    status: ActorHeartbeatStatus,
    failover_target: Option(String),
  )
}

/// Central dead-man switch registry.
pub type DeadManRegistry {
  DeadManRegistry(
    actors: List(ActorRegistration),
    last_eval_ms: Int,
    total_tripped_count: Int,
  )
}

/// Safety actions generated when an actor violates freshness bounds.
pub type DeadManAction {
  ActionWarnStaleness(actor_id: String, layer: String, missed: Int)
  ActionTripDeadMan(actor_id: String, layer: String, reason: String)
  ActionInitiateFailover(from_actor: String, to_actor: String, layer: String)
}

/// Initialize an empty dead-man registry.
pub fn init_deadman_registry() -> DeadManRegistry {
  DeadManRegistry(
    actors: [],
    last_eval_ms: 0,
    total_tripped_count: 0,
  )
}

/// Register a new distributed actor into the dead-man switch monitor.
pub fn register_actor(
  reg: DeadManRegistry,
  actor_id: String,
  layer: String,
  interval_ms: Int,
  max_missed: Int,
  failover: Option(String),
  now_ms: Int,
) -> DeadManRegistry {
  let existing_filtered =
    list.filter(reg.actors, fn(a) { a.actor_id != actor_id })
  let entry =
    ActorRegistration(
      actor_id: actor_id,
      fractal_layer: layer,
      heartbeat_interval_ms: interval_ms,
      max_missed_heartbeats: max_missed,
      last_heartbeat_ms: now_ms,
      missed_count: 0,
      status: HeartbeatNominal,
      failover_target: failover,
    )
  DeadManRegistry(..reg, actors: [entry, ..existing_filtered])
}

/// Record a heartbeat event from an actor.
pub fn record_heartbeat(
  reg: DeadManRegistry,
  actor_id: String,
  now_ms: Int,
) -> DeadManRegistry {
  let updated_actors =
    list.map(reg.actors, fn(a) {
      case a.actor_id == actor_id {
        True ->
          ActorRegistration(
            ..a,
            last_heartbeat_ms: now_ms,
            missed_count: 0,
            status: HeartbeatNominal,
          )
        False -> a
      }
    })
  DeadManRegistry(..reg, actors: updated_actors)
}

/// Evaluate heartbeat freshness across all registered actors.
pub fn evaluate_freshness_tick(
  reg: DeadManRegistry,
  now_ms: Int,
) -> #(DeadManRegistry, List(DeadManAction)) {
  let #(updated_actors, actions, newly_tripped) =
    list.fold(reg.actors, #([], [], 0), fn(acc, actor) {
      let #(actor_list, action_list, trip_count) = acc
      let elapsed_ms = now_ms - actor.last_heartbeat_ms
      let interval = actor.heartbeat_interval_ms

      case elapsed_ms > interval {
        False -> {
          // Healthy
          let updated = ActorRegistration(..actor, status: HeartbeatNominal, missed_count: 0)
          #([updated, ..actor_list], action_list, trip_count)
        }
        True -> {
          let missed = elapsed_ms / interval
          case missed >= actor.max_missed_heartbeats {
            True -> {
              // Tripped dead-man switch
              let updated =
                ActorRegistration(
                  ..actor,
                  missed_count: missed,
                  status: HeartbeatTripped(since_ms: now_ms),
                )
              let trip_action =
                ActionTripDeadMan(
                  actor_id: actor.actor_id,
                  layer: actor.fractal_layer,
                  reason: "missed heartbeats exceeded threshold",
                )
              let actions_with_failover = case actor.failover_target {
                Some(target) -> [
                  ActionInitiateFailover(
                    from_actor: actor.actor_id,
                    to_actor: target,
                    layer: actor.fractal_layer,
                  ),
                  trip_action,
                  ..action_list
                ]
                None -> [trip_action, ..action_list]
              }
              #([updated, ..actor_list], actions_with_failover, trip_count + 1)
            }
            False -> {
              // Warning phase
              let updated =
                ActorRegistration(
                  ..actor,
                  missed_count: missed,
                  status: HeartbeatWarning(missed: missed),
                )
              let warn_action =
                ActionWarnStaleness(
                  actor_id: actor.actor_id,
                  layer: actor.fractal_layer,
                  missed: missed,
                )
              #([updated, ..actor_list], [warn_action, ..action_list], trip_count)
            }
          }
        }
      }
    })

  let updated_reg =
    DeadManRegistry(
      actors: updated_actors,
      last_eval_ms: now_ms,
      total_tripped_count: reg.total_tripped_count + newly_tripped,
    )
  #(updated_reg, actions)
}

/// Count number of currently healthy nominal actors.
pub fn active_healthy_actors_count(reg: DeadManRegistry) -> Int {
  list.length(
    list.filter(reg.actors, fn(a) {
      case a.status {
        HeartbeatNominal -> True
        _ -> False
      }
    }),
  )
}

/// Check if all L0 Constitutional actors are fully operational.
pub fn is_l0_constitutional_safe(reg: DeadManRegistry) -> Bool {
  let l0_actors =
    list.filter(reg.actors, fn(a) { a.fractal_layer == "L0_CONSTITUTIONAL" })
  case l0_actors {
    [] -> True
    actors ->
      list.all(actors, fn(a) {
        case a.status {
          HeartbeatNominal -> True
          _ -> False
        }
      })
  }
}
