(* Production entrypoint deliberately has no admitted owner/anchor or Store
   dependency. Neither argv, stdin, environment, keys nor supplied digests can
   enable effects. Private full-path fixtures compile a DIFFERENT test worker. *)
let response code=Yojson.Basic.to_string(`Assoc[
 "status",`String"HOLD";"code",`String code;"authority",`String"NONE";
 "mutation_attempted",`Bool false;"admitted",`Bool false])
let main()=
 let code=try
  if Array.length Sys.argv<>1 then "ARGUMENTS_REFUSED"else
  let h=really_input_string stdin 4 in
  let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)h;
  if !n<1|| !n>65536 then "FRAME_BOUND"else
  let _body=really_input_string stdin !n in
  (try ignore(input_char stdin);"TRAILING_INPUT"with End_of_file->Recovery_kernel.production_owner_status())
 with End_of_file->"TRUNCATED_FRAME"in
 let body=response code in let n=String.length body in
 for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;
 output_string stdout body;flush stdout
let ()=main()
