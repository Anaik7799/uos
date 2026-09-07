# 20260907-1330- FerrisKey-as-NIF IAM Protocol (UOS mirror of the C3I rule)
#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l7 #zero-muda #km-triad #rocha-semiotics #cybernetics #stamp-stpa #iam

- **Contract IDs**: `SC-FERRISKEY-NIF-001..010`, `SC-GCP-IAM-001..020`, `AOR-IAM-NIF-001..008`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/.codex/rules/20260907-1330-iam-ferriskey-nif-rule.md](http://nas-1.tail55d152.ts.net:4100/docs/.codex/rules/20260907-1330-iam-ferriskey-nif-rule.md)
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`
- **Canonical copy**: `.claude/rules/20260907-1330-iam-ferriskey-nif-rule.md` (this file is the durable Codex summary per the full-symbiosis rule; keep both identical in substance).
- **Source**: `/home/an/dev/ver/c3i/.claude/rules/iam-ferriskey-nif.md` (VM-1 C3I evidence). UOS paths: `native/nifs/rust/ferriskey_nif/` (sources, ingestion pending operator permission), `apps/cepaf_gleam/src/ferriskey_nif.erl` (loader), `apps/cepaf_gleam/priv/ferriskey_nif.so` (host-provisioned, pinned by `priv/ferriskey_nif.sha256`, never committed). Provenance: `governance/sources/20260907-1330-ferriskey-nif-source-ingestion.json`. Codex R5 security review required before any admission claim.

---

## Mandate

FerrisKey IAM is embedded as a NIF inside cepaf_gleam. The local copy is the source of truth; Google Cloud IAM is the federation peer. All in-mesh IAM hot-paths run in-process; all cross-cloud IAM goes through the same NIF (no out-of-process HTTP hops).

## STAMP Constraints — SC-FERRISKEY-NIF-001..010

| ID | Constraint | Severity |
|----|-----------|----------|
| SC-FERRISKEY-NIF-001 | NIF cdylib MUST load via `-on_load` on BEAM start | CRITICAL |
| SC-FERRISKEY-NIF-002 | A single `OnceCell<tokio::Runtime>` MUST be shared across all NIFs | CRITICAL |
| SC-FERRISKEY-NIF-003 | All NIFs MUST be scheduled `DirtyCpu` or `DirtyIo` per workload class | CRITICAL |
| SC-FERRISKEY-NIF-004 | JWKS cache TTL ≤ 5 min, soft-refresh at 80 % | HIGH |
| SC-FERRISKEY-NIF-005 | In-process JWT validation latency p99 ≤ 2 ms | HIGH |
| SC-FERRISKEY-NIF-006 | Audit span MUST be emitted for every write NIF (OTel → Zenoh `indrajaal/l0/iam/**`) | HIGH |
| SC-FERRISKEY-NIF-007 | SQLite WAL + `synchronous=NORMAL` + 30 s busy_timeout | HIGH |
| SC-FERRISKEY-NIF-008 | Signing-key rotation ≤ 90 days; 7-day overlap; `kid` in JWT header | HIGH |
| SC-FERRISKEY-NIF-009 | NIF panic MUST NOT crash BEAM (rustler `Term` map_error) | CRITICAL |
| SC-FERRISKEY-NIF-010 | Vault-backed signing keys; no plaintext outside SQLite | CRITICAL |

## STAMP Constraints — SC-GCP-IAM-001..020

| ID | Constraint | Severity |
|----|-----------|----------|
| SC-GCP-IAM-001 | Workload Identity Pool provider = OIDC; issuer = `https://<host>/realms/<realm>` | CRITICAL |
| SC-GCP-IAM-002 | STS exchange MUST be RFC 8693 conformant (`subject_token_type = jwt`) | CRITICAL |
| SC-GCP-IAM-003 | GCP access-token cache TTL = `min(returned_exp, 55 min)` | HIGH |
| SC-GCP-IAM-004 | SCIM 2.0 server MUST be RFC 7643/7644 conformant (filter, sort, pagination, etag) | CRITICAL |
| SC-GCP-IAM-005 | GDPR EU residency: ALL GCP endpoints pinned to `europe-north1` | CRITICAL |
| SC-GCP-IAM-006 | Service-account keys fetched from RustyVault, never on disk | CRITICAL |
| SC-GCP-IAM-007 | SCIM destructive ops (DELETE Users/Groups) MUST be 2oo3 Guardian-gated | CRITICAL |
| SC-GCP-IAM-008 | Outbound SCIM PUSH retried with exponential backoff (max 3, jitter) | HIGH |
| SC-GCP-IAM-009 | STS rate-limit aware: token bucket 60 rpm/realm | HIGH |
| SC-GCP-IAM-010 | mTLS pinning on `sts.googleapis.com` cert chain (ring-verified) | HIGH |
| SC-GCP-IAM-011 | Allow-policy mutations MUST use etag (optimistic concurrency) | CRITICAL |
| SC-GCP-IAM-012 | `setIamPolicy` MUST be 2oo3 Guardian-gated | CRITICAL |
| SC-GCP-IAM-013 | `gcp_deny_policy_apply` is the canonical emergency-stop pathway, p99 ≤ 5 s | CRITICAL |
| SC-GCP-IAM-014 | Basic roles (Owner/Editor/Viewer) FORBIDDEN in TF; CI lint enforces | HIGH |
| SC-GCP-IAM-015 | IAM Recommender output reviewed weekly; 2oo3 to apply | HIGH |
| SC-GCP-IAM-016 | Policy Troubleshooter audit retained 90 days | MEDIUM |
| SC-GCP-IAM-017 | Org-policy violations MUST block NIF `policy_set` pre-flight | HIGH |
| SC-GCP-IAM-018 | VPC Service Controls perimeter MUST list Tailscale exit IP for `*.googleapis.com` egress | HIGH |
| SC-GCP-IAM-019 | CMEK keyring for backup + audit-log buckets distinct from FerrisKey signing-key vault | HIGH |
| SC-GCP-IAM-020 | Region-pin lint: any new `*.googleapis.com` reqwest call without `europe-north1` literal fails CI | HIGH |

## AOR Rules

| ID | Rule |
|----|------|
| AOR-IAM-NIF-001 | NEVER call FerrisKey out-of-process for hot-path operations (JWT validate, JWKS lookup) |
| AOR-IAM-NIF-002 | ALWAYS read GCP service-account keys via `vault_bridge::get`, never from disk or env |
| AOR-IAM-NIF-003 | ALWAYS call `audit::emit` before returning from a write NIF |
| AOR-IAM-NIF-004 | ALWAYS pin GCP region to `europe-north1`; CI lint rejects naked `*.googleapis.com` strings |
| AOR-IAM-NIF-005 | NEVER add basic IAM roles (Owner/Editor/Viewer) to any Terraform under `infra/gcp/iam/` |
| AOR-IAM-NIF-006 | ALWAYS update `wiring_guard.gleam` and `ferriskey_nif_wiring_test.gleam` in the same commit as Model field changes (SC-WIRE-002) |
| AOR-IAM-NIF-007 | ALWAYS gate destructive SCIM ops + `setIamPolicy` through 2oo3 Guardian |
| AOR-IAM-NIF-008 | ALWAYS use etag for `iam_policy_set` to prevent lost updates |

## Supervisor topology, fractal matrix, vault paths, RETE-UL rules, triple interface

Identical to the canonical copy in `.claude/rules/20260907-1330-iam-ferriskey-nif-rule.md`; UOS placement `apps/cepaf_gleam/src/cepaf_gleam/iam/*`, `auth/*`, `ui/wisp/auth_api.gleam`; tests `ferriskey_nif_wiring_test` (33), `ferriskey_rbac_wiring_test` (6), `auth_oidc_test`, `auth_rbac_test`.

---
Navigation: [ZK Master MOC](http://nas-1.tail55d152.ts.net:4100/zk) · [Hermes Wiki Corpus Index](http://nas-1.tail55d152.ts.net:4100/wiki) · [Review Tome](http://nas-1.tail55d152.ts.net:4100/docs/.claude/rules/20260907-1330-iam-ferriskey-nif-rule.md)
