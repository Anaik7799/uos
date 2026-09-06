#use "topfind";;
#require "core,core_unix,digestif.ocaml,sqlite3,yojson,bos.setup";;
#directory "/home/an/NAS-setup/uos/engines/hermes/_build/default/modules/sa_plan/.sa_plan.objs/byte";;
#directory "/home/an/NAS-setup/uos/engines/hermes/_build/default/modules/sa_plan";;
#load "sa_plan.cma";;

(* Bounded manual tracking. Reserved programme rows are only inspected. *)
module S = Sa_plan.Store
open Core
open Yojson.Basic.Util
module Runtime_sys = Sys
module Sys = struct let argv = Runtime_sys.get_argv () end

let manifest_digest = "b706f9a99dfaf6018772b2a819084ea3373a3ee720ed774b57e7f92792d8ee02"
let fail s = Error s
let ok = function Ok x -> x | Error e -> failwith e
let now () = Core.Time_ns.now () |> Core.Time_ns.to_int_ns_since_epoch |> Int64.of_int
let json = Yojson.Basic.to_string
let member key = function
  | `Assoc fields -> Option.value (List.Assoc.find fields ~equal:String.equal key) ~default:`Null
  | _ -> `Null
let str k x = match member k x with `String s when not (String.is_empty s) -> Ok s | _ -> fail ("missing " ^ k)
let obj k x = match member k x with `Assoc xs -> Ok xs | _ -> fail ("missing object " ^ k)
let passed x = match member "status" x with `String "PASSED" -> Ok () | _ -> fail "receipt status must be PASSED"
let lower = String.lowercase
let valid x = not (String.is_empty x) && String.for_all x ~f:(function 'a'..'z' | '0'..'9' | '-' -> true | _ -> false)
let sha256 x =
  String.length x = 64
  && String.for_all x ~f:(function
       | '0' .. '9' | 'a' .. 'f' -> true
       | _ -> false)
