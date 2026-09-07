# uos_tui Feature Sheet

## Widgets
rows: 17
| Widget | Focusable |
| --- | --- |
| Static | not focusable |
| Header | not focusable |
| Footer | not focusable |
| Button | focusable |
| Input | focusable |
| DataTable | focusable |
| Tree | focusable |
| ListView | focusable |
| ProgressBar | not focusable |
| Sparkline | not focusable |
| Tabs | focusable |
| Log | not focusable |
| Rule | not focusable |
| Container | not focusable |
| Grid | not focusable |
| Checklist | focusable |
| StatusBar | not focusable |

## Keys
rows: 19
| Key | Label |
| --- | --- |
| Char("a") | a |
| Enter | enter |
| Escape | esc |
| Backspace | backspace |
| Tab | tab |
| BackTab | shift+tab |
| Up | ↑ |
| Down | ↓ |
| Left | ← |
| Right | → |
| Home | home |
| End | end |
| PageUp | pgup |
| PageDown | pgdn |
| Delete | del |
| Insert | ins |
| F(1) | F1 |
| Ctrl("c") | ^c |
| Unknown("?") | ? |

## Effects
rows: 8
| Effect | Meaning |
| --- | --- |
| NoEffect | No side effect requested. |
| Batch | Run a list of effects together. |
| Task | Run an async fn() -> msg and dispatch its result. |
| PushScreen | Push a named screen onto the screen stack. |
| PopScreen | Pop the top screen off the screen stack. |
| FocusWidget | Move focus to a widget id. |
| Telemetry | Emit a channel/value telemetry pair. |
| Quit | Request application shutdown. |

## Aspects
rows: 17
| # | Aspect |
| --- | --- |
| 1 | Substrate & Hardware Storage Safety |
| 2 | Standalone Jujutsu Monorepo Discipline |
| 3 | Zero-Muda Purity & Waste Elimination |
| 4 | Gleam/OTP Root Supervisor |
| 5 | ZigVM Deterministic Engine & VFS Laws |
| 6 | Hermes Formal Evidence & Gospel |
| 7 | Mathematical Authority & Conservation |
| 8 | Biosemiotic Cybernetics & Rocha Cut |
| 9 | Quarantined Modular MAX Inference |
| 10 | Zenoh OoZ & MoZ Mesh Telemetry |
| 11 | AG-UI 32-Event SSE Stream |
| 12 | A2UI Declarative Catalog |
| 13 | Penta-Stack Multi-Interface Accessibility |
| 14 | Universal Tailscale FQDN Web Navigation |
| 15 | Comprehensive Verification Checklist |
| 16 | Knowledge Management Triad |
| 17 | Sa-Plan & Bionic Durable Workflows |

## F´ commands
rows: 6
| Command | Opcode | Kind |
| --- | --- | --- |
| TUI_SET_MODE | 1 | async |
| TUI_SELECT_TAB | 2 | async |
| TUI_PUSH_SCREEN | 3 | async |
| TUI_POP_SCREEN | 4 | async |
| TUI_REQUEST_INTENT | 5 | guarded |
| TUI_AUDIT_ASPECTS | 6 | sync |

## F´ channels
rows: 7
| Channel | Id | Type |
| --- | --- | --- |
| FrameCount | 1 | U64 |
| FrameMicros | 2 | U32 |
| ScreenDepth | 3 | U8 |
| FocusedWidget | 4 | String |
| AspectsPassed | 5 | U8 |
| AspectsFailed | 6 | U8 |
| CockpitMode | 7 | U8 |

## F´ events
rows: 7
| Event | Id | Severity |
| --- | --- | --- |
| TuiKeyPressed | 1 | ACTIVITY_LO |
| TuiScreenChanged | 2 | ACTIVITY_HI |
| TuiIntentEmitted | 3 | COMMAND |
| TuiActionBlocked | 4 | WARNING_HI |
| TuiResize | 5 | DIAGNOSTIC |
| TuiAspectFailed | 6 | WARNING_HI |
| TuiInterlockViolation | 7 | FATAL |

## F´ parameters
rows: 3
| Parameter | Id | Type |
| --- | --- | --- |
| FqdnBase | 1 | String |
| RefreshMs | 2 | U16 |
| OsNvmeSerial | 3 | String |

## Ontology fidelity
rows: 4
| Fidelity | Count |
| --- | --- |
| Isomorphic | 18 |
| Homomorphic | 12 |
| Reinterpreted | 6 |
| Deferred | 2 |

## Cockpit bindings
rows: 13
| Key | Description |
| --- | --- |
| 1 | overview |
| 2 | supervisors |
| 3 | containers |
| 4 | storage |
| 5 | zenoh |
| 6 | tasks |
| 7 | security |
| 8 | doctor |
| 9 | swarm |
| m | mode |
| r | restart(confirm) |
| x | stop(confirm) |
| q | quit |

## Drivers
rows: 4
| Driver | Purpose |
| --- | --- |
| headless.run | Feed scripted events through an App and collect every frame. |
| live.run | Drive a live terminal App on OTP: actor, reader and ticker. |
| live.child_spec | Supervisor child spec that starts the live driver actor. |
| live.snapshot_text | Render one deterministic text snapshot of an App at a given size. |

## Test modalities
rows: 9
| Modality | Where |
| --- | --- |
| Unit | test/*_test.gleam, one module under test each |
| System | headless.run driving a full App across many events |
| TDD | red/green cycles co-located with each src change |
| BDD | scenario-named _test.gleam functions (given/when/then) |
| Performance | perf_test.gleam frame-timing assertions |
| Scalability | large-N inputs via prng.ints and prng.text |
| Property | prng-seeded invariant checks across many seeds |
| Fuzz | prng.text random input fed to total, never-crash paths |
| Chaos | prng-seeded randomised event/effect sequences |

