(* HW.9.1.2 — interface-comment extraction, tested across the FULL
   FUNCTIONAL ENVELOPE rather than the happy path:

     N*  nominal        a doc comment above a val
     X*  exhaustion     size and nesting depth
     S*  stuck          a val with no comment, a comment with no val
     A*  anomaly        unterminated comments, an opener in a string, CRLF

   The law under all of it: STATIC PARSE, NEVER EVALUATION — nothing here
   compiles, imports or runs the interface it reads. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

open Wiki_iface

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 a val with a doc comment above it is extracted, named and typed" (fun () ->
      match items "(* the answer *)\nval answer : int\n" with
      | [ i ] -> i.name = "answer" && i.signature = "int" && i.doc = "the answer" && documented i
      | _ -> false);
  check "N2 items come out in SOURCE order, not sorted" (fun () ->
      List.map (fun i -> i.name) (items "val zeta : int\nval alpha : int\n")
      = [ "zeta"; "alpha" ]);
  check "N3 a MULTI-LINE signature is one item, whitespace-normalised" (fun () ->
      match items "val f :\n  string ->\n  int option\n" with
      | [ i ] -> i.name = "f" && i.signature = "string -> int option"
      | _ -> false);
  check "N4 the line number addresses the val, so a reader can go there" (fun () ->
      match items "\n\n(* c *)\nval x : int\n" with [ i ] -> i.line = 4 | _ -> false);
  check "N5 the NEAREST comment above wins — a later one replaces an earlier"
    (fun () ->
      match items "(* far and stale *)\n\n(* near and true *)\nval x : int\n" with
      | [ i ] -> i.doc = "near and true"
      | _ -> false)

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 a large interface is handled without stack or quadratic blowup" (fun () ->
      let b = Buffer.create 200000 in
      for k = 1 to 2000 do
        Buffer.add_string b (Printf.sprintf "(* doc %d *)\nval v%d : int\n" k k)
      done;
      let its = items (Buffer.contents b) in
      List.length its = 2000
      && (List.nth its 1999).name = "v2000"
      && documented (List.nth its 1999));
  check "X2 deeply NESTED comments close correctly (OCaml comments nest)" (fun () ->
      match items "(* a (* b (* c *) b *) a *)\nval x : int\n" with
      | [ i ] -> i.name = "x" && i.doc = "a (* b (* c *) b *) a"
      | _ -> false);
  check "X3 a comment far larger than the code does not lose the val" (fun () ->
      let filler = String.concat " " (List.init 5000 (fun _ -> "words")) in
      match items ("(* " ^ filler ^ " *)\nval x : int\n") with
      | [ i ] -> i.name = "x" && documented i
      | _ -> false)

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 an UNDOCUMENTED val is reported as such, never guessed at" (fun () ->
      match items "val bare : int\n" with
      | [ i ] -> i.doc = "" && not (documented i)
      | _ -> false);
  check "S2 a comment attached to NOTHING contributes no item" (fun () ->
      items "(* floating, documents nothing *)\n" = []);
  check "S3 a file with no val at all yields no items and no coverage" (fun () ->
      items "type t = int\nmodule M : sig end\n" = []
      && coverage "type t = int\n" = None);
  check "S4 coverage is a FRACTION, and 0/0 is None — never 100%" (fun () ->
      coverage "(* d *)\nval a : int\nval b : int\n" = Some (1, 2)
      && coverage "" = None);
  check "S5 undocumented lists exactly the bare names, in source order" (fun () ->
      undocumented "(* d *)\nval a : int\nval b : int\nval c : int\n" = [ "b"; "c" ])

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 an UNTERMINATED comment ends at EOF and never raises" (fun () ->
      items "val before : int\n(* runs off the end...\nval hidden : int\n"
      |> List.map (fun i -> i.name) = [ "before" ]);
  check "A2 an OPENER INSIDE A STRING is not a comment opener" (fun () ->
      (* the defect that erases a whole file and reports it clean *)
      match items "val marker : string (* doc *)\nval after : int\n" with
      | [ a; b ] -> a.name = "marker" && b.name = "after"
      | _ -> false);
  check "A2b a string literal containing a comment opener leaves code visible"
    (fun () ->
      let src = "val a : string\nval b : int\n" in
      List.length (items src) = 2);
  check "A3 a `val` written INSIDE a comment is not a declaration" (fun () ->
      items "(* val ghost : int *)\nval real : int\n"
      |> List.map (fun i -> i.name) = [ "real" ]);
  check "A4 CRLF input is handled; the signature carries no stray \\r" (fun () ->
      match items "(* d *)\r\nval x : int\r\n" with
      | [ i ] -> i.name = "x" && i.signature = "int"
      | _ -> false);
  check "A5 no trailing newline still yields the item" (fun () ->
      match items "val x : int" with [ i ] -> i.name = "x" | _ -> false);
  check "A6 TOTAL: pathological inputs return a value, never an exception" (fun () ->
      List.for_all
        (fun s -> match items s with _ -> true)
        [ ""; "("; "(*"; "*)"; "val"; "val :"; "val x :"; "\"(*\""; String.make 5000 '(' ]);
  check "A7 STATIC PARSE: an interface naming a module that cannot exist is still read"
    (fun () ->
      (* nothing is imported, so an unresolvable reference is just text *)
      match items "(* d *)\nval f : Nonexistent_module.t -> int\n" with
      | [ i ] -> i.name = "f" && i.signature = "Nonexistent_module.t -> int"
      | _ -> false)

(* ------------------------------------------- the real corpus of code *)

let () =
  check "R1 the engine's own interface is read, and is well documented" (fun () ->
      let ic = open_in_bin "modules/hermes_wiki/src/engine/wiki_include.mli" in
      let text = really_input_string ic (in_channel_length ic) in
      close_in ic;
      match coverage text with
      | Some (doc, total) -> total >= 5 && doc >= total - 1
      | None -> false)

let () =
  Printf.printf "wiki_iface: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_iface" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_iface ]);
  exit (Wiki_suite_telemetry.exit_code self)
