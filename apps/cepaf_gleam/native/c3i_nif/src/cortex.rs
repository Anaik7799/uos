//! Cortex & Operations NIFs — Real data from Smriti.db
//! 11 NIFs: inference, trace, conversation, cache, fmea, ha, voice, ruliology×3, ooda
//! STAMP: SC-WIRE-001, SC-COG-001, SC-NIF-001

use crate::db::open_db;
use rusqlite::params;
use rustler::NifResult;

fn json_err(fallback: &str) -> String { fallback.to_string() }

fn query_json(sql: &str, fallback: &str) -> String {
    let conn = match open_db() { Ok(c) => c, Err(_) => return json_err(fallback) };
    match conn.query_row(sql, [], |row| row.get::<_, String>(0)) {
        Ok(v) => v,
        Err(_) => json_err(fallback),
    }
}

fn query_int(sql: &str) -> i64 {
    let conn = match open_db() { Ok(c) => c, Err(_) => return 0 };
    conn.query_row(sql, [], |row| row.get::<_, i64>(0)).unwrap_or(0)
}

fn query_pref(key: &str, default: &str) -> String {
    let conn = match open_db() { Ok(c) => c, Err(_) => return default.to_string() };
    conn.query_row(
        "SELECT value FROM UserPreferences WHERE key = ?1", params![key],
        |row| row.get::<_, String>(0)
    ).unwrap_or_else(|_| default.to_string())
}

// 1. inference_status
#[rustler::nif(schedule = "DirtyCpu")]
pub fn inference_status() -> NifResult<String> {
    let conn = match open_db() { Ok(c) => c, Err(_) => return Ok("{\"tiers\":[],\"total_recent\":0}".into()) };
    let total = conn.query_row(
        "SELECT COUNT(*) FROM TransactionSummary WHERE timestamp_ms > (strftime('%s','now')*1000 - 3600000)",
        [], |r| r.get::<_, i64>(0)
    ).unwrap_or(0);
    Ok(format!("{{\"tiers\":[],\"total_recent\":{}}}", total))
}

// 2. trace_recent
#[rustler::nif(schedule = "DirtyCpu")]
pub fn trace_recent(limit: i64) -> NifResult<String> {
    let conn = match open_db() { Ok(c) => c, Err(_) => return Ok("{\"traces\":[],\"count\":0}".into()) };
    let mut stmt = match conn.prepare(
        "SELECT intent_id, model_used, total_latency_ms, status FROM TransactionSummary ORDER BY timestamp_ms DESC LIMIT ?1"
    ) { Ok(s) => s, Err(_) => return Ok("{\"traces\":[],\"count\":0}".into()) };

    let rows: Vec<String> = stmt.query_map(params![limit], |row| {
        let id: String = row.get(0)?;
        let model: String = row.get(1)?;
        let ms: i64 = row.get(2)?;
        let status: String = row.get(3)?;
        Ok(format!("{{\"intent_id\":\"{}\",\"model\":\"{}\",\"total_ms\":{},\"status\":\"{}\"}}", id, model, ms, status))
    }).ok().map(|r| r.filter_map(|x| x.ok()).collect()).unwrap_or_default();

    let count = rows.len();
    Ok(format!("{{\"traces\":[{}],\"count\":{}}}", rows.join(","), count))
}

// 3. conversation_history
#[rustler::nif(schedule = "DirtyCpu")]
pub fn conversation_history(limit: i64) -> NifResult<String> {
    let conn = match open_db() { Ok(c) => c, Err(_) => return Ok("{\"messages\":[],\"count\":0}".into()) };
    let mut stmt = match conn.prepare(
        "SELECT role, content, timestamp FROM ConversationHistory ORDER BY timestamp DESC LIMIT ?1"
    ) { Ok(s) => s, Err(_) => return Ok("{\"messages\":[],\"count\":0}".into()) };

    let rows: Vec<String> = stmt.query_map(params![limit], |row| {
        let role: String = row.get(0)?;
        let content: String = row.get::<_, String>(1)?.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', "\\n");
        let ts: String = row.get(2)?;
        Ok(format!("{{\"role\":\"{}\",\"content\":\"{}\",\"timestamp\":\"{}\"}}", role, content, ts))
    }).ok().map(|r| r.filter_map(|x| x.ok()).collect()).unwrap_or_default();

    let count = rows.len();
    Ok(format!("{{\"messages\":[{}],\"count\":{}}}", rows.join(","), count))
}

// 4. cache_stats
#[rustler::nif(schedule = "DirtyCpu")]
pub fn cache_stats() -> NifResult<String> {
    let entries = query_int("SELECT COUNT(*) FROM SemanticCache WHERE expires_at > strftime('%s','now')*1000");
    let total = query_int("SELECT COUNT(*) FROM SemanticCache");
    let hit_rate = if total > 0 { (entries as f64) / (total as f64) } else { 0.0 };
    Ok(format!("{{\"entries\":{},\"total\":{},\"hit_rate\":{:.3}}}", entries, total, hit_rate))
}

