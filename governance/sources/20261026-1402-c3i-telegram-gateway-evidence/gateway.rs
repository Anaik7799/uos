use crate::errors::IgnitionError;
use log::{debug, error, info, warn};

/// SC-VAULT-003 (Wave 7 Phase 4): vault-first-with-fallback secret read.
/// Best-effort by design — gateway broadcasts MUST NOT block on vault
/// availability. NEVER fabricates a value (Stub-That-Lies guard
/// [zk-3346fc607a1ef9e6]). Returns `None` if both paths miss.
async fn read_secret(name: &str) -> Option<String> {
    let vault_path = crate::data_paths::vault_path();
    match crate::vault::Vault::open(vault_path) {
        Ok(v) => match v.get_string(name).await {
            Ok(s) if !s.is_empty() => return Some(s),
            Ok(_) => {}
            Err(crate::vault::VaultError::SecretNotFound { .. }) => {}
            Err(crate::vault::VaultError::DbNotFound { .. }) => {
                debug!(
                    "[SC-VAULT-003] gateway: vault not initialized — falling back for {}",
                    name
                );
            }
            Err(e) => warn!(
                "[SC-VAULT-003] gateway: vault read {} failed: {} (falling back)",
                name, e
            ),
        },
        Err(crate::vault::VaultError::DbNotFound { .. }) => {
            debug!(
                "[SC-VAULT-003] gateway: smriti_vault.db absent — falling back for {}",
                name
            );
        }
        Err(e) => warn!(
            "[SC-VAULT-003] gateway: vault open failed: {} (falling back for {})",
            e, name
        ),
    }
    // SC-VAULT-029 fallback-visibility: warn when legacy path resolves.
    let val = crate::db::get_preference(name).ok().flatten();
    if val.is_some() {
        warn!("[SC-VAULT-029] gateway: '{}' from legacy smriti.db (vault path missed); migrate via 'sa-plan-daemon vault put {} -'", name, name);
    }
    val
}

/// ROBUST Gateway Dispatcher (SC-GATEWAY-001)
/// - PARALLEL delivery to all channels (tokio::join!)
/// - Retry once on failure with 1s backoff
/// - Persistent HTTP client (shared with inference)
/// - Never silently drops — all outcomes logged
/// - Truncates log output to prevent log pollution

const MAX_RETRIES: u32 = 1;
const GATEWAY_TIMEOUT_SECS: u64 = 5;

fn gateway_client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(GATEWAY_TIMEOUT_SECS))
        .pool_max_idle_per_host(2)
        .build()
        .expect("gateway client")
}

use std::sync::OnceLock;
static GW_CLIENT: OnceLock<reqwest::Client> = OnceLock::new();
fn client() -> &'static reqwest::Client {
    GW_CLIENT.get_or_init(gateway_client)
}

pub async fn broadcast_message(session: Option<&zenoh::Session>, text: &str, needs_ack: bool) {
    // SC-VAULT-003: vault-first-with-fallback. Broadcast is best-effort and
    // MUST NOT block on vault availability — `read_secret` returns `None`
    // honestly when neither path has the value, preserving the existing
    // "skip channel if no key" semantics.
    let telegram_token = read_secret("telegram_token").await;
    let telegram_chat_id = read_secret("telegram_chat_id")
        .await
        .unwrap_or_else(|| "6249174059".to_string());
    let gchat_webhook = read_secret("gchat_webhook").await.unwrap_or_default();

    let text = text.to_string();
    let tg_text = text.clone();
    let gc_text = text.clone();

    // PARALLEL delivery — both channels fire simultaneously
    let tg_fut = async {
        if let Some(token) = telegram_token {
            send_with_retry(
                session,
                "telegram",
                &tg_text,
                &token,
                &telegram_chat_id,
                needs_ack,
                None,
            )
            .await;
        }
    };
    let gc_fut = async {
        if !gchat_webhook.is_empty() {
            send_with_retry(
                session,
                "gchat",
                &gc_text,
                &gchat_webhook,
                "",
                needs_ack,
                None,
            )
            .await;
        }
    };

    tokio::join!(tg_fut, gc_fut);
}

