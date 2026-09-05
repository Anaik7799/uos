//! Zenoh NIF — Native Gleam bindings to Zenoh pub/sub mesh (SC-ZENOH-001)
//!
//! Provides direct BEAM NIF access to Zenoh session management, publish,
//! subscribe, and get operations. Replaces the Elixir Rustler bridge.
//!
//! STAMP: SC-ZENOH-001 (NIF loaded on all nodes), SC-ZMOF-001 (sole transport)

use once_cell::sync::OnceCell;
use rustler::{Atom, Encoder, Env, NifResult, Term};
use std::sync::Mutex;
use std::time::Duration;

// Global Zenoh session — shared across all NIF calls
static ZENOH_SESSION: OnceCell<Mutex<Option<zenoh::Session>>> = OnceCell::new();
static ZENOH_RUNTIME: OnceCell<tokio::runtime::Runtime> = OnceCell::new();

fn get_runtime() -> &'static tokio::runtime::Runtime {
    ZENOH_RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("Failed to create Zenoh tokio runtime")
    })
}

/// Open a Zenoh session (SC-ZENOH-001)
/// Config JSON: "{}" for default, or {"connect":{"endpoints":["tcp/localhost:7447"]}}
#[rustler::nif(schedule = "DirtyCpu")]
fn zenoh_open(config_json: String) -> NifResult<String> {
    let rt = get_runtime();

    let result = rt.block_on(async {
        // Parse config
        let config = if config_json.is_empty() || config_json == "{}" {
            zenoh::Config::default()
        } else {
            match serde_json::from_str::<serde_json::Value>(&config_json) {
                Ok(val) => {
                    let mut config = zenoh::Config::default();
                    // Set connect endpoints if provided
                    if let Some(endpoints) = val.get("connect")
                        .and_then(|c| c.get("endpoints"))
                        .and_then(|e| e.as_array())
                    {
                        let eps: Vec<String> = endpoints.iter()
                            .filter_map(|e| e.as_str().map(|s| s.to_string()))
                            .collect();
                        if !eps.is_empty() {
                            // Try setting via JSON merge
                            let connect_json = serde_json::json!({
                                "connect": {"endpoints": eps}
                            });
                            if let Ok(merged) = serde_json::to_string(&connect_json) {
                                let _ = config.insert_json5("connect", &format!("{{\"endpoints\":{}}}", serde_json::to_string(&eps).unwrap_or_default()));
                            }
                        }
                    }
                    config
                }
                Err(_) => zenoh::Config::default(),
            }
        };

        match zenoh::open(config).await {
            Ok(session) => {
                // Store session globally
                let _ = ZENOH_SESSION.set(Mutex::new(Some(session)));
                Ok(serde_json::json!({
                    "status": "connected",
                    "endpoint": "tcp/localhost:7447"
                }).to_string())
            }
            Err(e) => {
                Err(format!("zenoh_open_failed: {}", e))
            }
        }
    });

    match result {
        Ok(json) => Ok(json),
        Err(e) => Ok(serde_json::json!({"status": "error", "error": e}).to_string()),
    }
}

/// Publish data to a Zenoh key expression
#[rustler::nif(schedule = "DirtyCpu")]
fn zenoh_put(key: String, payload: String) -> NifResult<String> {
    let rt = get_runtime();

    let result: Result<String, String> = rt.block_on(async {
        let session_lock = ZENOH_SESSION.get()
            .ok_or_else(|| "zenoh_session_not_open".to_string())?;
        let guard = session_lock.lock().map_err(|e| format!("lock: {}", e))?;
        let session = guard.as_ref()
            .ok_or_else(|| "zenoh_session_none".to_string())?;

        session.put(&key, payload.as_bytes())
            .await
            .map_err(|e| format!("zenoh_put_failed: {}", e))?;

        Ok(serde_json::json!({"status": "ok", "key": key}).to_string())
    });

    match result {
        Ok(json) => Ok(json),
        Err(e) => Ok(serde_json::json!({"status": "error", "error": e}).to_string()),
    }
}

/// Get data from a Zenoh key expression
#[rustler::nif(schedule = "DirtyCpu")]
fn zenoh_get(key: String) -> NifResult<String> {
    let rt = get_runtime();

    let result: Result<String, String> = rt.block_on(async {
        let session_lock = ZENOH_SESSION.get()
            .ok_or_else(|| "zenoh_session_not_open".to_string())?;
        let guard = session_lock.lock().map_err(|e| format!("lock: {}", e))?;
        let session = guard.as_ref()
            .ok_or_else(|| "zenoh_session_none".to_string())?;

        let replies = session.get(&key)
            .await
            .map_err(|e| format!("zenoh_get_failed: {}", e))?;

        let mut results = Vec::new();
        while let Ok(reply) = replies.recv_async().await {
            if let Ok(sample) = reply.result() {
                let payload = String::from_utf8_lossy(&sample.payload().to_bytes()).to_string();
                results.push(serde_json::json!({
                    "key": sample.key_expr().as_str(),
                    "value": payload,
                }));
            }
        }

        Ok(serde_json::to_string(&results).unwrap_or_else(|_| "[]".to_string()))
    });

    match result {
        Ok(json) => Ok(json),
        Err(e) => Ok(serde_json::json!({"status": "error", "error": e}).to_string()),
    }
}

/// Check Zenoh session status
#[rustler::nif]
fn zenoh_status() -> NifResult<String> {
    let connected = ZENOH_SESSION.get()
        .map(|lock| lock.lock().ok().map(|g| g.is_some()).unwrap_or(false))
        .unwrap_or(false);

    Ok(serde_json::json!({
        "connected": connected,
        "endpoint": if connected { "tcp/localhost:7447" } else { "none" },
    }).to_string())
}

/// Close Zenoh session
#[rustler::nif(schedule = "DirtyCpu")]
fn zenoh_close() -> NifResult<String> {
    if let Some(lock) = ZENOH_SESSION.get() {
        if let Ok(mut guard) = lock.lock() {
            *guard = None;
        }
    }
    Ok(serde_json::json!({"status": "closed"}).to_string())
}
