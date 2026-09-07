-module(uos_ffi).
-export([get_arguments/0, file_exists/1, matches_timestamp_format/1, file_contains/2, halt/1]).

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
        _ -> false
    end.

matches_timestamp_format(Filename) ->
    case re:run(Filename, "^[0-9]{8}-[0-9]{4}-") of
        {match, _} -> true;
        _ -> false
    end.

file_contains(Path, Pattern) ->
    RealPath = file:read_file(Path),
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
