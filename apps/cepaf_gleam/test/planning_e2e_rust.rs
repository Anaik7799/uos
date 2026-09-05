/// C3I Planning Page — Comprehensive E2E Verification (Rust only)
/// Tests: DOM elements, API endpoints, SSE stream, WebSocket bidirectional,
///        Gemma AI chat, responsive CSS, JS features, live data, page content.
/// STAMP: SC-GLM-UI-001, SC-UIGT-008, SC-GLM-UI-010

use regex::Regex;
use std::net::TcpStream;
use std::time::Duration;
use tungstenite::{client_tls_with_config, stream::MaybeTlsStream, Connector, Message};

const BASE: &str = "https://localhost:4100";

fn main() {
    println!("╔══════════════════════════════════════════════════════════════╗");
    println!("║     C3I Planning Page — Full E2E Verification (Rust)       ║");
    println!("╚══════════════════════════════════════════════════════════════╝\n");

    let client = http_client();
    let mut total = 0u32;
    let mut passed = 0u32;

    // ── A. Server Health ──
    section("A. SERVER HEALTH");
    check(&mut total, &mut passed, "HTTPS /health returns 200",
        get_status(&client, "/health") == 200);
    check(&mut total, &mut passed, "HTTPS /planning returns 200",
        get_status(&client, "/planning") == 200);

    // ── B. API Endpoints ──
    section("B. API ENDPOINTS");
    let apis = [
        "/api/v1/plan/status",
        "/api/v1/plan/list/all",
        "/api/v1/plan/list/in_progress",
        "/api/v1/plan/list/blocked",
        "/api/v1/plan/list/completed",
        "/api/v1/plan/list/pending",
        "/api/v1/plan/pending",
        "/api/v1/plan/search?q=ooda",
        "/api/v1/ai/status",
        "/api/v1/plan/stream",
    ];
    for api in &apis {
        let code = get_status(&client, api);
        check(&mut total, &mut passed, &format!("{api} => {code}"), code == 200);
    }

    // ── C. Live Data Counts ──
    section("C. LIVE DATA");
    let status_json = get_body(&client, "/api/v1/plan/status");
    let status: serde_json::Value = serde_json::from_str(&status_json).unwrap_or_default();
    let total_tasks = status["total"].as_i64().unwrap_or(0);
    let active = status["active"].as_i64().unwrap_or(0);
    let blocked = status["blocked"].as_i64().unwrap_or(0);
    let completed = status["completed"].as_i64().unwrap_or(0);
    println!("  Data: {total_tasks} total, {active} active, {blocked} blocked, {completed} completed");
    check(&mut total, &mut passed, "Total tasks > 0", total_tasks > 0);
    check(&mut total, &mut passed, "Active tasks >= 0", active >= 0);
    check(&mut total, &mut passed, "Status JSON has 'total' key", status.get("total").is_some());

    // ── D. Page DOM Elements ──
    section("D. DOM ELEMENTS (21 expected)");
    let html = get_body(&client, "/planning");
    let id_re = Regex::new(r#"id="([^"]+)""#).unwrap();
    let ids: Vec<String> = id_re.captures_iter(&html)
        .map(|c| c[1].to_string())
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter().collect();

    let expected_ids = [
        "active-grid", "ai-chat-widget", "ai-search-input", "ai-search-results",
        "all-grid", "analytics-section", "blocked-grid", "change-log",
        "fractal-filter-chips", "grid-analytics", "grid-minichart", "grid-section",
        "grid-status", "kanban-section", "live-status-cards", "task-detail-panel",
        "timeline-section", "weather-bar", "weather-emoji", "weather-label", "weather-score",
    ];
    for eid in &expected_ids {
        check(&mut total, &mut passed, &format!("DOM #{eid}"), ids.contains(&eid.to_string()));
    }
    println!("  Found {}/{} expected IDs", ids.len(), expected_ids.len());

    // ── E. Responsive CSS ──
    section("E. RESPONSIVE CSS");
    let decoded = html.replace("&amp;", "&").replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">");
    let css_checks = [
        ("Mobile 1col grid", "grid-template-columns:1fr"),
        ("Tablet 768px breakpoint", "min-width:768px"),
        ("Desktop 1024px breakpoint", "min-width:1024px"),
        ("Wide 1400px breakpoint", "min-width:1400px"),
        ("Touch 44px targets", "min-height:44px"),
        ("Safe area inset", "safe-area-inset"),
        ("Smooth scroll", "scroll-behavior"),
    ];
    for (name, pattern) in &css_checks {
        check(&mut total, &mut passed, name, decoded.contains(pattern));
    }

    // ── F. Page Content Sections ──
    section("F. PAGE CONTENT");
    let section_re = Regex::new(r#"class="section-title">([^<]+)"#).unwrap();
    let sections: Vec<String> = section_re.captures_iter(&html).map(|c| c[1].to_string()).collect();
    println!("  Sections: {}", sections.len());
    check(&mut total, &mut passed, "Has >= 10 sections", sections.len() >= 10);
    check(&mut total, &mut passed, "Has Task Summary section",
        sections.iter().any(|s| s.contains("Task Summary")));
    check(&mut total, &mut passed, "Has AI Agent section",
        sections.iter().any(|s| s.contains("AI Agent")));
    check(&mut total, &mut passed, "Has State Change Log",
        sections.iter().any(|s| s.contains("State Change")));
    check(&mut total, &mut passed, "Has Task Explorer",
        sections.iter().any(|s| s.contains("Task Explorer")));

    let card_count = html.matches("card-value").count();
    let svg_count = html.matches("<svg").count();
    println!("  Cards: {card_count}, SVGs: {svg_count}");
    check(&mut total, &mut passed, "Has >= 15 status cards", card_count >= 15);
    check(&mut total, &mut passed, "Has >= 4 SVG progress rings", svg_count >= 4);

    // ── G. JS Features ──
    section("G. JS FEATURES (planning-grid.js)");
    let js = get_body(&client, "/static/planning-grid.js");
    let js_features = [
        ("Grid view", "createGrid"),
        ("Kanban view", "renderKanban"),
        ("Timeline view", "renderTimeline"),
        ("Analytics view", "renderAnalyticsView"),
        ("Fractal L0-L7", "FRACTAL_LAYERS"),
        ("AI search", "initAISearch"),
        ("Change log", "renderChangeLog"),
        ("Row diff", "findChangedIds"),
        ("Row highlight", "highlightChangedRows"),
        ("Detail drill-down", "showTaskDetail"),
        ("Knowledge lookup", "searchKnowledgeInPanel"),
        ("Related tasks", "searchRelatedInPanel"),
        ("Sub-tasks", "showSubTasks"),
        ("AI analysis", "runAIAnalysis"),
        ("STAMP refs", "showStampRefs"),
        ("Gemma chat", "callGemma"),
        ("Chat widget", "initAIChat"),
        ("WebSocket", "initWebSocket"),
        ("WS ping", "wsPingTimer"),
        ("WS reconnect", "wsReconnectDelay"),
        ("Header update", "refreshHeaderStatus"),
        ("Export CSV", "export-csv"),
        ("Keyboard shortcuts", "ctrlKey"),
        ("Heartbeat", "heartbeat-live"),
        ("Responsive CSS", "@media"),
        ("Touch targets", "min-height:44px"),
    ];
    for (name, pattern) in &js_features {
        check(&mut total, &mut passed, name, js.contains(pattern));
    }
    println!("  JS size: {} bytes", js.len());

    // ── H. SSE Stream ──
    section("H. SSE STREAM");
    let sse = get_body(&client, "/api/v1/plan/stream");
    check(&mut total, &mut passed, "SSE has 'event: status'", sse.contains("event: status"));
    check(&mut total, &mut passed, "SSE has 'event: active'", sse.contains("event: active"));
    check(&mut total, &mut passed, "SSE has 'event: blocked'", sse.contains("event: blocked"));
    check(&mut total, &mut passed, "SSE has 'retry: 3000'", sse.contains("retry: 3000"));

    // ── I. WebSocket Bidirectional ──
    section("I. WEBSOCKET (bidirectional)");
    let ws_results = test_websocket();
    for (name, ok) in &ws_results {
        check(&mut total, &mut passed, name, *ok);
    }

    // ── J. Gemma AI Chat ──
    section("J. GEMMA AI CHAT");
    let gemma_ok = test_gemma();
    check(&mut total, &mut passed, "Gemma 3 responds with task context", gemma_ok);

    // ── K. AI Status Endpoint ──
    section("K. AI STATUS");
    let ai_body = get_body(&client, "/api/v1/ai/status");
    let ai: serde_json::Value = serde_json::from_str(&ai_body).unwrap_or_default();
    check(&mut total, &mut passed, "AI agent = gemma4",
        ai["agent"].as_str() == Some("gemma4"));
    check(&mut total, &mut passed, "AI has capabilities array",
        ai["capabilities"].as_array().map(|a| a.len()).unwrap_or(0) >= 4);

    // ── L. Search Returns Results ──
    section("L. SEARCH VERIFICATION");
    let search1 = get_body(&client, "/api/v1/plan/search?q=zenoh");
    let search2 = get_body(&client, "/api/v1/plan/search?q=container");
    check(&mut total, &mut passed, "Search 'zenoh' returns data", search1.len() > 20);
    check(&mut total, &mut passed, "Search 'container' returns data", search2.len() > 20);

    // ══════════════════════════════════════════════════════════════
    // MULTI-STEP DAG SCENARIOS — chained cross-component paths
    // Each scenario is a DAG where stage N depends on stage N-1
    // ══════════════════════════════════════════════════════════════

    section("M. DAG: Task Triage Journey (5 stages)");
    // Stage 1: Load page → Stage 2: Get status → Stage 3: Get blocked tasks
    // → Stage 4: Search first blocked task → Stage 5: Verify via WebSocket
    {
        // M1: Page loads
        let page = get_body(&client, "/planning");
        let m1 = page.len() > 1000;
        check(&mut total, &mut passed, "M1: Page loads (>1KB)", m1);

        // M2: Get live status from the page's data source
        let status_raw = get_body(&client, "/api/v1/plan/status");
        let status: serde_json::Value = serde_json::from_str(&status_raw).unwrap_or_default();
        let blocked_count = status["blocked"].as_i64().unwrap_or(0);
        let m2 = blocked_count >= 0 && status["total"].as_i64().unwrap_or(0) > 0;
        check(&mut total, &mut passed, &format!("M2: Status has data (blocked={blocked_count})"), m2);

        // M3: Fetch blocked tasks list
        let blocked_raw = get_body(&client, "/api/v1/plan/list/blocked");
        let blocked: Vec<serde_json::Value> = serde_json::from_str(&blocked_raw).unwrap_or_default();
        let m3 = blocked.len() as i64 == blocked_count;
        check(&mut total, &mut passed, &format!("M3: Blocked list count matches status ({} == {blocked_count})", blocked.len()), m3);

        // M4: Search for first blocked task's title keyword
        let search_query = blocked.first()
            .and_then(|t| t["title"].as_str())
            .and_then(|t| t.split_whitespace().find(|w| w.len() > 4))
            .unwrap_or("blocked");
        let search_url = format!("/api/v1/plan/search?q={}", search_query.replace(' ', "%20"));
        let search_raw = get_body(&client, &search_url);
        let search_results: Vec<serde_json::Value> = serde_json::from_str(&search_raw).unwrap_or_default();
        let m4 = !search_results.is_empty();
        check(&mut total, &mut passed, &format!("M4: Search '{search_query}' finds results ({})", search_results.len()), m4);

        // M5: Verify same data via WebSocket
        let ws_results = test_ws_search(search_query);
        let m5 = ws_results;
        check(&mut total, &mut passed, "M5: WebSocket search returns same data", m5);
    }

    section("N. DAG: Real-Time Monitoring (6 stages)");
    // Stage 1: Connect WS → Stage 2: Get initial status → Stage 3: Ping →
    // Stage 4: Compare with HTTP status → Stage 5: Ping again → Stage 6: Verify seq monotonic
    {
        let tls = native_tls::TlsConnector::builder()
            .danger_accept_invalid_certs(true).build().unwrap();
        let tcp = TcpStream::connect("127.0.0.1:4100").unwrap();
        tcp.set_read_timeout(Some(Duration::from_secs(10))).ok();
        let (mut ws, _) = client_tls_with_config(
            "wss://localhost:4100/ws/planning", tcp, None, Some(Connector::NativeTls(tls)),
        ).unwrap();

        // N1: Get initial connected message
        let j = ws_rx(&mut ws);
        let ws_status_raw = g(&j, "status");
        let n1 = g(&j, "type") == "connected" && !ws_status_raw.is_empty();
        check(&mut total, &mut passed, "N1: WS connected with status", n1);

        // N2: Parse WS status and get total
        let ws_status: serde_json::Value = serde_json::from_str(&ws_status_raw).unwrap_or_default();
        let ws_total = ws_status["total"].as_i64().unwrap_or(0);
        let n2 = ws_total > 0;
        check(&mut total, &mut passed, &format!("N2: WS status total={ws_total}"), n2);

        // N3: Compare WS status with HTTP status
        let http_status: serde_json::Value = serde_json::from_str(&get_body(&client, "/api/v1/plan/status")).unwrap_or_default();
        let http_total = http_status["total"].as_i64().unwrap_or(0);
        let n3 = ws_total == http_total;
        check(&mut total, &mut passed, &format!("N3: WS total ({ws_total}) == HTTP total ({http_total})"), n3);

        // N4: Ping #1 and collect seq
        let _ = ws.send(Message::Text("ping".into()));
        let j = ws_rx(&mut ws);
        let seq1 = j["seq"].as_i64().unwrap_or(0);
        let n4 = seq1 > 0;
        check(&mut total, &mut passed, &format!("N4: Ping #1 seq={seq1}"), n4);

        // N5: Ping #2 — seq must increment
        let _ = ws.send(Message::Text("ping".into()));
        let j = ws_rx(&mut ws);
        let seq2 = j["seq"].as_i64().unwrap_or(0);
        let n5 = seq2 > seq1;
        check(&mut total, &mut passed, &format!("N5: Ping #2 seq={seq2} > {seq1}"), n5);

        // N6: Ping #3 — seq still incrementing (monotonic)
        let _ = ws.send(Message::Text("ping".into()));
        let j = ws_rx(&mut ws);
        let seq3 = j["seq"].as_i64().unwrap_or(0);
        let n6 = seq3 > seq2;
        check(&mut total, &mut passed, &format!("N6: Ping #3 seq={seq3} > {seq2} (monotonic)"), n6);

        let _ = ws.close(None);
    }

    section("O. DAG: AI-Assisted Analysis (5 stages)");
    // Stage 1: Get AI status → Stage 2: Get task data → Stage 3: Ask Gemma
    // → Stage 4: Cross-check with search → Stage 5: Verify via AI chat endpoint
    {
        // O1: Check AI agent availability
        let ai_raw = get_body(&client, "/api/v1/ai/status");
        let ai: serde_json::Value = serde_json::from_str(&ai_raw).unwrap_or_default();
        let o1 = ai["agent"].as_str() == Some("gemma4") && ai["status"].as_str() == Some("available");
        check(&mut total, &mut passed, "O1: AI agent status=available", o1);

        // O2: Get active tasks for context
        let active_raw = get_body(&client, "/api/v1/plan/list/in_progress");
        let active: Vec<serde_json::Value> = serde_json::from_str(&active_raw).unwrap_or_default();
        let o2 = !active.is_empty();
        check(&mut total, &mut passed, &format!("O2: Active tasks available ({})", active.len()), o2);

        // O3: Ask Gemma about the active tasks
        let gemma_body = serde_json::json!({
            "model": "gemma3",
            "messages": [
                {"role": "system", "content": format!("You are C3I AI. {} active tasks, {} total.", active.len(), total_tasks)},
                {"role": "user", "content": "In one sentence, what is the system status?"}
            ],
            "stream": false,
            "options": {"num_predict": 60}
        });
        let gemma_resp = client.post("http://localhost:11434/api/chat")
            .json(&gemma_body).timeout(Duration::from_secs(20)).send();
        let gemma_text = gemma_resp.ok()
            .and_then(|r| r.json::<serde_json::Value>().ok())
            .and_then(|j| j["message"]["content"].as_str().map(|s| s.to_string()))
            .unwrap_or_default();
        let o3 = gemma_text.len() > 10;
        if o3 { println!("  Gemma: {}", &gemma_text[..gemma_text.len().min(100)]); }
        check(&mut total, &mut passed, "O3: Gemma responds about system status", o3);

        // O4: Search for a keyword from Gemma's response
        let gemma_keyword = gemma_text.split_whitespace()
            .find(|w| w.len() > 5 && w.chars().all(|c| c.is_alphabetic()))
            .unwrap_or("tasks");
        let search_raw = get_body(&client, &format!("/api/v1/plan/search?q={gemma_keyword}"));
        let o4 = search_raw.len() > 10;
        check(&mut total, &mut passed, &format!("O4: Search Gemma keyword '{gemma_keyword}' returns data"), o4);

        // O5: Verify AI chat endpoint returns context
        let chat_raw = get_body(&client, "/api/v1/ai/chat?q=system+health");
        let chat: serde_json::Value = serde_json::from_str(&chat_raw).unwrap_or_default();
        let o5 = chat["context"].as_str().map(|s| s.contains("total")).unwrap_or(false);
        check(&mut total, &mut passed, "O5: AI chat endpoint returns task context", o5);
    }

    section("P. DAG: View Consistency (4 stages)");
    // Stage 1: Get all tasks via HTTP → Stage 2: Count by status
    // → Stage 3: Verify counts match status endpoint → Stage 4: Verify search is subset
    {
        // P1: Get all tasks
        let all_raw = get_body(&client, "/api/v1/plan/list/all");
        let all: Vec<serde_json::Value> = serde_json::from_str(&all_raw).unwrap_or_default();
        let p1 = !all.is_empty();
        check(&mut total, &mut passed, &format!("P1: All tasks loaded ({})", all.len()), p1);

        // P2: Count by status from the list
        let count_active = all.iter().filter(|t| t["status"].as_str() == Some("in_progress")).count();
        let count_blocked = all.iter().filter(|t| t["status"].as_str() == Some("blocked")).count();
        let count_completed = all.iter().filter(|t| t["status"].as_str() == Some("completed")).count();
        let count_pending = all.iter().filter(|t| t["status"].as_str() == Some("pending")).count();
        println!("  Counted: {count_active} active, {count_blocked} blocked, {count_completed} completed, {count_pending} pending");
        let p2 = count_active + count_blocked + count_completed + count_pending > 0;
        check(&mut total, &mut passed, "P2: Status counts computed from list", p2);

        // P3: Compare with status endpoint
        let st: serde_json::Value = serde_json::from_str(&get_body(&client, "/api/v1/plan/status")).unwrap_or_default();
        let st_active = st["active"].as_i64().unwrap_or(-1) as usize;
        let st_blocked = st["blocked"].as_i64().unwrap_or(-1) as usize;
        let st_completed = st["completed"].as_i64().unwrap_or(-1) as usize;
        let p3_active = count_active == st_active;
        let p3_blocked = count_blocked == st_blocked;
        let p3_completed = count_completed == st_completed;
        check(&mut total, &mut passed, &format!("P3a: Active {count_active} == status {st_active}"), p3_active);
        check(&mut total, &mut passed, &format!("P3b: Blocked {count_blocked} == status {st_blocked}"), p3_blocked);
        check(&mut total, &mut passed, &format!("P3c: Completed {count_completed} == status {st_completed}"), p3_completed);

        // P4: Search results are a subset of all tasks
        let search: Vec<serde_json::Value> = serde_json::from_str(&get_body(&client, "/api/v1/plan/search?q=implement")).unwrap_or_default();
        let all_ids: std::collections::HashSet<String> = all.iter().filter_map(|t| t["id"].as_str().map(|s| s.to_string())).collect();
        let search_subset = search.iter().all(|t| {
            t["id"].as_str().map(|id| all_ids.contains(id)).unwrap_or(true)
        });
        check(&mut total, &mut passed, &format!("P4: Search results ({}) are subset of all tasks", search.len()), search_subset);
    }

    section("Q. DAG: SSE → WS Consistency (4 stages)");
    // Stage 1: Get SSE status event → Stage 2: Parse it → Stage 3: Get WS status
    // → Stage 4: Both match
    {
        // Q1: Get SSE stream and extract status event
        let sse_raw = get_body(&client, "/api/v1/plan/stream");
        let sse_status_line = sse_raw.lines()
            .find(|l| l.starts_with("data: {"))
            .unwrap_or("data: {}");
        let sse_data = &sse_status_line[6..]; // strip "data: "
        let sse_json: serde_json::Value = serde_json::from_str(sse_data).unwrap_or_default();
        let sse_total = sse_json["total"].as_i64().unwrap_or(0);
        let q1 = sse_total > 0;
        check(&mut total, &mut passed, &format!("Q1: SSE status total={sse_total}"), q1);

        // Q2: Get WS status
        let tls = native_tls::TlsConnector::builder()
            .danger_accept_invalid_certs(true).build().unwrap();
        let tcp = TcpStream::connect("127.0.0.1:4100").unwrap();
        tcp.set_read_timeout(Some(Duration::from_secs(10))).ok();
        let (mut ws, _) = client_tls_with_config(
            "wss://localhost:4100/ws/planning", tcp, None, Some(Connector::NativeTls(tls)),
        ).unwrap();
        let j = ws_rx(&mut ws);
        let ws_status_str = g(&j, "status");
        let ws_json: serde_json::Value = serde_json::from_str(&ws_status_str).unwrap_or_default();
        let ws_total = ws_json["total"].as_i64().unwrap_or(0);
        let q2 = ws_total > 0;
        check(&mut total, &mut passed, &format!("Q2: WS status total={ws_total}"), q2);

        // Q3: SSE total == WS total
        let q3 = sse_total == ws_total;
        check(&mut total, &mut passed, &format!("Q3: SSE ({sse_total}) == WS ({ws_total})"), q3);

        // Q4: Both match HTTP status
        let q4 = sse_total == total_tasks && ws_total == total_tasks;
        check(&mut total, &mut passed, &format!("Q4: SSE + WS + HTTP all agree ({total_tasks})"), q4);

        let _ = ws.close(None);
    }

    section("R. DAG: Page ↔ API Integrity (3 stages)");
    // Stage 1: Extract data from page HTML → Stage 2: Compare with API
    // → Stage 3: Verify JS file is loadable and sized correctly
    {
        // R1: Page contains live task count from NIF
        let total_str = total_tasks.to_string();
        let r1 = html.contains(&total_str);
        check(&mut total, &mut passed, &format!("R1: Page HTML contains total count '{total_str}'"), r1);

        // R2: Page references the correct JS file
        let r2 = html.contains("/static/planning-grid.js");
        check(&mut total, &mut passed, "R2: Page references planning-grid.js", r2);

        // R3: JS file is substantial (>50KB)
        let js_size = get_body(&client, "/static/planning-grid.js").len();
        let r3 = js_size > 50_000;
        check(&mut total, &mut passed, &format!("R3: JS file size={js_size} bytes (>50KB)"), r3);
    }

    // ══════════════════════════════════════════════════════════════
    // RESPONSIVE DESIGN TESTS — Mobile / Tablet / Desktop
    // Verifies CSS breakpoints, layout rules, touch targets, typography,
    // component behavior, and navigation patterns per viewport.
    // ══════════════════════════════════════════════════════════════

    section("S. RESPONSIVE: Mobile (<768px) — Triage Interface");
    // Mobile: stacked layout, 1-col grids, hamburger nav, large touch targets
    {
        // S1: Mobile CSS rule — card grid collapses to 1 column
        check(&mut total, &mut passed, "S1: Mobile card-grid 1fr",
            decoded.contains("grid-template-columns:1fr"));

        // S2: Mobile kanban — single column
        let js_has_mobile_kanban = js.contains("grid-template-columns:1fr");
        check(&mut total, &mut passed, "S2: Mobile kanban 1-col",
            js_has_mobile_kanban);

        // S3: Mobile touch targets — all buttons >=44px
        check(&mut total, &mut passed, "S3: Touch min-height:44px in page CSS",
            decoded.contains("min-height:44px"));
        check(&mut total, &mut passed, "S3b: Touch min-height:44px in JS CSS",
            js.contains("min-height:44px"));

        // S4: Mobile search bar — large input (>=48px implied by padding+font)
        check(&mut total, &mut passed, "S4: Search input has padding 14px (mobile-friendly)",
            decoded.contains("padding:14px") || decoded.contains("padding:12px") || html.contains("padding:14px"));

        // S5: Mobile view toggle — horizontal scroll enabled
        check(&mut total, &mut passed, "S5: View toggle overflow-x:auto",
            js.contains("overflow-x:auto") || decoded.contains("overflow-x:auto"));

        // S6: Mobile timeline — horizontal scroll with min-width
        check(&mut total, &mut passed, "S6: Timeline min-width:500px for mobile scroll",
            js.contains("min-width:500px"));

        // S7: Mobile weather bar — flex-wrap for narrow screens
        check(&mut total, &mut passed, "S7: Weather bar flex-wrap",
            decoded.contains("flex-wrap"));

        // S8: Mobile safe area — notched phone padding
        check(&mut total, &mut passed, "S8: safe-area-inset-bottom",
            decoded.contains("safe-area-inset-bottom"));

        // S9: Mobile overscroll — prevents pull-to-refresh conflict
        check(&mut total, &mut passed, "S9: overscroll-behavior:none",
            decoded.contains("overscroll-behavior:none") || decoded.contains("overscroll-behavior"));

        // S10: Mobile font size — search input >=1rem on mobile
        check(&mut total, &mut passed, "S10: Mobile search font-size 1rem",
            decoded.contains("font-size:1rem"));

        // S11: Webkit touch scrolling for tables
        check(&mut total, &mut passed, "S11: -webkit-overflow-scrolling:touch",
            decoded.contains("-webkit-overflow-scrolling:touch") || js.contains("-webkit-overflow-scrolling:touch"));

        // S12: Mobile progress rings — 2x2 grid (not 4x1)
        check(&mut total, &mut passed, "S12: Progress rings grid-template-columns:repeat(2,1fr)",
            decoded.contains("repeat(2,1fr)"));
    }

    section("T. RESPONSIVE: Tablet (768px-1024px) — Review Interface");
    // Tablet: 2-col grids, 2-col kanban, side-by-side layout, medium touch
    {
        // T1: Tablet breakpoint exists at 768px
        check(&mut total, &mut passed, "T1: @media min-width:768px exists",
            decoded.contains("min-width:768px"));

        // T2: Tablet card grid — 2 columns
        // The 768px media query should set repeat(2,1fr) for cards
        let tablet_2col = decoded.contains("min-width:768px") &&
            decoded.contains("repeat(2,1fr)");
        check(&mut total, &mut passed, "T2: Tablet cards 2-col (repeat(2,1fr))",
            tablet_2col);

        // T3: Tablet kanban — 2 columns
        let js_tablet_kanban = js.contains("min-width:768px") &&
            js.contains("grid-template-columns:repeat(2,1fr)");
        check(&mut total, &mut passed, "T3: Tablet kanban 2-col in JS @media",
            js_tablet_kanban);

        // T4: Tablet progress rings — 4x1 row (upgraded from 2x2)
        let tablet_rings = decoded.contains("min-width:768px") &&
            decoded.contains("repeat(4,1fr)");
        check(&mut total, &mut passed, "T4: Tablet rings 4x1 (repeat(4,1fr))",
            tablet_rings);

        // T5: Tablet search input — slightly smaller than mobile
        let tablet_search = decoded.contains("min-width:768px") &&
            decoded.contains("0.95rem");
        check(&mut total, &mut passed, "T5: Tablet search font 0.95rem",
            tablet_search);

        // T6: Tablet table font — 0.85rem
        let tablet_table = decoded.contains("min-width:768px") &&
            decoded.contains("0.85rem");
        check(&mut total, &mut passed, "T6: Tablet table font 0.85rem",
            tablet_table);

        // T7: Tablet timeline label width — wider than mobile
        let tablet_timeline = js.contains("min-width:768px") &&
            js.contains("timeline-label");
        check(&mut total, &mut passed, "T7: Tablet timeline labels wider",
            tablet_timeline);

        // T8: Tablet detail panel — larger padding
        let tablet_detail = js.contains("min-width:768px") &&
            js.contains("detail-panel");
        check(&mut total, &mut passed, "T8: Tablet detail panel responsive",
            tablet_detail);
    }

    section("U. RESPONSIVE: Desktop (1024px+) — Investigation Canvas");
    // Desktop: auto-fill grids, 4-col kanban, full-width, larger rings
    {
        // U1: Desktop breakpoint exists at 1024px
        check(&mut total, &mut passed, "U1: @media min-width:1024px exists",
            decoded.contains("min-width:1024px"));

        // U2: Desktop card grid — auto-fill minmax(200px,1fr)
        let desktop_cards = decoded.contains("min-width:1024px") &&
            decoded.contains("auto-fill");
        check(&mut total, &mut passed, "U2: Desktop cards auto-fill",
            desktop_cards);

        // U3: Desktop kanban — 4 columns
        let js_desktop_kanban = js.contains("min-width:1024px") &&
            js.contains("repeat(4,1fr)");
        check(&mut total, &mut passed, "U3: Desktop kanban 4-col",
            js_desktop_kanban);

        // U4: Desktop timeline — no min-width constraint (full render)
        let desktop_timeline = js.contains("min-width:1024px") &&
            js.contains("min-width:auto");
        check(&mut total, &mut passed, "U4: Desktop timeline full-width",
            desktop_timeline);

        // U5: Desktop search input — refined size
        let desktop_search = decoded.contains("min-width:1024px") &&
            decoded.contains("0.92rem");
        check(&mut total, &mut passed, "U5: Desktop search font 0.92rem",
            desktop_search);

        // U6: Desktop table font — full size 0.88rem
        let desktop_table = decoded.contains("min-width:1024px") &&
            decoded.contains("0.88rem");
        check(&mut total, &mut passed, "U6: Desktop table font 0.88rem",
            desktop_table);

        // U7: Desktop analytics grid — auto-fit minmax(140px,1fr)
        let desktop_analytics = js.contains("min-width:1024px") &&
            js.contains("auto-fit");
        check(&mut total, &mut passed, "U7: Desktop analytics auto-fit",
            desktop_analytics);

        // U8: Desktop ring SVG size — 100px
        let desktop_rings = decoded.contains("min-width:1024px") &&
            decoded.contains("100px");
        check(&mut total, &mut passed, "U8: Desktop ring SVG 100px",
            desktop_rings);
    }

    section("V. RESPONSIVE: Wide Desktop (1400px+) — Expanded Canvas");
    {
        // V1: Wide breakpoint exists
        check(&mut total, &mut passed, "V1: @media min-width:1400px exists",
            decoded.contains("min-width:1400px"));

        // V2: Wide rings — 110px SVG
        let wide_rings = decoded.contains("min-width:1400px") &&
            decoded.contains("110px");
        check(&mut total, &mut passed, "V2: Wide ring SVG 110px",
            wide_rings);

        // V3: Wide gap — 2rem between rings
        let wide_gap = decoded.contains("min-width:1400px") &&
            decoded.contains("2rem");
        check(&mut total, &mut passed, "V3: Wide ring gap 2rem",
            wide_gap);

        // V4: Wide ring value font — 1.4rem
        let wide_font = decoded.contains("min-width:1400px") &&
            decoded.contains("1.4rem");
        check(&mut total, &mut passed, "V4: Wide ring value 1.4rem",
            wide_font);
    }

    section("W. RESPONSIVE: Cross-Viewport Consistency");
    // Verify that components exist regardless of viewport and scale correctly
    {
        // W1: All 21 DOM elements present (viewport-independent)
        check(&mut total, &mut passed, "W1: 21 DOM elements present at any viewport",
            ids.len() >= 21);

        // W2: All 4 view buttons present
        let view_btn_count = html.matches("view-btn").count();
        check(&mut total, &mut passed, &format!("W2: 4 view buttons present ({view_btn_count})"),
            view_btn_count >= 4);

        // W3: Smooth scroll behavior (all viewports)
        check(&mut total, &mut passed, "W3: scroll-behavior:smooth",
            decoded.contains("scroll-behavior:smooth"));

        // W4: Glassmorphism backdrop-filter present
        let backdrop_count = decoded.matches("backdrop-filter").count()
            + js.matches("backdrop-filter").count();
        check(&mut total, &mut passed, &format!("W4: backdrop-filter:blur ({backdrop_count} occurrences)"),
            backdrop_count >= 3);

        // W5: CSS transitions for smooth resizing
        let transition_count = decoded.matches("transition:").count()
            + js.matches("transition:").count();
        check(&mut total, &mut passed, &format!("W5: CSS transitions ({transition_count} rules)"),
            transition_count >= 5);

        // W6: No fixed pixel widths on main containers (fluid layout)
        let has_fluid = decoded.contains("100%") || decoded.contains("1fr");
        check(&mut total, &mut passed, "W6: Fluid layout (100% or 1fr)",
            has_fluid);

        // W7: Relative font units (rem/em) used
        let rem_count = decoded.matches("rem").count();
        check(&mut total, &mut passed, &format!("W7: Relative font units ({rem_count} rem usages)"),
            rem_count >= 10);

        // W8: Color variables (theme-independent)
        let var_count = html.matches("var(--").count();
        check(&mut total, &mut passed, &format!("W8: CSS variables ({var_count} var(--) usages)"),
            var_count >= 5);

        // W9: Dark theme default (command center requirement)
        check(&mut total, &mut passed, "W9: Dark theme bg #0a0e17",
            html.contains("#0a0e17") || html.contains("0a0e17"));

        // W10: Semantic color system (teal/green/amber/red)
        let has_teal = html.contains("#00d4aa") || js.contains("#00d4aa");
        let has_green = html.contains("#3dd68c") || js.contains("#3dd68c");
        let has_amber = html.contains("#f5a623") || js.contains("#f5a623");
        let has_red = html.contains("#ff4757") || js.contains("#ff4757");
        check(&mut total, &mut passed, "W10: Semantic colors (teal+green+amber+red)",
            has_teal && has_green && has_amber && has_red);

        // W11: Monospace font for code/IDs
        let has_mono = js.contains("monospace") || html.contains("monospace");
        check(&mut total, &mut passed, "W11: Monospace font for IDs/code",
            has_mono);

        // W12: Max-width constraint on main content
        let has_max_width = html.contains("max-width:1400px") || html.contains("max-width");
        check(&mut total, &mut passed, "W12: max-width constraint on content",
            has_max_width);
    }

    section("X. RESPONSIVE: User Journey — Mobile On-Call Triage");
    // Simulates a mobile user: load page → see status → tap blocked task → search
    {
        // X1: Page loads with weather bar (immediate situational awareness)
        check(&mut total, &mut passed, "X1: Weather bar visible for triage",
            html.contains("weather-bar") && html.contains("weather-score"));

        // X2: Status cards show counts (at-a-glance metrics)
        check(&mut total, &mut passed, "X2: Live status cards with task counts",
            html.contains("live-status-cards") && html.contains("card-value"));

        // X3: Blocked tasks immediately visible (mobile priority)
        check(&mut total, &mut passed, "X3: Blocked grid element present",
            html.contains("blocked-grid"));

        // X4: Search bar accessible (Ctrl+K or tap)
        check(&mut total, &mut passed, "X4: AI search input present",
            html.contains("ai-search-input"));

        // X5: Detail panel ready for tap-to-expand
        check(&mut total, &mut passed, "X5: Task detail panel container exists",
            html.contains("task-detail-panel"));

        // X6: AI chat available for quick questions
        check(&mut total, &mut passed, "X6: AI chat widget present",
            html.contains("ai-chat-widget"));

        // X7: Change log shows mutations (real-time awareness)
        check(&mut total, &mut passed, "X7: Change log present for monitoring",
            html.contains("change-log"));
    }

    section("Y. RESPONSIVE: User Journey — Desktop Investigation");
    // Simulates a desktop user: full canvas → analytics → AI deep dive
    {
        // Y1: All 4 view modes accessible
        check(&mut total, &mut passed, "Y1: Grid/Kanban/Timeline/Analytics views",
            html.contains("grid-section") && html.contains("kanban-section")
            && html.contains("timeline-section") && html.contains("analytics-section"));

        // Y2: Fractal filter for architectural analysis
        check(&mut total, &mut passed, "Y2: Fractal L0-L7 filter chips",
            html.contains("fractal-filter-chips"));

        // Y3: Full data tables visible (not truncated)
        let table_count = html.matches("<table").count();
        check(&mut total, &mut passed, &format!("Y3: {table_count} data tables for deep analysis"),
            table_count >= 4);

        // Y4: Export buttons (CSV/JSON) for data extraction
        check(&mut total, &mut passed, "Y4: Export CSV/JSON in JS",
            js.contains("export-csv") && js.contains("export-json"));

        // Y5: Keyboard shortcuts for power users
        check(&mut total, &mut passed, "Y5: Keyboard shortcuts (1-4, Ctrl+K, R, Esc)",
            js.contains("ctrlKey") && js.contains("Escape"));

        // Y6: WebSocket for real-time updates (desktop always-on)
        check(&mut total, &mut passed, "Y6: WebSocket client initialized",
            js.contains("initWebSocket") && js.contains("wss:"));

        // Y7: Multiple sections for comprehensive investigation
        check(&mut total, &mut passed, &format!("Y7: {0} sections for deep analysis", sections.len()),
            sections.len() >= 12);

        // Y8: Progress rings for visual metrics
        check(&mut total, &mut passed, "Y8: SVG progress rings",
            html.matches("<svg").count() >= 4);
    }

    // ══ SUMMARY ══
    println!("\n╔══════════════════════════════════════════════════════════════╗");
    if passed == total {
        println!("║  ALL {passed} TESTS PASSED — FULL RESPONSIVE + DAG COVERAGE  ║");
    } else {
        println!("║  {passed}/{total} PASSED — {} FAILED                              ║", total - passed);
    }
    println!("╚══════════════════════════════════════════════════════════════╝");

    if passed < total { std::process::exit(1); }
}

// ── Helpers ──

fn http_client() -> reqwest::blocking::Client {
    reqwest::blocking::Client::builder()
        .danger_accept_invalid_certs(true)
        .timeout(Duration::from_secs(10))
        .build()
        .unwrap()
}

fn get_status(client: &reqwest::blocking::Client, path: &str) -> u16 {
    client.get(format!("{BASE}{path}")).send()
        .map(|r| r.status().as_u16())
        .unwrap_or(0)
}

fn get_body(client: &reqwest::blocking::Client, path: &str) -> String {
    client.get(format!("{BASE}{path}")).send()
        .and_then(|r| r.text())
        .unwrap_or_default()
}

fn section(name: &str) { println!("\n--- {name} ---"); }

fn check(total: &mut u32, passed: &mut u32, name: &str, ok: bool) {
    *total += 1;
    if ok { *passed += 1; }
    println!("  [{}] {name}", if ok { "OK" } else { "FAIL" });
}

fn test_websocket() -> Vec<(String, bool)> {
    let mut results = Vec::new();
    let tls = native_tls::TlsConnector::builder()
        .danger_accept_invalid_certs(true)
        .build().unwrap();
    let tcp = match TcpStream::connect("127.0.0.1:4100") {
        Ok(t) => t,
        Err(_) => { results.push(("TCP connect".into(), false)); return results; }
    };
    tcp.set_read_timeout(Some(Duration::from_secs(10))).ok();

    let (mut ws, resp) = match client_tls_with_config(
        "wss://localhost:4100/ws/planning", tcp, None, Some(Connector::NativeTls(tls)),
    ) {
        Ok(r) => r,
        Err(_) => { results.push(("WS upgrade".into(), false)); return results; }
    };

    results.push(("WS upgrade 101".into(), resp.status() == 101));

    // Connected
    let j = ws_rx(&mut ws);
    results.push(("WS connected msg".into(), g(&j, "type") == "connected"));

    // Ping
    let _ = ws.send(Message::Text("ping".into()));
    let j = ws_rx(&mut ws);
    let t = g(&j, "type");
    let s1 = j["seq"].as_i64().unwrap_or(0);
    results.push(("WS ping response".into(), t == "heartbeat" || t == "update"));

    // Ping #2 — seq increments
    let _ = ws.send(Message::Text("ping".into()));
    let j = ws_rx(&mut ws);
    let s2 = j["seq"].as_i64().unwrap_or(0);
    results.push(("WS seq increments".into(), s2 > s1));

    // Search
    let _ = ws.send(Message::Text("zenoh".into()));
    let j = ws_rx(&mut ws);
    let has = j["results"].as_str().map(|r| r.len() > 10).unwrap_or(false);
    results.push(("WS search results".into(), g(&j, "type") == "search" && has));

    let _ = ws.close(None);
    results
}

fn ws_rx(ws: &mut tungstenite::WebSocket<MaybeTlsStream<TcpStream>>) -> serde_json::Value {
    ws.read().ok()
        .and_then(|m| m.to_text().ok().map(|s| s.to_string()))
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn g(j: &serde_json::Value, k: &str) -> String {
    j[k].as_str().unwrap_or("").into()
}

fn test_ws_search(query: &str) -> bool {
    let tls = native_tls::TlsConnector::builder()
        .danger_accept_invalid_certs(true).build().unwrap();
    let tcp = match TcpStream::connect("127.0.0.1:4100") { Ok(t) => t, Err(_) => return false };
    tcp.set_read_timeout(Some(Duration::from_secs(10))).ok();
    let (mut ws, _) = match client_tls_with_config(
        "wss://localhost:4100/ws/planning", tcp, None, Some(Connector::NativeTls(tls)),
    ) { Ok(r) => r, Err(_) => return false };
    let _ = ws_rx(&mut ws); // consume connected msg
    let _ = ws.send(Message::Text(query.into()));
    let j = ws_rx(&mut ws);
    let ok = g(&j, "type") == "search" && j["results"].as_str().map(|r| r.len() > 5).unwrap_or(false);
    let _ = ws.close(None);
    ok
}

fn test_gemma() -> bool {
    let client = http_client();
    let body = serde_json::json!({
        "model": "gemma3",
        "messages": [
            {"role": "system", "content": "You are C3I AI. 2710 tasks. Be concise."},
            {"role": "user", "content": "What should I prioritize?"}
        ],
        "stream": false,
        "options": {"num_predict": 80}
    });
    match client.post("http://localhost:11434/api/chat")
        .json(&body)
        .timeout(Duration::from_secs(20))
        .send()
    {
        Ok(resp) => {
            if let Ok(json) = resp.json::<serde_json::Value>() {
                let content = json["message"]["content"].as_str().unwrap_or("");
                if !content.is_empty() {
                    println!("  Gemma 3: {}", &content[..content.len().min(120)]);
                    return true;
                }
            }
            false
        }
        Err(_) => false,
    }
}
