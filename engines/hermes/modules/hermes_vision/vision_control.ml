(* The vision control plane. See vision_control.mli for the laws. *)

type action = Status | Restart

let action_name = function Status -> "status" | Restart -> "restart"

(* Exact names only. No trimming, no case folding, no prefix match: a
   control plane generous about spelling eventually restarts something
   on a typo. *)
let parse_action = function
  | "status" -> Ok Status
  | "restart" -> Ok Restart
  | other -> Error ("unknown action: " ^ other)

type component = {
  name : string;
  status : unit -> string;
  restart : unit -> (string, string) result;
}

let key_prefix = "hermes/vision/control"
let key_for name = key_prefix ^ "/" ^ name

let escape s =
  let b = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let err reason = Printf.sprintf {|{"ok":false,"error":"%s"}|} (escape reason)
let ok_json body = Printf.sprintf {|{"ok":true,%s}|} body

let component_of_key comps key =
  let leaf = Filename.basename key in
  List.find_opt (fun c -> c.name = leaf) comps

(* The payload is `{"action":"..."}`. Extracted by hand because the whole
   grammar is one field, and refusing anything else is cheaper and safer
   than accepting a general document and hoping the extra keys are
   harmless. *)
let action_field payload =
  let needle = "\"action\"" in
  let n = String.length payload and k = String.length needle in
  let rec find i = if i + k > n then None else if String.sub payload i k = needle then Some (i + k) else find (i + 1) in
  match find 0 with
  | None -> None
  | Some after ->
      let rec skip i =
        if i >= n then None
        else match payload.[i] with ' ' | ':' | '\t' -> skip (i + 1) | '"' -> Some (i + 1) | _ -> None
      in
      (match skip after with
       | None -> None
       | Some start ->
           let rec till i = if i >= n then None else if payload.[i] = '"' then Some i else till (i + 1) in
           (match till start with
            | None -> None
            | Some stop -> Some (String.sub payload start (stop - start))))

let dispatch comps key payload =
  match component_of_key comps key with
  | None ->
      (* fail-closed: never guess which component was meant *)
      err (Printf.sprintf "no such component in %s (known: %s)" key
             (String.concat "," (List.map (fun c -> c.name) comps)))
  | Some c -> (
      match action_field payload with
      | None -> err "payload has no \"action\" field"
      | Some raw -> (
          match parse_action raw with
          | Error e -> err e
          | Ok Status -> ok_json (Printf.sprintf {|"component":"%s","action":"status",%s|} (escape c.name) (c.status ()))
          | Ok Restart -> (
              match c.restart () with
              | Ok detail ->
                  ok_json
                    (Printf.sprintf {|"component":"%s","action":"restart","state":"%s"|}
                       (escape c.name) (escape detail))
              | Error e -> err ("restart failed: " ^ e))))

let serve comps =
  Hermes_zenoh.serve_queryable ~keyexpr:(key_prefix ^ "/*")
    ~callback:(fun key payload -> dispatch comps key payload)

(* Poll /whoami until the expected identity answers, or give up.

   THIS IS THE WHOLE DIFFICULTY OF A SHARED-PORT SWAP. With SO_REUSEPORT
   two instances hold one port and the kernel load-balances, so a plain
   health check may be answered by the OLD instance and pass regardless
   of whether the replacement works at all — a gate that cannot fail,
   which is the defect this repository keeps finding in other people's
   code. Requiring the NEW id to answer is what makes the gate real, and
   polling is required because the kernel may route the first several
   probes to the old one even when both are healthy. *)
let contains hay needle =
  let n = String.length hay and k = String.length needle in
  let rec go i = i + k <= n && (String.sub hay i k = needle || go (i + 1)) in
  k = 0 || go 0

let awaits_identity ~host ~port ~id ~attempts =
  let rec go n =
    if n <= 0 then false
    else
      match Vision_controller.http_get ~host ~port ~path:"/whoami" with
      | Ok (_, body) when contains body ("\"id\":\"" ^ id ^ "\"") -> true
      | Ok _ | Error _ -> Unix.sleepf 0.2; go (n - 1)
  in
  go attempts

(* The server is where the zero-downtime shape genuinely applies: two
   instances CAN share a listening socket, so the old one keeps serving
   through the gate and no client meets a closed port.

   Note where draining sits. For the contended encoder the drain must
   come FIRST, because the two cannot coexist. Here it comes LAST — the
   old instance serves throughout and is only drained once the
   replacement has been seen to answer. The phase names are the same;
   what changes is which operation carries the draining, and that is a
   property of the resource, not of the restart. *)
