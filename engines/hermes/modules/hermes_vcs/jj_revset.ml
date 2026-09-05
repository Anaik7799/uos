type node =
  | Working_copy
  | Commit of Jj_id.Commit.t
  | Change of Jj_id.Change.t
  | Bookmark of Jj_id.Bookmark.t
  | Remote_bookmark of Jj_id.Remote.t * Jj_id.Bookmark.t
  | Parent of node
  | Ancestors of node
  | Descendants of node
  | Union of node list
  | Intersection of node list
  | Difference of node * node
  | Limit of int * node

type t = { node : node; depth : int; nodes : int }

type error = Empty_set | Too_many_terms | Too_complex | Invalid_limit

let maximum_terms = 64
let maximum_limit = 4096
let maximum_depth = 64
let maximum_nodes = 4096

let leaf node = { node; depth = 1; nodes = 1 }
let working_copy = leaf Working_copy
let commit value = leaf (Commit value)
let change value = leaf (Change value)
let bookmark value = leaf (Bookmark value)
let remote_bookmark ~remote ~bookmark = leaf (Remote_bookmark (remote, bookmark))

let bounded ~node ~depth ~nodes =
  if depth > maximum_depth || nodes > maximum_nodes then Error Too_complex
  else Ok { node; depth; nodes }

let unary make value =
  bounded ~node:(make value.node) ~depth:(value.depth + 1)
    ~nodes:(value.nodes + 1)

let parent value = unary (fun node -> Parent node) value
let ancestors value = unary (fun node -> Ancestors node) value
let descendants value = unary (fun node -> Descendants node) value

let bounded_set make values =
  match List.length values with
  | 0 -> Error Empty_set
  | count when count > maximum_terms -> Error Too_many_terms
  | _ ->
      let depth = 1 + List.fold_left (fun acc value -> max acc value.depth) 0 values in
      let nodes = 1 + List.fold_left (fun acc value -> acc + value.nodes) 0 values in
      bounded ~node:(make (List.map (fun value -> value.node) values)) ~depth ~nodes

let union values = bounded_set (fun items -> Union items) values
let intersection values = bounded_set (fun items -> Intersection items) values
let difference left right =
  bounded ~node:(Difference (left.node, right.node))
    ~depth:(1 + max left.depth right.depth)
    ~nodes:(1 + left.nodes + right.nodes)

let limit ~max_count value =
  if max_count <= 0 || max_count > maximum_limit then Error Invalid_limit
  else
    bounded ~node:(Limit (max_count, value.node)) ~depth:(value.depth + 1)
      ~nodes:(value.nodes + 1)

let rec canonical = function
  | Working_copy -> Jj_id.length_frame [ "working-copy" ]
  | Commit value ->
      Jj_id.length_frame [ "commit"; Jj_id.Commit.to_string value ]
  | Change value ->
      Jj_id.length_frame [ "change"; Jj_id.Change.to_string value ]
  | Bookmark value ->
      Jj_id.length_frame [ "bookmark"; Jj_id.Bookmark.to_string value ]
  | Remote_bookmark (remote, bookmark) ->
      Jj_id.length_frame
        [ "remote-bookmark"; Jj_id.Remote.to_string remote;
          Jj_id.Bookmark.to_string bookmark ]
  | Parent value -> Jj_id.length_frame [ "parent"; canonical value ]
  | Ancestors value -> Jj_id.length_frame [ "ancestors"; canonical value ]
  | Descendants value -> Jj_id.length_frame [ "descendants"; canonical value ]
  | Union values ->
      Jj_id.length_frame ("union" :: List.map canonical values)
  | Intersection values ->
      Jj_id.length_frame ("intersection" :: List.map canonical values)
  | Difference (left, right) ->
      Jj_id.length_frame [ "difference"; canonical left; canonical right ]
  | Limit (count, value) ->
      Jj_id.length_frame [ "limit"; string_of_int count; canonical value ]

let equal left right = String.equal (canonical left.node) (canonical right.node)

let digest value =
  canonical value.node |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let source_digest =
  Jj_id.length_frame
    [ "jj-revset-authority-v1"; Jj_id.source_digest;
      "bounds"; string_of_int maximum_terms; string_of_int maximum_limit;
      string_of_int maximum_depth; string_of_int maximum_nodes;
      "constructors";
      Jj_id.length_frame
        [ "working-copy"; "commit"; "change"; "bookmark";
          "remote-bookmark"; "parent"; "ancestors"; "descendants";
          "union"; "intersection"; "difference"; "limit" ];
      "errors";
      Jj_id.length_frame
        [ "empty-set"; "too-many-terms"; "too-complex"; "invalid-limit" ] ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
