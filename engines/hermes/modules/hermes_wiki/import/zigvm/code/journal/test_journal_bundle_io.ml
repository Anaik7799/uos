open Bos

module B = Journal_bundle_core.Journal_bundle
module Io = Journal_bundle_runtime.Journal_bundle_io

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let get = function
  | Ok value -> value
  | Error (`Msg message) -> failwith message

let () =
  let directory = Filename.temp_dir "zigvm-journal-bundle-" "" in
  let source = Filename.concat directory "capture.png" in
  let durable = Filename.concat directory "durable/research.png" in
  get (OS.File.write (Fpath.v source) "image-bytes");
  get (Io.materialize_image B.{ path = durable; source = Some source });
  require "LAW ARTIFACT-MATERIALIZATION-ROUNDTRIP"
    (String.equal (get (OS.File.read (Fpath.v durable))) "image-bytes");

  let first = Filename.concat directory "local/report.html" in
  let second = Filename.concat directory "dashboard/report.html" in
  let written = get (Io.publish ~content:"one-render" ~outputs:[ first; second ]) in
  require "LAW PUBLICATION-FANOUT"
    (List.for_all
       (fun observation -> observation.Io.disposition = Io.Written)
       written &&
     String.equal (get (OS.File.read (Fpath.v first))) "one-render" &&
     String.equal (get (OS.File.read (Fpath.v second))) "one-render");
  let unchanged =
    get (Io.publish ~content:"one-render" ~outputs:[ first; second ])
  in
  require "LAW PUBLICATION-IDEMPOTENCE"
    (List.for_all
       (fun observation -> observation.Io.disposition = Io.Unchanged)
       unchanged);
  require "LAW OAIS-AIP-SHA256-FIXITY"
    (String.equal
       (get (Io.sha256_file first))
       "5e395e96b925fb8e72a823c70a385ba28b9e370940444c309679167ba92c6798");
  require "LAW OAIS-FANOUT-FIXITY-EQUALITY"
    (String.equal (get (Io.sha256_file first)) (get (Io.sha256_file second)));

  let sequential = get (Io.acquire_files ~pool_size:1 [ source; durable ]) in
  let parallel = get (Io.acquire_files ~pool_size:4 [ source; durable ]) in
  require "LAW PARALLEL-SEQUENTIAL-ACQUISITION-EQUIVALENCE"
    (sequential = parallel &&
     List.map fst parallel = [ source; durable ]);
  require "LAW PARALLEL-MAP-PRESERVES-MANIFEST-ORDER"
    (Io.map_ordered ~pool_size:4 (fun value -> value * value) [ 3; 1; 2 ] =
     [ 9; 1; 4 ]);

  let missing =
    Io.materialize_image
      B.{ path = Filename.concat directory "missing.png"; source = None }
  in
  require "MUT-MATERIALIZATION-MISSING-SOURCE"
    (match missing with Error _ -> true | Ok () -> false)
