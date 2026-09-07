//// Typed C04/C05 action-consumer boundary.
////
//// A caller-supplied policy snapshot and authorization reference are inputs,
//// never credentials minted here. Before an injected effect is invoked, the
//// consumer checks the exact session candidate, resource, epoch, policy and
//// command against current session-sync state. Integration and runtime claims
//// are different resources. Board messages, model output and terminal ACKs are
//// absent from the authority type and cannot increase authority.
////
//// Executor state binds operation IDs to exact requests and outcomes. Unknown
//// outcomes are retained for reconciliation and never retried automatically.
//// This state is intentionally explicit: production use still needs an admitted
//// durable action-attempt store and destination idempotency before privileged
//// integration or runtime effects are enabled.

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/session_sync as sync

pub type IntegrationOperation {
  InspectIntegration
  ApplyPreservingMerge
}

pub type RuntimeOperation {
  ObserveRuntime
  DiagnoseRuntime
  MitigateRuntime
  RollbackRuntime
}

pub type IntegrationCommand {
  IntegrationCommand(
    candidate_revision: String,
    operation: IntegrationOperation,
    evidence_refs: List(String),
  )
}

pub type RuntimeAction {
  RuntimeAction(
    service: String,
    deployed_revision: String,
    operation: RuntimeOperation,
    rollback_ref: Option(String),
    postcheck_ref: String,
  )
}

pub type ActionCommand {
  Integration(IntegrationCommand)
  Runtime(RuntimeAction)
}

pub type Request {
  Request(
    operation_id: String,
    session: String,
    epoch: Int,
    command: ActionCommand,
  )
}

pub type Permission {
  AllowIntegration(session: String, operation: IntegrationOperation)
  AllowRuntime(session: String, service: String, operation: RuntimeOperation)
}

pub type CandidateDisposition {
  CandidateVerified
  CandidateRejected
  CandidateStale
  CandidateUnknown
}

/// Invocation-scoped candidate evidence supplied by the trusted policy owner.
/// Times use the coordinator's boot-relative monotonic microsecond domain.
pub type CandidateReceipt {
  CandidateReceipt(
    revision: String,
    disposition: CandidateDisposition,
    observed_boot_us: Int,
    expires_boot_us: Int,
    runtime_evidence_ref: String,
    formal_evidence_ref: String,
  )
}

/// This is a snapshot supplied by a separately trusted policy consumer. The
/// constructor does not authenticate its contents.
pub type PolicySnapshot {
  PolicySnapshot(
    version: String,
    candidate: CandidateReceipt,
    permissions: List(Permission),
    expires_boot_us: Int,
  )
}

/// Exact, externally issued operation authorization. `authority_ref` is an
/// opaque reference for the owning authority to resolve; this module does not
/// treat possession of the record as authenticated identity.
pub type Authorization {
  Authorization(
    operation_id: String,
    principal: String,
    resource: String,
    epoch: Int,
    candidate_revision: String,
    policy_version: String,
    command: ActionCommand,
    expires_boot_us: Int,
    authority_ref: String,
  )
}

pub type EffectOutcome {
  EffectApplied(receipt_ref: String)
  EffectAlreadyApplied(receipt_ref: String)
  EffectRejected(reason: String)
  EffectUnknown(reconciliation_ref: String)
}

pub type AttemptOutcome {
  Executed(outcome: EffectOutcome, cached: Bool)
  Refused(reason: String)
}

pub opaque type Permit {
  Permit(request: Request, resource: String, checked_boot_us: Int)
}

type SeenAttempt {
  SeenAttempt(request: Request, outcome: EffectOutcome)
}

pub opaque type Executor {
  Executor(seen: Dict(String, SeenAttempt))
}

pub fn new_executor() -> Executor {
  Executor(dict.new())
}

pub fn scope(command: ActionCommand) -> String {
  case command {
    Integration(_) -> "integration/main"
    Runtime(RuntimeAction(service, ..)) -> "runtime:" <> service
  }
}

pub fn candidate_revision(command: ActionCommand) -> String {
  case command {
    Integration(IntegrationCommand(candidate, ..)) -> candidate
    Runtime(RuntimeAction(_, candidate, ..)) -> candidate
  }
}

pub fn permitted_operation_id(permit: Permit) -> String {
  permit.request.operation_id
}

