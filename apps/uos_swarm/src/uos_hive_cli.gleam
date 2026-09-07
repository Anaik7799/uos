//// Hive cognition CLI: dream (svapna), evolve, and the Hindu cognition-mirror
//// lookups from `agent_runtime`. Separate entry point from `uos_swarm.gleam`
//// (`gleam run -m uos_hive_cli -- <command>`) so ontology-round work on dream/
//// evolve never touches the main CLI's argument table.
////
//// `dream` opens no ETS table: it reads the ledger straight off disk with
//// `board.from_jsonl` (the same decoder `board.open` uses to restore its
//// chain state) rather than opening a live board.
////
////   dream <ledger.jsonl> [seed] [max] [out.acl]
////   evolve init <dream.json> <proposals.jsonl> <tier>
////   evolve record <proposals.jsonl> <id> <pass|fail> <evidence_ref>
////   evolve select <proposals.jsonl> <k> [seed]
////   evolve report <proposals.jsonl>
////   vritti <key> <value>
////   faculty <step>
////   (anything else)   prints this usage

import argv
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/agent_runtime
import uos_swarm/board
import uos_swarm/dream
import uos_swarm/evolve

const usage = "Hive cognition CLI. `gleam run -m uos_hive_cli -- <command>`:
  dream <ledger.jsonl> [seed] [max] [out.acl]
  evolve init <dream.json> <proposals.jsonl> <tier>
  evolve record <proposals.jsonl> <id> <pass|fail> <evidence_ref>
  evolve select <proposals.jsonl> <k> [seed]
  evolve report <proposals.jsonl>
  vritti <key> <value>
  faculty <step>"

pub fn main() -> Nil {
  case argv.load().arguments {
    ["dream", ledger] -> dream_cmd(ledger, 1, 5, None)
    ["dream", ledger, seed_s] ->
      dream_cmd(ledger, parse_int(seed_s, 1), 5, None)
    ["dream", ledger, seed_s, max_s] ->
      dream_cmd(ledger, parse_int(seed_s, 1), parse_int(max_s, 5), None)
    ["dream", ledger, seed_s, max_s, out] ->
      dream_cmd(ledger, parse_int(seed_s, 1), parse_int(max_s, 5), Some(out))
    ["evolve", "init", dream_path, proposals_path, tier] ->
      evolve_init(dream_path, proposals_path, tier)
    ["evolve", "record", proposals_path, id, verdict, evidence_ref] ->
      evolve_record(proposals_path, id, verdict, evidence_ref)
    ["evolve", "select", proposals_path, k_s] ->
      evolve_select(proposals_path, parse_int(k_s, 1), 1)
    ["evolve", "select", proposals_path, k_s, seed_s] ->
      evolve_select(proposals_path, parse_int(k_s, 1), parse_int(seed_s, 1))
    ["evolve", "report", proposals_path] -> evolve_report(proposals_path)
    ["vritti", key, value] -> vritti_cmd(key, value)
    ["faculty", step] -> faculty_cmd(step)
    _ -> io.println(usage)
  }
}

fn parse_int(s: String, default: Int) -> Int {
  int.parse(s) |> result.unwrap(default)
}

/// Conventional side-file: `slots.json`, a flat `{"key": "value", ...}`
/// object, read from the current directory when present. Absent or
/// unparseable -> an empty slot list, per the design ("uses an empty slot
/// list unless a `slots.json` path is given").
fn load_slots() -> List(#(String, String)) {
  case board.file_read("slots.json") {
    Ok(text) ->
      case
        json.parse(from: text, using: decode.dict(decode.string, decode.string))
      {
        Ok(d) -> dict.to_list(d)
        Error(_) -> []
      }
    Error(_) -> []
  }
}

fn dream_cmd(
  ledger_path: String,
  seed: Int,
  max: Int,
  out: Option(String),
) -> Nil {
  case board.file_read(ledger_path) {
    Ok(text) -> {
      let #(messages, _bad_lines) = board.from_jsonl(text)
      let slots = load_slots()
      let d = dream.svapna(messages, slots, seed, max)
      io.println(json.to_string(dream.to_json(d)))
      case out {
        Some(path) ->
          case board.file_write(path, dream.to_utterance_text(d, "hive-l1")) {
            Ok(_) -> io.println("wrote " <> path)
            Error(e) -> io.println("write error: " <> e)
          }
        None -> Nil
      }
    }
    Error(e) -> io.println("ledger error: " <> e)
  }
}

fn evolve_init(
  dream_path: String,
  proposals_path: String,
  tier: String,
) -> Nil {
  case board.file_read(dream_path) |> result.try(dream.from_json) {
    Ok(d) -> {
      let existing = case board.file_read(proposals_path) {
        Ok(t) -> evolve.from_jsonl(t)
        Error(_) -> []
      }
      let fresh = evolve.from_dream(d, tier)
      let merged = list.append(existing, fresh)
      case board.file_write(proposals_path, evolve.to_jsonl(merged)) {
        Ok(_) ->
          io.println(
            int.to_string(list.length(fresh))
            <> " proposal(s) written to "
            <> proposals_path,
          )
        Error(e) -> io.println("write error: " <> e)
      }
    }
    Error(e) -> io.println("dream error: " <> e)
  }
}

fn evolve_record(
  proposals_path: String,
  id: String,
  verdict: String,
  evidence_ref: String,
) -> Nil {
  case board.file_read(proposals_path) {
    Ok(text) -> {
      let pass = string.lowercase(string.trim(verdict)) == "pass"
      let updated =
        text
        |> evolve.from_jsonl
        |> list.map(fn(p) {
          case p.id == id {
            True -> evolve.record(p, pass, evidence_ref)
            False -> p
          }
        })
      case board.file_write(proposals_path, evolve.to_jsonl(updated)) {
        Ok(_) -> io.println("recorded " <> verdict <> " for " <> id)
        Error(e) -> io.println("write error: " <> e)
      }
    }
    Error(e) -> io.println("proposals file error: " <> e)
  }
}

fn evolve_select(proposals_path: String, k: Int, seed: Int) -> Nil {
  case board.file_read(proposals_path) {
    Ok(text) ->
      io.println(
        json.to_string(
          evolve.to_json(evolve.select(evolve.from_jsonl(text), seed, k)),
        ),
      )
    Error(e) -> io.println("proposals file error: " <> e)
  }
}

fn evolve_report(proposals_path: String) -> Nil {
  case board.file_read(proposals_path) {
    Ok(text) -> io.println(evolve.to_markdown(evolve.from_jsonl(text)))
    Error(e) -> io.println("proposals file error: " <> e)
  }
}

fn vritti_cmd(key: String, value: String) -> Nil {
  io.println(
    agent_runtime.vritti_label(agent_runtime.classify_slot(key, value)),
  )
}

fn faculty_cmd(step: String) -> Nil {
  io.println(agent_runtime.antahkarana_label(agent_runtime.faculty_of(step)))
}
