module Digest = struct
  type t = string
  type error = Invalid_digest

  let is_lower_hex = function
    | '0' .. '9' | 'a' .. 'f' -> true
    | _ -> false

  let make value =
    if String.length value = 64 && String.for_all is_lower_hex value then Ok value
    else Error Invalid_digest

  let of_bytes bytes =
    bytes |> Bytes.to_string |> Digestif.SHA256.digest_string
    |> Digestif.SHA256.to_hex

  let to_string value = value
end

type file_mode = Regular | Executable | Symlink

type file = {
  path : Jj_path.t;
  base_blob : Digest.t;
  current_blob : Digest.t;
  base_mode : file_mode;
  current_mode : file_mode;
}

type range = { start_offset : int; end_offset : int }

type whole = {
  selected : Jj_path.t list;
  remainder : Jj_path.t list;
  digest : string;
}

type partition = {
  path : Jj_path.t;
  current_blob : Digest.t;
  current_mode : file_mode;
  current_bytes : bytes;
  selected : range list;
  remainder : range list;
  selected_digest : Digest.t;
  remainder_digest : Digest.t;
  digest : string;
}

type error = Invalid_file | Empty_manifest | Too_many_entries | Duplicate_path
  | Unknown_selection | Invalid_range | Duplicate_range | Overlap
  | Incomplete_partition | Stale_blob

let maximum_entries = 4096
let maximum_blob_bytes = 16 * 1024 * 1024

let string_of_mode = function
  | Regular -> "regular"
  | Executable -> "executable"
  | Symlink -> "symlink"

let file ~path ~base_blob ~current_blob ~base_mode ~current_mode =
  Ok { path; base_blob; current_blob; base_mode; current_mode }

let range ~start_offset ~end_offset =
  if start_offset < 0 || end_offset <= start_offset then Error Invalid_range
  else Ok { start_offset; end_offset }

let has_duplicate compare values =
  let sorted = List.sort compare values in
  let rec loop = function
    | left :: (right :: _ as tail) -> compare left right = 0 || loop tail
    | _ -> false
  in
  loop sorted

let canonical_file (file : file) =
  Jj_id.length_frame
    [ Jj_path.to_string file.path; Digest.to_string file.base_blob;
      Digest.to_string file.current_blob; string_of_mode file.base_mode;
      string_of_mode file.current_mode ]

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let whole ~source_authority ~files ~selected =
  let file_count = List.length files in
  let selected_count = List.length selected in
  let file_paths = List.map (fun (item : file) -> item.path) files in
  if file_count = 0 || selected_count = 0 then Error Empty_manifest
  else if file_count > maximum_entries || selected_count > maximum_entries then
    Error Too_many_entries
  else if has_duplicate Jj_path.compare file_paths
          || has_duplicate Jj_path.compare selected
  then Error Duplicate_path
  else if
    List.exists
      (fun path -> not (List.exists (Jj_path.equal path) file_paths))
      selected
  then Error Unknown_selection
  else
    let is_selected path = List.exists (Jj_path.equal path) selected in
    let selected_files =
      List.filter (fun (item : file) -> is_selected item.path) files in
    let remainder_files =
      List.filter (fun (item : file) -> not (is_selected item.path)) files in
    if remainder_files = [] then Error Empty_manifest
    else
      let selected_paths = List.map (fun (item : file) -> item.path) selected_files in
      let remainder_paths = List.map (fun (item : file) -> item.path) remainder_files in
      let canonical =
        Jj_id.length_frame
          ([ "whole-v1"; Digest.to_string source_authority ]
           @ List.map canonical_file files
           @ [ Jj_id.length_frame (List.map Jj_path.to_string selected_paths) ])
      in
      Ok { selected = selected_paths; remainder = remainder_paths;
           digest = sha256 canonical }

let whole_selected (value : whole) = value.selected
let whole_remainder (value : whole) = value.remainder
let whole_digest (value : whole) = value.digest

let compare_range left right =
  match compare left.start_offset right.start_offset with
  | 0 -> compare left.end_offset right.end_offset
  | result -> result

let ordered_nonoverlapping ranges =
  let rec loop previous_end = function
    | [] -> true
    | item :: tail ->
        item.start_offset >= previous_end
        && loop item.end_offset tail
  in
  ranges = List.sort compare_range ranges && loop 0 ranges

