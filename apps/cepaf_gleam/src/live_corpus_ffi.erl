%% Bounded filesystem primitives only; routing, allowlists and rendering are Gleam.
-module(live_corpus_ffi).
-export([read/3, names/1, sha256/1, lstat_raw/1, pmap/2, scan_clean_children/2, walk_trees_bfs/2, count_buckets/1, sort_entries_newest/1, is_url_clean_path/1, encode_catalog_json/9]).
-include_lib("kernel/include/file.hrl").
sha256(Bin) -> string:lowercase(binary:encode_hex(crypto:hash(sha256, Bin))).

pmap(Items, Fun) ->
    Parent = self(),
    Workers = [
        spawn_monitor(fun() ->
            Parent ! {self(), Fun(Item)}
        end)
        || Item <- Items
    ],
    [
        receive
            {Pid, Result} ->
                erlang:demonitor(Ref, [flush]),
                Result;
            {'DOWN', Ref, process, Pid, Reason} ->
                erlang:error({pmap_worker_failed, Pid, Reason})
        end
        || {Pid, Ref} <- Workers
    ].

sort_entries_newest(Entries) ->
    Keyed = [{element(4, E), element(2, E), E} || E <- Entries],
    extract_sorted_desc(lists:sort(Keyed), []).

extract_sorted_desc([], Acc) ->
    Acc;
extract_sorted_desc([{_, _, E} | Rest], Acc) ->
    extract_sorted_desc(Rest, [E | Acc]).

is_url_clean_path(<<>>) ->
    true;
is_url_clean_path(<<C, Rest/binary>>)
  when (C >= $a andalso C =< $z) orelse
       (C >= $A andalso C =< $Z) orelse
       (C >= $0 andalso C =< $9) orelse
       C =:= $/ orelse C =:= $- orelse C =:= $_ orelse C =:= $. orelse C =:= $~ ->
    is_url_clean_path(Rest);
is_url_clean_path(_) ->
    false.

markers_pattern() ->
    Key = {?MODULE, markers_cp},
    case persistent_term:get(Key, undefined) of
        undefined ->
            Cp = binary:compile_pattern([
                <<".env">>, <<".pem">>, <<".key">>, <<".p12">>, <<".pfx">>,
                <<"id_rsa">>, <<"id_ed25519">>, <<"credentials">>, <<"secret_key">>,
                <<".sqlite">>, <<".db">>, <<"-wal">>, <<"-shm">>
            ]),
            persistent_term:put(Key, Cp),
            Cp;
        Cp ->
            Cp
    end.

is_barred_cache_segment(<<".lake">>) -> true;
is_barred_cache_segment(<<"__pycache__">>) -> true;
is_barred_cache_segment(<<"_build">>) -> true;
is_barred_cache_segment(<<"node_modules">>) -> true;
is_barred_cache_segment(<<".cache">>) -> true;
is_barred_cache_segment(<<".git">>) -> true;
is_barred_cache_segment(<<".jj">>) -> true;
is_barred_cache_segment(_) -> false.

valid_segment_bytes(<<>>) -> true;
valid_segment_bytes(<<C, _/binary>>) when C < 32; C =:= 127; C =:= $/; C =:= $\\; C =:= $% -> false;
valid_segment_bytes(<<C, Rest/binary>>) when C < 128 -> valid_segment_bytes(Rest);
valid_segment_bytes(Bin) ->
    case unicode:characters_to_list(Bin, utf8) of
        Chars when is_list(Chars) ->
            lists:all(fun(Cp) -> Cp >= 32 andalso Cp =/= 127 andalso Cp =/= $/ andalso Cp =/= $\\ andalso Cp =/= $% end, Chars);
        _ -> false
    end.

fast_lowercase(Bin) ->
    fast_lowercase(Bin, <<>>).

fast_lowercase(<<>>, Acc) -> Acc;
fast_lowercase(<<C, Rest/binary>>, Acc) when C >= $A, C =< $Z ->
    fast_lowercase(Rest, <<Acc/binary, (C + 32)>>);
