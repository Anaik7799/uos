//// Package entry. `gleam run -- <command>`:
////   stpa | fmea                 safety models as markdown
////   tps-demo                    TPS board markdown for the swarm ledger
////   swarm <ledger.json>         swarm KPI markdown
////   swarm-tui <ledger.json>     swarm dashboard frame as text (Gleam TUI dashboard)
////   dashboard <ledger.json> <board.jsonl> <usage.json> <out.html>   HTML KPI dashboard
////   board post <jsonl> <zenoh_base|-> <from> <layer> <to> <kind> <k=v,...> <aspects,..> <concepts|..>
////   board post-acl <jsonl> <zenoh_base|-> <acl_file> <model>
////   board ack <jsonl> <zenoh_base|-> <from> <layer> <id>
////   board timeline <jsonl> | board validate <jsonl> | board ingest <journal.jsonl> <jsonl> <zenoh_base|->
////   board reconcile <jsonl> <zenoh_base> | board share <zenoh_base> <ledger.json> <usage.json>
////   board proof <jsonl> <zenoh_base|-> <recipient> | board retry <jsonl> <zenoh_base|->
////   board replay <jsonl> <zenoh_base|-> | board inbox <jsonl> <agent>
////   board forgery-probe <jsonl> <zenoh_base|->
////   acl grammar | acl parse <file>
////   holon | holon-json | lexicon
////   hive <ledger.json> <board.jsonl> <zenoh_base|->
////   controls <zenoh_base|->
////   lifecycle-machine
////   audit-system <ledger.json> <board.jsonl> <zenoh_base|->
////   manager-dictionary
////   manager-run <ledger.json> <board.jsonl> <zenoh_base|-> <cycles>
////   ontology dictionary | ontology glossary | ontology wiki | ontology json
////   ontology check <ledger.jsonl> | ontology resolve <name>
////   holon-km <stamp> <repo_root>   write one wiki page per holon + the holarchy ZK MOC
////   decision-record prepare <out_dir> <slug> <spec.json>
////   decision-record complete <record.json> <completion.json>
////   (anything else)             prints this usage

import argv
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile
import uos_swarm/acl
import uos_swarm/agent_runtime
import uos_swarm/board.{Agent, Causality, Draft, Semantics}
import uos_swarm/board_reader
import uos_swarm/cockpit
import uos_swarm/coord
import uos_swarm/decision_record_cli
import uos_swarm/fmea
import uos_swarm/gita
import uos_swarm/holon
import uos_swarm/holon_km
import uos_swarm/manager
import uos_swarm/ooda
import uos_swarm/raga
import uos_swarm/stpa
import uos_swarm/sutra
import uos_swarm/swarm
import uos_swarm/system_audit
import uos_swarm/system_ontology
import uos_swarm/tps
import uos_tui/aspects
import uos_tui/fprime
import uos_tui/frame
import uos_tui/geometry.{Size}
import uos_tui/html
import uos_tui/live
import uos_tui/ontology
import uos_tui/render

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

const supervisor = Agent("L0-fable", "L0", "fable")

const usage = "Package entry. `gleam run -- <command>`:
  stpa | fmea                 safety models as markdown
  tps-demo                    TPS board markdown for the swarm ledger
  swarm <ledger.json>         swarm KPI markdown
  swarm-tui <ledger.json>     swarm dashboard frame as text (Gleam TUI dashboard)
  dashboard <ledger.json> <board.jsonl> <usage.json> <out.html>   HTML KPI dashboard
  board post <jsonl> <zenoh_base|-> <from> <layer> <to> <kind> <k=v,...> <aspects,..> <concepts|..>
  board post-acl <jsonl> <zenoh_base|-> <acl_file> <model>
  board ack <jsonl> <zenoh_base|-> <from> <layer> <id>
  board timeline <jsonl> | board validate <jsonl> | board ingest <journal.jsonl> <jsonl> <zenoh_base|->
  board reconcile <jsonl> <zenoh_base> | board share <zenoh_base> <ledger.json> <usage.json>
  board proof <jsonl> <zenoh_base|-> <recipient> | board retry <jsonl> <zenoh_base|->
  board replay <jsonl> <zenoh_base|-> | board inbox <jsonl> <agent>
  board forgery-probe <jsonl> <zenoh_base|->
  acl grammar | acl parse <file>
  holon | holon-json | lexicon
  hive <ledger.json> <board.jsonl> <zenoh_base|->
  controls <zenoh_base|->
  lifecycle-machine
  audit-system <ledger.json> <board.jsonl> <zenoh_base|->
  manager-dictionary
  manager-run <ledger.json> <board.jsonl> <zenoh_base|-> <cycles>
  ontology dictionary | ontology glossary | ontology wiki | ontology json
  ontology check <ledger.jsonl> | ontology resolve <name>
  holon-km <stamp> <repo_root>   write one wiki page per holon + the holarchy ZK MOC
  decision-record prepare <out_dir> <slug> <spec.json>
  decision-record complete <record.json> <completion.json>"

