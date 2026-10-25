//! Zenoh Subscriber Functions
//!
//! Handles subscriptions to Zenoh topics with full async message delivery.
//!
//! ## STAMP Constraints
//! - SC-ZENOH-SUB-001: Async message delivery via tokio task
//! - SC-ZENOH-SUB-002: Messages buffered in bounded channel (1000 msgs)
//! - SC-ZENOH-SUB-003: Graceful unsubscribe with active flag
//! - SC-ZTEST-003: Publish latency < 10ms (subscriber receive path)

use crate::ZenohSessionResource;
use crate::types::ZenohMessage;
use crossbeam_channel::{bounded, Receiver, Sender};
use parking_lot::RwLock;
use rustler::{Atom, Encoder, Env, LocalPid, NifResult, Resource, ResourceArc, Term};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::runtime::Runtime;
use zenoh::Session;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        zenoh_message,
        subscription_error,
    }
}

/// Subscription statistics for observability (SC-ZTEST-003)
struct SubscriptionStats {
    messages_received: AtomicU64,
    messages_dropped: AtomicU64,
}

impl SubscriptionStats {
    fn new() -> Self {
        Self {
            messages_received: AtomicU64::new(0),
            messages_dropped: AtomicU64::new(0),
        }
    }
}

/// Subscription resource wrapping a Zenoh subscriber
pub struct ZenohSubscriptionResource {
    /// Receiver for messages from the subscription
    receiver: Receiver<ZenohMessage>,
    /// Key expression this subscription is for
    key_expr: String,
    /// Whether the subscription is active
    active: Arc<RwLock<bool>>,
    /// Runtime reference for cleanup
    #[allow(dead_code)]
    runtime: Arc<Runtime>,
    /// Statistics tracking
    stats: Arc<SubscriptionStats>,
}

// Implement Resource trait for rustler 0.37
impl Resource for ZenohSubscriptionResource {}

impl ZenohSubscriptionResource {
    /// Poll for received messages (non-blocking)
    /// SC-ZENOH-SUB-001: Returns up to max_count messages without blocking
    pub fn poll_messages(&self, max_count: usize) -> Vec<ZenohMessage> {
        let mut messages = Vec::with_capacity(max_count);
        for _ in 0..max_count {
            match self.receiver.try_recv() {
                Ok(msg) => messages.push(msg),
                Err(_) => break,
            }
        }
        messages
    }

    /// Get subscription statistics
    pub fn get_stats(&self) -> (u64, u64) {
        (
            self.stats.messages_received.load(Ordering::Relaxed),
            self.stats.messages_dropped.load(Ordering::Relaxed),
        )
    }

    /// Get the key expression this subscription is for
    pub fn key_expr(&self) -> &str {
        &self.key_expr
    }
}

/// Spawn the async subscription task
/// This runs in the tokio runtime and forwards messages to the channel
fn spawn_subscription_task(
    runtime: &Arc<Runtime>,
    session: Arc<Session>,
    key_expr: String,
    sender: Sender<ZenohMessage>,
    active: Arc<RwLock<bool>>,
    stats: Arc<SubscriptionStats>,
) {
    let key_expr_clone = key_expr.clone();

    runtime.spawn(async move {
        // Declare subscriber on the key expression
        // SC-ZENOH-SUB-001: Async subscription declaration
        let subscriber = match session.declare_subscriber(&key_expr_clone).await {
            Ok(sub) => sub,
            Err(e) => {
                log::error!("Failed to create Zenoh subscriber for {}: {}", key_expr_clone, e);
                return;
            }
        };

        log::info!("Zenoh subscriber active for key expression: {}", key_expr_clone);

        // Message receive loop
        // SC-ZENOH-SUB-002: Messages buffered via crossbeam channel
        loop {
            // Check if subscription is still active
            if !*active.read() {
                log::info!("Subscription deactivated for: {}", key_expr_clone);
                break;
            }

            // Use recv_async with a small timeout to allow checking active flag
            tokio::select! {
                result = subscriber.recv_async() => {
                    match result {
                        Ok(sample) => {
                            // Convert Zenoh sample to our message type
                            let msg = ZenohMessage {
                                key: sample.key_expr().to_string(),
                                payload: sample.payload().to_bytes().to_vec(),
                                timestamp: sample.timestamp().map(|t| t.get_time().as_u64() as i64),
                                encoding: sample.encoding().to_string(),
                                source: Some(format!("{:?}", sample.congestion_control())),
                            };

                            // Try to send to channel (non-blocking)
                            match sender.try_send(msg) {
                                Ok(_) => {
                                    stats.messages_received.fetch_add(1, Ordering::Relaxed);
                                }
                                Err(crossbeam_channel::TrySendError::Full(_)) => {
                                    // Channel full - drop message but log
                                    stats.messages_dropped.fetch_add(1, Ordering::Relaxed);
                                    log::warn!("Subscription channel full for {}, message dropped", key_expr_clone);
                                }
                                Err(crossbeam_channel::TrySendError::Disconnected(_)) => {
                                    // Receiver dropped - stop subscription
                                    log::info!("Subscription channel disconnected for: {}", key_expr_clone);
                                    break;
                                }
                            }
                        }
                        Err(e) => {
                            log::error!("Error receiving from subscriber {}: {}", key_expr_clone, e);
                            // Brief backoff on error
                            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                        }
                    }
                }
                // Periodic check for active flag (every 100ms)
                _ = tokio::time::sleep(tokio::time::Duration::from_millis(100)) => {
                    continue;
                }
            }
        }

        // Cleanup: undeclare subscriber
        if let Err(e) = subscriber.undeclare().await {
            log::warn!("Error undeclaring subscriber for {}: {}", key_expr_clone, e);
        }
        log::info!("Zenoh subscriber stopped for: {}", key_expr_clone);
    });
}

