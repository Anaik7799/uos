type output_format = [ `Text | `Json ]

let rewrite argv flag consumed =
  let tail = Array.sub argv consumed (Array.length argv - consumed) in
  Array.append [| argv.(0); flag |] tail

let verb argv = if Array.length argv > 2 then Some argv.(2) else None

(* Exact help tokens are controls, never task/worker/result data. Inspect raw
   argv before format extraction so a malformed --format cannot swallow help. *)
let help_request argv =
  let present = Array.exists (fun value -> value = "--help" || value = "-h")
    (if Array.length argv > 1 then Array.sub argv 1 (Array.length argv - 1) else [||]) in
  if not present then None
  else
    let context = if Array.length argv < 2 then None else
      match argv.(1) with
      | "plan" | "task" | "job" | "oban" | "workflow" | "temporal"
      | "work" | "docs" | "ui" | "agent" as noun -> Some noun
      | "--claim" | "--complete" | "--task-release" -> Some "task"
      | _ -> None in
    let program = if Array.length argv = 0 then "sa-plan" else argv.(0) in
    Some (Array.of_list ([program; "--help"] @ Option.to_list context))

let normalize argv =
  match help_request argv with
  | Some help -> help
  | None when Array.length argv < 2
     || String.length argv.(1) > 0 && argv.(1).[0] = '-'
    -> argv
  | None ->
    match argv.(1), verb argv with
    | "help", _ -> rewrite argv "--help" 2
    | "version", _ -> rewrite argv "--version" 2
    | "status", _ -> rewrite argv "--status" 2
    | "sync", _ -> rewrite argv "--sync" 2
    | "selftest", _ -> rewrite argv "--selftest" 2
    | "plan", Some "create" -> rewrite argv "--plan-create" 3
    | "plan", Some "show" -> rewrite argv "--plan-show" 3
    | "plan", Some "rename" -> rewrite argv "--plan-rename" 3
    | "plan", Some "register" -> rewrite argv "--register" 3
    | "plan", Some "status" -> rewrite argv "--status" 3
    | "plan", Some "list" -> rewrite argv "--plan" 3
    | "plan", Some "tree" -> rewrite argv "--tree" 3
    | "plan", Some "watch" -> rewrite argv "--watch" 3
    | "task", Some "create" -> rewrite argv "--task-create" 3
    | "task", Some "show" -> rewrite argv "--task-show" 3
    | "task", Some "list" -> rewrite argv "--task-list" 3
    | "task", Some "rename" -> rewrite argv "--task-rename" 3
    | "task", Some "claim" -> rewrite argv "--claim" 3
    | "task", Some "release" -> rewrite argv "--task-release" 3
    | "task", Some "complete" -> rewrite argv "--complete" 3
    | "task", Some "select" -> rewrite argv "--task-select" 3
    | "activity", Some "put" -> rewrite argv "--activity" 3
    | ("job" | "oban"), Some "enqueue" -> rewrite argv "--job-enqueue" 3
    | ("job" | "oban"), Some ("claim" | "run") ->
        rewrite argv "--job-claim" 3
    | ("job" | "oban"), Some "complete" -> rewrite argv "--job-complete" 3
    | ("job" | "oban"), Some "list" -> rewrite argv "--job-list" 3
    | ("workflow" | "temporal"), Some "start" ->
        rewrite argv "--workflow-start" 3
    | ("workflow" | "temporal"), Some "activity" ->
        rewrite argv "--workflow-activity" 3
    | ("workflow" | "temporal"), Some "complete" ->
        rewrite argv "--workflow-complete" 3
    | ("workflow" | "temporal"), Some "fail" ->
        rewrite argv "--workflow-fail" 3
    | ("workflow" | "temporal"), Some "history" ->
        rewrite argv "--workflow-history" 3
    | "work", Some "path" -> rewrite argv "--work-path" 3
    | "work", Some "materialize" -> rewrite argv "--work-materialize" 3
    | "docs", Some "validate" -> rewrite argv "--docs-validate" 3
    | "docs", Some "render" -> rewrite argv "--docs-render" 3
    | "docs", Some "publish" -> rewrite argv "--docs-publish" 3
    | "docs", Some "verify" -> rewrite argv "--docs-verify" 3
    | "ui", Some "tui" -> rewrite argv "--tui" 3
    | "ui", Some "bonsai" -> rewrite argv "--bonsai" 3
    | "ui", Some "jobs" -> rewrite argv "--tui-jobs" 3
    | "ui", Some "workflows" -> rewrite argv "--tui-workflows" 3
    | "ui", Some "snapshot" -> rewrite argv "--snapshot" 3
    | "ui", Some "parity" -> rewrite argv "--c3i-parity" 3
    | "agent", Some "progress" -> rewrite argv "--agent-progress" 3
    | _ -> argv

