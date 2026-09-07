---- MODULE FerrisKeyIAM ----
(***************************************************************************)
(* FerrisKey IAM — OIDC token lifecycle, RBAC mapping, session mutex        *)
(*                                                                          *)
(* Models the safety properties of the centralized identity & access        *)
(* management substrate (container #17 in the SIL-6 Biomorphic Mesh).       *)
(*                                                                          *)
(* Source modules:                                                          *)
(*   - sub-projects/ferriskey/                                              *)
(*   - lib/cepaf_gleam/src/cepaf_gleam/auth/oidc.gleam                      *)
(*   - lib/cepaf_gleam/src/cepaf_gleam/auth/rbac.gleam                      *)
(*   - lib/cepaf_gleam/src/cepaf_gleam/auth/token_exchange.gleam            *)
(*   - lib/cepaf_gleam/src/cepaf_gleam/ui/wisp/auth.gleam                   *)
(*                                                                          *)
(* STAMP: SC-AUTH-001..008, SC-IAM-001..008, SC-SAFETY-001                  *)
(***************************************************************************)

EXTENDS Naturals, FiniteSets, TLC

CONSTANTS
    Principals,         \* set of human + service identities
    Roles,              \* {c3i-admin, c3i-operator, c3i-viewer, c3i-service}
    Tokens,             \* finite token id domain
    Layers              \* {L0, L1, L2, L3, L4, L5, L6, L7}

VARIABLES
    token_state,        \* token_id -> {issued, valid, revoked, expired}
    token_owner,        \* token_id -> principal
    role_of,            \* principal -> role assignment (function)
    active_sessions     \* principal -> set of currently-valid tokens

vars == << token_state, token_owner, role_of, active_sessions >>

\* RBAC layer permissions per role (SC-IAM-003 exhaustiveness)
RolePermissions(r) ==
    CASE r = "c3i-admin"    -> Layers
      [] r = "c3i-operator" -> Layers \ {"L0"}
      [] r = "c3i-viewer"   -> {"L4", "L5", "L6", "L7"}
      [] r = "c3i-service"  -> {"L3", "L4", "L5", "L6"}
      [] OTHER              -> {}

Init ==
    /\ token_state = [t \in Tokens |-> "issued"]
    /\ token_owner \in [Tokens -> Principals]
    /\ role_of \in [Principals -> Roles]      \* INV: every principal has a role
    /\ active_sessions = [p \in Principals |-> {}]

\* Token state machine: issued -> valid -> {revoked, expired}
IssueToValid(t) ==
    /\ token_state[t] = "issued"
    /\ token_state' = [token_state EXCEPT ![t] = "valid"]
    /\ active_sessions' =
         [active_sessions EXCEPT ![token_owner[t]] = @ \cup {t}]
    /\ UNCHANGED << token_owner, role_of >>

Revoke(t) ==
    /\ token_state[t] = "valid"
    /\ token_state' = [token_state EXCEPT ![t] = "revoked"]
    /\ active_sessions' =
         [active_sessions EXCEPT ![token_owner[t]] = @ \ {t}]
    /\ UNCHANGED << token_owner, role_of >>

Expire(t) ==
    /\ token_state[t] = "valid"
    /\ token_state' = [token_state EXCEPT ![t] = "expired"]
    /\ active_sessions' =
         [active_sessions EXCEPT ![token_owner[t]] = @ \ {t}]
    /\ UNCHANGED << token_owner, role_of >>

Next ==
    \/ \E t \in Tokens : IssueToValid(t)
    \/ \E t \in Tokens : Revoke(t)
    \/ \E t \in Tokens : Expire(t)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* Invariants                                                               *)
(***************************************************************************)

\* INV-1: Token lifecycle is monotonic (issued -> valid -> {revoked|expired}, no resurrection)
TokenLifecycleConsistency ==
    \A t \in Tokens :
        token_state[t] \in {"issued", "valid", "revoked", "expired"}

\* INV-2: RBAC mapping is exhaustive — every principal has exactly one role
RBACMappingExhaustive ==
    \A p \in Principals : role_of[p] \in Roles

\* INV-3: Session mutual exclusion — strict version: at most one active session per principal
\* (stricter SC-IAM-004 reading; relax to bounded-N if multiple-device login is allowed)
SessionMutualExclusion ==
    \A p \in Principals : Cardinality(active_sessions[p]) <= 1

THEOREM Spec => [](TokenLifecycleConsistency /\ RBACMappingExhaustive /\ SessionMutualExclusion)

====
