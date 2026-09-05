(* HW.3.7.1 — typed cross-reference roles (mirror: zigvm note_ref.ml).
   The ONE payload grammar for `[[...]]` references, and kind-scoped
   resolution where a wrong-kind resolution is a FAILURE, not a fallback:
   `kind(resolve_k(x)) = k`.

   Grammar:  [!] [doc:|term:] target[#fragment] [ |display | |@rel ]

   The role set is CLOSED and lowercase — `[[re: subject]]` is a plain
   target containing a colon (protects real titles), and `Doc:` is not a
   role. TOTAL: every payload parses; malformed role forms degrade to a
   plain Any target, exactly as note_ref degrades a malformed slug. *)

type kind = Doc | Term | Any

type t = {
  kind : kind;
  target : string;
  display : string option;
  rel : string option;
  suppress : bool;
}

let strip_prefix p s =
  let np = String.length p and ns = String.length s in
  if ns >= np && String.sub s 0 np = p then Some (String.sub s np (ns - np))
  else None

let parse payload =
  (* Split on the FIRST '|' with split_payload's exact discipline: the
     target side is trimmed, the rest is kept raw ("X| @rel" has rel None
     today and must keep it — G15). *)
  let pre, post =
    match String.index_opt payload '|' with
    | Some i ->
        ( String.sub payload 0 i,
          Some (String.sub payload (i + 1) (String.length payload - i - 1)) )
    | None -> (payload, None)
  in
  let raw = String.trim pre in
  (* `!` needs a nonempty remainder — a bare "!" is prose, not an opt-out. *)
  let suppress, raw =
    if String.length raw > 1 && raw.[0] = '!' then
      (true, String.trim (String.sub raw 1 (String.length raw - 1)))
    else (false, raw)
  in
  let kind, target =
    let role k p =
      match strip_prefix p raw with
      | Some rest when String.trim rest <> "" -> Some (k, String.trim rest)
      | _ -> None
    in
    match role Doc "doc:" with
    | Some kt -> kt
    | None -> ( match role Term "term:" with Some kt -> kt | None -> (Any, raw))
  in
  let rel, display =
    match post with
    | Some rest when String.length rest > 0 && rest.[0] = '@' ->
        (Some (String.sub rest 1 (String.length rest - 1)), None)
    | Some rest when rest <> "" -> (None, Some rest)
    | _ -> (None, None)
  in
  { kind; target; display; rel; suppress }

let kind_name = function Doc -> "doc" | Term -> "term" | Any -> "any"

let to_wiki r =
  let sup = if r.suppress then "!" else "" in
  let role = match r.kind with Doc -> "doc:" | Term -> "term:" | Any -> "" in
  let tail =
    match (r.rel, r.display) with
    | Some rel, _ -> "|@" ^ rel
    | None, Some d -> "|" ^ d
    | None, None -> ""
  in
  "[[" ^ sup ^ role ^ r.target ^ tail ^ "]]"

(* ------------------------------------------------------- resolution *)

type candidate = { ckind : kind; cslug : string; canchor : string option }

type spaces = {
  docs : (string * string) list;
  terms : (string * (string * string)) list;
}

let resolve spaces k key =
  let docs () =
    List.filter_map (fun (kk, slug) -> if kk = key then Some slug else None) spaces.docs
    |> List.sort_uniq compare
    |> List.map (fun s -> { ckind = Doc; cslug = s; canchor = None })
  in
  let terms () =
    List.filter_map
      (fun (t, (slug, anchor)) -> if t = key then Some (slug, anchor) else None)
      spaces.terms
    |> List.sort_uniq compare
    |> List.map (fun (s, a) -> { ckind = Term; cslug = s; canchor = Some a })
  in
  match k with
  | Doc -> docs ()
  | Term -> terms ()
  (* Any is the UNION: a doc and a term sharing a name are two candidates
     — ambiguity at the reference site (HW.3.7.2), never a preference. *)
  | Any -> docs () @ terms ()