fast_lowercase(<<C, Rest/binary>>, Acc) when C < 128 ->
    fast_lowercase(Rest, <<Acc/binary, C>>);
fast_lowercase(OrigRest, Acc) ->
    RestLower = unicode:characters_to_binary(string:lowercase(OrigRest)),
    <<Acc/binary, RestLower/binary>>.

is_clean_segment(<<>>, _Cp) -> false;
is_clean_segment(<<".">>, _Cp) -> false;
is_clean_segment(<<"..">>, _Cp) -> false;
is_clean_segment(Bin, Cp) ->
    case valid_segment_bytes(Bin) of
        false -> false;
        true ->
            Lower = fast_lowercase(Bin),
            (not is_barred_cache_segment(Lower)) andalso (binary:match(Lower, Cp) =:= nomatch)
    end.

to_utf8_bin(N) when is_binary(N) ->
    case unicode:characters_to_binary(N, utf8, utf8) of
        B when is_binary(B) -> {ok, B};
        _ -> error
    end;
to_utf8_bin(N) when is_list(N) ->
    case unicode:characters_to_binary(N) of
        B when is_binary(B) -> {true_bin, B};
        _ -> error
    end;
to_utf8_bin(_) -> error.

chunk_list([], _Size) -> [];
chunk_list(List, Size) ->
    case length(List) =< Size of
        true -> [List];
        false ->
            {Head, Tail} = lists:split(Size, List),
            [Head | chunk_list(Tail, Size)]
    end.

