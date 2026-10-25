# 20261011-1830-telegram-service-slice3-verification

- **Timestamp**: `2026-10-11T16:32:00Z`
- **Plan ID**: `uos/telegram-runtime/20261001-1150`
- **Task ID**: `SERVICE_IMPL`
- **Attempt**: 1
- **Worker**: `agy-telegram-20261011`
- **Status**: DEVELOPMENT_COMPONENT_PASS (Task remains OPEN)
- **Tailscale FQDN**: [http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261011-1830-telegram-service-slice3-verification.md](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261011-1830-telegram-service-slice3-verification.md)

#fractal-l0 #fractal-l2 #fractal-l3 #fractal-l5 #zero-muda #km-triad #stamp-stpa

---

## 1. Scope & Trigger
Execution of Slice 3 hardening and verification for task `SERVICE_IMPL` (Attempt 1, `executing`, worker `agy-telegram-20261011`) under plan `uos/telegram-runtime/20261001-1150`. Following root review findings and concrete reproducers (`service_http_review.erl`, `service_http_deadline.erl`, and `governance/planning/20261011-1606-telegram-lifecycle-feasibility.json`), Slice 3 addresses:
1. Monotonic absolute deadline enforcement in `telegram_http_ffi.erl` spanning connect, headers, and all body chunks combined, with immediate client connection reaping on timeout/cancellation.
2. Out-of-policy HTTP configuration rejection (non-positive or excessive timeouts and byte caps).
3. Telegram error description sanitization into a categorized whitelist, strictly barring the leakage of tokens, URLs, or internal system state.
4. Elimination of mock cgroup directory paths and forged receipt test factories.
5. Integration of the retained parent slice witness pattern (`app-uos_tg_test_NONCE.slice`) for whole-unit cgroup isolation, verifying recursive process emptiness (`cgroup.events` reporting `populated 0`) after child service stop.
6. Execution and verification against all 19 root review reproducer cases and 62 in-tree unit and end-to-end tests.

---

## 2. Pre-State Assessment
- Slice 2 OTP actor and E2E tests were functional, but root independent review identified three critical vulnerabilities:
  - **Slow-Drip Timeout Reset**: Resetting timeouts per body chunk allowed slow-drip HTTP streams to exceed the configured deadline by multiple integer multiples (e.g. configured 80ms returning after 294ms).
  - **Opaque Proof Circumvention**: Accepting an arbitrary caller `cgroup_base_dir` allowed callers to create synthetic mock directories in `/tmp` and mint valid `UnitCleanupReceipt` objects without actually verifying systemd cgroups.
  - **Child Cgroup Removal upon Stop**: Systemd deletes transient child unit cgroups immediately upon stopping the service, making post-stop emptiness checks on the child's cgroup path fail with `ENOENT`.
- 8/8 product sources are strictly frozen and verified against their canonical SHA-256 hashes.
- Preflight passed 31/31.

---

## 3. Execution Detail
1. **Monotonic Absolute Deadline & Client Reaping (`telegram_http_ffi.erl`)**:
   - Implemented absolute deadline calculation: `Deadline = StartTime + TimeoutMs` using monotonic Erlang time.
   - At every chunk receive in the streaming Hackney client loop, the remaining duration is evaluated against the monotonic clock. If remaining time is `<= 0`, the client loop immediately terminates with `{error, <<"timeout">>}`.
   - Implemented `reap_client/1`, which explicitly closes the underlying Hackney connection and drains pending messages from the Erlang process mailbox on timeout or client errors.
   - Enforced policy boundary validation: rejected invalid or non-positive timeouts (1ms .. 60,000ms) and max bytes (1B .. 10,485,760B) with typed errors `{error, <<"invalid_timeout_ms_out_of_policy">>}` and `{error, <<"invalid_max_bytes_out_of_policy">>}`.
   - Sanitized Telegram API error descriptions into whitelist categories: `bad_request`, `chat_not_found`, `bot_blocked_by_user`, `user_deactivated`, `message_not_modified`, `message_empty`, `message_too_long`, `forbidden`, `not_found`, `client_error`.
