(* Fractal atlas for the vision pipeline. See vision_atlas.mli. *)

open Vision_ontology

type relation = Feeds | Observes | Governs

type edge = { source : stage; relation : relation; target : stage }

let relation_name = function Feeds -> "feeds" | Observes -> "observes" | Governs -> "governs"

let edges =
  [ { source = Source; relation = Feeds; target = Encode };
    { source = Encode; relation = Feeds; target = Package };
    { source = Package; relation = Feeds; target = Serve };
    { source = Serve; relation = Feeds; target = Play };
    (* Observe does not feed anything: it is a measurement, and drawing
       it as part of the chain is how a capture ends up compared against
       itself. *)
    { source = Observe; relation = Observes; target = Play };
    { source = Observe; relation = Observes; target = Source };
    (* the declared intent constrains both ends, which is what makes the
       burned-in ordinal comparable at Observe *)
    { source = Source; relation = Governs; target = Observe } ]

let evidence_path s =
  let rec go acc current =
    let up = upstream current in
    if up = current then List.rev (current :: acc) else go (current :: acc) up
  in
  go [] s |> List.rev

let assumptions s covered =
  let established = Vision_algebra.stages_of covered in
  evidence_path s
  |> List.filter (fun x -> x <> s && not (List.mem x established))

let render () =
  let b = Buffer.create 512 in
  Buffer.add_string b "vision atlas\n";
  List.iter
    (fun e ->
      Buffer.add_string b
        (Printf.sprintf "  %-8s --%s--> %-8s\n" (stage_name e.source) (relation_name e.relation)
           (stage_name e.target)))
    edges;
  List.iter
    (fun s ->
      Buffer.add_string b
        (Printf.sprintf "  %-8s  level=%s origin=%s\n" (stage_name s)
           (Fractal_diagnostic.level_name (level s))
           (Fractal_diagnostic.origin_name (origin s))))
    stages;
  Buffer.contents b
