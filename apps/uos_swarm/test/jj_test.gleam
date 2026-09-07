//// Tests for `uos_swarm/jj` against real throwaway standalone (non-colocated)
//// jj repositories created under the scratchpad path, never against the
//// shared UOS repository. If the `jj` binary is missing, `require_jj`
//// panics with a clear message rather than letting a test pass vacuously.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import uos_swarm/jj

pub fn main() -> Nil {
  gleeunit.main()
}

// -- Process-level helpers used only to bootstrap/tear down throwaway repos.
// Reuses the same two `uos_jj_ffi` exports the library itself calls through,
// plus this package's existing `uos_swarm_ffi` file helpers (already used by
// other CLIs in this package) — no new FFI surface is introduced for tests.

@external(erlang, "uos_jj_ffi", "which")
fn ffi_which(name: String) -> Result(String, Nil)

@external(erlang, "uos_jj_ffi", "run")
fn ffi_run(
  exe: String,
  args: List(String),
  cwd: String,
  timeout_ms: Int,
) -> Result(#(Int, String), String)

@external(erlang, "uos_swarm_ffi", "file_write")
fn file_write(path: String, content: String) -> Result(Nil, String)

@external(erlang, "uos_swarm_ffi", "file_read")
fn file_read(path: String) -> Result(String, String)

@external(erlang, "filelib", "is_dir")
fn is_dir(path: String) -> Bool

@external(erlang, "filelib", "is_file")
fn is_file(path: String) -> Bool

const scratch_base = "/tmp/claude-1000/-home-an-NAS-setup/656f0d2c-6019-4d9e-b0ce-b9e39b240047/scratchpad/jjlib-tests"

/// Fails the test immediately with a clear message instead of letting it
/// silently pass with nothing exercised, per the ground rule that a missing
/// `jj`/`rm` binary must not produce a vacuous green test.
fn require_binary(name: String) -> String {
  case ffi_which(name) {
    Ok(path) -> path
    Error(_) ->
      panic as {
        name
        <> " binary not found on $PATH; uos_swarm/jj tests require it to be installed"
      }
  }
}

fn rm_rf(dir: String) -> Nil {
  let rm = require_binary("rm")
  let _ = ffi_run(rm, ["-rf", "--", dir], "/tmp", 5000)
  Nil
}

/// Creates a fresh STANDALONE (non-colocated) jj repository at
/// `scratch_base <> "/" <> name` via `jj git init --no-colocate` (the
/// backing store is git-format, but no `.git` directory is exposed at the
/// repo root and `git` itself is never invoked — verified by
/// `standalone_repo_has_no_dot_git_test`), removing any stale directory
/// from a previous interrupted run first.
fn fresh_repo(name: String) -> jj.Repo {
  let jj_exe = require_binary("jj")
  let dir = scratch_base <> "/" <> name
  rm_rf(dir)
  let assert Ok(#(0, _)) =
    ffi_run(jj_exe, ["git", "init", "--no-colocate", dir], "/tmp", 20_000)
  let assert Ok(repo) = jj.open(dir)
  repo
}

fn dir_of(repo: jj.Repo) -> String {
  repo.root
}

// -- Pure-function tests (no jj binary required) ----------------------------

pub fn guard_read_test() {
  jj.guard_read(["log", "-r", "@"])
  |> should.equal(["--ignore-working-copy", "log", "-r", "@"])

  // Idempotent: a read that already carries the flag is left alone, never
  // duplicated.
  jj.guard_read(["--ignore-working-copy", "log"])
  |> should.equal(["--ignore-working-copy", "log"])
}

pub fn discipline_test() {
  let rules = jj.discipline()
  list.length(rules) |> should.equal(8)
  list.map(rules, fn(rule) {
    let #(id, _text) = rule
    id
  })
  |> should.equal(["D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8"])
  // Every rule has non-empty prose, not just an id.
  list.each(rules, fn(rule) {
    let #(_id, text) = rule
    { text != "" } |> should.be_true
  })
}

pub fn revset_builder_test() {
  jj.to_string(jj.at()) |> should.equal("@")
  jj.to_string(jj.expr("all()")) |> should.equal("all()")
  jj.to_string(jj.rev("abc123")) |> should.equal("\"abc123\"")
  jj.to_string(jj.main()) |> should.equal("\"main\"")
  jj.to_string(jj.parents(jj.at())) |> should.equal("parents(@)")
  jj.to_string(jj.ancestors(jj.at(), 5)) |> should.equal("ancestors(@, 5)")
  jj.to_string(jj.descendants(jj.at())) |> should.equal("descendants(@)")
  jj.to_string(jj.union(jj.main(), jj.at()))
  |> should.equal("(\"main\") | (@)")
  jj.to_string(jj.intersect(jj.main(), jj.at()))
  |> should.equal("(\"main\") & (@)")
  jj.to_string(jj.bookmarks_revset()) |> should.equal("bookmarks()")
  jj.to_string(jj.heads_all()) |> should.equal("heads(all())")
}

/// D1, enforced at runtime: any call against a `Repo` whose `exe` resolves
/// to a `git` binary is refused with `NativeGitBarred` before any process
/// is spawned — even though `open/1` only ever resolves `jj`. Does not
/// require the `jj` binary to be installed, since the barred path never
/// reaches the port at all.
pub fn native_git_barred_test() {
  let fake = jj.Repo(root: "/tmp", exe: "git", timeout_ms: 1000)
  jj.log(fake, jj.at(), 1) |> should.equal(Error(jj.NativeGitBarred))

  let fake_path = jj.Repo(root: "/tmp", exe: "/usr/bin/git", timeout_ms: 1000)
  jj.workspaces(fake_path) |> should.equal(Error(jj.NativeGitBarred))
}

/// D1: no function in `uos_swarm/jj` has "git" anywhere in its name.
/// Reads the module's own source (relative to the package root, which is
/// `gleam test`'s working directory) rather than trusting a claim about it.
pub fn no_function_name_contains_git_test() {
  let assert Ok(source) = file_read("src/uos_swarm/jj.gleam")
  let names = function_names(source)

  // Sanity-check the extraction itself found real functions, so this test
  // cannot vacuously pass by silently matching nothing.
  list.contains(names, "move_main") |> should.be_true
  list.contains(names, "integrate_chain") |> should.be_true
  list.contains(names, "guard_read") |> should.be_true
  { list.length(names) > 20 } |> should.be_true

  list.each(names, fn(name) { string.contains(name, "git") |> should.be_false })
}

fn function_names(source: String) -> List(String) {
  source
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    let trimmed = string.trim(line)
    case string.starts_with(trimmed, "pub fn ") {
      True -> extract_name(string.drop_start(trimmed, 7))
      False ->
        case string.starts_with(trimmed, "fn ") {
          True -> extract_name(string.drop_start(trimmed, 3))
          False -> Error(Nil)
        }
    }
  })
}

