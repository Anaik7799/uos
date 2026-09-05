/// Lustre component for KMS Catalog plane (SC-GLM-UI-001).
/// Manages key checkpoints, total keys, and active key tracking.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import gleam/list

pub type KmsModel {
  KmsModel(checkpoints: List(Checkpoint), total_keys: Int, active_keys: Int)
}

pub type Checkpoint {
  Checkpoint(id: String, label: String, timestamp: Int, key_count: Int)
}

pub type KmsMsg {
  CheckpointsLoaded(List(Checkpoint))
  KeyRotated(String)
  RefreshKms
}

pub fn init() -> KmsModel {
  KmsModel(checkpoints: [], total_keys: 0, active_keys: 0)
}

pub fn update(model: KmsModel, msg: KmsMsg) -> KmsModel {
  case msg {
    CheckpointsLoaded(cps) -> KmsModel(..model, checkpoints: cps)
    KeyRotated(_key_id) -> model
    RefreshKms -> model
  }
}

pub fn latest_checkpoint(model: KmsModel) -> Result(Checkpoint, Nil) {
  list.first(model.checkpoints)
}

pub fn checkpoint_count(model: KmsModel) -> Int {
  list.length(model.checkpoints)
}
