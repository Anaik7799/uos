type evidence_status = Fresh | Stale | Unavailable | Indeterminate
type confidence = Candidate | Discriminated | Established
type protocol_stage =
  | Declared | Observed | Oriented | Hypothesized | Discriminated_stage
  | Corrected | Verified | Closed | Blocked

type observation = {
  observation_id : string;
  statement : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  status : evidence_status;
  observed_at_ns : int64;
  evidence_digest : string;
}

type hypothesis = {
  hypothesis_id : string;
  statement : string;
  rca_origin : Ops_capability.rca_origin;
  predictions : string list;
}

type discriminator = {
  discriminator_id : string;
  hypothesis_ids : string list;
  measurement : string;
  maximum_cost : int;
}

val string_of_evidence_status : evidence_status -> string
val string_of_confidence : confidence -> string
val string_of_protocol_stage : protocol_stage -> string
val canonical_observation : observation -> string