let server_component ~host ~port ~dir ~spawn ~stop_old ~next_id =
  { name = "server";
    status =
      (fun () ->
        let reachable =
          match Vision_controller.http_get ~host ~port ~path:"/whoami" with
          | Ok (status, body) -> Printf.sprintf "%s %s" (String.trim status) (String.trim body)
          | Error e -> "unreachable: " ^ e
        in
        Printf.sprintf {|"port":%d,"dir":"%s","whoami":"%s"|} port (escape dir)
          (escape reachable));
    restart =
      (fun () ->
        let id = next_id () in
        let spawned = ref None in
        let ops =
          { Vision_restart.drain =
              (* NOTHING to drain yet: the old instance must keep serving
                 through the gate. That is the entire point. *)
              (fun () -> ());
            start = (fun () ->
              match spawn ~id with
              | Error e -> Error e
              | Ok pid -> spawned := Some pid; Ok pid);
            health = (fun _ -> awaits_identity ~host ~port ~id ~attempts:25);
            (* only now does the old one go *)
            retire = (fun () -> stop_old ());
            kill_new =
              (fun pid -> try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ()) }
        in
        let o = Vision_restart.execute ops in
        match o.Vision_restart.final with
        | Vision_restart.Promoted ->
            Ok (Printf.sprintf "swapped to %s (pid %s), no connection refused"
                  id
                  (match !spawned with Some p -> string_of_int p | None -> "?"))
        | Vision_restart.Rolled_back why ->
            (* the old instance was never drained, so it is still serving *)
            Error ("swap rolled back; the PREVIOUS instance is still serving: " ^ why)
        | other -> Error ("swap ended in a non-terminal phase: " ^ Vision_restart.phase_name other))
  }

let ffmpeg_component ~intent ~dir ~handle =
  { name = "ffmpeg";
    status =
      (fun () ->
        (* MEASURED on every call, never cached: a status that reports
           what was true at startup is how a dead component stays green. *)
        let h = !handle in
        let alive = Vision_controller.running h in
        let pkg = Vision_controller.probe_package ~dir in
        Printf.sprintf {|"pid":%d,"running":%b,"package":"%s","intent":"%s"|}
          (Vision_controller.pid h) alive
          (escape (Vision_controller.verdict_name pkg.Vision_controller.verdict))
          (escape (Vision_intent.describe intent)));
    restart =
      (fun () ->
        (* Graceful restart through Vision_restart, WITH ONE HONEST
           DEPARTURE from the zero-downtime shape.

           Zero downtime requires the old and new instances to coexist
           while the gate runs. An encoder cannot: two ffmpeg processes
           writing one playlist is the `start_pipeline / Provided_unsafe`
           unsafe control action in Vision_safety, and it corrupts the
           stream rather than merely wasting a process. They contend for
           an exclusive resource, so the old one must go before the new
           one starts.

           That means this restart HAS A GAP, and pretending otherwise
           would be the lie. What the gate still buys is the thing that
           matters more: a replacement is not accepted merely because it
           spawned. If it fails the gate we say so and the caller knows
           the pipeline is down, rather than being told a restart
           succeeded while nothing is producing segments.

           The server is the component where the zero-downtime shape does
           apply, because two servers can share a listening socket. *)
        let started = ref None in
        let ops =
          { Vision_restart.drain =
              (* for a contended resource the drain IS the retirement *)
              (fun () -> Vision_controller.stop !handle);
            start =
              (fun () ->
                match Vision_controller.start intent with
                | Error e -> Error e
                | Ok h -> started := Some h; Ok (Vision_controller.pid h));
            health =
              (fun _ ->
                match !started with
                | None -> false
                | Some h ->
                    (* NOT "is the process running" — that is the Play
                       hazard in another costume. The gate asks the
                       question the stage probe asks: is it producing
                       segments a player could fetch? *)
                    Vision_controller.running h
                    && (match (Vision_controller.probe_package ~dir).Vision_controller.verdict with
                        | Vision_controller.Live _ -> true
                        | Vision_controller.Absent _ | Vision_controller.Unknown _ -> false));
            retire = (fun () -> match !started with Some h -> handle := h | None -> ());
            kill_new = (fun _ -> match !started with Some h -> Vision_controller.stop h | None -> ())
          }
        in
        let outcome = Vision_restart.execute ops in
        match outcome.Vision_restart.final with
        | Vision_restart.Promoted ->
            Ok (Printf.sprintf "restarted, pid %d" (Vision_controller.pid !handle))
        | Vision_restart.Rolled_back why ->
            (* the gap is disclosed: the caller must know the pipeline is
               NOT running rather than infer it *)
            Error ("restart rolled back and the pipeline is DOWN: " ^ why)
        | other -> Error ("restart ended in a non-terminal phase: " ^ Vision_restart.phase_name other)) }
