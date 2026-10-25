-module(telegram_status_test_io).
-export([reset/2,now/0,authorize/0,probe/2,calls/0]).
reset(T,L)->put(status_times,T),put(status_leases,L),put(status_calls,0),nil.
next(K)->case get(K) of [X]->X;[X|Xs]->put(K,Xs),X end.
now()->next(status_times).
authorize()->next(status_leases).
probe(_,_) -> put(status_calls,calls()+1),{ok,200}.
calls()->get(status_calls).
