let maximum_length = 128

module type ID = sig
  type t
  val make : string -> (t, Jj_error.t) result
  val to_string : t -> string
end

let is_ascii_control byte = Char.code byte < 32 || Char.code byte = 127

let is_allowed = function
  | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' | '/' -> true
  | _ -> false

let canonical value =
  let length = String.length value in
  if length = 0 then Error (Jj_error.make Jj_error.Empty_identity ~detail:"empty")
  else if length > maximum_length then
    Error (Jj_error.make Jj_error.Identity_too_long ~detail:"maximum-128-bytes")
  else if String.exists is_ascii_control value then
    Error (Jj_error.make Jj_error.Control_byte ~detail:"ASCII-control-byte")
  else if value.[0] = '-' || value.[0] = '.' || value.[0] = '/'
          || value.[length - 1] = '-' || value.[length - 1] = '.'
          || value.[length - 1] = '/' || not (String.for_all is_allowed value)
  then Error (Jj_error.make Jj_error.Noncanonical_identity ~detail:"bounded-lower-ascii-token")
  else Ok value

module Make () = struct
  type t = string
  let make = canonical
  let to_string value = value
end

let is_lower_hex = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let canonical_sha256 value =
  if String.length value = 64 && String.for_all is_lower_hex value then
    Ok value
  else
    Error
      (Jj_error.make Jj_error.Noncanonical_identity
         ~detail:"sha256-lowerhex-64")

module Make_sha256 () = struct
  type t = string
  let make = canonical_sha256
  let to_string value = value
end

module Repository = Make ()
module Workspace = Make ()
module Operation = Make ()
module Change = Make ()
module Commit = Make ()
module Bookmark = Make ()
module Remote = Make ()
module Executable = Make ()
module Approval = Make ()
module Lease = Make ()
module Intent = Make ()
module Request = Make ()
module Event = Make ()
module Receipt = Make ()
module Formal_source = Make_sha256 ()
module Formal_model = Make_sha256 ()
module Negative_control = Make ()

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let source_digest =
  length_frame
    [ "jj-id-authority-v1"; Jj_error.source_digest;
      "maximum-length"; string_of_int maximum_length;
      "allowed"; "lower-alpha,digit,-,_,.,/";
      "forbidden-boundary"; "-,.,/";
      "control-bytes"; "0-31,127";
      "kinds";
      length_frame
        [ "repository"; "workspace"; "operation"; "change"; "commit";
          "bookmark"; "remote"; "executable"; "approval"; "lease";
          "intent"; "request"; "event"; "receipt"; "formal-source";
          "formal-model"; "negative-control" ];
      "digest-identities"; "formal-source,formal-model:sha256-lowerhex-64";
      "length-frame"; "decimal-byte-length:payload|..." ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
