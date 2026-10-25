
#load "unix.cma";;
let write p=let c=open_out_bin p in output_string c "late";close_out c
let ()=match Sys.argv.(1)with
|"normal"->print_endline "normal"
|"close"->Unix.close Unix.stdout;Unix.close Unix.stderr;Unix.sleepf 0.7
|"descendant"->(match Unix.fork()with 0->Unix.sleepf 0.65;write Sys.argv.(2)|_->Unix.sleepf 1.)
|"normal-descendant"->(match Unix.fork()with 0->Unix.sleepf 0.65;write Sys.argv.(2)|_->exit 0)
|"both"->print_string(String.make 800000 'o');flush stdout;prerr_string(String.make 800000 'e');flush stderr
|"finite-writer"->for _=1 to 100 do print_string(String.make 8192 'w');flush stdout;Unix.sleepf 0.003 done
|"exact"->print_string(String.make 1048576 'x');flush stdout
|_->exit 2
