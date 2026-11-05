(* Bounded read-only configuration observation. This is not an authorization,
   runtime identity or enabled-client check. Raw configs/unowned fields and
   their hashes never leave this module. Paths are trusted local launcher input;
   cooperative owned directories are assumed, not hostile descriptor-relative
   VFS safety. Run native filesystem IO beneath an external process guardian. *)
module Audit = struct
  module P=Ecology_pin_edit.Pin
  type format=Json|Toml
  type reason=UnsafePath|ResourceBound|SourceChanged|Malformed|IoUnavailable
  type observation=Observed of P.metadata list|Absent|Held of reason
  type item={id:string;observation:observation}
  let item id observation={id;observation}
  let maximum=262144
  exception Stop of reason
  let need b why=if not b then raise(Stop why)
  let safe_component s=s<>"" && s<>"." && s<>".." &&
    String.for_all(fun c->Char.code c>=32 && Char.code c<>127 && c<>'\\')s
  let relative s=s<>"" && Filename.is_relative s && String.length s<=4096
    && List.for_all safe_component(String.split_on_char '/' s)
  let absolute s=String.length s>1 && s.[0]='/' && String.length s<=4096
    && List.for_all safe_component(List.tl(String.split_on_char '/' s))
  let directories path=
    let parts=String.split_on_char '/' path|>List.filter((<>)"")in
    ignore(List.fold_left(fun parent name->let path=Filename.concat parent name in
      need((Unix.lstat path).Unix.st_kind=Unix.S_DIR)UnsafePath;path)"/"parts)
  let metadata format body =
    match (match format with Json->P.inspect_all_json body|Toml->P.inspect_all_toml body)with
    |Ok metadata->Observed metadata|Error _->Held Malformed
  let same_file a b=a.Unix.st_dev=b.Unix.st_dev && a.st_ino=b.st_ino
    && a.st_size=b.st_size && a.st_mtime=b.st_mtime && a.st_ctime=b.st_ctime
    && a.st_uid=b.st_uid && a.st_gid=b.st_gid && a.st_perm=b.st_perm && a.st_nlink=b.st_nlink
  let observe ~root ~relative:rel ~format =try
    need(absolute root && relative rel)UnsafePath;
    directories root;
    let path=Filename.concat root rel in
    directories(Filename.dirname path);
    let before=Unix.lstat path in
    need(before.Unix.st_kind=Unix.S_REG && before.st_nlink=1 && before.st_uid=Unix.geteuid()
      && before.st_perm land 0o7022=0)UnsafePath;
    need(before.st_size>=0 && before.st_size<=maximum)ResourceBound;
    let fd=Unix.openfile path [Unix.O_RDONLY;Unix.O_CLOEXEC;Unix.O_NONBLOCK]0 in
    let body=Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
      let opened=Unix.fstat fd in need(same_file before opened)SourceChanged;
      let buffer=Buffer.create before.st_size and chunk=Bytes.create 8192 in
      let rec loop total=let n=Unix.read fd chunk 0(Bytes.length chunk)in
        if n>0 then(need(total+n<=maximum)ResourceBound;Buffer.add_subbytes buffer chunk 0 n;loop(total+n))in
      loop 0;need(same_file opened(Unix.fstat fd) && same_file opened(Unix.lstat path))SourceChanged;
      Buffer.contents buffer)in
    metadata format body
    with Stop reason->Held reason
    |Unix.Unix_error(Unix.ENOENT,_,_)->Absent
    |Unix.Unix_error _|Sys_error _->Held IoUnavailable
  type scope=Repository|Home
  let catalog=[
    "workspace_claude_mcp",Repository,".mcp.json",Json;
    "workspace_codex_config",Repository,".codex/config.toml",Toml;
    "workspace_agy_settings",Repository,".gemini/settings.json",Json;
    "workspace_pi_mcp",Repository,".pi/mcp.json",Json;
    "workspace_deepseek_mcp",Repository,".deepseek/mcp.json",Json;
    "home_agy_antigravity_mcp",Home,".gemini/antigravity-cli/mcp_config.json",Json;
    "home_agy_config_mcp",Home,".gemini/config/mcp_config.json",Json;
    "home_agy_settings",Home,".gemini/settings.json",Json;
    "home_codex_config",Home,".codex/config.toml",Toml;
    "home_claude_config",Home,".claude.json",Json;
    "home_pi_mcp",Home,".pi/agent/mcp.json",Json;
    "home_pi_mcp_adapter",Home,".pi/agent/mcp-adapter.json",Json]
  let canonical ~repository ~home =
    List.map(fun(id,scope,relative,format)->item id
      (if repository=home then Held UnsafePath else
       observe ~root:(match scope with Repository->repository|Home->home) ~relative ~format))catalog
  let reason=function UnsafePath->"unsafe_path_or_alias"|ResourceBound->"resource_bound"
    |SourceChanged->"source_changed"|Malformed->"unrecognized_or_malformed_owned_pins"
    |IoUnavailable->"io_unavailable"
  let export items =
    let row {id;observation}=`Assoc(["target_id",`String id]@(match observation with
      |Absent->["state",`String "ABSENT";"pins",`List[]]
      |Held why->["state",`String "HOLD";"reason",`String(reason why);"pins",`List[]]
      |Observed pins->["state",`String "OBSERVED";"pins",`List(List.map(fun(p:P.metadata)->`Assoc[
        "server",`String p.server;"capsule",`String p.capsule;"payload_sha256",`String p.payload_sha256])pins)]))in
    let observed=List.fold_left(fun n item->match item.observation with Observed _->n+1|_->n)0 items in
    let pins=List.concat_map(fun item->match item.observation with Observed pins->pins|_->[])items in
    let bindings=List.map(fun(p:P.metadata)->p.capsule,p.payload_sha256)pins|>List.sort_uniq compare in
    let expected=List.map(fun(id,_,_,_)->id)catalog|>List.sort String.compare in
    let actual=List.map(fun item->item.id)items|>List.sort String.compare in
    let exact_catalog=actual=expected in
    let catalog_count=List.length catalog in
    `Assoc["schema",`String "uos.ecology-pin-audit.v1";
      "status",`String(if exact_catalog && observed=catalog_count && List.length bindings=1
        then "OBSERVED_CONSISTENT_PINS_ONLY"else "HOLD");"authority",`String "NONE";
      "read_only",`Bool true;"runtime_readiness",`String "UNVERIFIED";
      "scope",`String "explicit_configuration_catalog_only_not_runtime_or_enabled_client_inventory";
      "configuration_targets",`Int(List.length items);"observed_targets",`Int observed;
      "exact_configuration_catalog",`Bool exact_catalog;
      "observed_server_slots",`Int(List.length pins);"distinct_observed_bindings",`Int(List.length bindings);
      "all_configuration_targets_observed",`Bool(exact_catalog && observed=catalog_count);
      "runtime_targets",`String "UNRUN_3_LOGICAL_TARGETS";
      "rows",`List(List.map row items)]
end
