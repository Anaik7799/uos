//// CLI for the Jujutsu client library: `gleam run -m uos_jj_cli -- <root> <command> [args...]`.
////
////   log [revset] [limit]                        default revset "all()", limit 20
////   workspaces                                   list workspaces (name/path/change_id/stale)
////   ops [limit]                                   operation log, default limit 20
////   bookmarks                                     list local bookmarks
////   show <rev>                                    one change's metadata
////   stat <from> <to>                               diff summary between two revisions
////   discipline                                     the 8 encoded VCS rules (D1..D8)
////   guard-main-move <rev> [lease.json] [decision.json]
////                                                   dry-run: prints what move_main would
////                                                   refuse or accept, without moving anything
////   integrate-chain <base> <change>...             performs the rebases (a real WRITE)
////
//// Every command prints one JSON object or array to stdout.

import argv
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import uos_swarm/jj

@external(erlang, "uos_swarm_ffi", "file_read")
fn file_read(path: String) -> Result(String, String)

pub fn main() -> Nil {
  case argv.load().arguments {
    [root, "log"] -> log_cmd(root, "all()", 20)
    [root, "log", revset] -> log_cmd(root, revset, 20)
    [root, "log", revset, limit] ->
      log_cmd(root, revset, int.parse(limit) |> result.unwrap(20))
    [root, "workspaces"] -> workspaces_cmd(root)
    [root, "ops"] -> ops_cmd(root, 20)
    [root, "ops", limit] -> ops_cmd(root, int.parse(limit) |> result.unwrap(20))
    [root, "bookmarks"] -> bookmarks_cmd(root)
    [root, "show", rev] -> show_cmd(root, rev)
    [root, "stat", from, to] -> stat_cmd(root, from, to)
    [_root, "discipline"] -> discipline_cmd()
    [root, "guard-main-move", rev] -> guard_main_move_cmd(root, rev, None, None)
    [root, "guard-main-move", rev, lease_path] ->
      guard_main_move_cmd(root, rev, Some(lease_path), None)
    [root, "guard-main-move", rev, lease_path, decision_path] ->
      guard_main_move_cmd(root, rev, Some(lease_path), Some(decision_path))
    [root, "integrate-chain", base, ..changes] ->
      integrate_chain_cmd(root, base, changes)
    _ -> io.println(usage)
  }
}

const usage = "usage: gleam run -m uos_jj_cli -- <root> <command> [args...]
  log [revset] [limit]
  workspaces
  ops [limit]
  bookmarks
  show <rev>
  stat <from> <to>
  discipline
  guard-main-move <rev> [lease.json] [decision.json]
  integrate-chain <base> <change>..."

fn open_or_die(root: String) -> jj.Repo {
  case jj.open(root) {
    Ok(repo) -> repo
    Error(e) -> {
      print_error(e)
      panic as "jj executable not found on PATH"
    }
  }
}

fn print_error(e: jj.Error) -> Nil {
  io.println(
    json.to_string(
      json.object([
        #("ok", json.bool(False)),
        #("error", json.string(error_message(e))),
      ]),
    ),
  )
}

fn error_message(e: jj.Error) -> String {
  case e {
    jj.NotAJjRepo(msg) -> "not_a_jj_repo: " <> msg
    jj.CommandFailed(exit: code, output: out) ->
      "command_failed(" <> int.to_string(code) <> "): " <> out
    jj.Timeout(msg) -> "timeout: " <> msg
    jj.Parse(msg) -> "parse_error: " <> msg
    jj.GuardRefused(msg) -> "guard_refused: " <> msg
    jj.NativeGitBarred -> "native_git_barred"
  }
}

fn print_ok(value: Json) -> Nil {
  io.println(json.to_string(value))
}

fn change_json(c: jj.Change) -> Json {
  json.object([
    #("change_id", json.string(c.change_id)),
    #("commit_id", json.string(c.commit_id)),
    #("parents", json.array(c.parents, json.string)),
    #("bookmarks", json.array(c.bookmarks, json.string)),
    #("description", json.string(c.description)),
    #("conflict", json.bool(c.conflict)),
    #("empty", json.bool(c.empty)),
    #("author_ts", json.string(c.author_ts)),
  ])
}

fn workspace_json(w: jj.Workspace) -> Json {
  json.object([
    #("name", json.string(w.name)),
    #("path", json.string(w.path)),
    #("change_id", json.string(w.change_id)),
    #("stale", json.bool(w.stale)),
  ])
}

fn operation_json(o: jj.Operation) -> Json {
  json.object([
    #("id", json.string(o.id)),
    #("description", json.string(o.description)),
    #("time", json.string(o.time)),
  ])
}

fn bookmark_json(b: jj.Bookmark) -> Json {
  json.object([
    #("name", json.string(b.name)),
    #("change_id", json.string(b.change_id)),
    #("commit_id", json.string(b.commit_id)),
  ])
}

fn diff_stat_json(d: jj.DiffStatEntry) -> Json {
  json.object([
    #("status", json.string(d.status)),
    #("path", json.string(d.path)),
  ])
}

fn log_cmd(root: String, revset: String, limit: Int) -> Nil {
  let repo = open_or_die(root)
  case jj.log(repo, jj.expr(revset), limit) {
    Ok(changes) -> print_ok(json.array(changes, change_json))
    Error(e) -> print_error(e)
  }
}

