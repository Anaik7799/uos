-module(mcp_stdio_ffi).
-export([read_line/0, with_gateway_boot_lock/1, register_or_stop_supervisor/1,
         loaded_mcp_beams_digest/0, run_workspace_bounded_cd/4]).

-include_lib("kernel/include/file.hrl").

-define(MAX_LINE_BYTES, 1048576).
-define(OUTPUT_LIMIT, 1048576).

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

with_gateway_boot_lock(Fun) ->
    global:trans({uos_mcp_runtime_gateway_boot_lock, self()}, fun() -> Fun() end).

register_or_stop_supervisor(Pid) ->
    case erlang:whereis(uos_mcp_runtime_gateway_sup) of
        Pid -> true;
        Existing when is_pid(Existing), Existing =/= Pid ->
            case erlang:is_process_alive(Existing) of
                true ->
                    try erlang:unlink(Pid) catch _:_ -> ok end,
                    try gen_server:stop(Pid, shutdown, 1000) catch _:_ -> ok end,
                    try exit(Pid, shutdown) catch _:_ -> ok end,
                    false;
                false -> register_supervisor(Pid)
            end;
        _ -> register_supervisor(Pid)
    end.

register_supervisor(Pid) ->
    try
        erlang:register(uos_mcp_runtime_gateway_sup, Pid),
        true
    catch
        error:badarg ->
            try erlang:unlink(Pid) catch _:_ -> ok end,
            try exit(Pid, shutdown) catch _:_ -> ok end,
            false
    end.

%% The executable/guardian belong to the loaded capsule, while the child cwd
%% belongs to the caller's workspace (or an isolated absolute test directory).
%% This adapter is internal to the gateway; it grants no tool/effect authority.
run_workspace_bounded_cd(Path, Args, Cwd, TimeoutMs)
  when is_binary(Path), is_list(Args), is_binary(Cwd),
       is_integer(TimeoutMs), TimeoutMs > 0, TimeoutMs =< 60000 ->
    try
        CwdList = utf8_chars(Cwd),
        absolute = filename:pathtype(CwdList),
        Parts = filename:split(CwdList),
        false = lists:member("..", Parts),
        RealCwd = filename:join(Parts),
        true = filelib:is_dir(RealCwd),
        CapRoot = utf8_chars(ecology_capability_ffi:uos_root()),
        Ocaml = workspace_ocaml(CapRoot),
        Guardian = filename:join(CapRoot, "tools/ecology_process.ml"),
        true = filelib:is_regular(Guardian),
        A = ["-I", "+unix", Guardian, integer_to_list(TimeoutMs),
             integer_to_list(?OUTPUT_LIMIT), "merged", utf8_chars(Path)] ++
            [utf8_chars(Argument) || Argument <- Args],
        Port = erlang:open_port({spawn_executable, Ocaml},
          [stream, use_stdio, exit_status, binary, {args, A}, {cd, RealCwd}]),
        collect_workspace(Port,
          erlang:monotonic_time(millisecond) + TimeoutMs + 1000, 0, [])
    catch
        _:_ -> {error, <<"backend_spawn_failed">>}
    end;
run_workspace_bounded_cd(_, _, _, _) -> {error, <<"invalid_resource_bound">>}.

utf8_chars(Bytes) when is_binary(Bytes) ->
    case unicode:characters_to_list(Bytes, utf8) of
        Chars when is_list(Chars) -> Chars;
        _ -> error(invalid_utf8)
    end.

workspace_ocaml(CapRoot) ->
    Manifest = filename:join(CapRoot, "runtime-dependencies.json"),
    case filelib:is_regular(Manifest) of
        false -> filename:join(CapRoot, "toolchains/opam-ocaml/bin/ocaml");
        true ->
            {ok, #file_info{type = regular, size = N}} = file:read_file_info(Manifest),
            true = N =< 65536,
            {ok, Body} = file:read_file(Manifest),
            #{<<"ocaml">> := #{<<"path">> := Path, <<"sha256">> := Expected}} =
                json:decode(Body),
            Ocaml = utf8_chars(Path),
            absolute = filename:pathtype(Ocaml),
            {ok, #file_info{type = regular, size = Size}} = file:read_file_info(Ocaml),
            true = Size =< 134217728,
            {ok, Fd} = file:open(Ocaml, [read, binary, raw]),
            Actual = try hash_workspace_dependency(Fd, crypto:hash_init(sha256), Size)
                     after file:close(Fd) end,
            true = Actual =:= Expected,
            Ocaml
    end.

hash_workspace_dependency(Fd, Hash, Remaining) ->
    case file:read(Fd, 65536) of
        eof when Remaining =:= 0 ->
            binary:encode_hex(crypto:hash_final(Hash), lowercase);
        {ok, Bytes} when byte_size(Bytes) =< Remaining ->
            hash_workspace_dependency(Fd,
              crypto:hash_update(Hash, Bytes), Remaining - byte_size(Bytes));
        _ -> error(dependency_changed)
    end.

collect_workspace(Port, Deadline, Size, Chunks) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Chunk}} ->
            case Size + byte_size(Chunk) =< ?OUTPUT_LIMIT of
                true -> collect_workspace(Port, Deadline,
                          Size + byte_size(Chunk), [Chunk | Chunks]);
                false ->
                    try erlang:port_close(Port) catch _:_ -> ok end,
                    {error, <<"output_limit">>}
            end;
        {Port, {exit_status, 124}} -> {error, <<"timeout">>};
        {Port, {exit_status, 125}} -> {error, <<"backend_output_or_process_failure">>};
        {Port, {exit_status, Code}} ->
            {ok, {Code, iolist_to_binary(lists:reverse(Chunks))}}
    after Remaining ->
        try erlang:port_close(Port) catch _:_ -> ok end,
        {error, <<"guardian_timeout">>}
    end.

loaded_mcp_beams_digest() ->
    Modules = [cepaf_gleam@mcp@registry, cepaf_gleam@mcp@admission,
               cepaf_gleam@mcp@receipts, cepaf_gleam@mcp@dispatch,
               cepaf_gleam@mcp@route_convergence, cepaf_gleam@mcp@server,
               cepaf_gleam@mcp@runtime_gateway],
    try
        Acc = lists:foldl(fun(Mod, Bytes) ->
            {module, Mod} = code:ensure_loaded(Mod),
            {file, _} = code:is_loaded(Mod),
            Md5 = Mod:module_info(md5),
            true = is_binary(Md5) andalso byte_size(Md5) =:= 16,
            Name = atom_to_binary(Mod, utf8),
            <<Bytes/binary, (byte_size(Name)):32/unsigned-big, Name/binary,
              (byte_size(Md5)):32/unsigned-big, Md5/binary>>
        end, <<>>, Modules),
        binary:encode_hex(crypto:hash(sha256, Acc), lowercase)
    catch
        _:_ -> <<"unobserved">>
    end.
