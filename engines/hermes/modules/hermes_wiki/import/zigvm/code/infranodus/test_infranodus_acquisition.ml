module A = Zigvm_harness_support.Infranodus_acquisition
module Processing = Zigvm_harness_support.Graph_processing

let require condition message = if not condition then failwith message

let fake_provider request =
  match request.A.kind with
  | A.Web -> Ok A.{ body = "linked web evidence\nnetwork source"; content_type = "text/plain"; metadata = [ ("provider", "fixture-web") ]; usage = 2 }
  | A.Search -> Ok A.{ body = "search result evidence"; content_type = "text/plain"; metadata = [ ("provider", "fixture-search") ]; usage = 1 }
  | A.Youtube -> Ok A.{ body = "video transcript evidence"; content_type = "text/plain"; metadata = [ ("provider", "fixture-youtube") ]; usage = 3 }
  | A.Social -> Ok A.{ body = "social market sentiment"; content_type = "text/plain"; metadata = [ ("provider", "fixture-social") ]; usage = 4 }
  | A.Document -> Ok A.{ body = "pdf extracted evidence"; content_type = "text/plain"; metadata = [ ("extractor", "fixture-pdf") ]; usage = 1 }
  | _ -> Error (A.Unavailable "unexpected_provider_call")

let () =
  let requests =
    [ A.request ~id:"doc" ~kind:A.Document ~content_type:"text/markdown" "Graph evidence";
      A.request ~id:"pdf" ~kind:A.Document ~content_type:"application/pdf" "%PDF";
      A.request ~id:"csv" ~kind:A.Spreadsheet ~content_type:"text/csv" "text,kind\nSurvey graph,survey";
      A.request ~id:"batch" ~kind:A.Batch ~content_type:"text/plain" "first item\nsecond item";
      A.request ~id:"web" ~kind:A.Web ~locator:"https://example.test" ~content_type:"text/html" "";
      A.request ~id:"search" ~kind:A.Search ~content_type:"application/query" "graph research";
      A.request ~id:"youtube" ~kind:A.Youtube ~content_type:"application/id" "video-1";
      A.request ~id:"social" ~kind:A.Social ~content_type:"application/query" "market";
      A.request ~id:"notes" ~kind:A.Knowledge_notes ~content_type:"text/markdown" "[[graph]] #evidence";
      A.request ~id:"network" ~kind:A.Graph_network ~content_type:"text/vnd.graphviz" "graph -- evidence";
      A.request ~id:"api" ~kind:A.Api ~content_type:"application/json" "{\"text\":\"api evidence\"}" ]
  in
  let result = match A.acquire ~provider:fake_provider requests with Ok value -> value | Error _ -> failwith "all acquisition interpreters must succeed" in
  require (result.progress.completed = 11 && result.progress.total = 11) "progress must close at the request total";
  require (result.progress.usage = 11) "provider usage must be additive";
  require (List.length result.provenance = 11) "every source must retain provenance";
  require (List.length result.statements >= 11) "every source must yield inspectable statements";
  require (Processing.has_node result.processed "evidence") "acquired evidence must enter the shared processing algebra";
  (match A.acquire [ A.request ~id:"web" ~kind:A.Web ~content_type:"text/html" "" ] with
  | Error (A.Unavailable reason) -> require (String.length reason > 0) "unavailable state needs a reason"
  | _ -> failwith "missing providers must never fabricate web data");
  let limited _ = Error (A.Rate_limited { retry_after_seconds = 30 }) in
  (match A.acquire ~provider:limited [ A.request ~id:"search" ~kind:A.Search ~content_type:"application/query" "x" ] with
  | Error (A.Rate_limited { retry_after_seconds = 30 }) -> ()
  | _ -> failwith "rate limits must remain typed and observable");
  print_endline "infranodus acquisition laws: pass"
