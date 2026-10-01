open Unix
let ()=
 let mode=Filename.basename Sys.argv.(1)in
 let header=really_input_string Stdlib.stdin 4 in
 let n=ref 0 in String.iter(fun c->n:=(!n lsl 8) lor Char.code c)header;
 let body=really_input_string Stdlib.stdin !n in
 (try ignore(input_char Stdlib.stdin);exit 12 with End_of_file->());
 let write s=output_string Stdlib.stdout s;flush Stdlib.stdout in
 match mode with
 |"echo"->write(header^body)
 |"truncated"->write(header^String.sub body 0(max 0(!n-1)))
 |"trailing"->write(header^body^"private-marker")
 |"invalid_utf8"->write("\000\000\000\001\255")
 |"flood"->write(String.make 1048577 'x')
 |"nonzero"->write(header^body);exit 3
 |"timeout"->while true do write "x";sleepf 0.03 done
 |mode when String.starts_with ~prefix:"tree" mode->if fork()=0 then(sleepf 1.;let c=open_out(Sys.argv.(1)^".marker")in output_string c "escaped";close_out c;exit 0)else(write(header^body))
 |mode when String.starts_with ~prefix:"abandon" mode->if fork()=0 then(sleepf 1.;let c=open_out(Sys.argv.(1)^".marker")in output_string c "escaped";close_out c;exit 0)else(sleepf 10.)
 |_->exit 4
