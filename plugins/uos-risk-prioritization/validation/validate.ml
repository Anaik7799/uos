(* Repository-local checks. All output is advisory; no task, board or runtime writes. *)
open Priority
let stamp = "20260907-1559"
let sop = "contracts/rules/" ^ stamp ^ "-risk-prioritization-sop.md"
let planning = "governance/planning/" ^ stamp ^ "-risk-priority"
let plugin = "plugins/uos-risk-prioritization"
let skill = plugin ^ "/skills/uos-risk-prioritization/SKILL.md"
let str = function `String s -> s | _ -> raise (Invalid "expected string")
let int = function `Int n -> n | _ -> raise (Invalid "expected integer")
let arr = function `List xs -> xs | _ -> raise (Invalid "expected array")
let obj = function `Assoc xs -> xs | _ -> raise (Invalid "expected object")
let field key j = Option.value (List.assoc_opt key (obj j)) ~default:`Null
let text key j = str (field key j)
let has key j = List.mem_assoc key (obj j)
let contains s part =
  let rec loop i =
    i + String.length part <= String.length s &&
    (String.sub s i (String.length part) = part || loop (i+1))
  in part = "" || loop 0
let read path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let n = in_channel_length ic in
    require (n <= 1048576) ("file exceeds 1 MiB: " ^ path);
    really_input_string ic n)
let rec unique = function
  | `Assoc xs ->
      let keys = List.map fst xs in
      require (List.length keys = List.length (List.sort_uniq String.compare keys))
        "duplicate JSON object key";
      List.iter (fun (_,v) -> unique v) xs
  | `List xs -> List.iter unique xs
  | _ -> ()
let json path =
  let v = Yojson.Basic.from_string (read path) in unique v; v
let nullable_int = function `Null -> None | `Int n -> Some n
  | _ -> raise (Invalid "expected integer or null")
let hex64 s =
  String.length s = 64 &&
  String.for_all (fun c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) s

(* Bounded schema subset: unsupported assertion keywords fail closed. *)
let rec schema_check schema value path =
  let keys = List.map fst (obj schema) in
  let supported = ["$schema";"$comment";"title";"description";"const";"enum";"type";
    "anyOf";"minimum";"maximum";"minLength";"pattern";"format";"required";
    "properties";"additionalProperties";"items";"prefixItems";"minItems";"maxItems"] in
  List.iter (fun k -> require (List.mem k supported) ("unsupported schema keyword: " ^ k)) keys;
  if has "anyOf" schema then
    require (List.exists (fun branch ->
      try schema_check branch value path; true with Invalid _ -> false)
      (arr (field "anyOf" schema))) (path ^ ": no anyOf branch matched");
  if has "const" schema then require (value = field "const" schema) (path ^ ": wrong constant");
  if has "enum" schema then require (List.mem value (arr (field "enum" schema))) (path ^ ": wrong enum");
  if has "type" schema then (
    let ok = match text "type" schema, value with
      | "null",`Null | "string",`String _ | "integer",`Int _
      | "object",`Assoc _ | "array",`List _ | "boolean",`Bool _ -> true
      | _ -> false in require ok (path ^ ": wrong type"));
  (match value with
  | `Int n ->
      if has "minimum" schema then require (n >= int (field "minimum" schema)) (path ^ ": below minimum");
      if has "maximum" schema then require (n <= int (field "maximum" schema)) (path ^ ": above maximum")
  | `String s ->
      if has "minLength" schema then require (String.length s >= int (field "minLength" schema)) (path ^ ": empty string");
      if has "pattern" schema then (
        require (text "pattern" schema = "^[0-9a-f]{64}$") "unsupported pattern";
        require (hex64 s) (path ^ ": invalid SHA-256 syntax"));
      if has "format" schema then (
        require (text "format" schema = "date-time") "unsupported format";
        require (valid_utc s) (path ^ ": requires canonical UTC timestamp"))
  | `Assoc xs ->
      if has "required" schema then List.iter (fun k ->
        require (List.mem_assoc (str k) xs) (path ^ ": missing " ^ str k)) (arr (field "required" schema));
      let properties = if has "properties" schema then obj (field "properties" schema) else [] in
      List.iter (fun (k,v) ->
        match List.assoc_opt k properties with
        | Some child -> schema_check child v (path ^ "." ^ k)
        | None -> require (field "additionalProperties" schema <> `Bool false)
                    (path ^ ": unknown field " ^ k)) xs
  | `List xs ->
      let n = List.length xs in
      if has "minItems" schema then require (n >= int (field "minItems" schema)) (path ^ ": too few items");
      if has "maxItems" schema then require (n <= int (field "maxItems" schema)) (path ^ ": too many items");
      let prefix = if has "prefixItems" schema then arr (field "prefixItems" schema) else [] in
      List.iteri (fun i v ->
        let child = if i < List.length prefix then Some (List.nth prefix i)
          else if has "items" schema then Some (field "items" schema) else None in
        Option.iter (fun s -> schema_check s v (path ^ "[" ^ string_of_int i ^ "]")) child) xs
  | _ -> ())

let utc_seconds s =
  require (valid_utc s) "invalid UTC";
  let p a n = int_of_string (String.sub s a n) in
  let y=p 0 4 and m=p 5 2 and d=p 8 2 in
  let prev=y-1 in
  let days=ref (prev*365 + prev/4 - prev/100 + prev/400 + d-1) in
  for month=1 to m-1 do
    days := !days + (match month with
      | 2 -> if y mod 4=0 && (y mod 100<>0 || y mod 400=0) then 29 else 28
      | 4|6|9|11 -> 30 | _ -> 31)
  done;
  !days*86400 + p 11 2*3600 + p 14 2*60 + p 17 2

let check_record schema j =
  unique j; schema_check schema j "record";
  let factors = field "factors" j in
  let names = ["criticality";"stpa";"fmea";"dependency";"impact"] in
  let values = List.map (fun name ->
    let f = field name factors in
    let low=int (field "low" f) and high=int (field "high" f) in
    require (low <= high) ("factor interval inverted: " ^ name);
    let v=nullable_int (field "value" f) in
    Option.iter (fun n -> require (low <= n && n <= high) ("factor outside interval: " ^ name)) v;
    v) names in
  let expected = if List.mem None values then None else Some (score (List.map Option.get values)) in
  require (nullable_int (field "score" j) = expected) "five-factor product mismatch";
  let lows=List.map (fun n->int (field "low" (field n factors))) names in
  let highs=List.map (fun n->int (field "high" (field n factors))) names in
  require (List.map int (arr (field "score_interval" j)) = [score lows;score highs])
    "score interval mismatch";
  let modes = List.map (fun mode ->
    let s=nullable_int (field "s" mode) and o=nullable_int (field "o" mode)
    and d=nullable_int (field "det" mode) in
    let expected_rpn, expected_band = match s,o,d with
      | Some s,Some o,Some d -> Some (rpn s o d), Some (fmea s o d)
      | _ -> None,None in
    require (nullable_int (field "rpn" mode) = expected_rpn) "FMEA RPN mismatch";
    require (nullable_int (field "band" mode) = expected_band) "FMEA band mismatch";
    expected_band) (arr (field "fmea_modes" j)) in
  let aggregate = if List.mem None modes then None
    else Some (List.fold_left max 1 (List.map Option.get modes)) in
  require (nullable_int (field "value" (field "fmea" factors)) = aggregate)
    "FMEA factor must be maximum mode band";
  let stpa=field "stpa_analysis" j in
  let uc=arr (field "ucas" stpa) in
  let types=List.map (text "type") uc |> List.sort_uniq String.compare in
  require (types = List.sort String.compare ["not_provided";"provided_unsafe";"wrong_timing";"duration"])
    "all four UCA types must be considered";
  let hazards=List.map str (arr (field "hazards" stpa)) in
  List.iter (fun u ->
    let hs=List.map str (arr (field "hazard_ids" u)) in
    require (List.for_all (fun h->List.mem h hazards) hs) "UCA references missing hazard";
    if text "applicability" u = "applicable" then require (hs <> []) "applicable UCA needs hazard") uc;
  let observed=text "observed_at" j and expires=text "valid_until" j in
  let age=utc_seconds expires - utc_seconds observed in
  let ceiling=match text "phase" j with "incident"->900 | "release"->3600 | _->86400 in
  require (age>0 && age<=ceiling) "invalid assessment lifetime";
  if text "readiness" j = "ready" then (
    require (expected <> None) "unknown assessment cannot be ready";
    require (arr (field "blockers" j) = []) "blocked assessment cannot be ready");
  j
let candidate j =
  { id=text "task_id" j; class_=text "class" j;
    own_score=nullable_int (field "score" j);
    upper=int (List.nth (arr (field "score_interval" j)) 1);
    state=text "task_state" j; readiness=text "readiness" j;
    dependencies=List.map str (arr (field "dependencies" j));
    observed=text "observed_at" j; expires=text "valid_until" j;
    ready_since=text "ready_since" j }

let now_utc () =
  let t=Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (1900+t.Unix.tm_year) (1+t.Unix.tm_mon) t.Unix.tm_mday
    t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec
let print_json j = print_endline (Yojson.Basic.to_string j)
let schema () = json (planning ^ "-record.schema.json")
let sample () = json (planning ^ "-example.json")
let change k v j = `Assoc ((k,v)::List.remove_assoc k (obj j))
let selftest () =
  let count=ref (Priority.selftest ()) in
  let check name b=incr count; require b ("record test: " ^ name) in
  let s=schema () and ex=sample () in
  ignore (check_record s ex); incr count;
  let reject name j=check name (try ignore (check_record s j);false with Invalid _->true) in
  reject "forged product" (change "score" (`Int 3125) ex);
  reject "false ready with blocker" (change "blockers" (`List [`String "missing control"]) ex);
  reject "bad timestamp" (change "observed_at" (`String "yesterday") ex);
  reject "expired window" (change "valid_until" (field "observed_at" ex) ex);
  reject "extra privilege flag" (change "approved" (`Bool true) ex);
  let f=field "factors" ex in
  let impact=field "impact" f in
  reject "zero factor" (change "factors" (change "impact" (change "value" (`Int 0) impact) f) ex);
  let snap=field "snapshot" ex in
  let ev=List.hd (arr (field "evidence" snap)) in
  reject "placeholder digest" (change "snapshot"
    (change "evidence" (`List [change "sha256" (`String "authentic_physical_probe") ev]) snap) ex);
  let stpa=field "stpa_analysis" ex in
  reject "missing UCA type" (change "stpa_analysis"
    (change "ucas" (`List (List.tl (arr (field "ucas" stpa)))) stpa) ex);
  reject "duplicate JSON field" (`Assoc (("score",`Int 960)::obj ex));
  print_json (`Assoc ["status",`String "PASS";"checks",`Int !count;
    "authority",`String "REPORT_ONLY";"behavioral_agent_tests",`String "UNRUN"])
let check_package () =
  let repo=Unix.realpath "." in
  let checked=ref 0 in
  let local path =
    require (Sys.file_exists path) ("missing file: " ^ path);
    let resolved=Unix.realpath path in
    require (String.starts_with ~prefix:(repo ^ "/") resolved) ("external dependency: " ^ path);
    incr checked in
  let docs=[sop;
    "docs/wiki/"^stamp^"-risk-prioritization-guide.md";
    "docs/zk/"^stamp^"-adr-risk-prioritization.md";
    "docs/journal/"^stamp^"-risk-prioritization-journal.md";
    skill;plugin^"/skills/uos-risk-prioritization/references/"^stamp^"-superpowers-bindings.md"] in
  List.iter (fun path ->
    local path; let content=read path in
    require (contains content "SC-RISK-PRIORITY-001" || contains content "risk-prioritization-sop.md")
      ("missing policy link: "^path);
    for i=1 to 18 do
      require (contains content (Printf.sprintf "CHK-%02d-" i)) ("missing checklist row: "^path)
    done;
    require (contains content "http://nas-1.tail55d152.ts.net:4100/") ("missing FQDN: "^path)) docs;
  List.iter (fun root ->
    let agent=if root="" then "AGENTS.md" else root^"/AGENTS.md" in
    local agent;
    require (contains (read agent) "SC-RISK-PRIORITY-001") ("agent binding missing: "^agent);
    if root<>"" then (
      let alias=root^"/skills/uos-risk-prioritization/SKILL.md" in
      local alias; require (read alias=read skill) ("skill alias drift: "^alias);
      let rule=root^"/rules/"^stamp^"-risk-prioritization-sop.md" in
      local rule; require (read rule=read sop) ("rule alias drift: "^rule)))
    ["";".codex";".claude";".gemini";".agents"];
  let manifest=plugin^"/.codex-plugin/plugin.json" in
  local manifest; let m=json manifest in
  require (text "name" m="uos-risk-prioritization" && text "version" m="1.0.0") "plugin identity/version";
  require (text "skills" m="./skills/") "plugin skills path";
  require (not (has "mcpServers" m || has "apps" m || has "hooks" m)) "unexpected active plugin capability";
  List.iter local [planning^"-policy.json";planning^"-record.schema.json";planning^"-example.json";
    "governance/agents/policy/"^stamp^"-risk-priority-bindings.toml";"tools/risk-priority-check";
    plugin^"/validation/priority.ml";plugin^"/validation/validate.ml";plugin^"/validation/dune";plugin^"/validation/dune-project"];
  let profile=json (planning^"-policy.json") in
  require (field "factors" profile=`List (List.map (fun s->`String s)
    ["criticality";"stpa";"fmea";"dependency";"impact"])) "factor profile drift";
  require (field "rpn_maxima" (field "fmea" profile)=`List (List.map (fun n->`Int n) [5;15;35;70;125]))
    "FMEA band profile drift";
  ignore (check_record (schema ()) (sample ()));
  print_json (`Assoc ["status",`String "PASS";"local_paths_checked",`Int !checked;
    "authority",`String "REPORT_ONLY";"runtime_enforcement",`String "NOT_ASSERTED";
    "global_skill_dependency",`Bool false])
let () =
  try
    match Array.to_list Sys.argv with
    | [_;"--selftest"] -> selftest ()
    | [_;"--package"] -> check_package ()
    | [_;"--record";path] ->
        ignore (check_record (schema ()) (json path));
        print_json (`Assoc ["status",`String "STRUCTURE_AND_ARITHMETIC_VALID";
          "live_source_digest_match",`String "NOT_CHECKED";"authority",`String "REPORT_ONLY"])
    | [_;"--rank";path] ->
        let s=schema () in
        let records=List.map (check_record s) (arr (json path)) in
        require (List.length records<=1000) "portfolio exceeds bound";
        let plans=List.map (text "plan_id") records |> List.sort_uniq String.compare in
        require (List.length plans<=1) "rank one plan at a time";
        let now=now_utc () in
        let ranked=rank ~now (List.map candidate records) in
        print_json (`Assoc ["authority",`String "ADVISORY_NOT_AUTHORIZATION";
          "observed_now",`String now;"live_source_digest_match",`String "NOT_CHECKED";
          "cost_tie_review",`String "MANUAL_BEFORE_STABLE_FALLBACK";
          "tasks",`List (List.map (fun r -> `Assoc [
            "task_id",`String r.task.id;
            "effective_class",`String ("P"^string_of_int r.effective_class);
            "effective_score",`Int r.effective_score;
            "origins",`List (List.map (fun s->`String s) r.origins)]) ranked)])
    | _ -> prerr_endline "Usage: risk-priority-check --selftest | --package | --record FILE | --rank FILE";exit 2
  with
  | Invalid message -> prerr_endline ("INVALID: "^message);exit 1
  | exn -> prerr_endline ("ERROR: "^Printexc.to_string exn);exit 1

