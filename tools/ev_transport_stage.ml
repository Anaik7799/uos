#directory "+unix";;
#load "unix.cma";;
let ws="/home/an/NAS-setup/uos/.uos-workspaces/ev98-peer-loop-20260909/apps/cepaf_gleam";;
let dst=Sys.argv.(1);;
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700);;
let names=["crdt/delta_state";"crdt/health_bridge";"crdt/delta_mesh_engine";"crdt/mesh_sync";"crdt/mesh_wire";"ha/deadman_freshness";"crdt/mesh_peer";"crdt/mesh_peer_actor";"crdt/mesh_zenoh_http";"crdt/mesh_zenoh_transport"]|>List.map(fun s->"src/cepaf_gleam/"^s^".gleam");;
let names=names@["gleam.toml";"manifest.toml";"test/mesh_zenoh_test.gleam";"test/mesh_zenoh_live_test.gleam"];;
List.iter(fun name->let src=ws^"/"^name in if Sys.file_exists src then(let c=open_in_bin src in let s=really_input_string c(in_channel_length c)in close_in c;let path=dst^"/"^name in mkdir(Filename.dirname path);let o=open_out_gen[Open_creat;Open_wronly;Open_excl;Open_binary]0o600 path in output_string o s;close_out o))names;;