let bytes_for_ranges bytes ranges =
  let total =
    List.fold_left
      (fun count item -> count + item.end_offset - item.start_offset)
      0 ranges
  in
  let output = Bytes.create total in
  let _ =
    List.fold_left
      (fun output_offset item ->
        let length = item.end_offset - item.start_offset in
        Bytes.blit bytes item.start_offset output output_offset length;
        output_offset + length)
      0 ranges
  in
  output

let exact_partition length selected remainder =
  let all = List.sort compare_range (selected @ remainder) in
  let rec loop expected = function
    | [] -> expected = length
    | item :: tail ->
        item.start_offset = expected && loop item.end_offset tail
  in
  loop 0 all

let canonical_range item =
  Jj_id.length_frame
    [ string_of_int item.start_offset; string_of_int item.end_offset ]

let partition ~source_authority ~path ~base_blob ~current_blob ~base_mode
    ~current_mode ~base_bytes ~current_bytes ~selected ~remainder =
  let base_length = Bytes.length base_bytes in
  let current_length = Bytes.length current_bytes in
  if base_length > maximum_blob_bytes || current_length > maximum_blob_bytes
     || List.length selected > maximum_entries
     || List.length remainder > maximum_entries
  then Error Too_many_entries
  else if selected = [] || remainder = [] then Error Empty_manifest
  else if not (String.equal (Digest.to_string (Digest.of_bytes base_bytes))
                         (Digest.to_string base_blob))
          || not (String.equal (Digest.to_string (Digest.of_bytes current_bytes))
                              (Digest.to_string current_blob))
  then Error Stale_blob
  else if has_duplicate compare_range selected
          || has_duplicate compare_range remainder
  then Error Duplicate_range
  else if
    List.exists
      (fun item -> item.end_offset > current_length)
      (selected @ remainder)
  then Error Invalid_range
  else if not (ordered_nonoverlapping selected)
          || not (ordered_nonoverlapping remainder)
  then Error Overlap
  else if not (exact_partition current_length selected remainder) then
    let combined = List.sort compare_range (selected @ remainder) in
    let rec overlaps = function
      | left :: (right :: _ as tail) ->
          right.start_offset < left.end_offset || overlaps tail
      | _ -> false
    in
    if overlaps combined then Error Overlap else Error Incomplete_partition
  else
    let selected_bytes = bytes_for_ranges current_bytes selected in
    let remainder_bytes = bytes_for_ranges current_bytes remainder in
    let selected_digest = Digest.of_bytes selected_bytes in
    let remainder_digest = Digest.of_bytes remainder_bytes in
    let canonical =
      Jj_id.length_frame
        ([ "partition-v1"; Digest.to_string source_authority;
           Jj_path.to_string path; Digest.to_string base_blob;
           Digest.to_string current_blob; string_of_mode base_mode;
           string_of_mode current_mode; Digest.to_string selected_digest;
           Digest.to_string remainder_digest ]
         @ List.map canonical_range selected
         @ [ "remainder" ] @ List.map canonical_range remainder)
    in
    Ok { path; current_blob; current_mode; current_bytes = Bytes.copy current_bytes;
         selected; remainder;
         selected_digest; remainder_digest; digest = sha256 canonical }

let partition_reconstructs value =
  exact_partition (Bytes.length value.current_bytes) value.selected value.remainder

let partition_path (value : partition) = value.path
let partition_current_blob (value : partition) = value.current_blob
let partition_current_mode (value : partition) = value.current_mode
let partition_selected_digest (value : partition) = value.selected_digest
let partition_remainder_digest (value : partition) = value.remainder_digest
let partition_digest (value : partition) = value.digest

let source_digest =
  Jj_id.length_frame
    [ "jj-split-manifest-authority-v1"; Jj_id.source_digest;
      Jj_path.source_digest;
      "digest"; "sha256-lower-hex"; "digest-length"; "64";
      "bounds"; string_of_int maximum_entries;
      string_of_int maximum_blob_bytes;
      "file-modes";
      Jj_id.length_frame
        (List.map string_of_mode [ Regular; Executable; Symlink ]);
      "errors";
      Jj_id.length_frame
        [ "invalid-file"; "empty-manifest"; "too-many-entries";
          "duplicate-path"; "unknown-selection"; "invalid-range";
          "duplicate-range"; "overlap"; "incomplete-partition";
          "stale-blob" ];
      "schemas"; Jj_id.length_frame [ "whole-v1"; "partition-v1" ];
      "partition-law"; "ordered-disjoint-exact-cover" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
