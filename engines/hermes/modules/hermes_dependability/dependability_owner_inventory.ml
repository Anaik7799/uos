type refusal =
  | Empty_identity
  | Identity_too_long
  | Noncanonical_identity
  | Empty_denominator
  | Duplicate_expected_identity
  | Duplicate_observed_identity
  | Incomplete_denominator
  | Unresolved_obligations
  | Context_mismatch
  | Role_mismatch
  | Kind_mismatch

let refusal_code = function
  | Empty_identity -> "empty-identity"
  | Identity_too_long -> "identity-too-long"
  | Noncanonical_identity -> "noncanonical-identity"
  | Empty_denominator -> "empty-denominator"
  | Duplicate_expected_identity -> "duplicate-expected-identity"
  | Duplicate_observed_identity -> "duplicate-observed-identity"
  | Incomplete_denominator -> "incomplete-denominator"
  | Unresolved_obligations -> "unresolved-obligations"
  | Context_mismatch -> "context-mismatch"
  | Role_mismatch -> "role-mismatch"
  | Kind_mismatch -> "kind-mismatch"

module Identity = struct
  type t = string

  let canonical_byte = function
    | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' -> true
    | _ -> false

  let make value =
    let length = String.length value in
    if length = 0 then Error Empty_identity
    else if length > 128 then Error Identity_too_long
    else if
      value.[0] = '-' || value.[0] = '.'
      || value.[length - 1] = '-' || value.[length - 1] = '.'
      || not (String.for_all canonical_byte value)
    then Error Noncanonical_identity
    else Ok value

  let to_string value = value
  let equal = String.equal
end

let length_frame fields =
  fields
  |> List.map (fun field -> Printf.sprintf "%d:%s" (String.length field) field)
  |> String.concat ""

let sha256 fields =
  fields |> length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

type context = {
  manifest : Identity.t;
  owner_session : Identity.t;
  recovery_attempt : Identity.t;
  challenge : Identity.t;
  transition : Identity.t;
  digest : string;
}

let make_context ~manifest ~owner_session ~recovery_attempt ~challenge
    ~transition =
  let digest =
    sha256
      [ "owner-inventory-context-v1"; Identity.to_string manifest;
        Identity.to_string owner_session; Identity.to_string recovery_attempt;
        Identity.to_string challenge; Identity.to_string transition ]
  in
  Ok
    { manifest; owner_session; recovery_attempt; challenge; transition; digest }

let context_equal left right =
  Identity.equal left.manifest right.manifest
  && Identity.equal left.owner_session right.owner_session
  && Identity.equal left.recovery_attempt right.recovery_attempt
  && Identity.equal left.challenge right.challenge
  && Identity.equal left.transition right.transition
  && String.equal left.digest right.digest

type denominator = {
  expected : Identity.t list;
  observed : Identity.t list;
  digest : string;
}

let has_duplicate identities =
  let rec loop seen = function
    | [] -> false
    | identity :: rest ->
        if List.exists (Identity.equal identity) seen then true
        else loop (identity :: seen) rest
  in
  loop [] identities

let ordered_equal left right =
  try List.for_all2 Identity.equal left right with Invalid_argument _ -> false

let make_denominator ~expected ~observed =
  if expected = [] then Error Empty_denominator
  else if has_duplicate expected then Error Duplicate_expected_identity
  else if has_duplicate observed then Error Duplicate_observed_identity
  else if not (ordered_equal expected observed) then Error Incomplete_denominator
  else
    Ok
      { expected; observed;
        digest =
          sha256
            ("owner-inventory-denominator-v1"
            :: List.map Identity.to_string expected) }

type activation = |
type writer_fence = |
type dispatch = |
type recovery_vault = |
type completion_store = |

type _ role =
  | Activation : activation role
  | Writer_fence : writer_fence role
  | Dispatch : dispatch role
  | Recovery_vault : recovery_vault role
  | Completion_store : completion_store role

type packed_role = Pack_role : 'role role -> packed_role

