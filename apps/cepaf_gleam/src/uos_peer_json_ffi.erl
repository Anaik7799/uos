%% Bounded JSON decoding for the peer observation, using OTP's decoder hooks.
%% Source contract: https://www.erlang.org/doc/apps/stdlib/json.html#decode/3
%% API exists since OTP 27; effective runtime version is recorded separately.
-module(uos_peer_json_ffi).
-export([valid_object/1]).

valid_object(Bytes) when is_binary(Bytes), byte_size(Bytes) =< 32768 ->
    case bounds(Bytes, 0, false, false, 0) of
        false -> false;
        true ->
            Push = fun(Key, Value, Map) ->
                case maps:is_key(Key, Map) of
                    true -> erlang:error(duplicate_json_key);
                    false -> Map#{Key => Value}
                end
            end,
            Options = #{object_start => fun(_) -> #{} end,
                        object_push => Push,
                        object_finish => fun(Map, Old) -> {Map, Old} end},
            try json:decode(Bytes, ok, Options) of
                {Map, ok, Rest} when is_map(Map) -> whitespace(Rest);
                _ -> false
            catch error:_ -> false end
    end;
valid_object(_) -> false.

whitespace(<<>>) -> true;
whitespace(<<C, Rest/binary>>) when C =:= 32; C =:= 9; C =:= 10; C =:= 13 ->
    whitespace(Rest);
whitespace(_) -> false.

%% Depth and structural quotas are checked BEFORE entering the JSON parser.
bounds(_, Depth, _, _, Nodes) when Depth < 0; Depth > 32; Nodes > 8192 -> false;
bounds(<<>>, 0, false, false, _) -> true;
bounds(<<>>, _, _, _, _) -> false;
bounds(<<_, Rest/binary>>, Depth, true, true, Nodes) ->
    bounds(Rest, Depth, true, false, Nodes);
bounds(<<$\\, Rest/binary>>, Depth, true, false, Nodes) ->
    bounds(Rest, Depth, true, true, Nodes);
bounds(<<$", Rest/binary>>, Depth, Quoted, false, Nodes) ->
    bounds(Rest, Depth, not Quoted, false, Nodes);
bounds(<<_, Rest/binary>>, Depth, true, false, Nodes) ->
    bounds(Rest, Depth, true, false, Nodes);
bounds(<<C, Rest/binary>>, Depth, false, false, Nodes) when C =:= ${; C =:= $[ ->
    bounds(Rest, Depth + 1, false, false, Nodes + 1);
bounds(<<C, Rest/binary>>, Depth, false, false, Nodes) when C =:= $}; C =:= $] ->
    bounds(Rest, Depth - 1, false, false, Nodes + 1);
bounds(<<C, Rest/binary>>, Depth, false, false, Nodes) when C =:= $:; C =:= $, ->
    bounds(Rest, Depth, false, false, Nodes + 1);
bounds(<<_, Rest/binary>>, Depth, false, false, Nodes) ->
    bounds(Rest, Depth, false, false, Nodes).
