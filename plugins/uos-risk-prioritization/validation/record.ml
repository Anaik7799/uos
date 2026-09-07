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
let read path = Bounded.read path
let rec unique = function
  | `Assoc xs ->
      let keys = List.map fst xs in
      require (List.length keys = List.length (List.sort_uniq String.compare keys))
        "duplicate JSON object key";
      List.iter (fun (_,v) -> unique v) xs
  | `List xs -> List.iter unique xs
  | _ -> ()
let json path =
  let v = Bounded.json_text (read path) in unique v; v
let nullable_int = function `Null -> None | `Int n -> Some n
  | _ -> raise (Invalid "expected integer or null")
let hex64 s =
  String.length s = 64 &&
  String.for_all (fun c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) s

(* Bounded schema subset: unsupported assertion keywords fail closed. *)
let supported = ["$schema";"$comment";"title";"description";"const";"enum";"type";
  "anyOf";"minimum";"maximum";"minLength";"pattern";"format";"required";
  "properties";"additionalProperties";"items";"prefixItems";"minItems";"maxItems"]
(* Validate every schema branch BEFORE looking at data; no ignored assertion paths. *)
let schema_preflight schema =
  unique schema;
  let budget=ref 0 in
  let rec visit depth s =
    incr budget; require (!budget<=10000 && depth<=64) "schema exceeds bound";
    List.iter (fun (k,v) ->
      require (List.mem k supported) ("unsupported schema keyword: "^k);
      match k with
      | "$schema" -> require (str v="https://json-schema.org/draft/2020-12/schema") "unsupported dialect"
      | "$comment"|"title"|"description" -> ignore (str v)
      | "type" -> require (List.mem (str v)
          ["null";"string";"integer";"object";"array";"boolean"]) "unsupported schema type"
      | "anyOf"|"prefixItems" ->
          let xs=arr v in require (xs<>[]) "empty schema branch list";
          List.iter (visit (depth+1)) xs
      | "properties" -> List.iter (fun (_,child)->visit (depth+1) child) (obj v)
      | "items" -> visit (depth+1) v
      | "additionalProperties" -> require (v=`Bool false || v=`Bool true) "unsupported additionalProperties schema"
      | "minimum"|"maximum" -> ignore (int v)
      | "minLength"|"minItems"|"maxItems" -> require (int v>=0) "negative schema bound"
      | "required" ->
          let xs=List.map str (arr v) in
          require (List.length xs=List.length (List.sort_uniq String.compare xs))
            "duplicate required key"
      | "enum" ->
          let xs=arr v in require (xs<>[] && List.length xs=List.length (List.sort_uniq compare xs)) "empty/duplicate enum"
      | "pattern" -> require (str v="^[0-9a-f]{64}$") "unsupported pattern"
      | "format" -> require (str v="date-time") "unsupported format"
      | "const" -> ()
      | _ -> raise (Invalid "unhandled schema keyword")) (obj s);
    List.iter (fun (lo,hi)->if has lo s && has hi s then
      require (int (field lo s)<=int (field hi s)) "inverted schema bounds")
      ["minimum","maximum";"minItems","maxItems"]
  in visit 0 schema
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
  schema_preflight schema; unique j; schema_check schema j "record";
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
  let fmea_bound fallback =
    arr (field "fmea_modes" j) |> List.fold_left (fun acc mode ->
      let value key = Option.value (nullable_int (field key mode)) ~default:fallback in
      max acc (fmea (value "s") (value "o") (value "det"))) 1 in
  let ff = field "fmea" factors in
  require (int (field "low" ff) = fmea_bound 1 && int (field "high" ff) = fmea_bound 5)
    "FMEA interval must retain known severity and unknown occurrence/detection bounds";
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
let schema () =
  let path=planning ^ "-record.schema.json" in
  require (Bounded.sha256 (read path)="ce13ab02d802472e4966c97f58503ec0353ba2b31fd76e179843dceb70f7186c") "canonical record schema drift";
  json path
let sample () = json (planning ^ "-example.json")
let change k v j = `Assoc ((k,v)::List.remove_assoc k (obj j))