/// Subscribe to a key expression
/// Creates an async subscription that forwards messages to a polling channel
/// Returns: {:ok, subscription_ref} | {:error, reason}
///
/// SC-ZENOH-SUB-001: Async message delivery
/// SC-ZENOH-SUB-002: Messages buffered in bounded channel
pub fn zenoh_subscribe(
    env: Env,
    session: ResourceArc<ZenohSessionResource>,
    key_expr: String,
    _callback_pid: LocalPid,
) -> NifResult<Term> {
    // Create bounded channel for messages (buffer 1000 messages)
    // SC-ZENOH-SUB-002: Bounded buffer prevents memory exhaustion
    let (sender, receiver): (Sender<ZenohMessage>, Receiver<ZenohMessage>) = bounded(1000);
    let active = Arc::new(RwLock::new(true));
    let stats = Arc::new(SubscriptionStats::new());

    // Get session internals for spawning the subscription task
    // Note: ResourceArc<T> implements Deref<Target=T> in rustler 0.37
    // We use as_ref() to get &ZenohSessionResource
    let session_ref: &ZenohSessionResource = &session;
    let runtime = session_ref.get_runtime();
    let zenoh_session = session_ref.get_session();

    // Spawn the async subscription task
    spawn_subscription_task(
        &runtime,
        zenoh_session,
        key_expr.clone(),
        sender,
        active.clone(),
        stats.clone(),
    );

    let subscription = ZenohSubscriptionResource {
        receiver,
        key_expr,
        active,
        runtime,
        stats,
    };

    Ok((atoms::ok(), ResourceArc::new(subscription)).encode(env))
}

/// Unsubscribe from a key expression
/// Returns: :ok

pub fn zenoh_unsubscribe(subscription: ResourceArc<ZenohSubscriptionResource>) -> Atom {
    // Mark subscription as inactive
    *subscription.active.write() = false;
    atoms::ok()
}

/// Poll for received messages (non-blocking)
/// Returns: {:ok, [messages]}

pub fn zenoh_poll_messages(
    env: Env,
    subscription: ResourceArc<ZenohSubscriptionResource>,
    max_messages: usize,
) -> NifResult<Term> {
    let messages = subscription.poll_messages(max_messages);
    Ok((atoms::ok(), messages).encode(env))
}

/// Get subscription statistics
/// Returns: {:ok, %{messages_received: n, messages_dropped: n, key_expr: str}}
pub fn zenoh_subscription_stats(
    env: Env,
    subscription: ResourceArc<ZenohSubscriptionResource>,
) -> NifResult<Term> {
    let (received, dropped) = subscription.get_stats();
    let key_expr = subscription.key_expr().to_string();

    // Build result map
    let map = rustler::types::map::map_new(env)
        .map_put(
            rustler::types::atom::Atom::from_str(env, "messages_received").unwrap(),
            received.encode(env),
        )
        .ok()
        .unwrap()
        .map_put(
            rustler::types::atom::Atom::from_str(env, "messages_dropped").unwrap(),
            dropped.encode(env),
        )
        .ok()
        .unwrap()
        .map_put(
            rustler::types::atom::Atom::from_str(env, "key_expr").unwrap(),
            key_expr.encode(env),
        )
        .ok()
        .unwrap();

    Ok((atoms::ok(), map).encode(env))
}
