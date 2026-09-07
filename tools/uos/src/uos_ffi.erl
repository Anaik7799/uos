-module(uos_ffi).
-export([get_arguments/0, file_exists/1, file_size/1, matches_timestamp_format/1, file_contains/2, halt/1]).
-include_lib("kernel/include/file.hrl").

halt(Code) ->
    erlang:halt(Code).


get_arguments() ->
    Args = init:get_plain_arguments(),
    [case unicode:characters_to_binary(A) of
        B when is_binary(B) -> B;
        _ -> list_to_binary(A)
     end || A <- Args].

file_exists(Path) ->
    case file:read_file_info(Path) of
        {ok, _} -> true;
        _ ->
            RootPath = filename:join(["/home/an/NAS-setup/uos", Path]),
            case file:read_file_info(RootPath) of
                {ok, _} -> true;
                _ -> false
            end
    end.

file_size(Path) ->
    Info = case file:read_file_info(Path) of
        {ok, I} -> {ok, I};
        _ ->
            RootPath = filename:join(["/home/an/NAS-setup/uos", Path]),
            file:read_file_info(RootPath)
    end,
    case Info of
        {ok, #file_info{size = Size}} -> Size;
        _ -> -1
    end.

matches_timestamp_format(Filename) ->
    case re:run(Filename, "^[0-9]{8}-[0-9]{4}-") of
        {match, _} -> true;
        _ -> false
    end.

file_contains(Path, Pattern) ->
    RealPath = case file:read_file(Path) of
        {ok, Bin} -> {ok, Bin};
        _ ->
            RootPath = filename:join(["/home/an/NAS-setup/uos", Path]),
            file:read_file(RootPath)
    end,
    case RealPath of
        {ok, Content} ->
            PatternBin = case is_list(Pattern) of
                true -> unicode:characters_to_binary(Pattern);
                false -> Pattern
            end,
            case binary:match(Content, PatternBin) of
                nomatch -> false;
                _ -> true
            end;
        _ -> false
    end.

