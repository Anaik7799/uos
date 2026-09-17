import re

with open("apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/sciviz_comprehensive_explorer.gleam") as f:
    text = f.read()

# Add import for extension_examples if needed
if "extension_examples" not in text:
    imp_target = "import cepaf_gleam/sciviz/extension_catalog.{"
    rep_imp = "import cepaf_gleam/sciviz/extension_examples\nimport cepaf_gleam/sciviz/extension_catalog.{"
    text = text.replace(imp_target, rep_imp, 1)

# In view(): add render_deep_dive_table_view(deep_dives) after render_deep_dive_cards_grid(deep_dives)
old_view_grid = "      render_deep_dive_cards_grid(deep_dives),"
new_view_grid = (
    "      render_deep_dive_cards_grid(deep_dives),\n"
    "      render_deep_dive_table_view(deep_dives),"
)
assert old_view_grid in text, "Could not find render_deep_dive_cards_grid in view()"
text = text.replace(old_view_grid, new_view_grid, 1)

# In render_live_transpiler_section(): add the 2 new preset buttons
# After roc button (📈 ROC Diagnosis)
roc_btn_marker = '[element.text("📈 ROC Diagnosis")],'
assert roc_btn_marker in text, "Could not find roc preset button"

new_presets = """[element.text("📈 ROC Diagnosis")],
              ),
              html.button(
                [
                  attribute.class("transpiler-preset-btn"),
                  attribute.attribute("onclick", "setTranspilerPreset('eeg')"),
                  attribute.attribute(
                    "style",
                    "background: #1e293b; color: #a855f7; border: 1px solid #7e22ce; padding: 0.35rem 0.75rem; border-radius: 6px; font-size: 0.75rem; font-weight: 600; cursor: pointer;",
                  ),
                ],
                [element.text("🧠 EEG Brainwaves")],
              ),
              html.button(
                [
                  attribute.class("transpiler-preset-btn"),
                  attribute.attribute("onclick", "setTranspilerPreset('scrna')"),
                  attribute.attribute(
                    "style",
                    "background: #1e293b; color: #34d399; border: 1px solid #059669; padding: 0.35rem 0.75rem; border-radius: 6px; font-size: 0.75rem; font-weight: 600; cursor: pointer;",
                  ),
                ],
                [element.text("🔬 scRNA Single-Cell")],"""

text = text.replace(roc_btn_marker, new_presets, 1)

# In render_search_and_filter_toolbar(): add View Mode Toggle (Grid vs Table) and Sort Dropdown
old_toolbar_count = """          html.div([], [
            element.text("Showing "),
            html.span(
              [
                attribute.attribute("id", "sciviz-visible-count"),
                attribute.attribute(
                  "style",
                  "color: #38bdf8; font-weight: 800; font-family: monospace;",
                ),
              ],
              [element.text("167")],
            ),
            element.text(" of 167 extensions"),
          ]),"""

