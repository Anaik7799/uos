-module(cepaf_gleam_ffi).

-export([hackney_request/5, hackney_http_request/4, get_uid/0, sha256/1, sqrt/1, get_arguments/0]).
-export([system_time_nanos/0]).
-export([sqlite_open/1, sqlite_exec/2, sqlite_q/3, sqlite_close/1]).
-export([podman_uds_request/4]).
-export([duckdb_open/1, duckdb_connection/1, duckdb_query/2, duckdb_execute/2, duckdb_ensure_schema/1, duckdb_fetch_all/1, duckdb_columns/1]).
-export([zenoh_open/1, zenoh_put/3, zenoh_get/2, zenoh_subscribe/3, try_load_zenoh_nif/0]).
-export([file_read/1, file_write/2, file_rename/2, file_mtime_http/1]).
-export([generate_id/0, os_cmd/1, identity/1]).
-export([to_string/1, to_int/1, to_float/1, to_bool/1]).
-export([system_time_seconds/0, base64_decode/1, url_encode/1, get_env/1]).
-export([pi_port_open/3, pi_port_send/2, pi_port_close/1]).

%% @doc Execute a REST request over Podman Unix Domain Socket
podman_uds_request(Path, Method, Endpoint, Body) ->
    case gen_tcp:connect({local, binary_to_list(Path)}, 0, [binary, {active, false}, {packet, raw}]) of
        {ok, Socket} ->
            Request = list_to_binary([
                Method, " ", Endpoint, " HTTP/1.1\r\n",
                "Host: localhost\r\n",
                "Content-Length: ", integer_to_list(byte_size(Body)), "\r\n",
                "\r\n",
                Body
            ]),
            gen_tcp:send(Socket, Request),
            case gen_tcp:recv(Socket, 0, 5000) of
                {ok, Response} ->
                    gen_tcp:close(Socket),
                    {ok, Response};
                {error, Reason} ->
                    gen_tcp:close(Socket),
                    {error, list_to_binary(atom_to_list(Reason))}
            end;
        {error, Reason} ->
            {error, list_to_binary(atom_to_list(Reason))}
    end.

identity(X) -> X.

to_string(X) when is_binary(X) -> {ok, X};
to_string(_) -> {error, nil}.

to_int(X) when is_integer(X) -> {ok, X};
to_int(_) -> {error, nil}.

to_float(X) when is_float(X) -> {ok, X};
to_float(_) -> {error, nil}.

to_bool(X) when is_boolean(X) -> {ok, X};
to_bool(_) -> {error, nil}.

sqrt(X) when is_number(X), X >= 0 ->
    {ok, math:sqrt(X)};
sqrt(_X) ->
    {error, <<"Domain error: sqrt requires non-negative input">>}.

%% Use unicode-safe conversions for os_cmd
os_cmd(CmdBinary) ->
    try
        Cmd = unicode:characters_to_list(CmdBinary),
        Result = os:cmd(Cmd),
        {ok, unicode:characters_to_binary(Result)}
    catch
        _:Reason ->
            {error, unicode:characters_to_binary(io_lib:format("os_cmd error: ~p", [Reason]))}
    end.

file_rename(Old, New) ->
    case file:rename(Old, New) of
        ok -> {ok, nil};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

%% DuckDB FFI via Duckdbex
duckdb_open(Path) ->
    try 'Elixir.Duckdbex':open(Path)
    catch error:undef -> {error, <<"duckdbex_not_available">>} end.

duckdb_connection(Db) ->
    try 'Elixir.Duckdbex':connection(Db)
    catch error:undef -> {error, <<"duckdbex_not_available">>} end.

duckdb_query(Conn, Sql) ->
    try 'Elixir.Duckdbex':query(Conn, Sql)
    catch error:undef -> {error, <<"duckdbex_not_available">>} end.

duckdb_execute(Conn, Sql) ->
    try 'Elixir.Duckdbex':query(Conn, Sql)
    catch error:undef -> {error, <<"duckdbex_not_available">>} end.

duckdb_ensure_schema(_Schema) ->
    {ok, nil}.

duckdb_fetch_all(Result) ->
    try
        Rows = 'Elixir.Duckdbex':fetch_all(Result),
        {ok, [case Row of T when is_tuple(T) -> tuple_to_list(T); L when is_list(L) -> L end || Row <- Rows]}
    catch error:undef -> {error, <<"duckdbex_not_available">>} end.

duckdb_columns(Result) ->
    try {ok, 'Elixir.Duckdbex':columns(Result)}
    catch error:undef -> {error, <<"duckdbex_not_available">>} end.


sha256(Data) ->
    Hash = crypto:hash(sha256, Data),
    binary:encode_hex(Hash).

