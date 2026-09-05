type attribute_value = String_value of string | Int_value of int64
  | Float_value of float | Bool_value of bool
type attribute = { key : string; value : attribute_value }
type link_kind = Span_link | Event_link | Metric_link | Evidence_link | Profile_link
type link_resolution = Span_resolved of { trace_id : string; span_id : string }
  | Artifact_resolved | Unavailable_observed of string
type link = { kind : link_kind; id : string; digest : string option;
  resolution : link_resolution }
type span = { trace_id : string; span_id : string; parent_span_id : string option;
  name : string; run_id : string; provenance : Run_model.provenance;
  plane : Ops_capability.plane; surface : Ops_capability.surface option;
  coordinate : Ops_capability.coordinate; rca_origin : Ops_capability.rca_origin;
  started_at_ns : int64; ended_at_ns : int64; attributes : attribute list;
  links : link list }

module String_set = Set.Make (String)

let ( let* ) value f = match value with Ok result -> f result | Error _ as error -> error
let finite value = match classify_float value with
  | FP_nan | FP_infinite -> false
  | FP_normal | FP_subnormal | FP_zero -> true
let nonempty label value = if String.trim value = "" then Error (label ^ " must be nonempty") else Ok ()
let lower_hex = function '0' .. '9' | 'a' .. 'f' -> true | _ -> false

let validate_hex label length value =
  if String.length value <> length || not (String.for_all lower_hex value) then
    Error (Printf.sprintf "%s must be %d lowercase hexadecimal characters" label length)
  else if String.for_all (fun character -> character = '0') value then
    Error (label ^ " must not be all zero")
  else Ok ()

let validate_digest = function
  | None -> Ok ()
  | Some value when String.length value = 64 && String.for_all lower_hex value -> Ok ()
  | Some _ -> Error "trace link digest must be 64 lowercase hexadecimal characters"

let unique label values =
  if List.length values = List.length (List.sort_uniq String.compare values) then Ok ()
  else Error (label ^ " must be unique")

let valid_attribute_key key =
  String.length key <= 64 && String.length key > 0
  && String.for_all
       (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '_' | '-' -> true | _ -> false)
       key

let validate_attribute attribute =
  if not (valid_attribute_key attribute.key) then Error "trace attribute key is invalid"
  else if String.starts_with ~prefix:"hermes." attribute.key then
    Error "authored trace attributes cannot shadow reserved hermes.* context"
  else match attribute.value with
    | String_value value when String.length value > 256 ->
        Error "trace string attribute exceeds 256 bytes"
    | Float_value value when not (finite value) -> Error "trace float attribute must be finite"
    | String_value _ | Int_value _ | Float_value _ | Bool_value _ -> Ok ()

let link_kind_string = function
  | Span_link -> "span" | Event_link -> "event" | Metric_link -> "metric"
  | Evidence_link -> "evidence" | Profile_link -> "profile"

let validate_link link =
  let* () = nonempty "trace link id" link.id in
  let* () = if String.length link.id <= 128 then Ok () else Error "trace link id exceeds 128 bytes" in
  let* () =
    match link.kind with
    | Metric_link ->
        if Option.is_some (Run_metrics.find link.id) then Ok ()
        else Error "metric trace link does not resolve to the modeled metric registry"
    | Span_link | Event_link | Evidence_link | Profile_link -> Ok ()
  in
  let* () = validate_digest link.digest in
  match link.kind, link.resolution with
  | Span_link, Span_resolved { trace_id; span_id } ->
      let* () = validate_hex "linked trace id" 32 trace_id in
      let* () = validate_hex "linked span id" 16 span_id in
      if String.equal link.id span_id then Ok ()
      else Error "resolved span link id must equal its target span id"
  | Span_link, Unavailable_observed reason -> nonempty "unavailable span-link reason" reason
  | Span_link, Artifact_resolved -> Error "span link cannot use artifact resolution"
  | (Event_link | Metric_link | Evidence_link | Profile_link), Artifact_resolved ->
      begin match link.digest with
      | Some _ -> Ok ()
      | None -> Error "resolved artifact link requires a content digest"
      end
  | (Event_link | Metric_link | Evidence_link | Profile_link),
      Unavailable_observed reason -> nonempty "unavailable artifact-link reason" reason
  | (Event_link | Metric_link | Evidence_link | Profile_link), Span_resolved _ ->
      Error "artifact link cannot use span resolution"

