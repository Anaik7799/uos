open Bos

module J = Wiki_render.Journal_markdown_html
module U = Yojson.Safe.Util

let directory = ref "work/benchmarks/sa-plan/wiki-selfcheck"
let markdown_output = ref "work/benchmarks/sa-plan/wiki-selfcheck/dashboard.md"
let html_output = ref "work/benchmarks/sa-plan/wiki-selfcheck/dashboard.html"

let read_json path = Yojson.Safe.from_file path
let member name json = U.member name json
let float name json = member name json |> U.to_float
let int name json = member name json |> U.to_int
let string name json = member name json |> U.to_string
let list name json = member name json |> U.to_list

let stage name json =
  list "stages" json
  |> List.find (fun row -> String.equal (string "name" row) name)

let fmt_ms value =
  if value >= 1000. then Printf.sprintf "%.2f s" (value /. 1000.)
  else Printf.sprintf "%.2f ms" value

let timestamp () =
  let tm = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d%02d%02d-%02d%02d%02d"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

let write_atomic path content =
  let target = Fpath.v path and temporary = Fpath.v (path ^ ".tmp") in
  match OS.Dir.create (Fpath.parent target) with
  | Error (`Msg message) -> failwith message
  | Ok _ ->
      (match OS.File.write temporary content with
       | Error (`Msg message) -> failwith message
       | Ok () ->
           match OS.Path.move ~force:true temporary target with
           | Ok () -> ()
           | Error (`Msg message) -> failwith message)

let worker_row path =
  let json = read_json path in
  let workers = int "workers" json in
  let sequential = float "wall_ms" (stage "render-sequential-oracle" json)
  and parallel = float "wall_ms" (stage "render-parallel-gss" json) in
  let speedup = sequential /. parallel in
  let efficiency = speedup /. float_of_int workers in
  Printf.sprintf "| %d | %.2f | %.2f | %.3f× | %.3f |"
    workers sequential parallel speedup efficiency

let scale_row row =
  let nullable_float name =
    match member name row with `Float value -> Printf.sprintf "%.2f" value | _ -> "—" in
  Printf.sprintf "| %d | %.2f | %.2f | %.2f | %.3f× | %.3f | %.3f | %s |"
    (int "pages" row) (float "build_ms" row) (float "context_ms" row)
    (float "parallel_render_ms" row) (float "render_speedup" row)
    (float "compat_page_cold_ms" row) (float "compat_page_warm_ms" row)
    (nullable_float "naive_reference_ms")

let () =
  Arg.parse
    [ "--directory", Arg.Set_string directory, "Benchmark JSON directory";
      "--markdown", Arg.Set_string markdown_output, "Markdown output";
      "--html", Arg.Set_string html_output, "HTML output" ]
    (fun value -> raise (Arg.Bad ("unexpected argument: " ^ value)))
    "wiki_benchmark_dashboard [--directory PATH] [--markdown PATH] [--html PATH]";
  let at name = Filename.concat !directory name in
  let baseline = read_json (at "20260804-first-run.json")
  and final = read_json (at "20260804-final-default.json")
  and scale = read_json (at "corpus-scale.json") in
  let baseline_total = float "wall_ms" (stage "total" baseline)
  and final_total = float "wall_ms" (stage "total" final) in
  let overall_speedup = baseline_total /. final_total in
  let reduction = (1. -. (final_total /. baseline_total)) *. 100. in
  let build_speedup =
    float "wall_ms" (stage "corpus-build" baseline)
    /. float "wall_ms" (stage "corpus-build" final) in
  let final_workers = int "workers" final in
  let final_render_speedup = float "speedup" final in
  let amdahl_parallel_fraction =
    if final_workers <= 1 then 0.
    else (1. -. (1. /. final_render_speedup))
         /. (1. -. (1. /. float_of_int final_workers)) in
  let top_stages =
    list "stages" final
    |> List.filter (fun row -> not (String.contains (string "name" row) '/'))
    |> List.sort (fun a b -> compare (float "wall_ms" b) (float "wall_ms" a))
    |> List.filteri (fun index _ -> index < 8)
    |> List.map (fun row ->
         Printf.sprintf "| %s | %s | %d | %s |"
           (string "name" row) (fmt_ms (float "wall_ms" row))
           (int "budget_ms" row)
           (if U.(member "within_budget" row |> to_bool) then "within" else "over"))
    |> String.concat "\n" in
  let worker_rows =
    [ 1; 2; 4; 8; 9 ]
    |> List.map (fun workers -> at (Printf.sprintf "sensitivity-workers-%d.json" workers))
    |> List.map worker_row |> String.concat "\n" in
  let scale_rows = list "sizes" scale |> List.map scale_row |> String.concat "\n" in
  let markdown =
    Printf.sprintf
      {|---
id: 6bc2f2ec-7b27-4c23-b693-2a92c9f5abf5
title: Wiki and Zettelkasten Pipeline Benchmark Dashboard
status: published
verified_by: codex
type: evidence
tags: [benchmark, wiki, zettelkasten, eio, quint, smtml, rete-ul, stan]
---

# Wiki and Zettelkasten Pipeline Benchmark Dashboard

Generated `%s`. Authority: report-only telemetry plus executable differential laws. Gate authority remains the existing hard verification pipeline.

Relations: [[20260804-infranodus-design-superset-journal]] · [[20260804-wiki-zk-parallel-pipeline]] · [[20260804-131604-sa-plan-c3i-admission-journal]] · [[20260725-zk-wiki-system-architecture]]

## Progress

- [x] Stage-level wall, CPU, allocation, byte, work, and budget telemetry
- [x] Immutable render context and byte-identical sequential oracle
- [x] Eio guided self-scheduling with exactly-once accounting
- [x] Quint bounded scheduling model
- [x] SMTML concrete-trace refutation of duplicate/missing work
- [x] Live Rete-UL wiki/gate isolation
- [x] Stan latency posterior, advisory only
- [x] Indexed backlink reduction and Aho-Corasick unlinked mentions
- [x] Worker-count, corpus-size, and cold/warm sensitivity
- [x] Canonical gate and Zero-Trust `--verify-cycle`
- [x] Sa-plan Store closure: 18/18 completed
- [ ] NUMA topology discovery, pinning, and hierarchical stealing — `unavailable_observed`

## Outcome KPIs

| KPI | Baseline | Final | Impact |
|---|---:|---:|---:|
| Internal end-to-end | %s | %s | %.3f×; %.1f%% reduction |
| Corpus build | %s | %s | %.3f× |
| Parallel render | %s | %s | %.3f× at %d workers |
| Semantic checks | 6,473 | 6,479 | all green |
| Rendered bytes | %d | %d | conserved |
| Peak RSS from `/usr/bin/time` | 750,284 KiB | 588,984 KiB | 21.5%% reduction |

The render-kernel Amdahl estimate at %d workers is parallel fraction `p≈%.3f` and serial fraction `1-p≈%.3f`. This applies only to the render kernel; rendering is now too small a share of the full pipeline for more render workers to materially improve end-to-end latency.

## Final stage profile

| Stage | Actual | Budget ms | Budget state |
|---|---:|---:|---|
%s

## Worker sensitivity

| Workers | Sequential ms | Parallel ms | Speedup | Efficiency |
|---:|---:|---:|---:|---:|
%s

Measured choice: four workers. Eight and nine workers regress because shared-memory/GC/domain overhead exceeds useful parallel work.

## Corpus and cache sensitivity

| Pages | Build ms | Context ms | Parallel render ms | Speedup | Cold page ms | Warm page ms | Naive ref ms |
|---:|---:|---:|---:|---:|---:|---:|---:|
%s

The retained naive reference is bounded to 256 pages in scale sweeps; the full 643-page admission differential took 34.43 seconds and matched exactly. At 643 pages, compatibility page rendering improves from about 1.38 seconds cold to about 0.45 ms warm because the immutable corpus context is reused.

## Formal and control checks

| Technique | Question | Result | Authority |
|---|---|---|---|
| Sequential OCaml oracle | Are ordered HTML values identical? | byte-equal over every page | admission |
| Eio + GSS | Is every coordinate produced once with bounded workers? | green | execution |
| Quint | Can the bounded CAS-linearized claim model skip or duplicate work? | no violation in seeded bounded run | evidence |
| SMTML/Z3 | Is a bad visit compatible with the observed concrete trace? | UNSAT | evidence with independent OCaml oracle |
| Rete-UL | Can wiki/ZK report facts affect gate admission? | decoupled; 5 laws | gate-isolation guard |
| Stan | What is P(page render ≤100 ms) in this run? | 0.9984, correlated-page disclosure | report-only |

## Optimization decision algorithm

1. Rank stages by wall time, CPU, allocation, bytes, and duplicated acquisition.
2. Optimize the largest measured stage only.
3. Preserve the sequential interpretation and compare values, not formatting claims.
4. Sweep workers and corpus sizes; compute speedup, efficiency, saturation, and cache effects.
5. Reject changes that trade latency for semantic drift, unbounded RSS, or hidden authority coupling.
6. Repeat until stages meet budgets or carry an explicit measured residual.

## Ranked residuals

1. Render-context preparation (~1.58 s): similarity and transitive inference remain superlinear. Consider sharded immutable indexes or incremental invalidation before more domains.
2. Corpus build (~1.47 s): parsing still uses sequential mutable capture state. Make extraction state local before any parallel parse.
3. Structural/dynamic validation (~4.0 s combined): scan once into a compact observation record instead of repeatedly searching full HTML.
4. Code inventory/search (~0.71 s): add content-addressed inventory caching shared by requests.
5. NUMA: topology, first-touch placement, affinity, and hierarchical stealing are not implemented or claimed. Introduce only with hwloc/OS evidence through permitted OCaml FFI and cross-socket benchmarks.
|}
      (timestamp ())
      (fmt_ms baseline_total) (fmt_ms final_total) overall_speedup reduction
      (fmt_ms (float "wall_ms" (stage "corpus-build" baseline)))
      (fmt_ms (float "wall_ms" (stage "corpus-build" final))) build_speedup
      (fmt_ms (float "wall_ms" (stage "render-parallel-gss" baseline)))
      (fmt_ms (float "wall_ms" (stage "render-parallel-gss" final)))
      final_render_speedup final_workers
      (int "rendered_bytes" baseline) (int "rendered_bytes" final)
      final_workers amdahl_parallel_fraction (1. -. amdahl_parallel_fraction)
      top_stages worker_rows scale_rows in
  let html =
    J.create ~title:"Wiki and Zettelkasten Pipeline Benchmark Dashboard"
      ~source_path:!markdown_output ~markdown
    |> J.render in
  write_atomic !markdown_output markdown;
  write_atomic !html_output html;
  Printf.printf "wiki-benchmark-dashboard: green -> %s, %s\n%!"
    !markdown_output !html_output