scan_chunk(RawChunk, DirRel, FsDir, Cp) ->
    lists:filtermap(fun(RawN) ->
        Norm = case to_utf8_bin(RawN) of
            {ok, B} -> {ok, B};
            {true_bin, B} -> {ok, B};
            error -> error
        end,
        case Norm of
            {ok, NameBin} ->
                case is_clean_segment(NameBin, Cp) of
                    false -> false;
                    true ->
                        ChildRel = case DirRel of
                            <<>> -> NameBin;
                            _ -> <<DirRel/binary, "/", NameBin/binary>>
                        end,
                        ChildFs = <<FsDir/binary, "/", NameBin/binary>>,
                        case prim_file:read_link_info(ChildFs, [{time, posix}]) of
                            {ok, #file_info{type = directory, size = Size, mtime = Mtime}}
                              when is_integer(Size), is_integer(Mtime) ->
                                {true, {ChildRel, NameBin, true, Size, Mtime}};
                            {ok, #file_info{type = regular, links = 1, size = Size, mtime = Mtime}}
                              when is_integer(Size), is_integer(Mtime) ->
                                {true, {ChildRel, NameBin, false, Size, Mtime}};
                            _ ->
                                false
                        end
                end;
            error ->
                false
        end
    end, RawChunk).

scan_clean_children(Root, DirRel) ->
    FsDir = case DirRel of
        <<>> -> Root;
        _ -> <<Root/binary, "/", DirRel/binary>>
    end,
    case prim_file:list_dir(FsDir) of
        {ok, RawNames} ->
            Cp = markers_pattern(),
            case length(RawNames) > 256 of
                false ->
                    scan_chunk(RawNames, DirRel, FsDir, Cp);
                true ->
                    Chunks = chunk_list(RawNames, 256),
                    lists:append(pmap(Chunks, fun(Ch) -> scan_chunk(Ch, DirRel, FsDir, Cp) end))
            end;
        _ ->
            []
    end.

has_allowed_ext(Lower) ->
    Sz = byte_size(Lower),
    (Sz >= 3 andalso (
        binary:part(Lower, Sz - 3, 3) =:= <<".md">> orelse
        binary:part(Lower, Sz - 3, 3) =:= <<".ml">> orelse
        binary:part(Lower, Sz - 3, 3) =:= <<".sh">>
    )) orelse
    (Sz >= 4 andalso (
        binary:part(Lower, Sz - 4, 4) =:= <<".qnt">> orelse
        binary:part(Lower, Sz - 4, 4) =:= <<".txt">> orelse
        binary:part(Lower, Sz - 4, 4) =:= <<".mli">> orelse
        binary:part(Lower, Sz - 4, 4) =:= <<".zig">> orelse
        binary:part(Lower, Sz - 4, 4) =:= <<".sql">> orelse
        binary:part(Lower, Sz - 4, 4) =:= <<".svg">>
    )) orelse
    (Sz >= 5 andalso (
        binary:part(Lower, Sz - 5, 5) =:= <<".toml">> orelse
        binary:part(Lower, Sz - 5, 5) =:= <<".json">> orelse
        binary:part(Lower, Sz - 5, 5) =:= <<".lean">> orelse
        binary:part(Lower, Sz - 5, 5) =:= <<".html">>
    )) orelse
    (Sz >= 6 andalso binary:part(Lower, Sz - 6, 6) =:= <<".gleam">>) orelse
    (Sz >= 7 andalso binary:part(Lower, Sz - 7, 7) =:= <<".allium">>).

allowed_tree_file_bin(ChildRel, NameBin, Lower) ->
    has_allowed_ext(Lower) andalso (
        case ChildRel of
            <<"plugins/", _/binary>> ->
                NameSz = byte_size(NameBin),
                (NameSz >= 3 andalso binary:part(NameBin, NameSz - 3, 3) =:= <<".md">>) orelse
                (NameSz >= 5 andalso binary:part(NameBin, NameSz - 5, 5) =:= <<".json">>) orelse
                (binary:match(ChildRel, <<"/references/">>) =/= nomatch);
            _ ->
                true
        end
    ).

is_clean_lower_ascii([]) ->
    true;
is_clean_lower_ascii([C | _])
  when not is_integer(C); C < 32; C >= 127; C =:= $/; C =:= $\\; C =:= $%; (C >= $A andalso C =< $Z) ->
    false;
is_clean_lower_ascii([_ | Rest]) ->
    is_clean_lower_ascii(Rest).

norm_ascii([], RevOrig, RevLow) ->
    {ok, list_to_binary(lists:reverse(RevOrig)), list_to_binary(lists:reverse(RevLow))};
norm_ascii([C | _], _RevOrig, _RevLow)
  when is_integer(C), (C < 32 orelse C =:= 127 orelse C =:= $/ orelse C =:= $\\ orelse C =:= $%) ->
    error;
norm_ascii([C | Rest], RevOrig, RevLow) when is_integer(C), C >= $A, C =< $Z ->
    norm_ascii(Rest, [C | RevOrig], [C + 32 | RevLow]);
norm_ascii([C | Rest], RevOrig, RevLow) when is_integer(C), C < 128 ->
    norm_ascii(Rest, [C | RevOrig], [C | RevLow]);
norm_ascii(_, _RevOrig, _RevLow) ->
    fallback.

norm_segment([]) ->
    error;
norm_segment([$.]) ->
    error;
norm_segment([$., $.]) ->
    error;
norm_segment(RawN) when is_list(RawN) ->
    case is_clean_lower_ascii(RawN) of
        true ->
            Bin = list_to_binary(RawN),
            {ok, Bin, Bin};
        false ->
            case norm_ascii(RawN, [], []) of
                {ok, _, _} = Ok -> Ok;
                error -> error;
                fallback -> norm_segment_fallback(RawN)
            end
    end;
norm_segment(RawN) ->
    norm_segment_fallback(RawN).

norm_segment_fallback(RawN) ->
    Norm = case to_utf8_bin(RawN) of
        {ok, B} -> {ok, B};
        {true_bin, B} -> {ok, B};
        error -> error
    end,
    case Norm of
        {ok, NameBin} ->
            case valid_segment_bytes(NameBin) of
                false -> error;
                true -> {ok, NameBin, fast_lowercase(NameBin)}
            end;
        error -> error
    end.

list_one_dir_names([], _DirRelSlash, _FsDirSlash, _Cp, Acc) ->
    Acc;
list_one_dir_names([RawN | Rest], DirRelSlash, FsDirSlash, Cp, Acc) ->
    case norm_segment(RawN) of
        {ok, NameBin, Lower} ->
            case (not is_barred_cache_segment(Lower)) andalso (binary:match(Lower, Cp) =:= nomatch) of
                false ->
                    list_one_dir_names(Rest, DirRelSlash, FsDirSlash, Cp, Acc);
                true ->
                    ChildRel = <<DirRelSlash/binary, NameBin/binary>>,
                    ChildFs = <<FsDirSlash/binary, NameBin/binary>>,
                    list_one_dir_names(Rest, DirRelSlash, FsDirSlash, Cp, [{ChildRel, ChildFs, NameBin, Lower} | Acc])
            end;
        _ ->
            list_one_dir_names(Rest, DirRelSlash, FsDirSlash, Cp, Acc)
    end.

stat_candidates_chunk([], _CollectDirs, DirAcc, EntryAcc) ->
    {DirAcc, EntryAcc};
stat_candidates_chunk([{ChildRel, ChildFs, NameBin, Lower} | Rest], CollectDirs, DirAcc, EntryAcc) ->
    case prim_file:read_link_info(ChildFs, [{time, posix}]) of
        {ok, #file_info{type = directory, size = Size, mtime = Mtime}}
          when is_integer(Size), is_integer(Mtime) ->
            case CollectDirs of
                true ->
                    stat_candidates_chunk(Rest, CollectDirs, [ChildRel | DirAcc], EntryAcc);
                false ->
                    stat_candidates_chunk(Rest, CollectDirs, DirAcc, EntryAcc)
            end;
        {ok, #file_info{type = regular, links = 1, size = Size, mtime = Mtime}}
          when is_integer(Size), is_integer(Mtime) ->
            case allowed_tree_file_bin(ChildRel, NameBin, Lower) of
                true ->
                    stat_candidates_chunk(Rest, CollectDirs, DirAcc, [{entry, ChildRel, Size, Mtime, false} | EntryAcc]);
                false ->
                    stat_candidates_chunk(Rest, CollectDirs, DirAcc, EntryAcc)
            end;
        _ ->
            stat_candidates_chunk(Rest, CollectDirs, DirAcc, EntryAcc)
    end.

scan_raw_chunk(RawChunk, DirRelSlash, FsDirSlash, CollectDirs, Cp) ->
    Cands = list_one_dir_names(RawChunk, DirRelSlash, FsDirSlash, Cp, []),
    stat_candidates_chunk(Cands, CollectDirs, [], []).

walk_tree_async(_Root, _DirRel, Depth, _Cp) when Depth >= 16 ->
    [];
walk_tree_async(Root, DirRel, Depth, Cp) ->
    {DirRelSlash, FsDir, FsDirSlash} = case DirRel of
        <<>> -> {<<>>, Root, <<Root/binary, "/">>};
        _ ->
            Fs = <<Root/binary, "/", DirRel/binary>>,
            {<<DirRel/binary, "/">>, Fs, <<Fs/binary, "/">>}
    end,
    case prim_file:list_dir(FsDir) of
        {ok, RawNames} ->
            CollectDirs = (Depth + 1 < 16),
            ChunkSz = case Depth =< 1 of true -> 160; false -> 256 end,
            {SubRels, Entries} = case length(RawNames) > ChunkSz of
                false ->
                    scan_raw_chunk(RawNames, DirRelSlash, FsDirSlash, CollectDirs, Cp);
                true ->
                    Chunks = chunk_list(RawNames, ChunkSz),
                    Pairs = pmap(Chunks, fun(RCh) ->
                        scan_raw_chunk(RCh, DirRelSlash, FsDirSlash, CollectDirs, Cp)
                    end),
                    {DLs, ELs} = lists:unzip(Pairs),
                    {lists:append(DLs), lists:append(ELs)}
            end,
            Nested = case SubRels of
                [] ->
                    [];
                [SubRel] ->
                    walk_tree_async(Root, SubRel, Depth + 1, Cp);
                _ when Depth =< 1, length(SubRels) =< 32 ->
                    lists:append(pmap(SubRels, fun(SubRel) ->
                        walk_tree_async(Root, SubRel, Depth + 1, Cp)
                    end));
                _ when length(SubRels) > 16 ->
                    SubChunks = chunk_list(SubRels, (length(SubRels) + 5) div 6),
                    lists:append(pmap(SubChunks, fun(SCh) ->
                        lists:append([walk_tree_async(Root, SubRel, Depth + 1, Cp) || SubRel <- SCh])
                    end));
                _ ->
                    lists:append([walk_tree_async(Root, SubRel, Depth + 1, Cp) || SubRel <- SubRels])
            end,
            case Nested of
                [] -> Entries;
                _ -> lists:append(Entries, Nested)
            end;
        _ ->
            []
    end.

walk_trees_bfs(Root, TreeRels) ->
    Cp = markers_pattern(),
    lists:append(pmap(TreeRels, fun(T) -> walk_tree_async(Root, T, 0, Cp) end)).

count_buckets(Entries) ->
    count_buckets(Entries, 0, 0, 0, 0, 0, 0, 0, 0).

count_buckets([], T, W, Z, S, J, D, H, C) ->
    {T, W, Z, S, J, D, H, C};
count_buckets([E | Rest], T, W, Z, S, J, D, H, C) ->
    case element(2, E) of
        <<"docs/wiki/", _/binary>> -> count_buckets(Rest, T + 1, W + 1, Z, S, J, D, H, C);
        <<"docs/wiki">> -> count_buckets(Rest, T + 1, W + 1, Z, S, J, D, H, C);
        <<"docs/zk/", _/binary>> -> count_buckets(Rest, T + 1, W, Z + 1, S, J, D, H, C);
        <<"docs/zk">> -> count_buckets(Rest, T + 1, W, Z + 1, S, J, D, H, C);
        <<"docs/sop/", _/binary>> -> count_buckets(Rest, T + 1, W, Z, S + 1, J, D, H, C);
        <<"docs/sop">> -> count_buckets(Rest, T + 1, W, Z, S + 1, J, D, H, C);
        <<"docs/journal/", _/binary>> -> count_buckets(Rest, T + 1, W, Z, S, J + 1, D, H, C);
        <<"docs/journal">> -> count_buckets(Rest, T + 1, W, Z, S, J + 1, D, H, C);
        <<"docs/design/", _/binary>> -> count_buckets(Rest, T + 1, W, Z, S, J, D + 1, H, C);
        <<"docs/design">> -> count_buckets(Rest, T + 1, W, Z, S, J, D + 1, H, C);
        <<"docs/handover/", _/binary>> -> count_buckets(Rest, T + 1, W, Z, S, J, D, H + 1, C);
        <<"docs/handover">> -> count_buckets(Rest, T + 1, W, Z, S, J, D, H + 1, C);
        <<"contracts/", _/binary>> -> count_buckets(Rest, T + 1, W, Z, S, J, D, H, C + 1);
        <<"contracts">> -> count_buckets(Rest, T + 1, W, Z, S, J, D, H, C + 1);
        _ -> count_buckets(Rest, T + 1, W, Z, S, J, D, H, C)
    end.

is_url_clean_seg(<<>>) ->
    true;
is_url_clean_seg(<<C, Rest/binary>>)
  when (C >= $a andalso C =< $z) orelse
       (C >= $A andalso C =< $Z) orelse
       (C >= $0 andalso C =< $9) orelse
       C =:= $- orelse C =:= $_ orelse C =:= $. orelse C =:= $~ ->
    is_url_clean_seg(Rest);
is_url_clean_seg(_) ->
    false.

pct_encode_seg(Bin) ->
    case is_url_clean_seg(Bin) of
        true -> Bin;
        false -> uri_string:quote(Bin)
    end.

encode_url_path_bin(Path) ->
    case is_url_clean_path(Path) of
        true -> Path;
        false ->
            Parts = binary:split(Path, <<"/">>, [global]),
            iolist_to_binary(lists:join(<<"/">>, [pct_encode_seg(P) || P <- Parts]))
    end.

entry_json_iolist({entry, Path, Bytes, Mtime, _}) ->
    EncPath = encode_url_path_bin(Path),
    Url = <<"/files/", EncPath/binary>>,
    Route = case Path of
        <<"docs/wiki/", Name/binary>> -> [<<"/wiki/">>, pct_encode_seg(Name)];
        <<"docs/zk/", Name/binary>> -> [<<"/zk/">>, pct_encode_seg(Name)];
        _ -> Url
    end,
    [
        <<"{\"path\":">>, json:encode_binary(Path),
        <<",\"url\":">>, json:encode_binary(Url),
        <<",\"raw_url\":">>, json:encode_binary(<<Url/binary, "?raw=1">>),
        <<",\"tailscale_url\":">>, json:encode_binary(<<"http://nas-1.tail55d152.ts.net:4100", Url/binary>>),
        <<",\"document_url\":">>, json:encode_binary(iolist_to_binary([<<"http://nas-1.tail55d152.ts.net:4100">>, Route])),
        <<",\"bytes\":">>, integer_to_binary(Bytes),
        <<",\"mtime_seconds\":">>, integer_to_binary(Mtime),
        <<"}">>
    ].

encode_catalog_json(Root, {Total, Wiki, Zk, Sop, Journal, Design, Handover, Contracts}, PageEntries, TotalEntries, Limit, Offset, Truncated, _BaseUrl, _Unused) ->
    EntriesIo = lists:join(<<",">>, [entry_json_iolist(E) || E <- PageEntries]),
    TruncBin = case Truncated of true -> <<"true">>; false -> <<"false">> end,
    iolist_to_binary([
        <<"{\"wiki_count\":">>, integer_to_binary(Wiki),
        <<",\"zk_count\":">>, integer_to_binary(Zk),
        <<",\"sop_count\":">>, integer_to_binary(Sop),
        <<",\"journal_count\":">>, integer_to_binary(Journal),
        <<",\"design_count\":">>, integer_to_binary(Design),
        <<",\"handover_count\":">>, integer_to_binary(Handover),
        <<",\"contracts_count\":">>, integer_to_binary(Contracts),
        <<",\"workspace_root\":">>, json:encode_binary(Root),
        <<",\"total_allowlisted_files\":">>, integer_to_binary(Total),
        <<",\"entries\":[">>, EntriesIo, <<"]">>,
        <<",\"node_count\":">>, integer_to_binary(TotalEntries),
        <<",\"limit\":">>, integer_to_binary(Limit),
        <<",\"offset\":">>, integer_to_binary(Offset),
        <<",\"truncated\":">>, TruncBin,
        <<"}">>
    ]).

lstat_raw(Path) ->
    case prim_file:read_link_info(Path, [{time, posix}]) of
        {ok, #file_info{type = directory, size = Size, mtime = Mtime}}
          when is_integer(Size), is_integer(Mtime) ->
            {ok, {true, Size, Mtime}};
        {ok, #file_info{type = regular, links = 1, size = Size, mtime = Mtime}}
          when is_integer(Size), is_integer(Mtime) ->
            {ok, {false, Size, Mtime}};
        {ok, _} ->
            {error, 403};
        {error, enoent} ->
            {error, 404};
        {error, enotdir} ->
            {error, 403};
        _ ->
            {error, 403}
    end.

names(Path) ->
    case prim_file:list_dir(Path) of
        {ok, Names} -> lists:filtermap(fun(N) ->
            case to_utf8_bin(N) of
                {ok, B} -> {true, B};
                {true_bin, B} -> {true, B};
                error -> false
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
