%% =============================================================================
%% [C3I-SIL6] telegram_http_test_fixture — Real Bounded Local HTTP Test Fixture
%% =============================================================================
%% Local Tailnet HTTP fixture on an ephemeral port for testing
%% the Telegram client and service without touching live Telegram endpoints.
%%
%% Supports programmable modes:
%%   - normal: 200 OK with valid Telegram response matching target chat
%%   - forbidden: 403 Forbidden with ok=false
%%   - bad_request: 400 Bad Request with ok=false
%%   - bad_gateway: 502 Bad Gateway with ok=false
%%   - drop: drops TCP socket immediately (triggers client socket error)
%%   - delay: sleeps 15s (triggers client 10s timeout)
%%   - malformed: 200 OK with malformed JSON body
%%   - wrong_chat: 200 OK with valid JSON but wrong chat.id
%%
%% This module MUST NOT be reachable from production code paths.
%% =============================================================================
-module(telegram_http_test_fixture).
-behaviour(gen_server).

-export([start/0, start/1, stop/1, set_mode/2, set_updates/2, get_requests/1, clear_requests/1, set_file/4, set_file_opts/5, set_file_mode/5]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    listen_socket,
    port,
    mode = normal,
    preset_updates = [],
    %% wave 6i: file_id => {FilePath, Bytes}, served by getFile and /file/bot<token>/<path>
    preset_files = #{},
    requests = []
}).

%% -----------------------------------------------------------------------------
%% Public API
%% -----------------------------------------------------------------------------

start() ->
    start(0).

start(Port) ->
    case gen_server:start_link(?MODULE, [Port], []) of
        {ok, Pid} ->
            ActualPort = gen_server:call(Pid, get_port),
            %% Absolute DNS name prevents search-suffix retries after AAAA NODATA.
            BaseUrl = list_to_binary(io_lib:format("http://nas-1.tail55d152.ts.net.:~p", [ActualPort])),
            {ok, {Pid, ActualPort, BaseUrl}};
        Error ->
            Error
    end.

stop(Pid) ->
    try
        gen_server:stop(Pid)
    catch
        _:_ -> ok
    end.

set_mode(Pid, Mode) when is_binary(Mode) ->
    Atom = binary_to_existing_atom(Mode, utf8),
    gen_server:call(Pid, {set_mode, Atom});
set_mode(Pid, Mode) ->
    gen_server:call(Pid, {set_mode, Mode}).

set_updates(Pid, Updates) ->
    gen_server:call(Pid, {set_updates, Updates}).

get_requests(Pid) ->
    gen_server:call(Pid, get_requests).

clear_requests(Pid) ->
    gen_server:call(Pid, clear_requests).

%% wave 6i: register a file the fixture serves (test content only, never production).
set_file(Pid, FileId, FilePath, Bytes) when is_binary(FileId), is_binary(FilePath), is_binary(Bytes) ->
    gen_server:call(Pid, {set_file, FileId, FilePath, Bytes, true}).

%% DeclareSize=false makes getFile omit file_size, so the client sees an undeclared size.
set_file_opts(Pid, FileId, FilePath, Bytes, DeclareSize) when is_binary(FileId), is_binary(FilePath), is_binary(Bytes), is_boolean(DeclareSize) ->
    gen_server:call(Pid, {set_file, FileId, FilePath, Bytes, DeclareSize}).