/// Send a rich Telegram message with inline keyboard buttons.
/// `keyboard`: rows of (label, callback_data) tuples.
/// Returns the message_id for later editing.
pub async fn send_rich(text: &str, keyboard: Vec<Vec<(&str, &str)>>) -> Option<i64> {
    // SC-VAULT-003: vault-first-with-fallback.
    let token = read_secret("telegram_token").await?;
    let chat_id = read_secret("telegram_chat_id")
        .await
        .unwrap_or_else(|| "6249174059".to_string());

    let buttons: Vec<Vec<serde_json::Value>> = keyboard
        .iter()
        .map(|row| {
            row.iter()
                .map(|(label, data)| serde_json::json!({"text": label, "callback_data": data}))
                .collect()
        })
        .collect();

    let payload = serde_json::json!({
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "reply_markup": { "inline_keyboard": buttons }
    });

    let url = format!("https://api.telegram.org/bot{}/sendMessage", token);
    match client().post(&url).json(&payload).send().await {
        Ok(resp) if resp.status().is_success() => {
            if let Ok(val) = resp.json::<serde_json::Value>().await {
                let msg_id = val["result"]["message_id"].as_i64();
                info!(
                    "✅ telegram rich: delivered ({} chars, {} buttons)",
                    text.len(),
                    keyboard.iter().flatten().count()
                );
                return msg_id;
            }
            None
        }
        Ok(resp) => {
            error!("❌ TG rich send: {}", resp.status());
            None
        }
        Err(e) => {
            error!("❌ TG rich send: {}", e);
            None
        }
    }
}

/// Edit an existing Telegram message (for refresh/drill-down).
pub async fn edit_message(message_id: i64, text: &str, keyboard: Option<Vec<Vec<(&str, &str)>>>) {
    // SC-VAULT-003: vault-first-with-fallback.
    let token = match read_secret("telegram_token").await {
        Some(t) => t,
        None => return,
    };
    let chat_id = read_secret("telegram_chat_id")
        .await
        .unwrap_or_else(|| "6249174059".to_string());

    let mut payload = serde_json::json!({
        "chat_id": chat_id,
        "message_id": message_id,
        "text": text,
        "parse_mode": "HTML"
    });

    if let Some(kb) = keyboard {
        let buttons: Vec<Vec<serde_json::Value>> = kb
            .iter()
            .map(|row| {
                row.iter()
                    .map(|(label, data)| serde_json::json!({"text": label, "callback_data": data}))
                    .collect()
            })
            .collect();
        payload["reply_markup"] = serde_json::json!({"inline_keyboard": buttons});
    }

    let url = format!("https://api.telegram.org/bot{}/editMessageText", token);
    match client().post(&url).json(&payload).send().await {
        Ok(resp) if resp.status().is_success() => {
            info!("✅ telegram edit: msg_id={}", message_id);
        }
        Ok(resp) => {
            error!("❌ TG edit: {}", resp.status());
        }
        Err(e) => {
            error!("❌ TG edit: {}", e);
        }
    }
}

/// Answer a callback query (dismisses the "loading" spinner on button press).
pub async fn answer_callback(callback_query_id: &str, text: Option<&str>) {
    // SC-VAULT-003: vault-first-with-fallback.
    let token = match read_secret("telegram_token").await {
        Some(t) => t,
        None => return,
    };
    let mut payload = serde_json::json!({"callback_query_id": callback_query_id});
    if let Some(t) = text {
        payload["text"] = serde_json::json!(t);
    }

    let url = format!("https://api.telegram.org/bot{}/answerCallbackQuery", token);
    let _ = client().post(&url).json(&payload).send().await;
}