generate_id() ->
    Now = erlang:system_time(millisecond),
    Random = crypto:strong_rand_bytes(10),
    RandHex = binary:encode_hex(Random),
    list_to_binary(integer_to_list(Now) ++ binary_to_list(RandHex)).

hackney_request(Method, Url, Headers, Body, SocketPath) ->
    try
        case application:ensure_all_started(hackney) of
            {ok, _} ->
                L_SocketPath = case is_binary(SocketPath) of
                    true -> binary_to_list(SocketPath);
                    false -> SocketPath
                end,
                L_Url = case is_binary(Url) of
                    true -> binary_to_list(Url);
                    false -> Url
                end,
                L_Method = case Method of
                    get -> get;
                    post -> post;
                    put -> put;
                    delete -> delete;
                    _ -> Method
                end,
                L_Headers = [ {case is_binary(K) of true -> binary_to_list(K); _ -> K end, 
                               case is_binary(V) of true -> binary_to_list(V); _ -> V end} 
                             || {K, V} <- Headers ],
                Options = [
                    {connect_timeout, 5000},
                    {recv_timeout, 30000},
                    {connect_options, [{local_socket, L_SocketPath}]}
                ],
                case hackney:request(L_Method, L_Url, L_Headers, Body, Options) of
                    {ok, StatusCode, RespHeaders, ClientRef} ->
                        case hackney:body(ClientRef) of
                            {ok, RespBody} ->
                                {ok, {StatusCode, RespHeaders, RespBody}};
                            {error, BodyReason} ->
                                {error, unicode:characters_to_binary(io_lib:format("body_error: ~p", [BodyReason]))}
                        end;
                    {error, ReqReason} ->
                        {error, unicode:characters_to_binary(io_lib:format("req_error: ~p method: ~p url: ~p socket: ~p", [ReqReason, L_Method, Url, L_SocketPath]))}
                end;
            {error, AppReason} ->
                {error, unicode:characters_to_binary(io_lib:format("hackney_start_failed: ~p", [AppReason]))}
        end
    catch
        _:CatchReason ->
            {error, unicode:characters_to_binary(io_lib:format("hackney_request crash: ~p", [CatchReason]))}
    end.

hackney_http_request(Method, Url, Headers, Body) ->
    try
        case code:ensure_loaded(hackney) of
            {module, hackney} ->
                case application:ensure_all_started(hackney) of
                    {ok, _} ->
                        L_Method = case Method of
                            get -> get;
                            post -> post;
                            put -> put;
                            delete -> delete;
                            _ -> Method
                        end,
                        L_Url = case is_binary(Url) of
                            true -> binary_to_list(Url);
                            false -> Url
                        end,
                        L_Headers = [ {case is_binary(K) of true -> binary_to_list(K); _ -> K end, 
                                       case is_binary(V) of true -> binary_to_list(V); _ -> V end} 
                                     || {K, V} <- Headers ],
                        Options = [
                            {connect_timeout, 5000},
                            {recv_timeout, 10000},
                            {pool, default}
                        ],
                        case hackney:request(L_Method, L_Url, L_Headers, Body, Options) of
                            {ok, StatusCode, RespHeaders, ClientRef} ->
                                case hackney:body(ClientRef) of
                                    {ok, RespBody} ->
                                        {ok, {StatusCode, RespHeaders, RespBody}};
                                    {error, BodyReason} ->
                                        {error, unicode:characters_to_binary(io_lib:format("~p", [BodyReason]))}
                                end;
                            {error, ReqReason} ->
                                {error, unicode:characters_to_binary(io_lib:format("~p", [ReqReason]))}
                        end;
                    {error, AppReason} ->
                        {error, unicode:characters_to_binary(io_lib:format("hackney_start_failed: ~p", [AppReason]))}
                end;
            _ ->
                {error, <<"hackney_module_not_found">>}
        end
    catch
        error:undef -> {error, <<"hackney_not_available_undef">>};
        _:CatchReason ->
            {error, unicode:characters_to_binary(io_lib:format("hackney_http_request crash: ~p", [CatchReason]))}
    end.

system_time_nanos() ->
    erlang:system_time(nanosecond).

get_uid() ->
    Raw = case os:getenv("UID") of
        false -> os:cmd("id -u");
        Val -> Val
    end,
    case unicode:characters_to_binary(string:trim(Raw)) of
        Bin when is_binary(Bin) -> Bin;
        _ -> <<"1000">>
    end.

get_arguments() ->
    Args = init:get_plain_arguments(),
    [case unicode:characters_to_binary(A) of
        B when is_binary(B) -> B;
        _ -> list_to_binary(A)
     end || A <- Args].

