---
id: hermes-yuque-lake-format
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Lake 格式 — canonical form with derived projections (Yuque)

#feature #src-yuque #area-format #cov-differ

**Coverage**: ◇ deliberate divergence — Yuque stores Lake and DERIVES markdown; we store markdown and derive HTML

**Use cases**: One structured truth, several serialisations.

**Look & feel (reference)**: `bodyLake` is authoritative; `body` (markdown) and `bodyHTML` are projections requested from the API.

**Navigation cues**: API: `?format=markdown|html|lake`.

**Hermes reading**: The single most consequential difference between Yuque and Hermes. Their canonical form is **rich and proprietary**; ours is **plain and diffable**. Ours makes git the review surface; theirs makes the editor the review surface. See the algebra: the projection is a homomorphism only in one direction.
