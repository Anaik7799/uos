-module(uos_ffi).
-export([get_arguments/0, file_exists/1, matches_timestamp_format/1]).

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

matches_timestamp_format(Filename) ->
    case re:run(Filename, "^[0-9]{8}-[0-9]{4}-") of
        {match, _} -> true;
        _ -> false
    end.
