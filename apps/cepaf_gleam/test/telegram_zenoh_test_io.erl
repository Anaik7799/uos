-module(telegram_zenoh_test_io).
-export([set_clock/1,clock/0,http_reply/2]).
set_clock(Values)->put(zenoh_test_clock,Values),nil.
clock()->[Head|Tail]=get(zenoh_test_clock),put(zenoh_test_clock,Tail),Head.
http_reply(Status,Body) when is_integer(Status),is_binary(Body),byte_size(Body)=<100000 ->
 {ok,L}=gen_tcp:listen(0,[binary,{active,false},{ip,{127,0,0,1}},{reuseaddr,true}]),
 {ok,Port}=inet:port(L),
 {Pid,Ref}=spawn_monitor(fun()->
   case gen_tcp:accept(L,1000) of
    {ok,S}->try
      {ok,_}=gen_tcp:recv(S,0,1000),
      case Status of
       0->receive after 1000->ok end;
       _->ok=gen_tcp:send(S,[<<"HTTP/1.1 ">>,integer_to_binary(Status),
          <<" Test\r\nContent-Type: application/json\r\nContent-Length: ">>,
          integer_to_binary(byte_size(Body)),<<"\r\nConnection: close\r\n\r\n">>,Body])
      end
     after gen_tcp:close(S) end;
    _->ok
   end
 end),
 try uos_openrouter_ffi:bounded_call(fun(D)->
   {ok,S}=gen_tcp:connect({127,0,0,1},Port,[binary,{active,false}],150),
   try
    ok=gen_tcp:send(S,<<"GET /public/test HTTP/1.1\r\nHost: fixture\r\nConnection: close\r\n\r\n">>),
    uos_openrouter_ffi:read_response(fun(T)->gen_tcp:recv(S,0,T) end,D)
   after gen_tcp:close(S) end
 end,150)
 after
   gen_tcp:close(L),exit(Pid,kill),
   receive {'DOWN',Ref,process,Pid,_}->ok after 1000->erlang:error(fixture_cleanup_timeout) end
 end.