pub fn permitted_command(permit: Permit) -> ActionCommand {
  permit.request.command
}

pub fn permitted_resource(permit: Permit) -> String {
  permit.resource
}

fn require(condition: Bool, error: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(error)
  }
}

fn bounded(value: String, maximum: Int) -> Bool {
  value != ""
  && string.length(value) <= maximum
  && !string.contains(value, "\u{0000}")
}

fn identifier(value: String) -> Bool {
  bounded(value, 128)
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:",
      character,
    )
  })
}

fn valid_refs(refs: List(String)) -> Bool {
  !list.is_empty(refs)
  && list.length(refs) <= 32
  && list.all(refs, fn(reference) { bounded(reference, 1024) })
}

fn command_valid(command: ActionCommand) -> Bool {
  case command {
    Integration(IntegrationCommand(candidate, _, evidence_refs)) ->
      bounded(candidate, 512) && valid_refs(evidence_refs)
    Runtime(RuntimeAction(
      service,
      candidate,
      operation,
      rollback_ref,
      postcheck_ref,
    )) -> {
      let rollback_valid = case operation {
        MitigateRuntime | RollbackRuntime ->
          case rollback_ref {
            Some(reference) -> bounded(reference, 1024)
            None -> False
          }
        ObserveRuntime | DiagnoseRuntime ->
          case rollback_ref {
            Some(reference) -> bounded(reference, 1024)
            None -> True
          }
      }
      identifier(service)
      && bounded(candidate, 512)
      && bounded(postcheck_ref, 1024)
      && rollback_valid
    }
  }
}

fn privileged(command: ActionCommand) -> Bool {
  case command {
    Integration(IntegrationCommand(_, ApplyPreservingMerge, _)) -> True
    Runtime(RuntimeAction(_, _, MitigateRuntime, _, _)) -> True
    Runtime(RuntimeAction(_, _, RollbackRuntime, _, _)) -> True
    Integration(IntegrationCommand(_, InspectIntegration, _)) -> False
    Runtime(RuntimeAction(_, _, ObserveRuntime, _, _)) -> False
    Runtime(RuntimeAction(_, _, DiagnoseRuntime, _, _)) -> False
  }
}

fn policy_allows(policy: PolicySnapshot, request: Request) -> Bool {
  case request.command {
    Integration(IntegrationCommand(_, operation, _)) ->
      list.contains(
        policy.permissions,
        AllowIntegration(request.session, operation),
      )
    Runtime(RuntimeAction(service, _, operation, _, _)) ->
      list.contains(
        policy.permissions,
        AllowRuntime(request.session, service, operation),
      )
  }
}

fn candidate_valid(
  receipt: CandidateReceipt,
  expected_revision: String,
  now: Int,
) -> Bool {
  receipt.revision == expected_revision
  && receipt.disposition == CandidateVerified
  && receipt.observed_boot_us >= 0
  && receipt.observed_boot_us <= now
  && now < receipt.expires_boot_us
  && bounded(receipt.runtime_evidence_ref, 1024)
  && bounded(receipt.formal_evidence_ref, 1024)
}

/// Validate the complete action tuple against the observed session snapshot.
/// A permit is invocation-local and cannot be constructed outside this module.
pub fn authorize(
  state: sync.State,
  boot: String,
  now: Int,
  request: Request,
  policy: PolicySnapshot,
  authorization: Authorization,
) -> Result(Permit, String) {
  let resource = scope(request.command)
  let candidate = candidate_revision(request.command)
  use _ <- result.try(require(
    identifier(request.operation_id) && identifier(request.session),
    "invalid operation or session ID",
  ))
  use _ <- result.try(require(request.epoch > 0, "lease epoch must be positive"))
  use _ <- result.try(require(
    command_valid(request.command),
    "invalid or incomplete typed action",
  ))
  use _ <- result.try(require(
    !privileged(request.command),
    "privileged action blocked until an admitted authority verifier is connected",
  ))
  use _ <- result.try(require(
    bounded(policy.version, 256)
      && now < policy.expires_boot_us
      && candidate_valid(policy.candidate, candidate, now),
    "policy snapshot is invalid or expired",
  ))
  use _ <- result.try(require(
    authorization.operation_id == request.operation_id
      && authorization.principal == request.session
      && authorization.resource == resource
      && authorization.epoch == request.epoch
      && authorization.candidate_revision == candidate
      && authorization.policy_version == policy.version
      && authorization.command == request.command
      && now < authorization.expires_boot_us
      && bounded(authorization.authority_ref, 1024),
    "explicit authorization does not match the exact action",
  ))
  use _ <- result.try(require(
    policy_allows(policy, request),
    "current policy does not allow this principal, target, and operation",
  ))
  use session <- result.try(
    dict.get(state.sessions, request.session)
    |> result.replace_error("session is not registered"),
  )
  use _ <- result.try(require(
    session.revision == candidate,
    "session candidate no longer matches the authorized revision",
  ))
  use _ <- result.try(sync.check(
    state,
    request.session,
    resource,
    request.epoch,
    boot,
    now,
  ))
  Ok(Permit(request, resource, now))
}

