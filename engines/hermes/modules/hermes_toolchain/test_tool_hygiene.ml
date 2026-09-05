(* R19 as a DRIFT GATE over the tool sources.

   Three of R19's four properties are checkable statically, and each
   check exists because the corresponding defect actually shipped here:

     H1  the scrutinee-only exception guard   (crashed every tool)
     H2  a truncating write                   (left documents truncated)
     H3  a stale write-exemption              (an unreviewable hole)

   NOT checked here, and said plainly rather than implied: R19's
   unknown-flag clause. A static scan cannot tell an argv match that
   REFUSES from one that ignores, so that clause is reviewed per tool,
   not gated. This header once claimed an unknown-flag check that did not
   exist — a gate that overstates itself is worse than a smaller honest
   one, because the overstatement is what people rely on.

   A static check is a heuristic, not a proof — it can only see the
   shapes it knows. It is worth having anyway for the same reason
   `test_claude_artifacts` is: the alternative is remembering, and
   remembering is what failed. Every exemption is DECLARED in this file
   with its reason, so an exemption is reviewable rather than invisible. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let read_file path =
  try
    let ic = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Some (really_input_string ic (in_channel_length ic)))
  with _ -> None

let rec ml_files dir acc =
  match Sys.readdir dir with
  | entries ->
      Array.to_list entries |> List.sort compare
      |> List.fold_left
           (fun acc e ->
             let p = Filename.concat dir e in
             if e = "_build" then acc
             else if (try Sys.is_directory p with _ -> false) then ml_files p acc
             else if Filename.check_suffix e ".ml" then p :: acc
             else acc)
           acc
  | exception _ -> acc

(* Scan CODE, not prose. A comment naming a forbidden pattern (this file
   and R19 both quote `match open_in` to explain it) is not a defect, and
   a gate that cannot tell them apart teaches people to stop writing the
   explanation. Nesting is handled, because OCaml comments nest. *)
let strip_comments text =
  let n = String.length text in
  let buf = Buffer.create n in
  let depth = ref 0 in
  let in_string = ref false in
  let i = ref 0 in
  while !i < n do
    let c = text.[!i] in
    if !in_string then begin
      (* a backslash escape cannot end the literal *)
      if c = '\\' && !i + 1 < n then begin
        if !depth = 0 then Buffer.add_string buf (String.sub text !i 2);
        i := !i + 2
      end
      else begin
        if c = '"' then in_string := false;
        if !depth = 0 then Buffer.add_char buf c;
        incr i
      end
    end
    else if c = '"' then begin
      (* STRING LITERALS ARE NOT COMMENTS. Ignoring this made the scanner
         self-defeating: a tool containing "(*" inside a literal drove
         depth to 1 and erased the entire rest of the file, so both gates
         passed VACUOUSLY on exactly the sources most worth reading. *)
      in_string := true;
      if !depth = 0 then Buffer.add_char buf c;
      incr i
    end
    else if !i + 1 < n && c = '(' && text.[!i + 1] = '*' then (incr depth; i := !i + 2)
    else if !i + 1 < n && c = '*' && text.[!i + 1] = ')' && !depth > 0 then
      (decr depth; i := !i + 2)
    else begin
      if !depth = 0 then Buffer.add_char buf c;
      incr i
    end
  done;
  Buffer.contents buf

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

(* The tool surface: what an operator runs against real state. *)
let tool_files () =
  List.sort compare
    (ml_files "modules/hermes_wiki/src/tools" [] @ ml_files "modules/hermes_toolchain" [])
  |> List.filter (fun p -> not (contains p "test_"))

(* DECLARED exemptions, each with its reason. An exemption without a
   reason is a hole; an exemption with one is a decision. *)
let write_exempt =
  [ (* wiki_dashboard writes a GENERATED artifact under state/, which is
       gitignored and rebuilt in full by every run. Nothing tracked
       depends on a partial one. *)
    "modules/hermes_wiki/src/tools/wiki_dashboard.ml" ]

(* The two exemptions that used to sit here — gen_render_baseline and
   wiki_audit --pin — are GONE because both now write atomically, which
   is the correct resolution of an exemption. One of their stated reasons
   was also simply false: gen_render_baseline does not write the pin
   file, it writes the render baseline, and a partial one was NOT caught
   by the audit's own drift gauge. An exemption whose reason is wrong is
   worse than no exemption, because it reads as though someone checked. *)

let () =
  let tools = tool_files () in
  check "the tool surface is non-empty (a vacuous gate is not a gate)" (fun () ->
      List.length tools >= 5);
  check "H1 no tool uses the scrutinee-only exception guard on open_in" (fun () ->
      List.for_all
        (fun p ->
          match read_file p with
          | None ->
              (* an UNREADABLE source is not a passing source *)
              Printf.printf "  %s: unreadable, cannot be checked\n" p;
              false
          | Some raw ->
              let text = strip_comments raw in
              (* `match open_in ... with | ic -> BODY | exception _` guards
                 the scrutinee only: an exception raised in BODY escapes.
                 The guarded forms are `try ... with` or Fun.protect. *)
              let bad = contains text "match open_in" in
              if bad then Printf.printf "  %s: scrutinee-only open_in guard\n" p;
              not bad)
        tools);
  check "H2 a tool that writes does so atomically, or declares an exemption"
    (fun () ->
      List.for_all
        (fun p ->
          match read_file p with
          | None ->
              (* an UNREADABLE source is not a passing source *)
              Printf.printf "  %s: unreadable, cannot be checked\n" p;
              false
          | Some raw ->
              let text = strip_comments raw in
              if not (contains text "open_out") then true
              else if List.mem p write_exempt then true
              else if contains text "Sys.rename" then true
              else begin
                Printf.printf "  %s: writes with open_out, no rename, no exemption\n" p;
                false
              end)
        tools);
  check "H3 every declared write-exemption names a REAL file (no stale entries)"
    (fun () ->
      List.for_all
        (fun p ->
          Sys.file_exists p
          || (Printf.printf "  stale exemption: %s\n" p; false))
        write_exempt);
  check "meta-falsification: H1's pattern IS detected when present" (fun () ->
      contains "let f p = match open_in p with ic -> ic | exception _ -> raise Exit"
        "match open_in");
  check "meta-falsification: H2 sees a write that has no rename" (fun () ->
      let sample = "let () = let oc = open_out \"x\" in output_string oc \"y\"" in
      contains sample "open_out" && not (contains sample "Sys.rename"))

let () =
  Printf.printf "tool_hygiene: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_tool_hygiene" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.toolchain_core ]);
  exit (Suite_telemetry.exit_code self)
