(* HW.8.2.7 — the reconciliation pair (S36). Four legs per the synthesis
   exemplar: property (L36.1–L36.7), bounded smtml (L36.2, negation unsat +
   sanity sat), instance (Feature_register as frozen oracle, row for row),
   and the register leg lives in test_feature_register via the live probe.

   Mutation battery (killers named in advance, applied to reconcile.ml):
     M1 trusting register  — status returns decl over an answered probe
     M2 one-eyed residue   — drops declared-behind rows
     M3 vacuous reconcile  — unknown returns [] on a ghost key
     M4 optimistic default — neither-row admitted instead of refused
     M5 silent second write— duplicate key admitted, last wins *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

module IS = struct
  type key = int
  type claim = int

  let compare_key = Int.compare
  let equal_claim = Int.equal
  let show_key = string_of_int
  let show_claim = string_of_int
end

module R = Reconcile.Make (IS)

(* Deterministic generator: per key, a declaration in 0..3 or none, and a
   probe that answers 0..3, answers None (silent), or is absent — with the
   constraint the interface refuses otherwise: at least one of the two. *)
let () = Random.init 7

type gen_row = { k : int; d : int option; p : [ `Absent | `Silent | `Answers of int ] }

let gen_register n =
  List.init n (fun k ->
      let d = if Random.bool () then Some (Random.int 4) else None in
      let p =
        match Random.int 3 with
        | 0 when d <> None -> `Absent
        | 1 -> `Silent
        | _ -> `Answers (Random.int 4)
      in
      let d = if p = `Absent && d = None then Some (Random.int 4) else d in
      { k; d; p })

let to_entries rows =
  List.map
    (fun { k; d; p } ->
      let probe =
        match p with
        | `Absent -> None
        | `Silent -> Some (fun () -> None)
        | `Answers v -> Some (fun () -> Some v)
      in
      (k, d, probe))
    rows

let registers = List.init 30 (fun i -> gen_register (1 + ((i * 7) mod 29)))

let snapped rows = R.snapshot (Result.get_ok (R.register (to_entries rows)))

(* L36.1 — an answered probe outranks the declaration; silence falls back. *)
let () =
  check "L36.1 preference: answered probe wins; silence falls to the declaration"
    (fun () ->
      List.for_all
        (fun rows ->
          let t = snapped rows in
          List.for_all
            (fun { k; d; p } ->
              match p with
              | `Answers v -> R.status t k = Some v
              | `Silent | `Absent -> R.status t k = d)
            rows)
        registers)

(* L36.2 — residue iff both defined and differing, BOTH directions; checked
   against ground truth built independently of the implementation. *)
let () =
  check "L36.2 residue iff declared and observed differ (set equality)" (fun () ->
      List.for_all
        (fun rows ->
          let t = snapped rows in
          let expected =
            List.filter_map
              (fun { k; d; p } ->
                match (d, p) with
                | Some dv, `Answers ov when dv <> ov -> Some (k, dv, ov)
                | _ -> None)
              rows
            |> List.sort compare
          in
          List.sort compare (R.residue t) = expected)
        registers)

let () =
  check "L36.2 generator is two-sided (declared-ahead AND declared-behind occur)"
    (fun () ->
      let ahead = ref false and behind = ref false in
      List.iter
        (List.iter (fun { d; p; _ } ->
             match (d, p) with
             | Some dv, `Answers ov when dv > ov -> ahead := true
             | Some dv, `Answers ov when dv < ov -> behind := true
             | _ -> ()))
        registers;
      !ahead && !behind)

(* L36.3 — fail closed: the neither-row is refused; ghosts are named. *)
let () =
  check "L36.3 a row with neither declaration nor probe is refused" (fun () ->
      match R.register [ (1, Some 0, None); (2, None, None) ] with
      | Error _ -> true
      | Ok _ -> false)

let () =
  check "L36.3 unknown names every ghost key, sorted, and only ghosts" (fun () ->
      let t = snapped [ { k = 1; d = Some 0; p = `Absent }; { k = 5; d = None; p = `Answers 2 } ] in
      R.unknown t ~claimed:[ 9; 1; 7; 5; 7 ] = [ 7; 9 ])

(* L36.4 — write functionality: duplicate registration is a refusal. *)
let () =
  check "L36.4 duplicate key at register is refused, never last-wins" (fun () ->
      match R.register [ (3, Some 0, None); (3, Some 1, None) ] with
      | Error _ -> true
      | Ok _ -> false)

(* L36.5 — non-vacuity: inject makes the residue fire, and inject of the
   declared value itself does not (both directions of the overlay). *)
let () =
  check "L36.5 inject fires the residue iff the injected claim differs" (fun () ->
      List.for_all
        (fun rows ->
          let t = snapped rows in
          List.for_all
            (fun { k; d; _ } ->
              match d with
              | None -> true
              | Some dv ->
                  let differs = (dv + 1) mod 4 in
                  let fired =
                    List.exists (fun (k', _, _) -> k' = k) (R.residue (R.inject t k differs))
                  in
                  let quiet =
                    not (List.exists (fun (k', _, _) -> k' = k) (R.residue (R.inject t k dv)))
                  in
                  fired && quiet)
            rows)
        registers)

(* L36.6 — snapshot coherence: probes run ONCE, under snapshot; reads are
   pure and repeatable afterwards. *)
let () =
  check "L36.6 probes run once under snapshot; reads are frozen and repeatable"
    (fun () ->
      let calls = ref 0 in
      let entries = [ (1, Some 0, Some (fun () -> incr calls; Some 3)) ] in
      let t0 = Result.get_ok (R.register entries) in
      let before = !calls in
      let t = R.snapshot t0 in
      let after_snap = !calls in
      let s1 = R.status t 1 in
      let r1 = R.residue t in
      let s2 = R.status t 1 in
      let r2 = R.residue t in
      before = 0 && after_snap = 1 && !calls = 1 && s1 = s2 && r1 = r2
      && s1 = Some 3 && r1 = [ (1, 0, 3) ])

(* L36.7 — one serialisation: residue and unknown are sorted by key. *)
let () =
  check "L36.7 residue and unknown are sorted by compare_key" (fun () ->
      let sorted_keys ks = List.sort compare ks = ks in
      List.for_all
        (fun rows ->
          let t = snapped rows in
          sorted_keys (List.map (fun (k, _, _) -> k) (R.residue t))
          && sorted_keys (R.unknown t ~claimed:[ 99; 3; 98; 1; 97 ]))
        registers)

(* report — the one-line summary is consistent with its parts. *)
let () =
  check "report counts rows, probed, stale, unknown consistently" (fun () ->
      List.for_all
        (fun rows ->
          let t = snapped rows in
          let r = R.report t ~claimed:[ 998; 999 ] in
          r.R.rows = List.length rows
          && r.R.stale = List.length (R.residue t)
          && r.R.unknown = 2
          && r.R.probed = List.length (List.filter (fun { p; _ } -> p <> `Absent) rows))
        registers)

(* ---- Solver leg: L36.2 over a bounded encoding (6 keys, 4 claims). ---- *)
module SM = Smtml.Solver.Batch (Smtml.Z3_mappings)
open Smtml

let int_sym name = Expr.symbol (Symbol.make Ty.Ty_int name)
let int_val n = Expr.value (Value.Int n)
let eqi a b = Expr.relop Ty.Ty_bool Ty.Relop.Eq a b
let lei a b = Expr.relop Ty.Ty_int Ty.Relop.Le a b
let band a b = Expr.binop Ty.Ty_bool Ty.Binop.And a b
let bor a b = Expr.binop Ty.Ty_bool Ty.Binop.Or a b
let bnot a = Expr.unop Ty.Ty_bool Ty.Unop.Not a
let itb c t e = Expr.triop Ty.Ty_bool Ty.Triop.Ite c t e
let btrue = Expr.value Value.True
let bfalse = Expr.value Value.False
let in01 x = band (lei (int_val 0) x) (lei x (int_val 1))
let in03 x = band (lei (int_val 0) x) (lei x (int_val 3))

let keys = [ 0; 1; 2; 3; 4; 5 ]
let dp k = int_sym (Printf.sprintf "dp%d" k)
let opr k = int_sym (Printf.sprintf "op%d" k)
let dv k = int_sym (Printf.sprintf "dv%d" k)
let ov k = int_sym (Printf.sprintf "ov%d" k)

let range =
  List.fold_left band btrue
    (List.concat_map (fun k -> [ in01 (dp k); in01 (opr k); in03 (dv k); in03 (ov k) ]) keys)

(* the code shape: the nested match of Reconcile.residue *)
let code_mem k =
  itb (eqi (dp k) (int_val 1))
    (itb (eqi (opr k) (int_val 1)) (bnot (eqi (dv k) (ov k))) bfalse)
    bfalse

(* the spec shape: the conjunction of L36.2, written independently *)
let spec_mem k = band (eqi (dp k) (int_val 1)) (band (eqi (opr k) (int_val 1)) (bnot (eqi (dv k) (ov k))))

let check_solver name negation expected =
  let solver = SM.create () in
  let got = SM.check solver [ range; negation ] in
  let show = function `Sat -> "sat" | `Unsat -> "unsat" | `Unknown -> "unknown" in
  check name (fun () ->
      if got = expected then true
      else (print_endline ("  solver said " ^ show got); false))

let () =
  check_solver "L36.2 solver: code shape == spec shape (negation UNSAT, 6 keys x 4 claims)"
    (List.fold_left bor bfalse (List.map (fun k -> bnot (eqi (code_mem k) (spec_mem k))) keys))
    `Unsat;
  check_solver "L36.2 solver sanity: a residue member is SAT (not vacuous)"
    (code_mem 0) `Sat;
  check_solver "L36.2 solver sanity: the empty residue is SAT too"
    (List.fold_left band btrue (List.map (fun k -> bnot (code_mem k)) keys))
    `Sat

(* ---- Instance leg: Feature_register re-expressed, the landed code as the
   frozen oracle. claim = "the probe holds" (bool); declaration = "declared
   Built". stale_declarations must agree with residue row for row. ---- *)
module FS = struct
  type key = string
  type claim = bool

  let compare_key = String.compare
  let equal_claim = Bool.equal
  let show_key k = k
  let show_claim = string_of_bool
end

module FR = Reconcile.Make (FS)

let fr_entries =
  List.filter_map
    (fun (f : Feature_register.feature) ->
      match f.Feature_register.derived with
      | None -> None
      | Some p ->
          let declared_built =
            match f.Feature_register.declared with Feature_register.Built -> true | _ -> false
          in
          Some
            ( f.Feature_register.id,
              Some declared_built,
              Some (fun () -> Some (try p () with _ -> false)) ))
    Feature_register.features

let fr_t = FR.snapshot (Result.get_ok (FR.register fr_entries))

let () =
  check "instance leg: residue agrees with Feature_register.stale_declarations row for row"
    (fun () ->
      let ours = List.map (fun (k, _, _) -> k) (FR.residue fr_t) in
      let oracle = List.sort String.compare (Feature_register.stale_declarations ()) in
      ours = oracle)

let () =
  check "instance leg non-vacuity: a divergent injection fires OUR residue, not the oracle's"
    (fun () ->
      match
        List.find_opt
          (fun (f : Feature_register.feature) ->
            f.Feature_register.derived <> None
            && match f.Feature_register.declared with Feature_register.Built -> true | _ -> false)
          Feature_register.features
      with
      | None -> false
      | Some f ->
          let id = f.Feature_register.id in
          let t' = FR.inject fr_t id false in
          List.exists (fun (k, _, _) -> k = id) (FR.residue t')
          && Feature_register.stale_declarations () = List.sort String.compare (Feature_register.stale_declarations ()))

let () =
  Printf.printf "reconcile: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_reconcile" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_reconcile ]);
  exit (Wiki_suite_telemetry.exit_code self)
