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

pub type HierarchicalMachineState {
  HierarchicalMachineState(active_path: List(String), log: List(String))
}

pub fn init_machine(machine: StateMachine) -> Result(MachineState, String) {
  case machine {
    domain.ExternalMachine(name) ->
      Error("External machine " <> name <> " has no executable behavior")
    domain.HierarchicalMachine(_, _, _, _, _, _, _) ->
      Error("Use init_hsm for HierarchicalMachine")
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

pub fn init_hsm(
  machine: StateMachine,
) -> Result(HierarchicalMachineState, String) {
  case machine {
    domain.HierarchicalMachine(
      machine_name: _,
      signals: _,
      guards: _,
      actions: _,
      root_states: roots,
      choices: _,
      initial: #(init_actions, init_root_name),
    ) -> {
      case find_hstate_and_path(roots, init_root_name, []) {
        Error(_) ->
          Error("Initial root state " <> init_root_name <> " not found in HSM")
        Ok(#(root_st, root_path)) -> {
          let init_log = list.append(init_actions, root_st.entry)
          let #(full_path, full_log) =
            enter_initial_sub_states(root_st, root_path, init_log)
          Ok(HierarchicalMachineState(active_path: full_path, log: full_log))
        }
      }
    }
    _ -> Error("init_hsm expects a HierarchicalMachine")
  }
}

fn find_hstate_and_path(
  states: List(domain.HierarchicalState),
  target: String,
  current_path: List(String),
) -> Result(#(domain.HierarchicalState, List(String)), Nil) {
  case states {
    [] -> Error(Nil)
    [s, ..rest] -> {
      let path = list.append(current_path, [s.name])
      case s.name == target {
        True -> Ok(#(s, path))
        False -> {
          case find_hstate_and_path(s.sub_states, target, path) {
            Ok(found) -> Ok(found)
            Error(_) -> find_hstate_and_path(rest, target, current_path)
          }
        }
      }
    }
  }
}

fn enter_initial_sub_states(
  state: domain.HierarchicalState,
  current_path: List(String),
  current_log: List(String),
) -> #(List(String), List(String)) {
  case state.initial_sub_state {
    None -> #(current_path, current_log)
    Some(sub_name) -> {
      case list.find(state.sub_states, fn(sub) { sub.name == sub_name }) {
        Error(_) -> #(current_path, current_log)
        Ok(sub) -> {
          let next_path = list.append(current_path, [sub.name])
          let next_log = list.append(current_log, sub.entry)
          enter_initial_sub_states(sub, next_path, next_log)
        }
      }
    }
  }
}

fn common_ancestor_path(
  p1: List(String),
  p2: List(String),
  acc: List(String),
) -> List(String) {
  case p1, p2 {
    [x, ..r1], [y, ..r2] if x == y ->
      common_ancestor_path(r1, r2, list.append(acc, [x]))
    _, _ -> acc
  }
}

pub fn dispatch_hsm_signal(
  machine: StateMachine,
  guards: List(#(String, Bool)),
  state: HierarchicalMachineState,
  signal: String,
) -> Result(HierarchicalMachineState, String) {
  case machine {
    domain.HierarchicalMachine(
      machine_name: _,
      signals: _,
      guards: _,
      actions: _,
      root_states: roots,
      choices: choices,
      initial: _,
    ) -> {
      // Find the first state in active_path (from leaf up to root) that handles the signal
      let reversed_path = list.reverse(state.active_path)
      let handler =
        find_handling_hstate(roots, reversed_path, signal, guards)

      case handler {
        Error(_) -> {
          // Unhandled signal in active hierarchy is dropped per FPP specification
          Ok(state)
        }
        Ok(#(_handling_st, transition)) -> {
          // Resolve transition target
          case
            resolve_hsm_target(transition.target, roots, choices, guards)
          {
            Error(e) -> Error(e)
            Ok(#(target_st, target_path)) -> {
              let lca =
                common_ancestor_path(state.active_path, target_path, [])
              let lca_depth = list.length(lca)

              // States to exit: below LCA in active path, exited in reverse order (leaf first)
              let states_to_exit =
                list.drop(state.active_path, lca_depth)
                |> list.reverse

              let exit_actions =
                collect_exit_actions(roots, states_to_exit, [])

              // Transition do_actions
              let log_after_exit =
                list.append(state.log, exit_actions)
                |> list.append(transition.do_actions)

              // States to enter: below LCA down to target_st
              let states_to_enter = list.drop(target_path, lca_depth)
              let entry_actions =
                collect_entry_actions(roots, states_to_enter, [])

              let log_after_entry =
                list.append(log_after_exit, entry_actions)

              // Recursively enter initial sub_states of target if any
              let #(final_path, final_log) =
                enter_initial_sub_states(target_st, target_path, log_after_entry)

              Ok(HierarchicalMachineState(
                active_path: final_path,
                log: final_log,
              ))
            }
          }
        }
      }
    }
    _ -> Error("dispatch_hsm_signal expects a HierarchicalMachine")
  }
}

fn find_handling_hstate(
  roots: List(domain.HierarchicalState),
  path_from_leaf: List(String),
  signal: String,
  guards: List(#(String, Bool)),
) -> Result(#(domain.HierarchicalState, domain.Transition), Nil) {
  case path_from_leaf {
    [] -> Error(Nil)
    [name, ..rest] -> {
      case find_hstate_and_path(roots, name, []) {
        Error(_) -> find_handling_hstate(roots, rest, signal, guards)
        Ok(#(st, _)) -> {
          case
            list.find(st.transitions, fn(t) {
              t.on_signal == signal && eval_guard(t.guard, guards)
            })
          {
            Ok(trans) -> Ok(#(st, trans))
            Error(_) -> find_handling_hstate(roots, rest, signal, guards)
          }
        }
      }
    }
  }
}

fn resolve_hsm_target(
  target: domain.Target,
  roots: List(domain.HierarchicalState),
  choices: List(domain.Choice),
  guards: List(#(String, Bool)),
) -> Result(#(domain.HierarchicalState, List(String)), String) {
  case target {
    domain.ToState(name) -> {
      case find_hstate_and_path(roots, name, []) {
        Ok(found) -> Ok(found)
        Error(_) -> Error("Target state " <> name <> " not found in HSM")
      }
    }
    domain.ToChoice(name) -> {
      case list.find(choices, fn(c) { c.choice_name == name }) {
        Error(_) -> Error("Choice node " <> name <> " not found in HSM")
        Ok(choice) -> {
          let is_true = eval_guard(Some(choice.choice_guard), guards)
          let #(_actions, next_target) = case is_true {
            True -> choice.if_true
            False -> choice.if_false
          }
          resolve_hsm_target(next_target, roots, choices, guards)
        }
      }
    }
  }
}

fn collect_exit_actions(
  roots: List(domain.HierarchicalState),
  state_names: List(String),
  acc: List(String),
) -> List(String) {
  case state_names {
    [] -> acc
    [name, ..rest] -> {
      let actions = case find_hstate_and_path(roots, name, []) {
        Ok(#(st, _)) -> st.exit
        Error(_) -> []
      }
      collect_exit_actions(roots, rest, list.append(acc, actions))
    }
  }
}

fn collect_entry_actions(
  roots: List(domain.HierarchicalState),
  state_names: List(String),
  acc: List(String),
) -> List(String) {
  case state_names {
    [] -> acc
    [name, ..rest] -> {
      let actions = case find_hstate_and_path(roots, name, []) {
        Ok(#(st, _)) -> st.entry
        Error(_) -> []
      }
      collect_entry_actions(roots, rest, list.append(acc, actions))
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
    domain.HierarchicalMachine(_, _, _, _, _, _, _) ->
      Error("Use dispatch_hsm_signal for HierarchicalMachine")
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
