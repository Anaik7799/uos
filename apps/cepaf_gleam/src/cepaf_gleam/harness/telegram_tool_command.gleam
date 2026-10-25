//// Pure Telegram tool selection. Selection never grants effect authority.
import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_task_command as task_command
import cepaf_gleam/harness/telegram_knowledge_report as knowledge
import cepaf_gleam/harness/telegram_rete_report as rete
import cepaf_gleam/harness/telegram_verification_report as verification
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Selection {
  Help
  CancelLease(job:String,reason:String)
  Doctor
  Rete(facts:String)
  Storage
  Checklist
  Aspects(selector:String)
  Ecology
  Matrix
  SystemHealth
  Ha
  Fmea(task: String)
  KernelVersion
  Peers
  Board
  Search(query: String)
  Knowledge(view: String, query: String)
  Plan
  Task(String)
}

pub fn help() -> String {
  "Telegram tools (/action is an alias for /tool):\n"
  <> "/tool evaluate_rete {\"facts\":\"watchdog=true,mesh_running=true\"} — evaluate supplied facts; grants no authority.\n"
  <> "/tool query_checklist {} and query_aspects {} or {\"aspect\":\"A01\"} — configured candidate records, not gate execution.\n"
  <> "/tool query_storage {} — host capacity/device observations and bounded policy checks.\n"
  <> "/tool query_ecology {} — local participant snapshot; service health unverified.\n"
  <> "/tool query_matrix_versions {} — observed Matrix client API versions.\n"
  <> "/tool query_doctor {} — diagnostic provenance; live runtime checks are not inferred.\n"
  <> "/tool query_fmea {} or {\"task_id\":\"TASK_ID\"} — recorded risk assessments in the configured plan.\n"
  <> "/tool query_system_health {} — bounded service reachability and local Telegram state.\n"
  <> "/tool query_ha {} — current Telegram BEAM runtime pressure; cluster failover remains unverified.\n"
  <> "/tool query_zigvm_version {} — installed pinned executable version only.\n"
  <> "/tool query_peers {} — canonical session heartbeat observations.\n"
  <> "/tool query_board {} — verified coordination message metadata counts.\n"
  <> "/tool query_knowledge {\"view\":\"wiki\",\"query\":\"text\"} — observed wiki/zk documents.\n"
  <> "/tool query_search {\"query\":\"text\"} — configured task IDs/states and wiki/zk documents.\n"
  <> "/tool query_saplan {} — current configured plan snapshot.\n"
  <> "/tool query_task {\"task_id\":\"TASK_ID\"} — task detail in the configured plan only.\n"
  <> "/tool cancel_job_lease <job_id> -- <reason> — requests an approved lease revocation; worker termination is separate.\n"
  <> "/approval list — find pending controlled requests; /approval propose <request_id> — view the exact signing challenge; /approval submit <request_id> <role> <signed_receipt> — collect independent signatures; /approval withdraw <request_id> — withdraw your unexecuted pending request.\n"
  <> "Arguments cannot change the plan, database, path or authority. Other tools are unavailable."
}

fn split_name(chars: List(String), acc: List(String)) -> #(String, String) {
  case chars {
    [] -> #(list.reverse(acc) |> string.join(""), "")
    [c, ..rest] -> case c {
      " " | "\t" | "\n" -> #(
        list.reverse(acc) |> string.join(""),
        string.join(rest, "") |> string.trim,
      )
      _ -> split_name(rest, [c, ..acc])
    }
  }
}

fn empty_arguments(raw: String, selection: Selection) -> Result(Selection, String) {
  case string.byte_size(raw) <= 256 {
    False -> Error("Tool arguments exceed the 256 byte limit.")
    True -> case raw {
      "" -> Ok(selection)
      _ -> case json.parse(raw, decode.dict(decode.string, decode.dynamic)) {
        Ok(entries) -> case dict.size(entries) == 0 {
          True -> Ok(selection)
          False -> Error("This read tool requires absent arguments or an empty JSON object.")
        }
        _ -> Error("This read tool requires absent arguments or an empty JSON object.")
      }
    }
  }
}

fn task_arguments(raw: String) -> Result(Selection, String) {
  use _ <- result.try(case string.byte_size(raw) <= 1024 {
    True -> Ok(Nil)
    False -> Error("Task arguments exceed the 1024 byte limit.")
  })
  use entries <- result.try(json.parse(raw, decode.dict(decode.string, decode.dynamic))
    |> result.replace_error("Expected a JSON object containing only task_id."))
  use _ <- result.try(case dict.size(entries) == 1 {
    True -> Ok(Nil)
    False -> Error("Expected exactly one task_id field; scope overrides are refused.")
  })
  use value <- result.try(dict.get(entries, "task_id")
    |> result.replace_error("Expected a task_id field."))
  use raw_id <- result.try(decode.run(value, decode.string)
    |> result.replace_error("task_id must be a string."))
  use task <- result.try(task_command.parse_task_id(raw_id)
    |> result.replace_error("Invalid task identifier."))
  case raw_id == task {
    True -> Ok(Task(task))
    False -> Error("Task identifier must not have surrounding whitespace.")
  }
}

