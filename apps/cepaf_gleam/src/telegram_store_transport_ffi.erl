-module(telegram_store_transport_ffi).
-export([request/6, request_with_cleanup/6, request_config_with_cleanup/2, config_database/1, config_guardian_hash/1, config_worker_hash/1, finite_request_with_cleanup/2]).
-include_lib("kernel/include/file.hrl").
-define(MAX,1048572).
%% Bounded native Core/SQLite executables exceed16MiB; hashing shares request deadline.
-define(MAX_EXECUTABLE_BYTES,67108864).
%% Only the typed local configuration supplies these paths/hashes.
request(Guardian,GuardianHash,Worker,WorkerHash,Db,Body) ->
 case request_with_cleanup(Guardian,GuardianHash,Worker,WorkerHash,Db,Body) of
  {{ok,Out},_} -> {ok,Out};
  {{error,Code},_} -> {error,Code}
 end.

request_config_with_cleanup({local_configuration,Guardian,GuardianHash,Worker,WorkerHash,Db}, Body) ->
 request_with_cleanup(Guardian,GuardianHash,Worker,WorkerHash,Db,Body).

config_database({local_configuration,_,_,_,_,Db}) -> Db.
config_guardian_hash({local_configuration,_,GH,_,_,_}) -> GH.
config_worker_hash({local_configuration,_,_,_,WH,_}) -> WH.

%% Opt-in only. Legacy APIs above/below retain their separate denylist behavior.
%% Gleam chooses this closed architecture/profile; verify the real host as well.
%% Static facade runs BEFORE the guardian loader and supplies its own finite
%% envp, so unknown/concurrent parent env additions cannot cross that boundary.
%% This does not repair BEAM startup trust or mutable same-UID executable paths.
-spec finite_request_with_cleanup(term(), binary()) ->
 {{ok,binary()} | {error,binary()}, none | {some,{integer(),integer()}}}.
finite_request_with_cleanup(
 {finite_configuration,linux_x8664,native_storage_v1,
  Launcher,LH,Guardian,GH,Worker,WH,Db}, Body)
 when is_binary(Body),byte_size(Body)>0,byte_size(Body)=< ?MAX ->
 Parent=self(),Ref=make_ref(),Deadline=erlang:monotonic_time(millisecond)+5000,
 {Pid,Monitor}=spawn_monitor(fun()->
   PM=monitor(process,Parent),
   Result=try
     {unix,linux}=os:type(),
     true=lists:prefix("x86_64-",erlang:system_info(system_architecture)),
     true=valid_path(Db),true=valid_path(Guardian),true=valid_path(Worker),
     true=valid_path(Launcher),
     ok=pinned(Launcher,LH,Deadline),ok=pinned(Guardian,GH,Deadline),
     ok=pinned(Worker,WH,Deadline),
     Args=["linux-x86_64","native-storage-v1",binary_to_list(Guardian),
           binary_to_list(Worker),binary_to_list(Db)],
     %% No inherited-environment snapshot/overlay is a safety premise here.
     %% Complete preparation before final time sample; physical preemption after
     %% this sample is still not an atomic exec-time deadline guarantee.
     Remaining=Deadline-erlang:monotonic_time(millisecond),
     true=Remaining>0,
     Port=open_port({spawn_executable,binary_to_list(Launcher)},
       [stream,use_stdio,exit_status,binary,
        {args,Args++[integer_to_list(Remaining)]}]),
     try
       true=port_command(Port,<<(byte_size(Body)):32/big,Body/binary>>,[nosuspend]),
       collect_with_cleanup(Port,Deadline,PM,0,[])
     catch _:_->{{error,<<"transport_uncertain">>},none}
     after try port_close(Port) catch _:_ -> ok end end
   catch _:_->{{error,<<"transport_configuration_or_spawn">>},none}end,
   Parent!{Ref,Result}
 end),
 receive
  {Ref,Result}->demonitor(Monitor,[flush]),Result;
  {'DOWN',Monitor,process,Pid,_}->{{error,<<"transport_uncertain">>},none}
 after 5700->exit(Pid,kill),demonitor(Monitor,[flush]),
   {{error,<<"transport_cleanup_unknown">>},none}
 end;
