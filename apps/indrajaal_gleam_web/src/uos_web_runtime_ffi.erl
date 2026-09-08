-module(uos_web_runtime_ffi).
-export([observe_vm/0, configuration/0]).

-spec observe_vm() -> {binary(), binary(), binary(), binary(), integer(), integer(), non_neg_integer()}.
observe_vm() ->
    %% Initialized once at main entry, before accepting requests.
    Key = {?MODULE, started},
    {StartedUtc, StartedMono, RunId} = case persistent_term:get(Key, undefined) of
        undefined ->
            Utc = erlang:system_time(microsecond),
            Mono = erlang:monotonic_time(millisecond),
            Id = iolist_to_binary([os:getpid(), <<"-">>, integer_to_binary(Utc)]),
            Value = {Utc, Mono, Id},
            persistent_term:put(Key, Value),
            Value;
        Value -> Value
    end,
    %% A requested runtime version is configuration, never an observation.
    %% In particular, UOS_OTP_RELEASE must not bypass the startup guard.
    OtpRelease = erlang:system_info(otp_release),
    {list_to_binary(OtpRelease),
     list_to_binary(erlang:system_info(version)),
     list_to_binary(os:getpid()), RunId, StartedUtc,
     erlang:system_time(microsecond),
     max(0, erlang:monotonic_time(millisecond) - StartedMono)}.

-spec configuration() -> {binary(), binary(), binary(), boolean()}.
configuration() ->
    {bounded_env("UOS_WEB_CANDIDATE", 40),
     bounded_env("UOS_WEB_INSTANCE", 64),
     bounded_env("UOS_WEB_ROLE", 16),
     os:getenv("UOS_WEB_MANAGED") =:= "true"}.

bounded_env(Name, Limit) ->
    case os:getenv(Name) of
        false -> <<>>;
        Value when length(Value) =< Limit -> unicode:characters_to_binary(Value);
        _ -> <<>>
    end.
