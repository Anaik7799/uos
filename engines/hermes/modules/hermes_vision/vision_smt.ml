(* Z3 proofs for the vision state machines. See the .mli. *)

type verdict = Discharged of string | Refuted of string | Unavailable of string

let verdict_name = function
  | Discharged _ -> "DISCHARGED" | Refuted _ -> "REFUTED" | Unavailable _ -> "UNAVAILABLE"

let z3_available () =
  String.split_on_char ':' (try Sys.getenv "PATH" with Not_found -> "")
  |> List.exists (fun d -> d <> "" && Sys.file_exists (Filename.concat d "z3"))

(* Phases as integers, in the order Vision_restart declares them. *)
let encoding =
  {|(declare-fun ph (Int) Int)
; 0 Draining  1 Starting  2 Gating  3 Promoted  4 RolledBack
(assert (= (ph 0) 0))
|}

(* The transition relation, transcribed from Vision_restart.legal_transition. *)
let step i =
  Printf.sprintf
    "(assert (or (and (= (ph %d) 0) (= (ph %d) 1)) (and (= (ph %d) 1) (= (ph %d) 2)) (and (= \
     (ph %d) 2) (= (ph %d) 3)) (and (= (ph %d) 2) (= (ph %d) 4)) (and (= (ph %d) 1) (= (ph %d) \
     4)) (and (= (ph %d) 0) (= (ph %d) 4)) (and (= (ph %d) (ph %d)))))\n"
    i (i + 1) i (i + 1) i (i + 1) i (i + 1) i (i + 1) i (i + 1) i (i + 1)

let unrolled depth =
  let b = Buffer.create 1024 in
  Buffer.add_string b encoding;
  for i = 0 to depth - 1 do Buffer.add_string b (step i) done;
  Buffer.contents b

let promoted_requires_gating ~depth =
  (* the NEGATION: a run that reaches Promoted having never been in
     Gating. unsat means no such path exists at this depth. *)
  let b = Buffer.create 1024 in
  Buffer.add_string b (unrolled depth);
  Buffer.add_string b (Printf.sprintf "(assert (= (ph %d) 3))\n" depth);
  for i = 0 to depth do
    Buffer.add_string b (Printf.sprintf "(assert (not (= (ph %d) 2)))\n" i)
  done;
  Buffer.add_string b "(check-sat)\n";
  Buffer.contents b

let reachability_control ~depth =
  (* a trace that MUST exist: Draining .. Promoted, having gated *)
  let b = Buffer.create 1024 in
  Buffer.add_string b (unrolled depth);
  Buffer.add_string b (Printf.sprintf "(assert (= (ph %d) 3))\n" depth);
  Buffer.add_string b "(check-sat)\n";
  Buffer.contents b

let run_z3 smt =
  let tmp = Filename.temp_file "vision-smt" ".smt2" in
  let oc = open_out tmp in
  output_string oc smt;
  close_out oc;
  let ic = Unix.open_process_in (Printf.sprintf "timeout 60 z3 -smt2 %s 2>&1" (Filename.quote tmp)) in
  let b = Buffer.create 256 in
  (try while true do Buffer.add_channel b ic 1 done with End_of_file -> ());
  ignore (try Unix.close_process_in ic with Unix.Unix_error _ -> Unix.WEXITED 127);
  (try Sys.remove tmp with _ -> ());
  String.trim (Buffer.contents b)

let contains hay needle =
  let n = String.length hay and k = String.length needle in
  let rec go i = i + k <= n && (String.sub hay i k = needle || go (i + 1)) in
  k > 0 && go 0

let check smt =
  if not (z3_available ()) then Unavailable "z3 is not on PATH"
  else
    let out = run_z3 smt in
    if contains out "unsat" then Discharged out
    else if contains out "sat" then Refuted out
    else Unavailable ("z3 gave no verdict: " ^ out)

let prove_restart_machine ?(depth = 6) () =
  match check (promoted_requires_gating ~depth) with
  | Unavailable w -> Unavailable w
  | Refuted out -> Refuted ("a path reaches Promoted without gating: " ^ out)
  | Discharged _ -> (
      (* NON-VACUITY. Every query over a contradictory encoding is
         unsat, so an unsat alone proves nothing about the design. *)
      match check (reachability_control ~depth) with
      | Refuted _ ->
          Discharged
            (Printf.sprintf
               "no path of depth %d reaches Promoted without Gating, and the control trace is \
                reachable (encoding is not vacuous)"
               depth)
      | Discharged _ ->
          Unavailable
            "the control trace is UNSAT — the encoding is contradictory, so the discharge above \
             proves nothing"
      | Unavailable w -> Unavailable w)
