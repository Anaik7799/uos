%% Narrow IO only; task/grant/price/completion policy belongs to Gleam.
-module(pi_review_io).
-export([ready/0,reserve/1,invoke/3,check_runtime_pins/2]).
-include_lib("kernel/include/file.hrl").
-define(ROOT,"/home/an/NAS-setup/uos").
-define(PIN_CHUNK,65536).
-define(PIN_DEADLINE_MS,5000).
-define(NODE_LIMIT,134217728).
-define(WORKER_LIMIT,65536).
-define(SDK_LIMIT,1048576).
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
  Node = <<?ROOT "/toolchains/nix-profile/bin/node">>,
  Worker = <<SourceRoot/binary,"/apps/cepaf_gleam/priv/uos_pi_review_once.mjs">>,
  {ok,nil}=check_runtime_pins(SourceRoot,Runtime),
  case ecology_capability_ffi:run_bounded_raw_input(Node,[Worker],<<(byte_size(Body)):32/big,Body/binary>>,30000) of
   {ok,{0,Out}} when byte_size(Out)=<65536 -> {ok,{exchange,Out,reaped}};
   %% Any missing/nonzero guardian result is conservatively unreaped/unknown.
   %% Do not parse returned data or issue a second worker/readback from it.
   _ -> {error,<<"review_cleanup_or_outcome_unknown_no_retry">>}
  end
 catch _:_ -> {error,<<"review_runtime_or_cleanup_unavailable">>} end.
%% Read-only prerequisite, not a ready/authority constructor. Node/SDK paths
%% are fixed; worker is SourceRoot plus a fixed suffix. The caller MUST obtain
%% SourceRoot from the trusted whole-grant source binding. This exported helper
%% does not establish that trust or confine an arbitrary root. Exposing it to an
%% untrusted caller could create a bounded read/hash-match oracle; it is not an
%% untrusted-input admission API. Runtime supplies digests, not executable paths.
%% Current pinned Node is 73,394,160 bytes, above the former 64MiB whole-file cap.
%% Streaming bounds each pread allocation to 64KiB; filesystem calls themselves
%% still require the caller's supervised process/physical IO trust assumptions.
check_runtime_pins(SourceRoot,Runtime)
 when is_binary(SourceRoot),byte_size(SourceRoot)>0,byte_size(SourceRoot)=<4096,
      is_binary(Runtime),byte_size(Runtime)>0,byte_size(Runtime)=<512 ->
 try
  Deadline=erlang:monotonic_time(millisecond)+?PIN_DEADLINE_MS,
  Pins=json:decode(Runtime),
  true=is_map(Pins),3=map_size(Pins),
  #{<<"node_sha256">>:=NH,<<"worker_sha256">>:=WH,<<"sdk_sha256">>:=SH}=Pins,
  Node = <<?ROOT "/toolchains/nix-profile/bin/node">>,
  Worker = <<SourceRoot/binary,"/apps/cepaf_gleam/priv/uos_pi_review_once.mjs">>,
  SDK = <<"/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js">>,
  ok=pin(Node,NH,?NODE_LIMIT,Deadline),
  ok=pin(Worker,WH,?WORKER_LIMIT,Deadline),
  ok=pin(SDK,SH,?SDK_LIMIT,Deadline),
  pin_time(Deadline),{ok,nil}
 catch _:_ -> {error,<<"review_runtime_pins_unverified">>} end;
check_runtime_pins(_,_) -> {error,<<"review_runtime_pins_unverified">>}.

pin(Path,Hash,Limit,Deadline) when is_binary(Hash),byte_size(Hash)=:=64 ->
 true=lists:all(fun(C)->(C>=$0 andalso C=<$9) orelse
                         (C>=$a andalso C=<$f)end,binary_to_list(Hash)),
 pin_time(Deadline),
 {ok,Fd}=file:open(Path,[read,binary,raw]),
 try
  {ok,Before}=file:read_file_info(Fd),
  #file_info{size=Size,type=regular}=Before,
  true=Size>0,true=Size=<Limit,
  Digest=hash_chunks(Fd,0,Size,crypto:hash_init(sha256),Deadline),
  pin_time(Deadline),
  eof=file:pread(Fd,Size,1),
  {ok,After}=file:read_file_info(Fd),
  %% Ignore access time. These are observations on one retained descriptor,
  %% not a defense against same-UID replacement of a later executable path.
  true=file_binding(Before)=:=file_binding(After),
  Hash=binary:encode_hex(Digest,lowercase),pin_time(Deadline),ok
 after ok=file:close(Fd) end.

hash_chunks(_Fd,Size,Size,Context,Deadline) ->
 pin_time(Deadline),crypto:hash_final(Context);
hash_chunks(Fd,Offset,Size,Context,Deadline) ->
 pin_time(Deadline),Count=min(?PIN_CHUNK,Size-Offset),
 {ok,Chunk}=file:pread(Fd,Offset,Count),Count=byte_size(Chunk),
 hash_chunks(Fd,Offset+Count,Size,crypto:hash_update(Context,Chunk),Deadline).

pin_time(Deadline) -> true=erlang:monotonic_time(millisecond)<Deadline,ok.

file_binding(#file_info{size=S,type=T,mode=M,links=L,major_device=D,
                       minor_device=Minor,inode=I,uid=U,gid=G,mtime=MT,ctime=CT}) ->
 {S,T,M,L,D,Minor,I,U,G,MT,CT}.
