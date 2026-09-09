(* The effectful shell around Atlas_algebra.

   It reads the algebraic-atlas JSON, turns it into observations, and hands
   those to the pure core for judgement. All MEANING lives in atlas_algebra.ml;
   this file only parses and reports. That split is why the law suite can be
   evidence about the shipped semantics.

   Usage:
     atlas_check.exe ATLAS_JSON [--max-repeat N]
                     [--otp-release R --erts-version E --root-dir D]

   The OTP facts are passed in rather than measured here, because toolchain
   resolution is the shell library's authority (SC-NIX-DEVENV-001 inv.11) and a
   second resolver would drift. `tools/atlas-check` sources that library and
   supplies them. When they are absent the OTP arm reports UNKNOWN rather than
   passing -- an unmeasured inventory is not a matching inventory. *)

let ( let* ) o f = match o with None -> None | Some x -> f x

(* --- flattening ---------------------------------------------------------- *)

(* Leaf paths of one row, so degeneracy can be counted per field. Lists are
   indexed, because `errors[0]` being constant while `errors[1]` varies is a
   different fact from the whole list being constant. *)
let rec leaves prefix (j : Yojson.Safe.t) : (string * string) list =
  match j with
  | `Assoc kvs ->
      List.concat_map
        (fun (k, v) ->
          leaves (if prefix = "" then k else prefix ^ "." ^ k) v)
        kvs
  | `List xs ->
      List.concat
        (List.mapi (fun i x -> leaves (Printf.sprintf "%s[%d]" prefix i) x) xs)
  | leaf -> [ (prefix, Yojson.Safe.to_string leaf) ]

module SM = Map.Make (String)

(* For each field path, how many rows share its single most common value.
   Fields that do not appear on every row are still counted: a field present on
   three rows with one value is not degenerate at atlas scale, and the ratio in
   the message makes that legible. *)
let degeneracy (rows : Yojson.Safe.t list) : (string * int) list =
  let tally =
    List.fold_left
      (fun acc row ->
        List.fold_left
          (fun acc (path, v) ->
            let inner = try SM.find path acc with Not_found -> SM.empty in
            let n = try SM.find v inner with Not_found -> 0 in
            SM.add path (SM.add v (n + 1) inner) acc)
          acc (leaves "" row))
      SM.empty rows
  in
  SM.fold
    (fun path inner acc ->
      let top = SM.fold (fun _ n m -> max n m) inner 0 in
      (path, top) :: acc)
    tally []
  |> List.sort compare

(* --- obligation parsing -------------------------------------------------- *)

let structure_of_string s =
  List.find_opt
    (fun st -> Atlas_algebra.structure_name st = s)
    Atlas_algebra.all_structures

let status_of_string = function
  | "HOLDS" -> Some Atlas_algebra.Holds
  | "NOT_APPLICABLE" -> Some Atlas_algebra.Not_applicable
  | "UNKNOWN" -> Some Atlas_algebra.Unknown
  | "VIOLATED" -> Some Atlas_algebra.Violated
  | _ -> None

let str = function `String s -> Some s | _ -> None
let member k = function `Assoc kvs -> List.assoc_opt k kvs | _ -> None

let obligation_of_json (j : Yojson.Safe.t) : Atlas_algebra.obligation option =
  let* sname = member "structure" j |> Option.map str |> Option.join in
  let* structure = structure_of_string sname in
  let* sst = member "status" j |> Option.map str |> Option.join in
  let* status = status_of_string sst in
  let s k = match member k j with Some (`String v) -> v | _ -> "" in
  let b k = match member k j with Some (`Bool v) -> v | _ -> false in
  Some
    {
      Atlas_algebra.structure;
      status;
      predicate = s "predicate";
      falsifier = s "falsifier";
      oracle = s "oracle";
      independently_reviewed = b "independently_reviewed";
    }

