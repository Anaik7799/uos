#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;
#require "compiler-libs.common";;
#require "str";;

(* @agent_intent Read-only inventory of explicitly selected ZigVM OCaml sources.
   @laws Bounded reads; no source execution; stable source identity; fail closed;
   source-site counts are never represented as executed or passing test counts. *)
open Bos
open Parsetree
open Yojson.Basic.Util

let get = function Ok x -> x | Error (`Msg s) -> failwith s
let read path =
  let st = Unix.lstat path in
  if st.Unix.st_kind <> Unix.S_REG || st.Unix.st_size > 4_000_000 then
    failwith ("Unexpected source kind or size: " ^ path);
  get (OS.File.read (Fpath.v path))
let root = "/home/an/dev/ver/zigvm"
let has text needle =
  try ignore (Str.search_forward (Str.regexp_string needle) text 0); true
  with Not_found -> false
let compact s = Str.global_replace (Str.regexp "[ \t\r\n]+") " " s
let clip n s = if String.length s <= n then s else String.sub s 0 n ^ "..."
let rec lid = function
  | Longident.Lident s -> s
  | Longident.Ldot (p, s) -> lid p.txt ^ "." ^ s.txt
  | Longident.Lapply (a, b) -> lid a.txt ^ "(" ^ lid b.txt ^ ")"
let fname e = match e.pexp_desc with
  | Pexp_ident l -> lid l.txt | _ -> ""
let literal e = match e.pexp_desc with
  | Pexp_constant { pconst_desc = Pconst_string (s, _, _); _ } -> Some s
  | _ -> None
let slice source loc =
  let a = loc.Location.loc_start.Lexing.pos_cnum in
  let b = loc.Location.loc_end.Lexing.pos_cnum in
  if a < 0 || b < a || b > String.length source then "<location-unavailable>"
  else clip 180 (compact (String.sub source a (b - a)))
let clean_directives source =
  source |> String.split_on_char '\n'
  |> List.map (fun line ->
    if String.starts_with ~prefix:"#!" line || String.starts_with ~prefix:"#use " line
       || String.starts_with ~prefix:"#require " line || String.starts_with ~prefix:"#directory " line
    then String.make (String.length line) ' ' else line)
  |> String.concat "\n"
let sha path =
  let out = get (OS.Cmd.(run_out Cmd.(v "sha256sum" % "--" % path) |> out_string |> success)) in
  if String.length out < 64 then failwith "Missing digest";
  String.sub out 0 64
let jstr s = `String s
let assoc k v = k, v
let analyze spec =
  let rel = spec |> member "path" |> to_string in
  if not (String.starts_with ~prefix:"harness/" rel || String.starts_with ~prefix:"scripts/" rel)
     || has rel ".." || not (String.ends_with ~suffix:".ml" rel) then failwith ("Invalid path " ^ rel);
  let path = root ^ "/" ^ rel in
  let before = sha path in
  let source = read path in
  let lexbuf = Lexing.from_string (clean_directives source) in
  Location.init lexbuf path;
  let tree = Parse.implementation lexbuf in
  let scopes = match spec |> member "scopes" with `List xs -> List.map to_string xs | _ -> [] in
  let sites = ref [] and entrypoints = ref [] in
  let top_scope = ref "<module>" in
  let add kind label e =
    sites := `Assoc ["kind", jstr kind; "label", jstr (clip 240 label);
      "scope", jstr !top_scope; "line", `Int e.pexp_loc.loc_start.pos_lnum;
      "end_line", `Int e.pexp_loc.loc_end.pos_lnum] :: !sites
  in
  let expr self e =
    (match e.pexp_desc with
    | Pexp_assert condition -> add "assertion_site" (slice source condition.pexp_loc) e
    | Pexp_apply (f, args) ->
      let f = fname f in
      let checks = ["check"; "require"; "check_law"; "bdd"; "law"; "expect"; "assert_true"; "assert_false"; "test_case"; "Alcotest.test_case"] in
      if List.mem f checks then (
        let label = List.find_map (fun (_, a) -> literal a) args in
        match label with
        | Some label -> add "named_check_site" label e
        | None -> add "dynamic_check_site" (slice source e.pexp_loc) e
      ) else if List.mem f ["Test.make"; "QCheck.Test.make"; "QCheck2.Test.make"] then (
        let label = List.find_map (fun (key, a) -> match key with
          | Asttypes.Labelled "name" -> literal a | _ -> None) args in
        add "property_declaration" (Option.value label ~default:(slice source e.pexp_loc)) e
      )
    | Pexp_tuple ((_, first) :: _) ->
      (match literal first with
       | Some label when List.exists (fun prefix -> String.starts_with ~prefix label)
           ["LAW "; "GUARD "; "MUT-"; "SCENARIO "; "PROPERTY "] ->
           add "named_law_tuple" label e
       | _ -> ())
    | _ -> ());
    Ast_iterator.default_iterator.expr self e
  in
  let iterator = { Ast_iterator.default_iterator with expr } in
  List.iter (fun item ->
    match item.pstr_desc with
    | Pstr_value (_, bindings) ->
      List.iter (fun b ->
        let name = match b.pvb_pat.ppat_desc with
          | Ppat_var n -> n.txt | _ -> "<toplevel>" in
        if scopes = [] || List.mem name scopes then (
          top_scope := name;
          entrypoints := `Assoc ["name", jstr name;
            "line", `Int b.pvb_loc.loc_start.pos_lnum] :: !entrypoints;
          iterator.expr iterator b.pvb_expr
        )) bindings
    | _ -> if scopes = [] then (
        top_scope := "<module>";
        iterator.structure_item iterator item
      )) tree;
  let after = sha path in
  if before <> after then failwith ("Source changed while reading: " ^ rel);
  let lines = String.split_on_char '\n' source in
  let signal_lines = List.mapi (fun i l -> i+1,l) lines
    |> List.filter (fun (_, l) -> has l "[UNIMPLEMENTED]" || has l "report-only"
      || has l "~name:" || has l "~count:")
    |> List.map (fun (i,l) -> `Assoc ["line", `Int i; "text", jstr (clip 200 (compact l))]) in
  let fields = to_assoc spec in
  `Assoc (fields @ ["sha256", jstr before; "bytes", `Int (String.length source);
    "parse_status", jstr "parsed"; "execution_status", jstr "UNRUN";
    "sites", `List (List.rev !sites); "top_level_bindings", `List (List.rev !entrypoints);
    "classification_signals", `List signal_lines;
    "contains_unimplemented_marker", `Bool (has source "[UNIMPLEMENTED]")])

