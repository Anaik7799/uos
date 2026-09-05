-module(zigvm_process_SUITE).
-export([all/0, c_check_process_code/1, c_request_system_task/1]).
all() -> [c_check_process_code, c_request_system_task].
c_check_process_code(_) -> true.
c_request_system_task(_) -> true.
