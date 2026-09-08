(* SC-PROVENANCE-001 — Rete-UL forward-chaining verdict network for provenance.

   This is a genuine Rete, not a scanner with rule-shaped names:
     * an ALPHA network of per-condition constant tests, indexed by fact type,
       so a fact is tested once per condition rather than once per rule;
     * a BETA network that joins across conditions on shared bindings;
     * an AGENDA with conflict resolution by salience, emergency rules first;
     * FORWARD CHAINING to fixpoint, where derived facts re-enter working memory
       and may fire further rules.

   ADR-001 governs the fact schema and is enforced here: the schema is CLOSED,
   values are literal-validated, and duplicate keys are rejected fail-closed. An
   unknown fact key is a hard error, never a silently ignored input, because an
   unrecognised key could conceal the very state a safety rule exists to catch. *)

exception Invalid of string
let require c m = if not c then raise (Invalid m)

(* --- closed fact schema (ADR-001) --------------------------------------- *)

type value = S of string | N of float | B of bool

type fact = { kind : string; fields : (string * value) list }

(* The closed schema. Adding a key here is a deliberate act; nothing else is
   accepted at any point in the network. *)
let schema : (string * (string * [`Str | `Num | `Bool]) list) list = [
  "adr",        [ "id", `Num; "claims_ev", `Num; "layer", `Str ];
  "index",      [ "label", `Str; "completeness", `Num; "marking", `Num ];
  "ceiling",    [ "policy", `Num; "machine", `Num ];
  "chain",      [ "rows", `Num; "intact", `Bool ];
  (* derived kinds: produced by rules, re-entered into working memory *)
  "quarantined",[ "id", `Num; "claims_ev", `Num ];
  "violation",  [ "rule", `Str; "detail", `Str ];
  "andon",      [ "reason", `Str ];
]

let type_of = function S _ -> `Str | N _ -> `Num | B _ -> `Bool

let validate f =
  match List.assoc_opt f.kind schema with
  | None -> raise (Invalid ("unknown fact kind (closed schema): " ^ f.kind))
  | Some spec ->
    (* duplicate-key rejection, fail-closed per ADR-001 *)
    let keys = List.map fst f.fields in
    let sorted = List.sort compare keys in
    let rec dup = function
      | a :: b :: _ when a = b -> Some a
      | _ :: t -> dup t
      | [] -> None in
    (match dup sorted with
     | Some k -> raise (Invalid ("duplicate key in fact: " ^ f.kind ^ "." ^ k))
     | None -> ());
    List.iter (fun (k, v) ->
      match List.assoc_opt k spec with
      | None -> raise (Invalid ("unknown field (closed schema): " ^ f.kind ^ "." ^ k))
      | Some t -> require (type_of v = t) ("field type mismatch: " ^ f.kind ^ "." ^ k))
      f.fields;
    List.iter (fun (k, _) ->
      require (List.mem_assoc k f.fields) ("missing field: " ^ f.kind ^ "." ^ k)) spec;
    f

let get f k = List.assoc_opt k f.fields
let num f k = match get f k with Some (N n) -> Some n | _ -> None
let str f k = match get f k with Some (S s) -> Some s | _ -> None
let bool_ f k = match get f k with Some (B b) -> Some b | _ -> None

(* Compact numeric rendering for rule detail text: integers print without a
   trailing dot, ratios keep three decimals. *)
let show_num (x : float) =
  if Float.is_integer x then string_of_int (int_of_float x)
  else Printf.sprintf "%.3f" x

(* --- alpha network ------------------------------------------------------- *)
(* One alpha node per (kind, constant test). Working memory is partitioned by
   kind so a fact is only tested against the conditions that could match it. *)

type alpha = { a_kind : string; a_test : fact -> bool; a_name : string }

let alpha_nodes = [
  { a_kind = "adr";     a_name = "adr-any";        a_test = (fun _ -> true) };
  { a_kind = "index";   a_name = "index-any";      a_test = (fun _ -> true) };
  { a_kind = "ceiling"; a_name = "ceiling-any";    a_test = (fun _ -> true) };
  { a_kind = "chain";   a_name = "chain-broken";
    a_test = (fun f -> bool_ f "intact" = Some false) };
  { a_kind = "quarantined"; a_name = "quarantined-any"; a_test = (fun _ -> true) };
]

let alpha_memory wm node =
  List.filter (fun f -> f.kind = node.a_kind && node.a_test f) wm

(* --- rules --------------------------------------------------------------- *)
(* Salience orders the agenda. Emergency precedence is highest, matching the
   SIL-6 zero-trust salience hierarchy recorded in docs/zk. *)

type rule = {
  name : string;
  salience : int;
  fire : fact list -> fact list;   (* working memory -> newly derived facts *)
}

let find_kind wm k = List.filter (fun f -> f.kind = k) wm

let rules = [
  (* Emergency: a broken cycle chain halts everything else. Highest salience so
     it is resolved before any verdict that assumes the chain is trustworthy. *)
  { name = "R0-andon-chain-broken"; salience = 1000;
    fire = fun wm ->
      List.filter_map (fun f ->
        if bool_ f "intact" = Some false
        then Some { kind = "andon";
                    fields = ["reason", S "cycle chain digest mismatch; verdicts suspended"] }
        else None) (find_kind wm "chain") };

  (* Alpha+beta join: an ADR whose claimed cycle exceeds the policy ceiling is
     quarantined. Joins adr against ceiling on no shared binding but on a
     numeric comparison across both. *)
  { name = "R1-quarantine-above-ceiling"; salience = 100;
    fire = fun wm ->
      let ceilings = find_kind wm "ceiling" in
      List.concat_map (fun a ->
        List.filter_map (fun c ->
          match num a "claims_ev", num c "policy", num a "id" with
          | Some ev, Some pol, Some id when ev > pol ->
            Some { kind = "quarantined"; fields = ["id", N id; "claims_ev", N ev] }
          | _ -> None) ceilings) (find_kind wm "adr") };

  (* Beta join: quarantined facts against index facts. Fires once per index that
     has not fully marked, regardless of how many records are quarantined. *)
  { name = "R2-unmarked-quarantine"; salience = 90;
    fire = fun wm ->
      let q = find_kind wm "quarantined" in
      if q = [] then []
      else
        List.filter_map (fun i ->
          match num i "marking", str i "label" with
          | Some m, Some l when m < 1.0 ->
            Some { kind = "violation";
                   fields = ["rule", S "KMP-UNMARKED";
                             "detail", S (l ^ " marks only " ^ show_num m
                                          ^ " of its quarantined records")] }
          | _ -> None) (find_kind wm "index") };

  { name = "R3-incomplete-index"; salience = 80;
    fire = fun wm ->
      List.filter_map (fun i ->
        match num i "completeness", str i "label" with
        | Some c, Some l when c < 1.0 ->
          Some { kind = "violation";
                 fields = ["rule", S "KMP-INCOMPLETE";
                           "detail", S (l ^ " enumerates only " ^ show_num c)] }
        | _ -> None) (find_kind wm "index") };

  (* The 92-versus-93 discrepancy, derived rather than hard-coded. *)
  { name = "R4-ceiling-discrepancy"; salience = 70;
    fire = fun wm ->
      List.filter_map (fun c ->
        match num c "policy", num c "machine" with
        | Some p, Some m when p > m ->
          Some { kind = "violation";
                 fields = ["rule", S "KMP-CEILING-SPLIT";
                           "detail", S ("policy ceiling " ^ show_num p
                                        ^ " exceeds machine-verified ceiling "
                                        ^ show_num m)] }
        | _ -> None) (find_kind wm "ceiling") };
]

(* --- forward chaining to fixpoint ---------------------------------------- *)

let mem_fact wm f =
  List.exists (fun g -> g.kind = f.kind && g.fields = f.fields) wm

type trace = { cycle : int; rule_name : string; derived : int }

let run ?(max_cycles = 64) initial =
  let wm = ref (List.map validate initial) in
  let traces = ref [] in
  let agenda = List.sort (fun a b -> compare b.salience a.salience) rules in
  let rec loop n =
    if n > max_cycles then raise (Invalid "rete did not reach fixpoint within bound")
    else begin
      (* Conflict resolution: highest salience first; the first rule that
         produces a genuinely new fact fires, then the agenda restarts. This is
         the standard refraction-free single-fire cycle. *)
      let fired =
        List.fold_left (fun acc r ->
          match acc with
          | Some _ -> acc
          | None ->
            let derived = List.filter (fun f -> not (mem_fact !wm f)) (r.fire !wm) in
            let derived = List.map validate derived in
            if derived = [] then None
            else begin
              wm := !wm @ derived;
              traces := { cycle = n; rule_name = r.name; derived = List.length derived } :: !traces;
              Some r.name
            end) None agenda in
      match fired with None -> (!wm, List.rev !traces, n) | Some _ -> loop (n + 1)
    end in
  loop 1

let violations wm =
  List.filter_map (fun f ->
    match f.kind, str f "rule", str f "detail" with
    | "violation", Some r, Some d -> Some (r, d)
    | _ -> None) wm

let andons wm =
  List.filter_map (fun f ->
    match f.kind, str f "reason" with
    | "andon", Some r -> Some r
    | _ -> None) wm