fn extract_name(rest: String) -> Result(String, Nil) {
  case string.split_once(rest, "(") {
    Ok(#(name, _)) -> Ok(string.trim(name))
    Error(_) -> Error(Nil)
  }
}

// -- Repo lifecycle: init, describe, new, bookmark, workspace, reads -------

pub fn standalone_repo_has_no_dot_git_test() {
  let repo = fresh_repo("standalone-check")
  let dir = dir_of(repo)
  is_dir(dir <> "/.jj") |> should.be_true
  { is_dir(dir <> "/.git") || is_file(dir <> "/.git") } |> should.be_false
  rm_rf(dir)
}

pub fn jj_lifecycle_test() {
  let repo = fresh_repo("lifecycle")
  let dir = dir_of(repo)

  // 1. Write a file and describe @: describe is a WRITE (no
  // --ignore-working-copy) so it snapshots the pending file first.
  let assert Ok(Nil) = file_write(dir <> "/a.txt", "hello\n")
  let assert Ok(Nil) = jj.describe(repo, jj.at(), "base")

  let assert Ok(base) = jj.show(repo, jj.at())
  base.description |> should.equal("base")
  base.empty |> should.be_false
  base.conflict |> should.be_false

  // 2. new/3 creates a child and returns its Change directly.
  let assert Ok(second) = jj.new(repo, [base.change_id], "second")
  second.parents |> should.equal([base.change_id])
  second.empty |> should.be_true
  second.description |> should.equal("second")

  // 3. bookmark_set (a plain WRITE, no guard) creates/moves "main" freely.
  let assert Ok(bm) = jj.bookmark_set(repo, "main", jj.at(), False)
  bm.name |> should.equal("main")
  bm.change_id |> should.equal(second.change_id)

  let assert Ok(bms) = jj.bookmarks(repo)
  list.any(bms, fn(b) { b.name == "main" }) |> should.be_true

  // 4. workspace_add always passes --revision explicitly (D5).
  let ws_path = scratch_base <> "/lifecycle-ws2"
  rm_rf(ws_path)
  // `-r`/`--revision` sets the *parent* of the new workspace's fresh
  // working-copy commit, not the commit itself (confirmed against jj
  // 0.44's own `workspace add` output before writing this assertion) —
  // this is exactly the behavior D5 exists to guarantee is always
  // requested explicitly rather than left to jj's own default (which
  // parents on `@`'s parent, not `@`).
  let assert Ok(ws) = jj.workspace_add(repo, "ws2", ws_path, jj.at())
  ws.name |> should.equal("ws2")
  { ws.change_id != "" } |> should.be_true
  let assert Ok(ws_commit) = jj.show(repo, jj.rev(ws.change_id))
  ws_commit.parents |> should.equal([second.change_id])

  let assert Ok(all_ws) = jj.workspaces(repo)
  list.any(all_ws, fn(w) { w.name == "default" }) |> should.be_true
  list.any(all_ws, fn(w) { w.name == "ws2" }) |> should.be_true

  // 5. log/operations/file_list/file_show/diff_stat are all READs.
  let assert Ok(changes) = jj.log(repo, jj.expr("all()"), 50)
  list.any(changes, fn(c) { c.change_id == base.change_id }) |> should.be_true
  list.any(changes, fn(c) { c.change_id == second.change_id })
  |> should.be_true

  let assert Ok(ops) = jj.operations(repo, 50)
  { ops != [] } |> should.be_true

  let assert Ok(files) = jj.file_list(repo, jj.rev(base.change_id))
  list.contains(files, "a.txt") |> should.be_true

  let assert Ok(content) = jj.file_show(repo, jj.rev(base.change_id), "a.txt")
  content |> should.equal("hello\n")

  let assert Ok(stat) =
    jj.diff_stat(repo, jj.expr("root()"), jj.rev(base.change_id))
  list.any(stat, fn(e) { e.path == "a.txt" }) |> should.be_true

  jj.is_conflicted(repo, jj.rev(base.change_id)) |> should.equal(Ok(False))

  // 6. move_main: GuardRefused with no lease, wrong resource, non-positive
  // epoch, or no decision; Ok with a well-formed proof of both. "main" is
  // freely movable in this throwaway repo (only the shared UOS coordinator
  // adds any further, external policy).
  jj.move_main(repo, jj.at(), None, None)
  |> expect_guard_refused

  let bad_resource =
    jj.LeaseProof(
      resource: "not/integration-main",
      holder: "worker",
      epoch: 1,
      operation_id: "op-1",
    )
  let decision =
    jj.DecisionRef(path: "docs/decisions/x.md", decision_id: "DEC-1")
  jj.move_main(repo, jj.at(), Some(bad_resource), Some(decision))
  |> expect_guard_refused

  let zero_epoch =
    jj.LeaseProof(
      resource: "integration/main",
      holder: "worker",
      epoch: 0,
      operation_id: "op-1",
    )
  jj.move_main(repo, jj.at(), Some(zero_epoch), Some(decision))
  |> expect_guard_refused

  let good_lease =
    jj.LeaseProof(
      resource: "integration/main",
      holder: "worker",
      epoch: 3,
      operation_id: "op-42",
    )
  jj.move_main(repo, jj.at(), Some(good_lease), None) |> expect_guard_refused

  let assert Ok(moved) =
    jj.move_main(repo, jj.at(), Some(good_lease), Some(decision))
  moved.name |> should.equal("main")
  moved.change_id |> should.equal(second.change_id)

  // The guarded move recorded its proof as a trailer on the target
  // commit's full description (not visible through the first-line-only
  // `show`, which is exactly why description_of exists).
  let assert Ok(full) = jj.description_of(repo, jj.at())
  string.contains(full, "Guard-Lease: integration/main@epoch=3")
  |> should.be_true
  string.contains(full, "Guard-Decision: docs/decisions/x.md#DEC-1")
  |> should.be_true

  rm_rf(dir)
  rm_rf(ws_path)
}

fn expect_guard_refused(result: Result(jj.Bookmark, jj.Error)) -> Nil {
  case result {
    Error(jj.GuardRefused(_)) -> Nil
    other -> {
      other |> should.equal(Error(jj.GuardRefused("expected a refusal")))
    }
  }
}

// -- Conflicts and integrate_chain ------------------------------------------

pub fn conflict_and_integrate_chain_test() {
  let repo = fresh_repo("chain")
  let dir = dir_of(repo)

  let assert Ok(Nil) = file_write(dir <> "/f.txt", "line1\n")
  let assert Ok(Nil) = jj.describe(repo, jj.at(), "base")
  let assert Ok(base) = jj.show(repo, jj.at())

  // branchA and branchB both edit the same line of the same file from the
  // same base: rebasing one onto the other is a genuine, reproducible
  // conflict (verified directly against jj 0.44 before writing this test).
  let assert Ok(a) = jj.new(repo, [base.change_id], "branchA")
  let assert Ok(Nil) = file_write(dir <> "/f.txt", "lineA\n")
  let assert Ok(b) = jj.new(repo, [base.change_id], "branchB")
  let assert Ok(Nil) = file_write(dir <> "/f.txt", "lineB\n")

  let assert Ok(Nil) =
    jj.rebase_source(repo, jj.rev(b.change_id), jj.rev(a.change_id))
  jj.is_conflicted(repo, jj.rev(b.change_id)) |> should.equal(Ok(True))
  // The change that was never rebased is unaffected.
  jj.is_conflicted(repo, jj.rev(a.change_id)) |> should.equal(Ok(False))

  // integrate_chain: a positive chain (changeC then changeD, touching
  // different files, both rooted at base) succeeds and orders parents
  // correctly: the first change lands on `base`, the second on the first.
  let assert Ok(c) = jj.new(repo, [base.change_id], "changeC")
  let assert Ok(Nil) = file_write(dir <> "/g.txt", "g content\n")
  let assert Ok(d) = jj.new(repo, [base.change_id], "changeD")
  let assert Ok(Nil) = file_write(dir <> "/h.txt", "h content\n")
  // One more write-class call snapshots the pending h.txt edit before
  // integrate_chain's own rebases run.
  let assert Ok(Nil) = jj.describe(repo, jj.at(), "changeD")

  let assert Ok(integrated) =
    jj.integrate_chain(repo, [c.change_id, d.change_id], base.change_id)
  list.length(integrated) |> should.equal(2)
  let assert [c_result, d_result] = integrated
  c_result.parents |> should.equal([base.change_id])
  d_result.parents |> should.equal([c_result.change_id])
  c_result.conflict |> should.be_false
  d_result.conflict |> should.be_false

  // A negative chain: changeE and changeF both edit f.txt's current
  // (post-integration) content the same conflicting way from the same
  // parent, so integrate_chain must stop at the first conflict and report
  // how far it got, rather than leaving a silently-conflicted result.
  let assert Ok(base2) = jj.show(repo, jj.rev(d_result.change_id))
  let assert Ok(e) = jj.new(repo, [base2.change_id], "changeE")
  let assert Ok(Nil) = file_write(dir <> "/f.txt", "lineE\n")
  let assert Ok(f) = jj.new(repo, [base2.change_id], "changeF")
  let assert Ok(Nil) = file_write(dir <> "/f.txt", "lineF\n")
  let assert Ok(Nil) = jj.describe(repo, jj.at(), "changeF")

  case jj.integrate_chain(repo, [e.change_id, f.change_id], base2.change_id) {
    Error(jj.CommandFailed(output: msg, ..)) ->
      string.contains(msg, "aborted after 1/2") |> should.be_true
    other -> {
      other |> should.equal(Ok([]))
    }
  }

  rm_rf(dir)
}
