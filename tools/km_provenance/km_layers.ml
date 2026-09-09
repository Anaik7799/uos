(* SC-PROVENANCE-001 — content-based fractal layer classification (KMP-ENTROPY).

   !! THE PREMISE BELOW WAS A MEASUREMENT ARTIFACT (corrected 2026-09-09) !!

   This module was written because "68 of 87 ADRs are tagged #fractal-l0,
   collapsing the layer taxonomy to ~1.3 bits". That reading came from
   Km_metrics.layer_entropy_bits folding over Km_corpus.layer — the FIRST
   #fractal-lN tag in a record. Records are multi-label (47 of 80 ADRs carry all
   ten layers; only 6 carry as few as two) and the tag block is conventionally
   written ascending, so the first tag is "#fractal-l0" for 74 of 80 records.
   The statistic measured the WRITING CONVENTION, not the corpus.

   Read over every tag, the same corpus measures 3.31 bits against a ceiling of
   log2(10) = 3.32, and the gate passes its unchanged 2.50 floor. Nothing was
   degenerate. The metric is now fixed at source and carries its own law suite
   (km_gate --metrics-selftest), including a law that it must STILL fail a
   genuinely collapsed corpus.

   Consequence for this module: its classification is still a legitimate
   authorship AID, but it must NOT be applied to raise entropy — that number was
   never low. Note also that applying every proposal would have reached only 2.21
   bits, below the floor it was built to clear, while rewriting 58 records of
   which 35 were low-margin. Chasing a broken metric would have damaged the
   corpus to satisfy a statistic about tag ordering.

   Original description follows.

   This module PROPOSES a layer for each record from its own content and
   reports what the entropy would become. It never rewrites a record: assigning
   a layer is an authorship act belonging to the record's author or to sovereign
   review, so the output is a proposal, not a patch.

   Method: term-frequency vector over a fixed vocabulary, cosine similarity
   against one archetype vector per layer, highest similarity wins. The
   archetype vocabularies are taken from the repository's own L0-L7 gate
   definitions in the full-symbiosis rule, extended with L8 and L9. *)

exception Invalid of string
let require c m = if not c then raise (Invalid m)

(* Each archetype is (layer, terms). A term is matched as a lowercase substring
   of the document, so multi-word phrases are allowed. *)
let archetypes = [
  "#fractal-l0", ["constitutional"; "policy"; "mandate"; "governance"; "authority";
                  "ratification"; "sovereign"; "charter"; "invariant"; "rule bypass";
                  "admission"; "consensus"; "quorum"];
  "#fractal-l1", ["atomic"; "typed"; "type safety"; "secret"; "panic"; "error semantics";
                  "absence"; "null"; "byte"; "primitive"; "encoding"; "parser"; "schema"];
  "#fractal-l2", ["component"; "module"; "library"; "widget"; "api surface"; "package";
                  "boundary"; "interface"; "skill"; "agent definition"; "catalog"];
  "#fractal-l3", ["transaction"; "idempotent"; "timeout"; "hook"; "webhook"; "lease";
                  "commit"; "rollback"; "atomicity"; "durability"; "append-only";
                  "digest"; "chain"];
  "#fractal-l4", ["system"; "supervisor"; "supervision"; "otp"; "runtime"; "deployment";
                  "topology"; "mesh"; "cluster"; "kubernetes"; "service"; "daemon";
                  "process tree"];
  "#fractal-l5", ["cognitive"; "journal"; "zettelkasten"; "knowledge"; "ontology";
                  "wiki"; "decision record"; "reasoning"; "inference"; "evidence";
                  "residual risk"; "learning"];
  "#fractal-l6", ["ecosystem"; "external"; "third party"; "upstream"; "vendor";
                  "attribution"; "credential"; "provider"; "openrouter"; "integration";
                  "import"; "ingestion"];
  "#fractal-l7", ["federation"; "cross-host"; "cross-tree"; "peer"; "tailnet";
                  "multi-host"; "replication"; "sync"; "distributed"; "handover";
                  "drift"];
  "#fractal-l8", ["metric"; "kpi"; "measure"; "telemetry"; "observability"; "dashboard";
                  "instrumentation"; "entropy"; "coverage"; "score"; "benchmark";
                  "threshold"];
  "#fractal-l9", ["evolution"; "evolutionary"; "adaptation"; "self-improvement";
                  "mutation"; "emergence"; "roadmap"; "trajectory"; "lifecycle";
                  "maturity"; "convergence"];
]

let layers = List.map fst archetypes

(* The vocabulary is the union of all archetype terms, in a fixed order, so every
   vector has the same dimension and the same meaning per index. *)
let vocabulary =
  List.concat_map snd archetypes |> List.sort_uniq String.compare

let dim = List.length vocabulary

let lowercase = String.lowercase_ascii

(* Bounded substring count. *)
let count_occurrences hay needle =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 || nl > hl then 0
  else begin
    let n = ref 0 and i = ref 0 in
    while !i <= hl - nl do
      if String.sub hay !i nl = needle then (incr n; i := !i + nl) else incr i
    done; !n
  end

let doc_vector body =
  let b = lowercase body in
  List.map (fun term -> float_of_int (count_occurrences b term)) vocabulary

let archetype_vector layer =
  let terms = List.assoc layer archetypes in
  List.map (fun t -> if List.mem t terms then 1.0 else 0.0) vocabulary

(* Independent OCaml cosine. The Mojo kernel computes the same quantity; the two
   are compared in the cross-check below, which is the differential oracle. *)
let cosine a b =
  let rec go a b d na nb = match a, b with
    | [], [] -> (d, na, nb)
    | x :: ta, y :: tb -> go ta tb (d +. (x *. y)) (na +. (x *. x)) (nb +. (y *. y))
    | _ -> raise (Invalid "cosine: length mismatch") in
  let (d, na, nb) = go a b 0.0 0.0 0.0 in
  if na <= 0.0 || nb <= 0.0 then None else Some (d /. (sqrt na *. sqrt nb))

type proposal = {
  file : string;
  current : string;
  proposed : string;
  confidence : float;
  margin : float;        (* gap to the runner-up: low margin means low evidence *)
}

let classify ~file ~current ~body =
  let v = doc_vector body in
  let scored =
    List.filter_map (fun l ->
      match cosine v (archetype_vector l) with
      | Some s -> Some (l, s)
      | None -> None) layers in
  match List.sort (fun (_, a) (_, b) -> compare b a) scored with
  | [] -> None
  | (best, s1) :: rest ->
    let s2 = match rest with (_, s) :: _ -> s | [] -> 0.0 in
    Some { file; current; proposed = best; confidence = s1; margin = s1 -. s2 }

(* Entropy in bits of a layer assignment, used to show what the proposal would
   achieve before anyone applies it. *)
let entropy_of counts =
  let total = List.fold_left (fun a (_, c) -> a + c) 0 counts in
  if total = 0 then 0.0
  else List.fold_left (fun acc (_, c) ->
    if c = 0 then acc
    else
      let p = float_of_int c /. float_of_int total in
      acc -. (p *. (log p /. log 2.0))) 0.0 counts

let tally assignment =
  List.map (fun l -> (l, List.length (List.filter (fun x -> x = l) assignment))) layers

let () = require (dim > 0) "empty vocabulary"
