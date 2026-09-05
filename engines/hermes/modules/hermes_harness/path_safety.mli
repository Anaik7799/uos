(** L3 contract candidate: path-safety predicates for the
    [tool_execution.path_and_url_safety] capability.

    Reference capability: [tool_execution.path_and_url_safety]
    Frozen anchor: [tools/path_security.py]

    [has_traversal_component] mirrors the frozen predicate
    [".." in Path(path_str).parts] -- a component-level check for a [..]
    traversal segment. Faithful reproduction: splitting on ['/'] and testing for
    a [".."] component yields the same answer as pathlib's [parts] for this
    predicate (pathlib drops ['.']/[''] components and collapses [//], none of
    which is [".."]; it never synthesises a [".."] that a raw split would miss).
    The differential fixtures prove it across tricky inputs rather than assuming. *)

val has_traversal_component : string -> bool
(*@ found = has_traversal_component path
    pure *)
