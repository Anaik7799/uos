open Dependability_owner_inventory

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let get = function Ok value -> value | Error refusal -> failwith (refusal_code refusal)
let is_error = function Error _ -> true | Ok _ -> false
let id value = get (Identity.make value)

let context suffix =
  get
    (make_context ~manifest:(id ("manifest-" ^ suffix))
       ~owner_session:(id ("session-" ^ suffix))
       ~recovery_attempt:(id ("attempt-" ^ suffix))
       ~challenge:(id ("challenge-" ^ suffix))
       ~transition:(id ("transition-" ^ suffix)))

let denominator labels =
  let identities = List.map id labels in
  get (make_denominator ~expected:identities ~observed:identities)

let inventory_bundle context =
  ( get
      (prepare_fragment ~role:Activation ~context
         ~denominator:(denominator [ "activation-row" ])
         ~owner_readback:(id "activation-readback")),
    get
      (prepare_fragment ~role:Writer_fence ~context
         ~denominator:(denominator [ "writer-row" ])
         ~owner_readback:(id "writer-readback")),
    get
      (prepare_fragment ~role:Dispatch ~context
         ~denominator:(denominator [ "dispatch-row" ])
         ~owner_readback:(id "dispatch-readback")),
    get
      (prepare_fragment ~role:Recovery_vault ~context
         ~denominator:(denominator [ "vault-row" ])
         ~owner_readback:(id "vault-readback")),
    get
      (prepare_fragment ~role:Completion_store ~context
         ~denominator:(denominator [ "completion-row" ])
         ~owner_readback:(id "completion-readback")) )

let prepare_inventory (activation, writer_fence, dispatch, recovery_vault,
    completion_store) =
  prepare_manifest ~activation ~writer_fence ~dispatch ~recovery_vault
    ~completion_store

let terminal_bundle context =
  let activation, writer_fence, dispatch, recovery_vault, completion_store =
    inventory_bundle context
  in
  ( get
      (prepare_terminal_fragment ~fragment:activation
         ~unresolved_obligations:0
         ~readback:
           (Activation_terminal_readback
              { current_pointer = id "activation-pointer" })),
    get
      (prepare_terminal_fragment ~fragment:writer_fence
         ~unresolved_obligations:0
         ~readback:
           (Writer_fence_terminal_readback
              { mutation_frontier = id "terminal-frontier";
                fence = id "terminal-fence" })),
    get
      (prepare_terminal_fragment ~fragment:dispatch
         ~unresolved_obligations:0
         ~readback:
           (Dispatch_terminal_readback
              { dispatch_readback = id "terminal-dispatch" })),
    get
      (prepare_terminal_fragment ~fragment:recovery_vault
         ~unresolved_obligations:0
         ~readback:
           (Recovery_vault_terminal_readback
              { vault_readback = id "terminal-vault" })),
    get
      (prepare_terminal_fragment ~fragment:completion_store
         ~unresolved_obligations:0
         ~readback:
           (Completion_store_terminal_readback
              { completion_readback = id "terminal-completion" })) )

let prepare_terminal (activation, writer_fence, dispatch, recovery_vault,
    completion_store) =
  prepare_terminal_conjunction ~activation ~writer_fence ~dispatch
    ~recovery_vault ~completion_store

let recovery_only_bundle context =
  let activation, writer_fence, dispatch, recovery_vault, completion_store =
    inventory_bundle context
  in
  ( get
      (prepare_recovery_only_terminal_fragment ~fragment:activation
         ~readback:
           (Recovery_activation_terminal_readback
              { causal_transition = id "causal-transition";
                successor_generation_pointer = id "successor-pointer" })),
    get
      (prepare_recovery_only_terminal_fragment ~fragment:writer_fence
         ~readback:
           (Recovery_writer_fence_terminal_readback
              { mutation_frontier = id "recovery-frontier";
                fence = id "recovery-fence" })),
    get
      (prepare_recovery_only_terminal_fragment ~fragment:dispatch
         ~readback:
           (Recovery_dispatch_terminal_readback
              { dispatch_readback = id "recovery-dispatch";
                operation_tree_source_readback = id "operation-tree-source" })),
    get
      (prepare_recovery_only_terminal_fragment ~fragment:recovery_vault
         ~readback:
           (Recovery_vault_readback
              { recovery_readback = id "recovery-vault-readback" })),
    get
      (prepare_recovery_only_terminal_fragment ~fragment:completion_store
         ~readback:
           (Recovery_completion_store_readback
              { completion_readback = id "recovery-completion-readback" })) )

let prepare_recovery_only (activation, writer_fence, dispatch, recovery_vault,
    completion_store) =
  prepare_recovery_only_terminal ~activation ~writer_fence ~dispatch
    ~recovery_vault ~completion_store

(* Compile-time witnesses pin the exact current APIs without fabricating the
   producer seals that only root bootstrap may distribute. *)
let _exact_current_compose activation writer_fence dispatch recovery_vault
    completion_store =
  compose ~activation ~writer_fence ~dispatch ~recovery_vault ~completion_store

let _exact_terminal_compose activation writer_fence dispatch recovery_vault
    completion_store =
  compose_terminal_conjunction ~activation ~writer_fence ~dispatch
    ~recovery_vault ~completion_store