let main () =
  if Array.length Sys.argv <> 3 then failwith "usage: inventory.ml SPEC.json OUTPUT.json";
  let input = Sys.argv.(1) and output = Sys.argv.(2) in
  if not (String.starts_with ~prefix:"/tmp/" output) then failwith "Output must be under /tmp";
  let specs = read input |> Yojson.Basic.from_string |> to_list in
  if List.length specs > 250 then failwith "Source limit exceeded";
  let records = List.map analyze specs in
  let source_paths = List.map (fun s -> s |> member "path" |> to_string) specs in
  let status_cmd = Cmd.(v "git" % "--no-optional-locks" % "-C" % root % "status"
    % "--porcelain=v1" % "--untracked-files=normal" % "--" %% of_list source_paths) in
  let source_status = get (OS.Cmd.(run_out status_cmd |> out_string |> success)) in
  let result = `Assoc ["schema", jstr "uos.ocaml-web-test-inventory.v1";
    "source_root", jstr root;
    "source_revision", jstr (get (OS.Cmd.(run_out Cmd.(v "git" % "--no-optional-locks" % "-C" % root % "rev-parse" % "HEAD") |> out_string |> success)) |> String.trim);
    "method", jstr "OCaml compiler AST parsed without loading or executing source; explicit inventory scope; unique source sites, not runtime counts";
    "source_file_status", jstr source_status;
    "records", `List records] in
  get (OS.File.write (Fpath.v output) (Yojson.Basic.pretty_to_string result ^ "\n"));
  List.iter (fun r ->
    let sites = r |> member "sites" |> to_list in
    let count k = List.length (List.filter (fun s -> s |> member "kind" |> to_string = k) sites) in
    Printf.printf "%s\t%s\tnamed=%d dynamic=%d assert=%d property=%d stub=%b\n"
      (r |> member "path" |> to_string) (r |> member "category" |> to_string)
      (count "named_check_site") (count "dynamic_check_site")
      (count "assertion_site") (count "property_declaration") (r |> member "contains_unimplemented_marker" |> to_bool)) records

let () = try main () with exn ->
  Location.report_exception Format.err_formatter exn; exit 1