pub fn main() -> Nil {
  case argv.load().arguments {
    ["stpa"] -> io.println(stpa.to_markdown(stpa.model()))
    ["fmea"] -> io.println(fmea.to_markdown(fmea.model()))
    ["swarm", path] ->
      with_ledger(path, fn(l) { io.println(swarm.to_markdown(l)) })
    ["tps-demo", path] ->
      with_ledger(path, fn(l) { io.println(tps.to_markdown(tps_board(l))) })
    ["swarm-tui", path] ->
      with_ledger(path, fn(l) {
        render.compose(swarm.view(l, 0), Size(120, 40), None, render.dark)
        |> frame.to_text
        |> io.println
      })
    ["dashboard", ledger_path, board_path, usage_path, out] ->
      dashboard(ledger_path, board_path, usage_path, out)
    ["board", "timeline", path] ->
      io.println(board.to_markdown(load_board_messages(path)))
    ["board", "validate", path] ->
      case validate_board_file(path) {
        Ok(summary) -> io.println(summary)
        Error(error) -> {
          io.println("board INVALID: " <> error)
          halt(1)
        }
      }
    ["board", "ingest", journal, path, base] -> ingest(journal, path, base)
    ["board", "ingest", journal, path, base, ledger_path] ->
      with_ledger(ledger_path, fn(l) {
        ingest_with_labels(journal, path, base, ingest_labels_from_ledger(l))
      })
    ["board", "reconcile", path, base] -> reconcile(path, base)
    ["board", "share", base, ledger_path, usage_path] ->
      share(base, ledger_path, usage_path)
    ["board", "post", path, base, from, layer, to, kind, kv, asp, concepts] ->
      post(path, base, from, layer, to, kind, kv, asp, concepts)
    ["acl", "grammar"] -> io.println(acl.grammar)
    ["acl", "parse", file] ->
      case board.file_read(file) |> result.try(acl.parse) {
        Ok(u) -> {
          io.println(json.to_string(acl.to_json(u)))
          case acl.validate(u) {
            Ok(_) -> io.println("acl valid")
            Error(e) -> io.println("acl INVALID: " <> e)
          }
        }
        Error(e) -> io.println("acl error: " <> e)
      }
    ["board", "post-acl", path, base, file, model] ->
      case
        board.file_read(file) |> result.try(acl.parse),
        open_board(path, base)
      {
        Ok(u), Ok(b) ->
          case acl.validate(u) {
            Ok(_) -> {
              let #(policy, agents) = policy_and_roster()
              let draft0 = acl.to_draft(u, model)
              let draft =
                Draft(..draft0, from: rostered_agent(agents, draft0.from))
              case coord.authorize(policy, draft) {
                Error(v) -> io.println("refused: " <> coord.violation_label(v))
                Ok(_) -> {
                  let #(_, m) = board.post(b, draft)
                  io.println(board.to_string(m))
                }
              }
            }
            Error(e) -> io.println("rejected: " <> e)
          }
        Error(e), _ -> io.println("acl error: " <> e)
        _, Error(e) -> io.println("board: " <> e)
      }
    ["board", "ack", path, base, from, layer, id] ->
      case open_board(path, base) {
        Ok(b) -> {
          let #(policy, roster) = policy_and_roster()
          let agent = rostered_agent(roster, Agent(from, layer, "cli"))
          let draft = board.ack_draft(agent, id)
          let local = load_board_messages(path)
          let probe = board.seal(draft, "probe", 0, 0, "0000000000000000", "")
          case
            coord.authorize(policy, draft)
            |> result.try(fn(_) { coord.ack_target_ok(policy, probe, local) })
          {
            Ok(_) -> {
              let #(_, m) = board.post(b, draft)
              io.println(board.to_string(m))
            }
            Error(v) -> io.println("refused: " <> coord.violation_label(v))
          }
        }
        Error(e) -> io.println("board open: " <> e)
      }
    ["board", "proof", path, base, recipient] ->
      case open_board(path, base) {
        Ok(b) ->
          case coord.prove_delivery(b, Agent(recipient, "L2", "sonnet")) {
            Ok(p) ->
              io.println(
                "proof: sent "
                <> p.sent
                <> " | seen_in_inbox "
                <> bool_text(p.seen_in_inbox)
                <> " | acked "
                <> bool_text(p.acked)
                <> " | sender_saw_ack "
                <> bool_text(p.sender_saw_ack)
                <> " | state "
                <> p.state,
              )
            Error(e) -> io.println("proof error: " <> e)
          }
        Error(e) -> io.println("board: " <> e)
      }
    ["board", "retry", path, base] ->
      case open_board(path, base) {
        Ok(b) -> {
          let #(_, retried, dead) = board.retry_undelivered(b)
          io.println(
            "retry: "
            <> int.to_string(retried)
            <> " retried, "
            <> int.to_string(dead)
            <> " dead-lettered",
          )
        }
        Error(e) -> io.println("board: " <> e)
      }
    ["board", "replay", path, base] ->
      case open_board(path, base) |> result.try(board.replay) {
        Ok(#(ok, failed)) ->
          io.println(
            "replay: "
            <> int.to_string(ok)
            <> " published, "
            <> int.to_string(failed)
            <> " failed",
          )
        Error(e) -> io.println("replay error: " <> e)
      }
    ["board", "inbox", path, agent] -> {
      let ms = load_board_messages(path)
      let inbox = board.inbox(ms, agent)
      io.println(
        "inbox "
        <> agent
        <> ": "
        <> int.to_string(list.length(inbox))
        <> " unacknowledged",
      )
      list.each(inbox, fn(m) {
        io.println(
          "  "
          <> m.ts_iso
          <> " "
          <> board.kind_label(m.kind)
          <> " from "
          <> m.from.id
          <> " ["
          <> board.state_label(board.delivery_state(ms, m))
          <> "]",
        )
      })
    }
    ["sutra"] -> io.println(sutra.to_markdown())
    ["sutra", "json"] -> io.println(json.to_string(sutra.to_json()))
    ["gita"] -> io.println(gita.to_markdown())
    ["gita", "json"] -> io.println(json.to_string(gita.to_json()))
    ["holon", "rules"] -> io.println(holon.base_rules_markdown())
    ["raga"] -> io.println(raga.to_markdown())
    ["raga", "json"] -> io.println(json.to_string(raga.to_json()))
    ["holon"] -> io.println(holon.to_markdown(holon.holarchy()))
    ["holon-json"] ->
      io.println(json.to_string(holon.to_json(holon.holarchy())))
    ["lexicon"] -> io.println(acl.lexicon_markdown())
    ["hive", ledger_path, board_path, zenoh_base] ->
      hive(ledger_path, board_path, zenoh_base)
    ["controls", zenoh_base] -> {
      let ok = case opt_base(zenoh_base) {
        Some(b) ->
          system_audit.probe(b, "http://127.0.0.1:4100").zenoh_router_ok
        None -> False
      }
      let cs = agent_runtime.controls("../..", ok)
      io.println(agent_runtime.controls_markdown(cs))
      io.println("controls_ok=" <> bool_text(agent_runtime.controls_ok(cs)))
    }
    ["lifecycle-machine"] ->
      io.println(json.to_string(agent_runtime.machine_json()))
    ["board", "forgery-probe", path, base] ->
      case open_board(path, base) {
        Ok(b) -> {
          let c =
            coord.new(coord.default_policy(
              [supervisor, coord.system_agent, manager.agent],
              11,
            ))
          case coord.forgery_probe(b, c) {
            Ok(#(refused, r)) ->
              io.println(
                "forgery probe: refused="
                <> bool_text(refused)
                <> " | policy_rejected "
                <> int.to_string(r.policy_rejected)
                <> " | signature_rejected "
                <> int.to_string(r.signature_rejected)
                <> " | conflicts "
                <> int.to_string(r.conflicts)
                <> " | chain_rejected "
                <> int.to_string(r.chain_rejected)
                <> " | pulled "
                <> int.to_string(r.pulled),
              )
            Error(e) -> io.println("forgery probe error: " <> e)
          }
        }
        Error(e) -> io.println("board: " <> e)
      }
    ["audit-system", ledger_path, board_path, zenoh_base] ->
      audit_system(ledger_path, board_path, zenoh_base)
    ["manager-dictionary"] ->
      io.println(
        json.to_string(fprime.dictionary_json(
          manager.component(),
          manager.instance(),
        )),
      )
    ["manager-run", ledger_path, board_path, zenoh_base, cycles] ->
      manager_run(ledger_path, board_path, zenoh_base, cycles)
    ["ontology", "dictionary"] ->
      io.println(system_ontology.dictionary_markdown())
    ["ontology", "glossary"] -> io.println(system_ontology.glossary_markdown())
    ["ontology", "wiki"] -> io.println(system_ontology.wiki_markdown())
    ["ontology", "json"] ->
      io.println(json.to_string(system_ontology.to_json()))
    ["ontology", "check", path] -> ontology_check(path)
    ["ontology", "resolve", name] -> ontology_resolve(name)
    ["holon-km", stamp, repo_root] -> holon_km_write(stamp, repo_root)
    ["decision-record", "prepare", out_dir, slug, spec_path] ->
      case decision_record_cli.write_prepared(out_dir, slug, spec_path) {
        Ok(path) -> io.println(path)
        Error(e) -> {
          io.println(e)
          halt(1)
        }
      }
    ["decision-record", "complete", record_path, completion_path] ->
      case decision_record_cli.complete_record(record_path, completion_path) {
        Ok(id) -> io.println("completed " <> id)
        Error(e) -> {
          io.println(e)
          halt(1)
        }
      }
    _ -> io.println(usage)
  }
}

/// Load every message on a ledger and check `semantics.ontology_concepts` against the
/// unified system ontology registry: `aligned N/M` always, plus the bare word `aligned` when
/// every reference resolves, otherwise one `unresolved: <name>` line per unknown concept.
fn ontology_check(path: String) -> Nil {
  let ms = load_board_messages(path)
  let names = list.flat_map(ms, fn(m) { m.semantics.ontology_concepts })
  let total = list.length(names)
  let #(ok, unresolved) = system_ontology.alignment_report(names)
  io.println("aligned " <> int.to_string(ok) <> "/" <> int.to_string(total))
  case unresolved {
    [] -> io.println("aligned")
    xs -> list.each(xs, fn(n) { io.println("unresolved: " <> n) })
  }
}

fn ontology_resolve(name: String) -> Nil {
  case system_ontology.resolve(name) {
    Ok(c) ->
      io.println(
        c.id
        <> " · "
        <> c.devanagari
        <> " · "
        <> c.iast
        <> " · "
        <> c.english
        <> " · "
        <> system_ontology.domain_label(c.domain)
        <> " · L"
        <> int.to_string(c.layer)
        <> " · "
        <> c.definition,
      )
    Error(_) -> io.println("unresolved: " <> name)
  }
}

/// `holon-km <stamp> <repo_root>`: writes every page of `holon_km.pages(stamp)` under
/// `repo_root`, creating `docs/wiki/holons/` and `docs/zk/` first if either is missing, then
/// prints the count of pages successfully written (halts non-zero if any write failed).
fn holon_km_write(stamp: String, repo_root: String) -> Nil {
  let _ = simplifile.create_directory_all(repo_root <> "/docs/wiki/holons")
  let _ = simplifile.create_directory_all(repo_root <> "/docs/zk")
  let pages = holon_km.pages(stamp)
  let results =
    list.map(pages, fn(pair) {
      let #(rel_path, contents) = pair
      simplifile.write(to: repo_root <> "/" <> rel_path, contents: contents)
    })
  let written =
    list.length(
      list.filter(results, fn(r) {
        case r {
          Ok(_) -> True
          Error(_) -> False
        }
      }),
    )
  let failed = list.length(pages) - written
  io.println("wrote " <> int.to_string(written) <> " holon-km pages")
  case failed {
    0 -> Nil
    _ -> {
      io.println(int.to_string(failed) <> " holon-km page write(s) failed")
      halt(1)
    }
  }
}

fn with_ledger(path: String, k: fn(swarm.Ledger) -> Nil) -> Nil {
  case board.file_read(path) |> result.try(swarm.decode) {
    Ok(l) -> k(l)
    Error(e) -> io.println("ledger error: " <> e)
  }
}

fn opt_base(base: String) -> option.Option(String) {
  case base {
    "-" | "" -> None
    b -> Some(b)
  }
}

fn open_board(path: String, base: String) -> Result(board.Board, String) {
  board.open("uos-tui-swarm", "uos_tui_board", Some(path), opt_base(base))
}

/// Strict, bounded validation for the CLI. Exact duplicate ledger updates retain
/// legacy latest-record semantics; the same id with a different digest is refused.
pub fn validate_board_file(path: String) -> Result(String, String) {
  use text <- result.try(board_reader.read_file(path, board_reader.max_bytes))
  use input <- result.try(board_reader.from_jsonl(text))
  use _ <- result.try(case input.malformed_count {
    0 -> Ok(Nil)
    count -> Error(int.to_string(count) <> " malformed row(s)")
  })
  use _ <- result.try(reject_conflicting_digests(input.events, dict.new()))
  let messages = board.from_jsonl(text).0
  case messages {
    [] -> Ok("board EMPTY: 0 messages; no hive health inferred")
    _ -> {
      use _ <- result.try(board.validate(messages))
      Ok(
        "board valid: "
        <> int.to_string(list.length(messages))
        <> " messages, chain intact, semantics resolved, causal gaps "
        <> int.to_string(list.length(board.causal_gaps(messages)))
        <> ", chain forks "
        <> int.to_string(list.length(board.chain_forks(messages)))
        <> " (explicit records; lost history is not restored)",
      )
    }
  }
}

fn reject_conflicting_digests(
  messages: List(board.Message),
  seen: dict.Dict(String, String),
) -> Result(Nil, String) {
  case messages {
    [] -> Ok(Nil)
    [message, ..rest] ->
      case dict.get(seen, message.id) {
        Ok(digest) if digest != message.digest ->
          Error("conflicting duplicate digests for " <> message.id)
        Ok(_) -> reject_conflicting_digests(rest, seen)
        Error(_) ->
          reject_conflicting_digests(
            rest,
            dict.insert(seen, message.id, message.digest),
          )
      }
  }
}

fn load_board_messages(path: String) -> List(board.Message) {
  case board.file_read(path) {
    Ok(text) -> board.from_jsonl(text).0
    Error(_) -> []
  }
}

fn roster(l: swarm.Ledger) -> List(board.Agent) {
  [
    supervisor,
    coord.system_agent,
    ..list.map(l.agents, fn(a) { Agent(a.id, a.layer, a.model) })
  ]
}

/// The swarm ledger the live pipeline regenerates; CLI posts and journal ingestion authorize
/// against the roster and WIP limit it declares, so the policy the CLI enforces on itself is
/// the same one the swarm actually runs under.
const default_swarm_ledger = "swarm/20260907-0440-swarm-ledger.json"

/// Build the authorization policy (and its roster) from the swarm ledger. Falls back to a
/// minimal `[supervisor, coord.system_agent]` roster with the default WIP limit when the
/// ledger file is missing or unreadable, so a CLI post never bypasses authorization just
/// because the ledger path is not (yet) present.
fn policy_and_roster() -> #(coord.Policy, List(board.Agent)) {
  case board.file_read(default_swarm_ledger) |> result.try(swarm.decode) {
    Ok(l) -> #(coord.default_policy(roster(l), l.wip_limit), roster(l))
    Error(_) -> {
      let r = [supervisor, coord.system_agent]
      #(coord.default_policy(r, 11), r)
    }
  }
}

/// Replace a draft's `from` with the rostered agent sharing its id, so the model/layer
/// recorded and authorized is the roster's (e.g. "fable" for L0-fable), never a CLI-supplied
/// placeholder like "cli". Falls back to the given agent unchanged when its id is not on the
/// roster, so `coord.authorize` still fails closed with `UnknownAgent` rather than silently
/// admitting an unrostered sender.
fn rostered_agent(
  roster: List(board.Agent),
  agent: board.Agent,
) -> board.Agent {
  roster
  |> list.find(fn(a) { a.id == agent.id })
  |> result.unwrap(agent)
}

fn tps_board(l: swarm.Ledger) -> tps.Board {
  list.fold(l.agents, tps.new(l.wip_limit, l.takt_minutes), fn(b, a) {
    let column = case a.status {
      swarm.Planned -> tps.Planned
      swarm.Running -> tps.Running
      swarm.Passed -> tps.Verifying
      swarm.Integrated -> tps.Done
      swarm.Failed -> tps.Failed
    }
    tps.add(
      b,
      tps.Card(a.id, a.slice, a.model, column, [], case a.started, a.finished {
        "", _ -> None
        _, "" -> None
        _, _ -> Some(0)
      }),
    )
  })
}

fn post(path, base, from, layer, to, kind, kv, asp, concepts) -> Nil {
  let payload =
    kv
    |> string.split(",")
    |> list.filter_map(fn(p) {
      case string.split_once(p, "=") {
        Ok(#(k, v)) -> Ok(#(k, v))
        Error(_) -> Error(Nil)
      }
    })
  let aspects_ = asp |> string.split(",") |> list.filter_map(int.parse)
  let concepts_ = case concepts {
    "" | "-" -> []
    c -> string.split(c, "|")
  }
  case board.kind_from_label(kind), open_board(path, base) {
    Ok(k), Ok(b) -> {
      let #(policy, agents) = policy_and_roster()
      let draft =
        Draft(
          rostered_agent(agents, Agent(from, layer, "cli")),
          to,
          k,
          payload,
          Semantics(concepts_, aspects_, [], [], layer_int(layer)),
          Causality(None, []),
          None,
          None,
        )
      case board.validate_semantics(draft.semantics) {
        Error(e) -> io.println("rejected: " <> e)
        Ok(_) ->
          case coord.authorize(policy, draft) {
            Error(v) -> io.println("refused: " <> coord.violation_label(v))
            Ok(_) -> {
              let #(_, m) = board.post(b, draft)
              io.println(board.to_string(m))
            }
          }
      }
    }
    Error(e), _ -> io.println(e)
    _, Error(e) -> io.println("board open: " <> e)
  }
}

fn layer_int(layer: String) -> Int {
  layer |> string.drop_start(1) |> int.parse |> result.unwrap(3)
}

fn ingest(journal: String, path: String, base: String) -> Nil {
  ingest_with_labels(journal, path, base, [])
}

fn ingest_labels_from_ledger(l: swarm.Ledger) -> List(#(String, String)) {
  list.flat_map(l.agents, fn(a) {
    case a.role {
      "worker" -> [#(a.slice, a.id)]
      _ -> {
        let first =
          a.slice
          |> string.replace("verify ", "")
          |> string.split("+")
          |> list.first
          |> result.unwrap("")
        [#("verify:" <> first, a.id)]
      }
    }
  })
}

fn ingest_with_labels(
  journal: String,
  path: String,
  base: String,
  labels: List(#(String, String)),
) -> Nil {
  case board.file_read(journal), open_board(path, base) {
    Ok(text), Ok(b) -> {
      let #(policy, agents) = policy_and_roster()
      let drafts =
        board.drafts_from_journal_labelled(
          board.parse_journal(text),
          supervisor,
          labels,
        )
        |> list.map(fn(d) { Draft(..d, from: rostered_agent(agents, d.from)) })
      let #(b, n, authorized, refused) =
        list.fold(drafts, #(b, 0, 0, 0), fn(acc, d) {
          let #(b, n, authorized, refused) = acc
          case coord.authorize(policy, d) {
            Error(v) -> {
              io.println(
                "refused: "
                <> coord.violation_label(v)
                <> " ("
                <> board.kind_label(d.kind)
                <> " "
                <> d.from.id
                <> " -> "
                <> d.to
                <> ")",
              )
              #(b, n, authorized, refused + 1)
            }
            Ok(_) -> {
              let #(b, m) = board.post(b, d)
              let z =
                list.any(m.deliveries, fn(dl) {
                  string.starts_with(dl.transport, "zenoh")
                  && dl.status == board.Delivered
                })
              #(
                b,
                n
                  + case z {
                  True -> 1
                  False -> 0
                },
                authorized + 1,
                refused,
              )
            }
          }
        })
      io.println(
        "ingested "
        <> int.to_string(list.length(drafts))
        <> " journal entries; zenoh delivered "
        <> int.to_string(n)
        <> "; board count "
        <> int.to_string(b.count)
        <> "; authorized "
        <> int.to_string(authorized)
        <> " | refused "
        <> int.to_string(refused),
      )
    }
    Error(e), _ -> io.println("journal: " <> e)
    _, Error(e) -> io.println("board: " <> e)
  }
}

fn reconcile(path: String, base: String) -> Nil {
  case open_board(path, base) {
    Ok(b) -> {
      // The policy must carry the real roster (ledger agents + reviewers), otherwise
      // every peer message is refused as an unknown agent and the refusal was invisible.
      let #(policy, _) = policy_and_roster()
      let c = coord.new(policy)
      case coord.reconcile(b, c) {
        Ok(#(_, _, r)) ->
          io.println(
            "reconcile: pulled "
            <> int.to_string(r.pulled)
            <> ", pushed "
            <> int.to_string(r.pushed)
            <> ", digest_rejected "
            <> int.to_string(r.digest_rejected)
            <> ", remote "
            <> int.to_string(r.remote_total)
            <> ", local "
            <> int.to_string(r.local_total)
            <> " | policy_rejected "
            <> int.to_string(r.policy_rejected)
            <> " | signature_rejected "
            <> int.to_string(r.signature_rejected)
            <> " | conflicts "
            <> int.to_string(r.conflicts)
            <> " | chain_rejected "
            <> int.to_string(r.chain_rejected)
            <> " | push_rejected "
            <> int.to_string(r.push_rejected),
          )
        Error(e) -> io.println("reconcile error: " <> e)
      }
    }
    Error(e) -> io.println("board: " <> e)
  }
}

fn usage_from_file(path: String) -> List(coord.Usage) {
  let row = {
    use agent <- decode.field("label", decode.string)
    use model <- decode.field("model", decode.string)
    use inp <- decode.field("input_tokens", decode.int)
    use out <- decode.field("output_tokens", decode.int)
    use cr <- decode.field("cache_read", decode.int)
    use cw <- decode.field("cache_write", decode.int)
    use tools <- decode.field("tool_uses", decode.int)
    decode.success(coord.Usage(agent, model, inp, out, cr, cw, tools, 0))
  }
  case board.file_read(path) {
    Ok(text) ->
      json.parse(from: text, using: decode.list(row)) |> result.unwrap([])
    Error(_) -> []
  }
}

fn state_entries(
  l: swarm.Ledger,
  usages: List(coord.Usage),
) -> List(#(String, json.Json)) {
  let m0 = cockpit.init_model(live.utc_now(), l.base_change)
  // The CLI is never started under a supervisor, so `supervised` is honestly `False`.
  let ctx =
    cockpit.context(m0, Size(120, 40), False, [
      "gleam_stdlib",
      "gleam_erlang",
      "gleam_otp",
      "gleam_json",
      "argv",
    ])
  let m =
    cockpit.Model(
      ..m0,
      checklist_passed: cockpit.evidence_checklist_passed(m0, ctx),
    )
  let findings = aspects.audit(cockpit.view(m), ctx)
  let c =
    list.fold(
      usages,
      coord.new(coord.default_policy(roster(l), l.wip_limit)),
      coord.record_usage,
    )
  let k = swarm.kpis(l)
  [
    #(
      "aspects",
      json.array(findings, fn(f) {
        json.object([
          #("n", json.int(aspects.number(f.aspect))),
          #("name", json.string(aspects.name(f.aspect))),
          #("verdict", json.string(aspects.verdict_label(f.verdict))),
          #("evidence", json.string(f.evidence)),
        ])
      }),
    ),
    #(
      "kpis",
      json.object([
        #("completion_pct", json.int(k.completion_pct)),
        #("pass_rate_pct", json.int(k.pass_rate_pct)),
        #("first_pass_yield_pct", json.int(k.first_pass_yield_pct)),
        #("wip", json.int(k.wip)),
        #("tests_added", json.int(k.tests_added)),
        #("loc", json.int(k.loc)),
        #("jidoka_stops", json.int(k.jidoka_stops)),
        #("andon", json.string(swarm.andon_label(k.andon))),
      ]),
    ),
    // Feature-sheet generation is uos_tui library territory (see contract note in the
    // uos_swarm split plan); this package never calls `uos_tui/features` directly.
    #("features", json.string("feature sheet lives in the uos_tui library")),
    #(
      "fprime_dictionary",
      fprime.dictionary_json(fprime.component(), fprime.instance()),
    ),
    #("stpa", json.string(stpa.to_markdown(stpa.model()))),
    #("fmea", json.string(fmea.to_markdown(fmea.model()))),
    #("ontology", json.string(ontology.to_markdown(ontology.graph()))),
    #("usage", coord.usage_json(c)),
    #("ledger", json.string(swarm.to_markdown(l))),
  ]
}

fn share(base: String, ledger_path: String, usage_path: String) -> Nil {
  with_ledger(ledger_path, fn(l) {
    let #(n, errs) =
      coord.share_state(base, state_entries(l, usage_from_file(usage_path)))
    io.println(
      "shared "
      <> int.to_string(n)
      <> " state entries on "
      <> coord.state_url(base, "*")
      <> case errs {
        [] -> ""
        es -> " ; errors: " <> string.join(es, "; ")
      },
    )
  })
}

fn dashboard(
  ledger_path: String,
  board_path: String,
  usage_path: String,
  out: String,
) -> Nil {
  with_ledger(ledger_path, fn(l) {
    let k = swarm.kpis(l)
    let msgs = load_board_messages(board_path)
    let usages = usage_from_file(usage_path)
    let c =
      list.fold(
        usages,
        coord.new(coord.default_policy(roster(l), l.wip_limit)),
        coord.record_usage,
      )
    let g = coord.global_usage(c)
    let m0 = cockpit.init_model(live.utc_now(), l.base_change)
    // The CLI is never started under a supervisor, so `supervised` is honestly `False`.
    let ctx =
      cockpit.context(m0, Size(120, 40), False, [
        "gleam_stdlib",
        "gleam_erlang",
        "gleam_otp",
        "gleam_json",
        "argv",
      ])
    let m =
      cockpit.Model(
        ..m0,
        checklist_passed: cockpit.evidence_checklist_passed(m0, ctx),
      )
    let findings = aspects.audit(cockpit.view(m), ctx)
    let tone = fn(ok: Bool) {
      case ok {
        True -> html.Good
        False -> html.Bad
      }
    }
    let pct = fn(n: Int) { Some(int.to_float(n) /. 100.0) }
    let zenoh_delivered =
      list.count(msgs, fn(m) {
        list.any(m.deliveries, fn(d) {
          string.starts_with(d.transport, "zenoh")
          && d.status == board.Delivered
        })
      })
    let page =
      html.page(
        "uos_tui Swarm Dashboard",
        "15 agents · L0 Fable · jj base "
          <> l.base_change
          <> " · "
          <> l.timestamp,
        aspects.tailnet_fqdn,
        [
          html.Section("Swarm KPIs", [
            html.KpiRow([
              html.Kpi(
                "Completion",
                int.to_string(k.completion_pct) <> "%",
                pct(k.completion_pct),
                tone(k.completion_pct == 100),
              ),
              html.Kpi(
                "Pass rate",
                int.to_string(k.pass_rate_pct) <> "%",
                pct(k.pass_rate_pct),
                tone(k.pass_rate_pct == 100),
              ),
              html.Kpi(
                "First-pass yield",
                int.to_string(k.first_pass_yield_pct) <> "%",
                pct(k.first_pass_yield_pct),
                tone(k.first_pass_yield_pct == 100),
              ),
              html.Kpi(
                "Andon",
                swarm.andon_label(k.andon),
                None,
                tone(k.andon == swarm.Green),
              ),
              html.Kpi(
                "Jidoka stops",
                int.to_string(k.jidoka_stops),
                None,
                tone(k.jidoka_stops == 0),
              ),
              html.Kpi(
                "Tests added",
                int.to_string(k.tests_added),
                None,
                html.Neutral,
              ),
              html.Kpi("LOC added", int.to_string(k.loc), None, html.Neutral),
              html.Kpi(
                "WIP",
                int.to_string(k.wip) <> "/" <> int.to_string(l.wip_limit),
                None,
                html.Neutral,
              ),
            ]),
            html.Progress(
              "Slices integrated",
              int.to_float(k.completion_pct) /. 100.0,
            ),
          ]),
          html.Section("Resource utilization (per agent and global)", [
            html.KpiRow([
              html.Kpi(
                "Agents",
                int.to_string(dict.size(c.usage)),
                None,
                html.Neutral,
              ),
              html.Kpi(
                "Output tokens",
                int.to_string(g.output_tokens),
                None,
                html.Neutral,
              ),
              html.Kpi(
                "Input tokens",
                int.to_string(g.input_tokens),
                None,
                html.Neutral,
              ),
              html.Kpi(
                "Cache-read tokens",
                int.to_string(g.cache_read),
                None,
                html.Neutral,
              ),
              html.Kpi(
                "Tool uses",
                int.to_string(g.tool_uses),
                None,
                html.Neutral,
              ),
              html.Kpi(
                "Relative cost units",
                float_str(
                  list.fold(usages, 0.0, fn(acc, u) {
                    acc +. coord.weighted_cost(u, coord.default_weights)
                  }),
                ),
                None,
                html.Neutral,
              ),
            ]),
            html.TableNode(html.Table(
              [
                "agent",
                "model",
                "input",
                "output",
                "cache read",
                "tools",
                "wall",
                "rel. cost",
              ],
              coord.usage_rows(c),
            )),
            html.Text(
              "Relative cost units use the documented per-model weights in uos_tui/coord (sonnet input = 1.0); they are not currency.",
            ),
          ]),
          html.Section("Agents (ledger)", [
            html.TableNode(html.Table(
              [
                "id",
                "layer",
                "model",
                "slice",
                "status",
                "tests",
                "loc",
                "verdict",
              ],
              list.map(l.agents, fn(a) {
                [
                  a.id,
                  a.layer,
                  a.model,
                  a.slice,
                  swarm.status_label(a.status),
                  int.to_string(a.tests_added),
                  int.to_string(a.loc),
                  a.verdict,
                ]
              }),
            )),
          ]),
          html.Section("17-aspect audit of the cockpit screen", [
            html.KpiRow([
              html.Kpi(
                "Pass",
                int.to_string(aspects.passed(findings)),
                None,
                html.Good,
              ),
              html.Kpi(
                "Declared",
                int.to_string(aspects.declared(findings)),
                None,
                html.Warn,
              ),
              html.Kpi(
                "Fail",
                int.to_string(aspects.failed(findings)),
                None,
                tone(aspects.failed(findings) == 0),
              ),
            ]),
            html.TableNode(html.Table(
              ["#", "aspect", "verdict", "evidence"],
              list.map(findings, fn(f) {
                [
                  int.to_string(aspects.number(f.aspect)),
                  aspects.name(f.aspect),
                  aspects.verdict_label(f.verdict),
                  f.evidence,
                ]
              }),
            )),
          ]),
          html.Section("Message board (Zenoh c3i/a2a plane · ETS · JSONL)", [
            html.KpiRow([
              html.Kpi(
                "Tracked messages",
                int.to_string(list.length(msgs)),
                None,
                html.Neutral,
              ),
              html.Kpi(
                "Delivered to Zenoh",
                int.to_string(zenoh_delivered),
                Some(case list.length(msgs) {
                  0 -> 0.0
                  n -> int.to_float(zenoh_delivered) /. int.to_float(n)
                }),
                tone(zenoh_delivered == list.length(msgs) && msgs != []),
              ),
              html.Kpi(
                "Chain valid",
                case board.validate(msgs) {
                  Ok(_) -> "yes"
                  Error(_) -> "NO"
                },
                None,
                tone(board.validate(msgs) == Ok(Nil)),
              ),
            ]),
            html.TableNode(html.Table(
              [
                "ts",
                "lamport",
                "from",
                "kind",
                "to",
                "aspects",
                "control actions",
                "delivery",
              ],
              list.map(msgs, fn(m) {
                [
                  m.ts_iso,
                  int.to_string(m.lamport),
                  m.from.id,
                  board.kind_label(m.kind),
                  m.to,
                  string.join(list.map(m.semantics.aspects, int.to_string), ","),
                  string.join(m.semantics.control_actions, ","),
                  string.join(
                    list.filter_map(m.deliveries, fn(d) {
                      case d.status {
                        board.Delivered -> Ok(d.transport)
                        _ -> Error(Nil)
                      }
                    }),
                    " ",
                  ),
                ]
              }),
            )),
            html.Link(
              "Zenoh REST: c3i/a2a/**",
              "http://nas-1.tail55d152.ts.net:8080/c3i/a2a/**",
            ),
          ]),
          html.Section("Links", [
            html.Link(
              "Plan",
              aspects.tailnet_fqdn
                <> "/docs/docs/plans/20260907-0440-uos-tui-swarm-15-agent-multilayer-plan.md",
            ),
            html.Link(
              "Shared state on Zenoh: uos/tui/state/**",
              "http://nas-1.tail55d152.ts.net:8080/uos/tui/state/**",
            ),
          ]),
        ],
      )
    case write_file(out, page) {
      Ok(_) -> io.println("dashboard written: " <> out)
      Error(e) -> io.println("dashboard write failed: " <> e)
    }
  })
}

/// `lease_epoch` must be observed, not declared: pass the highest live lease epoch from a
/// real `coord.Coord` when this command holds one, else `0` (no live lease epoch observed).
/// `supervised` is always `False` here: the CLI process is never started under a supervisor.
fn system_ctx(l: swarm.Ledger, lease_epoch: Int) -> aspects.Context {
  let m =
    cockpit.Model(
      ..cockpit.init_model(live.utc_now(), l.base_change),
      lease_epoch: lease_epoch,
    )
  cockpit.context(m, Size(120, 40), False, [
    "gleam_stdlib",
    "gleam_erlang",
    "gleam_otp",
    "gleam_json",
    "argv",
  ])
}

/// The highest live lease epoch held by `c` at `now_us`, or `0` when nothing is live.
fn live_lease_epoch(c: coord.Coord, now_us: Int) -> Int {
  coord.live_leases(c, now_us)
  |> list.fold(0, fn(acc, lease) { int.max(acc, lease.epoch) })
}

fn audit_system(
  ledger_path: String,
  board_path: String,
  zenoh_base: String,
) -> Nil {
  with_ledger(ledger_path, fn(l) {
    let probe = case opt_base(zenoh_base) {
      Some(b) -> system_audit.probe(b, "http://127.0.0.1:4100")
      None -> system_audit.unprobed
    }
    let subjects =
      system_audit.all_subjects(
        system_ctx(l, 0),
        l,
        load_board_messages(board_path),
        probe,
      )
    io.println(system_audit.to_markdown(subjects))
  })
}

fn manager_run(
  ledger_path: String,
  board_path: String,
  zenoh_base: String,
  cycles: String,
) -> Nil {
  with_ledger(ledger_path, fn(l) {
    case open_board(board_path, zenoh_base) {
      Error(e) -> io.println("board: " <> e)
      Ok(b) -> {
        let c =
          coord.new(coord.default_policy(
            [
              supervisor,
              coord.system_agent,
              manager.agent,
              ..list.map(l.agents, fn(a) { Agent(a.id, a.layer, a.model) })
            ],
            l.wip_limit,
          ))
        let audit = fn() {
          let probe = case opt_base(zenoh_base) {
            Some(zb) -> system_audit.probe(zb, "http://127.0.0.1:4100")
            None -> system_audit.unprobed
          }
          system_audit.all_subjects(
            system_ctx(l, live_lease_epoch(c, board.system_time_us())),
            l,
            load_board_messages(board_path),
            probe,
          )
        }
        let c =
          list.fold(l.agents, c, fn(c, a) {
            case a.status {
              swarm.Integrated | swarm.Passed | swarm.Failed ->
                coord.retire(c, a.id)
              _ -> c
            }
          })
        let c =
          list.fold(board.timeline(b), c, fn(c, m) {
            coord.beat(c, m.from.id, m.ts_us)
          })
        let n = int.parse(cycles) |> result.unwrap(1)
        let #(m, _, _, log) =
          list.fold(prng_range(1, n), #(manager.new(), b, c, []), fn(acc, _) {
            let #(m, b, c, log) = acc
            let #(m, b, c, acts) =
              manager.live_cycle(m, b, c, opt_base(zenoh_base), audit)
            #(m, b, c, [acts, ..log])
          })
        io.println(
          "manager ran "
          <> int.to_string(m.cycles)
          <> " cycles; last mode "
          <> ooda_label(m.last_mode)
          <> "; acts per cycle: "
          <> string.join(
            list.map(list.reverse(log), fn(a) { int.to_string(list.length(a)) }),
            ",",
          ),
        )
      }
    }
  })
}

