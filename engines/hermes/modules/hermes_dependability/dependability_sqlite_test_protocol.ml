type fault = Open_failure | Close_failure | Busy_once
type fixture = In_memory | Temporary_file | Fault_injection of fault
type registry = Dependability_sqlite_location.For_test.registry
type lease = Dependability_sqlite_location.For_test.lease
type release_outcome = Dependability_sqlite_location.For_test.release_outcome
type cleanup_outcome = Dependability_sqlite_location.For_test.cleanup_outcome
type error = Dependability_sqlite_location.For_test.error

let all =
  [ In_memory; Temporary_file; Fault_injection Open_failure;
    Fault_injection Close_failure; Fault_injection Busy_once ]

let fixture_tag = function
  | In_memory ->
      Dependability_sqlite_location.For_test.In_memory
  | Temporary_file ->
      Dependability_sqlite_location.For_test.Temporary_file
  | Fault_injection Open_failure ->
      Dependability_sqlite_location.For_test.Fault_open
  | Fault_injection Close_failure ->
      Dependability_sqlite_location.For_test.Fault_close
  | Fault_injection Busy_once ->
      Dependability_sqlite_location.For_test.Fault_busy_once

let create = Dependability_sqlite_location.For_test.create
let maximum_live = Dependability_sqlite_location.For_test.maximum_live
let active_count = Dependability_sqlite_location.For_test.active_count

let acquire registry fixture =
  Dependability_sqlite_location.For_test.acquire registry (fixture_tag fixture)

let reference = Dependability_sqlite_location.For_test.reference
let replay = Dependability_sqlite_location.For_test.replay
let release = Dependability_sqlite_location.For_test.release
let cleanup = Dependability_sqlite_location.For_test.cleanup
let lease_digest = Dependability_sqlite_location.For_test.lease_digest
let release_replayed = Dependability_sqlite_location.For_test.release_replayed

let release_receipt_digest =
  Dependability_sqlite_location.For_test.release_receipt_digest

let cleanup_replayed = Dependability_sqlite_location.For_test.cleanup_replayed

let cleanup_released_count =
  Dependability_sqlite_location.For_test.cleanup_released_count

let cleanup_receipt_digest =
  Dependability_sqlite_location.For_test.cleanup_receipt_digest

let string_of_error = Dependability_sqlite_location.For_test.string_of_error