let validate_span span =
  let* () = validate_hex "trace id" 32 span.trace_id in
  let* () = validate_hex "span id" 16 span.span_id in
  let* () = match span.parent_span_id with None -> Ok () | Some value -> validate_hex "parent span id" 16 value in
  let* () = nonempty "span name" span.name in
  let* () = if String.length span.name <= 128 then Ok () else Error "span name exceeds 128 bytes" in
  let* () = Run_model.validate_head ~run_id:span.run_id ~provenance:span.provenance in
  let* () =
    if span.started_at_ns < 0L || span.ended_at_ns < span.started_at_ns then
      Error "span timestamps are invalid" else Ok () in
  let* () = if List.length span.attributes <= 32 then Ok () else Error "span has more than 32 attributes" in
  let* () = unique "trace attribute keys" (List.map (fun attribute -> attribute.key) span.attributes) in
  let rec attrs = function [] -> Ok () | item :: rest -> let* () = validate_attribute item in attrs rest in
  let* () = attrs span.attributes in
  let* () = if List.length span.links <= 32 then Ok () else Error "span has more than 32 links" in
  let link_ids = List.map (fun link -> link_kind_string link.kind ^ ":" ^ link.id) span.links in
  let* () = unique "trace links" link_ids in
  let rec links = function [] -> Ok () | item :: rest -> let* () = validate_link item in links rest in
  links span.links

let validate_graph spans =
  let* () = if spans = [] then Error "trace graph must be nonempty" else Ok () in
  let rec validate_all = function
    | [] -> Ok ()
    | span :: rest -> let* () = validate_span span in validate_all rest
  in
  let* () = validate_all spans in
  let ids = List.map (fun span -> span.span_id) spans in
  let* () = unique "span ids" ids in
  let roots = List.filter (fun span -> Option.is_none span.parent_span_id) spans in
  let* () = if List.length roots = 1 then Ok () else Error "trace graph must have exactly one root" in
  let first = List.hd spans in
  let* () =
    if List.for_all
        (fun span -> String.equal span.trace_id first.trace_id
          && String.equal span.run_id first.run_id
          && Run_model.equal_provenance span.provenance first.provenance)
        spans then Ok () else Error "trace graph exact-head context is inconsistent"
  in
  let* () =
    if List.for_all
        (fun span -> match span.parent_span_id with
           | None -> true
           | Some parent -> not (String.equal parent span.span_id) && List.mem parent ids)
        spans then Ok () else Error "trace graph contains an orphan or self-parent"
  in
  let* () =
    if List.for_all
        (fun span ->
          List.for_all
            (fun link -> match link.kind, link.resolution with
              | Span_link, Span_resolved target ->
                  String.equal target.trace_id span.trace_id
                  && not (String.equal target.span_id span.span_id)
                  && List.mem target.span_id ids
              | Span_link, Unavailable_observed _ -> true
              | Span_link, Artifact_resolved -> false
              | (Event_link | Metric_link | Evidence_link | Profile_link), _ -> true)
            span.links)
        spans
    then Ok () else Error "trace graph contains an unresolved phantom span link"
  in
  let parent_of id =
    match List.find_opt (fun span -> String.equal span.span_id id) spans with
    | None -> None
    | Some span -> span.parent_span_id
  in
  let rec acyclic_from seen id =
    if String_set.mem id seen then false
    else match parent_of id with
      | None -> true
      | Some parent -> acyclic_from (String_set.add id seen) parent
  in
  if List.for_all (acyclic_from String_set.empty) ids then Ok ()
  else Error "trace graph contains a parent cycle"

let attribute_value_json = function
  | String_value value -> `Assoc [ ("stringValue", `String value) ]
  | Int_value value -> `Assoc [ ("intValue", `String (Int64.to_string value)) ]
  | Float_value value -> `Assoc [ ("doubleValue", `Float value) ]
  | Bool_value value -> `Assoc [ ("boolValue", `Bool value) ]

