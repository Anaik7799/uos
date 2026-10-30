//// T17 version-specific MCP subscriptions. A subscription is bound to the
//// negotiated ProtocolProfile and the transport-bound principal at creation
//// time; reading or unsubscribing under a mismatched profile or a foreign
//// principal is refused. Each subscriber has a bounded pending-notification
//// queue.

import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/types.{
  type ProtocolProfile, type ToolError, NonRetryable, Retryable, ToolError,
}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

pub const max_pending_notifications = 128

pub const max_subscriptions = 1024

pub type SubscriptionKind {
  ResourceSubscription(uri: String)
  TaskSubscription(task_id: String)
}

pub type Subscription {
  Subscription(
    subscription_id: String,
    profile: ProtocolProfile,
    actor_id: String,
    workspace_root: String,
    kind: SubscriptionKind,
  )
}

pub type SubscriptionStore {
  SubscriptionStore(
    subscriptions: Dict(String, Subscription),
    notifications: Dict(String, List(String)),
  )
}

pub fn empty_store() -> SubscriptionStore {
  SubscriptionStore(dict.new(), dict.new())
}

pub fn subscribe(
  store: SubscriptionStore,
  profile: ProtocolProfile,
  principal: Principal,
  subscription_id: String,
  kind: SubscriptionKind,
) -> Result(SubscriptionStore, ToolError) {
  case dict.has_key(store.subscriptions, subscription_id) {
    True ->
      Error(ToolError(
        "SUBSCRIPTION_ID_ALREADY_EXISTS",
        "Subscription ID already registered",
        NonRetryable,
      ))
    False -> {
      use _ <- result.try(
        case dict.size(store.subscriptions) >= max_subscriptions {
          True ->
            Error(ToolError(
              "SUBSCRIPTION_CAPACITY_EXCEEDED",
              "Subscription store capacity exceeded",
              Retryable,
            ))
          False -> Ok(Nil)
        },
      )
      let subscription =
        Subscription(
          subscription_id: subscription_id,
          profile: profile,
          actor_id: principal.actor_id(principal),
          workspace_root: principal.workspace_root(principal),
          kind: kind,
        )
      Ok(SubscriptionStore(
        dict.insert(store.subscriptions, subscription_id, subscription),
        store.notifications,
      ))
    }
  }
}

pub fn read_subscription(
  store: SubscriptionStore,
  profile: ProtocolProfile,
  principal: Principal,
  subscription_id: String,
) -> Result(Subscription, ToolError) {
  case dict.get(store.subscriptions, subscription_id) {
    Error(_) ->
      Error(ToolError(
        "SUBSCRIPTION_NOT_FOUND",
        "No subscription registered with id " <> subscription_id,
        NonRetryable,
      ))
    Ok(subscription) -> authorize_subscription(profile, principal, subscription)
  }
}

fn authorize_subscription(
  profile: ProtocolProfile,
  principal: Principal,
  subscription: Subscription,
) -> Result(Subscription, ToolError) {
  case subscription.profile == profile {
    False ->
      Error(ToolError(
        "SUBSCRIPTION_PROFILE_MISMATCH",
        "Subscription "
          <> subscription.subscription_id
          <> " belongs to a different protocol profile",
        NonRetryable,
      ))
    True ->
      case
        subscription.actor_id == principal.actor_id(principal)
        && subscription.workspace_root == principal.workspace_root(principal)
      {
        False ->
          Error(ToolError(
            "CROSS_PRINCIPAL_SUBSCRIPTION_FORBIDDEN",
            "Subscription "
              <> subscription.subscription_id
              <> " belongs to another principal",
            NonRetryable,
          ))
        True -> Ok(subscription)
      }
  }
}

pub fn unsubscribe(
  store: SubscriptionStore,
  profile: ProtocolProfile,
  principal: Principal,
  subscription_id: String,
) -> Result(SubscriptionStore, ToolError) {
  use _ <- result.try(read_subscription(
    store,
    profile,
    principal,
    subscription_id,
  ))
  Ok(SubscriptionStore(
    dict.delete(store.subscriptions, subscription_id),
    dict.delete(store.notifications, subscription_id),
  ))
}

pub fn push_notification(
  store: SubscriptionStore,
  subscription_id: String,
  payload: String,
) -> Result(SubscriptionStore, ToolError) {
  let pending = pending_notifications_unchecked(store, subscription_id)
  case list.length(pending) >= max_pending_notifications {
    True ->
      Error(ToolError(
        "SUBSCRIPTION_BACKPRESSURE_LIMIT",
        "Pending notification queue exceeded "
          <> int.to_string(max_pending_notifications),
        Retryable,
      ))
    False ->
      Ok(SubscriptionStore(
        store.subscriptions,
        dict.insert(
          store.notifications,
          subscription_id,
          list.append(pending, [payload]),
        ),
      ))
  }
}

pub fn pending_notifications(
  store: SubscriptionStore,
  profile: ProtocolProfile,
  principal: Principal,
  subscription_id: String,
) -> Result(List(String), ToolError) {
  use _ <- result.try(read_subscription(
    store,
    profile,
    principal,
    subscription_id,
  ))
  Ok(pending_notifications_unchecked(store, subscription_id))
}

fn pending_notifications_unchecked(
  store: SubscriptionStore,
  subscription_id: String,
) -> List(String) {
  dict.get(store.notifications, subscription_id) |> result.unwrap([])
}
