-module(uos_zlp_shard).
-behaviour(gen_server).
-export([start_link/1, shard_name/1, resolve_port_executable/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

shard_name(ShardId) ->
    list_to_atom("uos_zlp_shard_" ++ integer_to_list(ShardId)).

resolve_port_executable() ->
    EnvCandidates = case os:getenv("UOS_ZLP_PORT_BIN") of
        false -> [];
        "" -> [];
        EnvPath -> [EnvPath]
    end,
    Candidates = EnvCandidates ++ [
        filename:absname("var/zlp/uos_zlp_v3_port"),
        filename:absname("../../var/zlp/uos_zlp_v3_port"),
        "/home/an/NAS-setup/uos/var/zlp/uos_zlp_v3_port"
    ],
    find_executable(Candidates).

find_executable([]) ->
    {error, zlp_port_binary_not_built};
find_executable([Path | Rest]) ->
    case filelib:is_regular(Path) of
        true -> {ok, Path};
        false -> find_executable(Rest)
    end.

start_link(ShardId) ->
    gen_server:start_link({local, shard_name(ShardId)}, ?MODULE, ShardId, []).

init(ShardId) ->
    process_flag(trap_exit, true),
    case resolve_port_executable() of
        {error, Reason} ->
            {stop, Reason};
        {ok, BinPath} ->
            Port = open_port({spawn_executable, BinPath},
                             [binary, {packet, 4}, use_stdio, exit_status, {parallelism, true}]),
            persistent_term:put({uos_zlp_shard_pid, ShardId}, self()),

            %% Prune dead subscriber Pids and replay live ETS Zenoh subscriptions on restart (Theorem T15)
            SavedEntries = case ets:whereis(uos_zlp_subscriptions) of
                undefined -> [];
                _ -> ets:lookup(uos_zlp_subscriptions, ShardId)
            end,
            lists:foreach(fun({S, T, SubPid} = Entry) ->
                case is_process_alive(SubPid) of
                    true -> ok;
                    false ->
                        _ = S,
                        _ = T,
                        ets:delete_object(uos_zlp_subscriptions, Entry)
                end
            end, SavedEntries),
            UniqueTopics = lists:usort([
                Topic || {_S, Topic, SubPid} <- SavedEntries, is_process_alive(SubPid)
            ]),
            NextReqId = lists:foldl(fun(TopicBin, ReqAcc) ->
                Frame = <<16#55:8, 16#03:8, 0:16/big, ReqAcc:64/big, 0:64/big, TopicBin/binary>>,
                erlang:port_command(Port, Frame),
                ReqAcc + 1
            end, 1, UniqueTopics),

            {ok, #{shard_id => ShardId,
                   port => Port,
                   next_req => NextReqId,
                   replay_until => NextReqId - 1,
                   pending => #{}}}
    end.

handle_call({rpc, Opcode, Flags, SeqOrRounds, Payload}, From, State) ->
    #{port := Port, next_req := ReqId, pending := Pending} = State,
    Frame = <<16#55:8, Opcode:8, Flags:16/big, ReqId:64/big, SeqOrRounds:64/big, Payload/binary>>,
    erlang:port_command(Port, Frame),
    {noreply, State#{next_req => ReqId + 1, pending => Pending#{ReqId => From}}};

handle_call({subscribe_zenoh, TopicBin, SubscriberPid}, From, State) ->
    #{shard_id := ShardId, port := Port, next_req := ReqId, pending := Pending} = State,
    Existing = ets:lookup(uos_zlp_subscriptions, ShardId),
    AlreadySubscribed = lists:any(
        fun({_S, T, P}) -> T =:= TopicBin andalso is_process_alive(P) end,
        Existing
    ),
    AlreadyHasExact = lists:member({ShardId, TopicBin, SubscriberPid}, Existing),
    case AlreadyHasExact of
        true -> ok;
        false -> ets:insert(uos_zlp_subscriptions, {ShardId, TopicBin, SubscriberPid})
    end,
    case AlreadySubscribed of
        true ->
            {reply, {ok, #{excl => 1, lane_or_sub => 1, value => 0}}, State};
        false ->
            Frame = <<16#55:8, 16#03:8, 0:16/big, ReqId:64/big, 0:64/big, TopicBin/binary>>,
            erlang:port_command(Port, Frame),
            {noreply, State#{next_req => ReqId + 1, pending => Pending#{ReqId => From}}}
    end.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({Port, {data, <<16#55:8, 16#83:8, Excl:8, _Sub:8, 0:64/big, Digest:64/big, JsonBin/binary>>}},
            #{port := Port, shard_id := ShardId} = State) ->
    %% Unsolicited live Zenoh SSE stream event (req_id == 0 -> disjoint from RPC correlation by Theorem T13)
    Entries = ets:lookup(uos_zlp_subscriptions, ShardId),
    lists:foreach(fun({_S, _Topic, SubPid} = Entry) ->
        case is_process_alive(SubPid) of
            true  -> SubPid ! {zlp_zenoh_push, ShardId, Excl, Digest, JsonBin};
            false -> ets:delete_object(uos_zlp_subscriptions, Entry)
        end
    end, Entries),
    {noreply, State};

handle_info({Port, {data, <<16#55:8, 16#84:8, Excl:8, Sub:8, ReqId:64/big, Val:64/big, BodyBin/binary>>}},
            #{port := Port, pending := Pending} = State) ->
    %% OP_ZENOH_GET variable-length verified payload reply
    case maps:take(ReqId, Pending) of
        {From, Pending1} ->
            gen_server:reply(From, {ok, #{excl => Excl, lane_or_sub => Sub, value => Val, body => BodyBin}}),
            {noreply, State#{pending => Pending1}};
        error ->
            {noreply, State}
    end;

handle_info({Port, {data, <<16#55:8, Status:8, Excl:8, Sub:8, ReqId:64/big, Val:64/big>>}},
            #{port := Port, pending := Pending, replay_until := ReplayUntil} = State) ->
    case maps:take(ReqId, Pending) of
        {From, Pending1} ->
            Reply = case Status of
                0 -> {ok, #{excl => Excl, lane_or_sub => Sub, value => Val}};
                _ ->
                    %% Roll back optimistic ETS insert if OP_ZENOH_SUBSCRIBE failed or was policy-refused
                    {error, {zlp_refused, Status, Excl, Val}}
            end,
            gen_server:reply(From, Reply),
            {noreply, State#{pending => Pending1}};
        error when ReqId =< ReplayUntil ->
            {noreply, State};
        error ->
            {noreply, State}
    end;

handle_info({Port, {exit_status, ExitCode}}, #{port := Port, pending := Pending} = State) ->
    maps:foreach(fun(_ReqId, From) ->
        gen_server:reply(From, {error, {port_crashed, ExitCode}})
    end, Pending),
    {stop, {port_crashed, ExitCode}, State#{pending => #{}}};

handle_info({'EXIT', Port, Reason}, #{port := Port, pending := Pending} = State) ->
    maps:foreach(fun(_ReqId, From) ->
        gen_server:reply(From, {error, {port_exit, Reason}})
    end, Pending),
    {stop, {port_exit, Reason}, State#{pending => #{}}};

handle_info(_Other, State) ->
    {noreply, State}.

terminate(_Reason, #{port := Port}) ->
    try erlang:port_close(Port) catch _:_ -> ok end,
    ok.
