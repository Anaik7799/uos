//// A typed, pure-Gleam client over the real `jj` (Jujutsu 0.44) binary,
//// reached through a pure-Erlang port (`uos_jj_ffi`) that never builds a
//// shell string — every argument is one element of an `{args, _}` list
//// handed straight to `erlang:open_port/2`, so there is no injection
//// surface regardless of what a caller puts in a message, path, or revset.
////
//// This module encodes this repository's VCS discipline as guards, not as
//// documentation: see `discipline/0` for the eight rules (D1..D8) and the
//// functions that enforce each one. In particular:
//// - READ functions (`log`, `show`, `workspaces`, `operations`,
////   `bookmarks`, `diff_stat`, `file_list`, `file_show`, `is_conflicted`)
////   always pass `--ignore-working-copy` (via `guard_read`), so a reader
////   never snapshots a workspace's checkout as a side effect.
//// - WRITE functions intentionally omit `--ignore-working-copy`: they are
////   the operations that are supposed to touch the working copy.
//// - `move_main` refuses to move the `main`-style bookmark of record
////   unless both a `LeaseProof` and a `DecisionRef` are presented; it does
////   not and cannot verify the coordinator's bookkeeping itself, only that
////   the caller presented a well-formed authorization and that the move is
////   recorded in the target commit's description as an audit trail.
//// - `integrate_chain` rebases a linear chain of changes in order and
////   aborts at the first conflict it observes, reporting how far it got.
//// - No function anywhere in this module has "git" in its name, and
//// `Repo.exe` is checked against a `git` executable path defensively on
//// every call (`NativeGitBarred`), even though `open/1` only ever
//// resolves `jj`.
////
//// Single-revision parameters are the opaque `Revset` builder (`rev`,
//// `main`, `at`, `parents`, `ancestors`, `descendants`, `union`,
//// `intersect`, `bookmarks_revset`, `heads_all`) so that composed
//// expressions (`ancestors(at(), 5)`, `union(main(), at())`, ...) are
//// constructed the same way for both reads and writes. `new/3` and
//// `integrate_chain/3` take raw change-id `String`s instead, matching how
//// callers naturally have a list of change ids on hand after a `log`.
////
//// Naming note: the jj revset language has a zero-argument function
//// `bookmarks()` (all local bookmark targets) and this module also has a
//// `bookmarks(repo)` READ operation (list of `Bookmark` records) — Gleam
//// has no overloading by arity, so the revset builder is exposed as
//// `bookmarks_revset()` to keep both names live in one module.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// -- FFI -----------------------------------------------------------------

@external(erlang, "uos_jj_ffi", "which")
fn ffi_which(name: String) -> Result(String, Nil)

