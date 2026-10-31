%% Bounded filesystem primitives only; routing, allowlists and rendering are Gleam.
-module(live_corpus_ffi).
-export([read/3, names/1, sha256/1]).
-include_lib("kernel/include/file.hrl").
sha256(Bin) -> string:lowercase(binary:encode_hex(crypto:hash(sha256, Bin))).
names(Path) ->
    case file:list_dir(Path) of
        {ok, Names} -> lists:filtermap(fun(N) ->
            case unicode:characters_to_binary(N) of
                B when is_binary(B) -> {true, B};
                _ -> false
            end end, Names);
        _ -> []
    end.
safe(I, Cap) -> I#file_info.type =:= regular andalso I#file_info.links =:= 1
    andalso I#file_info.size =< Cap.
same(A, B, Cap) -> safe(B, Cap) andalso
    A#file_info.inode =:= B#file_info.inode andalso
    A#file_info.major_device =:= B#file_info.major_device andalso
    A#file_info.size =:= B#file_info.size andalso
    A#file_info.mtime =:= B#file_info.mtime andalso
    A#file_info.ctime =:= B#file_info.ctime.
read(Path, Cap) ->
    case file:read_link_info(Path) of
        {ok, Before} -> case safe(Before, Cap) of
            false when Before#file_info.size > Cap -> {error, 413};
            false -> {error, 403};
            true -> case file:open(Path, [read, binary, raw]) of
                {ok, Fd} -> try
                    case file:read_file_info(Fd) of
                        {ok, Actual} -> case same(Before, Actual, Cap) of
                            true -> finish_read(Fd, Path, Before, Cap);
                            false -> {error, 403}
                        end;
                        _ -> {error, 403}
                    end
                after file:close(Fd) end;
                _ -> {error, 404}
            end
        end;
        {error, enoent} -> {error, 404};
        _ -> {error, 403}
    end.
finish_read(Fd, Path, Before, Cap) ->
    Read = case file:pread(Fd, 0, Cap + 1) of eof -> {ok, <<>>}; R -> R end,
    case {Read, file:read_file_info(Fd), file:read_link_info(Path)} of
        {{ok, Bin}, {ok, After}, {ok, Final}} when byte_size(Bin) =< Cap ->
            case same(Before, After, Cap) andalso same(Before, Final, Cap) of
                false -> {error, 403};
                true -> case unicode:characters_to_binary(Bin, utf8, utf8) of
                    Bin -> {ok, Bin};
                    _ -> {error, 400}
                end
            end;
        {{ok, _}, _, _} -> {error, 413};
        _ -> {error, 404}
    end.

%% Linux/OTP pinned descriptor-relative traversal. Each directory stays open
%% through the final read. /proc/self/fd refers to that open directory, so an
%% ancestor rename or symlink substitution cannot redirect later resolution.
%% Missing /proc or unsupported raw handles fail closed (no absolute fallback).
read(Root, Relative, Cap) ->
    try
        case file:read_link_info(Root) of
            {ok, Before} when Before#file_info.type =:= directory ->
                with_directory(Root, Before, fun(Fd) ->
                    anchored(Fd, binary:split(Relative, <<"/">>, [global]), Cap)
                end);
            _ -> {error, 403}
        end
    catch _:_ -> {error, 403} end.
identity(A, B) -> A#file_info.type =:= B#file_info.type andalso
    A#file_info.inode =:= B#file_info.inode andalso
    A#file_info.major_device =:= B#file_info.major_device.
with_directory(Path, Before, Fun) ->
    case file:open(Path, [read, raw, binary, directory]) of
        {ok, Fd} -> try
            case {file:read_file_info(Fd), file:read_link_info(Path)} of
                {{ok, Actual}, {ok, After}} ->
                    case identity(Before, Actual) andalso identity(Before, After) of
                        true -> Fun(Fd);
                        false -> {error, 403}
                    end;
                _ -> {error, 403}
            end
        after file:close(Fd) end;
        _ -> {error, 403}
    end.
fd_path(Fd, Segment) ->
    Handle = prim_file:get_handle(Fd),
    true = byte_size(Handle) =:= 4,
    Number = binary:decode_unsigned(Handle, erlang:system_info(endian)),
    <<"/proc/self/fd/", (integer_to_binary(Number))/binary, "/", Segment/binary>>.
anchored(Fd, [Segment], Cap) -> read(fd_path(Fd, Segment), Cap);
anchored(Fd, [Segment|Rest], Cap) ->
    Path = fd_path(Fd, Segment),
    case file:read_link_info(Path) of
        {ok, Before} when Before#file_info.type =:= directory ->
            with_directory(Path, Before, fun(Child) -> anchored(Child, Rest, Cap) end);
        {error, enoent} -> {error, 404};
        _ -> {error, 403}
    end;
anchored(_, _, _) -> {error, 403}.
