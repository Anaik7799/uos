-module(telegram_risk_files_test).
-include_lib("eunit/include/eunit.hrl").

utc_parser_test() ->
  ?assertEqual({ok,0},telegram_risk_files:parse_utc_ms(<<"1970-01-01T00:00:00Z">>)),
  ?assertEqual({ok,1709164800000},telegram_risk_files:parse_utc_ms(<<"2024-02-29T00:00:00Z">>)),
  lists:foreach(fun(S)->?assertMatch({error,_},telegram_risk_files:parse_utc_ms(S)) end,
    [<<"2023-02-29T00:00:00Z">>,<<"2026-01-01T24:00:00Z">>,<<"2026-01-01T00:00:60Z">>,
     <<"2026-01-01T00:00:00+00:00">>,<<"2026-01-01T00:00:00.000Z">>,<<"2026-+1-01T00:00:00Z">>,
     <<"1969-12-31T23:59:59Z">>,<<"2026-01-01T00:00:00Z",0>>]).

bounded_source_read_test() ->
  Dir="/tmp/uos-fmea-"++integer_to_list(erlang:unique_integer([positive,monotonic])),
  ok=file:make_dir(Dir),Path=Dir++"/risk.json",Link=Dir++"/link.json",
  Nested=Dir++"/nested",Alias=Dir++"/alias",
  try
    ok=file:write_file(Path,<<"[]">>),
    ?assertMatch({ok,{document,_,<<"[]">>,_,2}},telegram_knowledge_files:read_one(list_to_binary(Path),2)),
    ?assertMatch({error,_},telegram_knowledge_files:read_one(list_to_binary(Path),1)),
    ok=file:make_symlink(Path,Link),
    ?assertMatch({error,_},telegram_knowledge_files:read_one(list_to_binary(Link),100)),
    ok=file:make_dir(Nested),ok=file:write_file(Nested++"/risk.json",<<"[]">>),
    ok=file:make_symlink(Nested,Alias),
    ?assertMatch({error,_},telegram_knowledge_files:read_one(list_to_binary(Alias++"/risk.json"),100)),
    ?assertMatch({error,_},telegram_knowledge_files:read_one(list_to_binary(Dir),100)),
    ?assertMatch({error,_},telegram_knowledge_files:read_one(list_to_binary(Dir++"/absent.json"),100)),
    ok=file:write_file(Path,<<255,254>>),
    ?assertMatch({error,_},telegram_knowledge_files:read_one(list_to_binary(Path),100)),
    ?assertMatch({error,_},telegram_knowledge_files:read_one(list_to_binary(Path),1048577))
  after ok=file:del_dir_r(Dir) end.
