-module(serve_8999).
-export([start/0]).

start() ->
    application:ensure_all_started(inets),
    Root = "/home/an/NAS-setup/uos/ops/nodes/razr15-1-wsl2",
    {ok, _Pid} = inets:start(httpd, [
        {port, 8999},
        {server_name, "uos_razr15_staging"},
        {server_root, Root},
        {document_root, Root},
        {bind_address, {0,0,0,0}},
        {mime_types, [
            {"ps1", "text/plain"},
            {"sh", "text/plain"},
            {"mojo", "text/plain"},
            {"txt", "text/plain"},
            {"html", "text/html"},
            {"gz", "application/gzip"}
        ]}
    ]),
    io:format("UOS OTP 29 HTTP Staging Server active on 0.0.0.0:8999~n"),
    timer:sleep(infinity).
