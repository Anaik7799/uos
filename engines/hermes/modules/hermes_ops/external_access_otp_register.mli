type axis = Behavior | Performance | Scalability | Reliability | Operability | Predictability
type statistic = Median_with_mad
type measurement_protocol = {
  sample_count : int;
  statistic : statistic;
  requires_same_host : bool;
  requires_same_otp_pin : bool;
  requires_warmup : bool;
  requires_replay : bool;
}
type evidence_receipt = private {
  run_id : string;
  source_digest : string;
  otp_pin : string;
  host_fingerprint : string;
  evidence_level : int;
}
type status = Unmeasured | Reference_documented
  | Differential_equivalent of evidence_receipt
  | Measured_improvement of evidence_receipt
type improvement = {
  hypothesis : string;
  compatibility_invariant : string;
  proof_obligation_ids : string list;
  acceptance_metric_ids : string list;
}
type row = {
  feature_id : string;
  otp_service : string;
  reference_behavior : string;
  otp_source_paths : string list;
  hermes_component_ids : string list;
  axes : axis list;
  status : status;
  measurement : measurement_protocol;
  improvement : improvement option;
  residual : string;
}
type reference = { release : string; commit : string; pin_file : string }
val reference : reference
val rows : row list
val validate : row list -> string list
val source_digest : string
