(* TEST-ONLY framed adapter. No production entry, arbitrary executable or argv. *)
let ()=
 let reply=try
  if Array.length Sys.argv<>2 then failwith"fixture argv";
  let header=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)header;
  if !n<1|| !n>65536 then failwith"frame";
  let body=really_input_string stdin !n in
  (try ignore(input_char stdin);failwith"trailing"with End_of_file->());
  Jj_integration_fixture_kernel.handle Sys.argv.(1)body
 with _->"{\"fixture_frame_refused\":true}"in
 let n=String.length reply in for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;
 output_string stdout reply;flush stdout
