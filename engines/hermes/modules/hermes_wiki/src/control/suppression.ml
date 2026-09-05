(* HW.10.2.2 — see suppression.mli. Typed, disclosed, expiring. *)

type t = { kind : string; key : string; reason : string; expires : string option }

let valid_date d =
  String.length d = 10
  && String.for_all (fun c -> c = '-' || (c >= '0' && c <= '9')) d
  && d.[4] = '-' && d.[7] = '-'

let parse lines =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | line :: rest -> (
        let l = String.trim line in
        if l = "" || l.[0] = '#' then go acc rest
        else
          match String.split_on_char '|' l with
          | [ kind; key; reason ] | [ kind; key; reason; "" ] ->
              if kind = "" || key = "" then Error ("suppression without a kind or key: " ^ line)
              else if reason = "" then
                Error ("an unexplained exception is a hole, not an exception: " ^ line)
              else go ({ kind; key; reason; expires = None } :: acc) rest
          | [ kind; key; reason; date ] ->
              if kind = "" || key = "" then Error ("suppression without a kind or key: " ^ line)
              else if reason = "" then
                Error ("an unexplained exception is a hole, not an exception: " ^ line)
              else if not (valid_date date) then
                Error ("expiry is not a YYYY-MM-DD date: " ^ line)
              else go ({ kind; key; reason; expires = Some date } :: acc) rest
          | _ -> Error ("malformed suppression (kind|key|reason|expires?): " ^ line))
  in
  go [] lines

let serialize ts =
  List.map
    (fun t ->
      Printf.sprintf "%s|%s|%s|%s" t.kind t.key t.reason
        (match t.expires with Some d -> d | None -> ""))
    ts

(* THE TYPED LAW: exact kind AND key — never a blanket. *)
let applies ts ~kind ~key =
  List.exists (fun t -> String.equal t.kind kind && String.equal t.key key) ts

(* ISO dates compare lexicographically; the caller reads the clock (R16). *)
let active ts ~today =
  List.filter (fun t -> match t.expires with None -> true | Some d -> String.compare today d <= 0) ts

let expired ts ~today =
  List.filter (fun t -> match t.expires with None -> false | Some d -> String.compare today d > 0) ts

let disclose ts =
  List.map
    (fun t ->
      Printf.sprintf "suppressed %s on %s — %s%s" t.kind t.key t.reason
        (match t.expires with Some d -> " (until " ^ d ^ ")" | None -> " (standing)"))
    ts
