//! Zenoh Session Management
//!
//! Handles Zenoh session lifecycle via NIF resources.
//!
//! ## STAMP Constraints
//! - SC-ZENOH-SES-001: Single session per node
//! - SC-ZENOH-SES-002: Auto-reconnect within 5s
//! - SC-ZENOH-SES-003: Graceful shutdown with drain

use crate::types::{SessionStatus, ZenohConfig, ZenohMessage, ZenohStats};
use rustler::{Atom, Encoder, Env, Error, NifResult as RNifResult, Resource, ResourceArc, Term};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::runtime::Runtime;
use zenoh::Config;
use zenoh::Session;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        connected,
        disconnected,
        timeout,
    }
}

/// Zenoh session wrapper for NIF resource management
pub struct ZenohSessionResource {
    session: Arc<Session>,
    runtime: Arc<Runtime>,
    config: ZenohConfig,
    created_at: Instant,
    stats: SessionStats,
}

// Implement Resource trait for rustler 0.37
impl Resource for ZenohSessionResource {}

/// Statistics tracking
struct SessionStats {
    messages_sent: AtomicU64,
    messages_received: AtomicU64,
    reconnect_count: AtomicU64,
    last_publish_latency_us: AtomicU64,
}

impl SessionStats {
    fn new() -> Self {
        Self {
            messages_sent: AtomicU64::new(0),
            messages_received: AtomicU64::new(0),
            reconnect_count: AtomicU64::new(0),
            last_publish_latency_us: AtomicU64::new(0),
        }
    }

    fn to_zenoh_stats(&self, uptime: Duration) -> ZenohStats {
        ZenohStats {
            messages_sent: self.messages_sent.load(Ordering::Relaxed),
            messages_received: self.messages_received.load(Ordering::Relaxed),
            reconnect_count: self.reconnect_count.load(Ordering::Relaxed),
            uptime_seconds: uptime.as_secs(),
            last_publish_latency_us: self.last_publish_latency_us.load(Ordering::Relaxed),
        }
    }
}

impl ZenohSessionResource {
    /// Get the tokio runtime for spawning async tasks
    /// Used by subscriber module for async subscription handling
    pub fn get_runtime(&self) -> Arc<Runtime> {
        self.runtime.clone()
    }

    /// Get the Zenoh session for creating subscribers/publishers
    /// Used by subscriber module for async subscription handling
    pub fn get_session(&self) -> Arc<Session> {
        self.session.clone()
    }

    pub fn new(config: ZenohConfig) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        // Create Tokio runtime for async operations
        let runtime = Arc::new(
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .expect("Failed to create Tokio runtime"),
        );

        // Build Zenoh config using JSON for zenoh 1.0 compatibility
        let mode_str = match config.mode.as_str() {
            "peer" => "peer",
            "router" => "router",
            _ => "client",
        };

        let config_json = serde_json::json!({
            "mode": mode_str,
            "connect": {
                "endpoints": config.connect.clone()
            },
            "scouting": {
                "multicast": {
                    "enabled": config.multicast_scouting
                }
            }
        });

        let zenoh_config: Config = serde_json::from_value(config_json)?;

        // Open session - zenoh 1.0 uses direct .await, no .res()
        let session = runtime.block_on(async {
            zenoh::open(zenoh_config).await
        })?;

