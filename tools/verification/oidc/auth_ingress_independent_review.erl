%% Bounded independent review of the actual frozen HTTP adapter.
%% All request authority is a public test fixture. Run in an env -i VM.
%% No listener is started; complete reader fixtures use a dummy non-socket.
-module(auth_ingress_independent_review).
-export([run/0, mist_limit_probe/0]).

-define(ADAPTER, indrajaal_gleam_web).
-define(ROUTER, 'cepaf_gleam@ui@wisp@router').
-define(TOKEN, <<"eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MjAwMDAwMDMwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjoiYzNpLXdpc3AtYXBpIn0.mfaSQdB3lV47YleIzp9Kr3dFpBgZ87aiQBr3F_BMWdOUjAGJwoiRifw8ZtZcazFPL1gxFfgSQSz04xDhCVtuAg">>).

run() ->
    Results = auth_ingress_test_ffi:with_oidc_env(fun adapter_checks/0),
    Probe = mist_limit_probe(),
    Passed = length([ok || #{passed := true} <- Results]),
    Report = #{schema => <<"uos-auth-ingress-independent/v1">>,
      otp_release => list_to_binary(erlang:system_info(otp_release)),
      adapter_checks => #{total => length(Results), passed => Passed,
                          failed => length(Results) - Passed, results => Results},
      mist_limit_probe => Probe,
      traffic => <<"none; complete in-memory framing with dummy socket">>,
      production_configuration => <<"not read; env -i VM and public fixtures">>},
    io:put_chars(json:encode(Report)),
    io:nl(),
    case Passed =:= length(Results) of true -> 0; false -> 1 end.

