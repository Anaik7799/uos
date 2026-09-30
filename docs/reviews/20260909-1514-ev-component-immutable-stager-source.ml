#use "topfind";;
#require "unix,yojson,cryptokit,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
let root = "/home/an/NAS-setup/uos"
let workspace = root ^ "/.uos-workspaces/codex-ev-admission-20260909-0210"
let revision = Sys.argv.(1)
let target = Sys.argv.(2)
let mode = if Array.length Sys.argv=4 then Sys.argv.(3) else "composed"
let () = if not(List.mem mode ["composed";"transport"]) then failwith "closed review mode required"
let package = target ^ "/package"
let require b why = if not b then failwith why
let hash = Receipt_validator.sha
let read path =
  let before=Unix.lstat path in
  require(before.st_kind=Unix.S_REG && before.st_size<=4_194_304)"regular bounded source required";
  let fd=Unix.openfile path[Unix.O_RDONLY;Unix.O_NONBLOCK;Unix.O_CLOEXEC]0 in
  Fun.protect~finally:(fun()->Unix.close fd)(fun()->
    require(Receipt_validator.same_stat before(Unix.fstat fd))"source identity changed";
    let bytes=Bytes.create(before.st_size+1) in
    let rec loop at=if at=Bytes.length bytes then at else let n=Unix.read fd bytes at(Bytes.length bytes-at)in
      if n=0 then at else loop(at+n)in
    let n=loop 0 in
    require(n=before.st_size && Receipt_validator.same_stat before(Unix.fstat fd))"source changed during read";
    Bytes.sub_string bytes 0 n)
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p b=mkdir(Filename.dirname p);Ev_campaign.write p b
let jj args=Receipt_validator.run~seconds:5.~limit:1_048_576(root^"/toolchains/nix-profile/bin/jj")
  (["--ignore-working-copy";"--no-pager";"--color";"never";"-R";workspace]@args)
let selector="commit_id(\""^revision^"\")"
let candidate path=
  require(jj["file";"list";"-r";selector;"-T";"file_type ++ \" \" ++ path ++ \"\\n\"";"--";"root:"^path]="file "^path^"\n")"nonregular candidate source";
  jj["file";"show";"-r";selector;"-T";"\"\"";"--";"root:"^path]
let bound source staged bytes=`Assoc["source",`String source;"staged",`String staged;"sha256",`String(hash bytes);"bytes",`Int(String.length bytes)]
let deps=ref[] and sources=ref[] and probes=ref[]
let source_names=
  List.map(fun n->"src/cepaf_gleam/"^n^".gleam")
    (["crdt/delta_state";"crdt/health_bridge";"crdt/mesh_sync";"crdt/mesh_wire";"crdt/delta_mesh_engine";"ha/deadman_freshness";"crdt/mesh_peer";"crdt/mesh_peer_actor"] @
     if mode="transport" then ["crdt/mesh_zenoh_http";"crdt/mesh_zenoh_transport"] else []) @
  List.map(fun n->"test/"^n^".gleam")
    (["crdt_delta_state_test";"crdt_health_bridge_test";"crdt_mesh_sync_test";"deadman_freshness_test";"delta_mesh_engine_test";"mesh_sync_codec_test";"ev98_codec_runner";"mesh_peer_test";"mesh_peer_actor_test"] @
     if mode="transport" then ["mesh_zenoh_test";"mesh_zenoh_live_test"] else ["ev98_sync_status_runner"]) @ ["gleam.toml";"manifest.toml"]
let ()=
  require(String.length revision=40 && not(Sys.file_exists target))"full candidate and fresh output required";
  require(jj["log";"-r";selector;"--no-graph";"-T";"commit_id"]=revision)"candidate mismatch";
  List.iter(fun name->let source="apps/cepaf_gleam/"^name in let bytes=candidate source in
    let dest=if name="gleam.toml"then target^"/candidate-gleam.toml"else package^"/"^name in
    write dest bytes;sources:=bound("candidate:"^source)dest bytes::!sources)source_names;
  write(package^"/gleam.toml")"name = \"cepaf_gleam\"\nversion = \"1.0.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \"0.71.0\"\ngleam_erlang = \"1.3.0\"\ngleam_otp = \"1.2.0\"\ngleam_json = \"3.1.0\"\ngleeunit = \"1.9.0\"\n";
  List.iter(fun(source,name,expected)->let bytes=read source in require(hash bytes=expected)"independent probe changed";
    let dest=package^"/test/"^name in write dest bytes;probes:=bound source dest bytes::!probes)
    ([workspace^"/tools/ev_peer_independent_probe.gleam","ev_peer_independent_probe.gleam","d45b9b24c6df39fac2d14841720871c259a0c1ffba36491b85b69cc24f42aad0"] @
     if mode="transport" then ["/tmp/ev_transport_independent_http.gleam","ev_transport_independent_http.gleam",hash(read "/tmp/ev-http-independent-1442/package/test/ev_transport_independent_http.gleam")]
     else ["/tmp/ev_sync_reorder_probe.gleam","ev_sync_reorder_probe.gleam",hash(read "/tmp/ev-sync-root-reorder-red-1429/package/test/ev_sync_reorder_probe.gleam")]);
  let dependency_root=root^"/apps/cepaf_gleam/build/dev/erlang"in
  let rec copy depth name=require(depth<=16 && List.length !deps<=1024)"dependency traversal bound";
    let source=dependency_root^"/"^name in match(Unix.lstat source).st_kind with
    | Unix.S_DIR->Sys.readdir source |> Array.to_list |> List.sort String.compare |> List.iter(fun n->copy(depth+1)(name^"/"^n))
    | Unix.S_REG->let bytes=read source in let dest=target^"/lib/"^name in write dest bytes;deps:=bound source dest bytes::!deps
    | _->failwith "dependency links refused"in
  List.iter(copy 0)["gleam_stdlib";"gleam_erlang";"gleam_otp";"gleam_json";"gleeunit"];
  write(target^"/bindings.json")(Yojson.Basic.pretty_to_string(`Assoc[
    "candidate",`String revision;"observed_at",`Float(Unix.gettimeofday());"authority",`String "NONE";
    "sources",`List(List.rev !sources);"dependencies",`List(List.rev !deps);"independent_probes",`List(List.rev !probes);
    "private_build_profile",bound "reviewer-fixed-profile" (package^"/gleam.toml") (read(package^"/gleam.toml"));
    "stager_sha256",`String(hash(read "/tmp/ev_composed_peer_stage.ml"))])^"\n");
  Printf.printf "Prepared %s: %d immutable inputs, %d dependency files, %d unchanged independent probes\n"target(List.length !sources)(List.length !deps)(List.length !probes)
