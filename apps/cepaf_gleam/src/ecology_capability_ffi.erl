%% =============================================================================
%% UOS Ecology Capability Port FFI (SC-HOLON-001, SC-TOOLCHAIN-INPROJECT-001)
%% -----------------------------------------------------------------------------
%% Honest backend probes and BOUNDED subprocess execution for the 11-capability
%% super-agent substrate.
%%
%% Design invariant (the whole point of this module): a capability whose backend
%% is absent MUST be reported absent. It must never be simulated, defaulted, or
%% counted as engaged. Every probe below answers "is the real thing actually
%% there, right now" -- never "was it declared".
%%
%% Every subprocess is bounded by the OCaml process-group guardian: an absolute
%% deadline, exit status, output ceiling and process-group cleanup. A service
%% cgroup bounds children that create new sessions. This internal facade does
%% not expose arbitrary executable dispatch as an agent capability.
%% =============================================================================
-module(ecology_capability_ffi).

-export([uos_root/0, probe_executable/1, run_bounded/3,
         ets_backend_probe/0, km_nif_loaded/0, env_present/1,
         ets_init/0, ets_request/1, invoke_external/2, max_request/1]).

-include_lib("kernel/include/file.hrl").
-define(OUTPUT_LIMIT, 1048576).
-define(TABLE, uos_ecology_state).
-define(ROWS, 4096).

%% --- repo root --------------------------------------------------------------
%% Resolved from the loaded application's priv dir, so nothing hardcodes a
%% machine path. Falls back to cwd only if the app is not loaded.
uos_root() ->
    Start = case code:priv_dir(cepaf_gleam) of
                {error, _} -> element(2, file:get_cwd());
                PrivDir -> PrivDir
            end,
    unicode:characters_to_binary(ascend_to_repo_root(filename:absname(Start))).

%% Walk upward until the directory holding the standalone Jujutsu repo (.jj) is
%% found, or the exact immutable ecology release marker is found. No marker
%% yields the filesystem root, where required resources fail closed.
ascend_to_repo_root(Dir) ->
    case filelib:is_dir(filename:join(Dir, ".jj")) orelse release_root(Dir) of
        true -> Dir;
        false ->
            Parent = filename:dirname(Dir),
            case Parent =:= Dir of
                true -> Dir;
                false -> ascend_to_repo_root(Parent)
            end
    end.

release_root(Dir) ->
    file:read_file(filename:join(Dir,".uos-ecology-release")) =:=
        {ok,<<"uos.ecology-release.v1\n">>}.

