(* Operation adapter only. Assertions and verdicts belong to Gleam. *)
module P = Parity_algebra
let limit = 8 * 1024 * 1024
let all = [P.Unmapped; P.Blocked; P.Verified; P.Divergent]
let s x = `String x
let i x = `Int x
let b x = `Bool x
let name v = s (P.name v)
let obj xs = `Assoc xs
let get key = function
  | `Assoc xs -> (match List.assoc_opt key xs with Some x -> x | None -> invalid_arg ("missing " ^ key))
  | _ -> invalid_arg "expected object"
let string = function `String s -> s | _ -> invalid_arg "expected string"
let boolean = function `Bool b -> b | _ -> invalid_arg "expected boolean"
let verdict = function
  | `String "unmapped" -> P.Unmapped | `String "blocked" -> P.Blocked
  | `String "verified" -> P.Verified | `String "divergent" -> P.Divergent
  | _ -> invalid_arg "unknown verdict"
let verdicts = function `List xs -> List.map verdict xs | _ -> invalid_arg "expected verdict array"
let report required vs =
  let r = P.report ~required vs in
  let rolled = P.roll_up ~required vs in
  obj ["rolled", name rolled; "verdict", name r.verdict;
    "total", i r.total; "verified", i r.verified; "blocked", i r.blocked;
    "divergent", i r.divergent; "unmapped", i r.unmapped;
    "percent", i (P.credit_percent r); "rendered", s (P.render_report r);
    "grants_credit", b (P.grants_credit rolled)]
let execute operation args = match operation with
  | "observe" ->
    obj ["identity", name P.identity;
      "verdicts", `List (List.map (fun v -> obj ["name", name v;
        "rank", i (P.rank v); "grants_credit", b (P.grants_credit v);
        "asserts_defect", b (P.asserts_defect v)]) all);
      "combine", `List (List.map (fun a -> `List (List.map (fun c -> name (P.combine a c)) all)) all);
      "impacts", `List (List.map (fun v -> name (P.of_diagnostic_impact v))
        [Fractal_diagnostic.Blocks_credit; Fractal_diagnostic.Denies_credit; Fractal_diagnostic.No_effect])]
  | "report" -> report (boolean (get "required" args)) (verdicts (get "verdicts" args))
  | "vectors" ->
    Random.init 20260808;
    let random () = List.nth all (Random.int 4) in
    let vectors = List.init 2000 (fun _ ->
      let size = Random.int 12 in
      let vs = List.init size (fun _ -> random ()) in
      let required = Random.bool () in
      obj ["inputs", `List (List.map name vs); "required", b required;
        "report", report required vs]) in
    obj ["seed", i 20260808; "vectors", `List vectors]
  | _ -> invalid_arg "unknown operation"

(* Guard JSON nesting before the recursive parser; frame bytes are separately bounded. *)
let bounded_json text =
  let depth = ref 0 and quoted = ref false and escaped = ref false in
  String.iter (fun c ->
    if !quoted then
      if !escaped then escaped := false else if c = '\\' then escaped := true
      else if c = '"' then quoted := false
    else match c with
      | '"' -> quoted := true
      | '[' | '{' -> incr depth; if !depth > 64 then invalid_arg "JSON nesting exceeds 64"
      | ']' | '}' -> decr depth
      | _ -> ()) text;
  Yojson.Basic.from_string text

let main () =
  Sys.set_signal Sys.sigalrm (Sys.Signal_handle (fun _ -> exit 124));
  ignore (Unix.alarm 30);
  let length = input_binary_int stdin in
  if length < 0 || length > limit then invalid_arg "frame too large";
  let request = bounded_json (really_input_string stdin length) in
  let id = string (get "id" request) in
  let operation = string (get "operation" request) in
  let version = get "version" request in
  let response =
    try
      if version <> i 1 then invalid_arg "unsupported version";
      let args = get "arguments" request in
      (match args with `Assoc _ -> () | _ -> invalid_arg "arguments must be object");
      ["result", execute operation args]
    with Invalid_argument message -> ["error", obj ["code", s "invalid_request"; "message", s message]]
  in
  let bytes = Yojson.Basic.to_string (obj (["version", version; "id", s id; "operation", s operation] @ response)) in
  if String.length bytes > limit then invalid_arg "response too large";
  output_binary_int stdout (String.length bytes);
  output_string stdout bytes;
  flush stdout
let () = try main () with _ -> exit 2