(* --- main ---------------------------------------------------------------- *)

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  let path = match args with p :: _ when p <> "" && p.[0] <> '-' -> p | _ -> "" in
  let opt name =
    let rec go = function
      | a :: v :: _ when a = name -> Some v
      | _ :: tl -> go tl
      | [] -> None
    in
    go args
  in
  if path = "" then (
    prerr_endline "usage: atlas_check.exe ATLAS_JSON [--max-repeat N] \
                   [--otp-release R --erts-version E --root-dir D]";
    exit 2);
  let max_repeat =
    match opt "--max-repeat" with
    | Some n -> ( try int_of_string n with _ -> 20)
    (* Default ceiling. Two thirds of the rows may legitimately share a value --
       most capabilities really are `read`, for instance -- but a value on more
       than that is a constant, and a constant records nothing per row. *)
    | None -> 20
  in
  let json = Yojson.Safe.from_file path in
  let rows =
    match member "capabilities" json with
    | Some (`List xs) -> xs
    | _ ->
        prerr_endline "atlas_check: no `capabilities` array";
        exit 2
  in
  let total_rows = List.length rows in
  let row_id j =
    match member "id" j with Some (`String s) -> s | _ -> "<unnamed row>"
  in

  (* arm 1: every row carries the nine structure obligations, well formed *)
  let row_verdicts =
    List.map
      (fun r ->
        let id = row_id r in
        match member "structures" (Option.value ~default:`Null (member "algebra" r)) with
        | Some (`List os) ->
            let parsed = List.map obligation_of_json os in
            let bad = List.length (List.filter (fun o -> o = None) parsed) in
            let good = List.filter_map (fun o -> o) parsed in
            let parse_verdict =
              if bad = 0 then Atlas_algebra.Conforms
              else
                Atlas_algebra.Nonconforming
                  [
                    {
                      row_id = id;
                      detail =
                        Printf.sprintf
                          "%d obligation(s) unparseable: unknown structure or \
                           status name"
                          bad;
                    };
                  ]
            in
            Atlas_algebra.meet parse_verdict (Atlas_algebra.check_row ~row_id:id good)
        | _ ->
            Atlas_algebra.Nonconforming
              [
                {
                  row_id = id;
                  detail =
                    "no algebra.structures array -- formal spec section 3 \
                     declares nine structures per capability and this row \
                     encodes none of them";
                };
              ])
      rows
  in

  (* arm 2: degeneracy.

     The obligation array is EXCLUDED from this arm, and that exclusion is
     load-bearing rather than a convenience. `algebra.structures[i].structure`
     is required to be the same nine names in the same order on every row --
     that is what "all nine structures, exactly once" MEANS -- and an honest
     UNKNOWN legitimately carries an empty falsifier and oracle on many rows.
     Counting those as degeneracy would punish honesty and push an author to
     invent content to make a number go down. That is precisely the defect this
     whole module exists to prevent, appearing inside its own guard. The
     obligation fields already have their own arm (check_row); measuring them
     twice, under a rule that cannot distinguish "uniform because required"
     from "uniform because empty", is the coarser observable again. *)
  let under_obligations path =
    let p = "algebra.structures" in
    String.length path >= String.length p && String.sub path 0 (String.length p) = p
  in
  (* A categorical field with a small legitimate domain -- effect class,
     transport availability -- will exceed any ratio ceiling honestly: most
     capabilities really are reads. Forcing variation there would mean inventing
     it, which is the failure, not the fix. Such a field may be listed in the
     atlas's `bounded_domain_fields`, and is then judged by a FINER rule
     instead: it must actually exhibit more than one value. A field pinned to a
     single value is degenerate whatever its declared domain says. *)
  let bounded =
    match member "bounded_domain_fields" json with
    | Some (`List xs) ->
        List.filter_map (function `String s -> Some s | _ -> None) xs
    | _ -> []
  in
  let all_repeats = degeneracy rows in
  let distinct_values path =
    List.fold_left
      (fun acc row ->
        match List.assoc_opt path (leaves "" row) with
        | Some v -> if List.mem v acc then acc else v :: acc
        | None -> acc)
      [] rows
    |> List.length
  in
  let bounded_verdict =
    Atlas_algebra.meet_all
      (List.map
         (fun path ->
           if distinct_values path >= 2 then Atlas_algebra.Conforms
           else
             Atlas_algebra.Nonconforming
               [
                 {
                   row_id = "<atlas>";
                   detail =
                     Printf.sprintf
                       "field %s is declared a bounded-domain field but exhibits                         only one value across all %d rows -- a declared                         enumeration with one member is still a constant"
                       path total_rows;
                 };
               ])
         bounded)
  in
  let repeats =
    List.filter
      (fun (path, _) -> (not (under_obligations path)) && not (List.mem path bounded))
      all_repeats
  in
  let degen_verdict =
    Atlas_algebra.check_degeneracy ~total_rows ~max_repeat repeats
  in

  (* arm 3: the OTP inventory spec section 5 requires *)
  let otp_verdict =
    match member "otp_inventory" json with
    | None ->
        Atlas_algebra.Nonconforming
          [
            {
              row_id = "<atlas>";
              detail =
                "no otp_inventory key -- formal spec section 5 requires the \
                 atlas to enumerate the actual OTP/ERTS installation";
            };
          ]
    | Some inv -> (
        let field k = member k inv |> Option.map str |> Option.join in
        match (opt "--otp-release", opt "--erts-version", opt "--root-dir") with
        | Some r, Some e, Some d ->
            let cmp k observed =
              match field k with
              | Some declared when declared = observed -> Atlas_algebra.Conforms
              | Some declared ->
                  Atlas_algebra.Nonconforming
                    [
                      {
                        row_id = "<atlas>";
                        detail =
                          Printf.sprintf
                            "otp_inventory.%s declares %S but the running \
                             installation reports %S"
                            k declared observed;
                      };
                    ]
              | None ->
                  Atlas_algebra.Nonconforming
                    [
                      {
                        row_id = "<atlas>";
                        detail = "otp_inventory." ^ k ^ " missing";
                      };
                    ]
            in
            Atlas_algebra.meet_all
              [ cmp "otp_release" r; cmp "erts_version" e; cmp "root_dir" d ]
        (* Unmeasured is not matching. The arm reports and does not pass. *)
        | _ ->
            Atlas_algebra.Nonconforming
              [
                {
                  row_id = "<atlas>";
                  detail =
                    "otp_inventory present but NOT VERIFIED: no observed \
                     OTP facts were supplied, so the declaration was compared \
                     against nothing";
                };
              ])
  in

  let verdict =
    Atlas_algebra.meet_all
      (row_verdicts @ [ degen_verdict; bounded_verdict; otp_verdict ])
  in

  (* report *)
  let fs = Atlas_algebra.findings verdict in
  Printf.eprintf "atlas: %s, %d rows, ceiling %d\n" path total_rows max_repeat;
  let worst =
    List.filter (fun (_, n) -> n > max_repeat) repeats |> List.length
  in
  Printf.eprintf "degeneracy: %d of %d leaf fields exceed the ceiling\n" worst
    (List.length repeats);
  List.iter
    (fun (f : Atlas_algebra.finding) ->
      Printf.eprintf "  FAIL %-24s %s\n" f.row_id f.detail)
    fs;
  print_string
    (Yojson.Safe.to_string
       (`Assoc
         [
           ("schema", `String "uos.atlas.conformance.v1");
           ( "status",
             `String (if Atlas_algebra.is_conforming verdict then "PASS" else "FAIL") );
           ("authority", `String "NONE");
           ("atlas_path", `String path);
           ("rows", `Int total_rows);
           ("max_repeat", `Int max_repeat);
           ("leaf_fields", `Int (List.length repeats));
           ("degenerate_fields", `Int worst);
           ("findings", `Int (List.length fs));
           ( "detail",
             `List
               (List.map
                  (fun (f : Atlas_algebra.finding) ->
                    `Assoc
                      [ ("row", `String f.row_id); ("detail", `String f.detail) ])
                  fs) );
         ]));
  print_newline ();
  exit (if Atlas_algebra.is_conforming verdict then 0 else 1)