fn workspaces_cmd(root: String) -> Nil {
  let repo = open_or_die(root)
  case jj.workspaces(repo) {
    Ok(ws) -> print_ok(json.array(ws, workspace_json))
    Error(e) -> print_error(e)
  }
}

fn ops_cmd(root: String, limit: Int) -> Nil {
  let repo = open_or_die(root)
  case jj.operations(repo, limit) {
    Ok(ops) -> print_ok(json.array(ops, operation_json))
    Error(e) -> print_error(e)
  }
}

fn bookmarks_cmd(root: String) -> Nil {
  let repo = open_or_die(root)
  case jj.bookmarks(repo) {
    Ok(bs) -> print_ok(json.array(bs, bookmark_json))
    Error(e) -> print_error(e)
  }
}

fn show_cmd(root: String, rev: String) -> Nil {
  let repo = open_or_die(root)
  case jj.show(repo, jj.expr(rev)) {
    Ok(c) -> print_ok(change_json(c))
    Error(e) -> print_error(e)
  }
}

fn stat_cmd(root: String, from: String, to: String) -> Nil {
  let repo = open_or_die(root)
  case jj.diff_stat(repo, jj.expr(from), jj.expr(to)) {
    Ok(entries) -> print_ok(json.array(entries, diff_stat_json))
    Error(e) -> print_error(e)
  }
}

fn discipline_cmd() -> Nil {
  let rules =
    jj.discipline()
    |> list.map(fn(rule) {
      let #(id, text) = rule
      json.object([#("id", json.string(id)), #("text", json.string(text))])
    })
  print_ok(json.preprocessed_array(rules))
}

fn lease_decoder_from_json(text: String) -> Result(jj.LeaseProof, String) {
  case json.parse(text, lease_decode()) {
    Ok(l) -> Ok(l)
    Error(_) -> Error("could not parse lease JSON")
  }
}

fn decision_decoder_from_json(text: String) -> Result(jj.DecisionRef, String) {
  case json.parse(text, decision_decode()) {
    Ok(d) -> Ok(d)
    Error(_) -> Error("could not parse decision JSON")
  }
}

fn lease_decode() -> decode.Decoder(jj.LeaseProof) {
  use resource <- decode.field("resource", decode.string)
  use holder <- decode.field("holder", decode.string)
  use epoch <- decode.field("epoch", decode.int)
  use operation_id <- decode.field("operation_id", decode.string)
  decode.success(jj.LeaseProof(resource, holder, epoch, operation_id))
}

fn decision_decode() -> decode.Decoder(jj.DecisionRef) {
  use path <- decode.field("path", decode.string)
  use decision_id <- decode.field("decision_id", decode.string)
  decode.success(jj.DecisionRef(path, decision_id))
}

fn guard_main_move_cmd(
  root: String,
  rev: String,
  lease_path: Option(String),
  decision_path: Option(String),
) -> Nil {
  let repo = open_or_die(root)
  let lease =
    option.then(lease_path, fn(p) {
      case file_read(p) {
        Ok(text) ->
          case lease_decoder_from_json(text) {
            Ok(l) -> Some(l)
            Error(_) -> None
          }
        Error(_) -> None
      }
    })
  let decision =
    option.then(decision_path, fn(p) {
      case file_read(p) {
        Ok(text) ->
          case decision_decoder_from_json(text) {
            Ok(d) -> Some(d)
            Error(_) -> None
          }
        Error(_) -> None
      }
    })
  // Dry run: only a READ (`jj.show`, which itself carries
  // --ignore-working-copy) ever touches the repo here; the guard
  // predicate is evaluated purely, and move_main's own write path
  // (describe + bookmark_set) is never invoked.
  let exists = case jj.show(repo, jj.expr(rev)) {
    Ok(_) -> True
    Error(_) -> False
  }
  let decision_field = case decision {
    Some(d) ->
      json.object([
        #("path", json.string(d.path)),
        #("decision_id", json.string(d.decision_id)),
      ])
    None -> json.null()
  }
  case lease, decision {
    Some(l), Some(_) ->
      print_ok(
        json.object([
          #("rev_exists", json.bool(exists)),
          #("lease_resource", json.string(l.resource)),
          #("lease_epoch", json.int(l.epoch)),
          #("decision", decision_field),
          #("would", case jj.lease_authorizes_main(l) {
            True -> json.string("accept")
            False -> json.string("refuse")
          }),
          #(
            "reason",
            json.string(case jj.lease_authorizes_main(l) {
              True ->
                "lease authorizes integration/main and a decision record is present"
              False ->
                "lease does not authorize integration/main: resource must be \"integration/main\", epoch must be > 0, and operation_id must be non-empty"
            }),
          ),
        ]),
      )
    None, _ ->
      print_ok(
        json.object([
          #("rev_exists", json.bool(exists)),
          #("would", json.string("refuse")),
          #("reason", json.string("no lease proof presented")),
        ]),
      )
    _, None ->
      print_ok(
        json.object([
          #("rev_exists", json.bool(exists)),
          #("would", json.string("refuse")),
          #("reason", json.string("no decision record presented")),
        ]),
      )
  }
}

fn integrate_chain_cmd(
  root: String,
  base: String,
  changes: List(String),
) -> Nil {
  let repo = open_or_die(root)
  case jj.integrate_chain(repo, changes, base) {
    Ok(cs) -> print_ok(json.array(cs, change_json))
    Error(e) -> print_error(e)
  }
}
