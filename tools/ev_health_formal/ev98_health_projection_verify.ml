(** Reject-by-default verifier for the exhaustive Gleam EV98 projection. *)

module M = Ev98_health_model
module J = Yojson.Safe

let fail message = failwith ("EV98 projection refused: " ^ message)
let member name = function `Assoc xs -> (try List.assoc name xs with Not_found -> fail ("missing " ^ name)) | _ -> fail "object expected"
let integer name json = match member name json with `Int n -> n | _ -> fail (name ^ " must be an integer")
let string name json = match member name json with `String s -> s | _ -> fail (name ^ " must be a string")

let register json =
  let writer = string "writer" json in
  if String.length writer <> 2 || writer.[0] <> 'w' || writer.[1] < '0' || writer.[1] > '2'
  then fail "writer outside fixed domain";
  let record = { M.sample = integer "sample" json; logical = integer "logical" json;
                 writer = Char.code writer.[1] - Char.code '0'; payload = integer "payload" json } in
  if record.sample < 0 || record.sample > 2 || record.logical < 0 || record.logical > 2
     || record.payload < 0 || record.payload > 1 then fail "record outside fixed domain";
  record

let key a b =
  Printf.sprintf "%d/%d/%d/%d:%d/%d/%d/%d"
    a.M.sample a.logical a.writer a.payload b.M.sample b.logical b.writer b.payload

let verify_pair seen json =
  if string "node" json <> "target" then fail "pair node";
  let left = register (member "left" json) and right = register (member "right" json) in
  if not (M.well_formed_pair left right) then fail "malformed pair in exhaustive table";
  let identity = key left right in
  let actual = register (member "winner" json) in
  if Hashtbl.mem seen identity then fail "duplicate pair";
  if actual <> M.select left right then fail "Gleam winner differs from independent order";
  Hashtbl.add seen identity actual

let require_order = function
  | `List [ `String "a"; `String "b" ] -> ()
  | _ -> fail "canonical node order"

let verify_controls collision raw =
  let forward = register (member "forward" collision) and reverse = register (member "reverse" collision) in
  if forward.payload = reverse.payload then fail "collision control did not expose equal-key payload ambiguity";
  let forward_order = member "forward" raw and reverse_order = member "reverse" raw in
  if forward_order = reverse_order then fail "raw map control did not expose association-list order";
  require_order (member "canonical" raw)

let digest_file path =
  let channel = open_in_bin path in
  let digest = Cryptokit.hash_channel (Cryptokit.Hash.sha256 ()) channel in
  close_in channel;
  Cryptokit.transform_string (Cryptokit.Hexa.encode ()) digest

let output_from_receipt receipt =
  match J.from_file receipt with
  | `Assoc _ as json ->
    (match member "output" json with `String output -> output | _ -> fail "receipt output missing")
  | _ -> fail "receipt root"

let () =
  if Array.length Sys.argv <> 4 then fail "usage: RECEIPT BEAM EXPECTED_BEAM_SHA256";
  let receipt = Sys.argv.(1) and beam = Sys.argv.(2) and expected = Sys.argv.(3) in
  if digest_file beam <> expected then fail "compiled Gleam BEAM digest";
  let output = output_from_receipt receipt in
  if String.length output > 4 * 1024 * 1024 then fail "projection exceeds 4MiB";
  let lines = String.split_on_char '\n' output |> List.filter (fun x -> x <> "") in
  let seen = Hashtbl.create 3000 and header = ref false and collision = ref None and raw = ref None in
  List.iter
    (fun line ->
       let json = try J.from_string line with _ -> fail "invalid JSON line" in
       match string "kind" json with
       | "header" ->
         if !header || integer "records" json <> 54 || integer "well_formed_pairs" json <> 2862
         then fail "header"; header := true
       | "pair" -> verify_pair seen json
       | "malformed_collision" -> if Option.is_some !collision then fail "duplicate collision"; collision := Some json
       | "raw_map_order" -> if Option.is_some !raw then fail "duplicate raw order"; raw := Some json
       | _ -> fail "unknown line kind")
    lines;
  if not !header then fail "missing header";
  if Hashtbl.length seen <> 2862 then fail "missing pair result";
  List.iter (fun (left, right) -> if not (Hashtbl.mem seen (key left right)) then fail "required pair absent") (M.all_well_formed_pairs ());
  List.iter
    (fun (left, middle, right) ->
       let lm = Hashtbl.find seen (key left middle) in
       let mr = Hashtbl.find seen (key middle right) in
       let left_associated = Hashtbl.find seen (key lm right) in
       let right_associated = Hashtbl.find seen (key left mr) in
       if left_associated <> right_associated then
         fail "closed pair table refutes an actual triple composition")
    (M.all_well_formed_triples ());
  (match !collision, !raw with Some c, Some r -> verify_controls c r | _ -> fail "missing negative controls");
  print_endline "PASS EV98 exhaustive compiled Gleam projection: 54 records, 2862 pairs, closed actual triple compositions, malformed and raw-order controls"
