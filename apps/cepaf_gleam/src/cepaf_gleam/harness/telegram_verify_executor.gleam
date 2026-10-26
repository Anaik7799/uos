//// Bounded /verify execution for one reserved, loaded profile. Each gate runs
//// sequentially under the pinned verify guardian, which owns the child,
//// enforces the gate deadline and reaps the process group. Before every gate
//// the loader re-hashes all artifacts, so a swap after load is refused before
//// spawning. Every gate's captured bytes, including partial output from a
//// failing or killed gate, are written as exclusive evidence files and their
//// digests become the receipt's evidence_sha256. The receipt is then
//// classified by the reviewed contract; only VerifiedEvidence means every
//// required gate passed. Nothing here grants admission or deployment.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_loader as loader
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/result

pub const max_gate_output = 65_536

pub type Guardian {
  Guardian(path: String, sha256: String)
}

/// What the guardian observed for one gate. `result` is the guardian's
/// result tag; `child_exit` is -1 when the child did not exit normally.
pub type GateRun {
  GateRun(
    gate_id: String,
    result: String,
    child_exit: Int,
    status: String,
    evidence_sha256: String,
    truncated: Bool,
    elapsed_ms: Int,
  )
}

pub type Outcome {
  Outcome(assessment: v.Assessment, receipt: String, runs: List(GateRun))
}

type Observation {
  Observation(
    result: String,
    child_exit: Int,
    payload: BitArray,
    output_sha256: String,
    truncated: Bool,
    elapsed_ms: Int,
  )
}

@external(erlang, "telegram_verify_exec_ffi", "run")
fn guardian_run(
  guardian: String,
  guardian_sha256: String,
  exe: String,
  exe_sha256: String,
  args: List(String),
  deadline_ms: Int,
  max_bytes: Int,
) -> Result(Observation, String)

@external(erlang, "telegram_verify_exec_ffi", "write_new")
fn write_new(path: String, bytes: BitArray) -> Result(Nil, String)

fn status(o: Observation) -> String {
  case o.result, o.child_exit {
    "child_exited", 0 -> "PASS"
    "child_exited", _ -> "FAIL"
    _, _ -> "ERROR"
  }
}

fn row_json(r: GateRun, g: v.Gate) -> json.Json {
  json.object([
    #("id", json.string(r.gate_id)),
    #("executable_sha256", json.string(g.executable_sha256)),
    #("input_sha256", json.string(g.input_sha256)),
    #("status", json.string(r.status)),
    #("evidence_sha256", json.string(r.evidence_sha256)),
    #("elapsed_ms", json.int(r.elapsed_ms)),
  ])
}

fn receipt(b: v.Binding, rows: List(#(GateRun, v.Gate))) -> String {
  json.object([
    #("schema", json.string("uos.telegram.verify-result.v1")),
    #("request_id", json.string(b.request_id)),
    #("job_id", json.string(b.job_id)),
    #("attempt", json.int(b.attempt)),
    #("profile_sha256", json.string(b.profile_sha256)),
    #("candidate", json.string(b.candidate)),
    #("source_closure_sha256", json.string(b.source_closure_sha256)),
    #("gates", json.array(rows, fn(pair) { row_json(pair.0, pair.1) })),
  ])
  |> json.to_string
}

/// Evidence directory for a job, relative to the evidence root.
pub fn evidence_dir(base: String, b: v.Binding) -> String {
  base <> "/" <> files.digest(b.job_id)
}

fn run_gate(
  l: loader.Loaded,
  root: String,
  g: Guardian,
  gate: v.Gate,
  evidence_root: String,
  dir: String,
) -> Result(GateRun, String) {
  use _ <- result.try(
    loader.recheck(l) |> result.map_error(fn(e) { "artifact_changed:" <> e }),
  )
  use loc <- result.try(
    loader.locator(l, gate.id)
    |> result.replace_error("locator_missing:" <> gate.id),
  )
  use exe <- result.try(files.checked_path(root, loc.executable))
  use input <- result.try(files.checked_path(root, loc.input))
  use o <- result.try(
    guardian_run(
      g.path,
      g.sha256,
      exe,
      gate.executable_sha256,
      [input],
      gate.timeout_ms,
      max_gate_output,
    )
    |> result.map_error(fn(e) { "gate_" <> gate.id <> ":" <> e }),
  )
  use path <- result.try(files.checked_path(
    evidence_root,
    dir <> "/" <> gate.id <> ".out",
  ))
  use _ <- result.try(
    write_new(path, o.payload)
    |> result.map_error(fn(e) { "gate_" <> gate.id <> ":" <> e }),
  )
  Ok(GateRun(
    gate.id,
    o.result,
    o.child_exit,
    status(o),
    o.output_sha256,
    o.truncated,
    o.elapsed_ms,
  ))
}

/// Runs every required gate of the loaded profile for a reserved binding.
/// Errors (changed artifacts, guardian refusal of its own pin, unknown
/// cleanup, unwritable evidence) stop the run: they are not gate failures and
/// must not be reported as a verdict. `evidence_base` must already exist under
/// `evidence_root`; the per-job directory is created here and must be new.
pub fn execute(
  l: loader.Loaded,
  root: String,
  b: v.Binding,
  g: Guardian,
  evidence_root: String,
  evidence_base: String,
) -> Result(Outcome, String) {
  let p = loader.profile(l)
  use _ <- result.try(case v.binding(p, b.request_id, b.attempt) == Ok(b) {
    True -> Ok(Nil)
    False -> Error("binding_mismatch")
  })
  let dir = evidence_dir(evidence_base, b)
  use dir_path <- result.try(files.checked_path(evidence_root, dir))
  use _ <- result.try(
    make_dir(dir_path)
    |> result.replace_error("evidence_dir_exists_or_unavailable"),
  )
  use rows <- result.try(
    list.try_map(v.required_gates(p), fn(gate) {
      run_gate(l, root, g, gate, evidence_root, dir)
      |> result.map(fn(r) { #(r, gate) })
    }),
  )
  let raw = receipt(b, rows)
  use receipt_path <- result.try(files.checked_path(
    evidence_root,
    dir <> "/receipt.json",
  ))
  use _ <- result.try(write_new(receipt_path, bit_array.from_string(raw)))
  let runs = list.map(rows, fn(pair) { pair.0 })
  let observation =
    v.ProcessObservation(
      exit_code: case list.all(runs, fn(r) { r.result == "child_exited" }) {
        True -> 0
        False -> 1
      },
      timed_out: list.any(runs, fn(r) { r.result == "killed_deadline" }),
      reaped: True,
      elapsed_ms: list.fold(runs, 0, fn(sum, r) { sum + r.elapsed_ms }),
    )
  Ok(Outcome(v.assess(p, b, observation, raw), raw, runs))
}

@external(erlang, "telegram_verify_exec_ffi", "make_dir")
fn make_dir(path: String) -> Result(Nil, Nil)