let _exact_conditional_join activation dispatch =
  compose_conditional_terminal ~activation ~dispatch

let _exact_recovery_only_join activation writer_fence dispatch recovery_vault
    completion_store =
  compose_recovery_only_terminal ~activation ~writer_fence ~dispatch
    ~recovery_vault ~completion_store

let () =
  check "A1 the role GADT has the exact closed five-role order"
    (List.map role_id
       [ Pack_role Activation; Pack_role Writer_fence; Pack_role Dispatch;
         Pack_role Recovery_vault; Pack_role Completion_store ]
     = [ "activation"; "writer-fence"; "dispatch"; "recovery-vault";
         "completion-store" ]);
  check "A2 identities are bounded canonical lower-ASCII tokens"
    (Result.is_ok (Identity.make "owner-session-01")
     && List.for_all is_error
          [ Identity.make ""; Identity.make "UPPER"; Identity.make "../escape";
            Identity.make (String.make 129 'a') ]);
  check "A3 a denominator requires a nonempty exact ordered observation"
    (let a = id "row-a" and b = id "row-b" in
     Result.is_ok (make_denominator ~expected:[ a; b ] ~observed:[ a; b ])
     && is_error (make_denominator ~expected:[] ~observed:[])
     && is_error (make_denominator ~expected:[ a; b ] ~observed:[ a ])
     && is_error (make_denominator ~expected:[ a; b ] ~observed:[ b; a ]));
  check "A4 duplicate expected or observed rows are refused"
    (let a = id "row-a" in
     is_error (make_denominator ~expected:[ a; a ] ~observed:[ a ])
     && is_error (make_denominator ~expected:[ a ] ~observed:[ a; a ]));
  check "A5 five prepared owner fragments form one exact nonauthorizing manifest"
    (let prepared = get (prepare_inventory (inventory_bundle (context "one"))) in
     prepared_manifest_status prepared = `Prepared_nonauthorizing
     && String.length (prepared_manifest_digest prepared) = 64);
  check "A6 a cross-session owner fragment refuses manifest composition"
    (let activation, writer_fence, dispatch, recovery_vault, _ =
       inventory_bundle (context "left")
     in
     let _, _, _, _, completion_store = inventory_bundle (context "right") in
     is_error
       (prepare_manifest ~activation ~writer_fence ~dispatch ~recovery_vault
          ~completion_store));
  check "A7 every role readback contributes to the manifest digest"
    (let one = get (prepare_inventory (inventory_bundle (context "repeat"))) in
     let _activation, writer_fence, dispatch, recovery_vault, completion_store =
       inventory_bundle (context "repeat")
     in
     let changed_activation =
       get
         (prepare_fragment ~role:Activation ~context:(context "repeat")
            ~denominator:(denominator [ "activation-row" ])
            ~owner_readback:(id "changed-activation-readback"))
     in
     let changed =
       get
         (prepare_manifest ~activation:changed_activation ~writer_fence ~dispatch
            ~recovery_vault ~completion_store)
     in
     prepared_manifest_digest one <> prepared_manifest_digest changed
     && prepared_manifest_digest one
        = prepared_manifest_digest
            (get (prepare_inventory (inventory_bundle (context "repeat")))));
  check "A8 terminal preparation refuses unresolved obligations"
    (let activation, _, _, _, _ = inventory_bundle (context "unresolved") in
     is_error
       (prepare_terminal_fragment ~fragment:activation
          ~unresolved_obligations:1
          ~readback:
            (Activation_terminal_readback
               { current_pointer = id "activation-pointer" })));
  check "A9 five terminal roles form the exact lower terminal conjunction"
    (let prepared = get (prepare_terminal (terminal_bundle (context "terminal"))) in
     prepared_terminal_status prepared = `Prepared_nonauthorizing
     && String.length (prepared_terminal_digest prepared) = 64);
  check "A10 conditional terminal joins only activation and dispatch"
    (let activation, _, dispatch, _, _ = terminal_bundle (context "conditional") in
     let prepared =
       get (prepare_conditional_terminal ~activation ~dispatch)
     in
     prepared_conditional_terminal_status prepared = `Prepared_nonauthorizing
     && String.length (prepared_conditional_terminal_digest prepared) = 64);
  check "A11 recovery-only terminality is a distinct five-owner causal join"
    (let ordinary =
       get (prepare_terminal (terminal_bundle (context "recovery")))
     in
     let recovery =
       get
         (prepare_recovery_only
            (recovery_only_bundle (context "recovery")))
     in
     prepared_recovery_only_terminal_status recovery = `Prepared_nonauthorizing
     && prepared_terminal_digest ordinary
        <> prepared_recovery_only_terminal_digest recovery);
  check "A12 all lower current joins remain explicitly nonauthorizing"
    (current_join_authority = `Lower_pure_nonauthorizing);
  check "A13 source identity is a deterministic SHA-256 shape"
    (String.length source_digest = 64);
  let self =
    Suite_telemetry.observe ~suite:"test_dependability_owner_inventory"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_owner_inventory ]);
  exit (Suite_telemetry.exit_code self)
