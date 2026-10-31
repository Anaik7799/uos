-module(token_monitor_source_test).
-include_lib("eunit/include/eunit.hrl").

row(Path,Id) -> #{<<"format">>=><<"claude_cli">>,<<"provider">>=><<"claude">>,
 <<"request_id">>=>Id,<<"agent">>=><<"claude">>,<<"model">>=><<"mixed">>,<<"path">>=>Path}.
manifest(Rows) -> iolist_to_binary(json:encode(#{<<"schema_version">>=>1,
 <<"max_tokens">>=>1000,<<"max_calls">>=>10,<<"sources">>=>Rows})).
fixture() -> <<"{\"type\":\"result\",\"session_id\":\"same-session\",\"is_error\":false,\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"cache_read_input_tokens\":3,\"cache_creation_input_tokens\":4},\"total_cost_usd\":0.01}">>.

source_alias_and_copy_refusal_test() ->
 D=list_to_binary("/tmp/uos-token-monitor-source-"++integer_to_list(erlang:unique_integer([positive]))),
 ok=file:make_dir(D), P= <<D/binary,"/receipt.json">>, H= <<D/binary,"/hard.json">>,
 S= <<D/binary,"/sym.json">>, C= <<D/binary,"/copy.json">>,
 try
  ok=file:write_file(P,fixture()),ok=file:make_link(P,H),ok=file:make_symlink(P,S),
  {ok,_}=file:copy(P,C),
  Paths=[P,<<D/binary,"/./receipt.json">>,H,S,C],
  lists:foreach(fun(Alias)->
   ?assertEqual({error,<<"ambiguous_receipt_source_alias">>},
    'uos_swarm@token_monitor_manifest':report(manifest([row(P,<<"same-session">>),row(Alias,<<"other">>)])))
  end,Paths),
  {ok,Json}='uos_swarm@token_monitor_manifest':report(manifest([row(P,<<"same-session">>),row(C,<<"same-session">>)])),
  Report=json:decode('gleam@json':to_string(Json)),
  ?assertEqual(1,maps:get(<<"unique_calls">>,maps:get(<<"report">>,Report)))
 after
  lists:foreach(fun file:delete/1,[P,H,S,C]),file:del_dir(D)
 end.

empty_and_large_receipt_refuse_test() ->
 D=list_to_binary("/tmp/uos-token-monitor-bytes-"++integer_to_list(erlang:unique_integer([positive]))),
 ok=file:make_dir(D),P= <<D/binary,"/raw.json">>,
 try
  ok=file:write_file(P,<<>>),
  ?assertEqual({error,<<"receipt_empty_or_inflight">>},token_monitor_json_ffi:read_receipt(P)),
  ok=file:write_file(P,binary:copy(<<"x">>,65537)),
  ?assertEqual({error,<<"receipt_requires_bounded_regular_file">>},token_monitor_json_ffi:read_receipt(P))
 after file:delete(P),file:del_dir(D) end.

