//// Exact public shell and authenticated Mini App data routing.

import cepaf_gleam/telegram/mini_alerts_view
import cepaf_gleam/telegram/mini_health_view
import cepaf_gleam/telegram/mini_chat_view
import cepaf_gleam/telegram/mini_memory_view
import cepaf_gleam/telegram/mini_control_view
import cepaf_gleam/telegram/mini_control
import cepaf_gleam/telegram/mini_api
import cepaf_gleam/telegram/mini_runtime
import cepaf_gleam/telegram/mini_view
import cepaf_gleam/telegram/theme
import cepaf_gleam/telegram/types
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/result

pub fn is_mini_app_path(path: String) -> Bool {
  mini_api.owns_path(path)
}

pub fn route(path: String) -> String {
  case mini_api.parse_page(path) {
    Ok(page) -> render_shell(page)
    Error(_) ->
      "<!doctype html><html lang=\"en\"><title>Not found</title><h1>Page not found</h1></html>"
  }
}

fn render_shell(page: types.MiniAppPage) -> String {
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>UOS Telegram</title><style>"
  <> theme.mini_app_css()
  <> "#mini-fields{min-width:0;max-width:100%}#mini-topic{max-width:100%;width:100%;min-height:48px}#mini-live{margin-top:12px}#mini-fields dt,#mini-fields dd{display:block;min-width:0;max-width:100%;margin-inline:0;overflow-wrap:anywhere;word-break:break-word;white-space:normal}"
  <> "</style><script defer src=\"https://telegram.org/js/telegram-web-app.js\"></script><script defer src=\"/mini-app/client.js\"></script></head><body>"
  <> mini_view.public_page(page)
  <> "</body></html>"
}

fn public_response(
  body: String,
  status: Int,
  content_type: String,
) -> response.Response(String) {
  response.new(status)
  |> response.set_body(body)
  |> response.set_header("content-type", content_type)
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-content-type-options", "nosniff")
  |> response.set_header("referrer-policy", "no-referrer")
  |> response.set_header(
    "content-security-policy",
    "default-src 'none'; script-src 'self' https://telegram.org; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors https://web.telegram.org https://*.telegram.org",
  )
}

pub fn handle(req: request.Request(String)) -> response.Response(String) {
  case req.path {
    "/mini-app/api/action" | "/mini-app/api/action-receipt" -> mini_control.handle(req)
    "/mini-app/api/data" ->
      mini_api.handle_data(
        req,
        mini_runtime.load_configuration(),
        mini_runtime.clock,
        mini_runtime.observe,
      )
    _ ->
      case req.method {
        http.Get | http.Head -> {
          let response = case req.path {
            "/mini-app/client.js" ->
              public_response(
                client_script() <> "\n" <> mini_control_view.script() <> "\n" <> mini_memory_view.script() <> "\n" <> mini_chat_view.script() <> "\n" <> mini_health_view.script() <> "\n" <> mini_alerts_view.script(),
                200,
                "text/javascript; charset=utf-8",
              )
            _ ->
              case mini_api.parse_page(req.path) {
                Ok(_) ->
                  public_response(
                    route(req.path),
                    200,
                    "text/html; charset=utf-8",
                  )
                Error(_) ->
                  public_response(
                    "{\"error\":\"not_found\"}",
                    404,
                    "application/json",
                  )
              }
          }
          case req.method == http.Head {
            True -> response.set_body(response, "")
            False -> response
          }
        }
        _ ->
          case mini_api.parse_page(req.path) |> result.is_ok() {
            True ->
              public_response(
                "{\"error\":\"method_not_allowed\"}",
                405,
                "application/json",
              )
              |> response.set_header("allow", "GET, HEAD")
            False ->
              public_response(
                "{\"error\":\"not_found\"}",
                404,
                "application/json",
              )
          }
      }
  }
}

