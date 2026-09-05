val is_git_clean : string -> (bool, string) result
val get_head_sha : string -> (string, string) result
val write_receipt : string -> string -> (unit, string) result
val run_gate : repo_path:string -> state_root:string -> (string, string) result