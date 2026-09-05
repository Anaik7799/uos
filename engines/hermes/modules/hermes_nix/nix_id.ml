module type ID = sig
  type t
  val make : string -> (t, string) result
  val of_string_exn : string -> t
  val to_string : t -> string
  val equal : t -> t -> bool
  val compare : t -> t -> int
end

let is_valid_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '-' || c = '_' || c = '.' || c = '/' || c = '#' || c = ':' || c = '@' || c = '+' || c = '?' || c = '=' || c = '&'

let validate_id name s max_len =
  let len = String.length s in
  if len = 0 then Error (Printf.sprintf "%s cannot be empty" name)
  else if len > max_len then Error (Printf.sprintf "%s exceeds maximum length of %d" name max_len)
  else
    let ok = ref true in
    for i = 0 to len - 1 do
      if not (is_valid_char s.[i]) then ok := false
    done;
    if !ok then Ok s else Error (Printf.sprintf "%s contains invalid character" name)

module Make (M : sig val name : string val max_len : int end) : ID = struct
  type t = string
  let make s = validate_id M.name s M.max_len
  let of_string_exn s =
    match make s with
    | Ok v -> v
    | Error msg -> failwith msg
  let to_string s = s
  let equal (a : string) (b : string) = String.equal a b
  let compare (a : string) (b : string) = String.compare a b
end

module Store_path = Make(struct let name = "Store_path" let max_len = 512 end)
module Derivation_hash = Make(struct let name = "Derivation_hash" let max_len = 128 end)
module Flake_ref = Make(struct let name = "Flake_ref" let max_len = 512 end)
module Flake_url = Make(struct let name = "Flake_url" let max_len = 512 end)
module Attribute_path = Make(struct let name = "Attribute_path" let max_len = 256 end)
module Profile_name = Make(struct let name = "Profile_name" let max_len = 128 end)
module Devenv_root = Make(struct let name = "Devenv_root" let max_len = 512 end)
module Devenv_env_name = Make(struct let name = "Devenv_env_name" let max_len = 128 end)
module Process_name = Make(struct let name = "Process_name" let max_len = 128 end)
module Service_name = Make(struct let name = "Service_name" let max_len = 128 end)
module Task_name = Make(struct let name = "Task_name" let max_len = 128 end)
module Receipt_id = Make(struct let name = "Receipt_id" let max_len = 128 end)
module Closure_digest = Make(struct let name = "Closure_digest" let max_len = 128 end)
module Intent_id = Make(struct let name = "Intent_id" let max_len = 128 end)