new_toolbar_controls = """          html.div(
            [attribute.attribute("style", "display: flex; align-items: center; gap: 0.5rem;")],
            [
              html.span([attribute.attribute("style", "color: #64748b; font-size: 0.75rem;")], [element.text("Sort:")]),
              html.select(
                [
                  attribute.attribute("id", "sciviz-sort-select"),
                  attribute.attribute("onchange", "sortSciViz(this.value)"),
                  attribute.attribute(
                    "style",
                    "background: #020617; color: #cbd5e1; border: 1px solid #475569; border-radius: 5px; padding: 0.3rem 0.5rem; font-size: 0.75rem; outline: none; font-family: monospace; cursor: pointer;",
                  ),
                ],
                [
                  html.option([attribute.attribute("value", "name-asc")], "Name (A-Z)"),
                  html.option([attribute.attribute("value", "name-desc")], "Name (Z-A)"),
                  html.option([attribute.attribute("value", "category")], "Category"),
                  html.option([attribute.attribute("value", "records")], "Records (High to Low)"),
                ],
              ),
            ],
          ),
          html.div(
            [attribute.attribute("style", "display: flex; align-items: center; background: #020617; border: 1px solid #334155; border-radius: 6px; padding: 0.15rem; gap: 0.2rem;")],
            [
              html.button(
                [
                  attribute.attribute("id", "view-mode-grid-btn"),
                  attribute.attribute("onclick", "setViewMode('grid')"),
                  attribute.attribute(
                    "style",
                    "background: #0284c7; color: #ffffff; border: 1px solid #38bdf8; border-radius: 4px; padding: 0.25rem 0.6rem; font-size: 0.75rem; font-weight: 700; cursor: pointer;",
                  ),
                ],
                [element.text("🔲 Grid View")],
              ),
              html.button(
                [
                  attribute.attribute("id", "view-mode-table-btn"),
                  attribute.attribute("onclick", "setViewMode('table')"),
                  attribute.attribute(
                    "style",
                    "background: #0f172a; color: #94a3b8; border: 1px solid #334155; border-radius: 4px; padding: 0.25rem 0.6rem; font-size: 0.75rem; font-weight: 700; cursor: pointer;",
                  ),
                ],
                [element.text("📋 Table View")],
              ),
            ],
          ),
          html.div([], [
            element.text("Showing "),
            html.span(
              [
                attribute.attribute("id", "sciviz-visible-count"),
                attribute.attribute(
                  "style",
                  "color: #38bdf8; font-weight: 800; font-family: monospace;",
                ),
              ],
              [element.text("167")],
            ),
            element.text(" of 167 extensions"),
          ]),"""

assert old_toolbar_count in text, "Could not find old_toolbar_count"
text = text.replace(old_toolbar_count, new_toolbar_controls, 1)

# In render_deep_dive_cards_grid: wrap in #sciviz-grid-view
old_grid = """fn render_deep_dive_cards_grid(dives: List(ExtensionDeepDive)) -> Element(a) {
  html.div(
    [
      attribute.attribute(
        "style",
        "display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 1.25rem;",
      ),
    ],
    list.map(dives, render_deep_dive_card),
  )
}"""