let evidence_size_ceiling = 1_048_576
let parse_object bytes =
  if String.length bytes > evidence_size_ceiling then fail "JSON exceeds its read quota"
  else
    try
      match Yojson.Basic.from_string bytes with
      | `Assoc _ as value -> Ok value
      | _ -> fail "JSON must be an object"
    with _ -> fail "JSON must be valid execution JSON"

let allowed_relative_roots = [ "artifacts"; "receipts" ]

let no_traversal components =
  List.for_all components ~f:(fun component ->
    not (String.is_empty component)
    && not (String.equal component ".")
    && not (String.equal component ".."))

let split_path path = String.split path ~on:'/'

let strict_evidence_path path =
  let components = split_path path in
  match components with
  | "" :: "tmp" :: filename :: [] ->
      no_traversal [ filename ]
      && String.is_prefix filename ~prefix:"uos-sa-plan-swarm-"
  | _ ->
      (match components with
       | root :: _ ->
           List.mem allowed_relative_roots root ~equal:String.equal
           && no_traversal components
       | [] -> false)

let allowed_extension kind path =
  if String.equal kind "receipt" then String.is_suffix path ~suffix:".json"
  else
    List.exists [ ".json"; ".log"; ".txt"; ".xml" ] ~f:(fun suffix ->
      String.is_suffix path ~suffix)

let lstat path =
  try Ok (Core_unix.lstat path)
  with Core_unix.Unix_error (_, _, _) -> fail "evidence path cannot be statted"

let validate_file_stats ~quota stat =
  if not (Poly.equal stat.Core_unix.st_kind Core_unix.S_REG) then
    fail "evidence must be a regular file"
  else if stat.Core_unix.st_uid <> Core_unix.getuid () then
    fail "evidence file owner differs from current operator"
  else if
    Int64.(stat.Core_unix.st_size < 0L || stat.Core_unix.st_size > of_int quota)
  then fail "evidence file exceeds its hash quota"
  else Ok stat

let rec validate_components prefix components =
  match components with
  | [] -> fail "evidence path has no final component"
  | component :: rest ->
      let current = Filename.concat prefix component in
      Result.bind (lstat current) ~f:(fun stat ->
        if Poly.equal stat.Core_unix.st_kind Core_unix.S_LNK then
          fail "evidence symlinks are forbidden"
        else
          match rest with
          | [] ->
              validate_file_stats ~quota:evidence_size_ceiling stat
          | _ ->
              if not (Poly.equal stat.Core_unix.st_kind Core_unix.S_DIR) then
                fail "evidence path component is not a directory"
              else validate_components current rest)

let validate_evidence_path path =
  if not (strict_evidence_path path) then
    fail "evidence path is outside the canonical allowlist"
  else
    match split_path path with
    | "" :: "tmp" :: filename :: [] ->
        validate_components "/tmp" [ filename ]
    | components ->
        validate_components "." components

let same_evidence_file before after =
  Poly.equal before.Core_unix.st_dev after.Core_unix.st_dev
  && Poly.equal before.Core_unix.st_ino after.Core_unix.st_ino
  && Int64.equal before.Core_unix.st_size after.Core_unix.st_size
  && Int.equal before.Core_unix.st_uid after.Core_unix.st_uid
  && Poly.equal before.Core_unix.st_kind after.Core_unix.st_kind
  && Float.equal before.Core_unix.st_mtime after.Core_unix.st_mtime
  && Float.equal before.Core_unix.st_ctime after.Core_unix.st_ctime

let read_bounded_descriptor fd ~quota =
  let buffer = Bytes.create 65_536 in
  let contents = Buffer.create (min quota 65_536) in
  let rec loop context bytes_read =
    (* At most quota bytes plus one overflow sentinel are ever read. *)
    let count = Core_unix.read fd ~buf:buffer ~len:(min 65_536 (quota - bytes_read + 1)) in
    if count = 0 then Ok (Buffer.contents contents, Digestif.SHA256.get context |> Digestif.SHA256.to_hex)
    else if bytes_read > quota - count then fail "evidence exceeded its hash quota"
    else (
      Buffer.add_subbytes contents buffer ~pos:0 ~len:count;
      loop
        (Digestif.SHA256.feed_bytes context ~off:0 ~len:count buffer)
        (bytes_read + count))
  in
  loop (Digestif.SHA256.init ()) 0

let descriptor_bytes ~validate path =
  Result.bind (validate path) ~f:(fun before ->
    try
      let fd =
        Core_unix.openfile path ~mode:[ Core_unix.O_RDONLY; Core_unix.O_CLOEXEC; Core_unix.O_NONBLOCK ]
      in
      Fun.protect ~finally:(fun () -> Core_unix.close fd) (fun () ->
        let opened = Core_unix.fstat fd in
        Result.bind (validate_file_stats ~quota:evidence_size_ceiling opened)
          ~f:(fun opened ->
            if not (same_evidence_file before opened) then
              fail "evidence path changed before descriptor validation"
            else
              Result.bind (read_bounded_descriptor fd ~quota:evidence_size_ceiling)
                ~f:(fun checked ->
                  let closed_view = Core_unix.fstat fd in
                  Result.bind (validate path) ~f:(fun after ->
                    if same_evidence_file opened closed_view
                       && same_evidence_file opened after
                    then Ok checked
                    else fail "evidence changed while being hashed"))))
    with Core_unix.Unix_error (_, _, _) -> fail "evidence descriptor could not be opened")

let descriptor_sha256 ~validate path =
  Result.map (descriptor_bytes ~validate path) ~f:snd
let bounded_sha256 path = descriptor_sha256 ~validate:validate_evidence_path path

type external_dependency = {
  plan_id : string;
  task_id : string;
  required_state : string;
  candidate_bound_receipt_required : bool;
}

type task = {
  id : string;
  deps : string list;
  stream : string;
  external_deps : external_dependency list;
}
type manifest = { plan_id:string; programme:string; tasks:task list }
type attempt = { manifest:manifest; task:task; attempt_id:string; owner:string; preflight:string; change_id:string; commit_id:string; plan_id:string; task_id:string; job_id:string; workflow_id:string; queue:string; mapping_id:string }
type started = { owner:string; lease_id:string; fence:int64; expires_at_ns:int64 }

let find_task m id = match List.find m.tasks ~f:(fun t -> String.equal t.id id) with Some t -> Ok t | None -> fail ("task absent from manifest: " ^ id)
let manifest_path =
  "governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json"

let validate_manifest_path path =
  if not (String.equal path manifest_path) then
    fail "manifest path is not the immutable programme manifest"
  else
    validate_components "."
      [ "governance"; "planning";
        "20260906-1655-uos-sa-plan-execution-manifest.json" ]

let load_manifest path =
  Result.bind (descriptor_bytes ~validate:validate_manifest_path path) ~f:(fun (bytes, digest) ->
  if not (String.equal digest manifest_digest) then fail "immutable manifest digest mismatch" else
  Result.bind (parse_object bytes) ~f:(fun x -> try
    let plan_id=member "plan_id" x |> to_string in
    let programme=plan_id^"/workflow" and jobs=member "jobs" x |> to_list in
    let job_for id =
      List.find jobs ~f:(fun job -> String.equal (member "task_id" job |> to_string) id)
    in
    let stream id =
      Option.value_map (job_for id) ~default:programme
        ~f:(fun job -> member "workflow_id" job |> to_string)
    in
    let external_deps id =
      match job_for id with
      | None -> []
      | Some job ->
          member "external_dependencies" job |> to_list
          |> List.map ~f:(fun dependency ->
            { plan_id = member "plan_id" dependency |> to_string;
              task_id = member "task_id" dependency |> to_string;
              required_state = member "required_state" dependency |> to_string;
              candidate_bound_receipt_required =
                member "candidate_bound_receipt_required" dependency |> to_bool })
    in
    let tasks = member "tasks" x |> to_list |> List.map ~f:(fun row ->
      let id = member "id" row |> to_string in
      { id;
        deps = member "depends_on" row |> to_list |> List.map ~f:to_string;
        stream = stream id;
        external_deps = external_deps id })
    in
    if List.length tasks<>71 then fail "manifest task count mismatch" else Ok {plan_id;programme;tasks}
  with _ -> fail "cannot load manifest: invalid manifest structure"))
let manifest_for_test () =
  ok (load_manifest manifest_path)
let support (m:manifest) task attempt = m.plan_id^"/manual/"^lower task^"/"^attempt

let receipt_run ~owner ~attempt receipt =
  Result.bind (obj "run" receipt) ~f:(fun run ->
    Result.bind (str "owner" (`Assoc run)) ~f:(fun receipt_owner ->
      Result.bind (str "attempt" (`Assoc run)) ~f:(fun receipt_attempt ->
        if String.equal receipt_owner owner && String.equal receipt_attempt attempt
        then Ok ()
        else fail "receipt run owner or attempt differs from command")))

let validate_receipt_evidence bytes =
  Result.bind (parse_object bytes) ~f:(fun evidence ->
    Result.bind (str "schema" evidence) ~f:(fun schema ->
      if not
           (List.mem
              [ "uos.manual-execution-receipt.v1";
                "uos.manual-execution-evidence.v1" ]
              schema ~equal:String.equal)
      then fail "receipt evidence has an unsupported schema"
      else
        Result.bind (str "task_id" evidence) ~f:(fun _ ->
          Result.bind (obj "candidate" evidence) ~f:(fun candidate ->
            Result.bind (str "change_id" (`Assoc candidate)) ~f:(fun _ ->
              Result.bind (str "commit_id" (`Assoc candidate)) ~f:(fun _ ->
                match member "status" evidence with
                | `String ("PASSED" | "EXPECTED_FAILURE") -> Ok ()
                | _ -> fail "receipt evidence has no accepted status"))))))

