(* Pure byte-span pin editing. No filesystem, process, hashing, logging or
   authority effects. Load the existing pure Km_adjudication module first.
   JSON uses its RFC/UTF8/depth/duplicate-key checks. TOML supports bare dotted
   tables, bare keys and single-line JSON-basic/literal strings, booleans,
   decimal integers, arrays and bare-key inline tables. Unsupported syntax is
   HOLD, never a fallback. Only explicitly selected existing pin literals change.
   Nonowned bytes remain verbatim, including approval/disabled/auth settings. *)
module Pin : sig
  type metadata = {server:string; capsule:string; payload_sha256:string}
  type prepared
  val json : servers:string list -> capsule:string -> payload_sha256:string -> string -> (prepared,string) result
  val toml : servers:string list -> capsule:string -> payload_sha256:string -> string -> (prepared,string) result
  (* Private staging input, not a receipt or public response. Never log/hash it. *)
  val bytes_for_private_commit : prepared -> string
  val owned_metadata : prepared -> metadata list
end = struct
  module A=Km_adjudication.Adjudicator
  type metadata={server:string;capsule:string;payload_sha256:string}
  type prepared={bytes:string;metadata:metadata list}
  type span={first:int;last:int;replacement:string;server:string;key:string}
  exception Invalid of string
  let refuse s=raise(Invalid s)
  let require b s=if not b then refuse s
  let maximum=262144
  let release_key="UOS_COCKPIT_RELEASE"
  let payload_key="UOS_MCP_EXPECTED_PAYLOAD_SHA256"
  let hex64 s=String.length s=64 && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s
  let component s=s<>"" && s<>"." && s<>".." &&
    String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'.'|'_'|'-'->true|_->false)s
  let valid_capsule path=
    let length=String.length path in
    length>0 && length<=4096 && path.[0]='/' &&
    (match String.split_on_char '/' path with ""::parts->List.for_all component parts|_->false) &&
    let name=Filename.basename path in
    String.length name=78 && name.[8]='-' && name.[13]='-' &&
    String.for_all(function '0'..'9'->true|_->false)(String.sub name 0 8^String.sub name 9 4) &&
    hex64(String.sub name 14 64)
  let bindings allowed servers capsule payload=
    require(servers<>[] && List.length servers<=List.length allowed &&
      List.length servers=List.length(List.sort_uniq String.compare servers) &&
      List.for_all(fun s->List.mem s allowed)servers) "invalid_explicit_server_selection";
    require(valid_capsule capsule) "invalid_capsule_path";
    require(hex64 payload) "invalid_payload_sha256"
  let bounded body=
    require(String.length body<=maximum) "input_bound";
    A.validate_utf8 body;
    require(not(String.contains body '\000')) "nul_input"
  let ws=function ' '| '\t'|'\r'|'\n'->true|_->false
  let rec skip text i=if i<String.length text && ws text.[i] then skip text(i+1) else i
  let string_end text i=
    require(i<String.length text && text.[i]='"') "expected_string_literal";
    let rec walk j=
      require(j<String.length text) "unterminated_string";
      match text.[j] with
      | '"'->j+1
      | '\\'->require(j+1<String.length text) "unterminated_escape";walk(j+2)
      | _->walk(j+1) in
    walk(i+1)
  let json_string text first last=
    match Yojson.Safe.from_string(String.sub text first(last-first)) with
    | `String value->value|_->refuse "expected_string_literal"
  let finish body servers capsule payload spans=
    List.iter(fun server->List.iter(fun key->
      require(List.length(List.filter(fun s->s.server=server && s.key=key)spans)=1)
        "missing_or_duplicate_owned_pin") [release_key;payload_key])servers;
    let ordered=List.sort(fun a b->Int.compare a.first b.first)spans in
    let output=Buffer.create(String.length body) and position=ref 0 in
    List.iter(fun span->
      require(span.first>= !position && span.last>=span.first && span.last<=String.length body)
        "overlapping_pin_spans";
      Buffer.add_substring output body !position(span.first- !position);
      Buffer.add_string output span.replacement;position:=span.last)ordered;
    Buffer.add_substring output body !position(String.length body- !position);
    let bytes=Buffer.contents output in require(String.length bytes<=maximum) "output_bound";
    {bytes;metadata=List.map(fun server->{server;capsule;payload_sha256=payload})servers}
  let protect f=try Ok(f()) with
    | Invalid reason->Error reason
    | A.Input_error _|Yojson.Json_error _->Error "invalid_strict_json_or_utf8"
  let replacement capsule payload key=Yojson.Safe.to_string(`String(if key=release_key then capsule else payload))
  let json ~servers ~capsule ~payload_sha256 body=protect(fun()->
    bindings ["uos-gleam";"uos-harness";"uos-harness-dev"] servers capsule payload_sha256;
    bounded body;A.bound_nesting body;A.strict_validate body;
    let parsed=Yojson.Safe.from_string body in A.check_duplicate_keys parsed "root";
    let spans=ref [] in
    let owned=function
      | ["mcpServers";server;"env";key] when List.mem server servers &&
          (key=release_key || key=payload_key)->Some(server,key)
      | _->None in
    let rec value i path=
      let i=skip body i in require(i<String.length body) "missing_json_value";
      let last=match body.[i] with
        | '"'->string_end body i
        | '{'->object_ (skip body(i+1)) path
        | '['->array (skip body(i+1)) path
        | _->atom i in
      (match owned path with
       | None->()
       | Some(server,key)->require(body.[i]='"') "owned_pin_not_string";
         spans:={first=i;last;replacement=replacement capsule payload_sha256 key;server;key}::!spans);
      last
    and object_ i path=
      if body.[i]='}' then i+1 else
      let last=string_end body i in
      let key=json_string body i last in
      let colon=skip body last in require(body.[colon]=':') "missing_json_colon";
      let ending=skip body(value(colon+1)(path@[key])) in
      match body.[ending] with
      | '}'->ending+1|','->object_ (skip body(ending+1)) path
      | _->refuse "invalid_json_object"
    and array i path=
      if body.[i]=']' then i+1 else
      let ending=skip body(value i(path@["[]"])) in
      match body.[ending] with
      | ']'->ending+1|','->array (skip body(ending+1)) path
      | _->refuse "invalid_json_array"
    and atom i=
      let rec walk j=if j<String.length body && not(ws body.[j] || List.mem body.[j][',';']';'}'])
        then walk(j+1) else j in walk i in
    ignore(value 0 []);
    finish body servers capsule payload_sha256 !spans)

  let bare s=s<>"" && String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'->true|_->false)s
  let prefix left right=
    let rec loop a b=match a,b with [],_->true|x::xs,y::ys when x=y->loop xs ys|_->false in loop left right
  (* A finite one-line value parser is needed even for opaque values: ignoring
     an unclosed array/string could mistake its next line for an owned table. *)
  let toml_value line start=
    let n=String.length line in
    let nodes=ref 0 in
    let basic first last=
      let rec escapes i=
        if i>=last-1 then () else
        if line.[i]<>'\\' then escapes(i+1) else (
          require(i+1<last-1) "invalid_toml_escape";
          match line.[i+1] with
          | '"'|'\\'|'b'|'f'|'n'|'r'|'t'->escapes(i+2)
          | 'u'->
            require(i+5<last-1) "invalid_toml_unicode_escape";
            let code=try int_of_string("0x"^String.sub line(i+2)4)
              with Failure _->refuse "invalid_toml_unicode_escape" in
            require(code<0xd800 || code>0xdfff) "toml_surrogate_escape";
            escapes(i+6)
          | _->refuse "unsupported_toml_escape") in
      escapes(first+1) in
    let rec value depth i=
      require(depth<=32) "toml_depth_bound";
      incr nodes;require(!nodes<=4096) "toml_value_node_bound";
      let i=skip line i in require(i<n) "missing_toml_value";
      match line.[i] with
      | '"'->let last=string_end line i in
        let token=String.sub line i(last-i) in A.strict_validate token;basic i last;last
      | '\''->let rec literal j=require(j<n) "unsupported_multiline_or_literal";
          if line.[j]='\'' then j+1 else literal(j+1) in literal(i+1)
      | '['->array depth(skip line(i+1))
      | '{'->inline depth [] (skip line(i+1))
      | _->atom i
    and array depth i=
      require(i<n) "unsupported_multiline_array";
      if line.[i]=']' then i+1 else
      let last=skip line(value(depth+1)i) in require(last<n) "unsupported_multiline_array";
      if line.[last]=']' then last+1 else(
        require(line.[last]=',') "invalid_toml_array";array depth(skip line(last+1)))
    and inline depth keys i=
      require(i<n) "unsupported_multiline_inline_table";
      if line.[i]='}' then i+1 else
      let ()=require(List.length keys<256) "toml_inline_key_bound" in
      let rec key_end j=if j<n && line.[j]<>'=' && not(ws line.[j]) then key_end(j+1) else j in
      let stop=key_end i in let key=String.sub line i(stop-i) in
      require(bare key && not(List.mem key keys)) "unsupported_or_duplicate_inline_key";
      let eq=skip line stop in require(eq<n && line.[eq]='=') "invalid_inline_table";
      let last=skip line(value(depth+1)(eq+1)) in require(last<n) "unsupported_multiline_inline_table";
      if line.[last]='}' then last+1 else(
        require(line.[last]=',') "invalid_inline_table";
        let next=skip line(last+1) in require(next<n && line.[next]<>'}') "inline_table_trailing_comma";
        inline depth(key::keys)next)
    and atom i=
      let rec stop j=if j<n && not(ws line.[j] || List.mem line.[j][',';']';'}';'#']) then stop(j+1) else j in
      let last=stop i in let token=String.sub line i(last-i) in
      let unsigned=if String.length token>0 && (token.[0]='+' || token.[0]='-')
        then String.sub token 1(String.length token-1) else token in
      let decimal=unsigned<>"" && String.for_all(function '0'..'9'->true|_->false)unsigned &&
        (String.length unsigned=1 || unsigned.[0]<>'0') in
      require(token="true" || token="false" || decimal) "unsupported_toml_scalar";
      if decimal then (try ignore(Int64.of_string token) with Failure _->refuse "toml_integer_bound");last in
    value 0 start

  let toml ~servers ~capsule ~payload_sha256 body=protect(fun()->
    bindings ["uos_gleam";"uos_development"] servers capsule payload_sha256;
    bounded body;
    require(not(String.exists(fun c->(Char.code c<32 && not(ws c)) || Char.code c=127)body)) "invalid_toml_control";
    String.iteri(fun i c->if c='\r' then
      require(i+1<String.length body && body.[i+1]='\n') "bare_cr_toml")body;
    let section=ref [] and headers=ref [] and assignments=ref [] and spans=ref [] in
    let line offset ending=
      let text=String.sub body offset(ending-offset) in
      let text=if String.ends_with ~suffix:"\r" text then String.sub text 0(String.length text-1) else text in
      let n=String.length text in let first=skip text 0 in
      if first<n && text.[first]<>'#' then
      if text.[first]='[' then (
        let close=try String.index_from text(first+1)']' with Not_found->refuse "unsupported_toml_header" in
        let raw=String.sub text(first+1)(close-first-1) in
        let parts=String.split_on_char '.' raw in
        require(List.length parts<=32 && List.length !headers<256) "toml_structure_bound";
        require(List.for_all bare parts) "unsupported_quoted_or_array_table";
        let tail=skip text(close+1) in require(tail=n || text.[tail]='#') "invalid_toml_header_tail";
        require(not(List.mem parts !headers)) "duplicate_toml_section";
        require(not(List.exists(fun key->prefix key parts)!assignments)) "toml_key_table_conflict";
        headers:=parts::!headers;section:=parts)
      else (
        let eq=try String.index_from text first '=' with Not_found->refuse "unsupported_toml_assignment" in
        let key=String.trim(String.sub text first(eq-first)) in
        require(bare key) "unsupported_quoted_or_dotted_key";
        let path= !section@[key] in
        require(List.length !assignments<2048) "toml_structure_bound";
        require(not(List.mem path !assignments)) "duplicate_toml_key";
        require(not(List.exists(fun header->prefix path header)!headers)) "toml_table_key_conflict";
        assignments:=path::!assignments;
        let start=skip text(eq+1) in
        let last=toml_value text start in
        let tail=skip text last in require(tail=n || text.[tail]='#') "invalid_toml_value_tail";
        match !section with
        | ["mcp_servers";server;"env"] when List.mem server servers && (key=release_key || key=payload_key)->
          require(start<n && (text.[start]='"' || text.[start]='\'')) "owned_pin_not_string";
          spans:={first=offset+start;last=offset+last;replacement=replacement capsule payload_sha256 key;server;key}::!spans
        | _->()) in
    let rec lines start i=
      if i=String.length body then line start i
      else if body.[i]='\n' then(line start i;lines(i+1)(i+1))else lines start(i+1) in
    lines 0 0;
    finish body servers capsule payload_sha256 !spans)
  let bytes_for_private_commit p=p.bytes
  let owned_metadata p=p.metadata
end
