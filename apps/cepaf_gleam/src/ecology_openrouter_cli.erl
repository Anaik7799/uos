%% One-shot paid calibration adapter. Gleam owns ordering, OCaml checks the
%% canonical task/ledger and records body hashes. No optimization loop.
-module(ecology_openrouter_cli).
-export([main/0,prepare/0]).
-include_lib("kernel/include/file.hrl").
-define(ROOT, "/home/an/NAS-setup/uos").

helper(Operation, Payload) ->
    Encoded=iolist_to_binary(json:encode(Payload)),
    case ecology_capability_ffi:run_bounded(
      <<?ROOT "/toolchains/opam-ocaml/bin/ocaml">>,
      [<<?ROOT "/tools/ecology_openrouter.ml">>,Operation,Encoded],6000) of
        {ok,{0,Output}} ->
            try {ok,json:decode(Output)} catch _:_ -> {error,<<"invalid_guard_receipt">>} end;
        _ -> {error,<<"task_or_budget_guard_denied">>}
    end.

authorize(Scope) ->
    case helper(<<"guard">>,Scope) of
        {ok,#{<<"status">>:=<<"task_fence_observed">>,<<"dispatch_authorized">>:=false}} -> {ok,nil};
        _ -> {error,<<"task_fence_denied">>}
    end.

reserve(Scope,Request,Body) ->
    try
        Expected=binary:encode_hex(crypto:hash(sha256,Body),lowercase),
        #{<<"call_id">>:=CallId}=Scope,
        Envelope=#{<<"scope">>=>Scope,<<"request">>=>json:decode(Request),<<"body">>=>Body},
        case helper(<<"reserve">>,Envelope) of
            {ok,#{<<"status">>:=<<"reserved">>,<<"dispatch_authorized">>:=true,
                   <<"call_id">>:=CallId,<<"body_sha256">>:=Expected,
                   <<"ledger_path">>:=<<?ROOT "/var/ecology/openrouter_budget.sqlite3">>}} -> {ok,nil};
            _ -> {error,<<"fresh_bound_reservation_required">>}
        end
    catch _:_ -> {error,<<"reservation_binding_failed">>} end.

module_hash(Module) ->
    {module,Module}=code:ensure_loaded(Module),
    Path=code:which(Module),
    {ok,Bytes}=file:read_file(Path),
    {ok,{Module,Md5}}=beam_lib:md5(Bytes),
    Md5=Module:module_info(md5),
    #{module=>atom_to_binary(Module),path=>list_to_binary(Path),
      sha256=>binary:encode_hex(crypto:hash(sha256,Bytes),lowercase)}.

modules() -> ['cepaf_gleam@ecology@openrouter_engine','cepaf_gleam@ecology@daily_budget',
              'uos_swarm@openrouter_worker',uos_openrouter_ffi,ecology_openrouter_cli].

prepare() ->
    try
        [Path]=init:get_plain_arguments(),
        {ok,#file_info{type=regular,size=Size}}=file:read_link_info(Path),
        true=Size=<24576,
        {ok,Raw}=file:read_file(Path),
        #{<<"profile">>:=Name,<<"system">>:=System,<<"user">>:=User,<<"max_tokens">>:=Tokens}=json:decode(Raw),
        {ok,Profile}='uos_swarm@openrouter_worker':profile_from_name(Name),
        Model='uos_swarm@openrouter_worker':profile_model(Profile),
        Body='uos_swarm@openrouter_worker':request_json({request,Model,System,User,Tokens}),
        io:put_chars(json:encode(#{status=><<"prepared">>,body=>Body,
          loaded_modules=>[module_hash(M)||M<-modules()],network_calls=>0})),halt(0)
    catch _:_ ->
        io:put_chars(<<"{\"status\":\"stopped\",\"reason\":\"body_preparation_failed\"}">>),halt(1)
    end.

main() ->
    try
        [Path]=init:get_plain_arguments(),
        {ok,#file_info{type=regular,size=Size}}=file:read_link_info(Path),
        true=Size=<24576,
        {ok,Raw}=file:read_file(Path),
        Scope=json:decode(Raw),
        #{<<"profile">>:=Name,<<"system">>:=System,<<"user">>:=User,
          <<"max_tokens">>:=Tokens,<<"call_id">>:=Id}=Scope,
        {ok,Profile}='uos_swarm@openrouter_worker':profile_from_name(Name),
        Model='uos_swarm@openrouter_worker':profile_model(Profile),
        Request={request,Model,System,User,Tokens},
        Credential=fun()->case uos_openrouter_ffi:api_key() of {ok,K}->{some,K};_->none end end,
        Fetch=fun(T)->uos_openrouter_ffi:https_get(<<"https://openrouter.ai/api/v1/models">>,T) end,
        Post=fun(K,B,T)->uos_openrouter_ffi:https_post_json(<<"https://openrouter.ai/api/v1/chat/completions">>,K,B,T) end,
        Clock=fun()->erlang:monotonic_time(millisecond) end,
        Io={engine_io,{io,Credential,Fetch,Post,Clock},
            fun()->authorize(Scope) end,fun(R,B)->reserve(Scope,R,B) end},
        case 'cepaf_gleam@ecology@openrouter_engine':execute(Id,Profile,Request,Io) of
            {ok,Outcome} ->
                Value=json:decode('gleam@json':to_string('uos_swarm@openrouter_worker':outcome_json(Outcome))),
                io:put_chars(json:encode(#{status=><<"completed">>,outcome=>Value,
                  otp=>list_to_binary(erlang:system_info(otp_release)),
                  erts=>list_to_binary(erlang:system_info(version)),
                  loaded_modules=>[module_hash(M)||M<-modules()],effect_authority=>false})),halt(0);
            {error,Reason} ->
                io:put_chars(json:encode(#{status=><<"stopped">>,reason=>Reason,effect_authority=>false})),halt(1)
        end
    catch _:_ ->
        io:put_chars(<<"{\"status\":\"stopped\",\"reason\":\"calibration_adapter_failure\",\"effect_authority\":false}">>),
        halt(1)
    end.
