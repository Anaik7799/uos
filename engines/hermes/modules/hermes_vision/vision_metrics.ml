(* Metrics and profiling. See the .mli for the hazard this is built around. *)

type histogram = float list   (* kept unsorted; sorted on demand *)

let empty = []
let observe h v = v :: h
let count h = List.length h

(* NONE when nothing was observed. A zero would be a lie about a stage
   that never ran, and it is the exact shape of the OBS and JMeter
   counter hazards. *)
let percentile h p =
  match h with
  | [] -> None
  | _ ->
      let a = Array.of_list (List.sort compare h) in
      let n = Array.length a in
      let idx = int_of_float (Float.round (p /. 100.0 *. float_of_int (n - 1))) in
      Some a.(max 0 (min (n - 1) idx))

let mean h =
  match h with
  | [] -> None
  | _ -> Some (List.fold_left ( +. ) 0.0 h /. float_of_int (List.length h))

type metric = { name : string; channel : string; value : float; unit_ : string }

let channel_for s = "vision_" ^ String.lowercase_ascii (Vision_ontology.stage_name s) ^ "_verdict"

let histograms obs =
  List.map
    (fun s ->
      ( s,
        List.fold_left
          (fun h (o : Vision_controller.observation) ->
            if o.Vision_controller.stage = s then observe h o.Vision_controller.elapsed_ms else h)
          empty obs ))
    Vision_ontology.stages

let of_observations obs =
  let counted v =
    List.length
      (List.filter
         (fun (o : Vision_controller.observation) ->
           Vision_controller.verdict_name o.Vision_controller.verdict = v)
         obs)
  in
  let totals =
    [ { name = "vision_stages_live"; channel = "vision_stages_live";
        value = float_of_int (counted "LIVE"); unit_ = "1" };
      { name = "vision_stages_unknown"; channel = "vision_stages_unknown";
        value = float_of_int (counted "UNKNOWN"); unit_ = "1" } ]
  in
  let latencies =
    List.filter_map
      (fun (s, h) ->
        (* a stage with no observation contributes NO metric, rather than
           a zero that would read as instantaneous *)
        match percentile h 99.0 with
        | None -> None
        | Some v ->
            Some { name = "vision_stage_latency_p99"; channel = channel_for s; value = v;
                   unit_ = "ms" })
      (histograms obs)
  in
  totals @ latencies

let undeclared ms =
  let declared = Vision_fpp.declared_channels () in
  List.filter_map (fun m -> if List.mem m.channel declared then None else Some m.channel) ms

(* Budgets are per stage because the stages do different work: opening a
   socket is not decoding a file. Generous, because a budget that fires
   on ordinary variance gets disabled, and a disabled gate is worse than
   none. *)
let budget_ms = function
  | Vision_ontology.Source -> 2000.0
  | Vision_ontology.Encode -> 2000.0
  | Vision_ontology.Package -> 2000.0
  | Vision_ontology.Serve -> 5000.0
  | Vision_ontology.Play -> 30000.0
  | Vision_ontology.Observe -> 60000.0

let over_budget obs =
  List.filter_map
    (fun (s, h) ->
      match percentile h 99.0 with
      | None -> None
      | Some v -> if v > budget_ms s then Some (s, v, budget_ms s) else None)
    (histograms obs)

(* "not measured" and "fast" are different claims, so they are reported
   separately rather than both counting as within budget. *)
let unprofiled obs =
  List.filter_map (fun (s, h) -> if count h = 0 then Some s else None) (histograms obs)

let to_prometheus ms =
  match undeclared ms with
  | c :: _ -> Error ("metric names an undeclared FPP channel: " ^ c)
  | [] ->
      let b = Buffer.create 512 in
      List.iter
        (fun m ->
          Buffer.add_string b
            (Printf.sprintf "# TYPE %s gauge\n%s{channel=\"%s\",unit=\"%s\"} %g\n" m.name m.name
               m.channel m.unit_ m.value))
        ms;
      Ok (Buffer.contents b)

let to_otlp ~run_id ms =
  match undeclared ms with
  | c :: _ -> Error ("metric names an undeclared FPP channel: " ^ c)
  | [] ->
      Ok
        (Printf.sprintf
           {|{"resourceMetrics":[{"resource":{"attributes":[{"key":"hermes.run_id","value":{"stringValue":"%s"}}]},"scopeMetrics":[{"scope":{"name":"hermes_vision"},"metrics":[%s]}]}]}|}
           run_id
           (String.concat ","
              (List.map
                 (fun m ->
                   Printf.sprintf
                     {|{"name":"%s","unit":"%s","gauge":{"dataPoints":[{"asDouble":%g,"attributes":[{"key":"hermes.fpp_channel","value":{"stringValue":"%s"}}]}]}}|}
                     m.name m.unit_ m.value m.channel)
                 ms)))

let render obs =
  let b = Buffer.create 512 in
  List.iter
    (fun (s, h) ->
      Buffer.add_string b
        (Printf.sprintf "  %-8s n=%d p99=%s\n" (Vision_ontology.stage_name s) (count h)
           (match percentile h 99.0 with
            (* NOT 0.0 — a stage that never ran has no percentile *)
            | None -> "(never observed)"
            | Some v -> Printf.sprintf "%.1fms" v)))
    (histograms obs);
  List.iter
    (fun (s, v, budget) ->
      Buffer.add_string b
        (Printf.sprintf "  OVER BUDGET %s: %.1fms > %.1fms\n" (Vision_ontology.stage_name s) v
           budget))
    (over_budget obs);
  Buffer.contents b
