import cepaf_gleam/ui/lustre/navigational_omnisearch
import gleeunit/should

pub fn bm25_score_computation_test() {
  let doc =
    navigational_omnisearch.SearchDocument(
      id: "DOC-01",
      title: "Category Route Navigation",
      content: "Functor mapping and sheaf gluing condition for route verification.",
      route: "/verify-patrol",
      pagerank: 0.85,
      betweenness: 0.12,
    )
  let score =
    navigational_omnisearch.compute_bm25_score("route navigation", doc)
  should.be_true(score >. 0.0)
}

pub fn search_corpus_query_test() {
  let corpus = navigational_omnisearch.canonical_search_corpus()
  let results = navigational_omnisearch.execute_omnisearch("storage", corpus)
  should.be_true(navigational_omnisearch.results_count(results) >= 1)
}

pub fn route_category_reachability_test() {
  let doc =
    navigational_omnisearch.SearchDocument(
      id: "DOC-02",
      title: "Storage NVMe Lock",
      content: "Hardware lock on root OS NVMe 25503L801736",
      route: "/verify-patrol",
      pagerank: 0.92,
      betweenness: 0.28,
    )
  navigational_omnisearch.verify_route_reachability(doc)
  |> should.be_true()
}
