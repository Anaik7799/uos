// STAMP: SC-HOLON-004, SC-GLM-CORE-002
// AOR: AOR-HOLON-004, AOR-GLM-005
// Criticality: Level 2 (HIGH) - Distributed Transaction Manager
//
// Two-phase commit (2PC) coordinator for distributed transactions
// across multiple holon participants with deadlock detection.

import gleam/json

// =============================================================================
// Types
// =============================================================================

pub type TransactionStatus {
  TxPending
  TxRunning
  TxCommitting
  TxAborting
  TxDone
  TxAborted
  TxTimedOut
  TxDeadlocked
}

pub type DistributedTransaction {
  DistributedTransaction(
    id: String,
    participants: List(String),
    status: TransactionStatus,
    started_at: String,
    timeout_ms: Int,
  )
}

// =============================================================================
// FFI Stubs
// =============================================================================

pub fn begin_distributed(
  participants: List(String),
  timeout_ms: Int,
) -> Result(DistributedTransaction, String) {
  let _ = participants
  let _ = timeout_ms
  panic as "NYI: requires 2PC coordinator (SC-HOLON-004)"
}

pub fn prepare(
  tx: DistributedTransaction,
) -> Result(DistributedTransaction, String) {
  let _ = tx
  panic as "NYI: requires participant votes (SC-HOLON-004)"
}

pub fn commit_distributed(
  tx: DistributedTransaction,
) -> Result(DistributedTransaction, String) {
  let _ = tx
  panic as "NYI: requires 2PC (SC-HOLON-004)"
}

pub fn abort_distributed(
  tx: DistributedTransaction,
) -> Result(DistributedTransaction, String) {
  let _ = tx
  panic as "NYI: requires 2PC (SC-HOLON-004)"
}

pub fn check_deadlock(
  transactions: List(DistributedTransaction),
) -> List(String) {
  let _ = transactions
  panic as "NYI: requires wait-for graph (SC-HOLON-004)"
}

// =============================================================================
// Pure Helper Functions
// =============================================================================

pub fn status_to_string(s: TransactionStatus) -> String {
  case s {
    TxPending -> "pending"
    TxRunning -> "running"
    TxCommitting -> "committing"
    TxAborting -> "aborting"
    TxDone -> "done"
    TxAborted -> "aborted"
    TxTimedOut -> "timed_out"
    TxDeadlocked -> "deadlocked"
  }
}

pub fn is_terminal(s: TransactionStatus) -> Bool {
  case s {
    TxDone | TxAborted | TxTimedOut | TxDeadlocked -> True
    TxPending | TxRunning | TxCommitting | TxAborting -> False
  }
}

pub fn tx_to_json(tx: DistributedTransaction) -> json.Json {
  json.object([
    #("id", json.string(tx.id)),
    #("participants", json.array(tx.participants, json.string)),
    #("status", json.string(status_to_string(tx.status))),
    #("started_at", json.string(tx.started_at)),
    #("timeout_ms", json.int(tx.timeout_ms)),
  ])
}

pub fn default_timeout_ms() -> Int {
  30_000
}