/// Request a dual-channel approval for a destructive intent (Task 2.2).
/// Returns a unique approval_id for tracking.
pub async fn request_approval(
    session: Option<&zenoh::Session>,
    intent_id: &str,
    description: &str,
) -> Result<String, IgnitionError> {
    let approval_id = uuid::Uuid::new_v4()
        .to_string()
        .chars()
        .take(8)
        .collect::<String>();
    let text = format!(
        "🚨 APPROVAL REQUIRED (id:{})\nIntent: {}\nAction: {}",
        approval_id, intent_id, description
    );

    // SC-VAULT-003: vault-first-with-fallback (request_approval path).
    let telegram_token = read_secret("telegram_token").await;
    let telegram_chat_id = read_secret("telegram_chat_id")
        .await
        .unwrap_or_else(|| "6249174059".to_string());
    let gchat_webhook = read_secret("gchat_webhook").await.unwrap_or_default();

    let tg_text = text.clone();
    let gc_text = text.clone();
    let aid = approval_id.clone();

    info!(
        "🚨 Requesting approval {} for intent {}",
        approval_id, intent_id
    );

    let tg_fut = async {
        if let Some(token) = telegram_token {
            send_with_retry(
                session,
                "telegram",
                &tg_text,
                &token,
                &telegram_chat_id,
                true,
                Some(&aid),
            )
            .await;
        }
    };
    let gc_fut = async {
        if !gchat_webhook.is_empty() {
            send_with_retry(
                session,
                "gchat",
                &gc_text,
                &gchat_webhook,
                "",
                true,
                Some(&aid),
            )
            .await;
        }
    };

    tokio::join!(tg_fut, gc_fut);
    Ok(approval_id)
}

async fn send_with_retry(
    session: Option<&zenoh::Session>,
    channel: &str,
    text: &str,
    token: &str,
    chat_id: &str,
    needs_ack: bool,
    approval_id: Option<&str>,
) {
    for attempt in 0..=MAX_RETRIES {
        match send_to_channel(
            session,
            channel,
            text,
            token,
            chat_id,
            needs_ack,
            approval_id,
        )
        .await
        {
            Ok(_) => {
                info!("✅ {}: delivered ({} chars)", channel, text.len());
                return;
            }
            Err(e) => {
                if attempt < MAX_RETRIES {
                    warn!(
                        "⚠️ {} attempt {} failed: {} — retrying in 1s",
                        channel,
                        attempt + 1,
                        e
                    );
                    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                } else {
                    error!(
                        "❌ {} FAILED after {} attempts: {}",
                        channel,
                        attempt + 1,
                        e
                    );
                }
            }
        }
    }
}

