-module(telegram_brief_test_io).
-export([reset/2,now_ms/0,authorize/0,mark/1,calls/0]).
reset(T,L)->put(brief_times,T),put(brief_leases,L),put(brief_calls,[]),nil.
next(K)->case get(K) of [X]->X;[X|Xs]->put(K,Xs),X end.
now_ms()->next(brief_times).
authorize()->next(brief_leases).
mark(S)->put(brief_calls,[S|get(brief_calls)]),nil.
calls()->lists:reverse(get(brief_calls)).
