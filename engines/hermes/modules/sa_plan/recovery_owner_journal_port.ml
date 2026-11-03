(* Single framed metadata request. Guardian owns blocking deadline/reaping. *)
let ()=
 let result=try
  if Array.length Sys.argv<>2 then failwith"argv";
  let header=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)header;
  if !n<=0|| !n>16384 then failwith"frame";
  let bytes=really_input_string stdin !n in
  (try ignore(input_char stdin);failwith"trailing"with End_of_file->());
  Recovery_owner_journal.handle ~database:Sys.argv.(1)bytes
 with _->"{\"status\":\"hold\",\"code\":\"FRAME_REFUSED\",\"binding\":null,\"record\":null,\"authority\":\"NONE\"}"in
 let n=String.length result in for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;output_string stdout result;flush stdout
