module T = Journal_bundle_runtime.Journal_bundle_telemetry

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let measurement ?work_items ?bytes ?domains ?wiki_notes ?artifacts () =
  T.{ work_items; bytes; domains; wiki_notes; artifacts }

let events =
  [ T.make ~sequence:1 ~timestamp_ns:1L ~stage:T.Validate ~status:T.Started
      ~measurement:(measurement ()) ();
    T.make ~sequence:2 ~timestamp_ns:2L ~stage:T.Validate
      ~status:(T.Completed { duration_ms = 4 })
      ~measurement:(measurement ~work_items:3 ~bytes:120 ()) ();
    T.make ~sequence:3 ~timestamp_ns:3L ~stage:T.Acquire ~status:T.Started
      ~measurement:(measurement ~domains:4 ()) ();
    T.make ~sequence:4 ~timestamp_ns:4L ~stage:T.Acquire
      ~status:(T.Completed { duration_ms = 7 })
      ~measurement:(measurement ~work_items:8 ~bytes:2048 ~domains:4
                      ~wiki_notes:510 ~artifacts:59 ()) () ]

let () =
  require "LAW TELEMETRY-DISCOVERY-ZK-STAGES"
    (String.equal (T.stage_name T.Discover) "discover"
     && String.equal (T.stage_name T.Zk) "zk"
     && T.stage_budget_ms T.Discover > 0
     && T.stage_budget_ms T.Zk > 0);
  let summary = T.fold events in
  require "LAW TELEMETRY-EXACTLY-ONCE-TERMINALS"
    (T.violations summary = [] && summary.T.started_count = 2 &&
     summary.T.terminal_count = 2);
  require "LAW TELEMETRY-MONOTONE-COUNTERS"
    (summary.T.work_items_total = 11 && summary.T.bytes_total = 2168 &&
     summary.T.duration_ms_total = 11 && summary.T.max_domains = 4);
  require "LAW TELEMETRY-DETERMINISTIC-TUI"
    (String.equal (T.render_tui events) (T.render_tui events) &&
     String.contains (T.render_tui events) '4' &&
     String.contains (T.render_tui events) '/');
  let dashboard = T.render_dashboard ~title:"Bundle status" summary in
  (* This law was named SELF-CONTAINED and checked a doctype prefix and the
     absence of a NUL byte. It would have passed for a dashboard loading a CDN
     script — it never checked self-containment at all, and the corpus lint
     cannot cover it because this page is rendered in memory and never written
     under docs/. Strengthened here to state what the name claims.

     TyXML's document printer composes the doctype as `<!DOCTYPE html>`,
     uppercase; the lint rule lowercases before comparing, so the gate is
     unaffected, but this law compares raw bytes and had to follow. *)
  let contains_sub hay needle =
    let nl = String.length needle and hl = String.length hay in
    let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
    nl > 0 && go 0
  in
  require "LAW TELEMETRY-SELF-CONTAINED-DASHBOARD"
    (String.starts_with ~prefix:"<!DOCTYPE html>" dashboard
    && (not (String.contains dashboard '\000'))
    (* no resource resolves off-host, and no script element at all *)
    && (not (contains_sub dashboard "src=\"http"))
    && (not (contains_sub dashboard "src=\"//"))
    && (not (contains_sub dashboard "<link"))
    && not (contains_sub dashboard "<script"));
  (* The structure the Playwright observation depends on: eight KPI cards, a
     real <tbody> (TyXML's `table` cannot hold one — `tablex` can), and the
     budget-state column the selector matches on. *)
  require "LAW TELEMETRY-DASHBOARD-STRUCTURE"
    (let count needle =
       let nl = String.length needle and hl = String.length dashboard in
       let n = ref 0 in
       for i = 0 to hl - nl do
         if String.sub dashboard i nl = needle then incr n
       done;
       !n
     in
     count "class=\"card\"" = 8
     && contains_sub dashboard "<tbody>"
     && contains_sub dashboard "<th>budget state</th>");
  let otel = T.render_otel_file ~trace_id:"0123456789abcdef0123456789abcdef" events in
  let otel_text = Yojson.Safe.to_string otel in
  require "LAW TELEMETRY-OTEL-FILE-FIELDS"
    (String.contains otel_text 'r' &&
     String.length otel_text > 200 &&
     String.starts_with ~prefix:"{\"resourceLogs\"" otel_text);
  require "LAW TELEMETRY-REPORT-ONLY"
    (T.preserve_bundle_violations [ "missing-artifact" ] summary =
     [ "missing-artifact" ]);
  let duplicate =
    T.fold
      (events @
       [ T.make ~sequence:5 ~timestamp_ns:5L ~stage:T.Validate
           ~status:(T.Completed { duration_ms = 1 })
           ~measurement:(measurement ()) () ])
  in
  require "MUT-TELEMETRY-DUPLICATE-TERMINAL"
    (T.violations duplicate <> []);
  let slow_wiki =
    T.make ~sequence:6 ~timestamp_ns:6L ~stage:T.Wiki
      ~status:(T.Completed { duration_ms = T.stage_budget_ms T.Wiki + 1 })
      ~measurement:(measurement ~wiki_notes:512 ()) ()
  in
  require "MUT-STAGE-TIME-BUDGET-EXCEEDED"
    (T.budget_violations (T.fold [ slow_wiki ]) <> []);
  require "BDD-WARM-PATH-TIME-BUDGET"
    (T.within_warm_path_budget ~duration_ms:(T.warm_path_budget_ms - 1) &&
     not (T.within_warm_path_budget ~duration_ms:T.warm_path_budget_ms))
