//// Private test adapter; injected only with IsolatedTestPaths.
import cepaf_gleam/harness/telegram_service as service
import gleam/json
import gleam/option.{Some}
import gleam/result
import simplifile
import uos_swarm/openrouter_worker as model

@external(erlang, "telegram_test_authority", "seed_test_sa_plan_task")
fn seed_task(db: String, plan: String, task: String, worker: String, attempt: Int, until: Int)
  -> Result(Nil, gleam_dynamic.Dynamic)

import gleam/dynamic as gleam_dynamic

pub fn configure(config: service.ServiceConfiguration, mode: String, limit: Int, db: String)
  -> service.ServiceConfiguration {
  case mode {
    "disabled" -> config
    "free" -> service.ServiceConfiguration(..config, conversation: service.FreeConversation(limit, 10_000))
    _ -> {
      let io = model.Io(
        credential: fn() { Some("test-only-dummy") },
        now_ms: fn() { service.ffi_system_now_utc_us() / 1000 },
        fetch_prices: fn(_) {
          case mode {
            "expire" -> {
              let _ = seed_task(service.resolve_sa_plan_db(config.authority_paths),
                config.plan_id, config.task_id, config.worker_id, config.expected_task_attempt, 1)
              Nil
            }
            _ -> Nil
          }
          Ok(#(200, "{\"data\":[{\"id\":\"openrouter/free\",\"pricing\":{\"prompt\":\"0\",\"completion\":\"0\"}}]}"))
        },
        post: fn(_, _, _) {
          let _ = simplifile.write(db <> ".model-post", "called")
          case mode {
            "fail" -> Error("PRIVATE PROVIDER BODY MUST NOT LEAK")
            _ -> Ok(#(200, json.object([
              #("model",json.string("fixture/free")),
              #("choices",json.array([json.object([
                #("finish_reason",json.string("stop")),
                #("message",json.object([#("content",json.string("Model reply"))])),
              ])], fn(x) { x })),
              #("usage",json.object([
                #("prompt_tokens",json.int(20)),#("completion_tokens",json.int(4)),
                #("total_tokens",json.int(24)),#("cost",json.float(0.0)),
              ])),
            ]) |> json.to_string))
          }
        },
      )
      service.ServiceConfiguration(..config, conversation: service.IsolatedConversation(limit, 10_000, io))
    }
  }
}
