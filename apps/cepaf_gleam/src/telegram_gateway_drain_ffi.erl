%% Crash containment for the Telegram gateway drain (review G-02). The injected
%% Send runs inside the actor; an exception or exit inside it must neither
%% crash the actor nor carry its reason (which may embed request text or a
%% transport error string) into state, a report or a crash log. The reason is
%% discarded here by construction; the Gleam side records a typed
%% `OutboxUncertain("send_crashed")` with no payload.
-module(telegram_gateway_drain_ffi).
-export([guard_send/2]).

guard_send(Send, Request) when is_function(Send, 1) ->
  try {ok, Send(Request)} catch _:_ -> {error, nil} end.
