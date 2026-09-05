type evidence_status = Fresh | Stale | Unavailable | Indeterminate
type confidence = Candidate | Discriminated | Established
type protocol_stage =
  | Declared | Observed | Oriented | Hypothesized | Discriminated_stage
  | Corrected | Verified | Closed | Blocked
type observation = {
  observation_id : string; statement : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin; status : evidence_status;
  observed_at_ns : int64; evidence_digest : string;
}
type hypothesis = {
  hypothesis_id : string; statement : string;
  rca_origin : Ops_capability.rca_origin; predictions : string list;
}
type discriminator = {
  discriminator_id : string; hypothesis_ids : string list;
  measurement : string; maximum_cost : int;
}
let string_of_evidence_status = function Fresh -> "fresh" | Stale -> "stale" | Unavailable -> "unavailable" | Indeterminate -> "indeterminate"
let string_of_confidence = function Candidate -> "candidate" | Discriminated -> "discriminated" | Established -> "established"
let string_of_protocol_stage = function Declared -> "declared" | Observed -> "observed" | Oriented -> "oriented" | Hypothesized -> "hypothesized" | Discriminated_stage -> "discriminated" | Corrected -> "corrected" | Verified -> "verified" | Closed -> "closed" | Blocked -> "blocked"
let canonical_observation item =
  String.concat "|"
    [ item.observation_id; item.statement;
      Ops_capability.string_of_level item.coordinate.level;
      Ops_capability.string_of_phase item.coordinate.phase;
      Ops_capability.string_of_rca_origin item.rca_origin;
      string_of_evidence_status item.status;
      Int64.to_string item.observed_at_ns; item.evidence_digest ]
