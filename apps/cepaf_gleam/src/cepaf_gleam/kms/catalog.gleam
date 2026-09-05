// STAMP: SC-SING-008, SC-SING-009
// AOR: AOR-KMS-001
// Criticality: Level 6 (CRITICAL) - Key Management and Checkpoint Catalog
//
// This actor manages cryptographic checkpoints and metadata registries for the mesh.

import cepaf_gleam/zenoh/client.{type Session}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

// =============================================================================
// Domain Types (Ported from KmsCatalog.fs)
// =============================================================================

pub type Checkpoint {
  Checkpoint(
    id: String,
    hash: String,
    timestamp: String,
    // ISO8601
    metadata: Dict(String, String),
  )
}

pub type CatalogState {
  CatalogState(
    actor_id: String,
    db_path: String,
    checkpoints: Dict(String, Checkpoint),
    zenoh_session: Option(Session),
  )
}

// =============================================================================
// Actor Messages
// =============================================================================

pub type Message {
  Commit(checkpoint: Checkpoint, reply_to: Subject(Result(String, String)))
  Verify(id: String, reply_to: Subject(Bool))
  Rollback(id: String, reply_to: Subject(Result(Nil, String)))
  RotateKey(
    id: String,
    new_hash: String,
    reply_to: Subject(Result(String, String)),
  )
  RevokeKey(id: String, reply_to: Subject(Result(Nil, String)))
  SyncRuntime
  IngestRepository(path: String)
  Shutdown
}

// =============================================================================
// Actor Implementation
// =============================================================================

pub fn start(
  actor_id: String,
  db_path: String,
  session: Option(Session),
) -> Result(Subject(Message), actor.StartError) {
  let initial_state =
    CatalogState(
      actor_id: actor_id,
      db_path: db_path,
      checkpoints: dict.new(),
      zenoh_session: session,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn handle_message(
  state: CatalogState,
  message: Message,
) -> actor.Next(CatalogState, Message) {
  case message {
    Commit(checkpoint, reply_to) -> {
      io.println("[KMS-CATALOG] Committing checkpoint: " <> checkpoint.id)

      // Publish to mesh if Zenoh is connected
      case state.zenoh_session {
        Some(s) -> {
          let topic = "indrajaal/kms/catalog/" <> state.actor_id <> "/commit"
          let _ = client.put(s, topic, checkpoint.hash)
          Nil
        }
        None -> Nil
      }

      let new_checkpoints =
        dict.insert(state.checkpoints, checkpoint.id, checkpoint)
      process.send(reply_to, Ok(checkpoint.id))
      actor.continue(CatalogState(..state, checkpoints: new_checkpoints))
    }
    Verify(id, reply_to) -> {
      let is_valid = dict.has_key(state.checkpoints, id)
      process.send(reply_to, is_valid)
      actor.continue(state)
    }
    Rollback(id, reply_to) -> {
      case dict.has_key(state.checkpoints, id) {
        True -> {
          io.println("[KMS-CATALOG] Rolling back checkpoint: " <> id)

          case state.zenoh_session {
            Some(s) -> {
              let topic =
                "indrajaal/kms/catalog/" <> state.actor_id <> "/rollback"
              let _ = client.put(s, topic, id)
              Nil
            }
            None -> Nil
          }

          let new_checkpoints = dict.delete(state.checkpoints, id)
          process.send(reply_to, Ok(Nil))
          actor.continue(CatalogState(..state, checkpoints: new_checkpoints))
        }
        False -> {
          process.send(reply_to, Error("Checkpoint not found for rollback"))
          actor.continue(state)
        }
      }
    }
    RotateKey(id, new_hash, reply_to) -> {
      case dict.get(state.checkpoints, id) {
        Ok(existing) -> {
          io.println("[KMS-CATALOG] Rotating key for checkpoint: " <> id)
          let updated = Checkpoint(..existing, hash: new_hash)

          case state.zenoh_session {
            Some(s) -> {
              let topic =
                "indrajaal/kms/catalog/" <> state.actor_id <> "/rotate"
              let _ = client.put(s, topic, new_hash)
              Nil
            }
            None -> Nil
          }

          let new_checkpoints = dict.insert(state.checkpoints, id, updated)
          process.send(reply_to, Ok(id))
          actor.continue(CatalogState(..state, checkpoints: new_checkpoints))
        }
        Error(_) -> {
          process.send(reply_to, Error("Checkpoint not found for rotation"))
          actor.continue(state)
        }
      }
    }
    RevokeKey(id, reply_to) -> {
      case dict.has_key(state.checkpoints, id) {
        True -> {
          io.println("[KMS-CATALOG] Revoking key for checkpoint: " <> id)

          case state.zenoh_session {
            Some(s) -> {
              let topic =
                "indrajaal/kms/catalog/" <> state.actor_id <> "/revoke"
              let _ = client.put(s, topic, id)
              Nil
            }
            None -> Nil
          }

          let new_checkpoints = dict.delete(state.checkpoints, id)
          process.send(reply_to, Ok(Nil))
          actor.continue(CatalogState(..state, checkpoints: new_checkpoints))
        }
        False -> {
          process.send(reply_to, Error("Checkpoint not found for revocation"))
          actor.continue(state)
        }
      }
    }
    SyncRuntime -> {
      io.println(
        "[KMS-CATALOG] Syncing runtime holons to " <> state.db_path <> "...",
      )
      actor.continue(state)
    }
    IngestRepository(path) -> {
      io.println(
        "[KMS-CATALOG] Ingesting repository metadata from " <> path <> "...",
      )
      actor.continue(state)
    }
    Shutdown -> {
      io.println("[KMS-CATALOG] Shutting down...")
      actor.stop()
    }
  }
}
