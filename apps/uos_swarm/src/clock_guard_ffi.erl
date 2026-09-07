-module(clock_guard_ffi).
-export([sample/0, parse/1, load_floor/1, store_floor/2, fetch/4,
         sync_directory/1, halt_failure/0]).

fetch(Url, MaxBytes, TimeoutMs, Projection) ->
  try
    true = is_binary(Url) andalso byte_size(Url) > 0 andalso byte_size(Url) =< 2048,
    true = printable_ascii(Url),
    true = is_integer(MaxBytes) andalso MaxBytes > 0 andalso MaxBytes =< 16777216,
    true = is_integer(TimeoutMs) andalso TimeoutMs >= 100 andalso TimeoutMs =< 10000,
    true = safe_projection(Projection),
    Uri = uri_string:parse(Url),
    <<"http">> = maps:get(scheme, Uri),
    false = maps:is_key(userinfo, Uri),
    false = maps:is_key(fragment, Uri),
    Host = string:lowercase(unicode:characters_to_binary(maps:get(host, Uri))),
    true = allowed_host(Host),
    Curl = os:find_executable("curl"),
    true = (Curl =/= false),
    Timeout = io_lib:format("~.3f", [TimeoutMs / 1000]),
    ConnectTimeout = io_lib:format("~.3f", [min(TimeoutMs, 2000) / 1000]),
    Marker = <<"\nUOS_CLOCK_GUARD_META\t">>,
    WriteOut = binary_to_list(<<Marker/binary, "%{http_code}\t%{content_type}\t%{size_download}">>),
    Args = ["-q", "--silent", "--show-error", "--noproxy", "*", "--proto", "=http", "--max-redirs", "0",
      "--max-time", lists:flatten(Timeout), "--connect-timeout", lists:flatten(ConnectTimeout),
      "--max-filesize", integer_to_list(MaxBytes), "--header", "Accept: application/json",
      "--write-out", WriteOut, binary_to_list(Url)],
    Port = open_port({spawn_executable, Curl}, [binary, exit_status, stderr_to_stdout, {args, Args}]),
    case collect_fetch(Port, <<>>, MaxBytes + 1024, TimeoutMs + 500) of
      {ok, 0, Output} -> parse_fetch(Output, Marker, MaxBytes, Projection);
      {ok, 63, _} -> {error, <<"board response exceeds bound">>};
      {ok, 28, _} -> {error, <<"board fetch timeout">>};
      {ok, 6, _} -> {error, <<"board host resolution failed">>};
      {ok, 7, _} -> {error, <<"board connection failed">>};
      {ok, _, _} -> {error, <<"board fetch failed">>};
      {error, Why} -> {error, Why}
    end
  catch _:_ -> {error, <<"board URL or fetch configuration rejected">>} end.

collect_fetch(Port, Acc, Limit, TimeoutMs) ->
  receive
    {Port, {data, Bin}} when byte_size(Acc) + byte_size(Bin) =< Limit ->
      collect_fetch(Port, <<Acc/binary, Bin/binary>>, Limit, TimeoutMs);
    {Port, {data, _}} ->
      port_close(Port), {error, <<"board response exceeds bound">>};
    {Port, {exit_status, Status}} -> {ok, Status, Acc}
  after TimeoutMs ->
    port_close(Port), {error, <<"board fetch timeout">>}
  end.

parse_fetch(Output, Marker, MaxBytes, Projection) ->
  case binary:matches(Output, Marker) of
    [] -> {error, <<"board fetch response metadata missing">>};
    Matches ->
      {Position, MarkerSize} = lists:last(Matches),
      Body = binary:part(Output, 0, Position),
      Meta = binary:part(Output, Position + MarkerSize,
        byte_size(Output) - Position - MarkerSize),
      case binary:split(Meta, <<"\t">>, [global]) of
        [<<"200">>, ContentType, SizeText] ->
          try
            Size = trunc(binary_to_float_or_integer(SizeText)),
            true = Size =:= byte_size(Body) andalso Size =< MaxBytes,
            true = json_content_type(ContentType),
            case store_projection(Projection, Body) of
              ok -> {ok, Body};
              {error, Why} -> {error, Why}
            end
          catch _:_ -> {error, <<"board response metadata invalid">>} end;
        [Code, _, _] ->
          case valid_status(Code) of
            true -> {error, <<"board http status ", Code/binary>>};
            false -> {error, <<"board response metadata invalid">>}
          end;
        _ -> {error, <<"board response metadata invalid">>}
      end
  end.

binary_to_float_or_integer(Value) ->
  try binary_to_float(Value) catch error:badarg -> float(binary_to_integer(Value)) end.

valid_status(<<A, B, C>>) ->
  A >= $0 andalso A =< $9 andalso B >= $0 andalso B =< $9
    andalso C >= $0 andalso C =< $9;
valid_status(_) -> false.

json_content_type(ContentType0) ->
  ContentType = string:lowercase(ContentType0),
  Base = hd(binary:split(ContentType, <<";">>)),
  Base =:= <<"application/json">> orelse
    (byte_size(Base) > 5 andalso binary:part(Base, byte_size(Base) - 5, 5) =:= <<"+json">>).

printable_ascii(<<>>) -> true;
printable_ascii(<<C, Rest/binary>>) when C >= 32, C =< 126 -> printable_ascii(Rest);
printable_ascii(_) -> false.

safe_projection(Path) ->
  is_binary(Path) andalso byte_size(Path) > 0 andalso byte_size(Path) =< 4096
    andalso filename:pathtype(Path) =:= absolute.