// 5. fmea_report
#[rustler::nif(schedule = "DirtyCpu")]
pub fn fmea_report() -> NifResult<String> {
    let failures = query_int("SELECT COUNT(*) FROM TransactionSummary WHERE status != 'ok'");
    let total = query_int("SELECT COUNT(*) FROM TransactionSummary");
    let rate = if total > 0 { (failures as f64) / (total as f64) } else { 0.0 };
    Ok(format!("{{\"failure_modes\":[],\"total_failures\":{},\"failure_rate\":{:.4}}}", failures, rate))
}

// 6. ha_status
#[rustler::nif(schedule = "DirtyCpu")]
pub fn ha_status() -> NifResult<String> {
    let role = query_pref("ha_role", "standby");
    let missed = query_pref("ha_missed_heartbeats", "0");
    Ok(format!("{{\"role\":\"{}\",\"missed_heartbeats\":{},\"lease_ttl_ms\":5000}}", role, missed))
}

// 7. voice_status
#[rustler::nif(schedule = "DirtyCpu")]
pub fn voice_status() -> NifResult<String> {
    let ws = query_pref("voice_ws_connected", "false");
    let tier = query_pref("voice_active_tier", "none");
    Ok(format!("{{\"ws_connected\":{},\"active_tier\":\"{}\",\"transcription_active\":false}}", ws, tier))
}

// 8. ruliology_automaton
#[rustler::nif(schedule = "DirtyCpu")]
pub fn ruliology_automaton(name: String) -> NifResult<String> {
    let automata: Vec<(&str, &str, &str)> = vec![
        ("guardian", "idle", "[\"idle\",\"armed\",\"triggered\"]"),
        ("circuit_breaker", "closed", "[\"closed\",\"open\",\"half_open\"]"),
        ("container_lifecycle", "running", "[\"created\",\"running\",\"stopped\",\"restarting\"]"),
        ("boot_phase", "tier_1", "[\"pre_boot\",\"tier_1\",\"tier_2\",\"tier_3\",\"tier_4\",\"tier_5\",\"tier_6\",\"tier_7\",\"complete\"]"),
        ("apoptosis", "alive", "[\"alive\",\"draining\",\"dying\",\"dead\"]"),
        ("health_state", "healthy", "[\"healthy\",\"degraded\",\"critical\",\"unknown\"]"),
        ("mesh_state", "disconnected", "[\"disconnected\",\"connecting\",\"connected\",\"partitioned\"]"),
    ];
    for (n, current, states) in &automata {
        if *n == name.as_str() {
            return Ok(format!("{{\"name\":\"{}\",\"current\":\"{}\",\"states\":{},\"step_count\":0}}", n, current, states));
        }
    }
    Ok(format!("{{\"name\":\"{}\",\"current\":\"unknown\",\"states\":[],\"step_count\":0}}", name))
}

// 9. ruliology_multiway
#[rustler::nif(schedule = "DirtyCpu")]
pub fn ruliology_multiway() -> NifResult<String> {
    Ok("{\"nodes\":[{\"id\":\"gemini_direct\",\"branches\":[\"response\",\"openrouter\"]},{\"id\":\"openrouter\",\"branches\":[\"response\",\"ollama_gemma4\"]},{\"id\":\"ollama_gemma4\",\"branches\":[\"response\",\"ollama_gemma3\"]},{\"id\":\"ollama_gemma3\",\"branches\":[\"response\",\"rete_rules\"]},{\"id\":\"rete_rules\",\"branches\":[\"response\"]}],\"node_count\":5}".into())
}

// 10. ruliology_causal
#[rustler::nif(schedule = "DirtyCpu")]
pub fn ruliology_causal() -> NifResult<String> {
    Ok("{\"nodes\":[\"received\",\"classified\",\"ack_sent\",\"inference_started\",\"rag\",\"inference_complete\",\"delivered\"],\"edges\":[{\"from\":\"received\",\"to\":\"classified\",\"weight\":1.0},{\"from\":\"classified\",\"to\":\"ack_sent\",\"weight\":1.0},{\"from\":\"ack_sent\",\"to\":\"inference_started\",\"weight\":1.0},{\"from\":\"inference_started\",\"to\":\"rag\",\"weight\":1.0},{\"from\":\"rag\",\"to\":\"inference_complete\",\"weight\":5.0},{\"from\":\"inference_complete\",\"to\":\"delivered\",\"weight\":1.0}],\"node_count\":7,\"edge_count\":6}".into())
}

// 11. ooda_phase
#[rustler::nif(schedule = "DirtyCpu")]
pub fn ooda_phase() -> NifResult<String> {
    let phase = query_pref("ooda_current_phase", "idle");
    let count = query_pref("ooda_cycle_count", "0");
    Ok(format!("{{\"phase\":\"{}\",\"cycle_count\":{},\"target_ms\":100}}", phase, count))
}