/// Execute at most one injected effect for an unseen operation ID. Matching
/// replay returns the retained outcome, including Unknown, without invoking the
/// effect. A conflicting body under the same ID always fails closed.
pub fn attempt(
  executor: Executor,
  state: sync.State,
  boot: String,
  now: Int,
  request: Request,
  policy: PolicySnapshot,
  authorization: Authorization,
  effect: fn(Permit) -> EffectOutcome,
) -> #(Executor, AttemptOutcome) {
  case dict.get(executor.seen, request.operation_id) {
    Ok(seen) if seen.request == request -> #(
      executor,
      Executed(seen.outcome, True),
    )
    Ok(_) -> #(
      executor,
      Refused("operation ID already belongs to a different action"),
    )
    Error(_) ->
      case authorize(state, boot, now, request, policy, authorization) {
        Error(reason) -> #(executor, Refused(reason))
        Ok(permit) -> {
          let outcome = effect(permit)
          let next =
            Executor(dict.insert(
              executor.seen,
              request.operation_id,
              SeenAttempt(request, outcome),
            ))
          #(next, Executed(outcome, False))
        }
      }
  }
}

/// Observe and consume against the durable current session journal. The native
/// session transaction lock stays held through `attempt`, including the one
/// injected callback invocation, so a competing release/renew/claim cannot
/// change the local cooperative fence between the check and callback entry.
/// The callback must itself be bounded and must not re-enter this state root.
pub fn consume_current(
  root: String,
  executor: Executor,
  request: Request,
  policy: PolicySnapshot,
  authorization: Authorization,
  effect: fn(Permit) -> EffectOutcome,
) -> Result(#(Executor, AttemptOutcome), String) {
  let reply = process.new_subject()
  use _ <- result.try(
    sync.observe(root, fn(state, boot, now) {
      let attempted =
        attempt(
          executor,
          state,
          boot,
          now,
          request,
          policy,
          authorization,
          effect,
        )
      process.send(reply, attempted)
      Ok(
        json.object([
          #("operation_id", json.string(request.operation_id)),
          #("consumer", json.string("uos-action-boundary/current-v1")),
        ]),
      )
    }),
  )
  process.receive(reply, 1000)
  |> result.replace_error("action consumer did not return an attempt result")
}

/// Safe executable adapter: observe the durable current fence and report what
/// would be allowed. It never invokes an effect and never upgrades its
/// caller-supplied policy/authorization records into authenticated authority.
pub fn observe_dry_run(
  root: String,
  request: Request,
  policy: PolicySnapshot,
  authorization: Authorization,
) -> Result(String, String) {
  sync.observe(root, fn(state, boot, now) {
    use permit <- result.try(authorize(
      state,
      boot,
      now,
      request,
      policy,
      authorization,
    ))
    Ok(
      json.object([
        #("ok", json.bool(True)),
        #("dry_run", json.bool(True)),
        #("effect_invoked", json.bool(False)),
        #("operation_id", json.string(permitted_operation_id(permit))),
        #("resource", json.string(permitted_resource(permit))),
        #(
          "candidate_revision",
          json.string(candidate_revision(request.command)),
        ),
        #("checked_boot_us", json.int(permit.checked_boot_us)),
        #(
          "authority",
          json.string(
            "caller-supplied references validated; no authenticated authority or effect",
          ),
        ),
      ]),
    )
  })
}
