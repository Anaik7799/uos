(** Test-only native observations. Assertions and expected outcomes are in
    Gleam. This executable is not a dispatcher or production fixture loader. *)
module Store = Sa_plan.Store
let ( let* ) = Result.bind
let now_ns = 1_000_000_000L

let observe_counts store rejected =
  let* plan = Store.find_plan store ~id_or_name:Migration_plan.plan_id in
  let* jobs = Store.list_jobs store ~queue:None in
  let* workflows = Store.list_workflows store in
  let workflow_fields = match workflows with
    | [w] -> ["workflow_kind", `String w.kind; "workflow_input", `String w.input;
               "workflow_history", `List (List.map (fun (e : Store.workflow_event) ->
                 `Assoc ["sequence", `Int e.sequence; "kind", `String e.kind;
                         "payload", `String e.payload;
                         "occurred_at_ns", `String (Int64.to_string e.occurred_at_ns)]) w.events)]
    | _ -> [] in
  let job_fields = match jobs with
    | [j] -> ["job_name", `String j.name; "job_worker", `String j.worker;
              "job_args", `String j.args; "job_max_attempts", `Int j.max_attempts]
    | _ -> [] in
  Ok (`Assoc (["plan_count", `Int (Option.fold ~none:0 ~some:(fun _ -> 1) plan);
              "job_count", `Int (List.length jobs);
              "workflow_count", `Int (List.length workflows);
              "rejected", `Bool rejected] @ workflow_fields @ job_fields))

let scenario store = function
  | "rollback" ->
      let result = Store.with_transaction store (fun () ->
        let* _ = Migration_plan.materialize store ~now_ns in
        Error "injected outer transaction failure") in
      observe_counts store (Result.is_error result)
  | "workflow-conflict" ->
      let* () = Store.start_workflow_with_input store ~id:Migration_plan.workflow_id
        ~name:Migration_plan.workflow_id ~kind:"conflicting-kind" ~input:"unchanged-sentinel" ~now_ns in
      let result = Migration_plan.materialize store ~now_ns in
      observe_counts store (Result.is_error result)
  | "job-conflict" ->
      let* _ = Store.enqueue_job store ~id:(Migration_plan.plan_id ^ "/jobs/OGL.00")
        ~name:"tests/conflicting-job" ~queue:Migration_plan.queue
        ~worker:"UnchangedSentinel" ~args:"unchanged-sentinel" ~max_attempts:1 ~now_ns in
      let result = Migration_plan.materialize store ~now_ns in
      observe_counts store (Result.is_error result)
  | "dependency-claims" ->
      let* _ = Migration_plan.materialize store ~now_ns in
      let dependent = Store.claim_task store ~plan_id:Migration_plan.plan_id
        ~task_id:"OGL.01" ~worker:"gleam-test-observer" ~now_ns ~lease_ns:1_000_000L in
      let ready = Store.claim_task store ~plan_id:Migration_plan.plan_id
        ~task_id:"OGL.00" ~worker:"gleam-test-observer" ~now_ns ~lease_ns:1_000_000L in
      let* jobs = Store.list_jobs store ~queue:None in
      Ok (`Assoc ["dependent_refused", `Bool (Result.is_error dependent);
                  "root_claimed", `Bool (Result.is_ok ready);
                  "job_attempts", `Int (List.fold_left (fun n (j : Store.job_view) -> n + j.attempt) 0 jobs)])
  | _ -> Error "unknown test observation"

let () =
  try
    let database_path = match Array.to_list Sys.argv with
      | [_; path] when String.starts_with ~prefix:"/tmp/uos-sa-plan-tests." path
                      && not (List.mem ".." (String.split_on_char '/' path)) -> path
      | _ -> failwith "test-only temporary database path required" in
    Unix.mkdir (Filename.dirname database_path) 0o700;
    let header = really_input_string stdin 4 in
    let size = ref 0 in
    String.iter (fun c -> size := (!size lsl 8) lor Char.code c) header;
    if !size < 1 || !size > 4096 then failwith "invalid test request size";
    let request = really_input_string stdin !size |> Yojson.Basic.from_string in
    let open Yojson.Basic.Util in
    let id = member "id" request and op = member "operation" request in
    let result =
      let* store = Store.open_db database_path in
      Fun.protect ~finally:(fun () -> Store.close store)
        (fun () -> scenario store (to_string op)) in
    let body = match result with
      | Ok value -> "result", value
      | Error message -> "error", `Assoc ["code", `String "fixture_error"; "message", `String message] in
    let response = `Assoc ["version", `Int 1; "id", id; "operation", op; body]
      |> Yojson.Basic.to_string in
    let n = String.length response in
    List.iter (fun shift -> output_byte stdout ((n lsr shift) land 255)) [24;16;8;0];
    output_string stdout response; flush stdout
  with exn -> prerr_endline (Printexc.to_string exn); exit 2