%% Release executables and existing MAX environment inputs remain explicit
%% dependencies. Their bytes are rechecked before each external invocation.
dependency(Root,Name,DevelopmentRelative) ->
    case release_root(Root) of
        false -> filename:join(Root,DevelopmentRelative);
        true ->
            Manifest=filename:join(Root,"runtime-dependencies.json"),
            {ok,#file_info{type=regular,size=N}}=file:read_file_info(Manifest),
            true=N=<65536,
            {ok,Body}=file:read_file(Manifest),
            #{<<"schema">>:= <<"uos.ecology-runtime-dependencies.v1">>,
              Name:=#{<<"path">>:=Path,<<"sha256">>:=Expected}}=json:decode(Body),
            true=is_binary(Path) andalso filename:pathtype(Path)=:=absolute,
            {ok,#file_info{type=regular,size=Size}}=file:read_file_info(Path),
            true=Size=<134217728,
            {ok,Fd}=file:open(Path,[read,binary,raw]),
            Actual=try hash_file(Fd,crypto:hash_init(sha256),Size)
                   after file:close(Fd) end,
            true=Actual=:=Expected,
            binary_to_list(Path)
    end.

hash_file(Fd,Hash,Remaining) ->
    case file:read(Fd,65536) of
        eof when Remaining=:=0 -> binary:encode_hex(crypto:hash_final(Hash),lowercase);
        {ok,Bytes} when byte_size(Bytes)=<Remaining ->
            hash_file(Fd,crypto:hash_update(Hash,Bytes),Remaining-byte_size(Bytes));
        _ -> error(dependency_changed)
    end.

%% --- probes -----------------------------------------------------------------
probe_executable(Path) ->
    P = binary_to_list(Path),
    case file:read_file_info(P) of
        {ok, #file_info{type=regular, mode=Mode}} ->
            (Mode band 8#111) =/= 0;
        _ -> false
    end.

%% ETS is in-process: the probe actually creates and reads back a term rather
%% than asserting that ETS "exists". A read-back mismatch reports false.
ets_backend_probe() ->
    try
        Tab=ets:new(ecology_probe,[set]),
        try ets:insert(Tab,{probe,observed}), [{probe,observed}]=ets:lookup(Tab,probe), true
        after ets:delete(Tab) end
    catch _:_ -> false
    end.

%% Delegates to the NIF shim's own loaded/0, which distinguishes "kernel says 0.0"
%% from "kernel is absent".
km_nif_loaded() ->
    try uos_km_nif:loaded() catch _:_ -> false end.

env_present(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> false;
        "" -> false;
        _ -> true
    end.

%% --- bounded execution ------------------------------------------------------
%% Returns {ok, {ExitCode, Output}} | {error, Reason}. Never blocks past TimeoutMs.
run_bounded(Path, Args, TimeoutMs) -> run_guarded(Path,Args,TimeoutMs,none).

run_guarded(Path, Args, TimeoutMs, Input)
  when is_binary(Path), is_list(Args), is_integer(TimeoutMs),
       TimeoutMs>0, TimeoutMs=<60000 ->
    try
        Root=binary_to_list(uos_root()),
        Ocaml=dependency(Root,<<"ocaml">>,"toolchains/opam-ocaml/bin/ocaml"),
        Guardian=filename:join(Root,"tools/ecology_process.ml"),
        Mode=case Input of none->"merged";_->"framed" end,
        A=["-I","+unix",Guardian,integer_to_list(TimeoutMs),
           integer_to_list(?OUTPUT_LIMIT),Mode,binary_to_list(Path)] ++
          [binary_to_list(X)||X<-Args],
        Port = erlang:open_port({spawn_executable, Ocaml},
                              [stream,use_stdio,exit_status,binary,{args,A}]),
        case Input of
            none->ok;
            Data when is_binary(Data),byte_size(Data)=<65536 ->
                true=erlang:port_command(Port,<<(byte_size(Data)):32/big,Data/binary>>)
        end,
        collect(Port, erlang:monotonic_time(millisecond)+TimeoutMs+1000, 0, [])
    catch
        _:_ -> {error, <<"backend_spawn_failed">>}
    end;
run_guarded(_,_,_,_) -> {error,<<"invalid_resource_bound">>}.

collect(Port, Deadline, Size, Chunks) ->
    Remaining=max(0,Deadline-erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Chunk}} ->
            case Size+byte_size(Chunk)=< ?OUTPUT_LIMIT of
                true -> collect(Port,Deadline,Size+byte_size(Chunk),[Chunk|Chunks]);
                false -> erlang:port_close(Port), {error,<<"output_limit">>}
            end;
        {Port, {exit_status, 124}} -> {error,<<"timeout">>};
        {Port, {exit_status, 125}} -> {error,<<"backend_output_or_process_failure">>};
        {Port, {exit_status, Code}} ->
            {ok, {Code, iolist_to_binary(lists:reverse(Chunks))}}
    after Remaining ->
        _ = (try erlang:port_close(Port) catch _:_ -> ok end),
        {error, <<"guardian_timeout">>}
    end.

%% The permanent Gleam actor owns this table; transient workers never own it.
ets_init() ->
    case ets:whereis(?TABLE) of
        undefined -> ets:new(?TABLE,[named_table,public,set,{read_concurrency,true}]);
        _ -> ok
    end,
    nil.

ets_request(Input) when is_binary(Input),byte_size(Input)=<8192 ->
    try
        Req=json:decode(Input),
        #{<<"operation">>:=Op,<<"namespace">>:=Ns,<<"key">>:=Key}=Req,
        true=is_binary(Ns) andalso byte_size(Ns)>0 andalso byte_size(Ns)=<128,
        true=is_binary(Key) andalso byte_size(Key)>0 andalso byte_size(Key)=<128,
        true=(ets:whereis(?TABLE)=/=undefined),
        Result=ets_operation(Op,{Ns,Key},Req),
        {ok,iolist_to_binary(json:encode(Result))}
    catch
        throw:Why -> {error,Why};
        _:_ -> {error,<<"invalid_ets_request_or_runtime_unavailable">>}
    end;
ets_request(_) -> {error,<<"ets_input_bound">>}.

ets_operation(<<"get">>,Key,_) ->
    case ets:lookup(?TABLE,Key) of
        [{Key,Version,Value}] -> #{<<"found">>=>true,<<"version">>=>Version,<<"value">>=>Value};
        [] -> #{<<"found">>=>false}
    end;
ets_operation(Op,Key,Req) when Op=:= <<"put">>;Op=:= <<"compare_exchange">> ->
    Value=maps:get(<<"value">>,Req),
    true=iolist_size(json:encode(Value))=<4096,
    case ets:lookup(?TABLE,Key) of
        [] ->
            case Op=:= <<"compare_exchange">> andalso maps:get(<<"expected_version">>,Req,-1)=/=0 of
                true -> throw(<<"version_conflict">>);
                false -> ok
            end,
            %% Named-table insert count is conservatively bounded using an
            %% atomic reservation; callers cannot access the reserved atom key.
            Reserved=ets:update_counter(?TABLE,rows,{2,1},{rows,0}),
            case Reserved=< ?ROWS of
                false -> ets:update_counter(?TABLE,rows,{2,-1}),throw(<<"ets_capacity">>);
                true ->
                    Version=erlang:unique_integer([monotonic,positive]),
                    case ets:insert_new(?TABLE,{Key,Version,Value}) of
                        true -> #{<<"stored">>=>true,<<"version">>=>Version};
                        false -> ets:update_counter(?TABLE,rows,{2,-1}),throw(<<"version_conflict">>)
                    end
            end;
        [{Key,Version,_}] ->
            Expected=case Op of <<"compare_exchange">>->maps:get(<<"expected_version">>,Req);_->Version end,
            case Expected=:=Version of false->throw(<<"version_conflict">>);true->ok end,
            Next=erlang:unique_integer([monotonic,positive]),
            Match=[{{Key,Version,'_'},[],[{{{const,Key},Next,{const,Value}}}]}],
            case ets:select_replace(?TABLE,Match) of
                1 -> #{<<"stored">>=>true,<<"version">>=>Next};
                0 -> throw(<<"version_conflict">>)
            end
    end;
ets_operation(<<"delete">>,Key,_) ->
    case ets:take(?TABLE,Key) of
        [] -> #{<<"deleted">>=>false};
        [_] -> ets:update_counter(?TABLE,rows,{2,-1}),#{<<"deleted">>=>true}
    end;
ets_operation(_,_,_) -> throw(<<"unknown_ets_operation">>).

invoke_external(<<"modular_max">>,Input) -> max_request(Input);
invoke_external(<<"openrouter_free">>,Input) ->
    'cepaf_gleam@ecology@external_capabilities':openrouter(Input);
invoke_external(_,_) -> {error,<<"unknown_external_capability">>}.

max_request(Input) when is_binary(Input),byte_size(Input)=<65536 ->
    try max_request_checked(Input) catch _:_->{error,<<"max_runtime_dependency_mismatch">>} end;
max_request(_) -> {error,<<"max_input_bound">>}.

max_request_checked(Input) ->
    Root=uos_root(),
    RootPath=binary_to_list(Root),
    Pixi=list_to_binary(dependency(RootPath,<<"pixi">>,"toolchains/pixi/bin/pixi")),
    Manifest=list_to_binary(dependency(RootPath,<<"max_manifest">>,"services/inference/max/pixi.toml")),
    _=dependency(RootPath,<<"max_lock">>,"services/inference/max/pixi.lock"),
    Args=[<<"run">>,<<"--no-install">>,<<"--frozen">>,<<"--manifest-path">>,
          Manifest,<<"python">>,
          <<Root/binary,"/services/inference/max/ecology_max_worker.py">>],
    case run_guarded(Pixi,Args,30000,Input) of
        {ok,{0,<<Size:32/big,Body:Size/binary>>}} ->
            try json:decode(Body) of
                #{<<"ok">>:=true,<<"result">>:=Result} ->
                    {ok,iolist_to_binary(json:encode(Result))};
                #{<<"ok">>:=false,<<"error">>:=Error} -> {error,Error};
                _ -> {error,<<"invalid_max_response">>}
            catch _:_ -> {error,<<"invalid_max_response">>} end;
        {ok,{Code,_}} -> {error,<<"max_exit_or_framing_failure:",(integer_to_binary(Code))/binary>>};
        Error -> Error
    end.
