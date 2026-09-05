(* Task 1 prerequisite: the neutral FPP window authority.

   Two kinds of check live here, and the difference matters.

   The AGREEMENT checks compare the registry against the five real
   models. They pass the moment the registry states the truth, which it
   does, because its values were moved from those projections rather than
   invented.

   The SOLE-AUTHORITY checks assert that the projections no longer carry
   their own base literals. Those are the behavioral RED for this task.
   A registry that merely agrees with five independent literal sets is a
   sixth copy, not an authority — the drift it exists to prevent can
   still happen in any of the five, and the registry would agree with
   whichever it was written from. Only when each projection LOOKS THE
   VALUE UP does one place state a window. *)

let passed = ref 0
let failed = ref 0

let check name ok =
  if ok then (incr passed; Printf.printf "  [PASS] %s\n%!" name)
  else (incr failed; Printf.printf "  [FAIL] %s\n%!" name)

let contains hay needle =
  let n = String.length hay and k = String.length needle in
  let rec go i = i + k <= n && (String.sub hay i k = needle || go (i + 1)) in
  k > 0 && go 0

let read path =
  try
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Some (really_input_string ic (in_channel_length ic)))
  with _ -> None

(* Strip comments and string literals before scanning for a literal, so a
   header comment that merely NAMES a window is not mistaken for one that
   allocates it. Every one of these files documents its neighbours'
   windows in prose; counting those would make the guard fire forever and
   teach the next reader to disable it. *)
(* Comments stripped, STRING LITERALS KEPT. A model name is itself a
   string, so scanning for it in [code_only] output could never find one
   — the check would pass on every input and prove nothing. That false
   pass was observed before this function existed. *)
let without_comments source =
  let n = String.length source in
  let b = Buffer.create n in
  let rec go i depth =
    if i >= n then Buffer.contents b
    else if i + 1 < n && source.[i] = '(' && source.[i + 1] = '*' then
      go (i + 2) (depth + 1)
    else if i + 1 < n && source.[i] = '*' && source.[i + 1] = ')' && depth > 0 then
      go (i + 2) (depth - 1)
    else if depth > 0 then go (i + 1) depth
    else (Buffer.add_char b source.[i]; go (i + 1) depth)
  in
  go 0 0

let code_only source =
  let n = String.length source in
  let b = Buffer.create n in
  let rec go i depth in_string =
    if i >= n then Buffer.contents b
    else if in_string then
      if source.[i] = '\\' && i + 1 < n then go (i + 2) depth true
      else if source.[i] = '"' then go (i + 1) depth false
      else go (i + 1) depth true
    else if i + 1 < n && source.[i] = '(' && source.[i + 1] = '*' then
      go (i + 2) (depth + 1) false
    else if i + 1 < n && source.[i] = '*' && source.[i + 1] = ')' && depth > 0 then
      go (i + 2) (depth - 1) false
    else if depth > 0 then go (i + 1) depth false
    else if source.[i] = '"' then go (i + 1) depth true
    else (Buffer.add_char b source.[i]; go (i + 1) depth false)
  in
  go 0 0 false

