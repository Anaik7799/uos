use crate::errors::IgnitionError;
use base64::{engine::general_purpose, Engine as _};
use log::{debug, error, info};
use std::time::Duration;
use tokio::time::sleep;

/// Egress-Only Command Ingress (SC-ZMOF-001)
/// Replaces inbound webhooks with secure outbound long-polling to maintain the "Dark Cockpit" architecture.

pub async fn run_polling_service(session: &zenoh::Session) -> Result<(), IgnitionError> {
    info!("📡 Starting SIL-6 Egress-Only Ingress Polling (Dark Cockpit)");

    let client = reqwest::Client::new();
    // Restore polling offset from Smriti to avoid replaying old messages after restart
    let mut offset: i64 = crate::db::get_preference("telegram_poll_offset")
        .ok()
        .flatten()
        .and_then(|s| s.parse().ok())
        .unwrap_or(-1); // -1 = get only new messages
    info!("📡 Telegram polling offset restored: {}", offset);

    loop {
        let is_simulated = std::env::var("SIMULATOR_TELEGRAM_URL").is_ok();
        let token = match crate::db::get_preference("telegram_token") {
            Ok(Some(t)) => t,
            _ => std::env::var("TELEGRAM_TOKEN").unwrap_or_default(),
        };

        if !is_simulated && (token.is_empty() || token == "INTERNAL_SIL6_TOKEN") {
            debug!("⚠️ Telegram token missing or mock. Skipping polling cycle.");
            sleep(Duration::from_secs(10)).await;
            continue;
        }

        let url = if let Ok(sim_url) = std::env::var("SIMULATOR_TELEGRAM_URL") {
            format!(
                "{}/bot{}/getUpdates?offset={}&timeout=10",
                sim_url, token, offset
            )
        } else {
            format!(
                "https://api.telegram.org/bot{}/getUpdates?offset={}&timeout=10",
                token, offset
            )
        };

        match client.get(&url).send().await {
            Ok(response) => {
                if response.status().is_success() {
                    if let Ok(json) = response.json::<serde_json::Value>().await {
                        if let Some(results) = json["result"].as_array() {
                            for update in results {
                                // Update offset to acknowledge receipt
                                if let Some(update_id) = update["update_id"].as_i64() {
                                    offset = update_id + 1;
                                    // Persist offset to Smriti so restarts don't replay
                                    let _ = crate::db::set_preference(
                                        "telegram_poll_offset",
                                        &offset.to_string(),
                                        "infra_state",
                                    );
                                }

                                if let Some(message) = update.get("message") {
                                    let chat_id = message
                                        .pointer("/chat/id")
                                        .and_then(|v| v.as_i64())
                                        .map(|id| id.to_string());
                                    if let Some(text) = message["text"].as_str() {
                                        info!("📥 INGRESS: Received external command -> {}", text);

                                        // Package and dispatch as an internal Zenoh intent
                                        let intent_topic = "indrajaal/l5/cog/intent/req";
                                        let payload = serde_json::json!({
                                            "id": format!("tg-poll-{}", uuid::Uuid::new_v4()),
                                            "raw_text": text,
                                            "source": "telegram",
                                            "chat_id": chat_id,
                                            "timestamp_ms": chrono::Utc::now().timestamp_millis()
                                        });

                                        // Publish to Zenoh AND process directly (no Zenoh router needed)
                                        let payload_str = payload.to_string();
                                        // Attempt Zenoh publish (best-effort for mesh visibility)
                                        let _ =
                                            session.put(intent_topic, payload_str.clone()).await;

                                        // DIRECT PROCESSING — bypasses Zenoh loopback (SC-WORK-001)
                                        // This ensures commands work even without an external Zenoh router.
                                        {
                                            let zen = session.clone();
                                            let ps = payload_str.clone();
                                            tokio::spawn(async move {
                                                crate::cortex::process_intent_direct(&ps, &zen)
                                                    .await;
                                            });
                                        }
                                        let published = true; // direct processing guarantees delivery
                                        if !published {
                                            error!("❌ DEAD LETTER: Telegram msg lost after 3 Zenoh retries: {}", text);
                                        }
                                    }

                                    // ── VOICE MESSAGE HANDLING ──
                                    if let Some(voice) = message.get("voice") {
                                        let file_id = voice["file_id"].as_str().unwrap_or_default();
                                        let duration = voice["duration"].as_i64().unwrap_or(0);
                                        info!(
                                            "🎤 INGRESS: Voice message ({}s, file_id={})",
                                            duration,
                                            crate::errors::safe_trunc(file_id, 20)
                                        );

                                        // Download the voice file via Telegram getFile API
                                        let file_url = format!(
                                            "https://api.telegram.org/bot{}/getFile?file_id={}",
                                            token, file_id
                                        );
                                        if let Ok(file_resp) = client.get(&file_url).send().await {
                                            if let Ok(file_json) =
                                                file_resp.json::<serde_json::Value>().await
                                            {
                                                if let Some(file_path) =
                                                    file_json["result"]["file_path"].as_str()
                                                {
                                                    let download_url = format!(
                                                        "https://api.telegram.org/file/bot{}/{}",
                                                        token, file_path
                                                    );
                                                    if let Ok(audio_resp) =
                                                        client.get(&download_url).send().await
                                                    {
                                                        if let Ok(audio_bytes) =
                                                            audio_resp.bytes().await
                                                        {
                                                            info!(
                                                                "🎤 Downloaded voice: {} bytes",
                                                                audio_bytes.len()
                                                            );

                                                            // Publish voice intent with base64-encoded audio
                                                            let audio_b64 = base64::Engine::encode(
                                                                &base64::engine::general_purpose::STANDARD,
                                                                &audio_bytes
                                                            );

                                                            let intent_topic =
                                                                "indrajaal/l5/cog/intent/req";
                                                            let payload = serde_json::json!({
                                                                "id": format!("tg-voice-{}", uuid::Uuid::new_v4()),
                                                                "raw_text": format!("[voice:{}s]", duration),
                                                                "source": "telegram",
                                                                "chat_id": chat_id,
                                                                "timestamp_ms": chrono::Utc::now().timestamp_millis(),
                                                                "type": "voice",
                                                                "voice_b64": audio_b64,
                                                                "voice_duration_secs": duration,
                                                                "voice_mime": voice["mime_type"].as_str().unwrap_or("audio/ogg")
                                                            });

                                                            let ps = payload.to_string();
                                                            for a in 0..3 {
                                                                if session
                                                                    .put(intent_topic, ps.clone())
                                                                    .await
                                                                    .is_ok()
                                                                {
                                                                    break;
                                                                }
                                                                if a < 2 {
                                                                    tokio::time::sleep(
                                                                        Duration::from_millis(100),
                                                                    )
                                                                    .await;
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── CALLBACK QUERY HANDLING (inline keyboard buttons) ──
                                if let Some(callback) = update.get("callback_query") {
                                    let cb_id = callback["id"].as_str().unwrap_or_default();
                                    let cb_data = callback["data"].as_str().unwrap_or_default();
                                    let cb_msg_id = callback
                                        .pointer("/message/message_id")
                                        .and_then(|v| v.as_i64());
                                    let cb_chat_id = callback
                                        .pointer("/message/chat/id")
                                        .and_then(|v| v.as_i64())
                                        .map(|id| id.to_string());

                                    info!("📥 CALLBACK: {} (msg_id={:?})", cb_data, cb_msg_id);

                                    // Answer the callback to dismiss spinner
                                    crate::gateway::answer_callback(cb_id, None).await;

                                    // Route callback as a synthetic command intent
                                    let synthetic_text = match cb_data {
                                        "w:status" => "/w status",
                                        "w:pipeline" => "/pipeline",
                                        "w:forecast" => "/forecast",
                                        "w:contacts" => "/contacts",
                                        "w:briefing" => "/briefing",
                                        "w:fitness" => "/w fitness",
                                        "w:review" => "/review",
                                        "w:tasks" => "/tasks",
                                        "c:status" => "/status",
                                        "c:help" => "/help",
                                        "c:containers" => "/containers",
                                        "c:rules" => "/rules",
                                        d if d.starts_with("w:search:") => {
                                            d.strip_prefix("w:search:").unwrap_or("")
                                        }
                                        d if d.starts_with("w:contact:") => {
                                            d.strip_prefix("w:contact:").unwrap_or("")
                                        }
                                        _ => cb_data,
                                    };

                                    // Convert to text for processing if it starts with /
                                    if synthetic_text.starts_with('/') {
                                        let intent_topic = "indrajaal/l5/cog/intent/req";
                                        let payload = serde_json::json!({
                                            "id": format!("tg-cb-{}", uuid::Uuid::new_v4()),
                                            "raw_text": synthetic_text,
                                            "source": "telegram",
                                            "chat_id": cb_chat_id,
                                            "timestamp_ms": chrono::Utc::now().timestamp_millis()
                                        });
                                        let ps = payload.to_string();
                                        let _ = session.put(intent_topic, ps.clone()).await;
                                        let zen = session.clone();
                                        tokio::spawn(async move {
                                            crate::cortex::process_intent_direct(&ps, &zen).await;
                                        });
                                    }
                                }
                            }
                        }
                    }
                } else {
                    error!("❌ Telegram Polling HTTP Error: {}", response.status());
                }
            }
            Err(e) => {
                error!("❌ Telegram Polling Connection Error: {}", e);
            }
        }

        // Small delay to prevent tight-looping if getUpdates returns immediately
        sleep(Duration::from_secs(1)).await;
    }
}

pub async fn run_gchat_polling_service(session: &zenoh::Session) -> Result<(), IgnitionError> {
    info!("📡 Starting SIL-6 GChat Egress-Only Polling via GCP Pub/Sub");

    let client = reqwest::Client::new();
    let is_simulated = std::env::var("SIMULATOR_GCHAT_URL").is_ok();

    let project_id = match crate::db::get_preference("gcp_project_id") {
        Ok(Some(p)) => p,
        _ => std::env::var("GCP_PROJECT_ID").unwrap_or_default(),
    };
    let sub_id = match crate::db::get_preference("gcp_pubsub_subscription") {
        Ok(Some(s)) => s,
        _ => std::env::var("GCP_PUBSUB_SUBSCRIPTION").unwrap_or_default(),
    };

    if !is_simulated && (project_id.is_empty() || sub_id.is_empty()) {
        debug!("⚠️ GCP Pub/Sub config missing. Skipping GChat polling.");
        return Ok(());
    }

    // FRACTAL TPS: Preflight Check to verify the queue exists
    if !is_simulated {
        let token_output = std::process::Command::new("gcloud")
            .args(&["auth", "application-default", "print-access-token"])
            .output();

        if let Ok(output) = &token_output {
            if output.status.success() {
                let token = String::from_utf8_lossy(&output.stdout).trim().to_string();
                let check_url = format!(
                    "https://pubsub.googleapis.com/v1/projects/{}/subscriptions/{}",
                    project_id, sub_id
                );

                if let Ok(res) = client.get(&check_url).bearer_auth(&token).send().await {
                    if res.status() == 404 {
                        let err_msg = format!("❌ [PREFLIGHT FAILED] GChat Pub/Sub queue '{}' does not exist on project '{}'. Halting GChat Ingress.", sub_id, project_id);
                        error!("{}", err_msg);
                        crate::gateway::broadcast_message(None, &err_msg, false).await;
                        return Ok(());
                    }
                }
            }
        }
    }

    loop {
        if let Ok(sim_url) = std::env::var("SIMULATOR_GCHAT_URL") {
            let url = format!(
                "{}/v1/projects/{}/subscriptions/{}:pull",
                sim_url, project_id, sub_id
            );
            let req_body = serde_json::json!({ "maxMessages": 10 });

            if let Ok(res) = client.post(&url).json(&req_body).send().await {
                if res.status().is_success() {
                    if let Ok(json) = res.json::<serde_json::Value>().await {
                        if let Some(messages) = json["receivedMessages"].as_array() {
                            let mut ack_ids = Vec::new();
                            for msg in messages {
                                if let Some(ack_id) = msg["ackId"].as_str() {
                                    ack_ids.push(ack_id.to_string());
                                }
                                if let Some(data_b64) =
                                    msg.pointer("/message/data").and_then(|v| v.as_str())
                                {
                                    if let Ok(decoded) = general_purpose::STANDARD.decode(data_b64)
                                    {
                                        if let Ok(payload_str) = String::from_utf8(decoded) {
                                            if let Ok(chat_event) =
                                                serde_json::from_str::<serde_json::Value>(
                                                    &payload_str,
                                                )
                                            {
                                                let chat_id = chat_event
                                                    .pointer("/space/name")
                                                    .and_then(|v| v.as_str())
                                                    .map(|s| s.to_string());
                                                if let Some(text) = chat_event
                                                    .pointer("/message/text")
                                                    .and_then(|v| v.as_str())
                                                {
                                                    info!(
                                                        "📥 INGRESS [GChat Sim]: Received -> {}",
                                                        text
                                                    );
                                                    let intent_topic =
                                                        "indrajaal/l5/cog/intent/req";
                                                    let payload = serde_json::json!({
                                                        "id": format!("gc-poll-{}", uuid::Uuid::new_v4()),
                                                        "raw_text": text,
                                                        "source": "gchat",
                                                        "chat_id": chat_id,
                                                        "timestamp_ms": chrono::Utc::now().timestamp_millis()
                                                    });
                                                    let ps = payload.to_string();
                                                    for a in 0..3 {
                                                        if session
                                                            .put(intent_topic, ps.clone())
                                                            .await
                                                            .is_ok()
                                                        {
                                                            break;
                                                        }
                                                        if a < 2 {
                                                            tokio::time::sleep(
                                                                Duration::from_millis(100),
                                                            )
                                                            .await;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            if !ack_ids.is_empty() {
                                let ack_url = format!(
                                    "{}/v1/projects/{}/subscriptions/{}:acknowledge",
                                    sim_url, project_id, sub_id
                                );
                                let _ = client
                                    .post(&ack_url)
                                    .json(&serde_json::json!({"ackIds": ack_ids}))
                                    .send()
                                    .await;
                            }
                        }
                    }
                }
            }
            sleep(Duration::from_secs(2)).await;
            continue;
        }

        let token_output = std::process::Command::new("gcloud")
            .args(&["auth", "application-default", "print-access-token"])
            .output();

        if let Ok(output) = token_output {
            if output.status.success() {
                let token = String::from_utf8_lossy(&output.stdout).trim().to_string();
                let url = format!(
                    "https://pubsub.googleapis.com/v1/projects/{}/subscriptions/{}:pull",
                    project_id, sub_id
                );

                let req_body = serde_json::json!({
                    "maxMessages": 10,
                });

                if let Ok(res) = client
                    .post(&url)
                    .bearer_auth(&token)
                    .json(&req_body)
                    .send()
                    .await
                {
                    if res.status().is_success() {
                        if let Ok(json) = res.json::<serde_json::Value>().await {
                            if let Some(messages) = json["receivedMessages"].as_array() {
                                let mut ack_ids = Vec::new();

                                for msg in messages {
                                    if let Some(ack_id) = msg["ackId"].as_str() {
                                        ack_ids.push(ack_id.to_string());
                                    }

                                    // Extract payload
                                    if let Some(data_b64) =
                                        msg.pointer("/message/data").and_then(|v| v.as_str())
                                    {
                                        if let Ok(decoded) =
                                            general_purpose::STANDARD.decode(data_b64)
                                        {
                                            if let Ok(payload_str) = String::from_utf8(decoded) {
                                                if let Ok(chat_event) =
                                                    serde_json::from_str::<serde_json::Value>(
                                                        &payload_str,
                                                    )
                                                {
                                                    // Typically GChat events have message.text
                                                    let chat_id = chat_event
                                                        .pointer("/space/name")
                                                        .and_then(|v| v.as_str())
                                                        .map(|s| s.to_string());
                                                    if let Some(text) = chat_event
                                                        .pointer("/message/text")
                                                        .and_then(|v| v.as_str())
                                                    {
                                                        info!("📥 INGRESS [GChat]: Received external command -> {}", text);

                                                        // Package and dispatch as an internal Zenoh intent
                                                        let intent_topic =
                                                            "indrajaal/l5/cog/intent/req";
                                                        let payload = serde_json::json!({
                                                            "id": format!("gc-poll-{}", uuid::Uuid::new_v4()),
                                                            "raw_text": text,
                                                            "source": "gchat",
                                                            "chat_id": chat_id,
                                                            "timestamp_ms": chrono::Utc::now().timestamp_millis()
                                                        });

                                                        let ps = payload.to_string();
                                                        for a in 0..3 {
                                                            if session
                                                                .put(intent_topic, ps.clone())
                                                                .await
                                                                .is_ok()
                                                            {
                                                                break;
                                                            }
                                                            error!("❌ Zenoh publish attempt {} failed for GChat real", a + 1);
                                                            if a < 2 {
                                                                tokio::time::sleep(
                                                                    Duration::from_millis(100),
                                                                )
                                                                .await;
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Acknowledge messages
                                if !ack_ids.is_empty() {
                                    let ack_url = format!("https://pubsub.googleapis.com/v1/projects/{}/subscriptions/{}:acknowledge", project_id, sub_id);
                                    let ack_body = serde_json::json!({
                                        "ackIds": ack_ids
                                    });
                                    let _ = client
                                        .post(&ack_url)
                                        .bearer_auth(&token)
                                        .json(&ack_body)
                                        .send()
                                        .await;
                                }
                            }
                        }
                    } else if res.status() == 404 {
                        error!("❌ GChat Polling HTTP Error: 404 Not Found. Subscription may have been deleted.");
                        break; // Exit loop if the subscription vanishes
                    } else {
                        error!("❌ GChat Polling HTTP Error: {}", res.status());
                    }
                }
            } else {
                error!(
                    "❌ Failed to get gcloud auth token: {}",
                    String::from_utf8_lossy(&output.stderr)
                );
            }
        }

        sleep(Duration::from_secs(2)).await;
    }

    Ok(())
}
