(* Mutation runs — see ops_mutate.mli for the laws. *)

type verdict = Killed of string | Survived | Void of string

type mutant = {
  name : string;
  file : string;
  find : string;
  replace : string;
  expect_killer : string;
}

type outcome = {
  mutant : string;
  verdict : verdict;
  failures : string list;
  duration_ms : float;
}

type report = { outcomes : outcome list; killed : int; survived : int; void : int }

let string_of_verdict = function
  | Killed k -> "KILLED by " ^ k
  | Survived -> "SURVIVED"
  | Void why -> "VOID (" ^ why ^ ")"

let read_file path =
  try
    let ic = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Some (really_input_string ic (in_channel_length ic)))
  with _ -> None

let write_file path content =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc content)

(* LITERAL replacement, not a regex. A regex that matches nothing looks
   exactly like a mutant that survived, and this session lost two runs to
   exactly that before anyone noticed. Literal text either occurs or does
   not, and "does not" is reported as Void. *)
let replace_first ~find ~replace text =
  let n = String.length text and k = String.length find in
  if k = 0 then None
  else
    let rec go i =
      if i + k > n then None
      else if String.sub text i k = find then
        Some (String.sub text 0 i ^ replace ^ String.sub text (i + k) (n - i - k))
      else go (i + 1)
    in
    go 0

let run_capture cmd =
  match Unix.open_process_full cmd (Unix.environment ()) with
  | exception e -> (127, "could not start: " ^ Printexc.to_string e)
  | (out_c, in_c, err_c) as chans ->
      let buf = Buffer.create 4096 in
      let drain ic =
        try while true do Buffer.add_channel buf ic 1 done
        with End_of_file | Sys_error _ -> ()
      in
      Fun.protect
        ~finally:(fun () -> try close_out in_c with Sys_error _ -> ())
        (fun () -> drain out_c; drain err_c);
      let status =
        try Unix.close_process_full chans with Unix.Unix_error _ -> Unix.WEXITED 127
      in
      ((match status with Unix.WEXITED n -> n | Unix.WSIGNALED n | Unix.WSTOPPED n -> 128 + n),
       Buffer.contents buf)

(* The check names a suite reported as failed. The house harness prints
   "FAILED: <name>", so this reads the suite's own words rather than
   guessing which law broke. *)
let failed_checks output =
  String.split_on_char '\n' output
  |> List.filter_map (fun line ->
         let t = String.trim line in
         let p = "FAILED: " in
         let lp = String.length p in
         if String.length t > lp && String.sub t 0 lp = p then
           Some (String.sub t lp (String.length t - lp))
         else None)

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

let run_one ~suite m =
  let started = Unix.gettimeofday () in
  let stop v fails =
    { mutant = m.name; verdict = v; failures = fails;
      duration_ms = (Unix.gettimeofday () -. started) *. 1000.0 }
  in
  match read_file m.file with
  | None -> stop (Void ("cannot read " ^ m.file)) []
  | Some gold -> (
      match replace_first ~find:m.find ~replace:m.replace gold with
      (* the edit that did not apply — a silent no-op reads exactly like a
         surviving mutant, so it is refused rather than scored *)
      | None -> stop (Void "the mutant text was not found in the file") []
      | Some mutated ->
          if mutated = gold then stop (Void "the mutant changed nothing") []
          else
            Fun.protect
              ~finally:(fun () ->
                (* RESTORE, then VERIFY. These files are untracked while an
                   agent is writing them; `git restore` cannot help. *)
                write_file m.file gold;
                match read_file m.file with
                | Some back when back = gold -> ()
                | _ ->
                    prerr_endline
                      ("FATAL: could not restore " ^ m.file
                     ^ " — the working tree is now WRONG. Restore it by hand before continuing.");
                    exit 3)
              (fun () ->
                write_file m.file mutated;
                let build_code, build_out =
                  run_capture "dune build --pkg=disabled 2>&1"
                in
                if build_code <> 0 then
                  (* a mutant that does not compile is not a result *)
                  stop (Void ("did not compile: " ^ String.trim (String.sub build_out 0
                                (min 120 (String.length build_out))))) []
                else
                  let _, out = run_capture (Filename.quote suite ^ " 2>&1") in
                  match failed_checks out with
                  | [] -> stop Survived []
                  | fails ->
                      (* the PREDICTED killer must be among them: a mutant
                         killed by some other check means the prediction
                         was wrong, and that is worth knowing *)
                      if List.exists (fun f -> contains f m.expect_killer) fails then
                        stop (Killed m.expect_killer) fails
                      else
                        stop
                          (Killed (Printf.sprintf "%s (NOT the predicted %S)"
                                     (List.hd fails) m.expect_killer))
                          fails))

let run ~suite mutants =
  (* sequential by design — see the mli: concurrent mutants in one tree
     would overwrite each other's gold copies *)
  let outcomes = List.map (run_one ~suite) mutants in
  let count f = List.length (List.filter f outcomes) in
  { outcomes;
    killed = count (fun o -> match o.verdict with Killed _ -> true | _ -> false);
    survived = count (fun o -> o.verdict = Survived);
    void = count (fun o -> match o.verdict with Void _ -> true | _ -> false) }

let render r =
  let b = Buffer.create 2048 in
  List.iter
    (fun o ->
      Buffer.add_string b
        (Printf.sprintf "  %-34s %s\n" o.mutant (string_of_verdict o.verdict)))
    r.outcomes;
  (* A SURVIVOR IS THE FINDING. It is never softened into "equivalent" —
     that judgment is about intent and belongs to whoever reads this. *)
  if r.survived > 0 then
    Buffer.add_string b
      "\nSurvivors are NOT automatically equivalent mutants. Each one means either\n\
      \  (a) the test proved nothing — write a better killer and re-run, or\n\
      \  (b) the mutant is provably unreachable — say why, in the commit.\n\
       Deciding which is not this tool's job.\n";
  Buffer.add_string b
    (Printf.sprintf "mutate: %d killed, %d survived, %d void\n" r.killed r.survived r.void);
  (* void runs and survivors both mean the table is not yet a result *)
  (Buffer.contents b, if r.survived > 0 || r.void > 0 then 1 else 0)
