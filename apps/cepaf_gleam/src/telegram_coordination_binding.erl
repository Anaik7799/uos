%% Transport binding only: bind the isolated reader to the current build bytes.
%% No database access or agent policy here. The native guardian owns/reaps child.
-module(telegram_coordination_binding).
-export([launch_eval/2,launch_knowledge_eval/2]).

launch_eval(Db, View) ->
  try
    true = is_binary(Db) andalso byte_size(Db)>0 andalso byte_size(Db)=<1024,
    nomatch=binary:match(Db,<<0>>),
    absolute=filename:pathtype(binary_to_list(Db)),
    true=lists:member(View,[<<"peers">>,<<"board">>]),
    bound_eval('cepaf_gleam@harness@telegram_coordination_report',[Db,View])
  catch _:_ -> {error,<<"coordination_binding_failed">>} end.
launch_knowledge_eval(View, Query) ->
  try
    true=lists:member(View,[<<"wiki">>,<<"zk">>,<<"all">>]),
    true=is_binary(Query) andalso byte_size(Query)=<2048,
    nomatch=binary:match(Query,<<0>>),
    bound_eval('cepaf_gleam@harness@telegram_knowledge_report',[View,Query])
  catch _:_ -> {error,<<"knowledge_binding_failed">>} end.
bound_eval(Entry, Args) ->
  try
    Paths=[filename:absname(P)||P<-code:get_path()],
    true=length(Paths)=<256,
    Root=filename:absname(code:root_dir())++"/",
    Entries=closure([Entry],#{},Root,0),
    Sorted=lists:sort(maps:to_list(Entries)),
    Names=[atom_to_binary(M,utf8)||{M,_}<-Sorted],
    Hashes=[{atom_to_binary(M,utf8),H}||{M,H}<-Sorted],
    Digest=crypto:hash(sha256,term_to_binary(Hashes)),
    Data={Paths,Names,Digest,atom_to_binary(Entry,utf8),Args},
    true=byte_size(term_to_binary(Data))=<100000,
    Payload=base64:encode(term_to_binary(Data,[compressed])),
    Expr=io_lib:format(
      "{P,N,H,M0,A0}=binary_to_term(base64:decode(~0p),[safe]),"
      "true=code:set_path(P),"
      "B=[begin M=binary_to_atom(X,utf8),{M,C,F}=code:get_object_code(M),{X,M,C,F} end||X<-N],"
      "H=crypto:hash(sha256,term_to_binary([{X,crypto:hash(sha256,C)}||{X,_,C,_}<-B])),"
      "lists:foreach(fun({_,M,C,F})->{module,M}=code:load_binary(M,F,C) end,B),"
      "case erlang:apply(binary_to_atom(M0,utf8),read,A0) of "
      "{ok,R}->io:put_chars(R),halt(0);_->io:put_chars(<<\"coordination_read_failed\">>),halt(1) end.",
      [Payload]),
    Binary=iolist_to_binary(Expr),
    true=byte_size(Binary)=<4096,
    {ok,Binary}
  catch _:_ -> {error,<<"coordination_binding_failed">>} end.

closure([], Seen, _, _) -> Seen;
closure([M|Rest], Seen, Root, Total) ->
  case maps:is_key(M,Seen) orelse otp_module(M,Root) of
    true -> closure(Rest,Seen,Root,Total);
    false ->
      true=map_size(Seen)<192,
      {M,B,_}=code:get_object_code(M),
      true=byte_size(B)=<8388608,
      Next=Total+byte_size(B),true=Next=<33554432,
      {ok,{M,[{imports,Imports}]}}=beam_lib:chunks(B,[imports]),
      {ok,{M,Md5}}=beam_lib:md5(B),
      case code:is_loaded(M) of false->ok;_->Md5=M:module_info(md5) end,
      closure(Rest++lists:usort([I||{I,_,_}<-Imports]),
        Seen#{M=>crypto:hash(sha256,B)},Root,Next)
  end.
otp_module(M,Root) ->
  case code:which(M) of
    preloaded -> true;
    Path when is_list(Path) -> lists:prefix(Root,filename:absname(Path));
    _ -> false
  end.