finite_request_with_cleanup(_,_) ->
 {{error,<<"transport_configuration_or_spawn">>},none}.

request_with_cleanup(Guardian,GuardianHash,Worker,WorkerHash,Db,Body)
 when is_binary(Body),byte_size(Body)>0,byte_size(Body)=< ?MAX ->
 Parent=self(),Ref=make_ref(),Deadline=erlang:monotonic_time(millisecond)+5000,
 {Pid,Monitor}=spawn_monitor(fun()->
   PM=monitor(process,Parent),
   Result=try
     true=valid_path(Db),true=valid_path(Guardian),true=valid_path(Worker),
     ok=pinned(Guardian,GuardianHash,Deadline),ok=pinned(Worker,WorkerHash,Deadline),
     ChildEnv=loader_environment(),
     %% Finish bounded environment work BEFORE the final time sample. This is
     %% not an atomic scheduler/exec deadline fence against later preemption.
     Remaining=Deadline-erlang:monotonic_time(millisecond),
     true=Remaining>0,
     Port=open_port({spawn_executable,binary_to_list(Guardian)},
       [stream,use_stdio,exit_status,binary,{env,ChildEnv},
        {args,[binary_to_list(Worker),binary_to_list(Db),integer_to_list(Remaining)]}]),
     try
       true=port_command(Port,<<(byte_size(Body)):32/big,Body/binary>>,[nosuspend]),
       collect_with_cleanup(Port,Deadline,PM,0,[])
     catch _:_->{{error,<<"transport_uncertain">>},none}
     after try port_close(Port) catch _:_ -> ok end end
   catch _:_->{{error,<<"transport_configuration_or_spawn">>},none}end,
   Parent!{Ref,Result}
 end),
 receive
  {Ref,Result}->demonitor(Monitor,[flush]),Result;
  {'DOWN',Monitor,process,Pid,_}->{{error,<<"transport_uncertain">>},none}
 after 5700->exit(Pid,kill),demonitor(Monitor,[flush]),{{error,<<"transport_cleanup_unknown">>},none}
 end;
request_with_cleanup(_,_,_,_,_,_)->{{error,<<"transport_input_bound">>},none}.
%% Bounded loader-variable suppression for the existing native boundary.
%% Denotation: remove fixed loader hooks plus every OBSERVED LD_* name;
%% preserve all other inherited entries. This is a denylist, NOT an allowlist
%% or a complete safe environment. Do not return/log/hash environment values.
%% Fixed names are removed even when absent from the snapshot. Unknown names
%% concurrently introduced by os:putenv can still race open_port's overlay.
%% Caller premise: trusted stable BEAM environment. Untrusted concurrent
%% mutation remains unsupported/HOLD at runtime admission, never a scrub proof.
-spec loader_environment() -> [{string(), false}].
loader_environment() ->
 Entries=os:getenv(),
 true=length(Entries)=<2048,
 {Names,Bytes}=lists:foldl(fun(E,{Ns,N})->
   B=unicode:characters_to_binary(E),true=is_binary(B),
   Next=N+byte_size(B),true=Next=<262144,
   {Name,Rest}=lists:splitwith(fun(C)->C=/=$=end,E),
   true=Name=/=[],true=Rest=/=[],
   {[Name|Ns],Next}
 end,{[],0},Entries),
 true=Bytes=<262144,
 Fixed=["LD_AUDIT","LD_BIND_NOT","LD_BIND_NOW","LD_DEBUG","LD_DEBUG_OUTPUT",
        "LD_DYNAMIC_WEAK","LD_HWCAP_MASK","LD_LIBRARY_PATH","LD_ORIGIN_PATH",
        "LD_PRELOAD","LD_PROFILE","LD_PROFILE_OUTPUT","LD_SHOW_AUXV",
        "LD_TRACE_LOADED_OBJECTS","LD_USE_LOAD_BIAS","LD_VERBOSE","LD_WARN",
        "LD_PREFER_MAP_32BIT_EXEC","LD_POINTER_GUARD","LD_ASSUME_KERNEL",
        "GLIBC_TUNABLES","GCONV_PATH","LOCPATH","NLSPATH","GETCONF_DIR"],
 [{Name,false}||Name<-lists:usort(Fixed++[N||N<-Names,lists:prefix("LD_",N)])].

