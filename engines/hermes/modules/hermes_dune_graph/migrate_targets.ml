(* One-off migration: ~dependents:[ "string" ] -> ~targets:[ Stanza.lib ].

   TWO GUARDS THE ORIGIN REPOSITORY'S VERSION LACKED, both paid for there:

   1. IT SKIPS ITS OWN MODULE DIRECTORY. The first version searched for the
      literal "~dependents:" and therefore matched the marker string in its own
      source and in cone_shape's, rewriting both into syntax errors. A tool
      that edits source can edit itself.

   2. IT ONLY REWRITES A LITERAL LIST. Where the argument is a computed
      expression the first version consumed everything up to the next ']'
      anywhere in the file, silently destroying unrelated code. Now a
      non-literal argument is reported and left alone.

   Resolution is by this repository's naming convention — test_turn_budget.ml
   covers hermes_harness_turn_budget. Where that fails it falls back to every
   library in the file's own directory, which OVER-approximates: a wide cone is
   speculation but a narrow one hides risk, and a machine choosing on its own
   must never choose the direction that hides risk. Every fallback is listed. *)

let root = "modules"
let self_directory = "modules/hermes_dune_graph"

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let write_file path contents =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc contents)

let rec ml_files directory =
  match Sys.readdir directory with
  | exception _ -> []
  | entries ->
      Array.to_list entries |> List.sort String.compare
      |> List.concat_map (fun entry ->
             let path = Filename.concat directory entry in
             if (try Sys.is_directory path with _ -> false) then ml_files path
             else if Filename.check_suffix entry ".ml" then [ path ]
             else [])

let sanitise = String.map (fun c -> if c = '.' || c = '-' then '_' else c)

let ends_with ~suffix s =
  let n = String.length s and k = String.length suffix in
  k <= n && String.sub s (n - k) k = suffix

let () =
  let libs =
    match Dune_graph.libraries ~root with
    | Error e -> prerr_endline ("REFUSED: " ^ Dune_graph.string_of_parse_error e); exit 1
    | Ok l -> l
  in
  let rewritten = ref 0 and widened = ref [] and computed = ref [] in
  List.iter
    (fun path ->
      (* guard 1: never rewrite the tool's own module *)
      if Filename.dirname path = self_directory then ()
      else begin
        let source = read_file path in
        let marker = "~dependents:" in
        let n = String.length source and k = String.length marker in
        let occurs =
          let rec go i = i + k <= n && (String.sub source i k = marker || go (i + 1)) in
          go 0
        in
        if not occurs then ()
        else begin
          let base = Filename.remove_extension (Filename.basename path) in
          let stem =
            if String.length base > 5 && String.sub base 0 5 = "test_" then
              String.sub base 5 (String.length base - 5)
            else base
          in
          let directory = Filename.dirname path in
          let candidates =
            List.filter
              (fun (l : Dune_graph.library) ->
                l.lib_name = stem || ends_with ~suffix:("_" ^ stem) l.lib_name)
              libs
          in
          let same_dir =
            List.filter
              (fun (l : Dune_graph.library) -> Filename.dirname l.lib_file = directory)
              candidates
          in
          let chosen =
            match same_dir, candidates with
            | [ l ], _ -> [ l.lib_name ]
            | _, [ l ] -> [ l.lib_name ]
            | _ ->
                widened := path :: !widened;
                List.filter_map
                  (fun (l : Dune_graph.library) ->
                    if Filename.dirname l.lib_file = directory then Some l.lib_name else None)
                  libs
          in
          let replacement =
            match chosen with
            | [] -> "~targets:[]"
            | names ->
                Printf.sprintf "~targets:[ %s ]"
                  (String.concat "; " (List.map (fun l -> "Stanza." ^ sanitise l) names))
          in
          let b = Buffer.create n in
          let i = ref 0 and touched = ref false in
          while !i < n do
            if !i + k <= n && String.sub source !i k = marker then begin
              (* guard 2: only a LITERAL list is rewritten *)
              let j = ref (!i + k) in
              while !j < n && (source.[!j] = ' ' || source.[!j] = '\n' || source.[!j] = '\t') do
                incr j
              done;
              if !j < n && source.[!j] = '[' then begin
                let close = ref !j in
                while !close < n && source.[!close] <> ']' do incr close done;
                if !close >= n then begin
                  computed := path :: !computed;
                  Buffer.add_char b source.[!i];
                  incr i
                end
                else begin
                  Buffer.add_string b replacement;
                  touched := true;
                  i := !close + 1
                end
              end
              else begin
                computed := path :: !computed;
                Buffer.add_char b source.[!i];
                incr i
              end
            end
            else (Buffer.add_char b source.[!i]; incr i)
          done;
          if !touched then (write_file path (Buffer.contents b); incr rewritten)
        end
      end)
    (ml_files root);
  Printf.printf "rewritten: %d\nwidened to directory (REVIEW): %d\nnon-literal, left alone (REVIEW): %d\n"
    !rewritten (List.length !widened) (List.length (List.sort_uniq compare !computed));
  List.iter (fun p -> Printf.printf "  non-literal: %s\n" p)
    (List.sort_uniq compare !computed)
