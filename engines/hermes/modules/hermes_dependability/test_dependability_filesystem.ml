open Dependability_filesystem

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.eprintf "FAIL %s\n" name
  end

let get = function Ok value -> value | Error _ -> failwith "valid value refused"

let unavailable = function
  | Error Dependability_filesystem.Unavailable_observed -> true
  | Ok () | Error _ -> false

let () =
  let root = get (Dependability_filesystem.root "repository") in
  let target = get (Dependability_filesystem.target "records/item-01") in
  check "F1 backend names the missing RESOLVE_BENEATH and NO_XDEV enforcement"
    (Dependability_filesystem.backend ()
     = Dependability_filesystem.No_xdev_unavailable);
  check "F2 relative targets reject empty absolute parent traversal and ambiguous segments"
    (List.for_all
       (fun value -> Result.is_error (Dependability_filesystem.target value))
       [ ""; "/absolute"; "../escape"; "a/../escape"; "a//b";
         "a/./b"; "a\\b"; String.make 257 'a' ]);
  check "F3 closed roles have one exact precondition each"
    (Dependability_filesystem.precondition Observe_tree = Target_present
     && Dependability_filesystem.precondition Observe_object = Target_present
     && Dependability_filesystem.precondition Materialize_candidate = Target_absent
     && Dependability_filesystem.precondition Write_partition = Target_present
     && Dependability_filesystem.precondition Restore_partition = Target_present
     && Dependability_filesystem.precondition Write_sealed_record_candidate
        = Target_absent
     && Dependability_filesystem.precondition Restore_sealed_record_preimage
        = Target_present
     && Dependability_filesystem.precondition Remove_disposable_scope
        = Target_present);
  let prepare role =
    Dependability_filesystem.prepare ~root ~role ~target
      ~precondition:(Dependability_filesystem.precondition role)
    |> get
  in
  let wrong_precondition =
    Dependability_filesystem.prepare ~root ~role:Observe_tree ~target
      ~precondition:Target_absent
  in
  check "F4 preparation rejects a role/precondition mismatch"
    (wrong_precondition
     = Error Dependability_filesystem.Role_precondition_mismatch);
  check "F5 every operational entrypoint fails closed until the descriptor backend exists"
    (unavailable (Dependability_filesystem.observe_tree (prepare Observe_tree))
     && unavailable (Dependability_filesystem.observe_object (prepare Observe_object))
     && unavailable
          (Dependability_filesystem.materialize_candidate
             (prepare Materialize_candidate))
     && unavailable
          (Dependability_filesystem.write_partition (prepare Write_partition))
     && unavailable
          (Dependability_filesystem.restore_partition
             (prepare Restore_partition))
     && unavailable
          (Dependability_filesystem.write_sealed_record_candidate
             (prepare Write_sealed_record_candidate))
     && unavailable
          (Dependability_filesystem.restore_sealed_record_preimage
             (prepare Restore_sealed_record_preimage))
     && unavailable
          (Dependability_filesystem.remove_disposable_scope
             (prepare Remove_disposable_scope)));
  check "F6 prepared identities bind root role target and precondition"
    (Dependability_filesystem.prepared_digest (prepare Observe_tree)
     <> Dependability_filesystem.prepared_digest (prepare Observe_object)
     && String.length (Dependability_filesystem.prepared_digest
                         (prepare Observe_tree)) = 64);
  check "F7 source identity kills every named authority mutant"
    (String.length Dependability_filesystem.source_digest = 64
     && List.for_all
          (fun mutation ->
             Dependability_filesystem.source_digest
             <> Dependability_filesystem.For_test.source_digest_with_mutation
                  mutation)
          [ Dependability_filesystem.For_test.Drop_resolve_beneath;
            Drop_resolve_no_xdev; Permit_parent_segment; Promote_backend;
            Widen_target_bound; Drop_role_precondition ]);
  let self =
    Suite_telemetry.observe ~suite:"test_dependability_filesystem"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_filesystem ]);
  exit (Suite_telemetry.exit_code self)
