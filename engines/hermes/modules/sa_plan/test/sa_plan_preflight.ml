open Core

module Store = Sa_plan.Store

type identity = {
  domain : Store.bridge_domain;
  ooda_slice_id : string;
  sa_plan_id : string;
  sa_task_id : string;
}

type lease = { owner : string; lease_id : string; fencing_token : int64; expires_at_ns : int64 }

type safety_packet = {
  packet_hash : string;
  stpa_analysis_hash : string;
  fmea_analysis_hash : string;
  uca_guard_id : string;
}

type evidence = {
  prompt_ledger_hash : string;
  formal_evidence_hash : string;
  baseline_gate_stamp : string;
  gate_run_id : string;
}

type revision = { source_fingerprint : string; dependency_snapshot : string; commit_sha : string }

type packet = {
  mapping : Store.bridge_mapping;
  identity : identity;
  lease : lease;
  safety : safety_packet;
  evidence : evidence;
  revision : revision;
  packet_hash : string;
  recorded_at_ns : int64;
}

type receipt = { mapping_id : string; packet_hash : string; decision : string }

let require_nonempty field value =
  if String.is_empty value then Error ("missing preflight " ^ field) else Ok ()

let require_all fields =
  List.fold fields ~init:(Ok ()) ~f:(fun result (field, value) ->
      Result.bind result ~f:(fun () -> require_nonempty field value))

let equal_mapping (left : Store.bridge_mapping) (right : Store.bridge_mapping) =
  String.equal left.id right.id
  && Poly.equal left.domain right.domain
  && String.equal left.ooda_slice_id right.ooda_slice_id
  && String.equal left.idempotency_key right.idempotency_key
  && String.equal left.source_fingerprint right.source_fingerprint
  && String.equal left.dependency_snapshot right.dependency_snapshot
  && String.equal left.prompt_ledger_hash right.prompt_ledger_hash
  && String.equal left.safety_packet_hash right.safety_packet_hash
  && String.equal left.formal_evidence_hash right.formal_evidence_hash
  && Option.equal String.equal left.sa_plan_id right.sa_plan_id
  && Option.equal String.equal left.sa_task_id right.sa_task_id
  && String.equal left.lifecycle_state right.lifecycle_state
  && Int64.equal left.version right.version

let validate ~now_ns packet persisted =
  let mapping = packet.mapping in
  Result.bind
    (require_all
       [ "mapping_id", mapping.id;
         "identity.ooda_slice_id", packet.identity.ooda_slice_id;
         "identity.sa_plan_id", packet.identity.sa_plan_id;
         "identity.sa_task_id", packet.identity.sa_task_id;
         "lease.owner", packet.lease.owner;
         "lease.lease_id", packet.lease.lease_id;
         "safety.packet_hash", packet.safety.packet_hash;
         "safety.stpa_analysis_hash", packet.safety.stpa_analysis_hash;
         "safety.fmea_analysis_hash", packet.safety.fmea_analysis_hash;
         "safety.uca_guard_id", packet.safety.uca_guard_id;
         "evidence.prompt_ledger_hash", packet.evidence.prompt_ledger_hash;
         "evidence.formal_evidence_hash", packet.evidence.formal_evidence_hash;
         "evidence.baseline_gate_stamp", packet.evidence.baseline_gate_stamp;
         "evidence.gate_run_id", packet.evidence.gate_run_id;
         "revision.source_fingerprint", packet.revision.source_fingerprint;
         "revision.dependency_snapshot", packet.revision.dependency_snapshot;
         "revision.commit_sha", packet.revision.commit_sha;
         "packet_hash", packet.packet_hash ])
    ~f:(fun () ->
      if Int64.(packet.lease.fencing_token <= 0L) then Error "invalid preflight fencing token"
      else if Int64.(packet.lease.expires_at_ns <= now_ns) then Error "expired preflight lease"
      else if not (equal_mapping mapping persisted) then Error "preflight mapping provenance drift"
      else
        match mapping.sa_plan_id, mapping.sa_task_id with
        | Some plan_id, Some task_id
          when Poly.equal packet.identity.domain mapping.domain
               && String.equal packet.identity.ooda_slice_id mapping.ooda_slice_id
               && String.equal packet.identity.sa_plan_id plan_id
               && String.equal packet.identity.sa_task_id task_id
               && String.equal packet.safety.packet_hash mapping.safety_packet_hash
               && String.equal packet.evidence.prompt_ledger_hash mapping.prompt_ledger_hash
               && String.equal packet.evidence.formal_evidence_hash mapping.formal_evidence_hash
               && String.equal packet.revision.source_fingerprint mapping.source_fingerprint
               && String.equal packet.revision.dependency_snapshot mapping.dependency_snapshot -> Ok ()
        | _ -> Error "preflight identity or provenance mismatch")

let admit store ~now_ns packet =
  Result.bind (Store.find_bridge_mapping store ~id:packet.mapping.id) ~f:(function
    | None -> Error "unknown preflight mapping"
    | Some persisted ->
        Result.bind (validate ~now_ns packet persisted) ~f:(fun () ->
          Result.map
            (Store.record_bridge_preflight store ~mapping_id:packet.mapping.id
               ~packet_hash:packet.packet_hash ~decision:"admitted"
               ~recorded_at_ns:packet.recorded_at_ns)
            ~f:(fun () ->
              { mapping_id = packet.mapping.id;
                packet_hash = packet.packet_hash;
                decision = "admitted" })))