let () =
  print_endline "fpp window authority: registry shape";
  let open Fpp_window_authority in
  check "the owner set is closed at five" (List.length owners = 5);
  check "every owner declares a distinct model name"
    (let names = List.map declared_model_name owners in
     List.length (List.sort_uniq compare names) = 5);
  check "every owner declares a distinct window base"
    (let bases = List.map window_base owners in
     List.length (List.sort_uniq compare bases) = 5);
  check "no allocation names an owner outside the closed set"
    (List.for_all (fun (a : allocation) -> List.mem a.alloc_owner owners) allocations);
  check "every allocation sits at or above its owner's window base"
    (List.for_all (fun (a : allocation) -> a.base_id >= window_base a.alloc_owner) allocations);
  check "instance ids are unique within an owner"
    (List.for_all
       (fun o ->
         let ids = List.map (fun (a : allocation) -> a.instance_id) (allocations_of o) in
         List.length (List.sort_uniq compare ids) = List.length ids)
       owners);
  check "the digest is a 64-hex SHA-256"
    (let d = allocation_digest () in
     String.length d = 64
     && String.for_all
          (fun c ->
            (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
          d);
  (* Length framing is what makes the digest a fingerprint rather than a
     concatenation, so prove it rejects a boundary shift. *)
  check "the digest is stable across calls"
    (allocation_digest () = allocation_digest ());

  print_endline "fpp window authority: agreement with the five real models";
  let agrees owner model =
    let rs = rows owner model in
    rs <> []
    && List.for_all
         (fun r ->
           r.declared_model_name = r.observed_model_name
           && r.allocation_present && r.component_present
           && r.declared_base_id = r.observed_base_id)
         rs
  in
  check "Harness: the registry agrees with harness_topology"
    (agrees Harness (Harness_topology.model));
  check "Wiki: the registry agrees with wiki_topology"
    (agrees Wiki (Wiki_topology.model));
  check "every declared allocation resolves to a present instance"
    (let rs =
       rows Harness (Harness_topology.model)
       @ rows Wiki (Wiki_topology.model)
     in
     List.for_all
       (fun r -> r.declared_base_id = -1 || r.allocation_present)
       rs);
  check "a present component reports a positive span"
    (let rs = rows Harness (Harness_topology.model) in
     List.for_all (fun r -> (not r.component_present) || r.span > 0) rs);
  check "an absent instance reports observed_base_id = -1, never 0"
    (let empty : Fpp_model.model =
       { Fpp_model.model_name = declared_model_name Completion;
         type_defs = []; port_defs = []; constants = []; components = [];
         machines = []; instances = []; topologies = [] }
     in
     let rs = rows Completion empty in
     rs <> []
     && List.for_all
          (fun r -> (not r.allocation_present) && r.observed_base_id = -1)
          rs);
  check "a model-name mismatch surfaces as a declared/observed PAIR, not a verdict"
    (let wrong : Fpp_model.model =
       { Fpp_model.model_name = "NotTheDeclaredName";
         type_defs = []; port_defs = []; constants = []; components = [];
         machines = []; instances = []; topologies = [] }
     in
     List.for_all
       (fun r ->
         r.declared_model_name = "HermesCompletion"
         && r.observed_model_name = "NotTheDeclaredName")
       (rows Completion wrong));
  check "an instance outside a fixed owner window is reported separately, not promoted"
    (let stray : Fpp_model.model =
       { Fpp_model.model_name = declared_model_name Completion;
         type_defs = []; port_defs = []; constants = []; components = [];
         machines = [];
         instances =
           [ { Fpp_model.inst_name = "strayInstance"; of_component = "strayInstance";
               base_id = 0x9999; queue_size = None; stack_size = None;
               inst_priority = None; cpu = None } ];
         topologies = [] }
     in
     let normative = rows Completion stray in
     let observed = unregistered_actual_rows Completion stray in
     not (List.exists (fun r -> r.instance_id = "strayInstance") normative)
     && List.exists
          (fun r ->
            r.instance_id = "strayInstance" && not r.allocation_present
            && r.declared_base_id = -1)
          observed);
  check "fixed-owner normative rows have exactly the registered denominator"
    (List.length (rows Harness Harness_topology.model)
       = List.length (allocations_of Harness)
     && List.length (rows Wiki Wiki_topology.model)
        = List.length (allocations_of Wiki));
  check "the known Harness/Wiki actual collision is observed, never a normative row"
    (let harness = unregistered_actual_rows Harness Harness_topology.model in
     let wiki = unregistered_actual_rows Wiki Wiki_topology.model in
     let overlaps left right =
       left.observed_base_id < right.observed_base_id + right.span
       && right.observed_base_id < left.observed_base_id + left.span
     in
     let collision =
       List.exists
         (fun left ->
           List.exists
             (fun right ->
               overlaps left right
               && (left.observed_base_id = 0x1000
                   || left.observed_base_id = 0x1100))
             wiki)
         harness
     in
     let normative_ids =
       rows Harness Harness_topology.model @ rows Wiki Wiki_topology.model
       |> List.map (fun r -> (r.owner, r.instance_id))
     in
     collision
     && List.for_all
          (fun r -> not (List.mem (r.owner, r.instance_id) normative_ids))
          (harness @ wiki));

  (* ------------------------------------------------- the behavioral RED *)
  print_endline "fpp window authority: sole authority over base literals";
  let projections =
    [ ("modules/hermes_harness/harness_topology.ml", Harness);
      ("modules/hermes_wiki/src/fpp/wiki_topology.ml", Wiki);
      ("modules/hermes_ops/ops_topology.ml", Ops_monitor);
      ("modules/hermes_ops/ops_completion_topology.ml", Completion);
      ("modules/hermes_ops_dashboard/run_topology.ml", Operations) ]
  in
  List.iter
    (fun (path, owner) ->
      match read path with
      | None ->
          check (Printf.sprintf "%s is readable" path) false
      | Some source ->
          let code = code_only source in
          (* the owner's own window, written as a literal in its own code *)
          let literal = Printf.sprintf "0x%X" (window_base owner) in
          let lowercase = String.lowercase_ascii literal in
          check
            (Printf.sprintf "%s states no base literal of its own (%s)" path literal)
            (not (contains code literal || contains code lowercase));
          (* strings KEPT here — see [without_comments] *)
          let prose_free = without_comments source in
          (* Match the ASSIGNMENT, not the bare string. An earlier version
             scanned for any occurrence of the model name and flagged
             `topo_name = "HermesOps"` — a genuinely independent field
             that merely shares a spelling for three of the five owners.
             It does NOT share one for the other two (Harness declares
             model "Hermes" with topology "hermes_harness"; Wiki declares
             "HermesWikiZk" with "WikiZk"), so there is no law that the
             two are equal and pulling topology names into the registry
             would have invented one. Both assignment spellings are
             checked because run_topology uses the fpp_ prefix. *)
          let name = declared_model_name owner in
          let assigned =
            [ Printf.sprintf "model_name = %S" name;
              Printf.sprintf "fpp_model_name = %S" name ]
          in
          check
            (Printf.sprintf "%s assigns no model-name literal of its own" path)
            (List.for_all (fun a -> not (contains prose_free a)) assigned))
    projections;

  Printf.printf "fpp_window_authority: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_fpp_window_authority" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_fpp_window_authority ]);
  exit (Suite_telemetry.exit_code self)
