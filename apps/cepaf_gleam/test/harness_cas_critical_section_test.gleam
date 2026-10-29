import cepaf_gleam/harness/files
import cepaf_gleam/harness/operations
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/result
import gleeunit/should
import simplifile
import uos_swarm/session_authority as authority
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

const scratch = "/tmp/uos-harness-cas-critical-tests"

pub fn successor_write_path_serializes_competing_private_effects_test() {
  let #(db, root, _id, epoch) = setup()
  let assert Ok(Nil) = files.create(root, "target.json", "base")
  let expected = files.digest("base")
  let results = process.new_subject()
  list.each([1, 2], fn(writer) {
    let _ =
      process.spawn_unlinked(fn() {
        let result =
          operations.write_file_with_cas_at(
            db,
            "cas-session",
            "task:cas-test",
            epoch,
            "test-grant",
            "write-" <> int.to_string(writer),
            root,
            "target.json",
            "writer-" <> int.to_string(writer),
            expected,
          )
        process.send(results, #(writer, result))
      })
  })
  let assert Ok(#(writer_a, result_a)) = process.receive(results, 5000)
  let assert Ok(#(writer_b, result_b)) = process.receive(results, 5000)
  list.count([result_a, result_b], result.is_ok) |> should.equal(1)
  list.count([result_a, result_b], fn(result) {
    result == Error("refused: source_digest_conflict")
  })
  |> should.equal(1)
  let winner = case result_a {
    Ok(_) -> writer_a
    Error(_) -> writer_b
  }
  files.read(root, "target.json")
  |> should.equal(Ok("writer-" <> int.to_string(winner)))
}

fn setup() -> #(String, String, String, Int) {
  setup_with_ttl(60_000_000)
}

fn setup_with_ttl(ttl_us: Int) -> #(String, String, String, Int) {
  let _ = simplifile.create_directory_all(scratch)
  let id = unique_id()
  let root = scratch <> "/root-" <> id
  let db = scratch <> "/coord-" <> id <> ".sqlite3"
  let assert Ok(_) = simplifile.create_directory(root)
  let assert Ok(opened) = store.open(db)
  let assert Ok(_) =
    store.append(
      opened,
      sync.Register("cas-session", "codex", root, "test-revision", []),
      "register-" <> id,
    )
  let assert Ok(_) =
    store.append(
      opened,
      sync.Heartbeat("cas-session", "test-revision", []),
      "heartbeat-" <> id,
    )
  let assert Ok(#(claim, False)) =
    store.append(
      opened,
      sync.Claim("cas-session", "task:cas-test", ttl_us),
      "claim-" <> id,
    )
  let assert Ok(Nil) = store.close(opened)
  #(db, root, id, claim.epoch)
}

fn enter(
  db: String,
  path: String,
  operation: String,
  epoch: Int,
  body: fn() -> Result(a, String),
) -> Result(a, String) {
  authority.with_cas_critical_section_at(
    db,
    "cas-session",
    "task:cas-test",
    epoch,
    path,
    operation,
    body,
  )
}

pub fn two_process_same_session_different_intents_has_one_cas_winner_test() {
  let #(db, root, _id, epoch) = setup()
  let assert Ok(Nil) = files.create(root, "target.json", "base")
  let expected = files.digest("base")
  let started = process.new_subject()
  let locked = process.new_subject()
  let results = process.new_subject()

  list.each([1, 2], fn(worker) {
    let _ =
      process.spawn_unlinked(fn() {
        let gate = process.new_subject()
        process.send(started, #(worker, gate))
        let outcome =
          enter(
            db,
            "target.json",
            "cas-op-" <> int.to_string(worker),
            epoch,
            fn() {
              process.send(locked, worker)
              use _ <- result.try(
                process.receive(gate, 5000)
                |> result.map_error(fn(_) { "gate_timeout" }),
              )
              use _ <- result.try(files.replace(
                root,
                "target.json",
                expected,
                "writer-" <> int.to_string(worker),
              ))
              use written <- result.try(files.read(root, "target.json"))
              Ok(files.digest(written))
            },
          )
        process.send(results, #(worker, outcome))
      })
  })

  let assert Ok(#(first, first_gate)) = process.receive(started, 5000)
  let assert Ok(#(_second, second_gate)) = process.receive(started, 5000)
  let assert Ok(first_locked) = process.receive(locked, 5000)
  case first_locked == first {
    True -> process.send(first_gate, Nil)
    False -> process.send(second_gate, Nil)
  }
  let assert Ok(second_locked) = process.receive(locked, 5000)
  case second_locked == first {
    True -> process.send(first_gate, Nil)
    False -> process.send(second_gate, Nil)
  }
  let assert Ok(#(worker_a, result_a)) = process.receive(results, 5000)
  let assert Ok(#(worker_b, result_b)) = process.receive(results, 5000)
  let outcomes = [result_a, result_b]
  list.count(outcomes, result.is_ok) |> should.equal(1)
  list.count(outcomes, fn(outcome) {
    outcome == Error("refused: source_digest_conflict")
  })
  |> should.equal(1)
  files.read(root, "target.json")
  |> should.equal(
    Ok(case result_a {
      Ok(_) -> "writer-" <> int.to_string(worker_a)
      Error(_) -> "writer-" <> int.to_string(worker_b)
    }),
  )
}

pub fn transaction_rollback_before_rename_and_unknown_after_rename_recover_test() {
  let #(db, root, _id, epoch) = setup()
  let assert Ok(Nil) = files.create(root, "target.json", "base")
  let old_sha = files.digest("base")
  enter(db, "target.json", "pre-rename", epoch, fn() {
    Error("simulated_process_death_before_rename")
  })
  |> should.equal(Error("refused: simulated_process_death_before_rename"))
  files.read(root, "target.json") |> should.equal(Ok("base"))

  enter(db, "target.json", "post-rename", epoch, fn() {
    use _ <- result.try(files.replace(
      root,
      "target.json",
      old_sha,
      "after-rename",
    ))
    Error("simulated_process_death_after_rename_before_commit")
  })
  |> should.equal(Error(
    "refused: simulated_process_death_after_rename_before_commit",
  ))
  // The filesystem effect survived while SQLite rolled its transaction back:
  // the caller must reconcile this state and never blindly retry the old CAS.
  files.read(root, "target.json") |> should.equal(Ok("after-rename"))
  let new_sha = files.digest("after-rename")
  enter(db, "target.json", "reconcile-new-op", epoch, fn() {
    use _ <- result.try(files.replace(
      root,
      "target.json",
      new_sha,
      "reconciled",
    ))
    files.read(root, "target.json")
    |> result.map(files.digest)
  })
  |> should.equal(Ok(files.digest("reconciled")))
}

pub fn killed_writer_rolls_back_pre_rename_and_leaves_post_rename_unknown_test() {
  let #(db, root, _id, epoch) = setup()
  let assert Ok(Nil) = files.create(root, "target.json", "base")
  let old_sha = files.digest("base")

  let before_gate = process.new_subject()
  let before_entered = process.new_subject()
  let before_pid =
    process.spawn_unlinked(fn() {
      let _ =
        enter(db, "target.json", "killed-before", epoch, fn() {
          process.send(before_entered, Nil)
          let _ = process.receive(before_gate, 30_000)
          Ok(Nil)
        })
    })
  let assert Ok(Nil) = process.receive(before_entered, 5000)
  process.send_abnormal_exit(before_pid, atom.create("kill"))
  // A new writer can acquire BEGIN IMMEDIATE after process death; there is no
  // stale lock file to delete or recover manually.
  enter(db, "target.json", "after-killed-before", epoch, fn() {
    use _ <- result.try(files.replace(
      root,
      "target.json",
      old_sha,
      "after-before",
    ))
    files.read(root, "target.json") |> result.map(files.digest)
  })
  |> should.equal(Ok(files.digest("after-before")))

  let post_gate = process.new_subject()
  let post_entered = process.new_subject()
  let post_pid =
    process.spawn_unlinked(fn() {
      let _ =
        enter(db, "target.json", "killed-after", epoch, fn() {
          use _ <- result.try(files.replace(
            root,
            "target.json",
            files.digest("after-before"),
            "after-rename-before-commit",
          ))
          process.send(post_entered, Nil)
          let _ = process.receive(post_gate, 30_000)
          Ok(Nil)
        })
    })
  let assert Ok(Nil) = process.receive(post_entered, 5000)
  process.send_abnormal_exit(post_pid, atom.create("kill"))
  // The external rename survives but SQLite rolls back. Reconcile from bytes;
  // the old expected digest must not be retried.
  files.read(root, "target.json")
  |> should.equal(Ok("after-rename-before-commit"))
  enter(db, "target.json", "reconcile-killed-after", epoch, fn() {
    use _ <- result.try(files.replace(
      root,
      "target.json",
      files.digest("after-rename-before-commit"),
      "recovered",
    ))
    files.read(root, "target.json") |> result.map(files.digest)
  })
  |> should.equal(Ok(files.digest("recovered")))
}

pub fn expired_and_stale_coordinator_leases_refuse_before_effect_test() {
  let #(db, root, id, epoch) = setup()
  let assert Ok(opened) = store.open_existing(db)
  let assert Ok(_) =
    store.append(
      opened,
      sync.Release("cas-session", "task:cas-test", epoch),
      "release-" <> id,
    )
  let assert Ok(#(next_claim, False)) =
    store.append(
      opened,
      sync.Claim("cas-session", "task:cas-test", 60_000_000),
      "reclaim-" <> id,
    )
  let assert Ok(Nil) = store.close(opened)
  let assert Ok(Nil) = files.create(root, "target.json", "base")
  let ran = process.new_subject()
  enter(db, "target.json", "stale-epoch", epoch, fn() {
    process.send(ran, Nil)
    Ok(Nil)
  })
  |> should.be_error
  process.receive(ran, 0) |> should.equal(Error(Nil))

  enter(db, "target.json", "current-epoch", next_claim.epoch, fn() {
    process.send(ran, Nil)
    Ok(Nil)
  })
  |> should.equal(Ok(Nil))
  process.receive(ran, 0) |> should.equal(Ok(Nil))
}

pub fn expired_coordinator_lease_refuses_before_critical_callback_test() {
  let #(db, root, _id, epoch) = setup_with_ttl(1_000_000)
  let assert Ok(Nil) = files.create(root, "target.json", "base")
  process.sleep(1100)
  let ran = process.new_subject()
  enter(db, "target.json", "expired-lease", epoch, fn() {
    process.send(ran, Nil)
    Ok(Nil)
  })
  |> should.be_error
  process.receive(ran, 0) |> should.equal(Error(Nil))
}

pub fn critical_section_request_rejects_path_traversal_and_bad_operation_id_test() {
  store.critical_section("../target", "op-1") |> should.be_error
  store.critical_section("target", "bad id") |> should.be_error
  store.critical_section("target.json", "op-1") |> should.be_ok
}
