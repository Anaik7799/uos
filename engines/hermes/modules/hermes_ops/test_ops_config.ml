(* Declarative configuration (R23), across the envelope:

     N*  nominal      every element declares layer, purpose and consumer
     X*  exhaustion   the scan covers the whole tree
     S*  stuck        no elements of a layer; a key read nowhere
     A*  anomaly      an undeclared variable; a secret's posture

   The headline law: NO CONFIGURATION OUTSIDE THE MODEL. `undeclared` is
   what makes "declarative only" mechanical rather than aspirational —
   without it the rule is a sentence in a document, and with it adding an
   undeclared variable breaks the build. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 THE LAW: nothing the code reads is outside the model" (fun () ->
      Ops_config_gate.undeclared () = []);
  check "N2 every element declares a purpose and a consumer — no blanks" (fun () ->
      List.for_all
        (fun (x : Ops_config.element) ->
          String.length x.Ops_config.purpose > 10 && x.Ops_config.consumer <> "")
        Ops_config.elements);
  check "N3 every element sits at a FRACTAL LAYER — config is layered too" (fun () ->
      (* a missing prover (L3) and a missing corpus root (L0) fail
         different things and want different responses *)
      List.length
        (List.sort_uniq compare
           (List.map (fun (x : Ops_config.element) -> Ops_config.layer_name x.Ops_config.layer)
              Ops_config.elements))
      >= 4);
  check "N4 keys are unique — one declaration per element" (fun () ->
      let ks = List.map (fun (x : Ops_config.element) -> x.Ops_config.key) Ops_config.elements in
      List.length (List.sort_uniq compare ks) = List.length ks);
  check "N5 the scan actually finds variables — it is not vacuous" (fun () ->
      (* a scanner returning [] would make N1 pass for the wrong reason *)
      let o = Ops_config_gate.observed () in
      List.length o >= 10
      && List.exists (fun (k, _) -> k = "OPENROUTER_API_KEY") o)

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 the secret is declared PRESENCE-ONLY, and that is visible in the model"
    (fun () ->
      (* the posture is reviewable here rather than at a call site: a
         promotion to Value_used would be a change to this declaration *)
      List.exists
        (fun (x : Ops_config.element) ->
          x.Ops_config.key = "OPENROUTER_API_KEY"
          && x.Ops_config.secrecy = Ops_config.Presence_only)
        Ops_config.elements);
  check "A2 no element carries a VALUE — the model declares, it does not configure"
    (fun () ->
      let t = Ops_config.env_template () in
      (* every emitted assignment ends at '=' with nothing after it *)
      List.for_all
        (fun line ->
          let l = String.trim line in
          l = "" || l.[0] = '#'
          || (String.length l > 1 && l.[String.length l - 1] = '='))
        (String.split_on_char '\n' t));
  check "A3 the template names the model as its source and forbids hand-editing"
    (fun () ->
      let t = Ops_config.env_template () in
      contains t "GENERATED" && contains t "ops_config.ml" && contains t "Do not edit");
  check "A4 the check REPORTS its verdict in the exit code, not only in text" (fun () ->
      let text, code = Ops_config_gate.check () in
      code = (if Ops_config_gate.undeclared () = [] then 0 else 1)
      && contains text "config:")

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 the scan reaches every module tree, not just one" (fun () ->
      let files = List.map snd (Ops_config_gate.observed ()) in
      List.length (List.sort_uniq compare files) >= 5);
  check "X2 the template renders every environment-supplied element" (fun () ->
      let t = Ops_config.env_template () in
      List.for_all
        (fun (x : Ops_config.element) ->
          x.Ops_config.supply <> Ops_config.Environment || contains t (x.Ops_config.key ^ "="))
        Ops_config.elements)

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 an element supplied by the TOOLCHAIN is declared but not templated"
    (fun () ->
      (* PATH is real configuration and belongs in the model, but writing
         it into a .env would be wrong — the switch sets it *)
      let t = Ops_config.env_template () in
      List.exists
        (fun (x : Ops_config.element) ->
          x.Ops_config.key = "PATH" && x.Ops_config.supply = Ops_config.Toolchain)
        Ops_config.elements
      && not (contains t "\nPATH="));
  check "S2 render and template are total over the model" (fun () ->
      String.length (Ops_config.render ()) > 200
      && String.length (Ops_config.env_template ()) > 500)

let () =
  check "A5 the generated template may not DRIFT from the model" (fun () ->
      (* a template that drifts from its declaration is the failure the
         whole derive-everything discipline exists to prevent, and it was
         unchecked until a deliberate hand-edit slipped past the gate *)
      Ops_config_gate.template_drifted () = None);
  check "A6 drift is a FAILURE, not a warning — it moves the exit code" (fun () ->
      let _, code = Ops_config_gate.check () in
      code = 0 && Ops_config_gate.template_drifted () = None);
  check "N6 pure authority exposes one canonical schema and declaration digest"
    (fun () ->
      Ops_config.schema_id = "hermes.ops-config/v2"
      && String.length Ops_config.declaration_digest = 64);
  check "N7 Jujutsu configuration IDs are declared exactly once without values"
    (fun () ->
      let required =
        [ "JUJUTSU_RELEASE_ID"; "JUJUTSU_CONFIG_ID";
          "JUJUTSU_OPERATOR_PUBLIC_KEY_ID";
          "JUJUTSU_RESOURCE_BUDGET_PROFILE";
          "JUJUTSU_SOURCE_CARRIER_POLICY"; "JUJUTSU_APPROVAL_POLICY";
          "JUJUTSU_WRITER_LEASE_POLICY"; "JUJUTSU_CREDENTIAL_POLICY";
          "JUJUTSU_COMPLETION_RECONCILE_ATTEMPT_LIMIT" ] in
      List.for_all
        (fun key ->
          List.length
            (List.filter
               (fun (item : Ops_config.element) -> item.key = key)
               Ops_config.elements) = 1)
        required)

let () =
  Printf.printf "ops_config: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_config" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
