(* Drift diagnosis: production rules over reconciliation output, via the
   mirrored Hermes_rete engine (R14: the zigvm rete_rules projection
   discipline). The gate is fail-closed; diagnosis inserts advice facts the
   caller reads back. This module, not the lenient embedded GRL engine, is the
   authoritative path. *)

type advice = { target : string; action : string; detail : string }

let verdict_name = Parity_algebra.name

(* ------------------------------------------------------------- projection *)

let project (reconciled : Blueprint.reconciled list) =
  let open Hermes_rete in
  let wm = WM.create () in
  List.iter
    (fun (r : Blueprint.reconciled) ->
      match r.outcome with
      | Blueprint.Satisfied ->
          WM.insert wm "satisfied"
            [ ("target", Value.String r.directive.Blueprint.target) ]
      | Blueprint.Drift { desired; actual } ->
          let hazard =
            match r.diagnostic with
            | Some d -> d.Fractal_diagnostic.hazard
            | None -> ""
          in
          WM.insert wm "drift"
            [ ("target", Value.String r.directive.Blueprint.target);
              ("desired", Value.String (verdict_name desired));
              ("actual", Value.String (verdict_name actual));
              ("hazard", Value.String hazard);
              ("intent", Value.String r.directive.Blueprint.intent) ])
    reconciled;
  (* The analysis and the countermeasure table ride along so rules can join
     drift -> hazard -> response through variable bindings. *)
  List.iter
    (fun (h : Fractal_diagnostic.hazard) ->
      WM.insert wm "hazard"
        [ ("id", Value.String h.Fractal_diagnostic.id);
          ("realises_h1", Value.Bool h.Fractal_diagnostic.realises_h1) ])
    Fractal_diagnostic.hazards;
  List.iter
    (fun (c : Fractal_countermeasures.countermeasure) ->
      WM.insert wm "countermeasure"
        [ ("hazard", Value.String c.Fractal_countermeasures.hazard);
          ("auto", Value.Bool (Fractal_countermeasures.is_automatic c)) ])
    Fractal_countermeasures.countermeasures;
  wm

(* ------------------------------------------------------------------ rules *)

let attr fact name =
  match List.assoc_opt name fact.Hermes_rete.attrs with
  | Some (Hermes_rete.Value.String s) -> s
  | Some v -> Hermes_rete.Value.to_string v
  | None -> ""

let advise wm ~target ~action ~detail =
  Hermes_rete.WM.insert wm "advice"
    [ ("target", Hermes_rete.Value.String target);
      ("action", Hermes_rete.Value.String action);
      ("detail", Hermes_rete.Value.String detail) ]

let rules =
  let open Hermes_rete in
  [ (* The zero-trust gate: a drift whose actual equals its desired verdict is a
       corrupted reconciliation -- nothing downstream can be trusted. The
       equality is checked in the action: the engine's variable bindings join
       ACROSS patterns (the faithful zigvm semantics), not within one fact. *)
    { name = "drift-consistency";
      patterns = [ { pat_kind = "drift"; conds = []; bind_name = Some "d" } ];
      action =
        (fun _ named ->
          let d = List.assoc "d" named in
          if attr d "actual" = attr d "desired" then
            Error ("drift entry for " ^ attr d "target" ^ " has actual = desired")
          else Ok ()) };
    (* A proved divergence: the candidate is wrong at this target. *)
    { name = "divergent-drift";
      patterns =
        [ { pat_kind = "drift";
            conds = [ FieldCmp ("actual", Eq, Value.String "divergent") ];
            bind_name = Some "d" } ];
      action =
        (fun wm named ->
          let d = List.assoc "d" named in
          advise wm ~target:(attr d "target") ~action:"fix-candidate"
            ~detail:("implement faithfully from the frozen source: " ^ attr d "intent");
          Ok ()) };
    (* No evidence yet: the harness has not been pointed at the target. *)
    { name = "unmapped-drift";
      patterns =
        [ { pat_kind = "drift";
            conds = [ FieldCmp ("actual", Eq, Value.String "unmapped") ];
            bind_name = Some "d" } ];
      action =
        (fun wm named ->
          let d = List.assoc "d" named in
          advise wm ~target:(attr d "target") ~action:"capture-and-compare"
            ~detail:"pin reference fixtures and add the differential scenarios";
          Ok ()) };
    (* Blocked with a named hazard whose countermeasure is safe to automate. *)
    { name = "blocked-drift-auto-countermeasure";
      patterns =
        [ { pat_kind = "drift";
            conds =
              [ FieldCmp ("actual", Eq, Value.String "blocked");
                FieldCmp ("hazard", Neq, Value.String "");
                VarBind ("h", "hazard") ];
            bind_name = Some "d" };
          { pat_kind = "countermeasure";
            conds = [ VarCmp ("hazard", Eq, "h"); FieldCmp ("auto", Eq, Value.Bool true) ];
            bind_name = None } ];
      action =
        (fun wm named ->
          let d = List.assoc "d" named in
          advise wm ~target:(attr d "target") ~action:"apply-countermeasure"
            ~detail:("the countermeasure for " ^ attr d "hazard" ^ " is safe to apply");
          Ok ()) };
    (* Blocked otherwise: manual attention, with the hazard named if known. *)
    { name = "blocked-drift-manual";
      patterns =
        [ { pat_kind = "drift";
            conds = [ FieldCmp ("actual", Eq, Value.String "blocked") ];
            bind_name = Some "d" } ];
      action =
        (fun wm named ->
          let d = List.assoc "d" named in
          let already =
            List.exists
              (fun a -> attr a "target" = attr d "target" && attr a "action" = "apply-countermeasure")
              (WM.get_by_kind wm "advice")
          in
          if not already then
            advise wm ~target:(attr d "target") ~action:"manual-countermeasure"
              ~detail:
                (match attr d "hazard" with
                | "" -> "unblock manually; no hazard was named (R6: analyse it)"
                | hazard -> "perform the manual countermeasure for " ^ hazard);
          Ok ()) } ]

let diagnose reconciled =
  let wm = project reconciled in
  match Hermes_rete.fire_rules wm rules with
  | Error message -> Error message
  | Ok () ->
      Ok
        (Hermes_rete.WM.get_by_kind wm "advice"
        |> List.map (fun fact ->
               { target = attr fact "target"; action = attr fact "action";
                 detail = attr fact "detail" })
        |> List.sort (fun a b ->
               match compare a.target b.target with 0 -> compare a.action b.action | c -> c))