2. **Retained Parent Slice Witness Pattern (`telegram_lifecycle_ffi.erl` & `telegram_lifecycle_adapter.gleam`)**:
   - Enforced Poka-Yoke validation on both test units (`uos-tg-store-test-*`) and test slices (`app-uos_tg_test_*`), forbidding production units (`herdr`, `app.slice`, `user@1000.service`).
   - Implemented `start_test_slice` and `stop_test_slice` using timeout-bounded `open_port` spawn_executable, verifying exact exit code 0.
   - Enforced canonical `/sys/fs/cgroup` prefix in `read_cgroup_events_populated`, refusing any non-canonical paths outside `/sys/fs/cgroup`.
   - Updated `stop_and_verify_test_unit` to:
     1. Verify parent slice is active and capture its `ControlGroup` and `InvocationID`.
     2. Verify child unit is active and capture its `InvocationID`.
     3. Stop child unit (`systemctl --user stop <unit>`) and verify exit code 0.
     4. Observe child unit state is `inactive` or `failed`.
     5. Derive canonical cgroup path strictly from `/sys/fs/cgroup` + slice `ControlGroup`.
     6. Inspect retained parent slice `cgroup.events` for `populated 0`.
     7. Stop parent slice (`systemctl --user stop <slice>`) and verify exit code 0.
     8. Mint opaque `UnitCleanupReceipt` containing exact bindings.
3. **End-to-End Recovery Update (`telegram_service_e2e_test.gleam`)**:
   - Replaced mock cgroup directory with real userspace systemd test slice `app-uos_tg_test_recovery_1.slice` and service `uos-tg-store-test-recovery-1.service`.
   - Verified that `stop_and_verify_test_unit` exercises the real userspace systemd manager and cgroupv2 filesystem.
4. **Root Reproducer Verification**:
   - Evaluated against `service_http_review.erl`: 10/10 PASS (`violation=false`).
   - Evaluated against `service_http_deadline.erl`: 1/1 PASS (`violation=false`, slow drip times out at 138ms on 80ms deadline).
   - Evaluated against `service_http_boundaries.erl`: 8/8 PASS (`violation=false`).

---

## 4. Root Cause Analysis (ACH Disconfirmation Matrix)
During Slice 3, two critical failure modes were evaluated:

Engine 1 ACH (Analysis of Competing Hypotheses):
- H1: Per-chunk timeout reset in streaming HTTP client causes cumulative deadline overruns. Confirmed: resetting timeout per receive allows responses that trickle bytes slowly to evade timeouts; resolved by calculating monotonic absolute deadline up front.
- H2: Systemd cgroup deletion upon unit stop prevents post-stop emptiness verification. Confirmed: stopping a service removes its cgroup; resolved by starting a dedicated parent slice that remains active after child stop, acting as the retained emptiness witness.
- H3: Accepting arbitrary caller cgroup path enables forged cleanup receipts. Confirmed: allowing caller-provided paths permitted `/tmp` mocks; resolved by enforcing `/sys/fs/cgroup` prefix and deriving path exclusively from manager reported properties.

| Evidence / Finding | H1: Monotonic Deadline Needed | H2: Retained Parent Slice Needed | H3: Canonical Cgroup Path Mandatory |
|---|---|---|---|
| E1: 80ms deadline returned after 294ms | **Consistent** (slow drip exceeded deadline) | Irrelevant | Irrelevant |
| E2: Child cgroup returns ENOENT after stop | Irrelevant | **Consistent** (parent slice solves missing dir) | Irrelevant |
| E3: Forged receipt probe minted without unit | Irrelevant | Irrelevant | **Consistent** (removed caller base dir parameter) |

---

## 5. Fix Taxonomy
- **Poka-Yoke**: Monotonic absolute deadline calculation eliminates timer resets during slow-drip streaming attacks. Strict prefix and regex validation bars manipulation of host or production systemd units.
- **Jidoka**: Retained parent slice witness guarantees that any surviving descendant process prevents `populated 0`, triggering fail-closed rejection.
- **Muda Elimination**: Eliminated fake mock cgroup directories in testing; tests exercise real userspace systemd slices and cgroupv2 properties directly.

---

## 6. Patterns & Anti-Patterns Discovered
Engine 4 Devil's Advocate / Popperian falsification tested adversarial edge cases including slow-drip HTTP responses, trailing garbage bytes, oversized payloads, non-canonical cgroup paths, and surviving descendant processes.
- **Pattern**: Retained Parent Slice Witness — wrapping transient test services in a dedicated private parent slice provides a stable cgroup anchor to observe hierarchical emptiness (`populated 0`) after the child service unit is removed.
- **Pattern**: Monotonic Absolute Deadline — computing `StartTime + TimeoutMs` and checking remaining time before every I/O step bounds total connection lifetime across arbitrarily fragmented network streams.
- **Anti-Pattern**: Resetting receive timeouts on every incoming network chunk without tracking total elapsed time.
- **Anti-Pattern**: Accepting unverified filesystem paths from callers when minting high-assurance proof receipts.

---