@external(erlang, "uos_jj_ffi", "run")
fn ffi_run(
  exe: String,
  args: List(String),
  cwd: String,
  timeout_ms: Int,
) -> Result(#(Int, String), String)

// -- Types -----------------------------------------------------------------

pub type Repo {
  Repo(root: String, exe: String, timeout_ms: Int)
}

pub type Change {
  Change(
    change_id: String,
    commit_id: String,
    parents: List(String),
    bookmarks: List(String),
    description: String,
    conflict: Bool,
    empty: Bool,
    author_ts: String,
  )
}

pub type Workspace {
  Workspace(name: String, path: String, change_id: String, stale: Bool)
}

pub type Operation {
  Operation(id: String, description: String, time: String)
}

pub type Bookmark {
  Bookmark(name: String, change_id: String, commit_id: String)
}

pub type DiffStatEntry {
  DiffStatEntry(status: String, path: String)
}

pub type Error {
  NotAJjRepo(String)
  CommandFailed(exit: Int, output: String)
  Timeout(String)
  Parse(String)
  GuardRefused(String)
  NativeGitBarred
}

pub type LeaseProof {
  LeaseProof(resource: String, holder: String, epoch: Int, operation_id: String)
}

pub type DecisionRef {
  DecisionRef(path: String, decision_id: String)
}

/// Opaque revset builder. Values are always well-formed jj revset
/// expression text; construct them with `rev`, `main`, `at`, `parents`,
/// `ancestors`, `descendants`, `union`, `intersect`, `bookmarks_revset`,
/// and `heads_all`, and read them back with `to_string`.
pub opaque type Revset {
  Revset(String)
}

// -- Open --------------------------------------------------------------

/// Resolve the `jj` executable on `$PATH` and bind it to `root` with a
/// default 20 second timeout. Does not itself validate that `root` is a
/// jj repository; the first command run against the `Repo` will surface
/// that as `CommandFailed`.
pub fn open(root: String) -> Result(Repo, Error) {
  case ffi_which("jj") {
    Ok(exe) -> Ok(Repo(root: root, exe: exe, timeout_ms: 20_000))
    Error(_) ->
      Error(CommandFailed(exit: -1, output: "jj executable not found on PATH"))
  }
}

// -- Revset builder ------------------------------------------------------

fn quote_symbol(s: String) -> String {
  "\"" <> string.replace(s, "\"", "\\\"") <> "\""
}

/// A single revision referenced by change id, commit id, or bookmark name.
/// Quoted so the text can never be reinterpreted as revset syntax.
pub fn rev(id: String) -> Revset {
  Revset(quote_symbol(id))
}

/// The bookmark literally named `main`, quoted the same way as `rev`.
pub fn main() -> Revset {
  Revset(quote_symbol("main"))
}

/// The working-copy commit of the current workspace (`@`).
pub fn at() -> Revset {
  Revset("@")
}

/// A raw, unquoted revset expression, taken as-is (e.g. `"all()"`,
/// `"main() | at()"`, a bare change id typed by an operator). Unlike
/// `rev`, this is not quoted, so the text is parsed with full revset
/// grammar rather than resolved only as a literal symbol; callers that
/// build expressions out of untyped strings (such as the CLI, where a
/// human supplies the revset on the command line) use this constructor
/// instead of composing one field at a time.
pub fn expr(text: String) -> Revset {
  Revset(text)
}

pub fn parents(r: Revset) -> Revset {
  Revset("parents(" <> to_string(r) <> ")")
}

pub fn ancestors(r: Revset, n: Int) -> Revset {
  Revset("ancestors(" <> to_string(r) <> ", " <> int.to_string(n) <> ")")
}

pub fn descendants(r: Revset) -> Revset {
  Revset("descendants(" <> to_string(r) <> ")")
}

pub fn union(a: Revset, b: Revset) -> Revset {
  Revset("(" <> to_string(a) <> ") | (" <> to_string(b) <> ")")
}

pub fn intersect(a: Revset, b: Revset) -> Revset {
  Revset("(" <> to_string(a) <> ") & (" <> to_string(b) <> ")")
}

/// All local bookmark targets (the jj revset function `bookmarks()`). See
/// the module doc for why this isn't named `bookmarks`.
pub fn bookmarks_revset() -> Revset {
  Revset("bookmarks()")
}

/// All visible heads (`heads(all())`).
pub fn heads_all() -> Revset {
  Revset("heads(all())")
}

pub fn to_string(r: Revset) -> String {
  let Revset(s) = r
  s
}

// -- Templates -------------------------------------------------------------
//
// Fields are separated by the ASCII unit separator (0x1F) and records by
// the ASCII record separator (0x1E), embedded directly as raw bytes inside
// jj's own double-quoted template string literals (verified against 0.44:
// `jj` accepts a raw control byte inside a quoted template string without
// needing the textual `\xHH` escape). Neither byte occurs in ordinary
// commit text, so splitting on them is unambiguous.

const unit_sep = "\u{001F}"

const record_sep = "\u{001E}"

const log_template = "change_id.short(12) ++ \"\u{001F}\" ++ commit_id.short(12) ++ \"\u{001F}\" ++ parents.map(|p| p.change_id().short(12)).join(\",\") ++ \"\u{001F}\" ++ bookmarks.join(\",\") ++ \"\u{001F}\" ++ description.first_line() ++ \"\u{001F}\" ++ if(conflict, \"1\", \"0\") ++ \"\u{001F}\" ++ if(empty, \"1\", \"0\") ++ \"\u{001F}\" ++ author.timestamp() ++ \"\u{001E}\""

const op_template = "id.short(12) ++ \"\u{001F}\" ++ description ++ \"\u{001F}\" ++ time.start() ++ \"\u{001E}\""

const workspace_template = "name ++ \"\u{001F}\" ++ target.change_id().short(12) ++ \"\u{001F}\" ++ if(root, root.absolute(), \"\") ++ \"\u{001E}\""

const bookmark_template = "name ++ \"\u{001F}\" ++ if(normal_target, normal_target.change_id().short(12), \"\") ++ \"\u{001F}\" ++ if(normal_target, normal_target.commit_id().short(12), \"\") ++ \"\u{001E}\""

const file_list_template = "path ++ \"\u{001E}\""

const description_template = "description ++ \"\u{001E}\""

/// Split raw `jj -T` output into records on the record separator, dropping
/// exactly one trailing separator (the one the template always appends
/// after the last record) rather than filtering blank entries, so a
/// single record whose content happens to be empty is still returned as
/// one `""` element instead of being lost.
fn split_records(output: String) -> List(String) {
  case output {
    "" -> []
    _ ->
      case string.ends_with(output, record_sep) {
        True -> string.split(string.drop_end(output, 1), record_sep)
        False -> string.split(output, record_sep)
      }
  }
}

fn split_csv(s: String) -> List(String) {
  case s {
    "" -> []
    _ -> string.split(s, ",")
  }
}

fn parse_change(record: String) -> Result(Change, Error) {
  case string.split(record, unit_sep) {
    [
      change_id,
      commit_id,
      parents_s,
      bookmarks_s,
      description,
      conflict_s,
      empty_s,
      author_ts,
    ] ->
      Ok(Change(
        change_id: change_id,
        commit_id: commit_id,
        parents: split_csv(parents_s),
        bookmarks: split_csv(bookmarks_s),
        description: description,
        conflict: conflict_s == "1",
        empty: empty_s == "1",
        author_ts: author_ts,
      ))
    _ -> Error(Parse("unexpected change record shape: " <> record))
  }
}

fn parse_workspace(record: String) -> Result(Workspace, Error) {
  case string.split(record, unit_sep) {
    [name, change_id, path] ->
      Ok(Workspace(name: name, path: path, change_id: change_id, stale: False))
    _ -> Error(Parse("unexpected workspace record shape: " <> record))
  }
}

fn parse_operation(record: String) -> Result(Operation, Error) {
  case string.split(record, unit_sep) {
    [id, description, time] ->
      Ok(Operation(id: id, description: description, time: time))
    _ -> Error(Parse("unexpected operation record shape: " <> record))
  }
}

fn parse_bookmark(record: String) -> Result(Bookmark, Error) {
  case string.split(record, unit_sep) {
    [name, change_id, commit_id] ->
      Ok(Bookmark(name: name, change_id: change_id, commit_id: commit_id))
    _ -> Error(Parse("unexpected bookmark record shape: " <> record))
  }
}

fn parse_diff_stat_line(line: String) -> Result(DiffStatEntry, Error) {
  case string.split_once(line, " ") {
    Ok(#(status, path)) ->
      Ok(DiffStatEntry(status: status, path: string.trim(path)))
    Error(_) -> Error(Parse("unexpected diff summary line: " <> line))
  }
}

// -- Execution -------------------------------------------------------------

/// D1: this module never runs `git`. `open/1` only ever resolves `jj` on
/// `$PATH`, but every call re-checks the bound executable defensively so
/// the invariant is enforced in code, not only by construction.
fn barred(repo: Repo) -> Bool {
  repo.exe == "git" || string.ends_with(repo.exe, "/git")
}

fn exec(repo: Repo, args: List(String)) -> Result(String, Error) {
  case barred(repo) {
    True -> Error(NativeGitBarred)
    False ->
      case ffi_run(repo.exe, args, repo.root, repo.timeout_ms) {
        Ok(#(0, output)) -> Ok(output)
        Ok(#(code, output)) -> Error(CommandFailed(exit: code, output: output))
        Error(reason) ->
          case string.contains(reason, "timeout") {
            True -> Error(Timeout(reason))
            False -> Error(CommandFailed(exit: -1, output: reason))
          }
      }
  }
}

/// D2: ensures every read carries `--ignore-working-copy`, so a reader
/// never snapshots a shared checkout as a side effect of inspecting it.
pub fn guard_read(args: List(String)) -> List(String) {
  case list.contains(args, "--ignore-working-copy") {
    True -> args
    False -> ["--ignore-working-copy", ..args]
  }
}

fn read_exec(repo: Repo, args: List(String)) -> Result(String, Error) {
  exec(repo, guard_read(args))
}

// -- READ operations ---------------------------------------------------

pub fn log(
  repo: Repo,
  revset: Revset,
  limit: Int,
) -> Result(List(Change), Error) {
  let args = [
    "log",
    "--no-graph",
    "-T",
    log_template,
    "-r",
    to_string(revset),
    "-n",
    int.to_string(limit),
  ]
  use output <- result.try(read_exec(repo, args))
  output |> split_records |> list.try_map(parse_change)
}

pub fn show(repo: Repo, rev: Revset) -> Result(Change, Error) {
  let args = [
    "log",
    "--no-graph",
    "-T",
    log_template,
    "-r",
    to_string(rev),
    "-n",
    "1",
  ]
  use output <- result.try(read_exec(repo, args))
  case split_records(output) {
    [record] -> parse_change(record)
    [] -> Error(Parse("no such revision: " <> to_string(rev)))
    _ ->
      Error(Parse(
        "revset resolved to more than one revision: " <> to_string(rev),
      ))
  }
}

/// The full (possibly multi-line) description of `rev`, unlike the
/// `description` field on `Change` from `log`/`show`, which is
/// `first_line()`-truncated for compact records. Used to append the
/// `move_main` audit trailer without clobbering the rest of a message,
/// and exposed publicly because "give me the real description" is a
/// generically useful capability the compact log template can't offer.
pub fn description_of(repo: Repo, rev: Revset) -> Result(String, Error) {
  let args = [
    "log",
    "--no-graph",
    "-T",
    description_template,
    "-r",
    to_string(rev),
    "-n",
    "1",
  ]
  use output <- result.try(read_exec(repo, args))
  case split_records(output) {
    [d] -> Ok(d)
    _ -> Error(Parse("no such revision: " <> to_string(rev)))
  }
}

pub fn workspaces(repo: Repo) -> Result(List(Workspace), Error) {
  let args = ["workspace", "list", "-T", workspace_template]
  use output <- result.try(read_exec(repo, args))
  output |> split_records |> list.try_map(parse_workspace)
}

pub fn operations(repo: Repo, limit: Int) -> Result(List(Operation), Error) {
  let args = [
    "op",
    "log",
    "--no-graph",
    "-T",
    op_template,
    "-n",
    int.to_string(limit),
  ]
  use output <- result.try(read_exec(repo, args))
  output |> split_records |> list.try_map(parse_operation)
}

pub fn bookmarks(repo: Repo) -> Result(List(Bookmark), Error) {
  let args = ["bookmark", "list", "-T", bookmark_template]
  use output <- result.try(read_exec(repo, args))
  output |> split_records |> list.try_map(parse_bookmark)
}

pub fn diff_stat(
  repo: Repo,
  from: Revset,
  to: Revset,
) -> Result(List(DiffStatEntry), Error) {
  let args = [
    "diff",
    "--from",
    to_string(from),
    "--to",
    to_string(to),
    "-s",
  ]
  use output <- result.try(read_exec(repo, args))
  output
  |> string.split("\n")
  |> list.filter(fn(line) { line != "" })
  |> list.try_map(parse_diff_stat_line)
}

pub fn file_list(repo: Repo, rev: Revset) -> Result(List(String), Error) {
  let args = ["file", "list", "-r", to_string(rev), "-T", file_list_template]
  use output <- result.try(read_exec(repo, args))
  Ok(split_records(output))
}

pub fn file_show(
  repo: Repo,
  rev: Revset,
  path: String,
) -> Result(String, Error) {
  read_exec(repo, ["file", "show", "-r", to_string(rev), path])
}

pub fn is_conflicted(repo: Repo, rev: Revset) -> Result(Bool, Error) {
  use change <- result.try(show(repo, rev))
  Ok(change.conflict)
}

// -- WRITE operations --------------------------------------------------

pub fn describe(
  repo: Repo,
  rev: Revset,
  message: String,
) -> Result(Nil, Error) {
  use _ <- result.try(
    exec(repo, ["describe", "-r", to_string(rev), "-m", message]),
  )
  Ok(Nil)
}

/// Creates a new change on top of `parents` (raw change ids; empty means
/// "on top of `@`'s current parent(s)", matching plain `jj new`) and
/// returns the resulting working-copy `Change`.
pub fn new(
  repo: Repo,
  parents: List(String),
  message: String,
) -> Result(Change, Error) {
  use _ <- result.try(exec(
    repo,
    list.flatten([["new"], parents, ["-m", message]]),
  ))
  show(repo, at())
}

pub fn rebase_source(
  repo: Repo,
  source: Revset,
  destination: Revset,
) -> Result(Nil, Error) {
  use _ <- result.try(
    exec(repo, ["rebase", "-s", to_string(source), "-o", to_string(destination)]),
  )
  Ok(Nil)
}

pub fn squash_into(
  repo: Repo,
  from: Revset,
  into: Revset,
  use_destination_message: Bool,
) -> Result(Nil, Error) {
  let flag = case use_destination_message {
    True -> ["-u"]
    False -> []
  }
  use _ <- result.try(exec(
    repo,
    list.flatten([
      ["squash", "--from", to_string(from), "--into", to_string(into)],
      flag,
    ]),
  ))
  Ok(Nil)
}

pub fn abandon(repo: Repo, rev: Revset) -> Result(Nil, Error) {
  use _ <- result.try(exec(repo, ["abandon", to_string(rev)]))
  Ok(Nil)
}

fn find_bookmark(repo: Repo, name: String) -> Result(Bookmark, Error) {
  use all <- result.try(bookmarks(repo))
  case list.find(all, fn(b) { b.name == name }) {
    Ok(b) -> Ok(b)
    Error(_) -> Error(Parse("bookmark not found after set: " <> name))
  }
}

pub fn bookmark_set(
  repo: Repo,
  name: String,
  rev: Revset,
  allow_backwards: Bool,
) -> Result(Bookmark, Error) {
  let flag = case allow_backwards {
    True -> ["--allow-backwards"]
    False -> []
  }
  use _ <- result.try(exec(
    repo,
    list.flatten([["bookmark", "set", name, "-r", to_string(rev)], flag]),
  ))
  find_bookmark(repo, name)
}

/// Always passes `--revision` explicitly (D5): this repository learned
/// that `jj workspace add` without it parents on `@`'s parent, which is
/// rarely the intended base for a fresh workspace.
pub fn workspace_add(
  repo: Repo,
  name: String,
  path: String,
  revision: Revset,
) -> Result(Workspace, Error) {
  use _ <- result.try(
    exec(repo, [
      "workspace",
      "add",
      "--name",
      name,
      "-r",
      to_string(revision),
      path,
    ]),
  )
  use all <- result.try(workspaces(repo))
  case list.find(all, fn(w) { w.name == name }) {
    Ok(w) -> Ok(w)
    Error(_) -> Error(Parse("workspace not found after add: " <> name))
  }
}

pub fn workspace_forget(repo: Repo, name: String) -> Result(Nil, Error) {
  use _ <- result.try(exec(repo, ["workspace", "forget", name]))
  Ok(Nil)
}

/// Targets the workspace rooted at `path` via `-R`, independent of
/// `repo.root`, so a caller can reconcile a sibling workspace without
/// first `open`-ing it separately.
pub fn workspace_update_stale(repo: Repo, path: String) -> Result(Nil, Error) {
  use _ <- result.try(exec(repo, ["workspace", "update-stale", "-R", path]))
  Ok(Nil)
}

/// D6: operations are never edited, only restored (`jj op restore`).
pub fn op_restore(repo: Repo, op_id: String) -> Result(Nil, Error) {
  use _ <- result.try(exec(repo, ["op", "restore", op_id]))
  Ok(Nil)
}

/// D6: operations are never edited, only undone (`jj undo`, the top-level
/// alias for reverting the latest operation; jj 0.44 has no `jj op undo`
/// subcommand).
pub fn op_undo(repo: Repo) -> Result(Nil, Error) {
  use _ <- result.try(exec(repo, ["undo"]))
  Ok(Nil)
}

// -- Guards ------------------------------------------------------------

/// D3: refuses to move a bookmark named `main` unless both a `LeaseProof`
/// naming the `integration/main` resource with a positive epoch and a
/// non-empty operation id, and a `DecisionRef`, are presented. This
/// library cannot verify the coordinator's own bookkeeping (that the
/// lease is genuinely held, or that the decision record is admitted); it
/// enforces only that a well-formed proof accompanies the move, and
/// records that proof as a trailer on the target commit's description
/// before moving the bookmark, so the audit trail travels with the
/// history rather than living only in a caller's log line.
/// The pure predicate `move_main` enforces: `True` iff `lease` authorizes
/// the `integration/main` resource (matching resource name, positive
/// epoch, non-empty operation id). Exposed so callers (such as a
/// dry-run CLI) can report what `move_main` would decide without
/// triggering its write side effects.
pub fn lease_authorizes_main(lease: LeaseProof) -> Bool {
  lease.resource == "integration/main"
  && lease.epoch > 0
  && lease.operation_id != ""
}

pub fn move_main(
  repo: Repo,
  rev: Revset,
  lease: Option(LeaseProof),
  decision: Option(DecisionRef),
) -> Result(Bookmark, Error) {
  case lease, decision {
    Some(l), Some(d) ->
      case lease_authorizes_main(l) {
        True -> perform_guarded_move(repo, rev, l, d)
        False ->
          Error(GuardRefused(
            "lease does not authorize integration/main: resource must be \"integration/main\", epoch must be > 0, and operation_id must be non-empty",
          ))
      }
    None, _ ->
      Error(GuardRefused("main bookmark move refused: no lease proof presented"))
    _, None ->
      Error(GuardRefused(
        "main bookmark move refused: no decision record presented",
      ))
  }
}

fn perform_guarded_move(
  repo: Repo,
  rev: Revset,
  lease: LeaseProof,
  decision: DecisionRef,
) -> Result(Bookmark, Error) {
  use current <- result.try(description_of(repo, rev))
  let trailer =
    "\n\nGuard-Lease: "
    <> lease.resource
    <> "@epoch="
    <> int.to_string(lease.epoch)
    <> " holder="
    <> lease.holder
    <> " op="
    <> lease.operation_id
    <> "\nGuard-Decision: "
    <> decision.path
    <> "#"
    <> decision.decision_id
  use _ <- result.try(describe(repo, rev, current <> trailer))
  bookmark_set(repo, "main", rev, True)
}

fn error_to_string(e: Error) -> String {
  case e {
    NotAJjRepo(msg) -> "not_a_jj_repo: " <> msg
    CommandFailed(exit: code, output: out) ->
      "command_failed(" <> int.to_string(code) <> "): " <> out
    Timeout(msg) -> "timeout: " <> msg
    Parse(msg) -> "parse_error: " <> msg
    GuardRefused(msg) -> "guard_refused: " <> msg
    NativeGitBarred -> "native_git_barred"
  }
}

/// D4: rebases each change in `changes` onto the previous one in order
/// (the first onto `base`), aborting at the first change that comes out
/// conflicted and reporting, in the error text, how many of the total
/// changes were integrated before the abort.
pub fn integrate_chain(
  repo: Repo,
  changes: List(String),
  base: String,
) -> Result(List(Change), Error) {
  integrate_loop(repo, changes, list.length(changes), base, [])
}

fn integrate_loop(
  repo: Repo,
  remaining: List(String),
  total: Int,
  destination: String,
  acc: List(Change),
) -> Result(List(Change), Error) {
  case remaining {
    [] -> Ok(list.reverse(acc))
    [change, ..rest] ->
      case rebase_source(repo, rev(change), rev(destination)) {
        Error(e) ->
          Error(CommandFailed(
            exit: -1,
            output: "integrate_chain aborted after "
              <> int.to_string(list.length(acc))
              <> "/"
              <> int.to_string(total)
              <> " changes: rebase of "
              <> change
              <> " onto "
              <> destination
              <> " failed: "
              <> error_to_string(e),
          ))
        Ok(Nil) ->
          case is_conflicted(repo, rev(change)) {
            Ok(True) ->
              Error(CommandFailed(
                exit: -1,
                output: "integrate_chain aborted after "
                  <> int.to_string(list.length(acc))
                  <> "/"
                  <> int.to_string(total)
                  <> " changes: "
                  <> change
                  <> " is conflicted after rebase onto "
                  <> destination,
              ))
            Ok(False) ->
              case show(repo, rev(change)) {
                Ok(c) -> integrate_loop(repo, rest, total, change, [c, ..acc])
                Error(e) -> Error(e)
              }
            Error(e) -> Error(e)
          }
      }
  }
}

/// The discipline this module encodes, as `#(id, text)` pairs, for
/// documentation and for the `discipline` CLI command.
pub fn discipline() -> List(#(String, String)) {
  [
    #(
      "D1",
      "no native git mutation: no function in this module has \"git\" in its name, and every exec call is checked against a git executable path",
    ),
    #(
      "D2",
      "readers never snapshot a shared checkout: every READ function passes --ignore-working-copy via guard_read",
    ),
    #(
      "D3",
      "main moves only with a lease proof and a decision record: move_main refuses with GuardRefused unless both are presented and the lease authorizes integration/main",
    ),
    #(
      "D4",
      "integration is a linear chain rebased in order, abort on conflict: integrate_chain stops at the first conflicted change and reports how far it got",
    ),
    #(
      "D5",
      "workspaces are created with an explicit --revision: workspace_add always passes -r, never bare `jj workspace add`",
    ),
    #(
      "D6",
      "operations are never edited, only restored or undone: op_restore (jj op restore) and op_undo (jj undo) are the only operation-log mutators",
    ),
    #(
      "D7",
      "change ids are identity, commit ids are content: Change keeps both fields distinct and no function coerces one into the other",
    ),
    #(
      "D8",
      "conflicts are first-class values, never silently resolved: is_conflicted and Change.conflict surface them instead of hiding them",
    ),
  ]
}