adapter_checks() ->
    Bad = <<"must-not-authorize-in-oidc-mode">>,
    Unknown = <<"/api/review/nonexistent">>,
    UnknownReq = req(post, Unknown, <<>>, Bad, none),
    %% Verify the actual auth boundary on a harmless unknown route before
    %% any known mutation path is considered.
    Boundary = checks([
      {"unknown_post_rejects_static_credential", fun() -> status(send(UnknownReq)) =:= 401 end},
      {"signed_unknown_post_reaches_404", fun() -> status(send(req(post,Unknown,<<>>,?TOKEN,none))) =:= 404 end}
    ]),
    true = lists:all(fun(#{passed := P}) -> P end, Boundary),
    Paths = [<<"/api/v1/podman/action">>, <<"/api/v1/podman/restart">>, <<"/api/v1/podman/stop">>,
             <<"/api/v1/emergency/trigger">>, <<"/api/v1/guardian/respond">>, <<"/api/v1/ooda/trigger">>,
             <<"/api/v1/system/ooda-trigger">>, <<"/api/v1/plan/update">>, <<"/api/v1/planning/add">>,
             <<"/api/v1/reload">>, <<"/api/v1/zenoh/publish">>, <<"/api/v1/cockpit/mode">>,
             <<"/api/v1/pi/prompt">>, <<"/ag-ui/run">>, <<"/ag-ui/hitl/respond">>, <<"/ag-ui/tools/result">>],
    Rejections = checks([{binary_to_list(<<"adapter_post_rejects:",Path/binary>>),
      fun() -> status(send(req(post,Path,<<>>,Bad,none))) =:= 401 end} || Path <- Paths]),
    Basic = checks([
      {"get_reload_405", fun() -> status(send(req(get,<<"/api/v1/reload">>,<<>>,none,none))) =:= 405 end},
      {"head_reload_405_empty_body", fun() ->
        R=send(req(head,<<"/api/v1/reload">>,<<>>,none,none)), status(R)=:=405 andalso body(R)=:= <<>> end},
      {"get_reload_query_405", fun() -> status(send(req(get,<<"/api/v1/reload">>,<<>>,none,{some,<<"ignored=1">>}))) =:= 405 end},
      {"head_reload_query_405", fun() -> status(send(req(head,<<"/api/v1/reload">>,<<>>,none,{some,<<"ignored=1">>}))) =:= 405 end},
      {"signed_get_reload_405", fun() -> status(send(req(get,<<"/api/v1/reload">>,<<>>,?TOKEN,none))) =:= 405 end},
      {"reload_allow_header_preserved", fun() ->
        header(send(req(get,<<"/api/v1/reload">>,<<>>,none,none)),<<"allow">>) =:= <<"POST, OPTIONS">> end},
      {"get_unknown_404", fun() -> status(send(req(get,Unknown,<<>>,none,none))) =:= 404 end},
      {"head_unknown_404_empty_body", fun() ->
        R=send(req(head,Unknown,<<>>,none,none)), status(R)=:=404 andalso body(R)=:= <<>> end},
      {"query_reaches_canonical_dispatch", fun() ->
        status(send(req(post,<<"/ag-ui/run">>,<<>>,?TOKEN,{some,<<"review=%2F&x=1">>}))) =:= 404 end},
      {"redirect_query_and_location_preserved", fun() ->
        R=send(req(get,<<Unknown/binary,"/">>,<<>>,none,{some,<<"review=%2F&x=1">>})),
        status(R)=:=301 andalso header(R,<<"location">>) =:= <<Unknown/binary,"?review=%2F&x=1">> end},
      {"options_status_and_allow_headers_preserved", fun() ->
        R=send(req(options,Unknown,<<>>,Bad,none)),
        status(R)=:=204 andalso body(R)=:= <<>> andalso
        contains(header(R,<<"access-control-allow-headers">>),<<"authorization">>) end},
      {"empty_authorization_rejected", fun() -> status(send(req(post,Unknown,<<>>,<<>>,none))) =:= 401 end},
      {"missing_authorization_rejected", fun() -> status(send(req(post,Unknown,<<>>,none,none))) =:= 401 end},
      {"signed_agui_pure_response", fun() ->
        R=send(req(post,<<"/ag-ui/run">>,<<>>,?TOKEN,none)),
        status(R)=:=200 andalso contains(body(R),<<"run_id">>) end},
      {"signed_body_reaches_validation", fun() ->
        Payload = <<"{\"id\":\"fixture-only\",\"status\":\"deliberately_invalid\"}">>,
        R=send(req(post,<<"/api/v1/plan/update">>,Payload,?TOKEN,none)),
        status(R)=:=400 andalso contains(body(R),<<"invalid status: deliberately_invalid">>) end},
      {"body_exact_65536_reaches_auth", fun() -> status(send(req(post,Unknown,binary:copy(<<"x">>,65536),none,none))) =:= 401 end},
      {"body_65537_rejected", fun() -> status(send(req(post,Unknown,binary:copy(<<"x">>,65537),none,none))) =:= 413 end},
      {"utf8_exact_byte_limit_reaches_auth", fun() ->
        status(send(req(post,Unknown,binary:copy(<<195,169>>,32768),none,none))) =:= 401 end},
      {"utf8_excess_byte_limit_rejected", fun() ->
        status(send(req(post,Unknown,<<(binary:copy(<<195,169>>,32768))/binary,"x">>,none,none))) =:= 413 end},
      {"invalid_utf8_rejected", fun() -> status(send(req(post,Unknown,<<255>>,none,none))) =:= 400 end},
      {"oversize_takes_priority_before_utf8", fun() ->
        status(send(req(post,Unknown,binary:copy(<<255>>,65537),none,none))) =:= 413 end}
    ]),
    Methods = checks([{atom_to_list(Method) ++ "_405",fun() ->
      status(send(req(Method,Unknown,<<>>,none,none))) =:= 405 end} || Method <- [put,delete,patch]]),
    Equivalent = checks([{atom_to_list(Method) ++ "_canonical_response_preserved",fun() ->
      Request=req(Method,Unknown,<<>>,none,none),
      Actual=send(Request), Canonical=?ROUTER:handle_request(Request),
      status(Actual)=:=status(Canonical) andalso body(Actual)=:=element(4,Canonical)
        andalso lists:sort(element(3,Actual))=:=lists:sort(element(3,Canonical))
      end} || Method <- [get,head,post,options]]),
    Boundary ++ Rejections ++ Basic ++ Methods ++ Equivalent.

%% This checks the actual pinned dependency call used by candidate 6b033f37.
%% It deliberately records an observed defect, without assuming that a
%% subsequent application-level repair changes the dependency itself.
mist_limit_probe() ->
    Payload=binary:copy(<<"x">>,65537),
    Wire = <<"10001\r\n",Payload/binary,"\r\n0\r\n\r\n">>,
    Conn={connection,{initial,Wire},unused_socket,tcp,unused_factory},
    Req={request,post,[{<<"transfer-encoding">>,<<"chunked">>}],Conn,http,<<"review.invalid">>,none,<<"/api/review/nonexistent">>,none},
    {ok, Decoded}=mist:read_body(Req,65536),
    Fixed=req(post,<<"/api/review/nonexistent">>,Conn,none,none),
    Declared=setelement(3,Fixed,[{<<"content-length">>,<<"65537">>}]),
    #{declared_limit=>65536,chunked_payload_bytes=>byte_size(Payload),
      returned_bytes=>byte_size(element(4,Decoded)),chunked_oversize_rejected=>false,
      content_length_oversize_rejected=>(mist:read_body(Declared,65536)=:={error,excess_body}),
      socket=>unused_socket}.

checks(Cases) -> [begin
    Passed=try Check() =:= true catch _:_ -> false end,
    #{name=>list_to_binary(Name),passed=>Passed}
  end || {Name,Check} <- Cases].
req(Method,Path,Body,Token,Query) ->
    Headers=case Token of none->[]; _ -> [{<<"authorization">>,<<"Bearer ",Token/binary>>}] end,
    {request,Method,Headers,Body,http,<<"review.invalid">>,none,Path,Query}.
send(Req) -> ?ADAPTER:handle_c3i_http_request(Req).
status(Response) -> element(2,Response).
body(Response) -> {bytes,Tree}=element(4,Response), 'gleam@bytes_tree':to_bit_array(Tree).
header(Response,Name) -> proplists:get_value(Name,element(3,Response),<<>>).
contains(Bin,Part) -> binary:match(Bin,Part) =/= nomatch.