## 7. Verification Matrix (NATO STANAG >= B2)
| Check | Requirement | Result | Admiralty Rating |
|---|---|---|---|
| C1: HTTP Review Suite | 10/10 root HTTP cases | PASS (violation=false) | A1 |
| C2: HTTP Deadline Suite | 1/1 slow drip monotonic deadline | PASS (violation=false) | A1 |
| C3: HTTP Boundaries Suite | 8/8 edge case boundary tests | PASS (violation=false) | A1 |
| C4: Ledger Regression | 27/27 ledger tests green | PASS (0.152s) | A1 |
| C5: Ingress Guard Regression | 16/16 guard tests green | PASS (0.050s) | A1 |
| C6: Slice 1 Regression | 14/14 slice 1 tests green | PASS (4.108s) | A1 |
| C7: E2E Integration Suite | 5/5 E2E tests green with real slice | PASS (3.605s) | A1 |
| C8: Preflight Sweep | 31/31 preflight checks | PASS (2.6s) | A1 |
| C9: Risk Active-Check | ACTIVE_OBSERVATION_PASS | PASS (0 findings) | A1 |
| C10: Product Source Freeze | 8/8 product hashes exact match | PASS | A1 |

---

## 8. Files Modified / Created
- `apps/cepaf_gleam/src/telegram_http_ffi.erl`: Monotonic absolute deadline, connection reaping, out-of-policy parameter checks, and error description sanitization.
- `apps/cepaf_gleam/src/cepaf_gleam/harness/telegram_http_client.gleam`: Ingress ID boundaries and callback query result enforcement.
- `apps/cepaf_gleam/src/telegram_lifecycle_ffi.erl`: Poka-Yoke slice validation, slice start/stop, canonical `/sys/fs/cgroup` prefix enforcement.
- `apps/cepaf_gleam/src/cepaf_gleam/harness/telegram_lifecycle_adapter.gleam`: Retained parent slice witness pattern, removal of arbitrary caller cgroup base dir.
- `apps/cepaf_gleam/test/telegram_service_slice1_test.gleam`: Added slice name validation test.
- `apps/cepaf_gleam/test/telegram_service_e2e_test.gleam`: Swapped mock cgroup directory for real userspace systemd test slice and service.
- `governance/planning/20261011-1830-telegram-service-slice3-verification.json`: Slice 3 verification receipt.
- `docs/journal/20261011-1830-telegram-service-slice3-verification.md`: This epistemic ledger.

---

## 9. Architectural Observations
Using a dedicated transient parent slice as the retained witness solves the classic systemd lifecycle race condition where child cgroups vanish upon unit stop. By monitoring the parent slice's `cgroup.events` file, the lifecycle adapter can definitively verify that all descendant processes (including detached or daemonized child processes) have completely terminated before minting an opaque `UnitCleanupReceipt`.

---

## 10. Remaining Gaps
1. Independent review and verification by root of Slice 3 hardening.
2. Integration into the root UOS supervisor (`apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam`) following root verification.
3. Task `SERVICE_IMPL` remains **OPEN** as mandated until explicit root acceptance.

---

## 11. Metrics Summary
- **Tests Executed**: 19 (Root Review Reproducers) + 62 (In-Tree Telegram Suites) = 81 test cases green.
- **Product Source Mutations**: 0 bytes across all 8 verified product sources.
- **Preflight Checks**: 31/31 PASS.
- **Bayesian Trust & Lyapunov Stability**: All ephemeral systemd slices and units cleanly torn down; zero leaking cgroups or descriptors; Bayesian trust metric updated with posterior confidence Beta(82, 1).

---

## 12. STAMP & Constitutional Alignment
- **Control Loop Safety**: Adheres strictly to `SC-HARNESS-MCP-001`, `SC-JIDOKA-001`, and `SC-SA-PLAN-001`.
- **Zero-Muda**: Zero Bevy, zero Graphite, zero Python outside inference daemon.
- **Storage Safety**: Respects hardware OS NVMe interlocks (`[REDACTED_SYSTEM_OS_SERIAL]`).
- **Loopback Isolation**: All network operations strictly confined to `127.0.0.1:<ephemeral_port>`; zero traffic routed to live internet.

---

## 13. Conclusion
Slice 3 hardening is complete and verified green with 19/19 root review reproducer cases and 62/62 in-tree tests passing. Task `SERVICE_IMPL` remains **OPEN** awaiting root independent review and acceptance.

Engine 7 Forecast precommitment: p = 0.98 probability that root independent verification of `SERVICE_IMPL` Slice 3 will confirm green status without product source alterations by Horizon 2026-10-11T20:30:00Z; evaluated via Brier scoring Brier=(p-o)^2.
