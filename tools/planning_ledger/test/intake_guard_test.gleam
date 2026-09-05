import gleam/crypto
import gleeunit/should
import simplifile
import uos_planning_ledger/digest
import uos_planning_ledger/materializer

pub fn withheld_intake_stops_before_source_read_or_destination_mutation_test() {
  let nonce = crypto.strong_random_bytes(16) |> digest.sha256_hex
  let assert Ok(base) = simplifile.resolve("build")
  let destination = base <> "/intake-hold-" <> nonce <> ".sqlite3"
  let candidate = destination <> ".next.sqlite3"
  let assert Ok(Nil) = simplifile.write(destination, "existing destination")
  let assert Ok(Nil) = simplifile.write(candidate, "foreign candidate")
  // A nonexistent source root proves the intake decision precedes file reads:
  // the old materializer instead returns a filesystem error from this root.
  materializer.materialize(
    workspace_root: base <> "/no-such-source-" <> nonce,
    destination: destination,
    observed_at: "2026-09-05T12:00:00Z",
  )
  |> should.equal(
    Error(materializer.InvariantFailure(
      name: "source intake admission",
      expected: "all fixed-corpus artifacts classified admissible before reading",
      actual: "WITHHELD_PENDING_CLASSIFICATION: INC-UOS-REVIEW-PREFLIGHT-001, INC-UOS-REVIEW-PREFLIGHT-002",
    )),
  )
  simplifile.read(destination) |> should.equal(Ok("existing destination"))
  simplifile.read(candidate) |> should.equal(Ok("foreign candidate"))
  simplifile.exists(destination <> ".materialize.lock", follow_links: False)
  |> should.equal(Ok(False))
  let assert Ok(Nil) = simplifile.delete_file(destination)
  let assert Ok(Nil) = simplifile.delete_file(candidate)
}
