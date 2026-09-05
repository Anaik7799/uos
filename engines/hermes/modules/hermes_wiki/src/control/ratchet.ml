(* HW.10.2.1 — see ratchet.mli. The evaluator is an S36 instance: pins are
   the declaration, sensed gauges the observation; unknown gauges fail
   closed in both directions before any verdict is read. *)

type verdict =
  | Held of { gauge : string; at : int }
  | Improved of { gauge : string; previous : int; current : int }
  | Breached of { gauge : string; previous : int; current : int }

let check ~previous ~current =
  if current > previous then
    Error (Printf.sprintf "ratchet breached: %d > %d (the count may only fall)" current previous)
  else Ok ()

let judge ~gauge ~previous ~current =
  if current > previous then Breached { gauge; previous; current }
  else if current < previous then Improved { gauge; previous; current }
  else Held { gauge; at = current }

let parse_pins lines =
  let rec go acc = function
    | [] -> (
        let sorted = List.sort compare (List.rev acc) in
        let rec first_dup = function
          | (a, _) :: (b, _) :: _ when String.equal a b -> Some a
          | _ :: rest -> first_dup rest
          | [] -> None
        in
        match first_dup sorted with
        | Some g -> Error ("duplicate gauge refused (write functionality): " ^ g)
        | None -> Ok sorted)
    | line :: rest -> (
        let l = String.trim line in
        if l = "" || l.[0] = '#' then go acc rest
        else
          match List.filter (fun s -> s <> "") (String.split_on_char ' ' l) with
          | [ gauge; count ] -> (
              match int_of_string_opt count with
              | Some n when n >= 0 -> go ((gauge, n) :: acc) rest
              | _ -> Error ("pin line has no non-negative count: " ^ line))
          | _ -> Error ("malformed pin line (want \"gauge count\"): " ^ line))
  in
  go [] lines

let serialize_pins pins =
  List.sort compare pins |> List.map (fun (g, n) -> Printf.sprintf "%s %d" g n)

(* The S36 instance. *)
module Sub = struct
  type key = string
  type claim = int

  let compare_key = String.compare
  let equal_claim = Int.equal
  let show_key k = k
  let show_claim = string_of_int
end

module R = Reconcile.Make (Sub)

let evaluate ~pins ~gauges =
  match
    R.register (List.map (fun (g, p) -> (g, Some p, Some (fun () -> List.assoc_opt g gauges))) pins)
  with
  | Error e -> Error e
  | Ok t0 -> (
      let t = R.snapshot t0 in
      (* fail closed, both directions: a sensed gauge the pins do not know
         is drift (the Reconcile unknown rule); a pin nobody sensed is
         drift too (its probe answered None). *)
      match R.unknown t ~claimed:(List.map fst gauges) with
      | ghost :: _ -> Error ("sensed gauge has no pin (drift): " ^ ghost)
      | [] -> (
          match List.find_opt (fun (g, _) -> List.assoc_opt g gauges = None) pins with
          | Some (unsensed, _) -> Error ("pinned gauge was not sensed (drift): " ^ unsensed)
          | None ->
              Ok
                (List.sort compare pins
                |> List.map (fun (g, p) ->
                       match R.status t g with
                       | Some current -> judge ~gauge:g ~previous:p ~current
                       | None -> judge ~gauge:g ~previous:p ~current:p))))

let breaches vs = List.filter (function Breached _ -> true | _ -> false) vs

let render = function
  | Held { gauge; at } -> Printf.sprintf "held      %-24s at %d" gauge at
  | Improved { gauge; previous; current } ->
      Printf.sprintf "improved  %-24s %d -> %d (re-pin invited, deliberately)" gauge previous current
  | Breached { gauge; previous; current } ->
      Printf.sprintf "BREACHED  %-24s %d -> %d (the count may only fall)" gauge previous current
