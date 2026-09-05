/// TUI view for Smriti Knowledge plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/smriti.{type SmritiModel}
import gleam/float
import gleam/int
import gleam/string

pub fn render(model: SmritiModel) -> String {
  let header = visuals.with_color("  SMRITI KNOWLEDGE", "cyan")
  let catalog = render_catalog(model)
  let embeddings = render_embeddings(model)
  let searches = render_searches(model)
  let similarity = render_similarity(model)
  string.join([header, catalog, embeddings, searches, similarity], "\n")
}

fn render_catalog(model: SmritiModel) -> String {
  "  Catalog Entries: "
  <> visuals.with_color(int.to_string(model.catalog_entries), "blue")
}

fn render_embeddings(model: SmritiModel) -> String {
  let has = smriti.has_embeddings(model)
  let color = case has {
    True -> "green"
    False -> "yellow"
  }
  "  Embeddings: "
  <> visuals.with_color(int.to_string(model.embeddings_stored), color)
}

fn render_searches(model: SmritiModel) -> String {
  "  Search Queries: " <> int.to_string(model.search_queries)
}

fn render_similarity(model: SmritiModel) -> String {
  let pct = float.round(model.avg_similarity *. 100.0)
  let color = case model.avg_similarity {
    s if s >=. 0.8 -> "green"
    s if s >=. 0.5 -> "yellow"
    _ -> "red"
  }
  "  Avg Similarity: " <> visuals.with_color(int.to_string(pct) <> "%", color)
}