allowed_host(<<"localhost">>) -> true;
allowed_host(<<"127.0.0.1">>) -> true;
allowed_host(<<"::1">>) -> true;
allowed_host(Host) ->
  Size = byte_size(Host), Suffix = <<".ts.net">>, S = byte_size(Suffix),
  Size > S andalso binary:part(Host, Size - S, S) =:= Suffix.

store_projection(Path, Body) ->
  Tmp = <<Path/binary, ".pending">>,
  case file:write_file(Tmp, Body, [sync]) of
    ok -> case file:rename(Tmp, Path) of
      ok -> sync_dir(filename:dirname(Path));
      {error, Why} -> {error, durability_error(<<"projection rename">>, Why)}
    end;
    {error, Why} -> {error, durability_error(<<"projection write">>, Why)}
  end.

sample() ->
  try
    {ok, Host} = inet:gethostname(),
    {ok, Boot0} = file:read_file(<<"/proc/sys/kernel/random/boot_id">>),
    {ok, Up0} = file:read_file(<<"/proc/uptime">>),
    Boot = string:trim(Boot0),
    [Up | _] = binary:split(Up0, <<" ">>, [global]),
    BootUs = trunc(binary_to_float(Up) * 1000000),
    UtcUs = erlang:system_time(microsecond),
    Domain = {domain, unicode:characters_to_binary(Host), Boot},
    Reading = {reading, Domain, UtcUs, BootUs},
    case chrony() of
      {ok, {ReferenceUtcUs, Offset, Uncertainty, Source}} ->
        Age = max(0, UtcUs - ReferenceUtcUs),
        ReferenceBootUs = max(0, BootUs - Age),
        Reference = {reading, Domain, ReferenceUtcUs, ReferenceBootUs},
        {ok, {sample, {evidence, Reference, Source, true, Offset, Uncertainty, 0}, Reading}};
      {error, Why} -> {error, Why}
    end
  catch _:SampleError -> {error, iolist_to_binary(io_lib:format("clock sample failed: ~p", [SampleError]))}
  end.

chrony() ->
  case os:find_executable("chronyc") of
    false -> {error, <<"chronyc unavailable; synchronization unknown">>};
    Exe ->
      Port = open_port({spawn_executable, Exe}, [binary, exit_status, stderr_to_stdout, {args, ["-c", "tracking"]}]),
      collect(Port, <<>>, 8192)
  end.

collect(Port, Acc, Limit) ->
  receive
    {Port, {data, Bin}} when byte_size(Acc) + byte_size(Bin) =< Limit -> collect(Port, <<Acc/binary, Bin/binary>>, Limit);
    {Port, {data, _}} -> port_close(Port), {error, <<"chronyc output exceeded bound">>};
    {Port, {exit_status, 0}} -> parse(Acc);
    {Port, {exit_status, _}} -> {error, <<"chronyc reported unsynchronized or failed">>}
  after 2000 -> port_close(Port), {error, <<"chronyc timeout">>}
  end.

parse(Bin) ->
  Fields = binary:split(string:trim(Bin), <<",">>, [global]),
  try
    true = (length(Fields) =:= 14),
    %% reference UTC 4; system offset 5; root delay 11; dispersion 12; leap 14.
    Leap = lists:nth(14, Fields),
    true = (Leap =:= <<"Normal">>),
    RefUtc = trunc(binary_to_float(lists:nth(4, Fields)) * 1000000),
    Offset = round(binary_to_float(lists:nth(5, Fields)) * 1000000),
    RootDelay = abs(binary_to_float(lists:nth(11, Fields))),
    Disp = abs(binary_to_float(lists:nth(12, Fields))),
    Uncertainty = ceil((RootDelay / 2 + Disp) * 1000000),
    {ok, {RefUtc, Offset, Uncertainty, <<"chronyc:-c-tracking:reference-utc">>}}
  catch _:_ -> {error, <<"chronyc tracking format invalid or unsynchronized">>}
  end.

load_floor(Path) ->
  case file:read_file(Path) of
    {ok, Bin} -> try {ok, binary_to_integer(string:trim(Bin))} catch _:_ -> {error, <<"invalid durable Lamport floor">>} end;
    {error, enoent} -> {ok, 0};
    {error, Why} -> {error, atom_to_binary(Why)}
  end.

store_floor(Path, Floor) when is_integer(Floor), Floor >= 0 ->
  Tmp = <<Path/binary, ".pending">>,
  case file:write_file(Tmp, integer_to_binary(Floor), [sync]) of
    ok -> case file:rename(Tmp, Path) of
      ok -> case sync_dir(filename:dirname(Path)) of
        ok -> {ok, nil};
        {error, Why} -> {error, Why}
      end;
      {error, Why} -> {error, durability_error(<<"floor rename">>, Why)}
    end;
    {error, Why} -> {error, durability_error(<<"floor write">>, Why)}
  end;
store_floor(_, _) -> {error, <<"invalid Lamport floor">>}.

sync_dir(Dir) ->
  case file:open(Dir, [read, raw, directory]) of
    {ok, Fd} ->
      Synced = file:sync(Fd),
      Closed = file:close(Fd),
      case {Synced, Closed} of
        {ok, ok} -> ok;
        {{error, Why}, _} -> {error, durability_error(<<"directory sync">>, Why)};
        {_, {error, Why}} -> {error, durability_error(<<"directory close">>, Why)}
      end;
    {error, Why} -> {error, durability_error(<<"directory open">>, Why)}
  end.

sync_directory(Path) when is_binary(Path) ->
  case sync_dir(Path) of ok -> {ok, nil}; {error, Why} -> {error, Why} end;
sync_directory(_) -> {error, <<"invalid directory path">>}.

durability_error(Operation, Why) ->
  <<Operation/binary, " failed: ", (atom_to_binary(Why))/binary>>.

halt_failure() -> erlang:halt(1).
