%% Decode one ZLP hyperplane subscription push for bridge/zenoh_mcp.gleam.
%%
%% The ZLP shard delivers {zlp_zenoh_push, ShardId, Excl, Digest, JsonBin}
%% (uos_zlp_shard.erl:109) where JsonBin is {"key":...,"value":...,...}. The
%% bridge needs the key and the value re-serialised as a JSON string, because
%% runtime_gateway:handle_zenoh_raw/2 takes the envelope as text.
%%
%% Pure decode: no I/O, no spawning, no effects. Any malformed input is an
%% error, never a partially decoded push.
-module(zenoh_mcp_ffi).
-export([split_push/1, push_json/1]).

split_push(JsonBin) when is_binary(JsonBin), byte_size(JsonBin) =< 2097152 ->
    try
        Map = json:decode(JsonBin),
        Key = maps:get(<<"key">>, Map),
        Value = maps:get(<<"value">>, Map),
        true = is_binary(Key),
        ValueJson =
            case Value of
                B when is_binary(B) -> B;
                _ -> iolist_to_binary(json:encode(Value))
            end,
        {ok, {Key, ValueJson}}
    catch
        _:_ -> {error, nil}
    end;
split_push(_) ->
    {error, nil}.

%% Extract the JSON body from a raw {zlp_zenoh_push, Shard, Seq, Digest, Json}
%% tuple arriving as a selector Dynamic. Shard/seq/digest are transport
%% bookkeeping and are not part of the signed envelope, so they are dropped
%% rather than carried into the message type.
push_json({zlp_zenoh_push, _Shard, _Seq, _Digest, Json}) when is_binary(Json) ->
    {ok, Json};
push_json(_) ->
    {error, nil}.
