%% Bounded reads for fixed client MCP registries. The Gleam caller owns the
%% fixed path and receives bytes only after the file has been read and checked.
-module(client_config_io).
-export([read_bounded/2]).
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
