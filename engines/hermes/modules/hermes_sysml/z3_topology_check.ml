(* modules/hermes_sysml/z3_topology_check.ml *)
open Hermes_sysml.Sysml_types

type port = {
  id : string;
  mult : multiplicity;
}

type connection = {
  source : string;
  target : string;
}

type graph = {
  ports : port list;
  connections : connection list;
}

let check_topology (g : graph) =
  let smt2_spec = Buffer.create 256 in
  Buffer.add_string smt2_spec "(set-option :produce-models true)\n";
  Buffer.add_string smt2_spec "(set-logic QF_LIA)\n";

  List.iter (fun p ->
    Buffer.add_string smt2_spec (Printf.sprintf "(declare-const port_%s Int)\n" p.id);
    match p.mult with
    | Single ->
      Buffer.add_string smt2_spec (Printf.sprintf "(assert (= port_%s 1))\n" p.id)
    | Optional ->
      Buffer.add_string smt2_spec (Printf.sprintf "(assert (and (>= port_%s 0) (<= port_%s 1)))\n" p.id p.id)
    | Collection ->
      Buffer.add_string smt2_spec (Printf.sprintf "(assert (>= port_%s 0))\n" p.id)
  ) g.ports;

  List.iter (fun p ->
    let count = List.fold_left (fun acc c -> 
      if c.source = p.id || c.target = p.id then acc + 1 else acc
    ) 0 g.connections in
    Buffer.add_string smt2_spec (Printf.sprintf "(assert (= port_%s %d))\n" p.id count)
  ) g.ports;

  Buffer.add_string smt2_spec "(check-sat)\n(get-model)\n";
  
  let filename = "sysml_topology.smt2" in
  let oc = open_out filename in
  output_string oc (Buffer.contents smt2_spec);
  close_out oc;
  
  let cmd = "z3 " ^ filename in
  print_endline ("Running Z3 topology check: " ^ cmd);
  
  let in_ch = Unix.open_process_in cmd in
  let rec read_all acc =
    try read_all (acc ^ input_line in_ch ^ "\n")
    with End_of_file -> acc
  in
  let res = read_all "" in
  let status = Unix.close_process_in in_ch in
  
  match status with
  | Unix.WEXITED 0 ->
      if String.starts_with ~prefix:"sat" res then (
        print_endline "Topology constraints mathematically proven (SAT).";
        print_endline res;
        Ok "SAT"
      ) else (
        print_endline "Topology violates multiplicity bounds (UNSAT).";
        print_endline res;
        Error "UNSAT"
      )
  | _ ->
      print_endline "Z3 process failed.";
      Error "Z3_ERROR"

let () =
  let test_graph = {
    ports = [
      { id = "p1"; mult = Single };
      { id = "p2"; mult = Optional };
      { id = "p3"; mult = Collection };
    ];
    connections = [
      { source = "p1"; target = "p2" };
      { source = "p3"; target = "p1" }; (* wait, p1 has 2 connections now, but it's Single, so should be UNSAT *)
    ]
  } in
  ignore (check_topology test_graph);
  
  let test_graph2 = {
    ports = [
      { id = "p1"; mult = Single };
      { id = "p2"; mult = Optional };
    ];
    connections = [
      { source = "p1"; target = "p2" };
    ]
  } in
  ignore (check_topology test_graph2)
