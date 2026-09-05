(* The full-fractal controller sweep. One control leg per fractal level, each a
   pure function of a REAL signal; entry points compose the sweep they can
   honestly sense and list the rest as unsensed (no silent caps). Alerts
   observe/refuse/advise only -- no leg touches a parity verdict (R10); the
   evidence lattice and the alert lattice stay orthogonal by construction:
   nothing here has access to the store or to a verdict type. *)

type leg = { level : string; alert : Homeostasis.alert }
type sweep = { legs : leg list; unsensed : (string * string) list }

(* ---------------------------------------------------------------- helpers *)

let family_of contract_id =
  match String.index_opt contract_id '.' with
  | Some i -> String.sub contract_id 0 i
  | None -> contract_id

(* The sensor's memory: per-scenario windows keep only the last [window_size]
   receipts (the c3i last-10 rule). Without this, a recovery note from months
   ago is permanent noise and a pass older than the window still counts as
   regression evidence -- windows forget so alerts stay CURRENT. *)
let window_size = 10

let last_n n items =
  let excess = List.length items - n in
  if excess <= 0 then items
  else
    List.filteri (fun index _ -> index >= excess) items

(* Group (contract, scenario, passed) history into per-scenario chronological
   windows (trimmed to [window_size]), preserving first-seen scenario order. *)
let windows history =
  List.fold_left
    (fun acc (contract_id, scenario_id, passed) ->
      match List.assoc_opt scenario_id acc with
      | Some (family, window) ->
          (scenario_id, (family, window @ [ passed ])) :: List.remove_assoc scenario_id acc
      | None -> (scenario_id, (family_of contract_id, [ passed ])) :: acc)
    [] history
  |> List.rev
  |> List.map (fun (scenario, (family, window)) -> (scenario, (family, last_n window_size window)))

let short_rev revision =
  if String.length revision > 7 then String.sub revision 0 7 else revision

(* ------------------------------------------------------------------- legs *)

let l0_frontier ~counts ~total =
  { level = "L0 product";
    alert = Homeostasis.frontier_alert ~satisfied_counts:counts ~total }

let l1_regressions ~history =
  let regressed =
    List.filter_map
      (fun (scenario, (family, window)) ->
        if Homeostasis.regressed ~window then Some (family, scenario) else None)
      (windows history)
  in
  let alert =
    match regressed with
    | [] -> Homeostasis.Green
    | hits ->
        let by_family =
          List.fold_left
            (fun acc (family, scenario) ->
              match List.assoc_opt family acc with
              | Some scenarios ->
                  (family, scenarios @ [ scenario ]) :: List.remove_assoc family acc
              | None -> (family, [ scenario ]) :: acc)
            [] hits
          |> List.rev
        in
        Homeostasis.P0
          ("regressed slices by family: "
          ^ String.concat "; "
              (List.map
                 (fun (family, scenarios) ->
                   family ^ " (" ^ String.concat ", " scenarios ^ ")")
                 by_family)
          ^ " -- previously passing, latest receipt fails; stop the line")
  in
  { level = "L1 family"; alert }

let l2_flaps ~history =
  let classified =
    List.map
      (fun (scenario, (_family, window)) -> (scenario, Homeostasis.transitions window, window))
      (windows history)
  in
  let flapping = List.filter_map (fun (s, t, _) -> if t >= 2 then Some s else None) classified in
  let single =
    (* One transition ending in a pass: a recovery note. (Ending in a fail is
       the L1 regression's finding -- one authority per signal.) *)
    List.filter_map
      (fun (s, t, window) ->
        if t = 1 && not (Homeostasis.regressed ~window) then Some s else None)
      classified
  in
  let alert =
    if flapping <> [] then
      Homeostasis.P1
        ("flapping scenarios: " ^ String.concat ", " flapping
        ^ " -- quarantine candidates: pin the nondeterminism before trusting their receipts")
    else if single <> [] then
      Homeostasis.P2
        ("recovered scenarios this window: " ^ String.concat ", " single)
    else Homeostasis.Green
  in
  { level = "L2 capability"; alert }

let l3_contract_oracle ~available =
  { level = "L3 contract";
    alert =
      (if available then Homeostasis.Green
       else
         Homeostasis.P1
           "gospel oracle unavailable -- contracts unverifiable (provision gospel or set \
            HERMES_GOSPEL); obligations are not being checked") }

let l4_receipt_currency ~receipts_revision ~current =
  let alert =
    match receipts_revision with
    | None -> Homeostasis.Green (* nothing minted yet: coverage is L6's finding *)
    | Some revision when revision = current -> Homeostasis.Green
    | Some revision ->
        Homeostasis.P2
          (Printf.sprintf
             "latest receipts minted at %s but HEAD is %s -- staleness lead-time: \
              re-verify before trusting Verified"
             (short_rev revision) (short_rev current))
  in
  { level = "L4 fixture"; alert }

let l6_observation_coverage ~recorded ~corpus =
  let alert =
    if recorded = corpus then Homeostasis.Green
    else if recorded < corpus then
      Homeostasis.P2
        (Printf.sprintf "%d of %d corpus scenarios have receipts -- capture the gap"
           recorded corpus)
    else
      Homeostasis.P1
        (Printf.sprintf
           "%d scenarios have receipts but this surface's corpus lists only %d -- its \
            corpus registry is STALE (the drifting-surfaces sensor)"
           recorded corpus)
  in
  { level = "L6 receipt"; alert }

let lx_envelope ~satisfied =
  { level = "LX control";
    alert =
      (if satisfied then Homeostasis.Green
       else
         Homeostasis.P0
           "resource envelope unsatisfied -- refuse before consuming (R13)") }

(* ------------------------------------------------------------ composition *)

let worst sweep = Homeostasis.worst (List.map (fun leg -> leg.alert) sweep.legs)

let render sweep =
  List.map
    (fun leg -> Printf.sprintf "  %-14s %s" leg.level (Homeostasis.describe leg.alert))
    sweep.legs
  @ List.map
      (fun (level, reason) -> Printf.sprintf "  %-14s unsensed -- %s" level reason)
      sweep.unsensed
