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

type violation
val orient : observation -> violation list
val orient_route_identity : route_identity -> violation list
val violation_name : violation -> string
