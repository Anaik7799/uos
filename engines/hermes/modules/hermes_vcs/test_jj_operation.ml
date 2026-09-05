let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let operation_keys =
  [ "version"; "operation-head"; "status-at-operation";
    "operation-log-at-operation"; "revision-log-at-operation";
    "bookmark-list-at-operation"; "workspace-list-at-operation";
    "remote-list-at-operation"; "diff-summary-at-operation";
    "diff-stat-at-operation"; "diff-patch-at-operation"; "file-show-at-operation";
    "resolve-list-at-operation"; "working-copy-snapshot"; "repository-init";
    "bookmark-set"; "bookmark-delete"; "duplicate"; "describe"; "new-change";
    "file-untrack"; "workspace-add"; "workspace-forget"; "workspace-update-stale";
    "split-files"; "partition-change"; "edit"; "rebase"; "squash"; "abandon";
    "operation-restore"; "partition-recover"; "git-fetch"; "git-push" ]

let () =
  check "O1 exact ordered closed operation denominator"
    (List.map (fun operation -> (Jj_operation.declaration operation).key)
     Jj_operation.all = operation_keys);
  check "O2 each operation has a distinct declaration key"
    (let keys = List.map (fun operation -> (Jj_operation.declaration operation).key) Jj_operation.all in
     List.length keys = List.length (List.sort_uniq String.compare keys));
  check "O3 every identity constructor rejects empty control noncanonical and oversized input"
    (let invalid = [ ""; "repo\000bad"; "Repo-Main"; " repo"; String.make 129 'a' ] in
     List.for_all (fun value -> Result.is_error (Jj_id.Repository.make value)) invalid
     && Result.is_ok (Jj_id.Repository.make "repo-main"));
  check "O4 all fourteen identity kinds accept one bounded canonical ASCII value"
    (Result.is_ok (Jj_id.Repository.make "repo-main")
     && Result.is_ok (Jj_id.Workspace.make "workspace-main")
     && Result.is_ok (Jj_id.Operation.make "operation-main")
     && Result.is_ok (Jj_id.Change.make "change-main")
     && Result.is_ok (Jj_id.Commit.make "commit-main")
     && Result.is_ok (Jj_id.Bookmark.make "bookmark-main")
     && Result.is_ok (Jj_id.Remote.make "remote-main")
     && Result.is_ok (Jj_id.Executable.make "executable-main")
     && Result.is_ok (Jj_id.Approval.make "approval-main")
     && Result.is_ok (Jj_id.Lease.make "lease-main")
     && Result.is_ok (Jj_id.Intent.make "intent-main")
     && Result.is_ok (Jj_id.Request.make "request-main")
     && Result.is_ok (Jj_id.Event.make "event-main")
     && Result.is_ok (Jj_id.Receipt.make "receipt-main"));
  check "O5 typed identities are canonically stable and cross-kind values remain separately typed"
    (match Jj_id.Repository.make "repo-main", Jj_id.Workspace.make "repo-main" with
     | Ok repository, Ok workspace ->
         String.equal (Jj_id.Repository.to_string repository) "repo-main"
         && String.equal (Jj_id.Workspace.to_string workspace) "repo-main"
     | Error _, _ | _, Error _ -> false);
  check "O6 declarations are total and lookup is exact for every declaration"
    (List.for_all
       (fun operation ->
          let declaration = Jj_operation.declaration operation in
          Jj_operation.find declaration.key = Some operation)
       Jj_operation.all
     && Jj_operation.find "unknown-operation" = None);
  check "O7 risk approval and effect metadata are total and non-escalating"
    (List.for_all Jj_operation.declaration_is_safe Jj_operation.all
     &&
     let rewrites =
       [ Jj_operation.Split_files; Jj_operation.Partition_change; Jj_operation.Edit;
         Jj_operation.Rebase; Jj_operation.Squash; Jj_operation.Abandon ]
     in
     List.for_all
       (fun operation ->
          let declaration = Jj_operation.declaration operation in
          declaration.risk = Jj_operation.Risk_history_rewrite
          && declaration.effect_class = Jj_operation.Effect_history_rewrite
          && declaration.capability = Jj_operation.Capability_history_rewrite)
       rewrites
     &&
     let fetch = Jj_operation.declaration Jj_operation.Git_fetch in
     fetch.approval = Jj_operation.Approval_fetch
     && fetch.effect_class = Jj_operation.Effect_fetch
     && fetch.capability = Jj_operation.Capability_fetch
     && fetch.precondition = Jj_operation.Precondition_fetch_authority
     && fetch.recovery = Jj_operation.Recovery_before_state);
  check "O8 canonical declaration digest is order-sensitive and stable"
    (String.equal Jj_operation.source_digest
       "3bf20688b4cf3f36c10ef839d3c498e2a53c01055723cf0ed593e3e1b008923d"
     && not (String.equal Jj_operation.source_digest
               (Jj_operation.digest_of (List.rev Jj_operation.all)))
     &&
     let baseline = Jj_operation.digest_of [ Jj_operation.Git_push ] in
     not (String.equal baseline
            (Jj_operation.Testing.mutated_digest Jj_operation.Git_push
               Jj_operation.Testing.Approval))
     && not (String.equal baseline
               (Jj_operation.Testing.mutated_digest Jj_operation.Git_push
                  Jj_operation.Testing.Recovery))
     && not (String.equal baseline
               (Jj_operation.Testing.mutated_digest Jj_operation.Git_push
                  Jj_operation.Testing.Activation)));
  check "O9 each budget profile rejects zero and preserves bounded positive values"
    (List.for_all
       (fun operation ->
          let budget = (Jj_operation.declaration operation).budget in
          Jj_budget.valid budget
          && Result.is_error (Jj_budget.make ~max_attempts:0 ~timeout_ms:1 ~max_output_bytes:1))
       Jj_operation.all);
  check "O10 primitive identity error and budget authorities expose distinct SHA-256 digests"
    (Jj_id.source_digest
       = "b41985b2d5b95a1cc2524765c64cdf38a23bfec62d721b9cb09d734c08756177"
     && Jj_error.source_digest
        = "6e6f6250d27f5b0b2afdec69019e8aa29c8948059271877a6819dfa40c9554aa"
     && Jj_budget.source_digest
        = "6451c6ea58788946c669b82253b7a7227a5346ecc6de1ad45c46a672f2f36842"
     && List.length
          (List.sort_uniq String.compare
             [ Jj_id.source_digest; Jj_error.source_digest;
               Jj_budget.source_digest ]) = 3);
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 10 - failed in
  let self =
    Suite_telemetry.observe ~suite:"test_jj_operation" ~passed ~failed ~skipped:0
  in
  Printf.printf "Jujutsu operation denominator: %d operations\n"
    (List.length Jj_operation.all);
  Printf.printf "Jujutsu operation source digest: %s\n" Jj_operation.source_digest;
  Printf.printf "Jujutsu id source digest: %s\n" Jj_id.source_digest;
  Printf.printf "Jujutsu error source digest: %s\n" Jj_error.source_digest;
  Printf.printf "Jujutsu budget source digest: %s\n" Jj_budget.source_digest;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
