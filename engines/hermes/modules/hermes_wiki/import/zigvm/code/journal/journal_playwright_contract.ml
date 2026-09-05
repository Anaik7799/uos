type observation = {
  viewport_width : float;
  root_width : float;
  heading_count : int;
  artifact_count : int;
  prompt_ledger_count : int;
  remote_resource_count : int;
  remote_css_reference_count : int;
  required_prompt_marker_count : int;
  expected_prompt_marker_count : int;
  console_errors : string list;
  page_errors : string list;
}

type route_identity = {
  expected_title : string;
  observed_title : string;
  expected_sha256 : string;
  observed_sha256 : string;
}

type violation =
  | Horizontal_overflow of float
  | Missing_heading
  | Missing_artifacts
  | Missing_prompt_ledgers of int
  | Remote_resources of int
  | Remote_css_references of int
  | Missing_prompt_markers of { actual : int; expected : int }
  | Wrong_route_title of { expected : string; observed : string }
  | Wrong_route_body of { expected : string; observed : string }
  | Console_error of string
  | Page_error of string

let orient_route_identity identity =
  let violations = ref [] in
  if not (String.equal identity.expected_title identity.observed_title) then
    violations :=
      Wrong_route_title
        { expected = identity.expected_title; observed = identity.observed_title }
      :: !violations;
  if not (String.equal identity.expected_sha256 identity.observed_sha256) then
    violations :=
      Wrong_route_body
        { expected = identity.expected_sha256; observed = identity.observed_sha256 }
      :: !violations;
  List.rev !violations

let orient observation =
  let violations = ref [] in
  let overflow = observation.root_width -. observation.viewport_width in
  if overflow > 0.5 then violations := Horizontal_overflow overflow :: !violations;
  if observation.heading_count < 1 then violations := Missing_heading :: !violations;
  if observation.artifact_count < 1 then violations := Missing_artifacts :: !violations;
  if observation.prompt_ledger_count < 2 then
    violations := Missing_prompt_ledgers observation.prompt_ledger_count :: !violations;
  if observation.remote_resource_count > 0 then
    violations := Remote_resources observation.remote_resource_count :: !violations;
  if observation.remote_css_reference_count > 0 then
    violations :=
      Remote_css_references observation.remote_css_reference_count :: !violations;
  if observation.required_prompt_marker_count < observation.expected_prompt_marker_count then
    violations :=
      Missing_prompt_markers
        { actual = observation.required_prompt_marker_count;
          expected = observation.expected_prompt_marker_count }
      :: !violations;
  List.iter (fun error -> violations := Console_error error :: !violations)
    observation.console_errors;
  List.iter (fun error -> violations := Page_error error :: !violations)
    observation.page_errors;
  List.rev !violations

let violation_name = function
  | Horizontal_overflow pixels -> Printf.sprintf "horizontal-overflow(%.2fpx)" pixels
  | Missing_heading -> "missing-heading"
  | Missing_artifacts -> "missing-artifacts"
  | Missing_prompt_ledgers count -> Printf.sprintf "missing-prompt-ledgers(%d/2)" count
  | Remote_resources count -> Printf.sprintf "remote-resources(%d)" count
  | Remote_css_references count ->
      Printf.sprintf "remote-css-references(%d)" count
  | Missing_prompt_markers { actual; expected } ->
      Printf.sprintf "missing-prompt-markers(%d/%d)" actual expected
  | Wrong_route_title { expected; observed } ->
      Printf.sprintf "wrong-route-title(expected=%S,observed=%S)" expected observed
  | Wrong_route_body { expected; observed } ->
      Printf.sprintf "wrong-route-body(expected=%s,observed=%s)" expected observed
  | Console_error error -> "console-error(" ^ error ^ ")"
  | Page_error error -> "page-error(" ^ error ^ ")"
