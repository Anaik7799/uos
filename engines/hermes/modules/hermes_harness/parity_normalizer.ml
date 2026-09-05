(* L5: normalize a reference or candidate trace into a comparable form.

   A differential comparison is only as trustworthy as its normalizer. Two
   opposite failures matter, and they pull against each other:

     too little  a run-varying field (a request id, a timestamp) makes every
                 comparison fail, and the suite gets muted or ignored
     too much    an over-eager rule erases a field that actually diverged, and
                 the comparison passes on a difference that matters

   The second is the dangerous one: it manufactures parity. So elision here is
   never inferred from the data. A field is dropped only if its path is
   explicitly declared volatile, and the declaration is part of the recorded
   evidence via [version], so a normalizer change is visible as a different
   normalization version rather than as a silent shift in what "equal" means.

   Object keys are sorted so that key order -- which carries no meaning in
   JSON -- cannot cause a spurious difference. Nothing else is reordered:
   array order is significant and is preserved. *)

type t = {
  version : string;
  volatile_paths : string list;
}

(* A path is dotted from the document root, with [] for "every element of this
   array": "choices[].message.id". *)
let default =
  {
    version = "hermes-parity-v1";
    volatile_paths =
      [ "id"; "created"; "system_fingerprint"; "choices[].message.id";
        "usage.total_time"; "extra_body.session_id" ];
  }

let is_volatile normalizer path = List.mem path normalizer.volatile_paths

let extend_path path segment =
  if path = "" then segment else path ^ "." ^ segment

let array_path path = if path = "" then "[]" else path ^ "[]"

(* Canonical numeric rendering. Two numbers that are equal in value must render
   identically regardless of whether the JSON parser tagged them Int, Intlit or
   Float, otherwise `{"x":1}` and `{"x":1.0}` diverge on spelling alone -- a
   false divergence the fable review caught, since the reference and candidate
   JSON encoders need not agree on integer-versus-float tagging.

   The canonical form is: an integral value is rendered as its shortest integer
   spelling; a non-integral value uses %.17g, which round-trips a float
   exactly. So Int 1, Intlit "1" and Float 1.0 all become "1". *)
let canonical_number ~is_float value =
  if Float.is_integer value && Float.abs value < 1e16 then
    Printf.sprintf "%.0f" value
  else if is_float then Printf.sprintf "%.17g" value
  else Printf.sprintf "%.0f" value

let rec normalize normalizer ~path (value : Yojson.Safe.t) : Yojson.Safe.t =
  match value with
  | `Assoc fields ->
      let kept =
        List.filter_map
          (fun (key, field) ->
            let child = extend_path path key in
            if is_volatile normalizer child then None
            else Some (key, normalize normalizer ~path:child field))
          fields
      in
      (* Key order carries no meaning in JSON; sorting removes it as a source
         of spurious difference. *)
      `Assoc (List.sort (fun (left, _) (right, _) -> String.compare left right) kept)
  | `List values ->
      let child = array_path path in
      (* Array order IS significant and is deliberately preserved. *)
      `List (List.map (normalize normalizer ~path:child) values)
  (* All three numeric tags collapse to one canonical string, so numeric
     equality is not defeated by encoder-chosen tagging. *)
  | `Float value -> `String (canonical_number ~is_float:true value)
  | `Int value -> `String (canonical_number ~is_float:false (float_of_int value))
  | `Intlit value -> (
      match float_of_string_opt value with
      | Some number -> `String (canonical_number ~is_float:false number)
      | None -> `String value)
  | (`String _ | `Bool _ | `Null) as leaf -> leaf

let normalize_document normalizer value = normalize normalizer ~path:"" value

let render normalizer value =
  Yojson.Safe.to_string (normalize_document normalizer value)

(* Equality is defined on the normalized rendering, not on the raw values, so
   that "equal" always means exactly what the recorded normalization version
   says it means. *)
let equal normalizer left right =
  String.equal (render normalizer left) (render normalizer right)

let version normalizer = normalizer.version

(* The declared volatile set is part of the evidence: two runs that disagree
   about what is volatile are not comparable, even at the same version. *)
let describe normalizer =
  normalizer.version ^ "[" ^ String.concat "," (List.sort String.compare normalizer.volatile_paths) ^ "]"
