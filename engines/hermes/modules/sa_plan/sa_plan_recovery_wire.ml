(* Pure factual adapter to existing Store v1 request bytes. This is not an
   authenticated envelope: v1 has NO proposal/review/portfolio/capability fields.
   Unlike recovery_model identifiers, native Store tokens do not allow colon.
   The standalone input schema below does not import the unmerged candidate. *)
type t = { bytes : string; digest : string }
type error = Invalid_input
exception Invalid
let require b=if not b then raise Invalid
let token s=String.length s>0&&String.length s<=160&&String.for_all(function
 |'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'|'/'->true|_->false)s
let hex s=String.length s=64&&String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s
let object_fields expected=function
 |`Assoc xs->let names=List.map fst xs in require(List.sort String.compare names=List.sort String.compare expected);xs
 |_->raise Invalid
let get xs k=match List.assoc_opt k xs with Some x->x|None->raise Invalid
let text=function `String s->s|_->raise Invalid
let integer=function `Int n->n|_->raise Invalid
let canonical_ns s=
 require(String.length s>0&&String.length s<=19);
 require(String.for_all(function '0'..'9'->true|_->false)s);
 let n=Int64.of_string s in require(Int64.compare n 0L>0&&Int64.to_string n=s);s
let check_tree root=
 let count=ref 0 in
 let rec walk depth value=incr count;require(depth<=8 && !count<=256);
  match value with
  |`Assoc fields->let names=List.map fst fields in
    require(List.length names=List.length(List.sort_uniq String.compare names));
    List.iter(fun(k,v)->require(not(String.contains k '\000'));walk(depth+1)v)fields
  |`List xs->List.iter(walk(depth+1))xs
  |`String s->require(not(String.contains s '\000'))
  |_->()in walk 0 root
(* Adapted from canonical tools/ecology_file_transaction_port.ml's bounded
   grammar, not Yojson's permissive whole-document reader. Only string-token
   unescaping uses Yojson after lexical validation. Numbers here are integers:
   the closed factual input has no legal float-bearing field. *)