new_grid = """fn render_deep_dive_cards_grid(dives: List(ExtensionDeepDive)) -> Element(a) {
  html.div(
    [
      attribute.attribute("id", "sciviz-grid-view"),
      attribute.attribute(
        "style",
        "display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 1.25rem;",
      ),
    ],
    list.map(dives, render_deep_dive_card),
  )
}

fn render_deep_dive_table_view(dives: List(ExtensionDeepDive)) -> Element(a) {
  html.div(
    [
      attribute.attribute("id", "sciviz-table-view"),
      attribute.attribute(
        "style",
        "display: none; width: 100%; overflow-x: auto; background: #0b1329; border: 1px solid #1e293b; border-radius: 8px; margin-bottom: 2rem;",
      ),
    ],
    [
      html.table(
        [
          attribute.attribute(
            "style",
            "width: 100%; border-collapse: collapse; font-size: 0.82rem; text-align: left;",
          ),
        ],
        [
          html.thead(
            [
              attribute.attribute(
                "style",
                "background: #0f172a; border-bottom: 2px solid #334155;",
              ),
            ],
            [
              html.tr([], [
                html.th(
                  [
                    attribute.attribute(
                      "style",
                      "padding: 0.75rem 1rem; color: #38bdf8; font-family: monospace;",
                    ),
                  ],
                  [element.text("Extension")],
                ),
                html.th(
                  [
                    attribute.attribute(
                      "style",
                      "padding: 0.75rem 1rem; color: #94a3b8;",
                    ),
                  ],
                  [element.text("Category")],
                ),
                html.th(
                  [
                    attribute.attribute(
                      "style",
                      "padding: 0.75rem 1rem; color: #64748b;",
                    ),
                  ],
                  [element.text("Author")],
                ),
                html.th(
                  [
                    attribute.attribute(
                      "style",
                      "padding: 0.75rem 1rem; color: #cbd5e1;",
                    ),
                  ],
                  [element.text("Graph Types")],
                ),
                html.th(
                  [
                    attribute.attribute(
                      "style",
                      "padding: 0.75rem 1rem; color: #34d399;",
                    ),
                  ],
                  [element.text("Empirical Dataset")],
                ),
                html.th(
                  [
                    attribute.attribute(
                      "style",
                      "padding: 0.75rem 1rem; color: #94a3b8; text-align: center;",
                    ),
                  ],
                  [element.text("BDD Scenarios")],
                ),
                html.th(
                  [
                    attribute.attribute(
                      "style",
                      "padding: 0.75rem 1rem; color: #94a3b8; text-align: right;",
                    ),
                  ],
                  [element.text("Actions")],
                ),
              ]),
            ],
          ),
          html.tbody(
            [attribute.attribute("id", "sciviz-table-body")],
            list.map(dives, render_deep_dive_table_row),
          ),
        ],
      ),
    ],
  )
}

fn render_deep_dive_table_row(dive: ExtensionDeepDive) -> Element(a) {
  let bdds_joined = string.join(dive.bdd_scenarios, "|||")
  let feats_joined = string.join(dive.key_features, "|||")
  let code_sample =
    extension_examples.example_code(
      extension_catalog.ExtensionMetadata(
        name: dive.name,
        url: dive.url,
        author: dive.author,
        description: dive.dataset_schema_summary,
        tags: dive.visual_graph_types,
        category: dive.category,
      ),
    )

  html.tr(
    [
      attribute.class("sciviz-row"),
      attribute.attribute("data-testid", "sciviz-row"),
      attribute.attribute("data-name", string.lowercase(dive.name)),
      attribute.attribute("data-category", dive.category_name),
      attribute.attribute("data-author", string.lowercase(dive.author)),
      attribute.attribute("data-dataset", dive.dataset_name),
      attribute.attribute(
        "data-records",
        int.to_string(dive.dataset_record_count),
      ),
      attribute.attribute("data-bdds", bdds_joined),
      attribute.attribute("data-features", feats_joined),
      attribute.attribute("data-code", code_sample),
      attribute.attribute(
        "style",
        "border-bottom: 1px solid #1e293b; transition: background 0.15s ease;",
      ),
    ],
    [
      html.td(
        [
          attribute.attribute(
            "style",
            "padding: 0.75rem 1rem; font-family: monospace; font-weight: 700; color: #38bdf8;",
          ),
        ],
        [element.text(dive.name)],
      ),
      html.td(
        [attribute.attribute("style", "padding: 0.75rem 1rem;")],
        [
          html.span(
            [
              attribute.attribute(
                "style",
                "background: #1e293b; color: #94a3b8; font-size: 0.7rem; padding: 0.15rem 0.45rem; border-radius: 4px; font-weight: 600;",
              ),
            ],
            [element.text(dive.category_name)],
          ),
        ],
      ),
      html.td(
        [
          attribute.attribute(
            "style",
            "padding: 0.75rem 1rem; color: #64748b; font-size: 0.78rem;",
          ),
        ],
        [element.text(dive.author)],
      ),
      html.td(
        [
          attribute.attribute(
            "style",
            "padding: 0.75rem 1rem; color: #cbd5e1; font-size: 0.75rem;",
          ),
        ],
        [element.text(string.join(dive.visual_graph_types, ", "))],
      ),
      html.td(
        [
          attribute.attribute(
            "style",
            "padding: 0.75rem 1rem; font-family: monospace; font-size: 0.75rem; color: #34d399;",
          ),
        ],
        [
          element.text(
            dive.dataset_name
            <> " ("
            <> int.to_string(dive.dataset_record_count)
            <> ")",
          ),
        ],
      ),
      html.td(
        [
          attribute.attribute(
            "style",
            "padding: 0.75rem 1rem; text-align: center;",
          ),
        ],
        [
          html.span(
            [
              attribute.attribute(
                "style",
                "background: #064e3b; color: #34d399; padding: 0.15rem 0.45rem; border-radius: 4px; font-size: 0.72rem; font-weight: 700; font-family: monospace;",
              ),
            ],
            [
              element.text(
                "✓ "
                <> int.to_string(list.length(dive.bdd_scenarios))
                <> " BDD",
              ),
            ],
          ),
        ],
      ),
      html.td(
        [
          attribute.attribute(
            "style",
            "padding: 0.75rem 1rem; text-align: right; white-space: nowrap;",
          ),
        ],
        [
          html.button(
            [
              attribute.class("inspect-spec-btn"),
              attribute.attribute("onclick", "openInspectModal(this)"),
              attribute.attribute(
                "style",
                "background: #1e293b; color: #38bdf8; border: 1px solid #0284c7; padding: 0.2rem 0.5rem; border-radius: 4px; font-size: 0.7rem; font-weight: 700; cursor: pointer; margin-right: 0.5rem;",
              ),
            ],
            [element.text("Inspect Spec 🔍")],
          ),
          html.a(
            [
              attribute.href(dive.url),
              attribute.attribute(
                "style",
                "color: #94a3b8; text-decoration: none; font-size: 0.72rem;",
              ),
            ],
            [element.text("Upstream ↗")],
          ),
        ],
      ),
    ],
  )
}"""

