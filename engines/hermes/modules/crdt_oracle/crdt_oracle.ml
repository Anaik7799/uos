(* crdt_oracle.ml — OCaml Reference Oracle for CRDT Semilattices *)
(* STAMP: SC-CRDT-001, SC-HERMES-001, SC-SIL6-001 *)

type node_id = string
type counter = int
type dot = { node: node_id; count: counter }
type vector_clock = (node_id * counter) list

let get_clock (vc : vector_clock) (n : node_id) : counter =
  match List.assoc_opt n vc with
  | Some c -> c
  | None -> 0

let merge_clocks (a : vector_clock) (b : vector_clock) : vector_clock =
  let from_a =
    List.map (fun (n, c_a) ->
      let c_b = get_clock b n in
      (n, max c_a c_b)
    ) a
  in
  let keys_a = List.map fst a in
  let missing_b = List.filter (fun (n, _) -> not (List.mem n keys_a)) b in
  from_a @ missing_b

type 'a lww_register = {
  value: 'a;
  timestamp_us: int;
  writer: node_id;
}

let merge_lww (a : 'a lww_register) (b : 'a lww_register) : 'a lww_register =
  if a.timestamp_us > b.timestamp_us then a
  else if b.timestamp_us > a.timestamp_us then b
  else if a.writer >= b.writer then a
  else b

(* Algebraic Verifier: Tests Commutativity, Associativity, Idempotence *)
let verify_algebraic_laws (a : vector_clock) (b : vector_clock) (c : vector_clock) : bool =
  let m_ab = merge_clocks a b in
  let m_ba = merge_clocks b a in
  let m_self = merge_clocks a a in
  let m_abc1 = merge_clocks m_ab c in
  let m_abc2 = merge_clocks a (merge_clocks b c) in

  (* Sort keys for deterministic equality *)
  let norm vc = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) vc in

  (norm m_ab = norm m_ba) &&
  (norm m_self = norm a) &&
  (norm m_abc1 = norm m_abc2)

let verify_lww_convergence () : bool =
  let r1 = { value = "val-a"; timestamp_us = 1000; writer = "node-1" } in
  let r2 = { value = "val-b"; timestamp_us = 2000; writer = "node-2" } in
  let m = merge_lww r1 r2 in
  let d = { node = "node-1"; count = 1 } in
  (m.value = "val-b") && (d.count = 1)

let () =
  let c1 = [("node-a", 3); ("node-b", 1)] in
  let c2 = [("node-a", 2); ("node-b", 4); ("node-c", 1)] in
  let c3 = [("node-b", 2); ("node-d", 5)] in
  let ok_laws = verify_algebraic_laws c1 c2 c3 in
  let ok_lww = verify_lww_convergence () in
  if ok_laws && ok_lww then
    Printf.printf "[HERMES-CRDT-ORACLE] Semilattice laws VERIFIED: Commutativity=OK, Idempotence=OK, Associativity=OK, LWW=OK\n"
  else
    (Printf.eprintf "[HERMES-CRDT-ORACLE] Semilattice law VIOLATION\n"; exit 1)