let strict_json text=
 let length=String.length text and i=ref 0 and nodes=ref 0 in
 let rec ws()=if !i<length&&List.mem text.[!i][' ';'\t';'\r';'\n']then(incr i;ws())in
 let take c=ws();require(!i<length&&text.[!i]=c);incr i in
 let hex_digit=function '0'..'9' as c->Char.code c-48|'a'..'f' as c->Char.code c-87|'A'..'F' as c->Char.code c-55|_->raise Invalid in
 let four()=require(!i+4<=length);let n=ref 0 in
  for k=0 to 3 do n:=(!n lsl 4)lor hex_digit text.[!i+k]done;i:= !i+4;!n in
 let string_token()=
  ws();let start= !i in take '"';
  let rec scan()=require(!i<length);match text.[!i]with
   |'"'->incr i
   |'\\'->incr i;require(!i<length);let c=text.[!i]in incr i;
    (match c with
     |'"'|'\\'|'/'|'b'|'f'|'n'|'r'|'t'->()
     |'u'->let h=four()in if h>=0xd800&&h<=0xdbff then(
       require(!i+2<=length&&text.[!i]='\\'&&text.[!i+1]='u');i:= !i+2;
       let low=four()in require(low>=0xdc00&&low<=0xdfff))
       else require(h<0xdc00||h>0xdfff)
     |_->raise Invalid);scan()
   |c->require(Char.code c>=32);incr i;scan()in
  scan();match Yojson.Safe.from_string(String.sub text start(!i-start))with
  |`String s->s|_->raise Invalid in
 let rec value depth=
  incr nodes;require(depth<=8 && !nodes<=256);ws();require(!i<length);
  match text.[!i]with
  |'"'->`String(string_token())
  |'{'->incr i;ws();let seen=Hashtbl.create 8 in
   let rec members acc=let key=string_token()in require(not(Hashtbl.mem seen key));Hashtbl.add seen key();
    take ':';let v=value(depth+1)in ws();
    if !i<length&&text.[!i]=','then(incr i;members((key,v)::acc))
    else(take '}';`Assoc(List.rev((key,v)::acc)))in
   if !i<length&&text.[!i]='}'then(incr i;`Assoc[])else members[]
  |'['->incr i;ws();
   let rec items acc=let v=value(depth+1)in ws();
    if !i<length&&text.[!i]=','then(incr i;items(v::acc))else(take ']';`List(List.rev(v::acc)))in
   if !i<length&&text.[!i]=']'then(incr i;`List[])else items[]
  |'t'->literal "true" (`Bool true)|'f'->literal "false" (`Bool false)|'n'->literal "null" `Null
  |'-'|'0'..'9'->let start= !i in if text.[!i]='-'then incr i;require(!i<length);
   (match text.[!i]with '0'->incr i|'1'..'9'->incr i;while !i<length&&text.[!i]>='0'&&text.[!i]<='9'do incr i done|_->raise Invalid);
   require(!i-start<=20);Yojson.Safe.from_string(String.sub text start(!i-start))
  |_->raise Invalid
 and literal s v=let n=String.length s in require(!i+n<=length&&String.sub text !i n=s);i:= !i+n;v in
 let parsed=value 0 in ws();require(!i=length);parsed
let decode raw=
 try
  require(String.length raw>0&&String.length raw<=32768);
  let root=strict_json raw in check_tree root;
  let fields=object_fields["request_id";"plan";"snapshot_sha256";"members";"deadline_utc_ms"]root in
  let request=text(get fields "request_id")and plan=text(get fields "plan")in
  require(token request&&token plan);
  let tagged=text(get fields "snapshot_sha256")in
  require(String.length tagged=71&&String.sub tagged 0 7="sha256:");
  let snapshot=String.sub tagged 7 64 in require(hex snapshot);
  let deadline=integer(get fields "deadline_utc_ms")in
  require(deadline>0&&deadline<=9223372036854);
  let members=match get fields "members"with `List([_;_;_]as xs)->xs|_->raise Invalid in
  let members=List.map(fun v->
   let f=object_fields["task_id";"worker";"old_attempt";"old_lease_ns";"lease_ms"]v in
   let task=text(get f "task_id")and worker=text(get f "worker")in require(token task&&token worker);
   let attempt=integer(get f "old_attempt")and duration=integer(get f "lease_ms")in
   require(attempt>0&&attempt<1000000&&duration>0&&duration<=3600000);
   task,worker,attempt,canonical_ns(text(get f "old_lease_ns")),duration)members in
  let members=List.sort(fun(a,_,_,_,_)(b,_,_,_,_)->String.compare a b)members in
  let ids=List.map(fun(id,_,_,_,_)->id)members in require(List.length(List.sort_uniq String.compare ids)=3);
  let duration=match members with (_,_,_,_,d)::_ ->d|_->raise Invalid in
  require(List.for_all(fun(_,_,_,_,d)->d=duration)members);
  let old=List.map(fun(task,worker,attempt,lease,_)->`Assoc[
   "task",`String task;"worker",`String worker;"attempt",`Int attempt;"lease",`String lease])members in
  let bytes=Yojson.Safe.to_string(`Assoc["domain",`String"uos.sa-plan.reclaim-three.v1";
   "request_id",`String request;"plan",`String plan;"snapshot",`String snapshot;"old",`List old;
   "duration",`String(Int64.to_string(Int64.mul(Int64.of_int duration)1000000L));
   "deadline",`String(Int64.to_string(Int64.mul(Int64.of_int deadline)1000000L))])in
  Ok{bytes;digest=Digestif.SHA256.(to_hex(digest_string bytes))}
 with Invalid|Yojson.Json_error _|Failure _|Invalid_argument _->Error Invalid_input
let canonical_bytes t=t.bytes
let request_sha256 t=t.digest
let tagged_request_sha256 t="sha256:"^t.digest
