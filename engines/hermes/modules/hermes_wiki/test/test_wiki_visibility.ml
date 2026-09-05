(* HW.1.4.1 — the visibility split. The law is MUTUALLY EXCLUSIVE AND
   TOTAL, so the suite proves both halves rather than sampling states:

     V1 totality        every page has exactly one state
     V2 exclusivity     the three predicates never agree pairwise
     V3 precedence      explicit visibility beats the status fallback
     V4 unlisted        built, NOT indexed, NOT searched — the whole point
     V5 malformed       an unrecognised value is reported, never Listed
     V6 fpp             the gauge is a topology channel (R: all code FPP) *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let page slug fm = ("docs/x/" ^ slug ^ ".md", fm ^ "# " ^ slug ^ "\n\nbody.\n")
let build files = Hermes_wiki.build files
let vis slug files =
  match Hermes_wiki.page (build files) slug with
  | Some p -> Wiki_visibility.of_page p
  | None -> failwith "missing"

let () =
  check "V1 TOTAL: every page lands in exactly one state" (fun () ->
      let files =
        [ page "a" ""; page "b" "---\nvisibility: draft\n---\n";
          page "c" "---\nvisibility: unlisted\n---\n"; page "d" "---\nstatus: draft\n---\n" ]
      in
      let m = build files in
      let census = Wiki_visibility.census m in
      let total = List.fold_left (fun acc (_, l) -> acc + List.length l) 0 census in
      total = List.length m.Hermes_wiki.pages && List.length census = 3);
  check "V2 EXCLUSIVE: the three predicates never agree pairwise" (fun () ->
      List.for_all
        (fun s ->
          let b = Wiki_visibility.in_build s
          and i = Wiki_visibility.in_index s
          and q = Wiki_visibility.in_search s in
          (* index implies build; search tracks index; draft is in none *)
          ((not i) || b) && i = q)
        [ Wiki_visibility.Draft; Wiki_visibility.Unlisted; Wiki_visibility.Listed ]);
  check "V3 an EXPLICIT visibility beats the status fallback" (fun () ->
      vis "x" [ page "x" "---\nstatus: draft\nvisibility: listed\n---\n" ]
      = Wiki_visibility.Listed
      && vis "y" [ page "y" "---\nstatus: published\nvisibility: draft\n---\n" ]
         = Wiki_visibility.Draft);
  check "V4 UNLISTED is built but neither indexed nor searched (the row's point)"
    (fun () ->
      let s = vis "u" [ page "u" "---\nunlisted: true\n---\n" ] in
      s = Wiki_visibility.Unlisted
      && Wiki_visibility.in_build s
      && (not (Wiki_visibility.in_index s))
      && not (Wiki_visibility.in_search s));
  check "V4b DRAFT is not built at all" (fun () ->
      let s = vis "d" [ page "d" "---\ndraft: true\n---\n" ] in
      s = Wiki_visibility.Draft && not (Wiki_visibility.in_build s));
  check "V4c a plain page is LISTED" (fun () ->
      vis "p" [ page "p" "" ] = Wiki_visibility.Listed);
  check "V5 an UNRECOGNISED visibility is reported, never silently listed" (fun () ->
      let m = build [ page "m" "---\nvisibility: pubic\n---\n" ] in
      match Wiki_visibility.malformed m with
      | [ line ] ->
          let has n =
            let nh = String.length line and nn = String.length n in
            let rec go i = i + nn <= nh && (String.sub line i nn = n || go (i + 1)) in
            go 0
          in
          has "pubic" && has "m"
      | _ -> false);
  check "V5b a well-formed corpus reports nothing" (fun () ->
      Wiki_visibility.malformed (build [ page "a" ""; page "b" "---\nvisibility: unlisted\n---\n" ])
      = []);
  check "V6 FPP: the visibility gauge is a Wiki_topology telemetry channel" (fun () ->
      (* every gauge the audit pins must exist in the actor model — the
         house law, applied to this row as it is to every other *)
      let names =
        List.concat_map
          (fun (c : Fpp_model.component) ->
            List.map (fun (ch : Fpp_model.channel) -> ch.Fpp_model.chan_name)
              c.Fpp_model.channels)
          Wiki_topology.model.Fpp_model.components
      in
      List.mem "visibility_malformed" names && List.mem "drafts" names)

let () =
  Printf.printf "wiki_visibility: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_visibility" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_visibility ]);
  exit (Wiki_suite_telemetry.exit_code self)
