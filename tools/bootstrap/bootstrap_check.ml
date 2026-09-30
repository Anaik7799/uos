#use "topfind";;
#require "unix,mtime.clock.os,yojson";;
#mod_use "bootstrap_model.ml";;
#mod_use "bootstrap_observer.ml";;
let () =
  let emit status details code =
    print_endline(Yojson.Basic.to_string(`Assoc[
      "schema",`String "uos.bootstrap-observation.v1";
      "status",`String status;"admission",`String "NOT_GRANTED";"details",details]));
    exit code in
  if Array.length Sys.argv<>1 then emit "REFUSED" (`String "no caller-selected command or predicate arguments") 2;
  match Bootstrap_observer.observe(Sys.getcwd()) with
  |Error reason->emit "REFUSED"(`String reason)1
  |Ok observation->match Bootstrap_model.verify observation.facts with
    |Error _->emit "REFUSED"(`String "bootstrap predicate failed")1
    |Ok verified->emit "OBSERVED_STANDALONE_JJ"
      (`Assoc["workspace",`String observation.root;"revision",`String observation.revision;
        "facts",`List(List.map(fun fact->`String(Bootstrap_model.name fact))(Bootstrap_model.observed verified));
        "git_markers",`List(List.map(function
          |Bootstrap_observer.Absent path->`Assoc["path",`String path;"kind",`String "ABSENT"]
          |Bootstrap_observer.Empty_directory(path,mode,mtime,ctime)->`Assoc[
            "path",`String path;"kind",`String "EMPTY_NON_OPERATIONAL_DIRECTORY";
            "mode",`Int mode;"mtime",`Float mtime;"ctime",`Float ctime;
            "provenance",`String "UNEXPLAINED_ENVIRONMENT_MARKER_NOT_GIT_METADATA"]
          )observation.markers);
        "scope",`String "Read-only workspace and internal Git-backed JJ bootstrap observation; not admission or effect-time fencing"])0
