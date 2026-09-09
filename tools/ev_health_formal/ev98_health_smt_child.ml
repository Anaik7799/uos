let json_string value =
  "\"" ^ String.escaped value ^ "\""

let emit row =
  Printf.printf
    "{\"name\":%s,\"expected\":%s,\"actual\":%s,\"query_sha256\":%s,\"assignment\":%s,\"independently_validated\":%b}\n%!"
    (json_string row.Ev98_health_smt.name)
    (json_string row.expected)
    (json_string row.actual)
    (json_string row.query_sha256)
    (json_string row.assignment)
    row.independently_validated

let () =
  let rows = Ev98_health_smt.rows () in
  List.iter emit rows;
  if Ev98_health_smt.emitted_rows_hold rows then
    print_endline "PASS EV98 bounded Smtml child"
  else begin
    prerr_endline "FAIL EV98 bounded Smtml child";
    exit 1
  end
