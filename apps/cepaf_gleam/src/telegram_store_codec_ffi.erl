-module(telegram_store_codec_ffi).
-export([parse_strict/1]).

-define(MAX_BYTES, 1048576).
-define(MAX_DEPTH, 64).
-define(MAX_OBJECT_KEYS, 2048).
-define(MAX_ARRAY_ELEMS, 4096).
-define(MAX_TOTAL_NODES, 16384).

wrap_val(true) -> {json_bool, true};
wrap_val(false) -> {json_bool, false};
wrap_val(null) -> json_null;
wrap_val(json_null) -> json_null;
wrap_val(Other) -> Other.

count_node() ->
    N = get(json_nodes),
    case N >= ?MAX_TOTAL_NODES of
        true -> throw(node_budget_exceeded);
        false -> put(json_nodes, N + 1)
    end.

parse_strict(Binary) when is_binary(Binary), byte_size(Binary) =< ?MAX_BYTES ->
    Decoders = #{
        object_start => fun(_) ->
            D = get(json_depth),
            case D >= ?MAX_DEPTH of
                true -> throw(depth_exceeded);
                false ->
                    count_node(),
                    put(json_depth, D + 1),
                    {[], #{}}
            end
        end,
        object_push => fun(Key, Value, {Acc, Map}) ->
            KeyBin = case Key of
                {json_string, S} -> S;
                _ when is_binary(Key) -> Key
            end,
            case maps:is_key(KeyBin, Map) of
                true -> throw({duplicate_key, KeyBin});
                false ->
                    case map_size(Map) >= ?MAX_OBJECT_KEYS of
                        true -> throw(object_too_wide);
                        false ->
                            count_node(),
                            {[{KeyBin, wrap_val(Value)} | Acc], Map#{KeyBin => true}}
                    end
            end
        end,
        object_finish => fun({Acc, _Map}, OldAcc) ->
            put(json_depth, get(json_depth) - 1),
            {{json_object, lists:reverse(Acc)}, OldAcc}
        end,
        array_start => fun(_) ->
            D = get(json_depth),
            case D >= ?MAX_DEPTH of
                true -> throw(depth_exceeded);
                false ->
                    count_node(),
                    put(json_depth, D + 1),
                    {0, []}
            end
        end,
        array_push => fun(Elem, {Count, Acc}) ->
            case Count >= ?MAX_ARRAY_ELEMS of
                true -> throw(array_too_long);
                false ->
                    count_node(),
                    {Count + 1, [wrap_val(Elem) | Acc]}
            end
        end,
        array_finish => fun({_Count, Acc}, OldAcc) ->
            put(json_depth, get(json_depth) - 1),
            {{json_array, lists:reverse(Acc)}, OldAcc}
        end,
        float => fun(B) -> {json_float, erlang:binary_to_float(B)} end,
        integer => fun(B) -> {json_int, erlang:binary_to_integer(B)} end,
        string => fun(S) -> {json_string, S} end,
        null => json_null
    },
    put(json_depth, 0),
    put(json_nodes, 0),
    try
        case json:decode(Binary, ok, Decoders) of
            {Term, _, Rest} ->
                case is_whitespace(Rest) of
                    true -> {ok, wrap_val(Term)};
                    false -> {error, <<"trailing_garbage">>}
                end
        end
    catch
        throw:{duplicate_key, _} -> {error, <<"duplicate_json_keys">>};
        throw:depth_exceeded -> {error, <<"json_nesting_depth_exceeded">>};
        throw:object_too_wide -> {error, <<"json_object_too_wide">>};
        throw:array_too_long -> {error, <<"json_array_too_long">>};
        throw:node_budget_exceeded -> {error, <<"json_node_budget_exceeded">>};
        _:_ -> {error, <<"invalid_json">>}
    after
        erase(json_depth),
        erase(json_nodes)
    end;
parse_strict(_) -> {error, <<"oversized_frame">>}.

is_whitespace(<<>>) -> true;
is_whitespace(<<$\s, Rest/binary>>) -> is_whitespace(Rest);
is_whitespace(<<$\t, Rest/binary>>) -> is_whitespace(Rest);
is_whitespace(<<$\r, Rest/binary>>) -> is_whitespace(Rest);
is_whitespace(<<$\n, Rest/binary>>) -> is_whitespace(Rest);
is_whitespace(_) -> false.
