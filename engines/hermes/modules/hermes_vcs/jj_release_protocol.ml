module Digest = struct
  type t = string

  let is_lower_hex = function
    | '0' .. '9' | 'a' .. 'f' -> true
    | _ -> false

  let make value =
    if String.length value = 64 && String.for_all is_lower_hex value
    then Ok value
    else Error (Jj_error.make Jj_error.Noncanonical_identity
      ~detail:"release digest must be 64 lowercase hexadecimal characters")

  let to_string value = value
end

type identities = {
  tag : Digest.t;
  commit : Digest.t;
  tree : Digest.t;
  archive : Digest.t;
  documentation : Digest.t;
  executable : Digest.t;
  config : Digest.t;
}

type pin = { release_id : Jj_id.Request.t; identities : identities; digest : string }
type bundle = { pin : pin; digest : string }

type mismatch =
  | Tag_mismatch
  | Commit_mismatch
  | Tree_mismatch
  | Archive_mismatch
  | Documentation_mismatch
  | Executable_mismatch
  | Config_mismatch

let sha256 value = Digestif.SHA256.(to_hex (digest_string value))

let canonical release_id identities =
  Jj_id.length_frame
    [ Jj_id.Request.to_string release_id;
      Digest.to_string identities.tag;
      Digest.to_string identities.commit;
      Digest.to_string identities.tree;
      Digest.to_string identities.archive;
      Digest.to_string identities.documentation;
      Digest.to_string identities.executable;
      Digest.to_string identities.config ]

let pin ~release_id ~tag ~commit ~tree ~archive ~documentation ~executable
    ~config =
  let identities = { tag; commit; tree; archive; documentation; executable; config } in
  { release_id; identities; digest = sha256 ("release-pin:" ^ canonical release_id identities) }

let mismatches expected observed =
  let add differs mismatch values = if differs then mismatch :: values else values in
  []
  |> add (expected.config <> observed.config) Config_mismatch
  |> add (expected.executable <> observed.executable) Executable_mismatch
  |> add (expected.documentation <> observed.documentation) Documentation_mismatch
  |> add (expected.archive <> observed.archive) Archive_mismatch
  |> add (expected.tree <> observed.tree) Tree_mismatch
  |> add (expected.commit <> observed.commit) Commit_mismatch
  |> add (expected.tag <> observed.tag) Tag_mismatch

let observe ~pin:pinned ~tag ~commit ~tree ~archive ~documentation ~executable
    ~config =
  let observed = { tag; commit; tree; archive; documentation; executable; config } in
  match mismatches pinned.identities observed with
  | _ :: _ as errors -> Error errors
  | [] ->
      Ok { pin = pinned;
        digest = sha256 ("release-bundle:" ^ pinned.digest ^ canonical pinned.release_id observed) }

let pin_digest (value : pin) = value.digest
let bundle_digest (value : bundle) = value.digest

let source_digest =
  Jj_id.length_frame
    [ "release-pin-v1"; "tag"; "commit"; "tree"; "archive";
      "documentation"; "executable"; "config"; "exact-observation-v1" ]
  |> sha256
