(* Independent finite oracle for the executable Lean reference, not a clone of
   the product probe. Uses explicit rejecting reasons and an exit/profile table.
   Its finite agreement does not establish implementation/model refinement. *)
let bool = function "true" -> true | "false" -> false | _ -> failwith "bad bool"

let () =
  if Array.length Sys.argv <> 2 then failwith "usage: admission-reference-check LEAN_CSV";
  let ic = open_in Sys.argv.(1) in
  let seen = Hashtbl.create 31_104 in
  let total = ref 0 and accepted = ref 0 and disagreements = ref 0 in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    try while true do
      let line = input_line ic in
      match String.split_on_char ',' line with
      | [target; profile; candidate; boot; finished; host_exit; guest_exit;
         success; abort; authentic; complete; verdict] ->
          let target = int_of_string target and profile = int_of_string profile in
          let c = int_of_string candidate and b = int_of_string boot in
          let finished = int_of_string finished in
          let age = 10 - finished in
          let host = int_of_string host_exit and guest = int_of_string guest_exit in
          let success = bool success and abort = bool abort in
          let authentic = bool authentic and complete = bool complete in
          if not (List.mem target [0;1;2] && List.mem profile [0;1]
            && List.mem c [0;1;2] && List.mem b [0;1;2]
            && List.mem finished [7;8;10;11] && List.mem host [0;83;255]
            && List.mem guest [-1;0;1]) then failwith "case outside declared finite universe";
          let key = (target, profile, c, b, finished, host, guest, success, abort, authentic, complete) in
          if Hashtbl.mem seen key then failwith "duplicate finite case";
          Hashtbl.add seen key ();
          let expected_exit = List.assoc (target, profile)
            [((0,0),0);((1,0),0);((2,0),83);((0,1),255);((1,1),255);((2,1),83)] in
          let reasons = [
            ("candidate", c <> 1); ("boot", b <> 1);
            ("future", age < 0); ("stale", age > 2);
            ("unauthenticated", not authentic);
            ("incomplete_output", not complete);
            ("wrong_host_exit", host <> expected_exit);
            ("wrong_outcome", if profile = 0 then
                guest <> 0 || not success || abort
              else guest = 0 || success || not abort);
          ] in
          let rejection = List.exists snd reasons in
          let expected = not rejection in
          incr total;
          if expected then incr accepted;
          if expected <> bool verdict then (
            incr disagreements;
            Printf.eprintf "disagreement: %s\n" line)
      | _ when not (String.contains line ',') -> () (* Lean #print axioms *)
      | _ -> failwith ("malformed finite case: " ^ line)
    done with End_of_file -> ());
  Printf.printf "{\"cases\":%d,\"accepted\":%d,\"rejected\":%d,\"disagreements\":%d}\n"
    !total !accepted (!total - !accepted) !disagreements;
  if !total <> 31_104 || !accepted = 0 || !accepted = !total || !disagreements <> 0 then exit 1
