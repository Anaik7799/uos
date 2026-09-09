let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let array_equal left right =
  Array.length left = Array.length right
  && Array.for_all2 String.equal left right

let () =
  require "LAW CLI-PLAN-TREE-ALIAS"
    (array_equal
       (Sa_plan_cli.normalize [| "sa-plan"; "plan"; "tree" |])
       [| "sa-plan"; "--tree" |]);
  require "LAW CLI-PLAN-CREATE"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "plan"; "create"; "p1"; "zigvm/docs/manual";
             "Manual" |])
       [| "sa-plan"; "--plan-create"; "p1"; "zigvm/docs/manual";
          "Manual" |]);
  require "LAW CLI-TASK-CREATE"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "task"; "create"; "p1"; "t1";
             "zigvm/docs/manual/write"; "Write" |])
       [| "sa-plan"; "--task-create"; "p1"; "t1";
          "zigvm/docs/manual/write"; "Write" |]);
  require "LAW CLI-TASK-CLAIM-BY-ID"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "task"; "claim"; "worker-1"; "p1"; "t1" |])
       [| "sa-plan"; "--claim"; "worker-1"; "p1"; "t1" |]);
  require "LAW CLI-TASK-RELEASE"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "task"; "release"; "p1"; "t1"; "worker-1" |])
       [| "sa-plan"; "--task-release"; "p1"; "t1"; "worker-1" |]);
  require "LAW CLI-TASK-SELECTION-EVIDENCE"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "task"; "select"; "p1"; "t1"; "codex"; "95";
             "100"; "252"; "90"; "80"; "85"; "95"; "uca:x guard:y" |])
       [| "sa-plan"; "--task-select"; "p1"; "t1"; "codex"; "95";
          "100"; "252"; "90"; "80"; "85"; "95"; "uca:x guard:y" |]);
  require "LAW CLI-JOB-ENQUEUE-ALIAS"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "job"; "enqueue"; "id"; "zigvm/docs/render";
             "q"; "worker"; "{}" |])
       [| "sa-plan"; "--job-enqueue"; "id"; "zigvm/docs/render";
          "q"; "worker"; "{}" |]);
  require "LAW CLI-OBAN-JOB-ALIAS"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "oban"; "claim"; "docs"; "worker" |])
       [| "sa-plan"; "--job-claim"; "docs"; "worker" |]);
  require "LAW CLI-WORKFLOW-ACTIVITY-ALIAS"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "workflow"; "activity"; "wf"; "act";
             "zigvm/docs/render"; "key"; "result" |])
       [| "sa-plan"; "--workflow-activity"; "wf"; "act";
          "zigvm/docs/render"; "key"; "result" |]);
  require "LAW CLI-TEMPORAL-WORKFLOW-ALIAS"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "temporal"; "start"; "wf";
             "zigvm/docs/publish"; "publication"; "{}" |])
       [| "sa-plan"; "--workflow-start"; "wf";
          "zigvm/docs/publish"; "publication"; "{}" |]);
  require "LAW CLI-WORK-PATH"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "work"; "path"; "plans"; "zigvm/docs/manual" |])
       [| "sa-plan"; "--work-path"; "plans"; "zigvm/docs/manual" |]);
  require "LAW CLI-DOCS-RENDER"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "docs"; "render"; "manual.md"; "manual.html" |])
       [| "sa-plan"; "--docs-render"; "manual.md"; "manual.html" |]);
  require "LAW CLI-DOCS-VERIFY-URL"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "docs"; "verify"; "https://example.test/manual" |])
       [| "sa-plan"; "--docs-verify"; "https://example.test/manual" |]);
  require "LAW CLI-UI-JOBS"
    (array_equal
       (Sa_plan_cli.normalize [| "sa-plan"; "ui"; "jobs" |])
       [| "sa-plan"; "--tui-jobs" |]);
  require "LAW CLI-UI-SNAPSHOT"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "ui"; "snapshot"; "work/sa-plan-observation.json" |])
       [| "sa-plan"; "--snapshot"; "work/sa-plan-observation.json" |]);
  require "LAW CLI-UI-C3I-PARITY"
    (array_equal
       (Sa_plan_cli.normalize
          [| "sa-plan"; "ui"; "parity"; "work/tasks/c3i/parity.json" |])
       [| "sa-plan"; "--c3i-parity"; "work/tasks/c3i/parity.json" |]);
  let normalized, format =
    Sa_plan_cli.extract_format
      [| "sa-plan"; "task"; "list"; "p1"; "--format"; "json" |]
  in
  require "LAW CLI-JSON-SELECTION"
    (array_equal normalized [| "sa-plan"; "task"; "list"; "p1" |]
     && format = `Json);
  require "LAW CLI-MISSING-ARGUMENT"
    (Result.is_error
       (Sa_plan_cli.validate
          (Sa_plan_cli.normalize [| "sa-plan"; "plan"; "create" |])));
  require "LAW CLI-CONTEXTUAL-HELP"
    (array_equal
       (Sa_plan_cli.normalize [| "sa-plan"; "help"; "job" |])
       [| "sa-plan"; "--help"; "job" |]);
  require "LAW CLI-LEGACY-STABILITY"
    (array_equal
       (Sa_plan_cli.normalize [| "sa-plan"; "--status" |])
       [| "sa-plan"; "--status" |]);
  require "LAW CLI-UNKNOWN-REJECTION"
    (Result.is_error
       (Sa_plan_cli.validate [| "sa-plan"; "frobnicate" |]))


let () =
  let valid = [
    [| "sa-plan"; "task"; "complete"; "p"; "t"; "w"; "2"; "done" |];
    [| "sa-plan"; "task"; "release"; "p"; "t"; "w"; "2" |];
    [| "sa-plan"; "job"; "complete"; "j"; "w"; "2"; "OK"; "done" |];
    [| "sa-plan"; "oban"; "complete"; "j"; "w"; "2"; "ERROR"; "retry" |]
  ] in
  List.iter (fun args -> require "LAW CLI-ORIGINAL-ATTEMPT-ACCEPTED"
    (Result.is_ok (Sa_plan_cli.validate (Sa_plan_cli.normalize args)))) valid;
  let invalid = [
    [| "sa-plan"; "task"; "complete"; "p"; "t"; "w"; "done" |];
    [| "sa-plan"; "task"; "release"; "p"; "t"; "w" |];
    [| "sa-plan"; "job"; "complete"; "j"; "w"; "OK"; "done" |];
    [| "sa-plan"; "task"; "complete"; "p"; "t"; "w"; "0"; "done" |];
    [| "sa-plan"; "task"; "complete"; "p"; "t"; "w"; "-1"; "done" |];
    [| "sa-plan"; "task"; "complete"; "p"; "t"; "w"; "999999999999999999999"; "done" |];
    [| "sa-plan"; "task"; "release"; "p"; "t"; "w"; "latest" |];
    [| "sa-plan"; "job"; "complete"; "j"; "w"; "0x2"; "OK"; "done" |];
    [| "sa-plan"; "job"; "complete"; "j"; "w"; "2"; "OK"; "done"; "extra" |];
    [| "sa-plan"; "--complete"; "p"; "t"; "w"; "done" |]
  ] in
  List.iter (fun args -> require "LAW CLI-MISSING-OR-MALFORMED-ATTEMPT-REJECTED"
    (Result.is_error (Sa_plan_cli.validate (Sa_plan_cli.normalize args)))) invalid

let () =
  let requests = [
    [| "sa-plan"; "task"; "claim"; "--help" |];
    [| "sa-plan"; "task"; "claim"; "worker"; "-h" |];
    [| "sa-plan"; "--claim"; "--help" |];
    [| "sa-plan"; "task"; "claim"; "worker"; "--format"; "--help" |];
    [| "sa-plan"; "job"; "claim"; "queue"; "--help" |];
    [| "sa-plan"; "task"; "complete"; "p"; "t"; "w"; "1"; "--help" |]
  ] in
  List.iter (fun args ->
    let normalized = Sa_plan_cli.normalize args in
    require "LAW CLI-HELP-CANNOT-NORMALIZE-TO-EFFECT"
      (Array.length normalized >= 2 && normalized.(1) = "--help"
       && Result.is_ok (Sa_plan_cli.validate normalized))) requests;
  List.iter (fun worker ->
    require "LAW CLI-OPTION-IS-NOT-CLAIM-WORKER"
      (Result.is_error (Sa_plan_cli.validate [|"sa-plan";"--claim";worker|])))
    ["--help";"-h";"--version";"--unknown";"";" "];
  require "LAW CLI-ORDINARY-HELP-TEXT-PRESERVED"
    (array_equal
      (Sa_plan_cli.normalize [|"sa-plan";"task";"create";"p";"t";"n";"Explain --help usage"|])
      [|"sa-plan";"--task-create";"p";"t";"n";"Explain --help usage"|])

let () =
  List.iter (fun worker ->
    require "LAW CLI-JOB-OPTION-IS-NOT-CLAIM-WORKER"
      (Result.is_error (Sa_plan_cli.validate [|"sa-plan";"--job-claim";"q";worker|])))
    ["--help";"-h";"--version";"--unknown";"";" "];
  List.iter (fun (noun, verb) ->
    List.iter (fun worker -> require "LAW CLI-JOB-ALIASES-VALIDATE-WORKER"
      (Result.is_error (Sa_plan_cli.validate
        (Sa_plan_cli.normalize [|"sa-plan";noun;verb;"q";worker|]))))
      ["--version";"--unknown";"";" "])
    ["job","claim";"job","run";"oban","claim";"oban","run"]