let verify_evidence_item item =
  match item with
  | `Assoc _ ->
    Result.bind (str "kind" item) ~f:(fun kind ->
      if not (List.mem [ "receipt"; "artifact" ] kind ~equal:String.equal)
      then fail "evidence kind must be receipt or artifact"
      else Result.bind (str "path" item) ~f:(fun path ->
        Result.bind (str "sha256" item) ~f:(fun expected ->
          if not (sha256 expected) then fail "evidence sha256 must be lowercase hexadecimal"
          else if not (allowed_extension kind path) then
            fail "evidence extension is not allowed for its kind"
          else Result.bind (descriptor_bytes ~validate:validate_evidence_path path) ~f:(fun (bytes, observed) ->
            if String.equal observed expected then
              if String.equal kind "receipt" then
                validate_receipt_evidence bytes
              else Ok ()
            else fail "evidence digest does not match local file"))))
  | _ -> fail "evidence item must be an object"

let verify_evidence receipt =
  match member "evidence" receipt with
  | `List (_ :: _ as items) ->
      List.fold items ~init:(Ok ()) ~f:(fun prior item ->
        Result.bind prior ~f:(fun () -> verify_evidence_item item))
  | _ -> fail "receipt needs non-empty local receipt or artifact evidence"

let decode m ~task_id ~attempt ~owner receipt =
  if not(valid attempt) then fail "attempt must use lowercase letters, digits, and hyphens" else if String.is_empty owner then fail "owner must be non-empty" else
  Result.bind(find_task m task_id)~f:(fun task ->
  Result.bind(str "schema" receipt)~f:(fun schema -> if not(String.equal schema "uos.manual-execution-receipt.v1") then fail "unsupported receipt schema" else
  Result.bind(str "manifest_sha256" receipt)~f:(fun d -> if not(String.equal d manifest_digest) then fail "receipt manifest mismatch" else
  Result.bind(str "task_id" receipt)~f:(fun actual_task -> if not(String.equal actual_task task_id) then fail "receipt task mismatch" else
  Result.bind(str "attempt" receipt)~f:(fun actual_attempt -> if not(String.equal actual_attempt attempt) then fail "receipt attempt mismatch" else
  Result.bind(obj "candidate" receipt)~f:(fun candidate ->
  Result.bind(str "change_id" (`Assoc candidate))~f:(fun change_id ->
  Result.bind(str "commit_id" (`Assoc candidate))~f:(fun commit_id ->
  Result.bind(receipt_run ~owner ~attempt receipt)~f:(fun () ->
  Result.bind(verify_evidence receipt)~f:(fun () ->
    let plan_id=support m task_id attempt in Ok {manifest=m;task;attempt_id=attempt;owner;preflight=json receipt;change_id;commit_id;plan_id;task_id="EXECUTE";job_id=plan_id^"/job";workflow_id=plan_id^"/workflow";queue="uos-manual-"^lower task_id^"-"^attempt;mapping_id="bridge/sa-plan/"^plan_id}))))))))))

