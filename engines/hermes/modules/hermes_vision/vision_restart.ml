(* Graceful restart. See the .mli: the ORDER is the whole design. *)

type phase =
  | Draining
  | Starting
  | Gating
  | Promoted
  | Rolled_back of string

let phase_name = function
  | Draining -> "Draining" | Starting -> "Starting" | Gating -> "Gating"
  | Promoted -> "Promoted" | Rolled_back _ -> "RolledBack"

(* No Starting -> Promoted edge. A replacement that was never gated has
   not been shown to work, and allowing that edge is how the gate gets
   skipped under time pressure. *)
let legal_transition a b =
  match (a, b) with
  | Draining, Starting -> true
  | Starting, Gating -> true
  | Gating, Promoted -> true
  | Gating, Rolled_back _ -> true
  (* a failure during start or drain rolls back without ever gating *)
  | Starting, Rolled_back _ -> true
  | Draining, Rolled_back _ -> true
  | _ -> false

let terminal = function Promoted | Rolled_back _ -> true | _ -> false

let well_formed = function
  | [] -> false
  | first :: _ as chain ->
      let rec contiguous = function
        | a :: (b :: _ as rest) -> legal_transition a b && contiguous rest
        | [ last ] -> terminal last
        | [] -> false
      in
      first = Draining && contiguous chain

type ops = {
  drain : unit -> unit;
  start : unit -> (int, string) result;
  health : int -> bool;
  retire : unit -> unit;
  kill_new : int -> unit;
}

type outcome = { trace : phase list; final : phase; old_retired : bool; new_pid : int option }

let succeeded o = o.final = Promoted

let execute ops =
  let trace = ref [ Draining ] in
  let add p = trace := p :: !trace in
  let finish final old_retired new_pid =
    add final;
    { trace = List.rev !trace; final; old_retired; new_pid }
  in
  match ops.drain () with
  | exception e -> finish (Rolled_back ("drain raised: " ^ Printexc.to_string e)) false None
  | () -> (
      add Starting;
      match ops.start () with
      | exception e ->
          (* the old instance was drained but NEVER retired, so it is
             still the thing serving; nothing to roll back *)
          finish (Rolled_back ("start raised: " ^ Printexc.to_string e)) false None
      | Error why -> finish (Rolled_back ("start failed: " ^ why)) false None
      | Ok pid -> (
          add Gating;
          match ops.health pid with
          | exception e ->
              ops.kill_new pid;
              finish (Rolled_back ("health raised: " ^ Printexc.to_string e)) false (Some pid)
          | false ->
              (* ROLLBACK. The old instance is never retired, so it keeps
                 serving; the replacement is stopped so it does not
                 linger holding the port beside it. *)
              ops.kill_new pid;
              finish (Rolled_back "the replacement did not pass the health gate") false (Some pid)
          | true ->
              (* and ONLY now *)
              ops.retire ();
              finish Promoted true (Some pid)))

let digest_of_file path =
  try Some (Digest.to_hex (Digest.file path)) with _ -> None

(* Unknown answers FALSE. The running instance is known to work, and
   restarting on an unreadable image trades a working service for a
   guess. *)
let image_changed ~running ~current =
  match (running, current) with
  | Some a, Some b -> a <> b
  | _ -> false

let render o =
  let b = Buffer.create 256 in
  Buffer.add_string b
    (Printf.sprintf "restart: %s\n  trace: %s\n"
       (phase_name o.final)
       (String.concat " -> " (List.map phase_name o.trace)));
  (match o.final with
   | Rolled_back why -> Buffer.add_string b (Printf.sprintf "  cause: %s\n" why)
   | _ -> ());
  Buffer.add_string b
    (Printf.sprintf "  old retired: %b   new pid: %s\n" o.old_retired
       (match o.new_pid with Some p -> string_of_int p | None -> "none"));
  Buffer.contents b

let supervise_once ~running ~image ~restart =
  let current = digest_of_file image in
  if not (image_changed ~running ~current) then None
  else
    match restart () with
    | Error e -> Some (Stdlib.Error e)
    | Ok detail -> (
        (* carry the digest forward, or the next tick sees the same
           change and restarts again, forever *)
        match current with
        | Some d -> Some (Stdlib.Ok (d, detail))
        | None -> Some (Stdlib.Error "restarted but the new image could not be digested"))
