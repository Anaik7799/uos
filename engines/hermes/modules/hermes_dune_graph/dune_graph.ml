(* The dune library graph. See the .mli: fail closed, because a parser that
   skips what it does not understand shrinks every cone derived from it. *)

type stanza_kind = Library | Executable | Other of string

type parse_error =
  | Unterminated_sexp of string
  | Unexpected_close of string
  | Library_without_name of string
  | Malformed_libraries of string * string

let string_of_parse_error = function
  | Unterminated_sexp file -> "unterminated s-expression in " ^ file
  | Unexpected_close file -> "unbalanced closing paren in " ^ file
  | Library_without_name file -> "a (library ...) stanza has no readable (name ...) in " ^ file
  | Malformed_libraries (file, name) ->
      Printf.sprintf "malformed (libraries ...) for %s in %s" name file

type library = { lib_name : string; lib_file : string; depends_on : string list }

(* ------------------------------------------------------------ s-expressions *)

type sexp = Atom of string | List of sexp list

exception Refused of parse_error

(* Comments run to end of line; dune has no nested comment form. Strings are
   opaque so a paren inside one cannot unbalance the file. *)
let parse_sexps ~file source =
  let n = String.length source in
  let pos = ref 0 in
  let rec skip () =
    if !pos < n then
      match source.[!pos] with
      | ' ' | '\t' | '\n' | '\r' -> incr pos; skip ()
      | ';' ->
          while !pos < n && source.[!pos] <> '\n' do incr pos done;
          skip ()
      | _ -> ()
  in
  let read_string () =
    let b = Buffer.create 32 in
    incr pos;
    let rec go () =
      if !pos >= n then raise (Refused (Unterminated_sexp file))
      else
        match source.[!pos] with
        | '\\' when !pos + 1 < n ->
            Buffer.add_char b source.[!pos + 1]; pos := !pos + 2; go ()
        | '"' -> incr pos
        | c -> Buffer.add_char b c; incr pos; go ()
    in
    go (); Buffer.contents b
  in
  let read_atom () =
    let start = !pos in
    while
      !pos < n
      && (match source.[!pos] with
          | ' ' | '\t' | '\n' | '\r' | '(' | ')' | ';' -> false
          | _ -> true)
    do incr pos done;
    String.sub source start (!pos - start)
  in
  let rec read_sexp () =
    skip ();
    if !pos >= n then raise (Refused (Unterminated_sexp file))
    else
      match source.[!pos] with
      | '(' ->
          incr pos;
          let items = ref [] in
          let rec loop () =
            skip ();
            if !pos >= n then raise (Refused (Unterminated_sexp file))
            else if source.[!pos] = ')' then (incr pos; List (List.rev !items))
            else (items := read_sexp () :: !items; loop ())
          in
          loop ()
      | ')' -> raise (Refused (Unexpected_close file))
      | '"' -> Atom (read_string ())
      | _ -> Atom (read_atom ())
  in
  let rec top acc =
    skip ();
    if !pos >= n then List.rev acc
    else if source.[!pos] = ')' then raise (Refused (Unexpected_close file))
    else top (read_sexp () :: acc)
  in
  top []

