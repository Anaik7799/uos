(* Thin driver: generate the parity KPI dashboard HTML from the live evidence
   store. Usage: render_parity_dashboard [root] [out.html] (defaults: ., stdout).
   Fail-closed: an unreadable store refuses (exit 1) instead of rendering. *)

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  match Parity_dashboard.generate ~root with
  | Error message ->
      prerr_endline message;
      exit 1
  | Ok html ->
      if Array.length Sys.argv > 2 then begin
        let channel = open_out_bin Sys.argv.(2) in
        output_string channel html;
        close_out channel;
        Printf.printf "wrote %s (%d bytes)\n" Sys.argv.(2) (String.length html)
      end
      else print_string html