assert old_grid in text, "Could not find old_grid"
text = text.replace(old_grid, new_grid, 1)

# In render_deep_dive_card: add data attributes & update inspect button
old_card_attrs = """      attribute.class("sciviz-card"),
      attribute.attribute("data-testid", "sciviz-card"),
      attribute.attribute("data-name", string.lowercase(dive.name)),
      attribute.attribute("data-category", dive.category_name),
      attribute.attribute("data-author", string.lowercase(dive.author)),"""

new_card_attrs = """      attribute.class("sciviz-card"),
      attribute.attribute("data-testid", "sciviz-card"),
      attribute.attribute("data-name", string.lowercase(dive.name)),
      attribute.attribute("data-category", dive.category_name),
      attribute.attribute("data-author", string.lowercase(dive.author)),
      attribute.attribute("data-dataset", dive.dataset_name),
      attribute.attribute(
        "data-records",
        int.to_string(dive.dataset_record_count),
      ),
      attribute.attribute("data-bdds", string.join(dive.bdd_scenarios, "|||")),
      attribute.attribute("data-features", string.join(dive.key_features, "|||")),
      attribute.attribute(
        "data-code",
        extension_examples.example_code(
          extension_catalog.ExtensionMetadata(
            name: dive.name,
            url: dive.url,
            author: dive.author,
            description: dive.dataset_schema_summary,
            tags: dive.visual_graph_types,
            category: dive.category,
          ),
        ),
      ),"""

assert old_card_attrs in text, "Could not find old_card_attrs"
text = text.replace(old_card_attrs, new_card_attrs, 1)

# Replace inspect button in render_deep_dive_card to use openInspectModal(this)
old_card_btn = """              html.button(
                [
                  attribute.class("inspect-spec-btn"),
                  attribute.attribute(
                    "onclick",
                    "openInspectModal('"
                      <> dive.name
                      <> "', '"
                      <> dive.category_name
                      <> "', '"
                      <> dive.author
                      <> "', '"
                      <> dive.dataset_name
                      <> "', "
                      <> int.to_string(dive.dataset_record_count)
                      <> ")",
                  ),
                  attribute.attribute(
                    "style",
                    "background: #1e293b; color: #38bdf8; border: 1px solid #0284c7; padding: 0.2rem 0.5rem; border-radius: 4px; font-size: 0.7rem; font-weight: 700; cursor: pointer;",
                  ),
                ],
                [element.text("Inspect Spec 🔍")],
              ),"""

