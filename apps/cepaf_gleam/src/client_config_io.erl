%% Bounded reads for fixed client MCP registries. The Gleam caller owns the
%% fixed path and receives bytes only after the file has been read and checked.
-module(client_config_io).
-export([read_bounded/2, read_optional_bounded/2, agy_profile_path/1, agy_profile_root/1, cleanup_agy_profile/1]).
-include_lib("kernel/include/file.hrl").

read_bounded(Path, MaxBytes) ->
  try
    true = is_binary(Path) andalso byte_size(Path) > 0 andalso byte_size(Path) =< 4096,
    nomatch = binary:match(Path, <<0>>),
    absolute = filename:pathtype(binary_to_list(Path)),
    true = is_integer(MaxBytes) andalso MaxBytes > 0 andalso MaxBytes =< 262144,
    {ok, Before = #file_info{type = regular}} = file:read_link_info(Path),
    {ok, Fd} = file:open(Path, [read, raw, binary]),
    Bytes = try
      {ok, Opened} = file:read_file_info(Fd),
      true = stable(Before, Opened),
      regular = Opened#file_info.type,
      Data = read_all(Fd, MaxBytes, []),
      {ok, After} = file:read_file_info(Fd),
      {ok, Named} = file:read_link_info(Path),
      true = stable(Opened, After),
      true = stable(After, Named),
      true = byte_size(Data) =:= After#file_info.size,
      Data
    after
      ok = file:close(Fd)
    end,
    Utf8 = unicode:characters_to_binary(Bytes, utf8, utf8),
    true = is_binary(Utf8),
    {ok, Utf8}
  catch
    _:_ -> {error, <<"client_metadata_unavailable">>}
  end.

read_optional_bounded(Path, MaxBytes) ->
  case read_bounded(Path, MaxBytes) of
    {ok, Body} -> {ok, Body};
    {error, _} ->
      case file:read_link_info(Path) of
        {error, enoent} -> {ok, <<>>};
        _ -> {error, <<"client_metadata_unavailable">>}
      end
  end.

agy_profile_path(GrantId) ->
  try
    true = valid_component(GrantId),
    Runtime = os:getenv("XDG_RUNTIME_DIR"),
    true = lists:prefix("/run/user/", Runtime),
    {ok, #file_info{type = directory, uid = RuntimeUid, mode = RuntimeMode}} = file:read_link_info(Runtime),
    {RuntimeUid, []} = string:to_integer(filename:basename(Runtime)),
    true = (RuntimeMode band 8#777) =:= 8#700,
    Root = filename:join([Runtime, "uos-harness-client-profiles", "agy", GrantId]),
    {ok, unicode:characters_to_binary(Root)}
  catch
    _:_ -> {error, <<"agy_private_profile_path_unavailable">>}
  end.

%% Use a private per-grant profile. Only provider-auth references are linked;
%% global, project, and plugin MCP registries are not included.
agy_profile_root(GrantId) ->
  try
    true = valid_component(GrantId),
    Runtime = os:getenv("XDG_RUNTIME_DIR"),
    Home = os:getenv("HOME"),
    true = is_list(Runtime) andalso filename:pathtype(Runtime) =:= absolute,
    true = lists:prefix("/run/user/", Runtime),
    {ok, #file_info{type = directory, uid = RuntimeUid, mode = RuntimeMode}} = file:read_link_info(Runtime),
    {RuntimeUid, []} = string:to_integer(filename:basename(Runtime)),
    true = (RuntimeMode band 8#777) =:= 8#700,
    true = is_list(Home) andalso filename:pathtype(Home) =:= absolute,
    Root = filename:join([Runtime, "uos-harness-client-profiles", "agy", GrantId]),
    ensure_private_dir(filename:join(Runtime, "uos-harness-client-profiles"), RuntimeUid),
    ensure_private_dir(filename:join([Runtime, "uos-harness-client-profiles", "agy"]), RuntimeUid),
    ensure_private_dir(Root, RuntimeUid),
    Gemini = filename:join(Root, ".gemini"),
    Config = filename:join([Root, ".gemini", "config"]),
    ensure_private_dir(Gemini, RuntimeUid),
    ensure_private_dir(Config, RuntimeUid),
    SourceGemini = filename:join(Home, ".gemini"),
    ensure_auth_reference(filename:join(SourceGemini, "oauth_creds.json"), filename:join(Gemini, "oauth_creds.json"), RuntimeUid),
    ensure_auth_reference(filename:join(SourceGemini, "google_accounts.json"), filename:join(Gemini, "google_accounts.json"), RuntimeUid),
    {ok, unicode:characters_to_binary(Root)}
  catch
    _:_ -> {error, <<"agy_private_profile_unavailable">>}
  end.

cleanup_agy_profile(GrantId) ->
  try
    true = valid_component(GrantId),
    Runtime = os:getenv("XDG_RUNTIME_DIR"),
    true = lists:prefix("/run/user/", Runtime),
    {ok, #file_info{type = directory, uid = RuntimeUid, mode = RuntimeMode}} = file:read_link_info(Runtime),
    {RuntimeUid, []} = string:to_integer(filename:basename(Runtime)),
    true = (RuntimeMode band 8#777) =:= 8#700,
    Root = filename:join([Runtime, "uos-harness-client-profiles", "agy", GrantId]),
    {ok, #file_info{type = directory, uid = RuntimeUid, mode = RootMode}} = file:read_link_info(Root),
    true = (RootMode band 8#777) =:= 8#700,
    {_, _, _} = remove_private_tree(Root, RuntimeUid, 0, 0, 0),
    {ok, nil}
  catch
    _:_ -> {error, <<"agy_private_profile_cleanup_failed">>}
  end.

valid_component(Text) when is_binary(Text), byte_size(Text) > 0, byte_size(Text) =< 48 ->
  lists:all(fun(C) ->
    (C >= $a andalso C =< $z) orelse (C >= $0 andalso C =< $9) orelse C =:= $-
  end, binary_to_list(Text));
valid_component(_) -> false.

ensure_private_dir(Path, Owner) ->
  case file:read_link_info(Path) of
    {ok, #file_info{type = directory, uid = Owner, mode = Mode}} ->
      true = (Mode band 8#777) =:= 8#700,
      ok;
    {error, enoent} ->
      ok = file:make_dir(Path),
      ok = file:change_mode(Path, 8#700),
      {ok, #file_info{type = directory, uid = Owner, mode = Mode}} = file:read_link_info(Path),
      true = (Mode band 8#777) =:= 8#700,
      ok;
    _ -> error(private_directory_conflict)
  end.

ensure_auth_reference(Source, Target, Owner) ->
  {ok, #file_info{type = regular, uid = Owner}} = file:read_link_info(Source),
  case file:read_link_info(Target) of
    {error, enoent} -> ok = file:make_symlink(Source, Target);
    {ok, #file_info{type = symlink}} ->
      {ok, Source} = file:read_link(Target);
    _ -> error(auth_reference_conflict)
  end,
  {ok, #file_info{type = symlink, uid = Owner}} = file:read_link_info(Target),
  {ok, Source} = file:read_link(Target),
  ok.

remove_private_tree(Path, Owner, Depth, Count, Bytes) ->
  true = Depth =< 8,
  true = Count < 1024,
  {ok, Info} = file:read_link_info(Path),
  case Info#file_info.type of
    directory ->
      true = Info#file_info.uid =:= Owner,
      true = (Info#file_info.mode band 8#777) =:= 8#700,
      {ok, Names} = file:list_dir(Path),
      true = length(Names) =< 256,
      {C1, B1} = lists:foldl(fun(Name, {C, B}) ->
        {C2, B2, _} = remove_private_tree(filename:join(Path, Name), Owner, Depth + 1, C, B),
        {C2, B2}
      end, {Count + 1, Bytes}, Names),
      ok = file:del_dir(Path),
      {C1, B1, ok};
    regular ->
      true = Info#file_info.uid =:= Owner,
      true = Bytes + Info#file_info.size =< 67108864,
      ok = file:delete(Path),
      {Count + 1, Bytes + Info#file_info.size, ok};
    symlink ->
      ok = file:delete(Path),
      {Count + 1, Bytes, ok};
    _ -> error(private_profile_entry_type)
  end.

identity(I) ->
  {I#file_info.type, I#file_info.inode, I#file_info.major_device, I#file_info.minor_device}.

stable(A, B) ->
  identity(A) =:= identity(B) andalso A#file_info.size =:= B#file_info.size
    andalso A#file_info.mtime =:= B#file_info.mtime.

read_all(Fd, Left, Acc) ->
  case file:read(Fd, min(65536, Left + 1)) of
    eof -> iolist_to_binary(lists:reverse(Acc));
    {ok, Part} ->
      true = byte_size(Part) =< Left,
      read_all(Fd, Left - byte_size(Part), [Part | Acc]);
    _ -> error(read_failed)
  end.
