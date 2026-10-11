//// Exact public shell and authenticated Mini App data routing.

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
                client_script(),
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
  "(() => {\n  const root = document.getElementById('mini-app');\n  if (!root) return;\n  const status = document.getElementById('mini-status');\n  const button = document.getElementById('mini-refresh');\n  const fields = document.getElementById('mini-fields');\n  let busy = false;\n  async function refresh() {\n    if (busy) return;\n    fields.replaceChildren();\n    const tg = window.Telegram && window.Telegram.WebApp;\n    if (!tg || !tg.initData) {\n      status.textContent = 'Telegram authentication is unavailable. Open this page through the configured bot.';\n      return;\n    }\n    busy = true; button.disabled = true;\n    status.textContent = 'Loading current data…';\n    const controller = new AbortController();\n    const deadline = setTimeout(() => controller.abort(), 6000);\n    try {\n      const reply = await fetch('/mini-app/api/data', {\n        method: 'POST', headers: {'content-type': 'application/json'},\n        body: JSON.stringify({init_data: tg.initData, path: root.dataset.page}),\n        credentials: 'omit', cache: 'no-store', redirect: 'error', signal: controller.signal\n      });\n      if (!reply.ok) {\n        status.textContent = reply.status === 401 ? 'Authentication expired or access is not allowed.' :\n          reply.status === 503 ? 'The data service is unavailable or not configured.' : 'The data request was refused.';\n        return;\n      }\n      const data = await reply.json();\n      if (data.path !== root.dataset.page || !['observed', 'stale', 'unavailable'].includes(data.status)) {\n        throw new Error('invalid response');\n      }\n      if (data.status !== 'observed') {\n        status.textContent = data.status === 'stale' ? 'The available observation is stale. Refresh to try again.' :\n          'This page has no integrated data source yet.';\n        return;\n      }\n      const entries = Object.entries(data.fields || {});\n      if (entries.length > 100 || entries.some(([key, value]) => typeof value !== 'string' || key.length > 128 || value.length > 2048)) {\n        throw new Error('invalid fields');\n      }\n      status.textContent = 'Observed at ' + new Date(data.observed_at * 1000).toISOString();\n      for (const [key, value] of entries) {\n        const term = document.createElement('dt');\n        const description = document.createElement('dd');\n        term.className = 'tg-list-cell'; description.className = 'tg-list-title';\n        term.textContent = key; description.textContent = value;\n        fields.append(term, description);\n      }\n    } catch (_) {\n      fields.replaceChildren();\n      status.textContent = 'The data request could not complete. Check connectivity and try again.';\n    } finally {\n      clearTimeout(deadline); busy = false; button.disabled = false;\n    }\n  }\n  button.addEventListener('click', refresh);\n  const tg = window.Telegram && window.Telegram.WebApp;\n  if (tg) { tg.ready(); tg.expand(); }\n})();"
}
