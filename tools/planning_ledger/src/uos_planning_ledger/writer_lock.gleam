import gleam/crypto
import simplifile
import uos_planning_ledger/digest

/// A successfully acquired cooperative writer lock.
///
/// The constructor is private so release can verify the exact owner token
/// before removing the lock directory. This prevents a stale owner from
/// deleting a replacement lock after external interference.
pub opaque type Lock {
  Lock(path: String, owner_token: String)
}

pub type LockError {
  FilesystemFailure(simplifile.FileError)
  MetadataAndCleanupFailure(
    metadata: simplifile.FileError,
    cleanup: simplifile.FileError,
  )
  OwnershipLost
}

/// Acquire a cooperative lock with one atomic `file:make_dir` operation.
///
/// Existing files, directories, and symlinks fail closed. Locks are never
/// stolen automatically: a crashed writer leaves a stale directory that an
/// operator must diagnose before removal. `owner_context` is journal metadata,
/// not an authority token, and must not contain secrets.
pub fn acquire(
  at path: String,
  owner_context owner_context: String,
) -> Result(Lock, LockError) {
  let owner_token =
    owner_context
    <> ":nonce-sha256-"
    <> digest.sha256_hex(crypto.strong_random_bytes(32))
  case simplifile.create_directory(path) {
    Error(error) -> Error(FilesystemFailure(error))
    Ok(Nil) ->
      case simplifile.set_permissions_octal(for_file_at: path, to: 0o700) {
        Error(error) -> cleanup_after_metadata_failure(path, error)
        Ok(Nil) -> write_owner(path, owner_token)
      }
  }
}

/// Release only the lock whose exact owner token was returned by `acquire`.
pub fn release(lock: Lock) -> Result(Nil, LockError) {
  let Lock(path:, owner_token:) = lock
  case simplifile.read(owner_path(path)) {
    Error(error) -> Error(FilesystemFailure(error))
    Ok(actual) if actual != owner_token -> Error(OwnershipLost)
    Ok(_) -> remove_owned_lock(path)
  }
}

fn write_owner(path: String, owner_token: String) -> Result(Lock, LockError) {
  let owner = owner_path(path)
  case simplifile.write(to: owner, contents: owner_token) {
    Error(error) -> cleanup_after_metadata_failure(path, error)
    Ok(Nil) ->
      case simplifile.set_permissions_octal(for_file_at: owner, to: 0o600) {
        Error(error) -> cleanup_after_metadata_failure(path, error)
        Ok(Nil) -> Ok(Lock(path: path, owner_token: owner_token))
      }
  }
}

fn cleanup_after_metadata_failure(
  path: String,
  metadata_error: simplifile.FileError,
) -> Result(a, LockError) {
  case remove_known_owner_then_directory(path) {
    Ok(Nil) -> Error(FilesystemFailure(metadata_error))
    Error(cleanup_error) ->
      Error(MetadataAndCleanupFailure(
        metadata: metadata_error,
        cleanup: cleanup_error,
      ))
  }
}

/// Remove only protocol-owned metadata, then ask the operating system to
/// remove the directory iff it is empty. This deliberately refuses recursive
/// deletion: an unexpected child is evidence of interference and is retained.
fn remove_owned_lock(path: String) -> Result(Nil, LockError) {
  remove_known_owner_then_directory(path)
  |> map_filesystem_error
}

fn remove_known_owner_then_directory(
  path: String,
) -> Result(Nil, simplifile.FileError) {
  case simplifile.delete_file(at: owner_path(path)) {
    Ok(Nil) | Error(simplifile.Enoent) -> delete_empty_directory(path)
    Error(error) -> Error(error)
  }
}

fn map_filesystem_error(
  outcome: Result(Nil, simplifile.FileError),
) -> Result(Nil, LockError) {
  case outcome {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> Error(FilesystemFailure(error))
  }
}

fn owner_path(path: String) -> String {
  path <> "/owner"
}

/// `simplifile` exposes this exact Erlang helper internally but does not make
/// it public. It is a non-recursive wrapper around `file:del_dir/1`.
@external(erlang, "simplifile_erl", "delete_directory")
fn delete_empty_directory(path: String) -> Result(Nil, simplifile.FileError)
