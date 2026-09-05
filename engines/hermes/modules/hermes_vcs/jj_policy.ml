type authority =
  | Observe_only
  | Local_mutation
  | Destructive_local
  | History_rewrite
  | Recovery
  | Fetch
  | Remote_publish

type denial = Snapshot_forbidden | Insufficient_authority | Stale_authority
type decision = Permit | Deny of denial

let authority_permits authority operation =
  let declaration : Jj_operation.declaration = Jj_operation.declaration operation in
  match authority, declaration.Jj_operation.risk with
  | Observe_only, Jj_operation.Risk_observe -> true
  | Local_mutation,
    (Jj_operation.Risk_observe | Jj_operation.Risk_local_mutation) -> true
  | Destructive_local,
    (Jj_operation.Risk_observe | Jj_operation.Risk_local_mutation
    | Jj_operation.Risk_destructive_local) -> true
  | History_rewrite,
    (Jj_operation.Risk_observe | Jj_operation.Risk_history_rewrite) -> true
  | Recovery,
    (Jj_operation.Risk_observe | Jj_operation.Risk_recovery) -> true
  | Fetch,
    (Jj_operation.Risk_observe | Jj_operation.Risk_remote_read) -> true
  | Remote_publish,
    (Jj_operation.Risk_observe | Jj_operation.Risk_remote_publish) -> true
  | _ -> false

let evaluate authority ~snapshot_requested operation =
  let declaration = Jj_operation.declaration operation in
  if snapshot_requested
     && declaration.Jj_operation.effect_class = Jj_operation.Effect_observation
  then Deny Snapshot_forbidden
  else if authority_permits authority operation then Permit
  else Deny Insufficient_authority

let combine left right =
  match left, right with
  | Deny denial, _ | _, Deny denial -> Deny denial
  | Permit, Permit -> Permit

let authorities =
  [ Observe_only; Local_mutation; Destructive_local; History_rewrite;
    Recovery; Fetch; Remote_publish ]

let authority_key = function
  | Observe_only -> "observe-only"
  | Local_mutation -> "local-mutation"
  | Destructive_local -> "destructive-local"
  | History_rewrite -> "history-rewrite"
  | Recovery -> "recovery"
  | Fetch -> "fetch"
  | Remote_publish -> "remote-publish"

let decision_key = function
  | Permit -> "permit"
  | Deny Snapshot_forbidden -> "deny:snapshot-forbidden"
  | Deny Insufficient_authority -> "deny:insufficient-authority"
  | Deny Stale_authority -> "deny:stale-authority"

let policy_rows authorities =
  List.concat_map
    (fun authority ->
      List.concat_map
        (fun operation ->
          let operation_key = (Jj_operation.declaration operation).key in
          [ Jj_id.length_frame
              [ authority_key authority; "snapshot:false"; operation_key;
                decision_key
                  (evaluate authority ~snapshot_requested:false operation) ];
            Jj_id.length_frame
              [ authority_key authority; "snapshot:true"; operation_key;
                decision_key
                  (evaluate authority ~snapshot_requested:true operation) ] ])
        Jj_operation.all)
    authorities

let source_digest_of ?(change_decision = false) authorities =
  let rows = policy_rows authorities in
  let rows =
    if change_decision then
      match rows with [] -> [] | _ :: rest -> "mutant:permit" :: rest
    else rows
  in
  Jj_id.length_frame
    [ "policy-authority-v1"; Jj_operation.source_digest;
      Jj_id.length_frame (List.map authority_key authorities);
      Jj_id.length_frame
        [ "snapshot-forbidden"; "insufficient-authority";
          "stale-authority" ];
      Jj_id.length_frame [ "permit"; "deny" ];
      Jj_id.length_frame rows;
      "combine:deny-absorbing" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let source_digest = source_digest_of authorities

module For_test = struct
  type source_mutation = Drop_authority | Change_decision
  let source_digest_with_mutation = function
    | Drop_authority -> source_digest_of (List.tl authorities)
    | Change_decision -> source_digest_of ~change_decision:true authorities
end
