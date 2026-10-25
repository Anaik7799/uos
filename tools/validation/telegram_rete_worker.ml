exception Invalid_schema
exception Worker_failure

let err_schema = "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"invalid_fact_schema\"}"
let err_worker = "{\"status\":\"unavailable\",\"reason\":\"worker_failure\"}"

let valid_keys = ["watchdog"; "mesh_running"; "e_stop"; "high_drift"; "divergent"]

let is_printable_ascii s =  let len = String.length s in
  let rec loop i =
    if i = len then true
    else
      let c = Char.code s.[i] in
      if c >= 32 && c <= 126 then loop (i + 1) else false
  in
  loop 0

let parse_facts raw =
  let len = String.length raw in
  if len < 1 || len > 256 || not (is_printable_ascii raw) then raise Invalid_schema;
  let parts = String.split_on_char ',' raw in
  let n = List.length parts in
  if n < 1 || n > 5 then raise Invalid_schema;
  let rec loop seen acc = function
    | [] -> String.concat "," (List.rev acc)
    | part :: rest ->
      let p = String.trim part in
      if p = "" then raise Invalid_schema;
      match String.split_on_char '=' p with
      | [k_raw; v_raw] ->
        let k = String.trim k_raw and v = String.trim v_raw in
        if not (List.mem k valid_keys) || List.mem k seen then raise Invalid_schema;
        if v <> "true" && v <> "false" then raise Invalid_schema;
        loop (k :: seen) ((k ^ "=" ^ v) :: acc) rest
      | _ -> raise Invalid_schema
  in
  loop [] [] parts

let () =
  match
    if Array.length Sys.argv <> 2 then raise Invalid_schema;
    let canonical = parse_facts Sys.argv.(1) in
    let res =
      try C3i_ocaml_bridge.ocaml_rete_eval canonical
      with _ -> raise Worker_failure
    in
    let rlen = String.length res in
    if rlen < 1 || rlen > 2048 || not (is_printable_ascii res) then raise Worker_failure;
    res
  with
  | res ->
    print_endline res;
    exit 0
  | exception Invalid_schema ->
    print_endline err_schema;
    exit 0
  | exception _ ->
    print_endline err_worker;
    exit 1
