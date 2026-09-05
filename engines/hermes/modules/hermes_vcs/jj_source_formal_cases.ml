let failures = ref []
let outcome = ref (0, 0)

let check name condition =
  if not condition then failures := name :: !failures

let expected_constituents =
  [ "jj-id"; "jj-error"; "jj-budget"; "jj-operation"; "jj-revset";
    "jj-path"; "jj-split-manifest"; "jj-action-kind";
    "jj-recovery-schema"; "jj-partition"; "jj-campaign-action";
    "jj-intent"; "jj-codec"; "jj-policy"; "jj-approval";
    "jj-writer-lease"; "mainline-carrier-policy"; "jj-source-manifest";
    "jj-secret-scan"; "jj-readback"; "jj-receipt-core"; "jj-ontology";
    "jj-algebra"; "jj-fpp"; "jj-sysml"; "jj-command-contract";
    "jj-process-protocol"; "jj-target-protocol"; "jj-dependency-schema";
    "jj-release-protocol"; "jj-runtime-manifest";
    "jj-runtime-current-protocol";
    "jj-recovery-transition-port-protocol";
    "jj-completion-store-protocol"; "jj-formal-obligations" ]

let expected_missing = []

let expected_laws =
  [ "canonicalization"; "identity-separation"; "monotone-policy";
    "approval-lease-absorption"; "apply-once-replay"; "output-bounds";
    "exact-readback"; "recovery-anchor-retention"; "source-only-closure";
    "redaction"; "surface-equivalence"; "zero-effect-before-bridge";
    "remote-publish-requires-cas" ]

let fake_digest index =
  Digestif.SHA256.digest_string (Printf.sprintf "constituent-%02d" index)
  |> Digestif.SHA256.to_hex

let () =
  let constituents = Jj_source_authority.constituents in
  let constituent_ids =
    List.map Jj_source_authority.constituent_id constituents
  in
  check "S1 the pure source denominator is exact and ordered"
    (Jj_source_authority.schema_id = "hermes.jj-source-authority.v1"
     && constituent_ids = expected_constituents);
  check "S2 constituent identities are unique"
    (List.length constituent_ids
     = List.length (List.sort_uniq String.compare constituent_ids));
  let missing =
    Jj_source_authority.unavailable_constituents ()
    |> List.map Jj_source_authority.constituent_id
  in
  check "S3 missing digest accessors are exact typed blockers"
    (missing = expected_missing);
  check "S4 the aggregate source digest closes only over the exact denominator"
    (match Jj_source_authority.source_digest () with
     | Error _ -> false
     | Ok digest -> String.length digest = 64);
  let closed = List.mapi (fun index id -> (id, fake_digest index)) expected_constituents in
  let baseline = Jj_source_authority.For_test.compose closed in
  check "S5 a closed exact denominator yields one SHA-256 digest"
    (match baseline with Ok digest -> String.length digest = 64 | Error _ -> false);
  check "S6 every constituent digest changes the aggregate"
    (match baseline with
     | Error _ -> false
     | Ok expected ->
         List.mapi
           (fun index (id, _) ->
             let mutated =
               List.mapi
                 (fun candidate pair ->
                   if candidate = index then (id, fake_digest (index + 100))
                   else pair)
                 closed
             in
             match Jj_source_authority.For_test.compose mutated with
             | Ok actual -> not (String.equal expected actual)
             | Error _ -> false)
           closed
         |> List.for_all Fun.id);
  check "S7 constituent order is source identity"
    (match baseline, Jj_source_authority.For_test.compose (List.rev closed) with
     | Ok left, Error _ -> String.length left = 64
     | _ -> false);
  check "S8 missing, duplicate, unknown, and malformed digest rows refuse"
    (Result.is_error (Jj_source_authority.For_test.compose (List.tl closed))
     && Result.is_error
          (Jj_source_authority.For_test.compose
             (List.hd closed :: closed))
     && Result.is_error
          (Jj_source_authority.For_test.compose
             (("unknown-constituent", fake_digest 99) :: List.tl closed))
     && Result.is_error
          (Jj_source_authority.For_test.compose
             ((List.hd expected_constituents, "not-a-digest")
              :: List.tl closed)));

  let obligations = Jj_formal_obligations.obligations in
  let law_ids = List.map Jj_formal_obligations.law_id obligations in
  check "F1 every pure algebra law has exactly one formal obligation"
    (law_ids = expected_laws && law_ids = List.map Jj_algebra.law_id Jj_algebra.laws);
  check "F2 formal obligation identities and negative controls are injective"
    (let obligation_ids =
       List.map Jj_formal_obligations.obligation_id obligations in
     let controls =
       List.map Jj_formal_obligations.negative_control_id obligations in
     List.length obligation_ids
       = List.length (List.sort_uniq String.compare obligation_ids)
     && List.length controls
        = List.length (List.sort_uniq String.compare controls));
  check "F3 negative-control identities derive exactly from the law"
    (List.for_all
       (fun obligation ->
         String.equal
           (Jj_formal_obligations.negative_control_id obligation)
           ("mutant." ^ Jj_formal_obligations.law_id obligation))
       obligations);
  check "F4 no static obligation invents theorem or parity credit"
    (List.for_all
       (fun obligation ->
         Jj_formal_obligations.availability obligation
           = Jj_formal_obligations.Unavailable_observed
         && Jj_formal_obligations.credit_limit obligation
            = Jj_formal_obligations.No_formal_or_parity_credit)
       obligations);
  check "F5 obligation statements are nonempty exact algebra projections"
    (List.for_all2
       (fun obligation law ->
         String.trim (Jj_formal_obligations.statement obligation) <> ""
         && String.equal
              (Jj_formal_obligations.statement obligation)
              (Jj_algebra.law_statement law))
       obligations Jj_algebra.laws);
  check "F6 the formal registry validates without executing a solver"
    (Jj_formal_obligations.validate () = []
     && Jj_formal_obligations.schema_id = "hermes.jj-formal-obligations.v1"
     && String.length Jj_formal_obligations.source_digest = 64);
  check "F7 a missing control, false credit, and denominator drift are rejected"
    (List.for_all
       (fun mutation ->
         Jj_formal_obligations.For_test.validate_with_mutation mutation <> [])
       [ Jj_formal_obligations.For_test.Drop_obligation;
         Duplicate_obligation; Drop_negative_control; Invent_credit;
         Reorder_obligations ]);

  List.iter (fun name -> Printf.eprintf "FAIL %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  outcome := (15 - failed, failed)
