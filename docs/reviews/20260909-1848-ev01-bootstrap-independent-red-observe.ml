#use "topfind";;
#require "unix,mtime.clock.os,yojson";;
#directory "/tmp/ev01-bootstrap-independent-1756/source/tools/bootstrap";;
#mod_use "/tmp/ev01-bootstrap-independent-1756/source/tools/bootstrap/bootstrap_model.ml";;
#mod_use "/tmp/ev01-bootstrap-independent-1756/source/tools/bootstrap/bootstrap_observer.ml";;
let ()=let before=Sys.getcwd()in let result=Bootstrap_observer.observe Sys.argv.(1)in let after=Sys.getcwd()in let status,revision=match result with Ok o->"PASS",o.revision|Error reason->"REFUSED",reason in print_endline(Yojson.Safe.to_string(`Assoc["status",`String status;"revision_or_reason",`String revision;"cwd_before",`String before;"cwd_after",`String after]));exit(if status="PASS"then 0 else 1)
