#use "topfind";;
#require "yojson";;

(* tests/acceptance/contract.ml
   Defines the core data types and serialization contracts for acceptance testing. *)

type status = Pass | Fail | Error

let string_of_status = function
  | Pass -> "PASS"
  | Fail -> "FAIL"
  | Error -> "ERROR"

let status_of_string = function
  | "PASS" -> Pass
  | "FAIL" -> Fail
  | _ -> Error

type observation = {
  exit_code: int;
  status: status;
  passing_tests: int;
  children_reaped: bool;
  raw_output: string;
  data: Yojson.Basic.t option;
}

type receipt = {
  receipt_id: string;
  task_id: string;
  operation: string;
  timestamp_utc: string;
  exit_code: int;
  status: status;
  passing_tests: int;
  children_reaped: bool;
  change_id: string;
  commit_id: string;
  duration_ms: float;
}

let receipt_to_yojson r : Yojson.Basic.t =
  `Assoc [
    ("receipt_id", `String r.receipt_id);
    ("task_id", `String r.task_id);
    ("operation", `String r.operation);
    ("timestamp_utc", `String r.timestamp_utc);
    ("exit_code", `Int r.exit_code);
    ("status", `String (string_of_status r.status));
    ("passing_tests", `Int r.passing_tests);
    ("children_reaped", `Bool r.children_reaped);
    ("candidate", `Assoc [
      ("change_id", `String r.change_id);
      ("commit_id", `String r.commit_id)
    ]);
    ("duration_ms", `Float r.duration_ms)
  ]