fn prng_range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..prng_range(from + 1, to)]
  }
}

fn ooda_label(m: ooda.Mode) -> String {
  ooda.mode_label(m)
}

/// Hive mind snapshot: one shared-cognition document every agent can GET (holarchy, board,
/// leases, KPIs, audit totals, lexicon) published on uos/tui/state/hive.
fn hive(ledger_path: String, board_path: String, zenoh_base: String) -> Nil {
  with_ledger(ledger_path, fn(l) {
    let msgs = load_board_messages(board_path)
    let k = swarm.kpis(l)
    let probe = case opt_base(zenoh_base) {
      Some(b) -> system_audit.probe(b, "http://127.0.0.1:4100")
      None -> system_audit.unprobed
    }
    let subjects = system_audit.all_subjects(system_ctx(l, 0), l, msgs, probe)
    let #(p, d, f) = system_audit.totals(subjects)
    let kinds =
      board.kinds
      |> list.map(fn(kd) {
        #(board.kind_label(kd), json.int(list.length(board.by_kind(msgs, kd))))
      })
    let acl_count =
      list.count(msgs, fn(m) { list.any(m.payload, fn(pp) { pp.0 == "acl" }) })
    let doc =
      json.object([
        #("hive", json.string("uos-tui-swarm · samūha-buddhi (समूह-बुद्धि)")),
        #("generated_at", json.string(live.utc_now())),
        #("holarchy", holon.to_json(holon.holarchy())),
        #(
          "board",
          json.object([
            #("messages", json.int(list.length(msgs))),
            #("with_acl_utterance", json.int(acl_count)),
            #("chain_valid", json.bool(board.validate(msgs) == Ok(Nil))),
            #("kinds", json.object(kinds)),
            #(
              "senders",
              json.array(
                msgs |> list.map(fn(m) { m.from.id }) |> list.unique,
                json.string,
              ),
            ),
          ]),
        ),
        #(
          "kpis",
          json.object([
            #("completion_pct", json.int(k.completion_pct)),
            #("first_pass_yield_pct", json.int(k.first_pass_yield_pct)),
            #("tests_added", json.int(k.tests_added)),
            #("loc", json.int(k.loc)),
            #("andon", json.string(swarm.andon_label(k.andon))),
          ]),
        ),
        #(
          "audit",
          json.object([
            #("subjects", json.int(list.length(subjects))),
            #("pass", json.int(p)),
            #("declared", json.int(d)),
            #("fail", json.int(f)),
            #("no_failures", json.bool(f == 0)),
            #("admissible", json.bool(f == 0 && d == 0)),
          ]),
        ),
        #(
          "language",
          json.object([
            #("lexemes", json.int(list.length(acl.lexicon))),
            #("performatives", json.int(list.length(acl.performatives))),
          ]),
        ),
        #(
          "zenoh",
          json.object([
            #("router_ok", json.bool(probe.zenoh_router_ok)),
            #("storages", json.int(probe.zenoh_storages)),
            #("a2a_messages", json.int(probe.zenoh_a2a_messages)),
            #("cockpit_connected", json.bool(probe.cockpit_zenoh_connected)),
          ]),
        ),
      ])
    io.println(json.to_string(doc))
    case opt_base(zenoh_base) {
      Some(b) ->
        case board.zenoh_put(b, "uos/tui/state/hive", json.to_string(doc)) {
          Ok(_) -> io.println("hive shared on " <> coord.state_url(b, "hive"))
          Error(e) -> io.println("hive share failed: " <> e)
        }
      None -> Nil
    }
  })
}

fn bool_text(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

fn float_str(f: Float) -> String {
  int.to_string(float_round(f))
}

@external(erlang, "erlang", "round")
fn float_round(f: Float) -> Int

@external(erlang, "uos_swarm_ffi", "file_write")
fn write_file(path: String, content: String) -> Result(Nil, String)
