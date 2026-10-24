%% Bounded filesystem mechanics inside the isolated observation child.
%% Gleam supplies fixed roots and budgets; this adapter never selects scope.
-module(telegram_knowledge_files).
-export([catalog/5]).
-include_lib("kernel/include/file.hrl").

catalog(Roots,MaxFiles,MaxBytes,MaxFile,MaxDepth) ->
  try
    true=is_list(Roots) andalso length(Roots)>0 andalso length(Roots)=<2,
    true=is_integer(MaxFiles) andalso MaxFiles>0 andalso MaxFiles=<1024,
    true=is_integer(MaxBytes) andalso MaxBytes>0 andalso MaxBytes=<8388608,
    true=is_integer(MaxFile) andalso MaxFile>0 andalso MaxFile=<262144,
    true=is_integer(MaxDepth) andalso MaxDepth>=0 andalso MaxDepth=<4,
    Limits={MaxFiles,MaxBytes,MaxFile,MaxDepth},
    {Docs,_,_,Links,_,_}=lists:foldl(fun({Root,Prefix},State)->
      true=is_binary(Root) andalso byte_size(Root)=<4096,
      true=is_binary(Prefix) andalso byte_size(Prefix)=<512,
      nomatch=binary:match(Root,<<0>>),nomatch=binary:match(Prefix,<<0>>),
      absolute=filename:pathtype(binary_to_list(Root)),
      ok=ancestors(binary_to_list(Root)),
      directory(Root,Prefix,0,Limits,State)
    end,{[],0,0,0,0,0},Roots),
    {ok,{catalog,lists:reverse(Docs),Links}}
  catch _:_ -> {error,<<"knowledge_catalog_unavailable">>} end.

ancestors("/") -> ok;
ancestors(Path) ->
  ok=ancestors(filename:dirname(Path)),
  {ok,#file_info{type=directory}}=file:read_link_info(Path),
  ok.

identity(I) -> {I#file_info.type,I#file_info.inode,I#file_info.major_device,I#file_info.minor_device}.
stable(A,B) -> identity(A)=:=identity(B) andalso A#file_info.size=:=B#file_info.size
  andalso A#file_info.mtime=:=B#file_info.mtime.

directory(Path,Prefix,Depth,{_,_,_,MaxDepth}=Limits,{Ds,N,B,L,E,D}) ->
  true=Depth=<MaxDepth,true=D<128,
  {ok,Before}=file:read_link_info(Path),directory=Before#file_info.type,
  {ok,Names}=file:list_dir(Path),
  true=length(Names)=<2048,true=E+length(Names)=<4096,
  Result=lists:foldl(fun(Name,S)->
    NameBin=unicode:characters_to_binary(Name),
    true=is_binary(NameBin) andalso byte_size(NameBin)>0 andalso byte_size(NameBin)=<255,
    nomatch=binary:match(NameBin,<<"/">>),nomatch=binary:match(NameBin,<<0>>),
    false=lists:member(NameBin,[<<".">>,<<"..">>]),
    visit(<<Path/binary,"/",NameBin/binary>>,<<Prefix/binary,"/",NameBin/binary>>,Depth,Limits,S)
  end,{Ds,N,B,L,E+length(Names),D+1},lists:sort(Names)),
  {ok,After}=file:read_link_info(Path),
  true=identity(Before)=:=identity(After),
  true=Before#file_info.mtime=:=After#file_info.mtime,
  Result.

visit(Path,Relative,Depth,Limits,{Ds,N,B,L,E,D}=State) ->
  {ok,I}=file:read_link_info(Path),
  case I#file_info.type of
    symlink -> {Ds,N,B,L+1,E,D};
    directory -> directory(Path,Relative,Depth+1,Limits,State);
    regular ->
      case filename:extension(binary_to_list(Relative)) of
        ".md" -> document(Path,Relative,I,Limits,State);
        _ -> State
      end;
    _ -> State
  end.

document(Path,Relative,Before,{MaxFiles,MaxBytes,MaxFile,_},{Ds,N,B,L,E,D}) ->
  true=N<MaxFiles,true=Before#file_info.size=<MaxFile,
  true=B+Before#file_info.size=<MaxBytes,
  {ok,Fd}=file:open(Path,[read,raw,binary]),
  Text=try
    {ok,Opened}=file:read_file_info(Fd),
    true=stable(Before,Opened),regular=Opened#file_info.type,
    Bytes=read_all(Fd,MaxFile,[]),
    {ok,After}=file:read_file_info(Fd),
    {ok,Named}=file:read_link_info(Path),
    true=stable(Opened,After),true=stable(After,Named),
    true=byte_size(Bytes)=:=After#file_info.size,
    Utf8=unicode:characters_to_binary(Bytes,utf8,utf8),
    true=is_binary(Utf8),Utf8
  after ok=file:close(Fd) end,
  Size=byte_size(Text),true=B+Size=<MaxBytes,
  Digest=binary:encode_hex(crypto:hash(sha256,Text),lowercase),
  {[{document,Relative,Text,Digest,Size}|Ds],N+1,B+Size,L,E,D}.

read_all(Fd,Left,Acc) ->
  case file:read(Fd,min(65536,Left+1)) of
    eof -> iolist_to_binary(lists:reverse(Acc));
    {ok,Part} -> true=byte_size(Part)=<Left,read_all(Fd,Left-byte_size(Part),[Part|Acc]);
    _ -> error(read_failed)
  end.
