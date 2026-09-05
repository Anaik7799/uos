module C = Playwright_control.Journal_playwright_contract

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let valid =
  C.{ viewport_width = 390.; root_width = 390.; heading_count = 1;
      artifact_count = 8; prompt_ledger_count = 2; remote_resource_count = 0;
      remote_css_reference_count = 0;
      required_prompt_marker_count = 28; expected_prompt_marker_count = 28;
      console_errors = []; page_errors = [] }

let valid_route_identity =
  C.{ expected_title = "Fractal FP Atlas comprehensive improvement review";
      observed_title = "Fractal FP Atlas comprehensive improvement review";
      expected_sha256 = String.make 64 'a';
      observed_sha256 = String.make 64 'a' }

let () =
  require "LAW JOURNAL-PLAYWRIGHT-ACCEPTS-CLOSED-BUNDLE"
    (C.orient valid = []);
  require "LAW JOURNAL-ROUTE-IDENTITY"
    (C.orient_route_identity valid_route_identity = []);
  require "MUT-JOURNAL-ROUTE-WRONG-TITLE"
    (C.orient_route_identity
       { valid_route_identity with observed_title = "zigvm · ops board (harness)" }
     <> []);
  require "MUT-JOURNAL-ROUTE-WRONG-BODY"
    (C.orient_route_identity
       { valid_route_identity with observed_sha256 = String.make 64 'b' }
     <> []);
  require "MUT-JOURNAL-REMOTE-RESOURCE"
    (C.orient { valid with remote_resource_count = 1 } <> []);
  require "MUT-JOURNAL-MISSING-PROMPT"
    (C.orient { valid with prompt_ledger_count = 1 } <> []);
  require "MUT-JOURNAL-OVERFLOW"
    (C.orient { valid with root_width = 420. } <> []);
  require "MUT-JOURNAL-PAGE-ERROR"
    (C.orient { valid with page_errors = [ "boom" ] } <> []);
  require "MUT-JOURNAL-REMOTE-CSS-REFERENCE"
    (C.orient { valid with remote_css_reference_count = 1 } <> []);
  require "MUT-JOURNAL-MISSING-REQUIRED-PROMPT"
    (C.orient { valid with required_prompt_marker_count = 27 } <> [])
