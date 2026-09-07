## Losses
- L1: Unsafe side effect executed from the TUI
- L2: Operator misled by a false-green screen
- L3: Loss of terminal (raw mode not restored)
- L4: Unverified code integrated

## Hazards
- H1: TUI dispatches a mutating intent without confirmation (losses: L1)
- H2: Screen paints a passing state that audit did not verify (losses: L2)
- H3: Process exits or crashes while raw mode is active (losses: L3)
- H4: Swarm integrates a slice that was not verified at HEAD (losses: L4)

## Control structure
- CTRL-TUI-APP: Pure step controller
- CTRL-TUI-DRIVER: Live terminal driver actor
- CTRL-TUI-ASPECTS: Audit / aspects controller
- CTRL-SWARM-L0: Swarm supervisor
- CTRL-SWARM-VERIFIER: Swarm verifier
  - CA-emit_intent (CTRL-TUI-APP): emit_intent
  - CA-push_confirm_screen (CTRL-TUI-APP): push_confirm_screen
  - CA-paint_frame (CTRL-TUI-DRIVER): paint_frame
  - CA-enter_raw (CTRL-TUI-DRIVER): enter_raw
  - CA-restore_terminal (CTRL-TUI-DRIVER): restore_terminal
  - CA-audit_screen (CTRL-TUI-ASPECTS): audit_screen
  - CA-integrate_slice (CTRL-SWARM-L0): integrate_slice
  - CA-verify_slice (CTRL-SWARM-VERIFIER): verify_slice
  - CA-write_owned_file (CTRL-SWARM-L0): write_owned_file

## UCAs
| id | source | type | action | pms | cif | sif | ej | band |
|---|---|---|---|---|---|---|---|---|
| UCA-01 | CTRL-TUI-APP | NotProvided | CA-push_confirm_screen | 4 | 5 | 20 | 4.5 | P1 |
| UCA-02 | CTRL-SWARM-VERIFIER | NotProvided | CA-verify_slice | 4 | 5 | 20 | 4.6 | P1 |
| UCA-03 | CTRL-TUI-APP | ProvidedUnsafe | CA-emit_intent | 3 | 4 | 12 | 3.4 | P2 |
| UCA-04 | CTRL-TUI-ASPECTS | ProvidedUnsafe | CA-audit_screen | 4 | 4 | 16 | 4.0 | P1 |
| UCA-05 | CTRL-TUI-DRIVER | WrongTiming | CA-enter_raw | 2 | 3 | 6 | 2.4 | P3 |
| UCA-06 | CTRL-SWARM-L0 | WrongTiming | CA-integrate_slice | 4 | 4 | 16 | 4.2 | P1 |
| UCA-07 | CTRL-TUI-DRIVER | StoppedTooSoon | CA-restore_terminal | 3 | 5 | 15 | 3.8 | P2 |
| UCA-08 | CTRL-SWARM-VERIFIER | StoppedTooSoon | CA-verify_slice | 3 | 4 | 12 | 3.3 | P2 |
| UCA-09 | CTRL-TUI-DRIVER | NotProvided | CA-paint_frame | 2 | 2 | 4 | 2.0 | P3 |
| UCA-10 | CTRL-SWARM-L0 | ProvidedUnsafe | CA-write_owned_file | 3 | 4 | 12 | 3.6 | P2 |
| UCA-11 | CTRL-TUI-APP | WrongTiming | CA-emit_intent | 2 | 3 | 6 | 2.5 | P3 |

## Constraints
| id | ucas | text | enforcement |
|---|---|---|---|
| C-01 | UCA-01 | Every mutating control action must route through push_confirm_screen | HarnessCheck: aspects.audit fail-closed |
| C-02 | UCA-02, UCA-06 | No slice may be integrated without a recorded verifier PASS verdict | ProcessRule: integrate only after PASS verdict |
| C-03 | UCA-03 | emit_intent is only valid for widgets present in focus_chain | HarnessCheck: focus_chain membership check |
| C-04 | UCA-04 | audit_screen must report FAIL whenever any finding is fail-closed | HarnessCheck: aspects.admissible fail-closed |
| C-05 | UCA-05 | enter_raw must not run until probe_size returns a resolved size | Production: live.probe_size ordering guard |
| C-06 | UCA-07 | restore_terminal must complete under signal handlers before exit | Production: live driver signal-safe teardown |
| C-07 | UCA-08 | verify_slice must run compile and test phases before PASS | HarnessCheck: verifier gleam build + gleam test gate |
| C-08 | UCA-10 | write_owned_file must stay inside the worker's declared package path | HarnessCheck: verifier jj diff --summary ownership |
| C-09 | UCA-09 | paint_frame must run after every accepted state transition | Production: app.step / frame_rendered invariant |
| C-10 | UCA-11 | emit_intent must be idempotent per key event id | ProcessRule: dedupe intents by event sequence number |