(* ------------------------------------------------------------------ reading *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let rec dune_files directory =
  match Sys.readdir directory with
  | exception _ -> []
  | entries ->
      Array.to_list entries |> List.sort String.compare
      |> List.concat_map (fun entry ->
             let path = Filename.concat directory entry in
             if (try Sys.is_directory path with _ -> false) then dune_files path
             else if entry = "dune" then [ path ]
             else [])

(* A (libraries ...) field mixes plain atoms with forms like
   (re_export foo) and (select ... from ...). Atoms are taken; re_export is
   unwrapped because it IS a dependency; anything else refuses rather than
   being dropped, since dropping is how a cone silently shrinks. *)
let rec dependency_names ~file ~name items =
  List.concat_map
    (function
      | Atom a -> [ a ]
      | List (Atom "re_export" :: rest) -> dependency_names ~file ~name rest
      | List _ -> raise (Refused (Malformed_libraries (file, name))))
    items

let stanza_head = function
  | List (Atom head :: _) -> Some head
  | _ -> None

let field name items =
  List.find_map
    (function List (Atom key :: rest) when key = name -> Some rest | _ -> None)
    items

let scan ~root =
  let libs = ref [] and heads = ref [] in
  List.iter
    (fun file ->
      let source = read_file file in
      List.iter
        (fun stanza ->
          match stanza_head stanza with
          | Some "library" ->
              let items = match stanza with List (_ :: rest) -> rest | _ -> [] in
              let name =
                match field "name" items with
                | Some [ Atom n ] -> n
                | _ -> raise (Refused (Library_without_name file))
              in
              let depends_on =
                match field "libraries" items with
                | None -> []
                | Some items -> dependency_names ~file ~name items
              in
              libs := { lib_name = name; lib_file = file; depends_on } :: !libs
          | Some head ->
              if not (List.mem head !heads) then heads := head :: !heads
          | None -> ())
        (parse_sexps ~file source))
    (dune_files root);
  (List.rev !libs, List.sort String.compare !heads)

let libraries ~root =
  try Ok (fst (scan ~root)) with Refused e -> Error e

let ignored_heads ~root =
  try Ok (snd (scan ~root)) with Refused e -> Error e

(* -------------------------------------------------------------------- graph *)

module StringSet = Set.Make (String)

type t = { names : StringSet.t; forward : (string * string list) list }

let of_libraries libs =
  let names = StringSet.of_list (List.map (fun l -> l.lib_name) libs) in
  (* External packages (yojson, unix, z3…) are not nodes: they have no dune
     stanza here, so nothing in this repository can be in their cone. Filtering
     is done ONCE, here, rather than at each use site. *)
  let forward =
    List.map
      (fun l ->
        (l.lib_name, List.filter (fun d -> StringSet.mem d names) l.depends_on))
      libs
  in
  { names; forward }

let nodes g = StringSet.elements g.names
let is_node g x = StringSet.mem x g.names

let edges g =
  List.concat_map
    (fun (dependent, deps) -> List.map (fun d -> (dependent, d)) deps)
    g.forward

let dependents g x =
  g.forward
  |> List.filter_map (fun (dependent, deps) ->
         if List.mem x deps then Some dependent else None)
  |> List.sort_uniq String.compare

(* Reverse reachability by fixpoint. The seeds are excluded from the result:
   a library is not in its own blast radius. *)
let cone_of_set g seeds =
  let seeds = List.filter (is_node g) seeds in
  let rec grow frontier acc =
    let next =
      List.concat_map (fun x -> dependents g x) frontier
      |> List.filter (fun x -> not (StringSet.mem x acc))
      |> List.sort_uniq String.compare
    in
    if next = [] then acc
    else grow next (List.fold_left (fun s x -> StringSet.add x s) acc next)
  in
  let reached = grow seeds StringSet.empty in
  StringSet.elements (List.fold_left (fun s x -> StringSet.remove x s) reached seeds)

let cone g x = cone_of_set g [ x ]

(* --------------------------------------------------------- formal crosscheck *)

let symbol = String.map (fun c -> if c = '.' || c = '-' then '_' else c)

let smt2_acyclic g =
  let b = Buffer.create 8192 in
  Buffer.add_string b "(set-logic QF_LIA)\n";
  Buffer.add_string b
    ";; One integer rank per library. An edge is a strict inequality, so a\n\
     ;; model IS a topological order and sat proves acyclicity; unsat proves\n\
     ;; a cycle. Mirrors Dependency_smt, independent of the traversal.\n";
  List.iter
    (fun name -> Buffer.add_string b (Printf.sprintf "(declare-const r_%s Int)\n" (symbol name)))
    (nodes g);
  List.iter
    (fun (dependent, dependency) ->
      Buffer.add_string b
        (Printf.sprintf "(assert (> r_%s r_%s)) ; %s depends on %s\n"
           (symbol dependent) (symbol dependency) dependent dependency))
    (edges g);
  Buffer.add_string b "(check-sat)\n";
  Buffer.contents b
