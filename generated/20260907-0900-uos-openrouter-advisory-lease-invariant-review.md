# 20260907-0900- OpenRouter advisory worker: sanitized lease-invariant review
#fractal-l0 #fractal-l3 #fractal-l7 #km-triad #zero-muda #tailscale-web #uos-tui #openrouter #advisory

- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/generated/20260907-0900-uos-openrouter-advisory-lease-invariant-review.md](http://nas-1.tail55d152.ts.net:4100/docs/generated/20260907-0900-uos-openrouter-advisory-lease-invariant-review.md)
- **Transclusions**: `[[zk:20260907-0537-adr-062-uos-tui-swarm-hive-mind-message-board-coordination-acl-and-zenoh-infra]]` `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`
- **Slice**: requested by the live Codex session over the board (integration writer for the tri-agent mainline sync); owned files `apps/uos_tui/src/uos_tui/openrouter_worker.gleam`, `apps/uos_tui/src/openrouter_worker_cli.gleam`, `apps/uos_tui/src/uos_openrouter_ffi.erl`, `apps/uos_tui/test/openrouter_worker_test.gleam`.
- **Role**: advisory only. No tools, no side effects, no automatic actions; the advice is recorded here and referenced from a board Report.

## Comprehensive Verification Checklist (SC-CHECKLIST-001)
<details><summary>18 checkpoints (record-time status)</summary>
CHK-01 PASS (prefix) · CHK-02 PASS (link) · CHK-03 PASS (tags) · CHK-04 PASS (transclusions) · CHK-05 PASS (no barred deps; pure OTP inets/ssl, no vendor SDK) · CHK-06 PASS (no NIF) · CHK-07 DECLARED · CHK-08 DECLARED · CHK-09 DECLARED · CHK-10 DECLARED · CHK-11 DECLARED · CHK-12 PASS (Gleam policy, Erlang I/O) · CHK-13 DECLARED · CHK-14 DECLARED · CHK-15 PASS (inference stays outside the BEAM, over HTTPS, bounded) · CHK-16 PASS (board Report carries trace/span ids) · CHK-17 DECLARED (Codex records formal coverage) · CHK-18 PASS (no git mutation)
</details>

## Policy (pure Gleam, fail closed)
| Control | Value | Enforced by |
|---|---|---|
| Model allowlist | 4 free + 4 paid exact ids, each with a USD/token ceiling | `openrouter_worker.allowlist`, `admit` |
| Live price check | public `/api/v1/models` price must be known and ≤ ceiling before every call | `admit` (`PriceUnknown`, `PriceAboveCeiling`) |
| Tokens | `max_tokens` ≤ 512 (policy cannot raise it) | `admit` (`TooManyTokens`) |
| Budget | estimated cost ≤ USD 0.02 (policy cannot raise it) | `admit` (`OverBudget`) |
| Timeout | 30 s (policy cannot raise it) | `run`, FFI `httpc` timeout |
| Tier | free-only by default; paid needs `allow_paid` / `--paid` | `admit` (`FreeOnly`) |
| Credential | `OPENROUTER_API_KEY` from the approved environment only; never printed; missing key refuses before any network call | `run` (`MissingCredential`), FFI `api_key/0` |
| Prompt hygiene | refuses paths, repository paths, source references, code fences, `import`, credential patterns and names, key markers, > 2000 chars | `sanitize_check` |
| Transport | TLS verify_peer against the system CA bundle with hostname check; errors rendered without headers | `uos_openrouter_ffi` |
| Tools / side effects | none in the request body; `stream=false`; temperature 0 | `request_json` |

## Live run (2026-09-07, this host)
| Attempt | Model | Result |
|---|---|---|
| 1 | google/gemma-4-31b-it:free | refused, http 404: 0 endpoints available under the account's guardrail and data-policy settings |
| 2 | nvidia/nemotron-3.5-lightning:free | refused, http 404 (same) |
| 3 | minimax/minimax-m3:free | refused, http 404 (same) |
| 4 | thinkingmachines/inkling:free | refused, http 403: only available on agentic harnesses |
| 5 | openai/gpt-4.1-nano (paid opt-in) | **completed** via provider Azure: 125+234 tokens, estimated USD 0.0001697, provider-reported USD 0.0001061, 2146 ms, finish `stop` |

Fail-closed check without a credential: `refused: no OPENROUTER_API_KEY in the approved environment` (no network call).

## The sanitized prompt (verbatim, no repository content)
> Design under review: each resource has at most one live lease; lease epochs are strictly increasing per resource; a renewal with a stale epoch, or after expiry, must be refused; a freshly started coordinator must seed its epochs from the durable log before granting anything; every mutation of the resource must carry the epoch and be refused when the epoch is not the current one. List the three most likely ways this invariant is violated in practice and one concrete test for each.

## Advice received (advisory only)
1. **Race Conditions in Lease Renewal or Expiry Handling**  
   - *Violation:* Multiple coordinators may simultaneously attempt to renew or expire a lease, leading to concurrent updates that violate the "at most one live lease" invariant.  
   - *Test:* Simulate concurrent renewal requests for the same resource and verify that only one succeeds, ensuring the system enforces mutual exclusion.

2. **Incorrect Epoch Initialization or Update after Failures**  
   - *Violation:* A coordinator that restarts may incorrectly seed its epoch from an inconsistent or stale log, causing it to accept or grant leases with stale epochs.  
   - *Test:* Restart a coordinator after a crash, then verify that it reads the epoch from the durable log before granting leases, and that it refuses renewal requests with stale epochs.

3. **Mutation with Outdated Epochs**  
   - *Violation:* A mutation request is processed with an epoch older than the current one, violating the rule that such requests must be refused.  
   - *Test:* Send a mutation with a stale epoch and confirm that the system rejects it, ensuring epoch validation is enforced at each mutation point.

## Cross-check against the hardened implementation
| Advice | Where it is enforced | Test |
|---|---|---|
| 1. Concurrent renew/expire must keep one live lease | `coord.acquire` refuses a live lease held by another; `renew` refuses stale epoch and expiry (`LeaseExpired`) | coord_test: lease held by other, renew expired |
| 2. Restart must seed epochs from the durable log | `coord.seed_epochs` reads LeaseGrant/Claim `resource`/`epoch` from the board; `reconcile` calls it | coord_test: fresh coordinator gets epoch 2, never 1 |
| 3. Mutation with a stale epoch must be refused | `coord.claim_ok` board-level epoch check on Claim messages; `WrongEpoch` on renew | coord_test: claim with wrong epoch refused |

The second point is exactly the P1 that Codex Astra raised and that hardening round H2 closed, which makes this cheap advisory pass a useful independent check.
