let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let get = function
  | Ok value -> value
  | Error _ -> failwith "production clock observation unavailable"

let valid_timestamp value =
  let rec valid_digit index =
    if index = String.length value then true
    else if index = 8 then valid_digit (index + 1)
    else
      match value.[index] with
      | '0' .. '9' -> valid_digit (index + 1)
      | _ -> false
  in
  String.length value = 13
  && value.[8] = '-'
  && valid_digit 0

let observe ?(lifetime_ns = 1_000_000_000L) () =
  Dependability_clock.observe ~max_pair_span_ns:1_000_000_000L ~lifetime_ns

let rec first_later_wall remaining previous =
  if remaining = 0 then None
  else
    let next = get (observe ()) in
    if Int64.compare (Dependability_clock.wall_ns next)
         (Dependability_clock.wall_ns previous) > 0
    then Some next
    else first_later_wall (remaining - 1) previous

let rec first_after_expiry remaining subject =
  if remaining = 0 then None
  else
    let next = get (observe ()) in
    if Int64.compare (Dependability_clock.monotonic_finished_ns next)
         (Dependability_clock.expires_monotonic_ns subject) >= 0
    then Some next
    else first_after_expiry (remaining - 1) subject

let () =
  check "C1 zero negative and excessive observation bounds refuse"
    (Result.is_error
       (Dependability_clock.observe ~max_pair_span_ns:0L
          ~lifetime_ns:1L)
     && Result.is_error
          (Dependability_clock.observe ~max_pair_span_ns:1L
             ~lifetime_ns:0L)
     && Result.is_error
          (Dependability_clock.observe
             ~max_pair_span_ns:
               (Int64.succ Dependability_clock.maximum_pair_span_ns)
             ~lifetime_ns:1L)
     && Result.is_error
          (Dependability_clock.observe ~max_pair_span_ns:1L
             ~lifetime_ns:
               (Int64.succ Dependability_clock.maximum_lifetime_ns)));

  let first = get (observe ()) in
  check "C2 production observation pairs positive POSIX wall and monotonic time"
    (Int64.compare (Dependability_clock.wall_ns first) 0L > 0
     && Int64.compare (Dependability_clock.monotonic_started_ns first) 0L >= 0
     && Int64.compare (Dependability_clock.monotonic_finished_ns first)
          (Dependability_clock.monotonic_started_ns first) >= 0);
  check "C3 acquisition span and expiry remain inside declared bounds"
    (Int64.compare
       (Int64.sub (Dependability_clock.monotonic_finished_ns first)
          (Dependability_clock.monotonic_started_ns first))
       1_000_000_000L <= 0
     && Int64.equal
          (Dependability_clock.expires_monotonic_ns first)
          (Int64.add (Dependability_clock.monotonic_finished_ns first)
             1_000_000_000L));
  check "C4 receipt is self-validating digest-bound and timestamp-formatted"
    (Dependability_clock.validate first = Ok ()
     && String.length (Dependability_clock.digest first) = 64
     && valid_timestamp (Dependability_clock.journal_timestamp first));

  let second = get (observe ()) in
  check "C5 forward paired observations preserve wall and monotonic order"
    (Dependability_clock.validate_order ~previous:first ~next:second = Ok ());
  check "C6 reversing a production pair is detected as clock rollback"
    (match Dependability_clock.validate_order ~previous:second ~next:first with
     | Error Dependability_clock.Monotonic_clock_rollback
     | Error Dependability_clock.Wall_clock_rollback -> true
     | _ -> false);
  check "C7 an immediate current observation accepts an unexpired receipt"
    (Dependability_clock.validate_current ~now:second first = Ok ());

  check "C8 a strictly later wall receipt kills the wall-rollback mutant"
    (match first_later_wall 256 first with
     | None -> false
     | Some later ->
         Dependability_clock.validate_order ~previous:later ~next:first
         = Error Dependability_clock.Wall_clock_rollback);

  let short = get (observe ~lifetime_ns:1L ()) in
  check "C9 monotonic expiry is absorbing even when wall time remains usable"
    (match first_after_expiry 256 short with
     | None -> false
     | Some now ->
         Dependability_clock.validate_current ~now short
         = Error Dependability_clock.Expired);

  check "C10 source authority binds wall monotonic bounds rollback and expiry"
    (String.length Dependability_clock.source_digest = 64
     && List.for_all
          (fun mutation ->
             Dependability_clock.source_digest
             <> Dependability_clock.For_test.source_digest_with_mutation
                  mutation)
          [ Dependability_clock.For_test.Drop_wall;
            Drop_monotonic; Widen_pair_bound; Widen_lifetime_bound;
            Remove_wall_rollback; Remove_monotonic_rollback;
            Remove_expiry ]);

  if Array.exists (String.equal "--emit-ledger-receipt") Sys.argv then
    Printf.printf "LEDGER_CLOCK_RECEIPT timestamp=%s digest=%s\n"
      (Dependability_clock.journal_timestamp first)
      (Dependability_clock.digest first);

  let self =
    Suite_telemetry.observe ~suite:"test_dependability_clock"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_clock ]);
  exit (Suite_telemetry.exit_code self)
