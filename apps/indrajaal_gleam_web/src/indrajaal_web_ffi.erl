-module(indrajaal_web_ffi).
-export([read_repo_file/1, list_repo_dir/1, listen_port/1, read_fixed_request_body/4]).

%% Read exactly one already-validated fixed-length request body. The caller
%% rejects transfer encodings and duplicate/invalid Content-Length fields.
%% A single monotonic deadline bounds the entire socket read.
read_fixed_request_body(Req, ContentLength, MaximumBytes, TimeoutMilliseconds)
  when is_integer(ContentLength), is_integer(MaximumBytes),
       is_integer(TimeoutMilliseconds), ContentLength >= 0,
       ContentLength =< MaximumBytes, MaximumBytes >= 0,
       TimeoutMilliseconds > 0 ->
    case Req of
        {request, _Method, _Headers,
         {connection, {initial, Initial}, Socket, Transport, _Factory},
         _Scheme, _Host, _Port, _Path, _Query}
          when is_bitstring(Initial), bit_size(Initial) rem 8 =:= 0 ->
            InitialSize = byte_size(Initial),
            case InitialSize of
                ContentLength ->
                    {ok, setelement(4, Req, Initial)};
                Size when Size < ContentLength ->
                    Deadline = erlang:monotonic_time(millisecond)
                               + TimeoutMilliseconds,
                    case receive_fixed_body(
                           Transport, Socket, ContentLength - Size,
                           Deadline, [Initial]) of
                        {ok, Body} -> {ok, setelement(4, Req, Body)};
                        Error -> Error
                    end;
                _ ->
                    {error, fixed_body_malformed}
            end;
        {request, _Method, _Headers,
         {connection, {stream, _, _, _, _}, _, _, _},
         _Scheme, _Host, _Port, _Path, _Query} ->
            {error, fixed_body_unsupported};
        _ ->
            {error, fixed_body_malformed}
    end;
read_fixed_request_body(_Req, _ContentLength, _MaximumBytes, _TimeoutMilliseconds) ->
    {error, fixed_body_malformed}.

receive_fixed_body(_Transport, _Socket, 0, _Deadline, Chunks) ->
    {ok, iolist_to_binary(lists:reverse(Chunks))};
receive_fixed_body(Transport, Socket, Remaining, Deadline, Chunks) ->
    TimeLeft = Deadline - erlang:monotonic_time(millisecond),
    case TimeLeft =< 0 of
        true ->
            {error, fixed_body_read_timeout};
        false ->
            case receive_with_timeout(Transport, Socket, Remaining, TimeLeft) of
                {ok, Data} when is_binary(Data), byte_size(Data) > 0,
                                byte_size(Data) =< Remaining ->
                    receive_fixed_body(
                      Transport, Socket, Remaining - byte_size(Data),
                      Deadline, [Data | Chunks]);
                {error, timeout} ->
                    {error, fixed_body_read_timeout};
                {error, unsupported} ->
                    {error, fixed_body_unsupported};
                _ ->
                    {error, fixed_body_malformed}
            end
    end.

receive_with_timeout(tcp, Socket, Amount, Timeout) ->
    gen_tcp:recv(Socket, Amount, Timeout);
receive_with_timeout(ssl, Socket, Amount, Timeout) ->
    ssl:recv(Socket, Amount, Timeout);
receive_with_timeout(_, _Socket, _Amount, _Timeout) ->
    {error, unsupported}.

listen_port(Default) ->
    case os:getenv("UOS_WEB_PORT") of
        false -> Default;
        Value ->
            try list_to_integer(Value) of
                Port when Port >= 1024, Port =< 65535 -> Port;
                _ -> Default
            catch
                _:_ -> Default
            end
    end.

