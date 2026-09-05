type backend = No_xdev_unavailable

type role =
  | Observe_tree
  | Observe_object
  | Materialize_candidate
  | Write_partition
  | Restore_partition
  | Write_sealed_record_candidate
  | Restore_sealed_record_preimage
  | Remove_disposable_scope

type precondition = Target_present | Target_absent

type error =
  | Invalid_root
  | Invalid_relative_target
  | Role_precondition_mismatch
  | Unavailable_observed

type root = Root of string
type target = Target of string
type prepared = {
  root : root;
  role : role;
  target : target;
  precondition : precondition;
  digest : string;
}

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let maximum_root_length = 64
let maximum_target_length = 256

let root_character = function
  | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' -> true
  | _ -> false

let target_character = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> true
  | _ -> false

let root value =
  let length = String.length value in
  if length = 0 || length > maximum_root_length
     || not (String.for_all root_character value)
     || value.[0] = '.' || value.[length - 1] = '.'
  then Error Invalid_root
  else Ok (Root value)

let valid_segment segment =
  String.length segment > 0
  && not (String.equal segment ".")
  && not (String.equal segment "..")
  && String.for_all target_character segment

let target value =
  let length = String.length value in
  if length = 0 || length > maximum_target_length
     || value.[0] = '/' || String.contains value '\\'
     || not (List.for_all valid_segment (String.split_on_char '/' value))
  then Error Invalid_relative_target
  else Ok (Target value)

let backend () = No_xdev_unavailable

let precondition = function
  | Observe_tree | Observe_object | Write_partition | Restore_partition
  | Restore_sealed_record_preimage | Remove_disposable_scope -> Target_present
  | Materialize_candidate | Write_sealed_record_candidate -> Target_absent

let role_key = function
  | Observe_tree -> "observe-tree"
  | Observe_object -> "observe-object"
  | Materialize_candidate -> "materialize-candidate"
  | Write_partition -> "write-partition"
  | Restore_partition -> "restore-partition"
  | Write_sealed_record_candidate -> "write-sealed-record-candidate"
  | Restore_sealed_record_preimage -> "restore-sealed-record-preimage"
  | Remove_disposable_scope -> "remove-disposable-scope"

let precondition_key = function
  | Target_present -> "target-present"
  | Target_absent -> "target-absent"

let authority_digest ?(resolve_beneath = true) ?(resolve_no_xdev = true)
    ?(reject_parent = true) ?(backend_unavailable = true)
    ?(target_bound = maximum_target_length) ?(role_schema = true) () =
  length_frame
    [ "dependability-filesystem-authority-v1";
      "descriptor-relative"; string_of_bool resolve_beneath;
      "resolve-no-xdev"; string_of_bool resolve_no_xdev;
      "reject-parent-segments"; string_of_bool reject_parent;
      "backend-unavailable"; string_of_bool backend_unavailable;
      "maximum-root-length"; string_of_int maximum_root_length;
      "maximum-target-length"; string_of_int target_bound;
      "role-precondition-schema"; string_of_bool role_schema;
      "roles";
      length_frame
        [ "observe-tree:target-present"; "observe-object:target-present";
          "materialize-candidate:target-absent";
          "write-partition:target-present";
          "restore-partition:target-present";
          "write-sealed-record-candidate:target-absent";
          "restore-sealed-record-preimage:target-present";
          "remove-disposable-scope:target-present" ];
      "current-readback-apply-once"; "forbidden" ]
  |> sha256

let source_digest = authority_digest ()

let root_key (Root value) = value
let target_key (Target value) = value

let prepare ~root ~role ~target ~precondition:actual =
  if actual <> precondition role then Error Role_precondition_mismatch
  else
    let digest =
      length_frame
        [ "dependability-filesystem-prepared-v1"; source_digest;
          root_key root; role_key role; target_key target;
          precondition_key actual ]
      |> sha256
    in
    Ok { root; role; target; precondition = actual; digest }

let prepared_digest prepared = prepared.digest
let unavailable _prepared = Error Unavailable_observed
let observe_tree = unavailable
let observe_object = unavailable
let materialize_candidate = unavailable
let write_partition = unavailable
let restore_partition = unavailable
let write_sealed_record_candidate = unavailable
let restore_sealed_record_preimage = unavailable
let remove_disposable_scope = unavailable

module For_test = struct
  type mutation =
    | Drop_resolve_beneath
    | Drop_resolve_no_xdev
    | Permit_parent_segment
    | Promote_backend
    | Widen_target_bound
    | Drop_role_precondition

  let source_digest_with_mutation = function
    | Drop_resolve_beneath -> authority_digest ~resolve_beneath:false ()
    | Drop_resolve_no_xdev -> authority_digest ~resolve_no_xdev:false ()
    | Permit_parent_segment -> authority_digest ~reject_parent:false ()
    | Promote_backend -> authority_digest ~backend_unavailable:false ()
    | Widen_target_bound -> authority_digest ~target_bound:257 ()
    | Drop_role_precondition -> authority_digest ~role_schema:false ()
end
