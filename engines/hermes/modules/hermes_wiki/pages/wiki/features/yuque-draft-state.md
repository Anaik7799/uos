---
id: hermes-yuque-draft-state
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# bodyDraftLake — draft as a distinct stored state (Yuque)

#feature #src-yuque #area-format #cov-gap

**Coverage**: ✗ gap — our `status: draft` is metadata on one body, not a second body

**Use cases**: Edit without publishing; keep the published version live.

**Look & feel (reference)**: Two bodies per document: draft and published.

**Navigation cues**: Publish button.

**Hermes reading**: A genuinely different model from our visibility split (HW.1.4.1). Yuque separates CONTENT states; we separate VISIBILITY states over one content. Theirs needs a merge story; ours does not.