pub fn parse(args: String) -> Result(Selection, String) {
  // Reuse canonical input bounds and control-character validation.
  use invocation <- result.try(commands.parse("/tool " <> args)
    |> result.replace_error("Invalid bounded tool arguments."))
  let #(name, tail) = split_name(string.to_graphemes(invocation.args), [])
  case name {
    "" | "help" -> empty_arguments(tail, Help)
    "cancel_job_lease" -> cancel_arguments(tail)
    "evaluate_rete" -> rete_arguments(tail)
    "query_checklist" -> empty_arguments(tail, Checklist)
    "query_aspects" -> aspects_arguments(tail)
    "query_storage" -> empty_arguments(tail, Storage)
    "query_ecology" -> empty_arguments(tail, Ecology)
    "query_matrix_versions" -> empty_arguments(tail, Matrix)
    "query_doctor" -> empty_arguments(tail, Doctor)
    "query_system_health" -> empty_arguments(tail, SystemHealth)
    "query_ha" -> empty_arguments(tail, Ha)
    "query_fmea" -> fmea_arguments(tail)
    "query_peers" -> empty_arguments(tail, Peers)
    "query_search" -> search_arguments(tail)
    "query_knowledge" -> knowledge_arguments(tail)
    "query_board" -> empty_arguments(tail, Board)
    "query_zigvm_version" -> empty_arguments(tail, KernelVersion)
    "query_saplan" -> empty_arguments(tail, Plan)
    "query_task" -> task_arguments(tail)
    _ -> Error("Tool unavailable. Use /tool help for supported read tools.")
  }
}

fn knowledge_arguments(raw: String) -> Result(Selection, String) {
  let raw = case raw { "" -> "{}" _ -> raw }
  use entries <- result.try(json.parse(raw,decode.dict(decode.string,decode.dynamic))
    |> result.replace_error("Expected optional view and query fields."))
  use _ <- result.try(case string.byte_size(raw) <= 1024
    && list.all(dict.keys(entries),fn(key){key == "view" || key == "query"}) {
    True -> Ok(Nil)
    False -> Error("Knowledge scope overrides are refused.")
  })
  use view <- result.try(case dict.get(entries,"view") {
    Error(_) -> Ok("all")
    Ok(value) -> decode.run(value,decode.string) |> result.replace_error("Invalid view.")
  })
  use query <- result.try(case dict.get(entries,"query") {
    Error(_) -> Ok("")
    Ok(value) -> decode.run(value,decode.string) |> result.replace_error("Invalid query.")
  })
  use clean <- result.try(knowledge.validate_query(query))
  case list.contains(["wiki","zk","all"],view) {
    True -> Ok(Knowledge(view,clean))
    False -> Error("View must be wiki, zk or all.")
  }
}

fn search_arguments(raw: String) -> Result(Selection,String) {
  let raw=case raw { "" -> "{}" _ -> raw }
  use entries <- result.try(json.parse(raw,decode.dict(decode.string,decode.dynamic))
    |> result.replace_error("Expected an optional query field."))
  use _ <- result.try(case string.byte_size(raw)<=1024 && list.all(dict.keys(entries),fn(k){k=="query"}) {
    True -> Ok(Nil)
    False -> Error("Search scope overrides are refused.")
  })
  use query <- result.try(case dict.get(entries,"query") {
    Error(_) -> Ok("")
    Ok(q) -> decode.run(q,decode.string) |> result.replace_error("Invalid search query.")
  })
  knowledge.validate_query(query) |> result.map(Search)
}

fn cancel_arguments(raw:String) -> Result(Selection,String) {
  case string.split(raw," -- ") {
    [job,reason] -> {
      let valid_job=string.byte_size(job)>0 && string.byte_size(job)<=240
        && !string.contains(job,"..")
        && list.all(string.to_graphemes(job),fn(c) {
          string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:",c)
        })
      case valid_job && string.trim(reason)==reason && reason!="" && string.byte_size(reason)<=256 {
        True -> Ok(CancelLease(job,reason))
        False -> Error("Use cancel_job_lease <job_id> -- <bounded reason>.")
      }
    }
    _ -> Error("Use cancel_job_lease <job_id> -- <bounded reason>.")
  }
}

fn fmea_arguments(raw:String)->Result(Selection,String) {
  case empty_arguments(raw,Fmea("")) {
    Ok(selected)->Ok(selected)
    Error(_)->case task_arguments(raw) {
      Ok(Task(task))->Ok(Fmea(task))
      _->Error("Use query_fmea with no arguments or only task_id.")
    }
  }
}

fn rete_arguments(raw:String)->Result(Selection,String) {
 use _ <- result.try(case string.byte_size(raw)<=512 {True->Ok(Nil) False->Error("Invalid bounded facts.")})
 use entries <- result.try(json.parse(raw,decode.dict(decode.string,decode.string)) |> result.replace_error("Expected only a facts string."))
 use value <- result.try(case dict.to_list(entries) {
   [#("facts",value)] -> Ok(value)
   _ -> Error("Expected only a facts string.")
 })
 rete.canonicalize(value) |> result.map(Rete)
}

fn aspects_arguments(raw:String)->Result(Selection,String) {
 case empty_arguments(raw,Aspects("")) {
  Ok(s)->Ok(s)
  Error(_)->{
   use _ <- result.try(case string.byte_size(raw)<=256 {True->Ok(Nil) False->Error("Invalid aspect scope.")})
   use entries <- result.try(json.parse(raw,decode.dict(decode.string,decode.string)) |> result.replace_error("Expected only an aspect code."))
   case dict.to_list(entries) {
    [#("aspect",code)] -> case verification.valid_scope("aspects",code) && code!="" {
      True->Ok(Aspects(code)) False->Error("Aspect must be A01 through A17.")
    }
    _->Error("Expected only an aspect code.")
   }
  }
 }
}
