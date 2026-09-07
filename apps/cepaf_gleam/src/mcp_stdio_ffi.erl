-module(mcp_stdio_ffi).
-export([read_line/0]).

-define(MAX_LINE_BYTES, 1048576).

%% io:get_line/1 returns a character list under the default standard_io
%% configuration and a binary when binary mode is enabled. Normalize both
%% without changing global IO options, and reject oversized request frames.
read_line() ->
    case io:get_line("") of
        eof -> end_of_file;
        {error, Reason} -> {read_error, reason_binary(Reason)};
        Data -> normalize_line(Data)
    end.

normalize_line(Data) when is_binary(Data) -> bounded_line(Data);
normalize_line(Data) when is_list(Data) ->
    case unicode:characters_to_binary(Data) of
        Binary when is_binary(Binary) -> bounded_line(Binary);
        {error, _, _} -> {read_error, <<"stdin line is not valid Unicode">>};
        {incomplete, _, _} -> {read_error, <<"stdin line has incomplete Unicode">>}
    end;
normalize_line(_) -> {read_error, <<"stdin returned an unsupported value">>}.

bounded_line(Binary) when byte_size(Binary) =< ?MAX_LINE_BYTES -> {line, Binary};
bounded_line(_) -> {read_error, <<"stdin line exceeds 1048576-byte limit">>}.

reason_binary(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).
