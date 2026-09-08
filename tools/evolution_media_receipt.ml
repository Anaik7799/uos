#use "release_process.ml";;
let ()=try
 require(Array.length Sys.argv=4)"usage: RECORDINGS NEW_DEST CANDIDATE";
 let source=realpath Sys.argv.(1)and dest=Sys.argv.(2)and candidate=Sys.argv.(3)in
 require(hex 40 candidate&&not(Filename.is_relative dest)&&not(Sys.file_exists dest))"new owned destination and candidate required";
 let report=read_file(source^"/report.json")65536|>Yojson.Safe.from_string|>assoc in
 let rows=field "recordings"report|>Yojson.Safe.Util.to_list in require(List.length rows=8)"eight recordings required";
 let observations=read_file(source^"/samples.json")1048576|>Yojson.Safe.from_string|>Yojson.Safe.Util.to_list in
 require(List.length observations=56)"56 samples required";
 let numeric=function `Int n->float_of_int n|`Float f->f|_->failwith"numeric observation required"in
 List.iter(fun label->
  let samples=List.filter(fun j->str(field "page"(assoc j))=label)observations in
  require(List.length samples=7)"missing page samples";
  let value k row=field k(assoc(field "observation"(assoc row)))in
  let first=List.hd samples and last=List.hd(List.rev samples)in
  require(numeric(value "frames"last)>numeric(value "frames"first))"recorded stream did not advance";
  require(value "source"first<>value "source"last)"recorded source timestamp did not advance"
 )["evolution";"components";"terminal"];
 mkdir dest 0o700;
 let files=List.map(fun j->
  let a=assoc j in let name=str(field "artifact"a)in
  require(Filename.basename name=name&&Filename.check_suffix name".webm")"invalid video name";
  let p=source^"/"^name in require((lstat p).st_kind=S_REG&&(lstat p).st_size<=8388608)"video size/type";
  require(Yojson.Safe.Util.to_float(field "observed_seconds"a)>=30.)"short observation";
  let meta=run ~seconds:10. "/home/an/.cache/ms-playwright/ffmpeg-1011/ffmpeg-linux"["-i";p]in
  let line=String.split_on_char '\n' meta.output|>List.find(fun s->String.starts_with~prefix:"  Duration: "s)in
  let duration=Scanf.sscanf line"  Duration: %d:%d:%f,"(fun h m s->float_of_int(h*3600+m*60)+.s)in
  require(Float.is_finite duration&&duration>=30.)"encoded video too short";
  copy p(dest^"/"^name);write_new(dest^"/"^name^".metadata.log")meta.output;
  `Assoc["path",`String name;"sha256",`String(sha p);"encoded_seconds",`Float duration]
 )rows in
 List.iter(fun n->copy(source^"/"^n)(dest^"/"^n))["report.json";"samples.json"];
 let receipt=`Assoc["schema",`String"uos.video-provenance.v1";"authority",`String"NONE";"candidate",`String candidate;"videos",`List files;"observed_updates",`List(List.map(fun s->`String s)["evolution";"components";"terminal"]);"scope",`String"8 routes; not all components or human acceptance"]in
 write_new(dest^"/provenance.json")(Yojson.Safe.pretty_to_string receipt);
 emit"recording-retention""PASS"["evidence",`String dest;"videos",`Int 8;"updates",`Int 3]
 with e->emit"recording-retention""FAIL"["error",`String(Printexc.to_string e)];exit 1;;

