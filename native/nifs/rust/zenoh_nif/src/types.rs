//! Type definitions and conversions for Zenoh NIF
//!
//! Provides Elixir-compatible type wrappers for Zenoh concepts.

use rustler::{Encoder, Env, NifStruct, Term};
use serde::{Deserialize, Serialize};

/// Zenoh configuration from Elixir
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "Indrajaal.Native.Zenoh.Config"]
pub struct ZenohConfig {
    /// Endpoints to connect to (e.g., ["tcp/zenoh:7447"])
    pub connect: Vec<String>,
    /// Mode: "peer", "client", or "router"
    pub mode: String,
    /// Enable multicast scouting
    pub multicast_scouting: bool,
}

impl Default for ZenohConfig {
    fn default() -> Self {
        Self {
            connect: vec!["tcp/localhost:7447".to_string()],
            mode: "client".to_string(),
            multicast_scouting: true,
        }
    }
}

/// Message received from Zenoh subscription
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "Indrajaal.Native.Zenoh.Message"]
pub struct ZenohMessage {
    /// Key expression the message was published on
    pub key: String,
    /// Message payload as binary
    pub payload: Vec<u8>,
    /// Timestamp (HLC if available)
    pub timestamp: Option<i64>,
    /// Encoding type
    pub encoding: String,
    /// Source locator (if available)
    pub source: Option<String>,
}

/// Session statistics
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "Indrajaal.Native.Zenoh.Stats"]
pub struct ZenohStats {
    /// Number of messages published
    pub messages_sent: u64,
    /// Number of messages received
    pub messages_received: u64,
    /// Number of reconnection attempts
    pub reconnect_count: u64,
    /// Session uptime in seconds
    pub uptime_seconds: u64,
    /// Last publish latency in microseconds
    pub last_publish_latency_us: u64,
}

/// Session status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionStatus {
    pub connected: bool,
    pub router_endpoint: Option<String>,
    pub session_id: String,
}

impl Encoder for SessionStatus {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let connected = self.connected.encode(env);
        let router_endpoint = self.router_endpoint.clone().encode(env);
        let session_id = self.session_id.clone().encode(env);

        rustler::types::map::map_new(env)
            .map_put(rustler::types::atom::Atom::from_str(env, "connected").unwrap(), connected)
            .ok()
            .unwrap()
            .map_put(rustler::types::atom::Atom::from_str(env, "router_endpoint").unwrap(), router_endpoint)
            .ok()
            .unwrap()
            .map_put(rustler::types::atom::Atom::from_str(env, "session_id").unwrap(), session_id)
            .ok()
            .unwrap()
    }
}

/// Batch publish request
#[derive(Debug, Clone, NifStruct)]
#[module = "Indrajaal.Native.Zenoh.BatchRequest"]
pub struct BatchPublishRequest {
    pub key: String,
    pub payload: Vec<u8>,
}

/// Result type for NIF functions (available for future use)
#[allow(dead_code)]
pub type NifResult<T> = Result<T, rustler::Error>;
