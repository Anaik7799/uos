%% http-laneC-gen-statem-verify: a real gen_statem (Cowboy's protocol behaviour)
%% run on zigvm loading the pinned OTP-30 stdlib beams from disk — byte-EQ vs OTP.
-module(zigvm_statem).
-behaviour(gen_statem).
-export([go/1, init/1, callback_mode/0, off/3, on/3]).

callback_mode() -> state_functions.
init([]) -> {ok, off, 0}.

off(cast, push, N)          -> {next_state, on,  N + 1};
off({call, From}, get, N)   -> {keep_state, N, [{reply, From, {off, N}}]}.
on(cast, push, N)           -> {next_state, off, N};
on({call, From}, get, N)    -> {keep_state, N, [{reply, From, {on, N}}]}.

go(_) ->
    {ok, _} = gen_statem:start({local, ?MODULE}, ?MODULE, [], []),
    gen_statem:cast(?MODULE, push),   %% off -> on,  N=1
    gen_statem:cast(?MODULE, push),   %% on  -> off, N=1
    gen_statem:cast(?MODULE, push),   %% off -> on,  N=2
    R = gen_statem:call(?MODULE, get),%% {on, 2}
    erlang:display(R),
    ok.
