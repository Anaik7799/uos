let () =
  if Ev98_health_smt.all_laws_hold () then
    print_endline "PASS EV98 bounded Smtml child"
  else begin
    prerr_endline "FAIL EV98 bounded Smtml child";
    exit 1
  end
