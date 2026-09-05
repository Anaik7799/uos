---
id: hermes-yuque-open-api
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# 开放 API v2 (Yuque)

#feature #src-yuque #area-surface #cov-gap

**Coverage**: ✗ gap — HW.6.2.1 is Ready: the read model already serialises, only the route is missing

**Use cases**: Script the knowledge base; let agents act headlessly.

**Look & feel (reference)**: REST over /api/v2: users, groups, repos, docs, TOC.

**Navigation cues**: Developer settings → token.

**Hermes reading**: Yuque's resource shape (users · groups · repos · docs · toc) is a good sanity check on ours: we need notes, groups, query and search — no user or membership resources, because we have no membership.