read_repo_file(RelativePath) ->
    Root = "/home/an/NAS-setup/uos",
    PathStr = case is_binary(RelativePath) of
        true -> binary_to_list(RelativePath);
        false -> RelativePath
    end,
    CleanPath = normalize_repo_path(PathStr),
    FullPath = filename:join([Root, CleanPath]),
    case filelib:is_dir(FullPath) of
        true ->
            render_dir_listing(FullPath, CleanPath);
        false ->
            case file:read_file(FullPath) of
                {ok, Bin} -> {ok, Bin};
                {error, eisdir} ->
                    render_dir_listing(FullPath, CleanPath);
                {error, enoent} ->
                    %% Try adding .md extension
                    case file:read_file(FullPath ++ ".md") of
                        {ok, MdBin} -> {ok, MdBin};
                        _ ->
                            %% Search in directory for matching file prefix/substring
                            Dir = filename:dirname(FullPath),
                            Base = string:lowercase(filename:basename(FullPath)),
                            case file:list_dir(Dir) of
                                {ok, Files} ->
                                    Matching = [F || F <- Files,
                                        string:find(string:lowercase(F), Base) =/= nomatch],
                                    case Matching of
                                        [FirstMatch | _] ->
                                            file:read_file(filename:join([Dir, FirstMatch]));
                                        [] ->
                                            {error, <<"enoent">>}
                                    end;
                                _ ->
                                    {error, <<"enoent">>}
                            end
                    end;
                {error, Reason} ->
                    {error, list_to_binary(atom_to_list(Reason))}
            end
    end.

render_dir_listing(FullPath, CleanPath) ->
    case file:list_dir(FullPath) of
        {ok, Files} ->
            Sorted = lists:sort(Files),
            Lines = [
                "# Directory: /", CleanPath, "\n\n",
                "| Name | Type | Navigation Link |\n",
                "|---|---|---|\n"
            ] ++ [
                format_entry(CleanPath, FullPath, F) || F <- Sorted
            ],
            {ok, unicode:characters_to_binary(lists:flatten(Lines))};
        {error, Reason} ->
            {error, list_to_binary(atom_to_list(Reason))}
    end.

format_entry(CleanPath, FullPath, F) ->
    SubPath = filename:join([FullPath, F]),
    RelLink = case CleanPath of
        "" -> F;
        _ -> CleanPath ++ "/" ++ F
    end,
    Type = case filelib:is_dir(SubPath) of
        true -> "📁 Directory";
        false -> "📄 File"
    end,
    WebPath = case CleanPath of
        "docs/wiki" ++ _ -> "/wiki/" ++ F;
        "docs/zk" ++ _ -> "/zk/" ++ F;
        "docs" ++ _ ->
            PrefixLen = length("docs/"),
            case length(RelLink) >= PrefixLen of
                true -> "/docs/" ++ string:slice(RelLink, PrefixLen);
                false -> "/docs/" ++ RelLink
            end;
        _ -> "/files/" ++ RelLink
    end,
    ["| `", F, "` | ", Type, " | [", F, "](", WebPath, ") |\n"].

list_repo_dir(RelativePath) ->
    Root = "/home/an/NAS-setup/uos",
    PathStr = case is_binary(RelativePath) of
        true -> binary_to_list(RelativePath);
        false -> RelativePath
    end,
    CleanPath = case PathStr of
        "/" ++ Rest -> Rest;
        P -> P
    end,
    FullPath = filename:join([Root, CleanPath]),
    case file:list_dir(FullPath) of
        {ok, Filenames} ->
            Bins = [unicode:characters_to_binary(F) || F <- Filenames],
            {ok, Bins};
        {error, Reason} -> {error, list_to_binary(atom_to_list(Reason))}
    end.

normalize_repo_path(P) ->
    P1 = strip_prefix(P, "file:///home/an/NAS-setup/uos/"),
    P2 = strip_prefix(P1, "http://nas-1.tail55d152.ts.net:4100/"),
    P3 = strip_prefix(P2, "http://100.87.7.78:4100/"),
    P4 = strip_prefix(P3, "/home/an/NAS-setup/uos/"),
    P5 = strip_prefix(P4, "home/an/NAS-setup/uos/"),
    P6 = strip_prefix(P5, "/files/"),
    P7 = strip_prefix(P6, "files/"),
    case P7 of
        "/" ++ Rest -> Rest;
        Clean -> Clean
    end.

strip_prefix(Str, Prefix) ->
    case string:prefix(Str, Prefix) of
        nomatch -> Str;
        Rest -> Rest
    end.
