-module(clock_guard_ffi).
-export([sample/0, parse/1, load_floor/1, store_floor/2]).

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
    ok -> case file:rename(Tmp, Path) of ok -> sync_dir(filename:dirname(Path)), {ok, nil}; {error, Why} -> {error, atom_to_binary(Why)} end;
    {error, Why} -> {error, atom_to_binary(Why)}
  end;
store_floor(_, _) -> {error, <<"invalid Lamport floor">>}.

sync_dir(Dir) ->
  case file:open(Dir, [read, raw]) of
    {ok, Fd} -> try file:sync(Fd) after file:close(Fd) end;
    _ -> ok
  end.
