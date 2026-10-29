%% INERT mechanical node-local atomic storage and bounded metadata/hash only.
%% Registry transition/identity/rebind policy is owned entirely by Gleam.
-module(harness_native_backend_ffi).
-export([read_state/0,cas_state/2,observe/3]).
-include_lib("kernel/include/file.hrl").
-define(KEY,{?MODULE,node()}).
read_state() -> persistent_term:get(?KEY,absent).
cas_state(Expected,Replacement) ->
  case global:trans({?KEY,self()},fun() ->
    case persistent_term:get(?KEY,absent) =:= Expected of
      true -> persistent_term:put(?KEY,Replacement), {ok,true};
      false -> {ok,false}
    end
  end,[node()],0) of
    aborted -> {error,<<"backend_state_lock">>};
    Result -> Result
  end.

observe(Path, Max, Timeout) when is_binary(Path), is_integer(Max), Max > 0,
    Max =< 67108864, is_integer(Timeout), Timeout > 0, Timeout =< 3000 ->
    Parent=self(), Ref=make_ref(),
    {Pid, Mon}=spawn_monitor(fun() ->
        Result = try inspect(Path, Max)
                 catch Class:Reason -> {error, error_text(Class,Reason)} end,
        Parent ! {Ref,Result}
    end),
    receive
        {Ref,Result} -> erlang:demonitor(Mon,[flush]), Result;
        {'DOWN',Mon,process,Pid,_} -> {error,<<"backend_hash_worker_died">>}
    after Timeout ->
        exit(Pid,kill),
        receive {'DOWN',Mon,process,Pid,_} -> ok after 1000 ->
            erlang:demonitor(Mon,[flush]) end,
        %% Ref is unguessable; no status is read from executable output.
        receive {Ref,_} -> ok after 0 -> ok end,
        {error,<<"backend_hash_timeout">>}
    end;
observe(_,_,_) -> {error,<<"backend_hash_bound">>}.
error_text(Class,Reason) ->
    unicode:characters_to_binary(io_lib:format("backend_metadata:~p:~P",[Class,Reason,6])).
dir(Path) ->
    {ok,I}=file:read_link_info(Path,[{time,posix}]),
    {directory_observation,Path,I#file_info.type =:= directory,
     I#file_info.uid,I#file_info.mode band 8#7777,
     I#file_info.access =:= write orelse I#file_info.access =:= read_write}.
same(A,B) ->
    {A#file_info.type,A#file_info.size,A#file_info.inode,A#file_info.major_device,
     A#file_info.minor_device,A#file_info.uid,A#file_info.mode,A#file_info.mtime,A#file_info.ctime}
    =:=
    {B#file_info.type,B#file_info.size,B#file_info.inode,B#file_info.major_device,
     B#file_info.minor_device,B#file_info.uid,B#file_info.mode,B#file_info.mtime,B#file_info.ctime}.
inspect(Path,Max) ->
    {ok,Before}=file:read_link_info(Path,[{time,posix}]),
    case Before#file_info.type =:= regular andalso Before#file_info.size =< Max of
        false -> {error,<<"backend_not_regular_or_oversize">>};
        true ->
            {ok,F}=file:open(Path,[read,binary,raw]),
            try
                {ok,Opened}=file:read_file_info(F,[{time,posix}]),
                {Digest,Count}=hash(F,crypto:hash_init(sha256),0,Max),
                {ok,Closed}=file:read_file_info(F,[{time,posix}]),
                {ok,After}=file:read_link_info(Path,[{time,posix}]),
                Hex=binary:encode_hex(Digest,lowercase),
                Ancestors=[dir(<<"/nix">>),dir(<<"/nix/store">>)],
                {ok,{file_observation,true,false,Opened#file_info.uid,
                     Opened#file_info.mode band 8#7777,Count,Hex,
                     same(Before,Opened) andalso same(Opened,Closed)
                       andalso same(Closed,After),Ancestors}}
            after ok=file:close(F) end
    end.
hash(F,Context,Count,Max) ->
    case file:read(F,65536) of
        eof -> {crypto:hash_final(Context),Count};
        {ok,B} when Count+byte_size(B) =< Max ->
            hash(F,crypto:hash_update(Context,B),Count+byte_size(B),Max);
        {ok,_} -> error(hash_bound);
        {error,E} -> error({hash_read,E})
    end.