new_card_btn = """              html.button(
                [
                  attribute.class("inspect-spec-btn"),
                  attribute.attribute("onclick", "openInspectModal(this)"),
                  attribute.attribute(
                    "style",
                    "background: #1e293b; color: #38bdf8; border: 1px solid #0284c7; padding: 0.2rem 0.5rem; border-radius: 4px; font-size: 0.7rem; font-weight: 700; cursor: pointer;",
                  ),
                ],
                [element.text("Inspect Spec 🔍")],
              ),"""

assert old_card_btn in text, "Could not find old_card_btn"
text = text.replace(old_card_btn, new_card_btn, 1)

# In render_interactive_modal_container: add #modal-bdd-scenarios container, #modal-key-features container, and copy button
old_modal_bdds = """          html.div([attribute.attribute("style", "margin-bottom: 1.25rem;")], [
            html.div(
              [
                attribute.attribute(
                  "style",
                  "font-size: 0.75rem; color: #94a3b8; font-weight: 700; text-transform: uppercase; margin-bottom: 0.5rem;",
                ),
              ],
              [element.text("BDD Test Scenarios (100% Machine-Checked)")],
            ),
            html.div(
              [
                attribute.attribute(
                  "style",
                  "background: #020617; border: 1px solid #1e293b; border-radius: 6px; padding: 0.75rem; font-family: monospace; font-size: 0.8rem; color: #38bdf8; line-height: 1.6;",
                ),
              ],
              [
                html.div([], [element.text("✔ Scenario: Exact visual layout rendering without client JavaScript")]),
                html.div([], [element.text("✔ Scenario: Statistical coordinate transformation and scale mapping")]),
                html.div([], [element.text("✔ Scenario: Large empirical dataset ingestion and zero memory leak verification")]),
              ],
            ),
          ]),"""

new_modal_bdds = """          html.div([attribute.attribute("style", "margin-bottom: 1.25rem;")], [
            html.div(
              [
                attribute.attribute(
                  "style",
                  "font-size: 0.75rem; color: #94a3b8; font-weight: 700; text-transform: uppercase; margin-bottom: 0.5rem;",
                ),
              ],
              [element.text("BDD Test Scenarios (100% Machine-Checked)")],
            ),
            html.div(
              [
                attribute.attribute("id", "modal-bdd-scenarios"),
                attribute.attribute(
                  "style",
                  "background: #020617; border: 1px solid #1e293b; border-radius: 6px; padding: 0.75rem; font-family: monospace; font-size: 0.8rem; color: #38bdf8; line-height: 1.6;",
                ),
              ],
              [
                html.div([], [element.text("✔ Scenario: Exact visual layout rendering without client JavaScript")]),
                html.div([], [element.text("✔ Scenario: Statistical coordinate transformation and scale mapping")]),
                html.div([], [element.text("✔ Scenario: Large empirical dataset ingestion and zero memory leak verification")]),
              ],
            ),
          ]),
          html.div([attribute.attribute("style", "margin-bottom: 1.25rem;")], [
            html.div(
              [
                attribute.attribute(
                  "style",
                  "font-size: 0.75rem; color: #94a3b8; font-weight: 700; text-transform: uppercase; margin-bottom: 0.5rem;",
                ),
              ],
              [element.text("Key Features Profile")],
            ),
            html.div(
              [
                attribute.attribute("id", "modal-key-features"),
                attribute.attribute(
                  "style",
                  "display: flex; flex-wrap: wrap; gap: 0.4rem;",
                ),
              ],
              [],
            ),
          ]),"""

assert old_modal_bdds in text, "Could not find old_modal_bdds"
text = text.replace(old_modal_bdds, new_modal_bdds, 1)

# In modal snippet header: add Copy Pipeline button
old_snippet_header = """            html.div(
              [
                attribute.attribute(
                  "style",
                  "font-size: 0.75rem; color: #94a3b8; font-weight: 700; text-transform: uppercase; margin-bottom: 0.5rem;",
                ),
              ],
              [element.text("Declarative ggplot2 / Gleam Pipeline Snippet")],
            ),"""

