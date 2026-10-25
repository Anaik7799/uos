-module(telegram_test_runtime_test).
-include_lib("eunit/include/eunit.hrl").
packet() ->
  {ok,Expr}=telegram_test_runtime:launch_eval(<<"/tmp/uos-test-binding-refusal-only.json">>),
  ?assert(byte_size(Expr)=<4096),
  {match,[Encoded]}=re:run(Expr,<<"base64:decode\\(<<\"([A-Za-z0-9+/=]+)\">>\\)">>,[{capture,[1],binary}]),
  {Expr,Encoded,binary_to_term(base64:decode(Encoded),[safe])}.
evaluate_bad(Expr,Old,Data) ->
  New=base64:encode(term_to_binary(Data,[{compressed,9}])),
  Changed=binary:replace(Expr,Old,New),
  {ok,Toks,_}=erl_scan:string(binary_to_list(Changed)),
  {ok,Forms}=erl_parse:parse_exprs(Toks),
  try erl_eval:exprs(Forms,[]) of _->unexpected_success
  catch error:Reason->Reason end.
aggregate_hash_cardinality_refused_test() ->
  {Expr,Old,{Paths,Names,Hashes,Config}}=packet(),
  ?assertEqual(32,byte_size(Hashes)),
  Short=binary:part(Hashes,0,byte_size(Hashes)-1),
  ?assertEqual({badmatch,false},evaluate_bad(Expr,Old,{Paths,Names,Short,Config})).
aggregate_hash_tampering_refused_before_runner_test() ->
  {Expr,Old,{Paths,Names,Hashes,Config}}=packet(),
  <<First:32/binary,Rest/binary>>=Hashes,
  <<Byte,Tail/binary>>=First,
  Bad = <<(Byte bxor 1),Tail/binary,Rest/binary>>,
  ?assertEqual({badmatch,First},evaluate_bad(Expr,Old,{Paths,Names,Bad,Config})).

omitted_module_rejected_before_loading_test() ->
  {Expr,Old,{Paths,[_First|Rest],Hash,Config}}=packet(),
  ?assertMatch({badmatch,<<_:256>>},evaluate_bad(Expr,Old,{Paths,Rest,Hash,Config})).
