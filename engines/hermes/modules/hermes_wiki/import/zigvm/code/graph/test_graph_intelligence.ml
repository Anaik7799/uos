module Graph = Zigvm_harness_support.Graph_intelligence
module Store = Zigvm_harness_support.Graph_store
module Ingest = Zigvm_harness_support.Graph_ingest
module Worker = Zigvm_harness_support.Graph_worker_core
module Db = Zigvm_harness_support.Db

let require condition message = if not condition then failwith message
let close left right = Float.abs (left -. right) < 1e-9

let node id =
  Graph.{ id; label = id; kind = "test"; layer = "L0"; group = "law"; detail = ""; weight = 1. }

let edge source target = Graph.{ source; target; relation = "links"; weight = 1. }

let graph =
  Graph.
    {
      id = "path";
      title = "Path";
      kind = "test";
      nodes = [ node "a"; node "b"; node "c"; node "a" ];
      edges = [ edge "a" "b"; edge "b" "c"; edge "a" "b"; edge "c" "missing" ];
    }

let remove_if_present path = if Sys.file_exists path then Sys.remove path

let () =
  let normalized = Graph.normalize graph in
  require (List.length normalized.nodes = 3) "normalization must deduplicate nodes";
  require (List.length normalized.edges = 2) "normalization must remove invalid and duplicate edges";
  require (Graph.normalize normalized = normalized) "normalization must be idempotent";
  require
    (match Graph.of_yojson (Graph.to_yojson normalized) with
    | Ok decoded -> decoded = normalized
    | Error _ -> false)
    "graph JSON must round-trip through the final encoding";
  let rank_sum = Graph.pagerank normalized |> List.fold_left (fun sum (_, rank) -> sum +. rank) 0. in
  require (close rank_sum 1.) "PageRank must be stochastic";
  let between = Graph.betweenness normalized in
  require
    (List.assoc "b" between > List.assoc "a" between)
    "path center must maximize betweenness";
  let communities = Graph.communities normalized in
  require (List.length communities = 3) "communities must partition every node";
  require
    (Graph.communities normalized = communities)
    "community labels must be deterministic";
  let analysis = Graph.analyze normalized in
  require (analysis.components = 1) "path must be one connected component";
  let reversed = Graph.{ normalized with id = "reversed"; nodes = List.rev normalized.nodes } in
  let lr = Graph.compare normalized reversed and rl = Graph.compare reversed normalized in
  require (lr.common_nodes = rl.common_nodes) "comparison intersection must be symmetric";
  require (String.length (Graph.to_graphml normalized) > 100) "GraphML export must be non-empty";
  require (String.length (Graph.to_dot normalized) > 50) "DOT export must be non-empty";
  let text_graph =
    Ingest.from_text ~id:"text-law" ~title:"Text law"
      "Graphs reveal concepts. Concepts connect evidence. Graphs connect evidence."
  in
  require (List.length text_graph.nodes = 5) "text projection must preserve five concepts";
  require
    (List.for_all
       (fun (edge : Graph.edge) -> not (String.equal edge.source edge.target))
       text_graph.edges)
    "text projection must reject self edges";
  require
    (Ingest.sentiment "verified robust success" > 0.
    && Ingest.sentiment "unsafe failure hazard" < 0.)
    "sentiment overlay must preserve polarity";
  let path = Filename.temp_file "zigvm-graph-" ".sqlite3" in
  let db = Db.open_ ~path in
  Fun.protect
    ~finally:(fun () ->
      Db.close db;
      remove_if_present path;
      remove_if_present (path ^ "-wal");
      remove_if_present (path ^ "-shm"))
    (fun () ->
      Store.ensure_schema db;
      let args =
        `Assoc
          [
            ("context_id", `String "law-text");
            ("title", `String "Law text");
            ("text", `String "Evidence connects laws. Laws connect implementation.");
          ]
      in
      let enqueue () =
        Store.enqueue db ~command:"import" ~args ~requested_by:"law@test"
          ~role:"operator" ~idempotency_key:(Some "law-idempotency")
      in
      let first = enqueue () and second = enqueue () in
      let id = function Ok job -> job.Store.id | Error message -> failwith message in
      require (id first = id second) "idempotency key must admit exactly one durable job";
      (match Worker.run_one db with
      | Worker.Finished job ->
          require (job.state = "completed") "import worker must complete the claimed job";
          require (job.attempts = 1) "exactly one claim must consume exactly one attempt"
      | Worker.No_work -> failwith "admitted import must be claimable");
      require
        (match Store.load_graph db "law-text" with
        | Some saved -> saved.id = "law-text" && List.length saved.nodes > 0
        | None -> false)
        "completed import must persist a retrievable graph";
      require
        (Worker.run_one db = Worker.No_work)
        "completed idempotent work must not be claimed again";
      require
        (Store.enqueue db ~command:"unknown" ~args ~requested_by:"law@test"
           ~role:"operator" ~idempotency_key:None
        = Error "unsupported command")
        "unknown commands must fail closed");
  Printf.printf
    "test-graph-intelligence: OK - normalization, JSON round-trip, analytics, exports, durable import, idempotency\n"
