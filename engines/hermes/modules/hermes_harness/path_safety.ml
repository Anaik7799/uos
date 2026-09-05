(* Path-safety predicates: candidate for tool_execution.path_and_url_safety.

   has_traversal_component mirrors the frozen `".." in Path(path_str).parts`.
   Splitting on '/' and testing for a ".." component is faithful: pathlib drops
   '.'/'' components and collapses '//' (none of which is ".."), and never
   synthesises a ".." a raw split would miss. Proven by the differential
   fixtures, not assumed. *)

let has_traversal_component path = List.mem ".." (String.split_on_char '/' path)
