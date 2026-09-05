import filepath
import gleam/crypto
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile
import uos_planning_ledger/digest
import uos_planning_ledger/writer_lock

type CoordinatorMessage {
  Ready(process.Subject(Nil))
  Attempted(Result(writer_lock.Lock, writer_lock.LockError))
}

const contender_count = 64

pub fn atomic_directory_lock_has_exactly_one_concurrent_winner_test() {
  let assert Ok(workspace_root) = simplifile.resolve("../../..")
  let lock_path = unique_lock_path(workspace_root, "race")
  let _ = simplifile.delete(lock_path)
  let coordinator = process.new_subject()

  int.range(from: 1, to: contender_count + 1, with: Nil, run: fn(_, index) {
    let _ =
      process.spawn_unlinked(fn() {
        let start = process.new_subject()
        process.send(coordinator, Ready(start))
        let assert Ok(Nil) = process.receive(from: start, within: 5000)
        process.send(
          coordinator,
          Attempted(writer_lock.acquire(
            at: lock_path,
            owner_context: "contender-" <> int.to_string(index),
          )),
        )
      })
    Nil
  })

  let starts = collect_ready(coordinator, contender_count, [])
  starts |> list.each(fn(start) { process.send(start, Nil) })
  let attempts = collect_attempts(coordinator, contender_count, [])
  let winners =
    attempts
    |> list.fold([], fn(acc, attempt) {
      case attempt {
        Ok(lock) -> [lock, ..acc]
        Error(_) -> acc
      }
    })
  let expected_losers =
    attempts
    |> list.filter(fn(attempt) {
      case attempt {
        Error(writer_lock.FilesystemFailure(simplifile.Eexist)) -> True
        _ -> False
      }
    })

  let assert [winner] = winners
  list.length(expected_losers) |> should.equal(contender_count - 1)
  let assert Ok(owner) = simplifile.read(lock_path <> "/owner")
  owner |> string.starts_with("contender-") |> should.be_true
  writer_lock.release(winner) |> should.equal(Ok(Nil))
  simplifile.exists(filepath: lock_path, follow_links: False)
  |> should.equal(Ok(False))
  let assert Ok(next_owner) =
    writer_lock.acquire(at: lock_path, owner_context: "next-owner")
  writer_lock.release(next_owner) |> should.equal(Ok(Nil))
}

pub fn release_fails_closed_if_owner_metadata_changes_test() {
  let assert Ok(workspace_root) = simplifile.resolve("../../..")
  let lock_path = unique_lock_path(workspace_root, "ownership")
  let _ = simplifile.delete(lock_path)
  let assert Ok(lock) =
    writer_lock.acquire(at: lock_path, owner_context: "original")
  let assert Ok(Nil) =
    simplifile.write(to: lock_path <> "/owner", contents: "replacement")

  let assert Error(writer_lock.OwnershipLost) = writer_lock.release(lock)
  simplifile.read(lock_path <> "/owner")
  |> should.equal(Ok("replacement"))

  let _ = simplifile.delete(lock_path)
}

pub fn release_refuses_to_recursively_delete_unexpected_children_test() {
  let assert Ok(workspace_root) = simplifile.resolve("../../..")
  let lock_path = unique_lock_path(workspace_root, "unexpected-child")
  let assert Ok(lock) =
    writer_lock.acquire(at: lock_path, owner_context: "original")
  let unexpected = lock_path <> "/not-owned-by-lock-protocol"
  let assert Ok(Nil) = simplifile.write(to: unexpected, contents: "retain")

  let assert Error(writer_lock.FilesystemFailure(_)) = writer_lock.release(lock)
  simplifile.read(unexpected) |> should.equal(Ok("retain"))
  simplifile.exists(filepath: lock_path, follow_links: False)
  |> should.equal(Ok(True))

  let _ = simplifile.delete(lock_path)
}

fn unique_lock_path(workspace_root: String, label: String) -> String {
  let nonce =
    crypto.strong_random_bytes(16)
    |> digest.sha256_hex
  filepath.join(
    workspace_root,
    "docs/journal/uos-planning-ledger/build/writer-lock-"
      <> label
      <> "-"
      <> nonce,
  )
}

fn collect_ready(
  coordinator: process.Subject(CoordinatorMessage),
  remaining: Int,
  acc: List(process.Subject(Nil)),
) -> List(process.Subject(Nil)) {
  case remaining {
    0 -> acc
    _ -> {
      let assert Ok(Ready(start)) =
        process.receive(from: coordinator, within: 5000)
      collect_ready(coordinator, remaining - 1, [start, ..acc])
    }
  }
}

fn collect_attempts(
  coordinator: process.Subject(CoordinatorMessage),
  remaining: Int,
  acc: List(Result(writer_lock.Lock, writer_lock.LockError)),
) -> List(Result(writer_lock.Lock, writer_lock.LockError)) {
  case remaining {
    0 -> acc
    _ -> {
      let assert Ok(Attempted(attempt)) =
        process.receive(from: coordinator, within: 5000)
      collect_attempts(coordinator, remaining - 1, [attempt, ..acc])
    }
  }
}