%% Hostile range modes (file body only), for refusal-law tests:
%%   ignore_range   - answer 200 with the whole body even when a Range is sent
%%   wrong_first    - 206 whose Content-Range first differs from the request
%%   span_differs   - 206 whose Content-Range span is shorter than the body
%%   truncated_body - 206 whose Content-Length promises more than is sent
%%   total_changes  - 206 whose advertised total changes after the first chunk
%%   early_416      - 416 (bytes */Total) from the half-way offset on, though
%%                    earlier 206s advertised the real Total
%% The normal getFile still declares the true size.
set_file_mode(Pid, FileId, FilePath, Bytes, Mode) when is_binary(FileId), is_binary(FilePath), is_binary(Bytes), is_atom(Mode) ->
    gen_server:call(Pid, {set_file, FileId, FilePath, Bytes, #{declare => true, mode => Mode}}).

%% -----------------------------------------------------------------------------
%% gen_server Callbacks
%% -----------------------------------------------------------------------------

init([Port]) ->
    Opts = [
        binary,
        {packet, raw},
        {active, false},
        {reuseaddr, true},
        {ip, {100, 87, 7, 78}},
        {backlog, 64}
    ],
    case gen_tcp:listen(Port, Opts) of
        {ok, ListenSocket} ->
            {ok, ActualPort} = inet:port(ListenSocket),
            self() ! accept,
            {ok, #state{listen_socket = ListenSocket, port = ActualPort}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(get_port, _From, State) ->
    {reply, State#state.port, State};
handle_call({set_mode, Mode}, _From, State) ->
    {reply, ok, State#state{mode = Mode}};
handle_call({set_updates, Updates}, _From, State) ->
    {reply, ok, State#state{preset_updates = Updates}};
handle_call(get_requests, _From, State) ->
    {reply, lists:reverse(State#state.requests), State};
handle_call(clear_requests, _From, State) ->
    {reply, ok, State#state{requests = []}};
handle_call({set_file, FileId, FilePath, Bytes, DeclareSize}, _From, State) ->
    Files = maps:put(FileId, {FilePath, Bytes, DeclareSize}, State#state.preset_files),
    {reply, ok, State#state{preset_files = Files}};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(accept, State) ->
    case gen_tcp:accept(State#state.listen_socket, 200) of
        {ok, ClientSocket} ->
            ServerPid = self(),
            spawn_link(fun() -> handle_client(ClientSocket, ServerPid, State#state.mode, State#state.preset_updates, State#state.preset_files) end),
            self() ! accept,
            {noreply, State};
        {error, timeout} ->
            self() ! accept,
            {noreply, State};
        {error, closed} ->
            {noreply, State};
        {error, _Reason} ->
            self() ! accept,
            {noreply, State}
    end;
handle_info({record_request, Req}, State) ->
    {noreply, State#state{requests = [Req | State#state.requests]}};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    case State#state.listen_socket of
        undefined -> ok;
        Sock -> gen_tcp:close(Sock)
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% -----------------------------------------------------------------------------
%% HTTP Request Handling
%% -----------------------------------------------------------------------------

handle_client(Socket, ServerPid, Mode, PresetUpdates, PresetFiles) ->
    case read_request(Socket, <<>>) of
        {ok, Method, Path, Headers, Body} ->
            ServerPid ! {record_request, {Method, Path, Headers, Body}},
            case {Mode, is_subpath(Path, <<"/getFile">>), is_subpath(Path, <<"/file/bot">>)} of
                {normal, true, _} -> serve_get_file(Socket, Body, PresetFiles);
                {normal, _, true} -> serve_file_body(Socket, Path, Headers, PresetFiles);
                _ -> dispatch_response(Socket, Mode, Method, Path, Body, PresetUpdates)
            end;
        {error, _} ->
            gen_tcp:close(Socket)
    end.

read_request(Socket, Acc) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, Chunk} ->
            Combined = <<Acc/binary, Chunk/binary>>,
            case binary:split(Combined, <<"\r\n\r\n">>) of
                [Head, Rest] ->
                    [RequestLine | HeaderLines] = binary:split(Head, <<"\r\n">>, [global]),
                    [Method, Path, _Proto] = binary:split(RequestLine, <<" ">>, [global]),
                    Headers = parse_headers(HeaderLines, []),
                    ContentLength = case lists:keyfind(<<"content-length">>, 1, Headers) of
                        {_, Val} ->
                            try binary_to_integer(string:trim(Val)) catch _:_ -> 0 end;
                        false -> 0
                    end,
                    case byte_size(Rest) >= ContentLength of
                        true ->
                            <<Body:ContentLength/binary, _/binary>> = Rest,
                            {ok, Method, Path, Headers, Body};
                        false ->
                            read_remaining_body(Socket, Rest, ContentLength, Method, Path, Headers)
                    end;
                _ ->
                    read_request(Socket, Combined)
            end;
        Error ->
            Error
    end.

read_remaining_body(Socket, Current, Total, Method, Path, Headers) ->
    Needed = Total - byte_size(Current),
    case gen_tcp:recv(Socket, Needed, 5000) of
        {ok, Chunk} ->
            FullBody = <<Current/binary, Chunk/binary>>,
            {ok, Method, Path, Headers, FullBody};
        Error ->
            Error
    end.

parse_headers([], Acc) ->
    Acc;
parse_headers([<<>> | Rest], Acc) ->
    parse_headers(Rest, Acc);
parse_headers([Line | Rest], Acc) ->
    case binary:split(Line, <<": ">>) of
        [Key, Value] ->
            parse_headers(Rest, [{string:lowercase(Key), Value} | Acc]);
        _ ->
            parse_headers(Rest, Acc)
    end.

dispatch_response(Socket, drop, _Method, _Path, _Body, _Presets) ->
    gen_tcp:close(Socket);

dispatch_response(Socket, slow_valid, Method, Path, Body, Presets) ->
    timer:sleep(6000),
    dispatch_response(Socket, normal, Method, Path, Body, Presets);

dispatch_response(Socket, delay, Method, Path, Body, Presets) ->
    timer:sleep(15000),
    dispatch_response(Socket, normal, Method, Path, Body, Presets);

dispatch_response(Socket, forbidden, _Method, _Path, _Body, _Presets) ->
    send_json(Socket, 403, <<"{\"ok\":false,\"error_code\":403,\"description\":\"Forbidden: bot was blocked by the user\"}">>);

dispatch_response(Socket, bad_request, _Method, _Path, _Body, _Presets) ->
    send_json(Socket, 400, <<"{\"ok\":false,\"error_code\":400,\"description\":\"Bad Request: chat not found\"}">>);

dispatch_response(Socket, bad_gateway, _Method, _Path, _Body, _Presets) ->
    send_json(Socket, 502, <<"{\"ok\":false,\"error_code\":502,\"description\":\"Bad Gateway\"}">>);

dispatch_response(Socket, malformed, _Method, _Path, _Body, _Presets) ->
    send_json(Socket, 200, <<"{\"ok\":true, \"result\": broken_json">>);

dispatch_response(Socket, wrong_chat, _Method, _Path, _Body, _Presets) ->
    send_json(Socket, 200, <<"{\"ok\":true,\"result\":{\"message_id\":42,\"chat\":{\"id\":99999999}}}">>);

%% Positive-offset fixture mode for multi-cycle service acceptance. Normal mode
%% deliberately retains repeated presets for adversarial replay tests.
dispatch_response(Socket, offset_aware, Method, Path, Body, Presets) ->
    case is_subpath(Path, <<"/getUpdates">>) of
        false -> dispatch_response(Socket, normal, Method, Path, Body, Presets);
        true ->
            try
                Request = json:decode(Body),
                Offset = maps:get(<<"offset">>, Request, 0),
                Limit = maps:get(<<"limit">>, Request, 100),
                true = is_integer(Offset) andalso Offset >= 0,
                true = is_integer(Limit) andalso Limit >= 1 andalso Limit =< 100,
                Filtered = [I || I <- Presets,
                    maps:get(<<"update_id">>, json:decode(I)) >= Offset],
                dispatch_response(Socket, normal, Method, Path, Body,
                    lists:sublist(Filtered, Limit))
            catch _:_ ->
                send_json(Socket, 400, <<"{\"ok\":false,\"error_code\":400}">>)
            end
    end;

dispatch_response(Socket, normal, _Method, Path, Body, Presets) ->
    case is_subpath(Path, <<"/getUpdates">>) of
        true ->
            UpdatesJson = case Presets of
                [] -> <<"[]">>;
                List ->
                    Items = [Item || Item <- List],
                    iolist_to_binary([<<"[">>, string:join([binary_to_list(I) || I <- Items], ","), <<"]">>])
            end,
            Resp = iolist_to_binary([<<"{\"ok\":true,\"result\":">>, UpdatesJson, <<"}">>]),
            send_json(Socket, 200, Resp);
        false ->
            case is_subpath(Path, <<"/sendMessage">>) of
                true ->
                    ChatId = extract_chat_id(Body),
                    Resp = iolist_to_binary([
                        <<"{\"ok\":true,\"result\":{\"message_id\":42,\"chat\":{\"id\":">>,
                        integer_to_binary(ChatId),
                        <<"}}}">>
                    ]),
                    send_json(Socket, 200, Resp);
                false ->
                    case is_subpath(Path, <<"/answerCallbackQuery">>) of
                        true ->
                            send_json(Socket, 200, <<"{\"ok\":true,\"result\":true}">>);
                        false ->
                            send_json(Socket, 404, <<"{\"ok\":false,\"error_code\":404,\"description\":\"Not Found\"}">>)
                    end
            end
    end.

is_subpath(Path, Target) ->
    case binary:match(Path, Target) of
        nomatch -> false;
        _ -> true
    end.

extract_chat_id(Body) ->
    try
        case binary:match(Body, <<"\"chat_id\":">>) of
            {Pos, Len} ->
                <<_:Pos/binary, _:Len/binary, Rest/binary>> = Body,
                Trimmed = string:trim(Rest),
                Digits = lists:takewhile(fun(C) -> (C >= $0 andalso C =< $9) orelse C == $- end, binary_to_list(Trimmed)),
                list_to_integer(Digits);
            nomatch ->
                100
        end
    catch
        _:_ -> 100
    end.

send_json(Socket, StatusCode, Body) ->
    StatusText = case StatusCode of
        200 -> <<"OK">>;
        400 -> <<"Bad Request">>;
        403 -> <<"Forbidden">>;
        404 -> <<"Not Found">>;
        502 -> <<"Bad Gateway">>;
        _ -> <<"Status">>
    end,
    Len = byte_size(Body),
    Header = io_lib:format(
        "HTTP/1.1 ~p ~s\r\n"
        "Content-Type: application/json; charset=utf-8\r\n"
        "Content-Length: ~p\r\n"
        "Connection: close\r\n"
        "\r\n",
        [StatusCode, StatusText, Len]
    ),
    gen_tcp:send(Socket, [Header, Body]),
    gen_tcp:close(Socket).

%% -----------------------------------------------------------------------------
%% wave 6i: getFile and file body (normal mode only)
%% -----------------------------------------------------------------------------

serve_get_file(Socket, Body, Files) ->
    FileId = extract_json_string(Body, <<"\"file_id\":">>),
    case maps:find(FileId, Files) of
        {ok, {FilePath, Bytes, DeclareOpt}} ->
            DeclareSize = declare_of(DeclareOpt),
            SizeField = case DeclareSize of
                true -> [<<"\"file_size\":">>, integer_to_binary(byte_size(Bytes)), <<",">>];
                false -> []
            end,
            Resp = iolist_to_binary([
                <<"{\"ok\":true,\"result\":{\"file_id\":\"">>, FileId,
                <<"\",\"file_unique_id\":\"fx-">>, FileId, <<"\",">>,
                SizeField,
                <<"\"file_path\":\"">>, FilePath, <<"\"}}">>
            ]),
            send_json(Socket, 200, Resp);
        error ->
            send_json(Socket, 400, <<"{\"ok\":false,\"error_code\":400,\"description\":\"Bad Request: file not found\"}">>)
    end.

serve_file_body(Socket, Path, Headers, Files) ->
    %% Path is /file/bot<token>/<file_path>; match on the file path suffix.
    Matches = [{Bytes, mode_of(Opt)} || {_Id, {FilePath, Bytes, Opt}} <- maps:to_list(Files),
                        binary:longest_common_suffix([Path, <<"/", FilePath/binary>>]) =:= byte_size(FilePath) + 1],
    case Matches of
        [{Bytes, ignore_range} | _] ->
            send_bytes(Socket, 200, Bytes);
        [{Bytes, Mode} | _] ->
            %% wave 6j: honour a single byte range like the Telegram file CDN.
            case lists:keyfind(<<"range">>, 1, Headers) of
                {_, RangeValue} -> serve_range(Socket, Bytes, RangeValue, Mode);
                false -> send_bytes(Socket, 200, Bytes)
            end;
        [] -> send_json(Socket, 404, <<"{\"ok\":false,\"error_code\":404,\"description\":\"Not Found\"}">>)
    end.

declare_of(Opt) when is_boolean(Opt) -> Opt;
declare_of(#{declare := D}) -> D.

mode_of(Opt) when is_boolean(Opt) -> normal;
mode_of(#{mode := M}) -> M.

serve_range(Socket, Bytes, RangeValue, Mode) ->
    Total = byte_size(Bytes),
    try
        <<"bytes=", Spec/binary>> = string:trim(RangeValue),
        [FirstBin, LastBin] = binary:split(Spec, <<"-">>),
        First = binary_to_integer(FirstBin),
        Last0 = case LastBin of <<>> -> Total - 1; _ -> binary_to_integer(LastBin) end,
        case First >= Total orelse (Mode =:= early_416 andalso First >= Total div 2) of
            true -> send_status(Socket, 416, <<"Range Not Satisfiable">>, [{<<"Content-Range">>, iolist_to_binary([<<"bytes */">>, integer_to_binary(Total)])}], <<>>);
            false ->
                Last = min(Last0, Total - 1),
                Len = Last - First + 1,
                <<_:First/binary, Part:Len/binary, _/binary>> = Bytes,
                {CF, CL, CT} = case Mode of
                    wrong_first -> {First + 1, Last + 1, Total + 1};
                    span_differs -> {First, Last - 1, Total};
                    total_changes when First > 0 -> {First, Last, Total + 1};
                    _ -> {First, Last, Total}
                end,
                ContentRange = iolist_to_binary([<<"bytes ">>, integer_to_binary(CF), <<"-">>, integer_to_binary(CL), <<"/">>, integer_to_binary(CT)]),
                case Mode of
                    truncated_body -> send_truncated(Socket, ContentRange, Part);
                    _ -> send_status(Socket, 206, <<"Partial Content">>, [{<<"Content-Range">>, ContentRange}], Part)
                end
        end
    catch
        _:_ -> send_json(Socket, 400, <<"{\"ok\":false,\"error_code\":400,\"description\":\"Bad Range\"}">>)
    end.

send_status(Socket, StatusCode, StatusText, ExtraHeaders, Body) ->
    Len = byte_size(Body),
    Extra = [[K, <<": ">>, V, <<"\r\n">>] || {K, V} <- ExtraHeaders],
    Header = [io_lib:format("HTTP/1.1 ~p ~s\r\n", [StatusCode, StatusText]),
              <<"Content-Type: application/octet-stream\r\n">>,
              Extra,
              io_lib:format("Content-Length: ~p\r\nConnection: close\r\n\r\n", [Len])],
    gen_tcp:send(Socket, [Header, Body]),
    gen_tcp:close(Socket).

%% Promise the full length, send ten bytes fewer, close: a truncated body.
send_truncated(Socket, ContentRange, Part) ->
    Len = byte_size(Part),
    Sent = binary:part(Part, 0, max(0, Len - 10)),
    Header = [io_lib:format("HTTP/1.1 206 Partial Content\r\n", []),
              <<"Content-Type: application/octet-stream\r\n">>,
              <<"Content-Range: ">>, ContentRange, <<"\r\n">>,
              io_lib:format("Content-Length: ~p\r\nConnection: close\r\n\r\n", [Len])],
    gen_tcp:send(Socket, [Header, Sent]),
    gen_tcp:close(Socket).

extract_json_string(Body, Marker) ->
    try
        case binary:match(Body, Marker) of
            {Pos, Len} ->
                <<_:Pos/binary, _:Len/binary, Rest/binary>> = Body,
                Trimmed = string:trim(Rest),
                <<$", Tail/binary>> = Trimmed,
                [Value | _] = binary:split(Tail, <<"\"">>),
                Value;
            nomatch -> <<>>
        end
    catch
        _:_ -> <<>>
    end.

send_bytes(Socket, StatusCode, Body) ->
    Len = byte_size(Body),
    Header = io_lib:format(
        "HTTP/1.1 ~p OK\r\n"
        "Content-Type: application/octet-stream\r\n"
        "Content-Length: ~p\r\n"
        "Connection: close\r\n"
        "\r\n",
        [StatusCode, Len]
    ),
    gen_tcp:send(Socket, [Header, Body]),
    gen_tcp:close(Socket).