async fn send_to_channel(
    session: Option<&zenoh::Session>,
    channel: &str,
    text: &str,
    token: &str,
    chat_id: &str,
    needs_ack: bool,
    approval_id: Option<&str>,
) -> Result<serde_json::Value, IgnitionError> {
    let c = client();
    let log_preview = crate::errors::safe_trunc(text, 60);

    if token == "INTERNAL_SIL6_TOKEN" || token.is_empty() {
        info!("⚠️ {} token is mock — skipping", channel);
        return Ok(serde_json::json!({"status": "mock_skipped"}));
    }

    match channel {
        "telegram" => {
            // Check for method in text (hacky) or assume sendMessage
            // A better way is to pass method explicitly
            let method = if text.starts_with("METHOD:") {
                text.split(':').nth(1).unwrap_or("sendMessage")
            } else {
                "sendMessage"
            };

            let url = if let Ok(sim) = std::env::var("SIMULATOR_TELEGRAM_URL") {
                format!("{}/bot{}/{}", sim, token, method)
            } else {
                format!("https://api.telegram.org/bot{}/{}", token, method)
            };

            let mut payload =
                serde_json::json!({"chat_id": chat_id, "text": text, "parse_mode": "HTML"});

            // If method is editMessageText, we might need message_id
            if method == "editMessageText" && text.contains("|MID:") {
                let parts: Vec<&str> = text.split("|MID:").collect();
                if parts.len() == 2 {
                    payload["text"] = serde_json::json!(parts[0]);
                    payload["message_id"] = serde_json::json!(parts[1].parse::<i64>().unwrap_or(0));
                }
            }

            if needs_ack {
                let callback_data = if let Some(aid) = approval_id {
                    format!("APPROVE:{}", aid)
                } else {
                    "ACK".to_string()
                };
                let reject_data = if let Some(aid) = approval_id {
                    format!("REJECT:{}", aid)
                } else {
                    "REJECT".to_string()
                };

                let mut buttons =
                    vec![serde_json::json!({"text": "✅ Approve", "callback_data": callback_data})];
                if approval_id.is_some() {
                    buttons.push(
                        serde_json::json!({"text": "❌ Reject", "callback_data": reject_data}),
                    );
                }

                payload["reply_markup"] = serde_json::json!({
                    "inline_keyboard": [buttons]
                });
            }

            info!("📤 TG: {}...", log_preview);
            let resp = c
                .post(&url)
                .json(&payload)
                .send()
                .await
                .map_err(|e| IgnitionError::InternalError(format!("TG send: {}", e)))?;

            if resp.status().is_success() {
                let val = resp
                    .json::<serde_json::Value>()
                    .await
                    .map_err(|e| IgnitionError::InternalError(format!("TG JSON: {}", e)))?;

                // Extract message_id and run_id if available to publish mapping
                if let Some(msg_id) = val["result"]["message_id"].as_i64() {
                    // We need run_id from the payload or text
                    // For now, assume it was in the payload
                    if let Some(run_id) = payload["run_id"].as_str() {
                        let mapping = serde_json::json!({
                            "run_id": run_id,
                            "message_id": msg_id.to_string(),
                            "chat_id": chat_id
                        });

                        if let Some(s) = session {
                            let topic = "indrajaal/l4/system/gateway/telegram/mapping";
                            let _ = s.put(topic, mapping.to_string()).await;
                        }
                    }
                }
                Ok(val)
            } else {
                let s = resp.status();
                let b = resp.text().await.unwrap_or_default();
                Err(IgnitionError::InternalError(format!(
                    "TG {}: {}",
                    s,
                    crate::errors::safe_trunc(&b, 150)
                )))
            }
        }
        "gchat" => {
            let url = if let Ok(sim) = std::env::var("SIMULATOR_GCHAT_URL") {
                format!("{}/webhook", sim)
            } else {
                token.to_string()
            };

            let mut payload = serde_json::json!({"text": text});
            if needs_ack {
                let callback_data = if let Some(aid) = approval_id {
                    format!("APPROVE:{}", aid)
                } else {
                    "ACK".to_string()
                };
                let reject_data = if let Some(aid) = approval_id {
                    format!("REJECT:{}", aid)
                } else {
                    "REJECT".to_string()
                };

                let mut buttons = vec![
                    serde_json::json!({"text": "✅ Approve", "onClick": {"action": {"function": callback_data}}}),
                ];
                if approval_id.is_some() {
                    buttons.push(serde_json::json!({"text": "❌ Reject", "onClick": {"action": {"function": reject_data}}}));
                }

                payload["cardsV2"] = serde_json::json!([{
                    "cardId": "ack", "card": {"sections": [{"widgets": [{"buttonList": {"buttons": buttons}}]}]}
                }]);
            }

            info!("📤 GC: {}...", log_preview);
            let resp = c
                .post(&url)
                .json(&payload)
                .send()
                .await
                .map_err(|e| IgnitionError::InternalError(format!("GC send: {}", e)))?;

            if resp.status().is_success() {
                Ok(serde_json::json!({"status": "ok"}))
            } else {
                Err(IgnitionError::InternalError(format!(
                    "GC {}",
                    resp.status()
                )))
            }
        }

        "whatsapp" => {
            let url = format!("https://graph.facebook.com/v19.0/{}/messages", chat_id);
            let resp = c.post(&url).bearer_auth(token)
                .json(&serde_json::json!({"messaging_product":"whatsapp","to":chat_id,"type":"text","text":{"body":text}}))
                .send().await
                .map_err(|e| IgnitionError::InternalError(format!("WA send: {}", e)))?;
            if resp.status().is_success() {
                Ok(serde_json::json!({"status": "ok"}))
            } else {
                Err(IgnitionError::InternalError(format!(
                    "WA {}",
                    resp.status()
                )))
            }
        }
        _ => Ok(serde_json::json!({"status": "unknown_channel"})),
    }
}

// Keep the old signature for CLI gateway command
pub async fn send_message(
    session: Option<&zenoh::Session>,
    channel: &str,
    text: &str,
    token: Option<&str>,
    chat_id: Option<&str>,
    _phone: Option<&str>,
    needs_ack: bool,
) -> Result<serde_json::Value, IgnitionError> {
    send_to_channel(
        session,
        channel,
        text,
        token.unwrap_or(""),
        chat_id.unwrap_or(""),
        needs_ack,
        None,
    )
    .await
}
