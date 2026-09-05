type declared = { intent : Debug_intent.t }
type observed = { intent : Debug_intent.t; observations : Debug_ontology.observation list }
type oriented = observed
type hypothesized = { observed : observed; hypotheses : Debug_ontology.hypothesis list }
type discriminated = { hypothesized : hypothesized; root_cause : Debug_ontology.hypothesis }
type corrected = { discriminated : discriminated; correction_id : string }
type verified = { corrected : corrected; verification : Debug_ontology.observation list }
type receipt = { intent_id : string; root_cause_id : string; rca_origin : Ops_capability.rca_origin; evidence_digests : string list; stage : Debug_ontology.protocol_stage; digest : string }
let nonempty value = String.trim value <> ""
let unique values = List.length values = List.length (List.sort_uniq String.compare values)
let valid_digest value = String.length value = 64

let declare (intent : Debug_intent.t) : declared = { intent }

let validate_observations observations =
  observations <> []
  && unique (List.map (fun item -> item.Debug_ontology.observation_id) observations)
  && List.for_all (fun (item : Debug_ontology.observation) ->
       nonempty item.Debug_ontology.statement
       && item.status = Debug_ontology.Fresh
       && item.observed_at_ns >= 0L
       && valid_digest item.evidence_digest) observations

let observe (declared : declared) observations =
  if validate_observations observations then Ok { intent = declared.intent; observations }
  else Error "observation set is empty, stale, duplicate, or malformed"

let orient (observed : observed) : (oriented, string) result = Ok observed

let hypothesize observed ~mechanical_proof hypotheses =
  let ids = List.map (fun item -> item.Debug_ontology.hypothesis_id) hypotheses in
  if (mechanical_proof && List.length hypotheses = 1)
     || (List.length hypotheses >= 2 && unique ids
         && List.for_all (fun item -> item.Debug_ontology.predictions <> []) hypotheses)
  then Ok { observed; hypotheses }
  else Error "competing hypotheses and predictions are required"

let discriminate hypothesized discriminator ~eliminated =
  let ids = List.map (fun item -> item.Debug_ontology.hypothesis_id) hypothesized.hypotheses in
  let survivors = Debug_algebra.eliminate hypothesized.hypotheses eliminated in
  if discriminator.Debug_ontology.hypothesis_ids = ids
     && discriminator.maximum_cost > 0
     && nonempty discriminator.measurement
     && eliminated <> [] && unique eliminated
     && List.for_all (fun id -> List.mem id ids) eliminated
     && List.length survivors = 1
  then Ok { hypothesized; root_cause = List.hd survivors }
  else Error "measurement does not discriminate exactly one root cause"

let correct discriminated ~correction_id ~via_bridge =
  if not (nonempty correction_id) then Error "correction identity is empty"
  else match discriminated.hypothesized.observed.intent.effect_policy with
  | Debug_intent.Pure_diagnosis -> Error "diagnostic-only intent cannot correct"
  | Corrective_via_bridge _ when not via_bridge ->
      Error "correction requires Run_swarm_bridge mediation"
  | Corrective_via_bridge _ -> Ok { discriminated; correction_id }

let verify corrected verification =
  if validate_observations verification then Ok { corrected; verification }
  else Error "verification evidence is empty, stale, duplicate, or malformed"

let close verified =
  let root = verified.corrected.discriminated.root_cause in
  let intent = verified.corrected.discriminated.hypothesized.observed.intent in
  let evidence =
    verified.corrected.discriminated.hypothesized.observed.observations
    @ verified.verification
    |> List.map (fun item -> item.Debug_ontology.evidence_digest)
    |> List.sort_uniq String.compare
  in
  let payload = String.concat "|"
    [ intent.stable_id; root.hypothesis_id;
      Ops_capability.string_of_rca_origin root.rca_origin;
      verified.corrected.correction_id; String.concat "," evidence; "closed" ]
  in
  Ok { intent_id = intent.stable_id; root_cause_id = root.hypothesis_id;
       rca_origin = root.rca_origin; evidence_digests = evidence;
       stage = Debug_ontology.Closed;
       digest = Digestif.SHA256.(to_hex (digest_string payload)) }
