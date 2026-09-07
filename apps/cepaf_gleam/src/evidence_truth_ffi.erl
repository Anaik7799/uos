-module(evidence_truth_ffi).
-export([read_candidate_file/3, sha256_candidate_file/3, unix_seconds/0]).

-include_lib("kernel/include/file.hrl").

unix_seconds() -> erlang:system_time(second).

read_candidate_file(Root0, Rel0, Cap) ->
    case safe_regular_path(Root0, Rel0) of
        {ok, Path} -> bounded_read(Path, Cap);
        {error, Reason} -> {error, atom_or_binary(Reason)}
    end.

sha256_candidate_file(Root0, Rel0, Cap) ->
    case read_candidate_file(Root0, Rel0, Cap) of
        {ok, Bin} -> {ok, binary:encode_hex(crypto:hash(sha256, Bin), lowercase)};
        Error -> Error
    end.

safe_regular_path(Root0, Rel0) ->
    Root = filename:dirname(filename:absname(filename:join(binary_to_list(Root0), "__uos_root_marker__"))),
    Rel = binary_to_list(Rel0),
    case filename:pathtype(Rel) =:= relative andalso safe_parts(filename:split(Rel)) of
        false -> {error, unsafe_path};
        true ->
            Path = filename:absname(filename:join(Root, Rel)),
            Prefix = Root ++ "/",
            case lists:prefix(Prefix, Path) andalso no_symlink_components(Root, filename:split(Rel)) of
                false -> {error, unsafe_path};
                true ->
                    case file:read_link_info(Path) of
                        {ok, #file_info{type = regular}} -> {ok, Path};
                        {ok, _} -> {error, not_regular};
                        {error, Reason} -> {error, Reason}
                    end
            end
    end.

safe_parts([]) -> false;
safe_parts(Parts) ->
    lists:all(fun(P) -> P =/= "" andalso P =/= "." andalso P =/= ".." end, Parts).

no_symlink_components(_Current, []) -> true;
no_symlink_components(Current, [Part | Rest]) ->
    Next = filename:join(Current, Part),
    case file:read_link_info(Next) of
        {ok, #file_info{type = symlink}} -> false;
        {ok, _} -> no_symlink_components(Next, Rest);
        {error, _} -> false
    end.

bounded_read(Path, Cap) when is_integer(Cap), Cap > 0 ->
    case file:open(Path, [read, binary, raw]) of
        {ok, Io} ->
            Result = case file:read(Io, Cap + 1) of
                eof -> {ok, <<>>};
                {ok, Bin} when byte_size(Bin) =< Cap -> {ok, Bin};
                {ok, _} -> {error, cap_exceeded};
                {error, Reason} -> {error, Reason}
            end,
            ok = file:close(Io),
            Result;
        {error, Reason} -> {error, Reason}
    end;
bounded_read(_, _) -> {error, invalid_cap}.

atom_or_binary(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
atom_or_binary(Value) when is_binary(Value) -> Value.
