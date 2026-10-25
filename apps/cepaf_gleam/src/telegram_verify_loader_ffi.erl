%% Bounded binary file digest for the /verify profile loader. Refuses anything
%% but a regular single-link file whose identity and size are unchanged across
%% the read; hashes in 64 KiB chunks so executables are never held whole.
-module(telegram_verify_loader_ffi).
-export([file_sha256/2]).
-include_lib("kernel/include/file.hrl").

file_sha256(Path, MaxBytes) when is_binary(Path), is_integer(MaxBytes), MaxBytes > 0 ->
    case file:read_link_info(Path, [raw]) of
        {ok, #file_info{type = regular, links = 1, size = Size, inode = Ino,
                        major_device = Dev}} when Size =< MaxBytes ->
            case file:open(Path, [read, binary, raw]) of
                {ok, Fd} ->
                    Result = hash_open(Fd, Size, Ino, Dev),
                    _ = file:close(Fd),
                    Result;
                {error, _} -> {error, <<"artifact_open_failed">>}
            end;
        {ok, #file_info{type = regular, links = 1}} -> {error, <<"artifact_size_bound">>};
        {ok, _} -> {error, <<"artifact_not_regular_single_link">>};
        {error, _} -> {error, <<"artifact_unavailable">>}
    end;
file_sha256(_, _) -> {error, <<"artifact_request_invalid">>}.

hash_open(Fd, Size, Ino, Dev) ->
    case file:read_file_info(Fd, [raw]) of
        {ok, #file_info{inode = Ino, major_device = Dev, size = Size}} ->
            case chunks(Fd, crypto:hash_init(sha256), 0, Size) of
                {ok, Ctx} ->
                    case file:read_file_info(Fd, [raw]) of
                        {ok, #file_info{inode = Ino, size = Size}} ->
                            {ok, binary:encode_hex(crypto:hash_final(Ctx), lowercase)};
                        _ -> {error, <<"artifact_changed_during_read">>}
                    end;
                Error -> Error
            end;
        _ -> {error, <<"artifact_changed_before_read">>}
    end.

chunks(Fd, Ctx, Seen, Size) ->
    case file:read(Fd, 65536) of
        eof when Seen =:= Size -> {ok, Ctx};
        eof -> {error, <<"artifact_changed_during_read">>};
        {ok, Bytes} when Seen + byte_size(Bytes) =< Size ->
            chunks(Fd, crypto:hash_update(Ctx, Bytes), Seen + byte_size(Bytes), Size);
        {ok, _} -> {error, <<"artifact_changed_during_read">>};
        {error, _} -> {error, <<"artifact_read_failed">>}
    end.