let dependency_receipts task receipt =
  Result.bind(obj "dependencies" receipt)~f:(fun states ->
    if List.for_all task.deps ~f:(fun id -> match List.Assoc.find states ~equal:String.equal id with Some(`String "PASSED")->true|_->false)
    then Ok() else fail "missing or nonpassing linked dependency receipt")

let external_receipts attempt _receipt =
  if List.is_empty attempt.task.external_deps then Ok ()
  else
    fail
      "UNSUPPORTED_EXTERNAL_STORE: external dependencies need an admitted federation adapter"

let master_deps store attempt receipt =
  let check_local id =
    Result.bind
      (S.find_task store ~plan_id:attempt.manifest.plan_id ~id_or_name:id)
      ~f:(function
        | Some task when String.equal task.state "completed" -> Ok ()
        | Some _ -> fail ("master dependency not complete: " ^ id)
        | None -> fail ("master dependency missing: " ^ id))
  in
  let local =
    List.fold attempt.task.deps ~init:(Ok ()) ~f:(fun prior id ->
      Result.bind prior ~f:(fun () -> check_local id))
  in
  Result.bind local ~f:(fun () ->
    external_receipts attempt receipt)

let master_task_lease store attempt ~now_ns =
  Result.bind (S.list_task_observations store ~plan_id:attempt.manifest.plan_id)
    ~f:(fun observations ->
      match List.find observations ~f:(fun observation ->
        String.equal observation.task.id attempt.task.id) with
      | Some observation
        when String.equal observation.task.state "executing"
             && Option.equal String.equal observation.task.worker (Some attempt.owner)
             && Option.value_map observation.lease_until_ns ~default:false
                  ~f:(fun expires_at_ns -> Int64.(expires_at_ns >= now_ns)) ->
          Ok ()
      | Some _ ->
          fail
            "manual support needs an independently claimed, unexpired master task lease with the same owner"
      | None -> fail "master task is missing")

let recheck_start store attempt ~now_ns =
  Result.bind (parse_object attempt.preflight) ~f:(fun receipt ->
  Result.bind (decode attempt.manifest ~task_id:attempt.task.id
    ~attempt:attempt.attempt_id ~owner:attempt.owner receipt) ~f:(fun _ ->
    Result.bind (dependency_receipts attempt.task receipt) ~f:(fun () ->
      Result.bind (master_deps store attempt receipt) ~f:(fun () ->
        master_task_lease store attempt ~now_ns))))

let input (a:attempt) = json(`Assoc[
  "schema",`String"uos.manual-execution-support.v1";"master_plan",`String a.manifest.plan_id;"master_task",`String a.task.id;"manifest_sha256",`String manifest_digest;"attempt",`String a.attempt_id;"owner",`String a.owner;
  "candidate",`Assoc["change_id",`String a.change_id;"commit_id",`String a.commit_id];
  "preflight",Yojson.Basic.from_string a.preflight;"implementation_credit",`Bool false;"system_admission_granted",`Bool false])
let bridge (a:attempt) now_ns =
  S.
    { domain = Sa_plan;
      ooda_slice_id = a.plan_id;
      idempotency_key = a.plan_id ^ ":" ^ manifest_digest;
      source_fingerprint = a.change_id ^ ":" ^ a.commit_id;
      dependency_snapshot =
        json (`List (List.map a.task.deps ~f:(fun dependency -> `String dependency)));
      prompt_ledger_hash = "not-prompt-ledger/manual-execution";
      safety_packet_hash = "not-safety-packet/manual-execution";
      formal_evidence_hash = "not-formal/manual-execution";
      sa_plan_id = Some a.plan_id;
      sa_task_id = Some a.task_id;
      lifecycle_state = "manual-supervised";
      created_at_ns = now_ns }
let activity (a:attempt) stage receipt = json(`Assoc["schema",`String"uos.manual-execution-activity.v1";"master_plan",`String a.manifest.plan_id;"master_task",`String a.task.id;"attempt",`String a.attempt_id;"stage",`String stage;"candidate",`Assoc["change_id",`String a.change_id;"commit_id",`String a.commit_id];"receipt",receipt;"implementation_credit",`Bool false;"system_admission_granted",`Bool false])
let complete_activity store wf (a:attempt) stage receipt now_ns =
  let id="manual-"^lower a.task.id^"-"^a.attempt_id^"-"^stage in
  S.complete_workflow_activity store ~workflow_id_or_name:wf ~id ~name:(wf^"/activity/manual/"^lower a.task.id^"/"^a.attempt_id^"/"^stage) ~idempotency_key:(manifest_digest^":"^id) ~result:(activity a stage receipt) ~now_ns
let master_activities store (a:attempt) stage receipt now_ns =
  Result.bind(complete_activity store a.manifest.programme a stage receipt now_ns)~f:(fun _ ->
    if String.equal a.task.stream a.manifest.programme then Ok() else Result.map(complete_activity store a.task.stream a stage receipt now_ns)~f:(fun _->()))

let register_attempt store m ~task_id ~attempt ~owner ~preflight ~now_ns =
  Result.bind (parse_object preflight) ~f:(fun receipt ->
  Result.bind (decode m ~task_id ~attempt ~owner receipt) ~f:(fun a ->
    Result.bind (passed receipt) ~f:(fun () ->
    Result.bind (dependency_receipts a.task receipt) ~f:(fun () ->
      Result.bind (master_deps store a receipt) ~f:(fun () ->
        S.with_transaction store (fun () ->
          Result.bind (S.find_plan store ~id_or_name:a.plan_id) ~f:(function
            | Some p ->
                if not (String.equal p.name a.plan_id) then fail "support plan identity drift"
                else Result.bind (S.list_workflows store) ~f:(fun ws ->
                  match List.find ws ~f:(fun w -> String.equal w.id a.workflow_id) with
                  | Some w when String.equal w.input (input a) -> Ok a
                  | Some _ -> fail "attempt replay conflicts with candidate or receipt"
                  | None -> fail "support plan incomplete")
            | None ->
                Result.bind (S.create_plan store ~id:a.plan_id ~name:a.plan_id
                  ~title:("Manual support " ^ a.task.id ^ " " ^ a.attempt_id) ~now_ns) ~f:(fun () ->
                Result.bind (S.create_task store ~plan_id:a.plan_id ~id:a.task_id
                  ~name:(a.plan_id ^ "/task/execute") ~title:("Bounded manual support for " ^ a.task.id)
                  ~parent_id:None ~dependencies:[] ~priority:100 ~now_ns) ~f:(fun () ->
                Result.bind (S.start_workflow_with_input store ~id:a.workflow_id ~name:a.workflow_id
                  ~kind:"uos.manual-supervised-execution.v1" ~input:(input a) ~now_ns) ~f:(fun () ->
                Result.bind (S.enqueue_job store ~id:a.job_id ~name:(a.plan_id ^ "/job/execution")
                  ~queue:a.queue ~worker:a.owner ~args:(input a) ~max_attempts:20 ~now_ns) ~f:(fun _ ->
                Result.map (S.ensure_bridge_mapping store (bridge a now_ns)) ~f:(fun _ -> a))))))))))))

let job store a = Result.bind(S.list_jobs store ~queue:(Some a.queue))~f:(fun js -> match List.find js ~f:(fun j->String.equal j.id a.job_id) with Some j->Ok j|None->fail "manual support job missing")
let current_lease store a ~owner ~lease_id ~now_ns = Result.bind(S.find_bridge_lease store ~mapping_id:a.mapping_id)~f:(function
  |Some l when String.equal l.owner owner&&String.equal l.lease_id lease_id&&Int64.(l.expires_at_ns>=now_ns)->Ok l
  |Some l when Int64.(l.expires_at_ns<now_ns)->fail "manual bridge lease expired"|Some _->fail "manual bridge lease owner or id stale"|None->fail "manual bridge lease missing")

let minimum_lease_ns = 1_320_000_000_000L

let start_attempt store a ~now_ns ~lease_ns =
  if Int64.(lease_ns < minimum_lease_ns) then
    fail "manual lease must be at least 1320 seconds"
  else
  S.with_transaction store (fun () ->
  Result.bind (recheck_start store a ~now_ns) ~f:(fun () ->
  Result.bind(S.find_bridge_lease store ~mapping_id:a.mapping_id)~f:(fun prior ->
    let lease=match prior with Some l when Int64.(l.expires_at_ns>=now_ns)->if String.equal l.owner a.owner then Ok l else fail "live attempt belongs to another owner"|_->S.claim_bridge_lease store ~mapping_id:a.mapping_id ~owner:a.owner ~lease_id:(a.plan_id^":lease:"^Int64.to_string now_ns) ~now_ns ~lease_ns in
  Result.bind lease~f:(fun lease -> Result.bind(job store a)~f:(fun old ->
    let claimed=match old.state,old.lease_owner,old.lease_until_ns with S.Job_executing,Some o,Some e when String.equal o a.owner&&Int64.(e>=now_ns)->Ok old|_->Result.bind(S.claim_job store ~queue:a.queue ~worker:a.owner ~now_ns ~lease_ns)~f:(function Some j when String.equal j.id a.job_id->Ok j|Some _->fail "unexpected job in unique queue"|None->fail "manual job not claimable") in
  Result.bind claimed~f:(fun j -> if not(j.attempt > 0
    && Int64.equal (Int64.of_int j.attempt) lease.fencing_token
    && Option.equal String.equal j.lease_owner(Some a.owner)
    && Option.value_map j.lease_until_ns ~default:false ~f:(fun e->Int64.(e>=now_ns)))
    then fail "manual job owner, attempt, fence, or expiry check failed" else
  Result.bind(S.record_bridge_command store ~mapping_id:a.mapping_id ~command_id:"start" ~request_hash:(a.preflight^":start") ~result:(activity a "start"(Yojson.Basic.from_string a.preflight)) ~recorded_at_ns:now_ns)~f:(fun _ ->
  Result.bind(complete_activity store a.workflow_id a "start"(Yojson.Basic.from_string a.preflight) now_ns)~f:(fun _ ->
  Result.map(master_activities store a "start"(Yojson.Basic.from_string a.preflight) now_ns)~f:(fun ()->{owner=a.owner;lease_id=lease.lease_id;fence=lease.fencing_token;expires_at_ns=lease.expires_at_ns})))))))))

let valid_stage s=List.mem["specification";"red-test";"implementation";"verification";"review";"journal"]s~equal:String.equal

let stage_status stage receipt =
  match stage, member "status" receipt with
  | "red-test", (`String "EXPECTED_FAILURE" | `String "PASSED") -> Ok ()
  | _, `String "PASSED" -> Ok ()
  | "red-test", _ -> fail "red-test receipt must report EXPECTED_FAILURE or PASSED"
  | _ -> fail "non-red-test receipt status must be PASSED"

let bound a stage raw =
  Result.bind (parse_object raw) ~f:(fun receipt ->
  if not (valid_stage stage) then fail "invalid manual activity stage"
  else Result.bind
    (decode a.manifest ~task_id:a.task.id ~attempt:a.attempt_id ~owner:a.owner receipt)
    ~f:(fun other ->
      if not (String.equal other.change_id a.change_id
        && String.equal other.commit_id a.commit_id)
      then fail "receipt candidate differs from registered attempt"
      else Result.bind (str "stage" receipt) ~f:(fun receipt_stage ->
        if String.equal receipt_stage stage then stage_status stage receipt
        else fail "receipt stage differs from command")))

let current_job store attempt ~owner ~fence ~now_ns =
  Result.bind (job store attempt) ~f:(fun job ->
    if job.attempt > 0
       && Int64.equal (Int64.of_int job.attempt) fence
       && Poly.equal job.state S.Job_executing
       && Option.equal String.equal job.lease_owner (Some owner)
       && Option.value_map job.lease_until_ns ~default:false
            ~f:(fun expires_at_ns -> Int64.(expires_at_ns >= now_ns))
    then Ok job
    else fail "manual job owner, attempt, fence, or expiry check failed")

let required_stages = [ "red-test"; "implementation"; "verification"; "review" ]

let required_stage_records store attempt =
  List.fold required_stages ~init:(Ok ()) ~f:(fun prior stage ->
    Result.bind prior ~f:(fun () ->
      Result.bind
        (S.find_bridge_command store ~mapping_id:attempt.mapping_id
           ~command_id:("record:" ^ stage))
        ~f:(function
          | Some _ -> Ok ()
          | None -> fail ("required stage receipt is missing: " ^ stage))))
let record_attempt store a ~owner ~lease_id ~stage ~receipt ~now_ns =
  Result.bind (bound a stage receipt) ~f:(fun () ->
    S.with_transaction store (fun () ->
      Result.bind (current_lease store a ~owner ~lease_id ~now_ns) ~f:(fun lease ->
        Result.bind (current_job store a ~owner ~fence:lease.fencing_token ~now_ns)
          ~f:(fun _ ->
            Result.bind
              (S.record_bridge_command store ~mapping_id:a.mapping_id
                 ~command_id:("record:" ^ stage) ~request_hash:receipt
                 ~result:(activity a stage (Yojson.Basic.from_string receipt))
                 ~recorded_at_ns:now_ns)
              ~f:(fun _ ->
                Result.bind
                  (complete_activity store a.workflow_id a stage
                     (Yojson.Basic.from_string receipt) now_ns)
                  ~f:(fun _ ->
                    master_activities store a stage
                      (Yojson.Basic.from_string receipt) now_ns))))))

let finish_attempt store a ~owner ~lease_id ~receipt ~now_ns =
  Result.bind (parse_object receipt) ~f:(fun r ->
  Result.bind (decode a.manifest ~task_id:a.task.id ~attempt:a.attempt_id ~owner:a.owner r) ~f:(fun other ->
    if not (String.equal other.change_id a.change_id && String.equal other.commit_id a.commit_id)
    then fail "receipt candidate differs from registered attempt"
    else Result.bind (str "stage" r) ~f:(fun stage ->
      if not (String.equal stage "finish") then fail "finish needs finish receipt"
      else Result.bind (passed r) ~f:(fun () ->
        Result.bind (verify_evidence r) ~f:(fun () ->
          S.with_transaction store (fun () ->
              Result.bind (current_lease store a ~owner ~lease_id ~now_ns) ~f:(fun lease ->
                Result.bind (current_job store a ~owner ~fence:lease.fencing_token ~now_ns)
                  ~f:(fun _ ->
                  Result.bind (required_stage_records store a) ~f:(fun () ->
                  Result.bind (S.record_bridge_command store ~mapping_id:a.mapping_id ~command_id:"finish"
                    ~request_hash:receipt ~result:(activity a "finish" r) ~recorded_at_ns:now_ns) ~f:(fun _ ->
                    Result.bind (S.complete_bridge_task store ~mapping_id:a.mapping_id ~owner ~lease_id
                      ~fencing_token:lease.fencing_token ~result:receipt ~now_ns) ~f:(fun () ->
                    Result.bind (S.complete_job store ~id_or_name:a.job_id ~worker:owner ~outcome:(`Ok receipt) ~now_ns) ~f:(fun done_job ->
                    Result.bind (complete_activity store a.workflow_id a "finish" r now_ns) ~f:(fun _ ->
                    Result.bind (master_activities store a "finish" r now_ns) ~f:(fun () ->
                    Result.map (S.complete_workflow store ~id_or_name:a.workflow_id
                      ~result:(activity a "support-complete" r) ~now_ns) ~f:(fun () -> done_job)))))))))))))))