new_snippet_header = """            html.div(
              [
                attribute.attribute(
                  "style",
                  "display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;",
                ),
              ],
              [
                html.span(
                  [
                    attribute.attribute(
                      "style",
                      "font-size: 0.75rem; color: #94a3b8; font-weight: 700; text-transform: uppercase;",
                    ),
                  ],
                  [element.text("Declarative ggplot2 / Gleam Pipeline Snippet")],
                ),
                html.button(
                  [
                    attribute.attribute("id", "copy-pipeline-btn"),
                    attribute.attribute("onclick", "copyPipelineSnippet()"),
                    attribute.attribute(
                      "style",
                      "background: #1e293b; color: #38bdf8; border: 1px solid #0284c7; border-radius: 4px; padding: 0.2rem 0.5rem; font-size: 0.72rem; font-weight: 700; cursor: pointer;",
                    ),
                  ],
                  [element.text("Copy Pipeline 📋")],
                ),
              ],
            ),"""

assert old_snippet_header in text, "Could not find old_snippet_header"
text = text.replace(old_snippet_header, new_snippet_header, 1)

# Now replace render_interactive_client_script with updated JS
client_script_start = text.find("fn render_interactive_client_script() -> Element(a) {")
assert client_script_start != -1

new_client_script = """fn render_interactive_client_script() -> Element(a) {
  element.unsafe_raw_html(
    "",
    "script",
    [],
    "
    let currentCategory = 'all';
    let currentQuery = '';
    let currentViewMode = 'grid';

    function filterCategory(cat, btn) {
      currentCategory = cat;
      document.querySelectorAll('.sciviz-cat-btn').forEach(b => {
        b.style.background = '#0f172a';
        b.style.borderColor = '#334155';
        b.style.color = '#cbd5e1';
      });
      if (btn) {
        btn.style.background = '#0284c7';
        btn.style.borderColor = '#38bdf8';
        btn.style.color = '#ffffff';
      }
      applyFilters();
    }

    function filterSearch(query) {
      currentQuery = query.toLowerCase().trim();
      applyFilters();
    }

    function setViewMode(mode) {
      currentViewMode = mode;
      const grid = document.getElementById('sciviz-grid-view');
      const table = document.getElementById('sciviz-table-view');
      const gridBtn = document.getElementById('view-mode-grid-btn');
      const tableBtn = document.getElementById('view-mode-table-btn');

      if (mode === 'grid') {
        if (grid) grid.style.display = 'grid';
        if (table) table.style.display = 'none';
        if (gridBtn) {
          gridBtn.style.background = '#0284c7';
          gridBtn.style.borderColor = '#38bdf8';
          gridBtn.style.color = '#ffffff';
        }
        if (tableBtn) {
          tableBtn.style.background = '#0f172a';
          tableBtn.style.borderColor = '#334155';
          tableBtn.style.color = '#94a3b8';
        }
      } else {
        if (grid) grid.style.display = 'none';
        if (table) table.style.display = 'block';
        if (tableBtn) {
          tableBtn.style.background = '#0284c7';
          tableBtn.style.borderColor = '#38bdf8';
          tableBtn.style.color = '#ffffff';
        }
        if (gridBtn) {
          gridBtn.style.background = '#0f172a';
          gridBtn.style.borderColor = '#334155';
          gridBtn.style.color = '#94a3b8';
        }
      }
      applyFilters();
    }

    function sortSciViz(criteria) {
      const grid = document.getElementById('sciviz-grid-view');
      const tableBody = document.getElementById('sciviz-table-body');
      if (!grid || !tableBody) return;

      const cards = Array.from(grid.querySelectorAll('.sciviz-card'));
      const rows = Array.from(tableBody.querySelectorAll('.sciviz-row'));

      const comparator = (a, b) => {
        if (criteria === 'name-asc') {
          return (a.getAttribute('data-name') || '').localeCompare(b.getAttribute('data-name') || '');
        } else if (criteria === 'name-desc') {
          return (b.getAttribute('data-name') || '').localeCompare(a.getAttribute('data-name') || '');
        } else if (criteria === 'category') {
          return (a.getAttribute('data-category') || '').localeCompare(b.getAttribute('data-category') || '');
        } else if (criteria === 'records') {
          const rA = parseInt(a.getAttribute('data-records') || '0', 10);
          const rB = parseInt(b.getAttribute('data-records') || '0', 10);
          return rB - rA;
        }
        return 0;
      };

      cards.sort(comparator).forEach(card => grid.appendChild(card));
      rows.sort(comparator).forEach(row => tableBody.appendChild(row));
    }

    function applyFilters() {
      const cards = document.querySelectorAll('.sciviz-card');
      const rows = document.querySelectorAll('.sciviz-row');
      let visible = 0;

      cards.forEach(card => {
        const name = (card.getAttribute('data-name') || '').toLowerCase();
        const category = card.getAttribute('data-category') || '';
        const author = (card.getAttribute('data-author') || '').toLowerCase();
        const text = card.innerText.toLowerCase();

        const matchesCat = (currentCategory === 'all' || category === currentCategory);
        const matchesQuery = (!currentQuery || name.includes(currentQuery) || text.includes(currentQuery) || author.includes(currentQuery));

        if (matchesCat && matchesQuery) {
          card.style.display = 'flex';
          visible++;
        } else {
          card.style.display = 'none';
        }
      });

      rows.forEach(row => {
        const name = (row.getAttribute('data-name') || '').toLowerCase();
        const category = row.getAttribute('data-category') || '';
        const author = (row.getAttribute('data-author') || '').toLowerCase();
        const text = row.innerText.toLowerCase();

        const matchesCat = (currentCategory === 'all' || category === currentCategory);
        const matchesQuery = (!currentQuery || name.includes(currentQuery) || text.includes(currentQuery) || author.includes(currentQuery));

        if (matchesCat && matchesQuery) {
          row.style.display = 'table-row';
        } else {
          row.style.display = 'none';
        }
      });

      const countEl = document.getElementById('sciviz-visible-count');
      if (countEl) countEl.innerText = visible;
    }

    function resetSciVizFilters() {
      currentCategory = 'all';
      currentQuery = '';
      const input = document.getElementById('sciviz-search-input');
      if (input) input.value = '';
      document.querySelectorAll('.sciviz-cat-btn').forEach(b => {
        b.style.background = '#0f172a';
        b.style.borderColor = '#334155';
        b.style.color = '#cbd5e1';
      });
      const allBtn = document.querySelector('.sciviz-cat-btn');
      if (allBtn) {
        allBtn.style.background = '#0284c7';
        allBtn.style.borderColor = '#38bdf8';
        allBtn.style.color = '#ffffff';
      }
      applyFilters();
    }

    function openInspectModal(btn) {
      const card = btn.closest('.sciviz-card') || btn.closest('.sciviz-row');
      if (!card) return;
      const name = card.getAttribute('data-name');
      const author = card.getAttribute('data-author');
      const category = card.getAttribute('data-category');
      const dataset = card.getAttribute('data-dataset');
      const count = card.getAttribute('data-records');
      const code = card.getAttribute('data-code');
      const bddsRaw = card.getAttribute('data-bdds') || '';
      const featuresRaw = card.getAttribute('data-features') || '';

      const modal = document.getElementById('sciviz-inspect-modal');
      if (!modal) return;
      document.getElementById('modal-ext-name').innerText = name.toUpperCase() + ' Deep-Dive Specification';
      document.getElementById('modal-ext-author').innerText = 'Authored by ' + author;
      document.getElementById('modal-ext-cat').innerText = category;
      document.getElementById('modal-ext-ds').innerText = dataset + ' (' + Number(count).toLocaleString() + ' records)';

      const bddContainer = document.getElementById('modal-bdd-scenarios');
      if (bddContainer) {
        const bdds = bddsRaw.split('|||').filter(Boolean);
        bddContainer.innerHTML = bdds.map(s => '<div style=\"margin-bottom: 0.35rem;\"><span style=\"color:#34d399; font-weight:bold;\">✔</span> ' + s + '</div>').join('');
      }

      const featContainer = document.getElementById('modal-key-features');
      if (featContainer) {
        const feats = featuresRaw.split('|||').filter(Boolean);
        featContainer.innerHTML = feats.map(f => '<span style=\"background:#1e293b; color:#cbd5e1; border:1px solid #334155; padding:0.15rem 0.45rem; border-radius:4px; font-size:0.75rem;\">' + f + '</span>').join('');
      }

      const codeEl = document.getElementById('modal-code-snippet');
      if (codeEl) {
        codeEl.innerText = code || ('library(ggplot2)\\nlibrary(' + name + ')\\nggplot(data) + aes(x, y)');
      }

      modal.style.display = 'flex';
    }

    function closeInspectModal() {
      const modal = document.getElementById('sciviz-inspect-modal');
      if (modal) modal.style.display = 'none';
    }

    function copyPipelineSnippet() {
      const code = document.getElementById('modal-code-snippet').innerText;
      navigator.clipboard.writeText(code).then(() => {
        const btn = document.getElementById('copy-pipeline-btn');
        if (btn) {
          btn.innerText = 'Copied! ✓';
          btn.style.borderColor = '#34d399';
          btn.style.color = '#34d399';
          setTimeout(() => {
            btn.innerText = 'Copy Pipeline 📋';
            btn.style.borderColor = '#0284c7';
            btn.style.color = '#38bdf8';
          }, 2000);
        }
      });
    }

    function setTranspilerPreset(preset) {
      const textarea = document.getElementById('transpiler-code-input');
      if (!textarea) return;
      let code = '';
      if (preset === 'diamonds') {
        code = 'ggplot(diamonds) +\\n  aes(carat, price) +\\n  geom_point(alpha=.1) +\\n  geom_smooth() #<<\\nggram(\\'Diamond Pricing\\')';
      } else if (preset === 'tcga') {
        code = 'ggplot(tcga_pan_cancer) +\\n  aes(log2_fc, -log10(p_val)) +\\n  geom_point(aes(color = is_significant)) +\\n  geom_text_repel(aes(label = gene_symbol)) #<<\\nggtree_align()';
      } else if (preset === 'swarm') {
        code = 'ggplot(uos_mesh_events) +\\n  aes(peer_id, latency_us) +\\n  geom_edge_bundle() +\\n  geom_node_point(size = 3) #<<\\nggnetwork_theme()';
      } else if (preset === 'roc') {
        code = 'ggplot(credit_risk_eval) +\\n  aes(d = default_obs, m = pred_prob) +\\n  geom_roc(n.cuts = 0) +\\n  style_roc() #<<\\nannotate(\\'text\\', x = .75, y = .25, label = \\'AUC = 0.89\\')';
      } else if (preset === 'eeg') {
        code = 'ggplot(eeg_128ch_matrix) +\\n  aes(epoch_time_ms, microvolts, group = channel_id) +\\n  geom_path(alpha = 0.6) +\\n  geom_highlight_band(12, 30, fill = \\'#a855f7\\') #<<\\nggtimeseries_spec()';
      } else if (preset === 'scrna') {
        code = 'ggplot(scrna_10x_pbmc) +\\n  aes(umap_1, umap_2, color = cell_type) +\\n  geom_point(size = 0.8, alpha = 0.7) +\\n  geom_density_2d(color = \\'#38bdf8\\') #<<\\nscale_color_scran()';
      }
      textarea.value = code;
    }
    ",
  )
}
"""

text = text[:client_script_start] + new_client_script

with open("apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/sciviz_comprehensive_explorer.gleam", "w") as f:
    f.write(text)

print("Successfully upgraded sciviz_comprehensive_explorer.gleam!")
