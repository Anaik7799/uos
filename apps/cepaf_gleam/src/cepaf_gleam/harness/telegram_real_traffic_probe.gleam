//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_real_traffic_probe</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-JOURNEY-001, SC-JIDOKA-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Real-traffic smoke for the outbound gateway path: the production bot
//// credential is read from the durable vault store INSIDE this BEAM, a drain
//// and a ticker are started under a one-for-one supervisor exactly as a
//// deployment would start them, one Critical and one Notice are enqueued, and
//// the ticker delivers them through `telegram_http_client.send_message` to
//// the real Telegram API. The report carries counts, the alarms the ticker
//// raised and the message ids Telegram answered with; it never carries the
//// token.
////
//// This is an operational tool, not a test: it sends real messages to the
//// configured chat. It is run on purpose under a Sa-plan task, with the
//// chat id taken from the same vault store, never from an argument that a
//// typo could point at a stranger.

import cepaf_gleam/gateway/telegram_gateway_drain as drain
import cepaf_gleam/gateway/telegram_gateway_outbox as outbox
import cepaf_gleam/gateway/telegram_gateway_ticker as ticker
import cepaf_gleam/harness/telegram_http_client as http_client
import cepaf_gleam/harness/telegram_service as service
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/static_supervisor as sup
import gleam/string

pub type Report {
  Report(
    bot_id: Int,
    chat_id: Int,
    enqueued: Int,
    delivered: Int,
    failed: Int,
    uncertain: Int,
    ticks: Int,
    alarms: List(String),
    elapsed_ms: Int,
  )
}

@external(erlang, "uos_vault_file", "get")
fn vault_get(store: String, name: String, passphrase_file: String) -> Dynamic

@external(erlang, "telegram_real_traffic_probe_ffi", "ok_binary")
fn ok_binary(value: Dynamic) -> Result(String, String)

fn now_ms() -> Int {
  service.ffi_system_now_utc_us() / 1000
}

fn read(store: String, passphrase_file: String, name: String) -> Result(String, String) {
  ok_binary(vault_get(store, name, passphrase_file))
}

/// Send one Critical and one Notice through the real gateway path. `label`
/// is included in both texts so the operator can tell runs apart.
pub fn run(
  store: String,
  passphrase_file: String,
  token_name: String,
  chat_id_name: String,
  bot_id: Int,
  label: String,
) -> Result(Report, String) {
  case read(store, passphrase_file, token_name), read(store, passphrase_file, chat_id_name) {
    Error(e), _ -> Error("token_unreadable:" <> e)
    _, Error(e) -> Error("chat_id_unreadable:" <> e)
    Ok(token), Ok(chat_text) ->
      case int.parse(string.trim(chat_text)) {
        Error(_) -> Error("chat_id_not_an_integer")
        Ok(chat_id) -> {
          let started = now_ms()
          let config =
            service.development_service_configuration(
              transport.reviewed_local_configuration(
                "/tmp/uos-real-traffic-probe-unused/guardian",
                "0",
                "/tmp/uos-real-traffic-probe-unused/worker",
                "0",
                "/tmp/uos-real-traffic-probe-unused/store.sqlite3",
              ),
              http_client.TelegramHttpConfiguration(
                base_url: "https://api.telegram.org",
                bot_token: string.trim(token),
                timeout_ms: 15_000,
                max_response_bytes: 65_536,
              ),
              bot_id,
              [#(chat_id, chat_id)],
              "real-traffic-probe",
              1,
            )
          let #(drain_name, drain_spec) = service.gateway_drain_child(config, 8)
          let alarms = process.new_subject()
          let #(_ticker_name, ticker_spec) =
            service.gateway_ticker_child(config, drain_name, 500, 4, 60_000, alarms)
          case
            sup.new(sup.OneForOne)
            |> sup.add(drain_spec)
            |> sup.add(ticker_spec)
            |> sup.start
          {
            Error(_) -> Error("supervisor_start_failed")
            Ok(supervisor) -> {
              let d = process.named_subject(drain_name)
              let at = now_ms()
              let critical =
                outbox.Request(
                  kind: outbox.Critical,
                  chat_id: chat_id,
                  text: "UOS real-traffic probe (Critical) " <> label,
                  source_topic: "indrajaal/otel/span/critical",
                  observed_at_ms: at,
                  digest: "probe-critical-" <> label,
                )
              let notice =
                outbox.Request(
                  kind: outbox.Notice,
                  chat_id: chat_id,
                  text: "UOS real-traffic probe (Notice) " <> label,
                  source_topic: "indrajaal/otel/span/notice",
                  observed_at_ms: at,
                  digest: "probe-notice-" <> label,
                )
              let enqueued =
                list.count([critical, notice], fn(r) {
                  drain.enqueue(d, r, 2000) == Ok(Nil)
                })
              let counters = wait_delivered(d, enqueued, 30)
              let collected = collect_alarms(alarms, [])
              process.unlink(supervisor.pid)
              process.kill(supervisor.pid)
              Ok(Report(
                bot_id: bot_id,
                chat_id: chat_id,
                enqueued: enqueued,
                delivered: counters.delivered,
                failed: counters.failed,
                uncertain: counters.uncertain,
                ticks: counters.ticks,
                alarms: collected,
                elapsed_ms: now_ms() - started,
              ))
            }
          }
        }
      }
  }
}

fn wait_delivered(d, expected: Int, rounds: Int) -> drain.Counters {
  let counters = drain.counters(d, 2000)
  case counters.delivered + counters.failed + counters.uncertain >= expected || rounds <= 0 {
    True -> counters
    False -> {
      process.sleep(1000)
      wait_delivered(d, expected, rounds - 1)
    }
  }
}

fn collect_alarms(sink, acc: List(String)) -> List(String) {
  case process.receive(sink, 10) {
    Ok(alarm) -> collect_alarms(sink, [render(alarm), ..acc])
    Error(_) -> list.reverse(acc)
  }
}

fn render(alarm: ticker.Alarm) -> String {
  case alarm {
    ticker.Stale(oldest, age, n) ->
      "stale oldest=" <> int.to_string(oldest) <> " age_ms=" <> int.to_string(age) <> " uncertain=" <> int.to_string(n)
    ticker.Cleared(after) -> "cleared after_ms=" <> int.to_string(after)
    ticker.Unobserved(reason) -> "unobserved " <> reason
  }
}

/// A one-line rendering for an operator terminal; carries no secret.
pub fn render_report(report: Report) -> String {
  "bot=" <> int.to_string(report.bot_id)
  <> " chat=" <> int.to_string(report.chat_id)
  <> " enqueued=" <> int.to_string(report.enqueued)
  <> " delivered=" <> int.to_string(report.delivered)
  <> " failed=" <> int.to_string(report.failed)
  <> " uncertain=" <> int.to_string(report.uncertain)
  <> " ticks=" <> int.to_string(report.ticks)
  <> " alarms=[" <> string.join(report.alarms, "; ") <> "]"
  <> " elapsed_ms=" <> int.to_string(report.elapsed_ms)
}
