//// Combine independently observed sources without turning partial failure into empty success.
import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string

fn envelope(schema: String, authority: String) -> decode.Decoder(String) {
  use s <- decode.field("schema",decode.string)
  use status <- decode.field("status",decode.string)
  use a <- decode.field("authority",decode.string)
  use admission <- decode.field("runtime_admission",decode.string)
  case s == schema && status == "observed" && a == authority && admission == "NOT_GRANTED" {
    True -> decode.success(s)
    False -> decode.failure("observed search source",s)
  }
}
fn source(raw: Result(String,String), schema: String, authority: String, limit: Int) -> Result(String,Nil) {
  use text <- result.try(raw |> result.replace_error(Nil))
  use _ <- result.try(case string.byte_size(text) <= limit {
    True -> Ok(Nil)
    False -> Error(Nil)
  })
  use _ <- result.try(json.parse(text,envelope(schema,authority)) |> result.replace_error(Nil))
  Ok(text)
}
fn render(value: Result(String,Nil)) -> String {
  case value {
    Ok(raw) -> raw
    Error(_) -> "{\"status\":\"unavailable\",\"runtime_admission\":\"NOT_GRANTED\"}"
  }
}
pub fn combine(tasks: Result(String,String), documents: Result(String,String)) -> String {
  let tasks=source(tasks,"uos.telegram.task_search.v1","NONE",16384)
  let docs=source(documents,"uos.telegram.knowledge.v1","observation_only",32768)
  let status=case tasks,docs {
    Ok(_),Ok(_) -> "observed"
    Error(_),Error(_) -> "unavailable"
    _,_ -> "partial"
  }
  // Only schema-validated JSON is embedded; command text and raw errors are omitted.
  "{\"schema\":\"uos.telegram.search.v1\",\"status\":\"" <> status
  <> "\",\"authority\":\"NONE\",\"runtime_admission\":\"NOT_GRANTED\","
  <> "\"scope\":\"configured_plan_ids_and_states_plus_wiki_zk_documents\","
  <> "\"tasks\":" <> render(tasks) <> ",\"documents\":" <> render(docs) <> "}"
}
