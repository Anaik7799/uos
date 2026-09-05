# Profile Contract

Model `Ontology × Tokens × Components × Screens × Interactions × Responsive ×
Motion × Accessibility × Quality × Provenance × Evidence`. Every value has a
stable OCaml identifier independent of external tool IDs.

Profiles:

- Figma: variables, modes, styles, components, variants, pages, frames, and transitions.
- Stitch: DESIGN.md, design systems, projects, screens, devices, prompts, variants, HTML, screenshots, and Figma exports.
- GetDesign: catalog, previews, tokens, rationale, responsive rules, coverage, provenance, and gaps.
- Impeccable: lifecycle, audit, critique, harden, adapt, detector, debt, and direction reports.
- Bonsai: models, actions, transitions, Virtual_dom views, routes, and adaptive composition.
- InfraNodus: ingestion, graph, analytics, graph-grounded AI, integrations, export, and evidence workflows.

Require projection determinism/idempotence, stable IDs, token and dependency
closure, transition closure, responsive non-amputation, accessibility-name
preservation, content non-invention, export/readback agreement, explicit
residual preservation, and Figma/Stitch/Bonsai shared-observation agreement.

External Figma/Stitch readback is a separate typed observation. A complete
Figma row totals file/node identity, 115 components, 37 pages, devices,
variants, variables, modes, transitions, and timestamp. A complete Stitch row
totals account boundary, project/design-system identity, screens, components,
variants, HTML, screenshots, Figma exports, and timestamp. Missing
authorization or resources terminate as `Unavailable_observed` with the exact
failed operation and evidence required to reopen; generated projections never
count as external success.
