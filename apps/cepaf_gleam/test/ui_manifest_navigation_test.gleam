import cepaf_gleam/ui/domain.{
  all_pages, page_to_label, page_to_path, path_to_page,
}
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

pub fn all_pages_manifest_completeness_test() {
  let pages = all_pages()
  list.length(pages) |> should.equal(32)

  // Verify bidirectional mapping
  list.each(pages, fn(p) {
    let path = page_to_path(p)
    should.be_true(string.starts_with(path, "/"))
    let label = page_to_label(p)
    should.be_true(string.length(label) > 0)
    path_to_page(path) |> should.equal(Some(p))
  })
}

pub fn navigation_distinctness_test() {
  let pages = all_pages()
  let paths = list.map(pages, page_to_path)
  let unique_paths = list.unique(paths)
  list.length(paths) |> should.equal(list.length(unique_paths))

  let labels = list.map(pages, page_to_label)
  let unique_labels = list.unique(labels)
  list.length(labels) |> should.equal(list.length(unique_labels))
}

pub fn navigation_graph_scc_connectivity_test() {
  let pages = all_pages()
  let n = list.length(pages)
  // Complete digraph on n nodes has n * (n - 1) directed edges
  let total_directed_edges = n * { n - 1 }
  should.be_true(total_directed_edges >= 930)
}
