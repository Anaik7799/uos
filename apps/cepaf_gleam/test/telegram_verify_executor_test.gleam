import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_executor as executor
import cepaf_gleam/harness/telegram_verify_loader as loader
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const guardian_sha256 = "d1dc2995fe52915e9c2a7b39309f23a8197cfb273d025f3453ebd904b24f50f4"

fn guardian() -> executor.Guardian {
  let assert Ok(cwd) = simplifile.current_directory()
  executor.Guardian(
    cwd <> "/../../tools/validation/verify_guardian.exe",
    guardian_sha256,
  )
}

fn fresh_root(tag: String) -> String {
  let root =
    "/tmp/uos_tg_verify_exec_test_"
    <> tag
    <> "_"
    <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(root <> "/gates")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/evidence")
  root
}

fn script(root: String, name: String, body: String) -> String {
  let content = "#!/bin/sh\n" <> body <> "\n"
  let path = root <> "/gates/" <> name
  let assert Ok(_) = simplifile.write(path, content)
  let assert Ok(_) = simplifile.set_permissions_octal(path, 0o755)
  files.digest(content)
}

/// Two gates; the second gate's body is the variable under test.
fn setup(root: String, unit_body: String, unit_timeout: Int) -> loader.Loaded {
  let build = script(root, "build.sh", "echo built \"$1\"")
  let unit = script(root, "unit.sh", unit_body)
  let assert Ok(_) = simplifile.write(root <> "/gates/build.in", "b")
  let assert Ok(_) = simplifile.write(root <> "/gates/unit.in", "u")
  let assert Ok(p) =
    v.profile(
      "telegram-core",
      string.repeat("a", 40),
      string.repeat("b", 64),
      [
        v.Gate("build", build, files.digest("b"), 2000),
        v.Gate("unit", unit, files.digest("u"), unit_timeout),
      ],
      2000 + unit_timeout,
    )
  let assert Ok(_) =
    simplifile.write(root <> "/profile.json", v.canonical_json(p))
  let assert Ok(l) =
    loader.load(root, "profile.json", v.profile_digest(p), [
      loader.Locator("build", "gates/build.sh", "gates/build.in"),
      loader.Locator("unit", "gates/unit.sh", "gates/unit.in"),
    ])
  l
}

fn binding(l: loader.Loaded) -> v.Binding {
  let assert Ok(b) = v.binding(loader.profile(l), "bot999/inbox8101", 1)
  b
}

fn evidence(root: String, b: v.Binding, gate: String) -> String {
  let assert Ok(text) =
    simplifile.read(
      root
      <> "/"
      <> executor.evidence_dir("evidence", b)
      <> "/"
      <> gate
      <> ".out",
    )
  text
}

fn run(root: String, l: loader.Loaded) {
  executor.execute(l, root, binding(l), guardian(), root, "evidence")
}

pub fn all_gates_pass_yields_verified_evidence_test() {
  let root = fresh_root("pass")
  let l = setup(root, "echo unit ok", 2000)
  let assert Ok(out) = run(root, l)
  out.assessment |> should.equal(v.VerifiedEvidence)
  list.map(out.runs, fn(r) { r.status }) |> should.equal(["PASS", "PASS"])
  let b = binding(l)
  evidence(root, b, "build")
  |> should.equal("built " <> root <> "/gates/build.in\n")
  // The receipt's evidence digest is the digest of the preserved bytes.
  let assert [first, ..] = out.runs
  first.evidence_sha256
  |> should.equal(files.digest(evidence(root, b, "build")))
}

pub fn failing_gate_keeps_partial_output_and_fails_test() {
  let root = fresh_root("fail")
  let l = setup(root, "echo failing detail\nexit 2", 2000)
  let assert Ok(out) = run(root, l)
  out.assessment |> should.equal(v.Failed("gate_not_passed"))
  let assert [_, unit] = out.runs
  unit.status |> should.equal("FAIL")
  unit.child_exit |> should.equal(2)
  evidence(root, binding(l), "unit") |> should.equal("failing detail\n")
}

pub fn hanging_gate_is_killed_with_partial_output_preserved_test() {
  let root = fresh_root("hang")
  let l = setup(root, "echo before hang\nsleep 10", 300)
  let assert Ok(out) = run(root, l)
  let assert [_, unit] = out.runs
  unit.result |> should.equal("killed_deadline")
  unit.status |> should.equal("ERROR")
  evidence(root, binding(l), "unit") |> should.equal("before hang\n")
  { out.assessment != v.VerifiedEvidence } |> should.be_true
}

