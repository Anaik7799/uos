import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/mcp/types.{Complete, NonRetryable, Refused}
import gleam/dict
import gleeunit/should

pub fn traversal_symlink_hardlink_and_credential_paths_refused_test() {
  let corpus =
    knowledge.new_corpus("/workspace", ["public"], 4096, 8)
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: ".env",
      link_kind: knowledge.RegularFile,
      scope_tag: "public",
      content: "TOKEN=value",
    ))
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: "escape/symlink.txt",
      link_kind: knowledge.SymlinkEscape,
      scope_tag: "public",
      content: "outside",
    ))
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: "escape/hardlink.txt",
      link_kind: knowledge.HardlinkEscape,
      scope_tag: "public",
      content: "outside",
    ))

  let assert Refused(credential_error) =
    knowledge.execute(
      corpus,
      ["public"],
      "read_file",
      dict.from_list([#("path", ".env")]),
    )
  credential_error.code |> should.equal("PATH_SECURITY_VIOLATION")
  credential_error.retryability |> should.equal(NonRetryable)

  let assert Refused(traversal_error) =
    knowledge.execute(
      corpus,
      ["public"],
      "read_file",
      dict.from_list([#("path", "../outside.txt")]),
    )
  traversal_error.code |> should.equal("PATH_SECURITY_VIOLATION")

  let assert Refused(symlink_error) =
    knowledge.execute(
      corpus,
      ["public"],
      "read_file",
      dict.from_list([#("path", "escape/symlink.txt")]),
    )
  symlink_error.code |> should.equal("LINK_ESCAPE_REFUSED")

  let assert Refused(hardlink_error) =
    knowledge.execute(
      corpus,
      ["public"],
      "read_file",
      dict.from_list([#("path", "escape/hardlink.txt")]),
    )
  hardlink_error.code |> should.equal("LINK_ESCAPE_REFUSED")
  hardlink_error.retryability |> should.equal(NonRetryable)

  let assert Refused(outside_error) =
    knowledge.execute(
      corpus,
      ["public"],
      "read_file",
      dict.from_list([#("path", "/home/an/NAS-setup/uos-evil/doc.md")]),
    )
  outside_error.code |> should.equal("PATH_SECURITY_VIOLATION")
  outside_error.retryability |> should.equal(NonRetryable)

  let assert Refused(sqlite_error) =
    knowledge.execute(
      corpus,
      ["public"],
      "read_file",
      dict.from_list([#("path", "var/sa-plan/uos.sqlite3")]),
    )
  sqlite_error.code |> should.equal("PATH_SECURITY_VIOLATION")

  let assert Refused(key_error) =
    knowledge.execute(
      corpus,
      ["public"],
      "read_file",
      dict.from_list([#("path", "keys/id_ed25519")]),
    )
  key_error.code |> should.equal("PATH_SECURITY_VIOLATION")
}

pub fn transclusion_cycles_are_bounded_test() {
  let cyclic =
    knowledge.new_corpus("/workspace", ["public"], 4096, 8)
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: "A",
      link_kind: knowledge.RegularFile,
      scope_tag: "public",
      content: "A -> [[zk:B]]",
    ))
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: "B",
      link_kind: knowledge.RegularFile,
      scope_tag: "public",
      content: "B -> [[wiki:A]]",
    ))

  let assert Refused(cycle_error) =
    knowledge.execute(
      cyclic,
      ["public"],
      "zk_transclude",
      dict.from_list([#("key", "A")]),
    )
  cycle_error.code |> should.equal("TRANSCLUSION_CYCLE_OR_DEPTH_EXCEEDED")
  cycle_error.retryability |> should.equal(NonRetryable)

  let bounded =
    knowledge.new_corpus("/workspace", ["public"], 4096, 1)
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: "C",
      link_kind: knowledge.RegularFile,
      scope_tag: "public",
      content: "[[zk:D]]",
    ))
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: "D",
      link_kind: knowledge.RegularFile,
      scope_tag: "public",
      content: "[[zk:E]]",
    ))
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: "E",
      link_kind: knowledge.RegularFile,
      scope_tag: "public",
      content: "leaf",
    ))

  let assert Refused(depth_error) =
    knowledge.execute(
      bounded,
      ["public"],
      "zk_transclude",
      dict.from_list([#("key", "C")]),
    )
  depth_error.code |> should.equal("TRANSCLUSION_CYCLE_OR_DEPTH_EXCEEDED")
}

pub fn cross_principal_scope_cannot_expand_test() {
  let corpus =
    knowledge.new_corpus("/workspace", ["public", "successor-private"], 4096, 8)
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: "public/doc.md",
      link_kind: knowledge.RegularFile,
      scope_tag: "public",
      content: "shared",
    ))
    |> knowledge.with_entry(knowledge.CorpusEntry(
      rel_path: "restricted/doc.md",
      link_kind: knowledge.RegularFile,
      scope_tag: "successor-private",
      content: "restricted",
    ))

  let assert Complete(_, _) =
    knowledge.execute(
      corpus,
      ["public"],
      "read_file",
      dict.from_list([#("path", "public/doc.md")]),
    )

  let assert Refused(scope_error) =
    knowledge.execute(
      corpus,
      ["public"],
      "read_file",
      dict.from_list([#("path", "restricted/doc.md")]),
    )
  scope_error.code |> should.equal("CROSS_PRINCIPAL_SCOPE_FORBIDDEN")
  scope_error.retryability |> should.equal(NonRetryable)
}