fn client_script() -> String {
  "(() => {\n  const root = document.getElementById('mini-app');\n  if (!root) return;\n  const status = document.getElementById('mini-status');\n  const button = document.getElementById('mini-refresh');\n  const fields = document.getElementById('mini-fields');\n  const topic = document.getElementById('mini-topic');\n  const live = document.getElementById('mini-live');\n  const liveStatus = document.getElementById('mini-live-status');\n  let busy = false, queued = false, generation = 0, controller = null;\n  let timer = null, liveUntil = 0, closed = false;\n  function stopLive(message = 'Live refresh stopped.') {\n    clearTimeout(timer); timer = null; liveUntil = 0;\n    if (live) { live.textContent = 'Start live refresh'; live.setAttribute('aria-pressed', 'false'); }\n    if (liveStatus) liveStatus.textContent = message;\n  }\n  function clearTopics() {\n    if (!topic) return;\n    topic.replaceChildren(new Option('Load your allowed topics first', ''));\n    topic.disabled = true; live.disabled = true;\n  }\n  function updateTopics(entries, selected) {\n    if (!topic) return;\n    const keys = entries.filter(([key]) => key.startsWith('Available topic ')).map(([,value]) => value);\n    if (keys.length > 20 || new Set(keys).size !== keys.length) throw new Error('invalid topics');\n    topic.replaceChildren(new Option('Select a topic', ''));\n    for (const key of keys) topic.append(new Option(key, key));\n    topic.disabled = keys.length === 0;\n    topic.value = keys.includes(selected) ? selected : '';\n    live.disabled = !topic.value;\n    if (!topic.value && liveUntil) stopLive('Select an allowed topic to start live refresh.');\n  }\n  async function refresh() {\n    if (closed || document.hidden) return;\n    clearTimeout(timer); timer = null;\n    if (busy) { queued = true; return; }\n    queued = false;\n    const current = ++generation;\n    const selected = topic ? topic.value : '';\n    fields.replaceChildren();\n    window.dispatchEvent(new Event('mini-observation-start'));\n    const tg = window.Telegram && window.Telegram.WebApp;\n    if (!tg || !tg.initData) {\n      clearTopics(); stopLive('Authentication is required for live refresh.');\n      status.textContent = 'Telegram authentication is unavailable. Open this page through the configured bot.';\n      return;\n    }\n    busy = true; button.disabled = true;\n    status.textContent = 'Loading current data…';\n    const abort = new AbortController(); controller = abort;\n    const deadline = setTimeout(() => abort.abort(), 6000);\n    let observed = false;\n    try {\n      const body = {init_data: tg.initData, path: root.dataset.page};\n      if (selected) body.topic = selected;\n      const reply = await fetch('/mini-app/api/data', {\n        method: 'POST', headers: {'content-type': 'application/json'},\n        body: JSON.stringify(body), credentials: 'omit', cache: 'no-store',\n        redirect: 'error', signal: abort.signal\n      });\n      if (current !== generation || closed) return;\n      if (!reply.ok) {\n        clearTopics(); stopLive('Live refresh stopped after a refused request.');\n        status.textContent = reply.status === 401 ? 'Authentication expired or access is not allowed.' :\n          reply.status === 403 ? 'Access to this topic is not allowed.' :\n          reply.status === 503 ? 'The data service is unavailable or not configured.' : 'The data request was refused.';\n        return;\n      }\n      const data = await reply.json();\n      if (current !== generation || closed) return;\n      if (data.path !== root.dataset.page || !['observed', 'stale', 'unavailable'].includes(data.status)) throw new Error('invalid response');\n      if (data.status !== 'observed') {\n        clearTopics(); stopLive('Live refresh stopped because the source is unavailable.');\n        status.textContent = data.status === 'stale' ? 'The available observation is stale. Refresh to try again.' :\n          'The data source is unavailable or not configured.';\n        return;\n      }\n      const entries = Object.entries(data.fields || {});\n      if (entries.length > 100 || entries.some(([key, value]) => typeof value !== 'string' || key.length > 128 || value.length > 2048)) throw new Error('invalid fields');\n      updateTopics(entries, selected);\n      status.textContent = 'Observed at ' + new Date(data.observed_at * 1000).toISOString();\n      for (const [key, value] of entries) {\n        if ((root.dataset.page === '/mini-app/health' && /^Device [0-9]+$/.test(key)) || (root.dataset.page === '/mini-app/alerts' && (/^Alert [0-9]+$/.test(key) || ['Snapshot SHA256','Episode set SHA256','Owner incarnation','Reader user'].includes(key)))) continue;\n        const term = document.createElement('dt'), description = document.createElement('dd');\n        term.className = 'tg-list-cell'; description.className = 'tg-list-title';\n        term.textContent = key; description.textContent = value;\n        fields.append(term, description);\n      }\n      window.dispatchEvent(new CustomEvent('mini-observed',{detail:data.fields}));\n      observed = true;\n    } catch (_) {\n      if (current === generation && !closed) {\n        fields.replaceChildren(); clearTopics(); stopLive('Live refresh stopped after a connection failure.');\n        status.textContent = 'The data request could not complete. Check connectivity and try again.';\n      }\n    } finally {\n      clearTimeout(deadline);\n      if (controller === abort) controller = null;\n      busy = false; button.disabled = false;\n      if (queued && !closed && !document.hidden) { queued = false; timer = setTimeout(refresh, 0); }\n      else if (observed && liveUntil && !closed && !document.hidden) {\n        if (performance.now() >= liveUntil) stopLive('Five-minute live refresh limit reached.');\n        else timer = setTimeout(() => {\n          if (performance.now() >= liveUntil) stopLive('Five-minute live refresh limit reached.');\n          else refresh();\n        }, Math.min(2000, liveUntil - performance.now()));\n      }\n    }\n  }\n  button.addEventListener('click', refresh);\n  if (topic) {\n    topic.addEventListener('change', () => {\n      stopLive(); ++generation;\n      if (controller) controller.abort();\n      fields.replaceChildren(); live.disabled = !topic.value;\n      refresh();\n    });\n    live.addEventListener('click', () => {\n      if (liveUntil) { stopLive(); return; }\n      if (!topic.value || closed || document.hidden) return;\n      liveUntil = performance.now() + 300000;\n      live.textContent = 'Stop live refresh'; live.setAttribute('aria-pressed', 'true');\n      liveStatus.textContent = 'Polling the selected topic every two seconds; stops within five minutes or on failure.';\n      refresh();\n    });\n  }\n  function suspend() {\n    ++generation; queued = false; stopLive('Live refresh stopped because the page is inactive.');\n    if (controller) controller.abort();\n  }\n  document.addEventListener('visibilitychange', () => { if (document.hidden) suspend(); });\n  window.addEventListener('pagehide', () => { closed = true; suspend(); });\n  const tg = window.Telegram && window.Telegram.WebApp;\n  if (tg) { tg.ready(); tg.expand(); }\n})();"
}
