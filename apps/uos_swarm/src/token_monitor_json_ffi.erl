%% Bounded JSON decoding for the peer observation, using OTP's decoder hooks.
%% Source contract: https://www.erlang.org/doc/apps/stdlib/json.html#decode/3
%% API exists since OTP 27; effective runtime version is recorded separately.
-module(token_monitor_json_ffi).
-export([valid_object/1]).
-export([read_receipt/1]).
-include_lib("kernel/include/file.hrl").

%% One bounded descriptor read with source identity, avoiding path-alias counting.
%% No path, contents or credential material is returned in an error.
read_receipt(Path) when is_binary(Path), byte_size(Path) =< 4096 ->
    case file:read_file_info(Path) of
        {ok,#file_info{type=regular,size=Size}} when Size =< 65536 -> read_regular(Path);
        _ -> {error,<<"receipt_requires_bounded_regular_file">>}
    end;
read_receipt(_) -> {error,<<"invalid_receipt_path">>}.

read_regular(Path) ->
    case file:open(Path, [read,binary,raw]) of
        {ok,Fd} -> try
            case file:read_file_info(Fd) of
                {ok,Before=#file_info{type=regular,size=Size}} when Size =< 65536 ->
                    case file:read(Fd,65537) of
                        {ok,Bin} when byte_size(Bin) =< 65536 ->
                            case file:read_file_info(Fd) of
                                {ok,After} ->
                                    true = Before#file_info{atime=undefined} =:= After#file_info{atime=undefined},
                                    Dev=Before#file_info.major_device,
                                    Inode=Before#file_info.inode,
                                    Key=iolist_to_binary(io_lib:format("~p:~p",[Dev,Inode])),
                                    Digest=binary:encode_hex(crypto:hash(sha256,Bin),lowercase),
                                    {ok,{Bin,Key,Digest}};
                                _ -> {error,<<"receipt_changed_during_read">>}
                            end;
                        eof -> {error,<<"receipt_empty_or_inflight">>};
                        _ -> {error,<<"receipt_read_or_size_failure">>}
                    end;
                _ -> {error,<<"receipt_requires_bounded_regular_file">>}
            end
        catch _:_ -> {error,<<"receipt_read_failure">>}
        after file:close(Fd) end;
        _ -> {error,<<"receipt_open_failure">>}
    end.

valid_object(Bytes) when is_binary(Bytes), byte_size(Bytes) =< 1048576 ->
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
bounds(_, Depth, _, _, Nodes) when Depth < 0; Depth > 16; Nodes > 100000 -> false;
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