let extract_format argv =
  let rec loop index acc selected =
    if index >= Array.length argv then Array.of_list (List.rev acc), selected
    else if String.equal argv.(index) "--format" then
      if index + 1 >= Array.length argv then
        Array.of_list (List.rev acc), selected
      else
        let selected =
          if String.equal argv.(index + 1) "json" then `Json else `Text
        in
        loop (index + 2) acc selected
    else loop (index + 1) (argv.(index) :: acc) selected
  in
  loop 0 [] `Text

let required_arguments = function
  | "--help" | "--version" | "--status" | "--sync" | "--selftest"
  | "--register" | "--plan" | "--tree" | "--tui" | "--bonsai"
  | "--tui-jobs" | "--tui-workflows" | "--bonsai-jobs"
  | "--bonsai-workflows" -> Some 0
  | "--plan-show" | "--task-list" | "--workflow-history"
  | "--docs-validate" | "--snapshot" | "--c3i-parity" -> Some 1
  | "--watch" -> Some 0
  | "--plan-create" -> Some 3
  | "--plan-rename" -> Some 2
  | "--task-show" -> Some 2
  | "--task-create" -> Some 4
  | "--task-rename" -> Some 3
  | "--claim" -> Some 1
  | "--task-release" -> Some 4
  | "--complete" -> Some 5
  | "--task-select" -> Some 11
  | "--activity" -> Some 3
  | "--job-enqueue" -> Some 5
  | "--job-claim" -> Some 2
  | "--job-complete" -> Some 5
  | "--job-list" -> Some 0
  | "--workflow-start" -> Some 4
  | "--workflow-activity" -> Some 5
  | "--workflow-complete" | "--workflow-fail" -> Some 2
  | "--work-path" -> Some 2
  | "--work-materialize" -> Some 5
  | "--docs-render" -> Some 2
  | "--docs-publish" -> Some 2
  | "--docs-verify" -> Some 1
  | "--agent-progress" -> Some 1
  | _ -> None

let validate argv =
  if Array.length argv < 2 then Error "missing command"
  else
    match required_arguments argv.(1) with
    | None -> Error ("unknown command: " ^ argv.(1))
    | Some required ->
        let supplied = Array.length argv - 2 in
        if supplied < required then
          Error
            (Printf.sprintf "%s requires at least %d argument(s)" argv.(1)
               required)
        else if (match argv.(1) with
          | "--claim" -> String.trim argv.(2) = "" || argv.(2).[0] = '-'
          | "--job-claim" -> String.trim argv.(3) = "" || argv.(3).[0] = '-'
          | _ -> false) then
          Error "WORKER must be a nonempty identity, not an option"
        else
          let attempt_index =
            match argv.(1) with
            | "--task-release" | "--complete" -> Some 5
            | "--job-complete" -> Some 4
            | _ -> None
          in
          match attempt_index with
          | None -> Ok ()
          | Some index ->
              if supplied <> required then
                Error "fenced completion/release requires exact arguments including original ATTEMPT"
              else
                let text = argv.(index) in
                let decimal = String.length text > 0
                  && String.for_all (fun c -> c >= '0' && c <= '9') text in
                match int_of_string_opt text with
                | Some attempt when decimal && attempt > 0 -> Ok ()
                | _ -> Error "ATTEMPT must be the positive decimal attempt from the original claim"
