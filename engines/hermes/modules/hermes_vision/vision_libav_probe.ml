let () =
  print_endline "linked libav (via Ctypes, no subprocess):";
  print_endline ("  " ^ Vision_libav.linked_report ())
