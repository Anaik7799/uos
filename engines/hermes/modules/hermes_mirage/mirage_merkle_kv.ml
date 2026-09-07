(** Immutable key-value map with deterministic content hashing. *)

module PathMap = Map.Make(struct
  type t = string list
  let compare = compare
end)

type t = {
  tree : string PathMap.t;
}

let create () = {
  tree = PathMap.empty;
}

let key_to_string key = String.concat "/" key

let sha256_hex s =
  Digestif.SHA256.(to_hex (digest_string s))

let add_length_prefixed buffer value =
  Buffer.add_string buffer (string_of_int (String.length value));
  Buffer.add_char buffer ':';
  Buffer.add_string buffer value

let canonical_key key =
  let buffer = Buffer.create 64 in
  Buffer.add_string buffer (string_of_int (List.length key));
  Buffer.add_char buffer ':';
  List.iter (add_length_prefixed buffer) key;
  Buffer.contents buffer

let get t key =
  match PathMap.find_opt key t.tree with
  | Some value -> Ok value
  | None -> Error (`Read_error (Printf.sprintf "key not found: %s" (key_to_string key)))

let set t key value =
  let tree = PathMap.add key value t.tree in
  Ok { tree }

let remove t key =
  let tree = PathMap.remove key t.tree in
  Ok { tree }

let list t prefix =
  let prefix_len = List.length prefix in
  let matches =
    PathMap.fold (fun k _ acc ->
      if List.length k >= prefix_len &&
         List.filteri (fun i _ -> i < prefix_len) k = prefix then
        k :: acc
      else acc
    ) t.tree []
  in
  Ok (List.rev matches)

let digest t key =
  match get t key with
  | Ok value -> Ok (sha256_hex value)
  | Error e -> Error e

let root_hash t =
  let buffer = Buffer.create 256 in
  PathMap.iter (fun key value ->
    add_length_prefixed buffer (canonical_key key);
    add_length_prefixed buffer (sha256_hex value)
  ) t.tree;
  sha256_hex (Buffer.contents buffer)

let branch t =
  { tree = t.tree }

let merge ~our ~their =
  let merged = ref our.tree in
  let conflicts = ref [] in
  PathMap.iter (fun k v_their ->
    match PathMap.find_opt k our.tree with
    | None ->
        merged := PathMap.add k v_their !merged
    | Some v_our ->
        if v_our <> v_their then
          conflicts := (key_to_string k) :: !conflicts
  ) their.tree;
  if !conflicts <> [] then
    Error (Printf.sprintf "merge conflict on keys: %s" (String.concat ", " !conflicts))
  else
    Ok { tree = !merged }