let attribute_json attribute =
  `Assoc [ ("key", `String attribute.key); ("value", attribute_value_json attribute.value) ]

let span_link_json link =
  match link.kind, link.resolution with
  | Span_link, Span_resolved { trace_id; span_id } ->
      let attributes =
        [ attribute_json { key = "hermes.link.kind";
                           value = String_value (link_kind_string link.kind) };
          attribute_json { key = "hermes.link.id"; value = String_value link.id } ]
        @ match link.digest with None -> [] | Some digest ->
            [ attribute_json { key = "hermes.link.digest"; value = String_value digest } ]
      in
      Some (`Assoc
        [ ("attributes", `List attributes);
          ("spanId", `String span_id);
          ("traceId", `String trace_id) ])
  | _ -> None

let reference_json link =
  let resolution, resolution_fields = match link.resolution with
    | Artifact_resolved -> "resolved", []
    | Unavailable_observed reason ->
        "unavailable-observed", [ ("reason", `String reason) ]
    | Span_resolved _ -> "span-resolved", [] in
  `Assoc
    ([ ("id", `String link.id);
       ("kind", `String (link_kind_string link.kind));
       ("resolution", `String resolution) ]
     @ (match link.digest with None -> [] | Some digest -> [ ("digest", `String digest) ])
     @ resolution_fields)

let plane_string = function
  | Ops_capability.Control_plane -> "control" | Data_plane -> "data"

let span_json span =
  let required_attributes =
    [ { key = "hermes.run.id"; value = String_value span.run_id };
      { key = "hermes.source.revision"; value = String_value span.provenance.source_revision };
      { key = "hermes.configuration.digest"; value = String_value span.provenance.configuration_digest };
      { key = "hermes.authority.digest"; value = String_value span.provenance.authority_digest };
      { key = "hermes.executable.digest"; value = String_value span.provenance.executable_digest };
      { key = "hermes.fractal.level";
        value = String_value (Ops_capability.string_of_level span.coordinate.level) };
      { key = "hermes.ooda.phase";
        value = String_value (Ops_capability.string_of_phase span.coordinate.phase) };
      { key = "hermes.rca.origin";
        value = String_value (Ops_capability.string_of_rca_origin span.rca_origin) };
      { key = "hermes.plane"; value = String_value (plane_string span.plane) } ]
    @ match span.surface with None -> [] | Some surface ->
        [ { key = "hermes.surface";
            value = String_value (Ops_capability.string_of_surface surface) } ]
  in
  let attributes = List.sort (fun left right -> String.compare left.key right.key)
      (required_attributes @ span.attributes) in
  let links = List.sort
      (fun left right -> String.compare (link_kind_string left.kind ^ left.id)
          (link_kind_string right.kind ^ right.id)) span.links in
  let span_links = List.filter
      (fun link -> match link.kind, link.resolution with
         | Span_link, Span_resolved _ -> true | _ -> false) links in
  let references = List.filter
      (fun link -> match link.kind, link.resolution with
         | Span_link, Span_resolved _ -> false | _ -> true) links in
  `Assoc
    [ ("attributes", `List (List.map attribute_json attributes));
      ("endTimeUnixNano", `String (Int64.to_string span.ended_at_ns));
      ("hermesReferences", `List (List.map reference_json references));
      ("links", `List (List.filter_map span_link_json span_links));
      ("name", `String span.name);
      ("parentSpanId", match span.parent_span_id with None -> `String "" | Some id -> `String id);
      ("spanId", `String span.span_id);
      ("startTimeUnixNano", `String (Int64.to_string span.started_at_ns));
      ("traceId", `String span.trace_id) ]

let to_otlp_json spans =
  let* () = validate_graph spans in
  let spans = List.sort (fun left right -> String.compare left.span_id right.span_id) spans in
  let scope =
    `Assoc
      [ ("scope", `Assoc [ ("name", `String "hermes.operations") ]);
        ("spans", `List (List.map span_json spans)) ]
  in
  let resource = `Assoc [ ("scopeSpans", `List [ scope ]) ] in
  Ok (`Assoc [ ("resourceSpans", `List [ resource ]) ])
