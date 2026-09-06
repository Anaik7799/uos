//// =============================================================================
//// [UOS-FPP-INTERP] Pure FPP Simulator & Queue Policy Interpreter in Gleam
//// =============================================================================
//// Implements executable semantics for the NASA JPL FPP metamodel:
//// 1. State machine signal dispatch:
////    - Exit actions -> Transition do_actions -> Target resolution -> Entry actions
////    - Unhandled signals in current state dropped (spec semantics)
////    - Guarded choice arc resolution (Kleene-iteration loops)
//// 2. Command queue dispatch:
////    - Sync & Guarded commands execute immediately (Executed)
////    - Async commands enqueue until capacity
////    - Queue-full behaviors: Assert (crash defect), Block (backpressure), Drop
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type Model, type StateMachine, type Target, Assert, AsyncCmd, Block, Drop,
  GuardedCmd, InternalMachine, SyncCmd, ToChoice, ToState,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

// ------------------------------------------------------------- State Machine

pub type MachineState {
  MachineState(current: String, log: List(String))
}

pub fn init_machine(machine: StateMachine) -> Result(MachineState, String) {
  case machine {
    domain.ExternalMachine(name) ->
      Error("External machine " <> name <> " has no executable behavior")
    InternalMachine(
      machine_name: _,
      signals: _,
      guards: _,
      actions: _,
      states: states,
      choices: _,
      initial: #(init_actions, init_state_name),
    ) -> {
      case list.find(states, fn(s) { s.state_name == init_state_name }) {
        Ok(s) -> {
          let log = list.append(init_actions, s.entry)
          Ok(MachineState(current: init_state_name, log: log))
        }
        Error(_) ->
          Error("Initial state " <> init_state_name <> " not found in machine")
      }
    }
  }
}

pub fn dispatch_signal(
  machine: StateMachine,
  guards: List(#(String, Bool)),
  state: MachineState,
  signal: String,
) -> Result(MachineState, String) {
  case machine {
    domain.ExternalMachine(name) ->
      Error("External machine " <> name <> " has no executable behavior")
    InternalMachine(
      machine_name: _,
      signals: _,
      guards: _,
      actions: _,
      states: states,
      choices: choices,
      initial: _,
    ) -> {
      case list.find(states, fn(s) { s.state_name == state.current }) {
        Error(_) -> Error("Current state " <> state.current <> " not found")
        Ok(curr_state) -> {
          let matching =
            list.find(curr_state.transitions, fn(t) {
              t.on_signal == signal && eval_guard(t.guard, guards)
            })

          case matching {
            Error(_) -> {
              // Unhandled signal is dropped per FPP specification semantics
              Ok(state)
            }
            Ok(trans) -> {
              let log_with_exit = list.append(state.log, curr_state.exit)
              let log_with_trans = list.append(log_with_exit, trans.do_actions)
              resolve_target(
                trans.target,
                states,
                choices,
                guards,
                log_with_trans,
              )
            }
          }
        }
      }
    }
  }
}

fn eval_guard(guard: Option(String), guards: List(#(String, Bool))) -> Bool {
  case guard {
    None -> True
    Some(g) -> {
      case list.key_find(guards, g) {
        Ok(b) -> b
        Error(_) -> False
      }
    }
  }
}

fn resolve_target(
  target: Target,
  states: List(domain.State),
  choices: List(domain.Choice),
  guards: List(#(String, Bool)),
  current_log: List(String),
) -> Result(MachineState, String) {
  case target {
    ToState(name) -> {
      case list.find(states, fn(s) { s.state_name == name }) {
        Ok(target_state) -> {
          let final_log = list.append(current_log, target_state.entry)
          Ok(MachineState(current: name, log: final_log))
        }
        Error(_) -> Error("Target state " <> name <> " not found")
      }
    }
    ToChoice(name) -> {
      case list.find(choices, fn(c) { c.choice_name == name }) {
        Error(_) -> Error("Choice node " <> name <> " not found")
        Ok(choice) -> {
          let is_true = eval_guard(Some(choice.choice_guard), guards)
          let #(branch_actions, next_target) = case is_true {
            True -> choice.if_true
            False -> choice.if_false
          }
          let next_log = list.append(current_log, branch_actions)
          resolve_target(next_target, states, choices, guards, next_log)
        }
      }
    }
  }
}

// ------------------------------------------------------------ Command Queues

pub type Queue {
  Queue(capacity: Int, depth: Int, dropped: Int)
}

pub fn empty_queue(capacity: Int) -> Queue {
  Queue(capacity: capacity, depth: 0, dropped: 0)
}

pub type DispatchResult {
  Executed
  Enqueued(Queue)
  Dropped(Queue)
  Blocked
  AssertFailed
  Rejected(String)
}

pub fn send_command(
  model: Model,
  instance_name: String,
  opcode: Int,
  queue: Option(Queue),
) -> Result(DispatchResult, String) {
  case list.find(model.instances, fn(i) { i.inst_name == instance_name }) {
    Error(_) -> Error("Instance " <> instance_name <> " not found")
    Ok(inst) -> {
      case
        list.find(model.components, fn(c) { c.comp_name == inst.of_component })
      {
        Error(_) ->
          Error("Component " <> inst.of_component <> " for instance not found")
        Ok(comp) -> {
          case list.find(comp.commands, fn(cmd) { cmd.opcode == opcode }) {
            Error(_) ->
              Ok(Rejected("Opcode " <> int.to_string(opcode) <> " rejected"))
            Ok(cmd) -> {
              case cmd.cmd_kind {
                SyncCmd -> Ok(Executed)
                GuardedCmd -> Ok(Executed)
                AsyncCmd(priority: _, queue_full: q_policy) -> {
                  case queue {
                    None ->
                      Error(
                        "Async command dispatched to instance without queue context",
                      )
                    Some(q) -> {
                      case q.depth < q.capacity {
                        True -> Ok(Enqueued(Queue(..q, depth: q.depth + 1)))
                        False -> {
                          case q_policy {
                            Drop ->
                              Ok(Dropped(Queue(..q, dropped: q.dropped + 1)))
                            Block -> Ok(Blocked)
                            Assert -> Ok(AssertFailed)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
