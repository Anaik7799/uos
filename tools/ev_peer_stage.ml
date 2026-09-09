#directory "+unix";;
#load "unix.cma";;
let root="/home/an/NAS-setup/uos/.uos-workspaces/ev98-peer-loop-20260909/apps/cepaf_gleam";;
let dst=Sys.argv.(1);;
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700);;
let files=["gleam.toml";"manifest.toml";"src/cepaf_gleam/crdt/delta_state.gleam";"src/cepaf_gleam/crdt/health_bridge.gleam";"src/cepaf_gleam/crdt/delta_mesh_engine.gleam";"src/cepaf_gleam/crdt/mesh_sync.gleam";"src/cepaf_gleam/crdt/mesh_wire.gleam";"src/cepaf_gleam/ha/deadman_freshness.gleam";"src/cepaf_gleam/crdt/mesh_peer.gleam";"src/cepaf_gleam/crdt/mesh_peer_actor.gleam";"test/mesh_peer_test.gleam";"test/mesh_peer_actor_test.gleam"];;
List.iter(fun path->if Sys.file_exists(root^"/"^path)then(let source=root^"/"^path in let st=Unix.lstat source in if st.Unix.st_kind<>Unix.S_REG || st.Unix.st_size>1048576 then failwith("nonregular/oversize source "^source);let ic=open_in_bin source in let bytes=really_input_string ic(in_channel_length ic)in close_in ic;mkdir(Filename.dirname(dst^"/"^path));let oc=open_out_gen[Open_wronly;Open_creat;Open_excl;Open_binary]0o600(dst^"/"^path)in output_string oc bytes;close_out oc))files;;