pub fn signalled_gate_is_an_error_with_output_test() {
  let root = fresh_root("sig")
  let l = setup(root, "echo before signal\nkill -9 $$", 2000)
  let assert Ok(out) = run(root, l)
  let assert [_, unit] = out.runs
  unit.result |> should.equal("child_signalled")
  evidence(root, binding(l), "unit") |> should.equal("before signal\n")
  { out.assessment != v.VerifiedEvidence } |> should.be_true
}

pub fn artifact_swapped_after_load_is_refused_before_spawn_test() {
  let root = fresh_root("swap")
  let l = setup(root, "echo unit ok", 2000)
  let _ = script(root, "unit.sh", "echo swapped")
  run(root, l)
  |> should.equal(Error("artifact_changed:executable_pin_mismatch:unit"))
}

pub fn wrong_guardian_pin_is_refused_test() {
  let root = fresh_root("gpin")
  let l = setup(root, "echo unit ok", 2000)
  let g = executor.Guardian(guardian().path, string.repeat("0", 64))
  executor.execute(l, root, binding(l), g, root, "evidence")
  |> should.equal(Error("gate_build:guardian_pin_mismatch"))
}

pub fn evidence_is_never_overwritten_test() {
  let root = fresh_root("again")
  let l = setup(root, "echo unit ok", 2000)
  let assert Ok(_) = run(root, l)
  run(root, l) |> should.equal(Error("evidence_dir_exists_or_unavailable"))
}

pub fn binding_for_another_profile_is_refused_test() {
  let root = fresh_root("bind")
  let l = setup(root, "echo unit ok", 2000)
  let foreign = v.Binding(..binding(l), profile_sha256: string.repeat("f", 64))
  executor.execute(l, root, foreign, guardian(), root, "evidence")
  |> should.equal(Error("binding_mismatch"))
}

/// A pinned but dishonest guardian: prints a fixed receipt and payload, then
/// exits with `code`. The adapter must check the receipt, not trust it.
fn fake_guardian(root: String, receipt: String, payload: String, code: Int) {
  let content =
    "#!/bin/sh\nprintf '%s\\n%s' '"
    <> receipt
    <> "' '"
    <> payload
    <> "'\nexit "
    <> int.to_string(code)
    <> "\n"
  let path = root <> "/fake_guardian.sh"
  let assert Ok(_) = simplifile.write(path, content)
  let assert Ok(_) = simplifile.set_permissions_octal(path, 0o755)
  executor.Guardian(path, files.digest(content))
}

pub fn guardian_payload_digest_lie_is_refused_test() {
  let root = fresh_root("lie_sha")
  let l = setup(root, "echo unit ok", 2000)
  let g =
    fake_guardian(
      root,
      "{\"guardian\":\"uos.telegram.verify.guardian.v1\",\"result\":\"child_exited\",\"cleanup\":\"confirmed\",\"child_exit\":0,\"output_bytes\":2,\"output_sha256\":\""
        <> string.repeat("0", 64)
        <> "\",\"truncated\":false}",
      "ok",
      0,
    )
  executor.execute(l, root, binding(l), g, root, "evidence")
  |> should.equal(Error("gate_build:guardian_output_digest_mismatch"))
}

pub fn guardian_exit_code_not_matching_result_is_cleanup_unknown_test() {
  // Claims a clean exit but exits with the deadline-kill status.
  let root = fresh_root("lie_code")
  let l = setup(root, "echo unit ok", 2000)
  let g =
    fake_guardian(
      root,
      "{\"guardian\":\"uos.telegram.verify.guardian.v1\",\"result\":\"child_exited\",\"cleanup\":\"confirmed\",\"child_exit\":0,\"output_bytes\":0,\"output_sha256\":\"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\"truncated\":false}",
      "",
      4,
    )
  executor.execute(l, root, binding(l), g, root, "evidence")
  |> should.equal(Error("gate_build:cleanup_unknown"))
}

pub fn foreign_guardian_marker_is_refused_test() {
  let root = fresh_root("marker")
  let l = setup(root, "echo unit ok", 2000)
  let g =
    fake_guardian(
      root,
      "{\"guardian\":\"uos.sa_plan.observer.guardian.v1\",\"result\":\"child_exited\",\"cleanup\":\"confirmed\",\"child_exit\":0,\"output_bytes\":0}",
      "",
      0,
    )
  executor.execute(l, root, binding(l), g, root, "evidence")
  |> should.equal(Error("gate_build:guardian_marker_mismatch"))
}
