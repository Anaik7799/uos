(** End-to-End (E2E) Requirement-Driven Test Framework for Hermes Agent Loop.

    Provides registration, preflight resource checking, suite execution, and reporting
    across 4 Tiers:
    - Tier 1: Feature Coverage
    - Tier 2: Boundary & Corner Cases
    - Tier 3: Cross-Feature Combinations (Pairwise)
    - Tier 4: Real-World Application Scenarios
*)

type tier =
  | Tier1_Feature
  | Tier2_Boundary
  | Tier3_Pairwise
  | Tier4_Application

type test_result =
  | Pass
  | Fail of string
  | Skip of string

type test_case = {
  id : string;
  name : string;
  tier : tier;
  feature : string;
  run : unit -> test_result;
}

val register_test : test_case -> unit

val clear_registry : unit -> unit

val get_all_tests : unit -> test_case list
(*@ tests = get_all_tests ()
    pure *)

val string_of_tier : tier -> string
(*@ s = string_of_tier t
    pure *)

val string_of_result : test_result -> string
(*@ s = string_of_result r
    pure *)

val run_preflight : unit -> bool
(*@ ok = run_preflight () *)

val run_suite : unit -> int * int * int
(*@ (pass, fail, skip) = run_suite ()
    ensures pass >= 0 && fail >= 0 && skip >= 0 *)

val run_all : unit -> int
(*@ code = run_all ()
    ensures code = 0 || code = 1 *)