valid_path(P) when is_binary(P),byte_size(P)>0,byte_size(P)=<4096 ->
 filename:pathtype(P)=:=absolute andalso binary:match(P,<<0>>)=:=nomatch
 andalso not lists:any(fun(X)->X=:= <<"..">> orelse X=:= <<".">>end,filename:split(P));
valid_path(_)->false.
pinned(Path,Expected,Deadline) ->
 true=erlang:monotonic_time(millisecond)<Deadline,
 true=is_binary(Expected) andalso byte_size(Expected)=:=64,
 {ok,#file_info{type=regular,links=1,size=N,mode=M}}=file:read_link_info(Path),
 true=N>0 andalso N=< ?MAX_EXECUTABLE_BYTES andalso M band 8#111=/=0,
 {ok,F}=file:open(Path,[read,binary,raw]),
 Actual=try hash(F,crypto:hash_init(sha256),N,Deadline)after file:close(F)end,
 true=Actual=:=Expected,ok.
hash(F,H,N,Deadline)->
 true=erlang:monotonic_time(millisecond)<Deadline,
 case file:read(F,65536)of
 eof when N=:=0->binary:encode_hex(crypto:hash_final(H),lowercase);
 {ok,B}when byte_size(B)=<N->hash(F,crypto:hash_update(H,B),N-byte_size(B),Deadline);
 _->error(changed)
 end.
collect_with_cleanup(Port,Deadline,PM,Size,Chunks)->
 Remaining=max(0,Deadline+500-erlang:monotonic_time(millisecond)),
 receive
  {Port,{data,B}}when Size+byte_size(B)=<1048576->collect_with_cleanup(Port,Deadline,PM,Size+byte_size(B),[B|Chunks]);
  {Port,{data,_}}->{{error,<<"transport_output_bound_uncertain">>},none};
  {Port,{exit_status,0}}->
   NowUs=erlang:system_time(microsecond),
   Witness={some,{0,NowUs}},
   case {erlang:monotonic_time(millisecond)=<Deadline,iolist_to_binary(lists:reverse(Chunks))}of
    {true,<<N:32/big,Body:N/binary>>}when N>0,N=< ?MAX->
     case unicode:characters_to_binary(Body,utf8,utf8)of
      Body->{{ok,Body},Witness};
      _->{{error,<<"transport_response_uncertain">>},Witness}
     end;
    _->{{error,<<"transport_response_uncertain">>},Witness}
   end;
  {Port,{exit_status,124}}->
   NowUs=erlang:system_time(microsecond),
   {{error,<<"transport_uncertain">>},{some,{124,NowUs}}};
  {Port,{exit_status,125}}->
   NowUs=erlang:system_time(microsecond),
   {{error,<<"transport_uncertain">>},{some,{125,NowUs}}};
  {Port,{exit_status,126}}->
   {{error,<<"transport_cleanup_unknown">>},none};
  {Port,{exit_status,_}}->
   {{error,<<"transport_uncertain">>},none};
  {'DOWN',PM,process,_,_}->exit(caller_down)
 after Remaining->{{error,<<"transport_cleanup_unknown">>},none}
 end.