let inspect_attempt store m ~task_id ~attempt =
  let plan_id = support m task_id attempt in
  Result.bind (find_task m task_id) ~f:(fun task ->
    Result.bind (S.find_plan store ~id_or_name:plan_id) ~f:(function
      | None -> fail "manual attempt not registered"
      | Some _ ->
          Result.bind (S.list_workflows store) ~f:(fun workflows ->
            match List.find workflows ~f:(fun workflow -> String.equal workflow.id (plan_id ^ "/workflow")) with
            | None -> fail "manual workflow missing"
            | Some workflow ->
                let a = { manifest=m; task; attempt_id=attempt; owner=""; preflight=""; change_id=""; commit_id="";
                  plan_id; task_id="EXECUTE"; job_id=plan_id ^ "/job"; workflow_id=plan_id ^ "/workflow";
                  queue="uos-manual-" ^ lower task_id ^ "-" ^ attempt; mapping_id="bridge/sa-plan/" ^ plan_id } in
                Result.bind (job store a) ~f:(fun j ->
                  Result.map (S.find_bridge_lease store ~mapping_id:a.mapping_id) ~f:(fun lease ->
                    `Assoc [
                      "schema", `String "uos.manual-execution-inspection.v1";
                      "master_task", `String task_id; "attempt", `String attempt;
                      "support_plan", `String plan_id; "workflow_state", `String workflow.state;
                      "job_state", `String (match j.state with
                        | S.Job_available -> "available" | Job_executing -> "executing" | Job_retry -> "retry"
                        | Job_completed -> "completed" | Job_discarded -> "discarded" | Job_cancelled -> "cancelled");
                      "lease", (match lease with
                        | None -> `Null
                        | Some lease -> `Assoc [
                            "owner", `String lease.owner; "lease_id", `String lease.lease_id;
                            "fence", `String (Int64.to_string lease.fencing_token);
                            "expires_at_ns", `String (Int64.to_string lease.expires_at_ns) ]);
                      "implementation_credit", `Bool false;
                      "system_admission_granted", `Bool false ])))))

let register_master_for_test store (m:manifest) ~now_ns =
  ok (S.create_plan store ~id:m.plan_id ~name:m.plan_id ~title:"scratch master" ~now_ns:now_ns);
  let rec create pending created =
    match pending with
    | [] -> ()
    | _ ->
        let ready, later = List.partition_tf pending ~f:(fun t ->
          List.for_all t.deps ~f:(fun dep -> List.mem created dep ~equal:String.equal)) in
        if List.is_empty ready then failwith "scratch manifest dependency cycle";
        List.iter ready ~f:(fun t ->
          ok (S.create_task store ~plan_id:m.plan_id ~id:t.id
            ~name:(m.plan_id ^ "/task/" ^ lower t.id) ~title:t.id ~parent_id:None
            ~dependencies:t.deps ~priority:50 ~now_ns:now_ns));
        create later (List.map ready ~f:(fun t -> t.id) @ created)
  in
  create m.tasks [];
  ok (S.start_workflow_with_input store ~id:m.programme ~name:m.programme
    ~kind:"scratch" ~input:"" ~now_ns:now_ns);
  List.iter m.tasks ~f:(fun t ->
    if not (String.equal t.stream m.programme)
       && not (List.exists (ok (S.list_workflows store)) ~f:(fun w -> String.equal w.id t.stream))
    then ok (S.start_workflow_with_input store ~id:t.stream ~name:t.stream
      ~kind:"scratch" ~input:"" ~now_ns:now_ns));
  let rec complete id time =
    let t = ok (find_task m id) in
    List.iter t.deps ~f:(fun d -> complete d Int64.(time + 1L));
    match ok (S.find_task store ~plan_id:m.plan_id ~id_or_name:id) with
    | Some { state = "completed"; _ } -> ()
    | Some _ ->
        ignore (ok (S.claim_task store ~plan_id:m.plan_id ~task_id:id ~worker:"scratch"
          ~now_ns:time ~lease_ns:1000L));
        ok (S.complete_task store ~plan_id:m.plan_id ~task_id:id ~worker:"scratch"
          ~result:"scratch dependency receipt" ~now_ns:Int64.(time + 1L))
    | None -> failwith "missing scratch task"
  in
  complete "PLAN00" Int64.(now_ns + 10L)

let lease_ns_of_seconds seconds =
  if Int64.(seconds < 1_320L) then fail "LEASE_SECONDS must be at least 1320"
  else if Int64.(seconds > 9_000_000L) then fail "LEASE_SECONDS is too large"
  else Ok Int64.(seconds * 1_000_000_000L)

let usage () =
  print_endline
    "register M DB TASK ATTEMPT OWNER PREFLIGHT; start M DB TASK ATTEMPT OWNER LEASE_SECONDS; record M DB TASK ATTEMPT OWNER LEASE_ID STAGE RECEIPT; finish M DB TASK ATTEMPT OWNER LEASE_ID RECEIPT; inspect M DB TASK ATTEMPT. Lease seconds are converted to ns and must be at least 1320. No active renewal exists: resume only after expiry with a new fence. At expires_at_ns equality the lease remains live; reclamation starts only after expiry."
let read path =
  if not (allowed_extension "receipt" path) then fail "receipt input extension must be .json"
  else Result.bind (descriptor_bytes ~validate:validate_evidence_path path) ~f:(fun (bytes, _) ->
    Result.bind (parse_object bytes) ~f:(fun receipt ->
      Result.bind (str "schema" receipt) ~f:(fun schema ->
        if String.equal schema "uos.manual-execution-receipt.v1" then Ok bytes
        else fail "unsupported receipt schema")))
let stored store m task attempt owner =
  let plan = support m task attempt in
  Result.bind (S.list_workflows store) ~f:(fun workflows ->
    match List.find workflows ~f:(fun workflow -> String.equal workflow.id (plan ^ "/workflow")) with
    | None -> fail "manual workflow missing"
    | Some workflow ->
        Result.bind (parse_object workflow.input) ~f:(fun input ->
        Result.bind (str "owner" input) ~f:(fun registered_owner ->
          if not (String.equal registered_owner owner) then fail "registered attempt owner differs from command"
          else decode m ~task_id:task ~attempt ~owner (member "preflight" input))))
let with_store db f=Result.bind(S.open_db db)~f:(fun store->Fun.protect~finally:(fun()->S.close store)(fun()->f store))
let ()=if String.equal (Filename.basename Sys.argv.(0)) "sa_plan_swarm.ml" then try
  if Array.length Sys.argv=2&&String.equal Sys.argv.(1)"--help"then usage ()
  else if Array.length Sys.argv<6 then(usage();exit 2)else let op=Sys.argv.(1)and path=Sys.argv.(2)and db=Sys.argv.(3)and task=Sys.argv.(4)and attempt=Sys.argv.(5)in let m=ok(load_manifest path)in
  let result=with_store db(fun store->match op with
  |"inspect"when Array.length Sys.argv=6->inspect_attempt store m~task_id:task~attempt
  |"register"when Array.length Sys.argv=8->Result.bind(read Sys.argv.(7))~f:(fun r->Result.map(register_attempt store m~task_id:task~attempt~owner:Sys.argv.(6)~preflight:r~now_ns:(now()))~f:(fun a->`Assoc["status",`String"REGISTERED";"support_plan",`String a.plan_id;"implementation_credit",`Bool false]))
  |"start"when Array.length Sys.argv=8->Result.bind(stored store m task attempt Sys.argv.(6))~f:(fun a->Result.bind(lease_ns_of_seconds(Int64.of_string Sys.argv.(7)))~f:(fun lease_ns->Result.map(start_attempt store a~now_ns:(now())~lease_ns)~f:(fun x->`Assoc["status",`String"STARTED";"lease_id",`String x.lease_id;"fence",`String(Int64.to_string x.fence);"expires_at_ns",`String(Int64.to_string x.expires_at_ns);"implementation_credit",`Bool false])))
  |"record"when Array.length Sys.argv=10->Result.bind(stored store m task attempt Sys.argv.(6))~f:(fun a->Result.bind(read Sys.argv.(9))~f:(fun r->Result.map(record_attempt store a~owner:Sys.argv.(6)~lease_id:Sys.argv.(7)~stage:Sys.argv.(8)~receipt:r~now_ns:(now()))~f:(fun ()->`Assoc["status",`String"RECORDED";"implementation_credit",`Bool false])))
  |"finish"when Array.length Sys.argv=9->Result.bind(stored store m task attempt Sys.argv.(6))~f:(fun a->Result.bind(read Sys.argv.(8))~f:(fun r->Result.map(finish_attempt store a~owner:Sys.argv.(6)~lease_id:Sys.argv.(7)~receipt:r~now_ns:(now()))~f:(fun j->`Assoc["status",`String"SUPPORT_FINISHED";"job_attempt",`String(string_of_int j.attempt);"implementation_credit",`Bool false;"system_admission_granted",`Bool false])))
  |_ ->fail"invalid command arguments; use --help")in print_endline(json(ok result))
  with exn->prerr_endline("sa-plan swarm: "^Exn.to_string exn);exit 1
