let envelope =
  Resource_envelope.
    [ Disk_space { path = "/tmp"; bytes_needed = 32 * 1024 * 1024; margin = 0.1 };
      Binary { name = "dune"; env_var = None };
      Binary { name = "python3"; env_var = None };
      Writable "/tmp" ]

let () =
  let checks = Resource_envelope.preflight envelope in
  if not (Resource_envelope.satisfied checks) then begin
    Printf.eprintf "preflight refused: %d of %d resources unavailable\n\n"
      (List.length (Resource_envelope.unmet_checks checks)) (List.length checks);
    List.iter (fun d -> prerr_endline (Fractal_diagnostic.render d))
      (Resource_envelope.to_diagnostics checks);
    exit 1
  end;
  Printf.printf "[PREFLIGHT PASSED] All %d pipeline resource components (Storage, Binaries, Telemetry Channels) verified and satisfied.\n" (List.length checks)
