%% Narrow IO only; task/grant/price/completion policy belongs to Gleam.
-module(pi_review_io).
-export([ready/0,reserve/1,invoke/3]).
-define(ROOT,"/home/an/NAS-setup/uos").
%% Source gate, not a caller/configuration assertion. Generic inherited-env
%% launch and the post-catalog fence are not qualified for model dispatch.
ready() -> {error,<<"review_transport_unavailable_clean_env_post_fence_runtime_closure">>}.
reserve(Request) when is_binary(Request),byte_size(Request)=<2048 ->
 case ecology_capability_ffi:run_bounded(<<?ROOT "/toolchains/opam-ocaml/bin/ocaml">>,
    [<<?ROOT "/tools/pi_review_reserve.ml">>,Request],6000) of
   {ok,{0,Out}} when byte_size(Out)=<8192 -> {ok,Out};
   _ -> {error,<<"review_reservation_unknown_no_retry">>}
 end;
reserve(_) -> {error,<<"review_request_bound">>}.
invoke(SourceRoot,Runtime,Body) ->
 try
  {ok,nil}=ready(),
  true=is_binary(Body),true=byte_size(Body)>0,true=byte_size(Body)=<65536,
  %% Runtime data is obtained ONLY from the whole reviewed grant. No request
  %% can select arbitrary executables, SDK module, cwd or environment values.
  #{<<"node_sha256">>:=NH,<<"worker_sha256">>:=WH,<<"sdk_sha256">>:=SH}=json:decode(Runtime),
  Node = <<?ROOT "/toolchains/nix-profile/bin/node">>,
  Worker = <<SourceRoot/binary,"/apps/cepaf_gleam/priv/uos_pi_review_once.mjs">>,
  SDK = <<"/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js">>,
  ok=pin(Node,NH),ok=pin(Worker,WH),ok=pin(SDK,SH),
  case ecology_capability_ffi:run_bounded_raw_input(Node,[Worker],<<(byte_size(Body)):32/big,Body/binary>>,30000) of
   {ok,{0,Out}} when byte_size(Out)=<65536 -> {ok,{exchange,Out,reaped}};
   %% Any missing/nonzero guardian result is conservatively unreaped/unknown.
   %% Do not parse returned data or issue a second worker/readback from it.
   _ -> {error,<<"review_cleanup_or_outcome_unknown_no_retry">>}
  end
 catch _:_ -> {error,<<"review_runtime_or_cleanup_unavailable">>} end.
pin(Path,Hash) when is_binary(Hash),byte_size(Hash)=:=64 ->
 {ok,Fd}=file:open(Path,[read,binary,raw]),
 try
  {ok,Before}=file:read_file_info(Fd),
  {file_info,Size,regular,_,_,_,_,_,_,_,_,_,_,_}=Before,
  true=Size>0,true=Size=<67108864,
  {ok,Bytes}=file:pread(Fd,0,Size+1),Size=byte_size(Bytes),
  {ok,After}=file:read_file_info(Fd),
  %% Ignore access-time changes, compare size/type/mode/identity via the FD.
  true=element(2,After)=:=Size,true=element(3,After)=:=regular,
  true=element(8,Before)=:=element(8,After),
  true=element(12,Before)=:=element(12,After),
  Hash=binary:encode_hex(crypto:hash(sha256,Bytes),lowercase),ok
 after file:close(Fd) end.