let role_key : type r. r role -> string = function
  | Activation -> "activation"
  | Writer_fence -> "writer-fence"
  | Dispatch -> "dispatch"
  | Recovery_vault -> "recovery-vault"
  | Completion_store -> "completion-store"

let role_id (Pack_role role) = role_key role

type inventory_kind = |
type terminal_kind = |
type recovery_only_terminal_kind = |

type _ kind =
  | Inventory_kind : inventory_kind kind
  | Terminal_kind : terminal_kind kind
  | Recovery_only_terminal_kind : recovery_only_terminal_kind kind

let kind_key : type k. k kind -> string = function
  | Inventory_kind -> "inventory"
  | Terminal_kind -> "terminal"
  | Recovery_only_terminal_kind -> "recovery-only-terminal"

type ('kind, 'role) prepared = {
  kind : 'kind kind;
  role : 'role role;
  context : context;
  denominator : denominator;
  fact_digest : string;
  digest : string;
}

type 'role fragment_prepared = (inventory_kind, 'role) prepared
type 'role terminal_fragment_prepared = (terminal_kind, 'role) prepared
type 'role recovery_only_terminal_fragment_prepared =
  (recovery_only_terminal_kind, 'role) prepared

let make_prepared ~kind ~role ~(context : context)
    ~(denominator : denominator) ~facts =
  let fact_digest = sha256 facts in
  let digest =
    sha256
      [ "owner-inventory-prepared-v1"; kind_key kind; role_key role;
        context.digest; denominator.digest; fact_digest ]
  in
  { kind; role; context; denominator; fact_digest; digest }

let prepare_fragment ~role ~context ~denominator ~owner_readback =
  Ok
    (make_prepared ~kind:Inventory_kind ~role ~context ~denominator
       ~facts:
         [ "owner-readback"; role_key role; Identity.to_string owner_readback ])

let prepared_fragment_digest prepared = prepared.digest

type packed_prepared =
  | Packed_prepared : ('kind, 'role) prepared -> packed_prepared

let expected_roles =
  [ "activation"; "writer-fence"; "dispatch"; "recovery-vault";
    "completion-store" ]

let prepare_join ~domain ~expected_kind ~expected_role_keys packed =
  match packed with
  | [] -> Error Role_mismatch
  | Packed_prepared first :: _ ->
      let contexts_match =
        List.for_all
          (fun (Packed_prepared item) ->
            context_equal first.context item.context)
          packed
      in
      let kinds =
        List.map
          (fun (Packed_prepared item) -> kind_key item.kind)
          packed
      in
      let roles =
        List.map
          (fun (Packed_prepared item) -> role_key item.role)
          packed
      in
      if not contexts_match then Error Context_mismatch
      else if not (List.for_all (String.equal expected_kind) kinds) then
        Error Kind_mismatch
      else if roles <> expected_role_keys then Error Role_mismatch
      else
        Ok
          ( first.context,
            sha256
              ([ domain; first.context.digest ]
              @ List.map
                  (fun (Packed_prepared item) -> item.digest)
                  packed) )

type prepared_manifest = {
  prepared_manifest_context : context;
  prepared_manifest_digest_value : string;
}

let prepare_manifest ~activation ~writer_fence ~dispatch ~recovery_vault
    ~completion_store =
  match
    prepare_join ~domain:"owner-inventory-prepared-manifest-v1"
      ~expected_kind:"inventory" ~expected_role_keys:expected_roles
      [ Packed_prepared activation; Packed_prepared writer_fence;
        Packed_prepared dispatch; Packed_prepared recovery_vault;
        Packed_prepared completion_store ]
  with
  | Error _ as error -> error
  | Ok (context, digest) ->
      Ok
        { prepared_manifest_context = context;
          prepared_manifest_digest_value = digest }

let prepared_manifest_digest manifest = manifest.prepared_manifest_digest_value
let prepared_manifest_status _ = `Prepared_nonauthorizing

type activation_producer_seal = { activation_producer : Identity.t }
type writer_fence_producer_seal = { writer_fence_producer : Identity.t }
type dispatch_producer_seal = { dispatch_producer : Identity.t }
type recovery_vault_producer_seal = { recovery_vault_producer : Identity.t }
type completion_store_producer_seal = { completion_store_producer : Identity.t }

type ('kind, 'role) current = {
  prepared : ('kind, 'role) prepared;
  producer_digest : string;
}

type 'role fragment_current = (inventory_kind, 'role) current
type 'role terminal_fragment_current = (terminal_kind, 'role) current
type 'role recovery_only_terminal_fragment_current =
  (recovery_only_terminal_kind, 'role) current

let seal producer prepared =
  { prepared;
    producer_digest =
      sha256
        [ "owner-inventory-producer-seal-v1"; producer; prepared.digest ] }

let seal_activation_current producer prepared =
  seal (Identity.to_string producer.activation_producer) prepared

let seal_writer_fence_current producer prepared =
  seal (Identity.to_string producer.writer_fence_producer) prepared

let seal_dispatch_current producer prepared =
  seal (Identity.to_string producer.dispatch_producer) prepared

let seal_recovery_vault_current producer prepared =
  seal (Identity.to_string producer.recovery_vault_producer) prepared

let seal_completion_store_current producer prepared =
  seal (Identity.to_string producer.completion_store_producer) prepared

type packed_current =
  | Packed_current : ('kind, 'role) current -> packed_current

let current_join ~domain ~expected_kind ~expected_role_keys currents =
  let prepared =
    List.map
      (fun (Packed_current current) -> Packed_prepared current.prepared)
      currents
  in
  match prepare_join ~domain:(domain ^ "-prepared") ~expected_kind
          ~expected_role_keys prepared with
  | Error _ as error -> error
  | Ok (context, prepared_digest) ->
      let producer_digests =
        List.map
          (fun (Packed_current current) -> current.producer_digest)
          currents
      in
      Ok
        ( context,
          sha256 ([ domain; prepared_digest ] @ producer_digests) )

type manifest = {
  manifest_context : context;
  manifest_digest_value : string;
}

let compose ~activation ~writer_fence ~dispatch ~recovery_vault
    ~completion_store =
  match
    current_join ~domain:"owner-inventory-current-manifest-v1"
      ~expected_kind:"inventory" ~expected_role_keys:expected_roles
      [ Packed_current activation; Packed_current writer_fence;
        Packed_current dispatch; Packed_current recovery_vault;
        Packed_current completion_store ]
  with
  | Error _ as error -> error
  | Ok (context, digest) ->
      Ok { manifest_context = context; manifest_digest_value = digest }

let manifest_digest manifest = manifest.manifest_digest_value

type _ terminal_readback =
  | Activation_terminal_readback :
      { current_pointer : Identity.t } -> activation terminal_readback
  | Writer_fence_terminal_readback :
      { mutation_frontier : Identity.t; fence : Identity.t } ->
      writer_fence terminal_readback
  | Dispatch_terminal_readback :
      { dispatch_readback : Identity.t } -> dispatch terminal_readback
  | Recovery_vault_terminal_readback :
      { vault_readback : Identity.t } -> recovery_vault terminal_readback
  | Completion_store_terminal_readback :
      { completion_readback : Identity.t } -> completion_store terminal_readback

let terminal_readback_fields : type r. r terminal_readback -> string list =
  function
  | Activation_terminal_readback { current_pointer } ->
      [ "activation-current-pointer"; Identity.to_string current_pointer ]
  | Writer_fence_terminal_readback { mutation_frontier; fence } ->
      [ "writer-mutation-frontier"; Identity.to_string mutation_frontier;
        "writer-fence"; Identity.to_string fence ]
  | Dispatch_terminal_readback { dispatch_readback } ->
      [ "dispatch-readback"; Identity.to_string dispatch_readback ]
  | Recovery_vault_terminal_readback { vault_readback } ->
      [ "vault-readback"; Identity.to_string vault_readback ]
  | Completion_store_terminal_readback { completion_readback } ->
      [ "completion-readback"; Identity.to_string completion_readback ]

let prepare_terminal_fragment ~fragment ~unresolved_obligations ~readback =
  if unresolved_obligations <> 0 then Error Unresolved_obligations
  else
    Ok
      (make_prepared ~kind:Terminal_kind ~role:fragment.role
         ~context:fragment.context ~denominator:fragment.denominator
         ~facts:
           ([ "zero-unresolved-obligations"; fragment.digest ]
           @ terminal_readback_fields readback))

type prepared_terminal_conjunction = {
  prepared_terminal_context : context;
  prepared_terminal_digest_value : string;
}

let prepare_terminal_conjunction ~activation ~writer_fence ~dispatch
    ~recovery_vault ~completion_store =
  match
    prepare_join ~domain:"owner-inventory-prepared-terminal-v1"
      ~expected_kind:"terminal" ~expected_role_keys:expected_roles
      [ Packed_prepared activation; Packed_prepared writer_fence;
        Packed_prepared dispatch; Packed_prepared recovery_vault;
        Packed_prepared completion_store ]
  with
  | Error _ as error -> error
  | Ok (context, digest) ->
      Ok
        { prepared_terminal_context = context;
          prepared_terminal_digest_value = digest }

let prepared_terminal_digest terminal = terminal.prepared_terminal_digest_value
let prepared_terminal_status _ = `Prepared_nonauthorizing

type terminal_conjunction = {
  terminal_context : context;
  terminal_digest_value : string;
}

let compose_terminal_conjunction ~activation ~writer_fence ~dispatch
    ~recovery_vault ~completion_store =
  match
    current_join ~domain:"owner-inventory-current-terminal-v1"
      ~expected_kind:"terminal" ~expected_role_keys:expected_roles
      [ Packed_current activation; Packed_current writer_fence;
        Packed_current dispatch; Packed_current recovery_vault;
        Packed_current completion_store ]
  with
  | Error _ as error -> error
  | Ok (context, digest) ->
      Ok { terminal_context = context; terminal_digest_value = digest }

let terminal_conjunction_digest terminal = terminal.terminal_digest_value

type prepared_conditional_terminal = {
  prepared_conditional_context : context;
  prepared_conditional_digest_value : string;
}

let prepare_conditional_terminal ~activation ~dispatch =
  match
    prepare_join ~domain:"owner-inventory-prepared-conditional-terminal-v1"
      ~expected_kind:"terminal"
      ~expected_role_keys:[ "activation"; "dispatch" ]
      [ Packed_prepared activation; Packed_prepared dispatch ]
  with
  | Error _ as error -> error
  | Ok (context, digest) ->
      Ok
        { prepared_conditional_context = context;
          prepared_conditional_digest_value = digest }

let prepared_conditional_terminal_digest terminal =
  terminal.prepared_conditional_digest_value

let prepared_conditional_terminal_status _ = `Prepared_nonauthorizing

type conditional_terminal_current = {
  conditional_context : context;
  conditional_digest_value : string;
}

let compose_conditional_terminal ~activation ~dispatch =
  match
    current_join ~domain:"owner-inventory-current-conditional-terminal-v1"
      ~expected_kind:"terminal"
      ~expected_role_keys:[ "activation"; "dispatch" ]
      [ Packed_current activation; Packed_current dispatch ]
  with
  | Error _ as error -> error
  | Ok (context, digest) ->
      Ok
        { conditional_context = context; conditional_digest_value = digest }

let conditional_terminal_digest terminal = terminal.conditional_digest_value

type _ recovery_only_readback =
  | Recovery_activation_terminal_readback :
      { causal_transition : Identity.t;
        successor_generation_pointer : Identity.t } ->
      activation recovery_only_readback
  | Recovery_writer_fence_terminal_readback :
      { mutation_frontier : Identity.t; fence : Identity.t } ->
      writer_fence recovery_only_readback
  | Recovery_dispatch_terminal_readback :
      { dispatch_readback : Identity.t;
        operation_tree_source_readback : Identity.t } ->
      dispatch recovery_only_readback
  | Recovery_vault_readback :
      { recovery_readback : Identity.t } -> recovery_vault recovery_only_readback
  | Recovery_completion_store_readback :
      { completion_readback : Identity.t } ->
      completion_store recovery_only_readback

let recovery_only_readback_fields :
    type r. r recovery_only_readback -> string list = function
  | Recovery_activation_terminal_readback
      { causal_transition; successor_generation_pointer } ->
      [ "causal-recovery-transition"; Identity.to_string causal_transition;
        "successor-generation-current-pointer";
        Identity.to_string successor_generation_pointer ]
  | Recovery_writer_fence_terminal_readback { mutation_frontier; fence } ->
      [ "terminal-mutation-frontier"; Identity.to_string mutation_frontier;
        "terminal-writer-fence"; Identity.to_string fence ]
  | Recovery_dispatch_terminal_readback
      { dispatch_readback; operation_tree_source_readback } ->
      [ "reconciled-dispatch"; Identity.to_string dispatch_readback;
        "operation-tree-source-readback";
        Identity.to_string operation_tree_source_readback ]
  | Recovery_vault_readback { recovery_readback } ->
      [ "recovery-vault-readback"; Identity.to_string recovery_readback ]
  | Recovery_completion_store_readback { completion_readback } ->
      [ "completion-store-readback"; Identity.to_string completion_readback ]

let prepare_recovery_only_terminal_fragment ~fragment ~readback =
  Ok
    (make_prepared ~kind:Recovery_only_terminal_kind ~role:fragment.role
       ~context:fragment.context ~denominator:fragment.denominator
       ~facts:
         (fragment.digest :: "recovery-only-causal-terminal"
         :: recovery_only_readback_fields readback))

type prepared_recovery_only_terminal = {
  prepared_recovery_context : context;
  prepared_recovery_digest_value : string;
}

let prepare_recovery_only_terminal ~activation ~writer_fence ~dispatch
    ~recovery_vault ~completion_store =
  match
    prepare_join ~domain:"owner-inventory-prepared-recovery-only-terminal-v1"
      ~expected_kind:"recovery-only-terminal"
      ~expected_role_keys:expected_roles
      [ Packed_prepared activation; Packed_prepared writer_fence;
        Packed_prepared dispatch; Packed_prepared recovery_vault;
        Packed_prepared completion_store ]
  with
  | Error _ as error -> error
  | Ok (context, digest) ->
      Ok
        { prepared_recovery_context = context;
          prepared_recovery_digest_value = digest }

let prepared_recovery_only_terminal_digest terminal =
  terminal.prepared_recovery_digest_value

let prepared_recovery_only_terminal_status _ = `Prepared_nonauthorizing

type recovery_only_terminal_current = {
  recovery_only_context : context;
  recovery_only_digest_value : string;
}

let compose_recovery_only_terminal ~activation ~writer_fence ~dispatch
    ~recovery_vault ~completion_store =
  match
    current_join ~domain:"owner-inventory-current-recovery-only-terminal-v1"
      ~expected_kind:"recovery-only-terminal"
      ~expected_role_keys:expected_roles
      [ Packed_current activation; Packed_current writer_fence;
        Packed_current dispatch; Packed_current recovery_vault;
        Packed_current completion_store ]
  with
  | Error _ as error -> error
  | Ok (context, digest) ->
      Ok
        { recovery_only_context = context;
          recovery_only_digest_value = digest }

let recovery_only_terminal_digest terminal =
  terminal.recovery_only_digest_value

let current_join_authority = `Lower_pure_nonauthorizing

let source_digest =
  sha256
    [ "dependability-owner-inventory-v1";
      "roles=activation,writer-fence,dispatch,recovery-vault,completion-store";
      "exact-ordered-bounded-denominators";
      "distinct-unconstructible-role-producer-seals";
      "exact-five-argument-inventory-compose";
      "exact-five-argument-terminal-conjunction";
      "activation-dispatch-zero-unresolved-conditional-terminal";
      "distinct-causal-five-owner-recovery-only-terminal";
      "lower-pure-nonauthorizing-no-upper-run-types" ]