sqlite_open(PathBinary) ->
    try
        Path = unicode:characters_to_list(PathBinary),
        case esqlite3:open(Path) of
            {ok, Conn} -> {ok, Conn};
            {error, Reason} -> 
                {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
        end
    catch
        _:CatchReason ->
            {error, unicode:characters_to_binary(io_lib:format("sqlite_open crash: ~p", [CatchReason]))}
    end.

sqlite_exec(Conn, Sql) ->
    try
        case esqlite3:exec(Conn, Sql) of
            ok -> {ok, 0};
            {ok, Rows} -> {ok, length(Rows)};
            {error, Reason} -> 
                {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
        end
    catch
        _:CatchReason ->
            {error, unicode:characters_to_binary(io_lib:format("sqlite_exec crash: ~p", [CatchReason]))}
    end.

sqlite_q(Conn, Sql, Params) ->
    try
        case esqlite3:q(Conn, Sql, Params) of
            Rows when is_list(Rows) -> 
                {ok, [case Row of T when is_tuple(T) -> tuple_to_list(T); L when is_list(L) -> L end || Row <- Rows]};
            {error, Reason} -> 
                {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
        end
    catch
        _:CatchReason ->
            {error, unicode:characters_to_binary(io_lib:format("sqlite_q crash: ~p", [CatchReason]))}
    end.

sqlite_close(Conn) ->
    try esqlite3:close(Conn)
    catch _:_ -> ok end.

%% Zenoh NIF — dual-path loading:
%%   Path 1: Elixir Rustler module (when running inside Mix/OTP app)
%%   Path 2: Direct erlang:load_nif (when running standalone via gleam run)
%%
%% The NIF exports functions prefixed with zenoh_ that match the Rustler-generated names.
%% SC-ZENOH-001: Zenoh NIF MUST be loaded on ALL nodes.

try_load_zenoh_nif() ->
    %% Try Elixir module first (Mix app context)
    case code:ensure_loaded('Elixir.Indrajaal.Native.Zenoh') of
        {module, _} -> {ok, <<"elixir_rustler_loaded">>};
        _ ->
            %% Fallback: load NIF directly into this module
            NifPath = case filelib:is_file("/home/an/dev/ver/c3i/sub-projects/c3i/priv/native/zenoh_nif.so") of
                true -> "/home/an/dev/ver/c3i/sub-projects/c3i/priv/native/zenoh_nif";
                false -> "/home/an/dev/ver/c3i/sub-projects/c3i/target/debug/libzenoh_nif"
            end,
            case erlang:load_nif(NifPath, 0) of
                ok -> {ok, <<"direct_nif_loaded">>};
                {error, {reload, _}} -> {ok, <<"nif_already_loaded">>};
                {error, Reason} -> {error, unicode:characters_to_binary(io_lib:format("nif_load_failed: ~p", [Reason]))}
            end
    end.

%% Internal: resolve which module has the NIF functions
%% Returns the module atom to call, or 'none' if unavailable
zenoh_module() ->
    case code:ensure_loaded('Elixir.Indrajaal.Native.Zenoh') of
        {module, _} -> 'Elixir.Indrajaal.Native.Zenoh';
        _ ->
            %% When NIF is loaded directly into this module, the functions
            %% are available as cepaf_gleam_ffi:zenoh_open_session etc.
            %% But Rustler NIF names are prefixed, so we try the Elixir module first.
            %% If not available, return none — caller handles gracefully.
            none
    end.

zenoh_open(ConfigJson) ->
    try
        case zenoh_module() of
            none ->
                %% Try direct NIF call (if loaded into this module)
                %% Rustler generates 'Elixir.Module':function_name, not direct calls.
                %% Without the Elixir module, we simulate a session for standalone mode.
                try_load_zenoh_nif(),
                case code:ensure_loaded('Elixir.Indrajaal.Native.Zenoh') of
                    {module, _} ->
                        case 'Elixir.Indrajaal.Native.Zenoh':open_session(ConfigJson) of
                            {ok, Session} -> {ok, Session};
                            {error, Reason} -> {error, Reason}
                        end;
                    _ -> {error, <<"zenoh_nif_not_available_standalone">>}
                end;
            Mod ->
                case Mod:open_session(ConfigJson) of
                    {ok, Session} -> {ok, Session};
                    {error, Reason} -> {error, Reason}
                end
        end
    catch
        error:undef -> {error, <<"zenoh_nif_not_available">>};
        _:CatchReason -> {error, unicode:characters_to_binary(io_lib:format("zenoh_open_error: ~p", [CatchReason]))}
    end.

zenoh_put(Session, Key, Payload) ->
    try
        case zenoh_module() of
            none -> {error, <<"zenoh_nif_not_available">>};
            Mod ->
                case Mod:put(Session, Key, Payload) of
                    ok -> {ok, nil};
                    {ok, _} -> {ok, nil};
                    {error, Reason} -> {error, Reason}
                end
        end
    catch
        error:undef -> {error, <<"zenoh_nif_not_available">>};
        _:CatchReason -> {error, unicode:characters_to_binary(io_lib:format("zenoh_put_error: ~p", [CatchReason]))}
    end.

zenoh_get(Session, Key) ->
    try
        case zenoh_module() of
            none -> {error, <<"zenoh_nif_not_available">>};
            Mod ->
                case Mod:get(Session, Key) of
                    {ok, []} -> {ok, <<"">>};
                    {ok, [Msg | _]} ->
                        MsgPayload = case Msg of
                            #{payload := P} -> P;
                            #{<<"payload">> := P} -> P;
                            _ -> <<"">>
                        end,
                        {ok, MsgPayload};
                    {error, Reason} -> {error, Reason}
                end
        end
    catch
        error:undef -> {error, <<"zenoh_nif_not_available">>};
        _:CatchReason -> {error, unicode:characters_to_binary(io_lib:format("zenoh_get_error: ~p", [CatchReason]))}
    end.

zenoh_subscribe(Session, Key, Pid) ->
    try
        case zenoh_module() of
            none -> {error, <<"zenoh_nif_not_available">>};
            Mod ->
                case Mod:subscribe(Session, Key, Pid) of
                    {ok, _SubRef} -> {ok, nil};
                    {error, Reason} -> {error, Reason}
                end
        end
    catch
        error:undef -> {error, <<"zenoh_nif_not_available">>};
        _:CatchReason -> {error, unicode:characters_to_binary(io_lib:format("zenoh_subscribe_error: ~p", [CatchReason]))}
    end.

file_read(Path) ->
    try
        case file:read_file(Path) of
            {ok, Binary} -> {ok, Binary};
            {error, Reason} -> {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
        end
    catch
        _:CatchReason ->
            {error, unicode:characters_to_binary(io_lib:format("file_read crash: ~p", [CatchReason]))}
    end.

%% SC-HTTP-LAST-MODIFIED (Pass-118) — return RFC 7231 §7.1.1.1 IMF-fixdate
%% string of file mtime, or {error, _} on any failure. Used by serve_static_file
%% to emit Last-Modified header alongside ETag (Pass-85), so If-Modified-Since
%% conditional GETs can return 304 even when client lacks ETag cache.
file_mtime_http(Path) ->
    try
        case file:read_file_info(Path, [{time, posix}]) of
            {ok, FileInfo} ->
                Mtime = element(7, FileInfo), %% file_info record: mtime field (posix seconds)
                UniversalTime = calendar:system_time_to_universal_time(Mtime, second),
                Formatted = httpd_util:rfc1123_date(UniversalTime),
                {ok, unicode:characters_to_binary(Formatted)};
            {error, Reason} ->
                {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
        end
    catch
        _:CatchReason ->
            {error, unicode:characters_to_binary(io_lib:format("file_mtime crash: ~p", [CatchReason]))}
    end.

file_write(Path, Content) ->
    try
        case file:write_file(Path, Content) of
            ok -> {ok, nil};
            {error, Reason} -> {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
        end
    catch
        _:CatchReason ->
            {error, unicode:characters_to_binary(io_lib:format("file_write crash: ~p", [CatchReason]))}
    end.

%% Auth FFI functions (SC-AUTH-001)
system_time_seconds() ->
    erlang:system_time(second).

base64_decode(Input) ->
    try
        Decoded = base64:decode(Input),
        {ok, Decoded}
    catch
        _:_ -> {error, nil}
    end.

url_encode(Input) ->
    uri_string:compose_query([{<<"v">>, Input}]),
    %% Simple percent encoding
    unicode:characters_to_binary(http_uri:encode(binary_to_list(Input))).

get_env(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.

%% @doc Open an Erlang port spawning the given executable with args and env.
%% Args is a list of binaries; Env is a list of {binary, binary} tuples.
%% Returns {ok, Port} on success, {error, Reason} on failure.
pi_port_open(Cmd, Args, Env) ->
    CmdStr = binary_to_list(Cmd),
    ArgsList = [binary_to_list(A) || A <- Args],
    EnvList = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- Env],
    try
        Port = erlang:open_port(
            {spawn_executable, CmdStr},
            [stream, use_stdio, exit_status, binary,
             {args, ArgsList}, {env, EnvList}]
        ),
        {ok, Port}
    catch
        _:Reason -> {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

%% @doc Send a binary line to the port (stdin of the subprocess).
pi_port_send(Port, Data) ->
    try
        erlang:port_command(Port, Data),
        ok
    catch
        _:_ -> {error, closed}
    end.

%% @doc Close the port (sends EOF / SIGTERM to subprocess).
pi_port_close(Port) ->
    try
        erlang:port_close(Port),
        ok
    catch
        _:_ -> ok
    end.