        Ok(Self {
            session: Arc::new(session),
            runtime,
            config,
            created_at: Instant::now(),
            stats: SessionStats::new(),
        })
    }

    pub fn publish(&self, key: &str, payload: &[u8]) -> Result<Duration, Box<dyn std::error::Error + Send + Sync>> {
        let start = Instant::now();
        self.runtime.block_on(async {
            self.session.put(key, payload).await
        })?;
        let elapsed = start.elapsed();
        self.stats
            .last_publish_latency_us
            .store(elapsed.as_micros() as u64, Ordering::Relaxed);
        self.stats.messages_sent.fetch_add(1, Ordering::Relaxed);
        Ok(elapsed)
    }

    pub fn get(&self, key_expr: &str, timeout_ms: u64) -> Result<Vec<ZenohMessage>, Box<dyn std::error::Error + Send + Sync>> {
        self.runtime.block_on(async {
            let replies = self
                .session
                .get(key_expr)
                .timeout(Duration::from_millis(timeout_ms))
                .await?;

            let mut messages = Vec::new();
            while let Ok(reply) = replies.recv_async().await {
                if let Ok(sample) = reply.result() {
                    messages.push(ZenohMessage {
                        key: sample.key_expr().to_string(),
                        payload: sample.payload().to_bytes().to_vec(),
                        timestamp: sample.timestamp().map(|t| t.get_time().as_u64() as i64),
                        encoding: sample.encoding().to_string(),
                        source: None,
                    });
                }
            }
            Ok(messages)
        })
    }

    pub fn get_stats(&self) -> ZenohStats {
        self.stats.to_zenoh_stats(self.created_at.elapsed())
    }

    pub fn get_status(&self) -> SessionStatus {
        SessionStatus {
            connected: true, // TODO: Implement proper connection checking
            router_endpoint: self.config.connect.first().cloned(),
            session_id: format!("{:?}", self.session.zid()),
        }
    }
}

/// Open a new Zenoh session
/// Returns: {:ok, session_ref} | {:error, reason}

pub fn zenoh_open_session(env: Env, config_json: String) -> RNifResult<Term> {
    // SC-NIF-003: panic safety provided by lib::ffi_guard_term wrapping this call.
    let config: ZenohConfig = serde_json::from_str(&config_json)
        .map_err(|e| Error::Term(Box::new(format!("Invalid config: {}", e))))?;
    match ZenohSessionResource::new(config) {
        Ok(session) => Ok((atoms::ok(), ResourceArc::new(session)).encode(env)),
        Err(e) => Ok((atoms::error(), format!("{}", e)).encode(env)),
    }
}

/// Close a Zenoh session
/// Returns: :ok | {:error, reason}

pub fn zenoh_close_session(_session: ResourceArc<ZenohSessionResource>) -> Atom {
    // Session is automatically closed when ResourceArc is dropped
    atoms::ok()
}

/// Get session information
/// Returns: {:ok, info_map} | {:error, reason}

pub fn zenoh_session_info(
    env: Env,
    session: ResourceArc<ZenohSessionResource>,
) -> RNifResult<Term> {
    let stats = session.get_stats();
    Ok(stats.encode(env))
}

/// Get session connection status
/// Returns: {:ok, status_map}

pub fn zenoh_session_status(
    env: Env,
    session: ResourceArc<ZenohSessionResource>,
) -> RNifResult<Term> {
    let status = session.get_status();
    Ok(status.encode(env))
}

/// Query Zenoh storage with default timeout (10s)
/// Returns: {:ok, [messages]} | {:error, reason}

pub fn zenoh_get(
    env: Env,
    session: ResourceArc<ZenohSessionResource>,
    key_expr: String,
) -> RNifResult<Term> {
    zenoh_get_timeout_impl(env, session, key_expr, 10000)
}

/// Query Zenoh storage with custom timeout
/// Returns: {:ok, [messages]} | {:error, reason}

pub fn zenoh_get_timeout(
    env: Env,
    session: ResourceArc<ZenohSessionResource>,
    key_expr: String,
    timeout_ms: u64,
) -> RNifResult<Term> {
    zenoh_get_timeout_impl(env, session, key_expr, timeout_ms)
}

/// Internal implementation for get with timeout
fn zenoh_get_timeout_impl(
    env: Env,
    session: ResourceArc<ZenohSessionResource>,
    key_expr: String,
    timeout_ms: u64,
) -> RNifResult<Term> {
    match session.get(&key_expr, timeout_ms) {
        Ok(messages) => Ok((atoms::ok(), messages).encode(env)),
        Err(e) => Ok((atoms::error(), format!("{}", e)).encode(env)),
    }
}
