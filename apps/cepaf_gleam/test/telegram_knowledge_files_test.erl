-module(telegram_knowledge_files_test).
-include_lib("eunit/include/eunit.hrl").
with_root(F) ->
  Root=list_to_binary("/tmp/uos-knowledge-"++integer_to_list(erlang:unique_integer([positive,monotonic]))++"-"++integer_to_list(erlang:system_time(microsecond))),
  ok=file:make_dir(Root),
  try F(Root) after file:del_dir_r(Root) end.
scan(R,N,B,S,D) -> telegram_knowledge_files:catalog([{R,<<"docs/wiki">>}],N,B,S,D).
observed_content_and_hash_test() -> with_root(fun(R) ->
  ok=file:write_file(<<R/binary,"/a.md">>,<<"actual body">>),
  ok=file:write_file(<<R/binary,"/ignored.txt">>,<<"ignored">>),
  {ok,{catalog,[{document,<<"docs/wiki/a.md">>,<<"actual body">>,Hash,11}],0}}=scan(R,10,100,100,2),
  ?assertEqual(binary:encode_hex(crypto:hash(sha256,<<"actual body">>),lowercase),Hash)
end).
symlink_exclusion_test() -> with_root(fun(R) ->
  ok=file:make_symlink(<<"/etc">>,<<R/binary,"/outside">>),
  ok=file:make_symlink(<<"/etc/passwd">>,<<R/binary,"/outside.md">>),
  ?assertEqual({ok,{catalog,[],2}},scan(R,10,100,100,2)),
  ?assertMatch({error,_},scan(<<R/binary,"/outside">>,10,100,100,2))
end).
file_count_and_byte_limits_test() -> with_root(fun(R) ->
  ok=file:write_file(<<R/binary,"/a.md">>,<<"abcd">>),
  ok=file:write_file(<<R/binary,"/b.md">>,<<"efgh">>),
  ?assertMatch({error,_},scan(R,1,100,100,2)),
  ?assertMatch({error,_},scan(R,2,7,100,2)),
  ?assertMatch({error,_},scan(R,2,100,3,2)),
  ?assertMatch({ok,{catalog,[_,_],0}},scan(R,2,8,4,2))
end).
depth_and_missing_root_test() -> with_root(fun(R) ->
  ok=file:make_dir(<<R/binary,"/nested">>),
  ok=file:write_file(<<R/binary,"/nested/a.md">>,<<"ok">>),
  ?assertMatch({error,_},scan(R,10,100,100,0)),
  ?assertMatch({ok,_},scan(R,10,100,100,1)),
  ?assertMatch({error,_},scan(<<R/binary,"/missing">>,10,100,100,2)),
  ?assertMatch({error,_},scan(<<R/binary,"/nested/a.md">>,10,100,100,2))
end).
invalid_utf8_test() -> with_root(fun(R) ->
  ok=file:write_file(<<R/binary,"/bad.md">>,<<255>>),
  ?assertMatch({error,_},scan(R,10,100,100,2))
end).
invalid_budget_test() ->
  ?assertMatch({error,_},scan(<<"/tmp">>,0,100,100,2)),
  ?assertMatch({error,_},scan(<<"/tmp">>,1025,100,100,2)),
  ?assertMatch({error,_},scan(<<"/tmp">>,10,8388609,100,2)),
  ?assertMatch({error,_},scan(<<"/tmp">>,10,100,262145,2)),
  ?assertMatch({error,_},scan(<<"/tmp">>,10,100,100,5)).
knowledge_binding_refuses_bad_scope_test() ->
  ?assertMatch({error,_},telegram_coordination_binding:launch_knowledge_eval(<<"outside">>,<<>>)),
  ?assertMatch({error,_},telegram_coordination_binding:launch_knowledge_eval(<<"wiki">>,<<0>>)),
  {ok,E}=telegram_coordination_binding:launch_knowledge_eval(<<"all">>,<<"x\";halt(1)">>),
  ?assert(byte_size(E)=<4096).
