# UOS Standalone Jujutsu VCS Governance (`governance/vcs/JUJUTSU.md`)

## 1. Principles and Invariants

1. **Standalone Non-Colocated Repository**: UOS is initialized via `jj git init --no-colocate /home/an/NAS-setup/uos`. The Git backing store is isolated inside `.jj/repo/store/git`. Top-level `.git/` is strictly absent.
2. **Native Git Prohibition**: Invoking `git` commands (`commit`, `checkout`, `merge`, `rebase`, `push`) directly within `/home/an/NAS-setup/uos` is strictly prohibited and fails admission gates.
3. **Immutability of Historical Changes**: Changes and commits are content-addressed by 16-byte change IDs and SHA-1/SHA-256 Git commit IDs.
4. **Operation Log Durability**: Every mutating command records an operation in `.jj/repo/op_store/`. Rollback to any prior operational state is guaranteed via `jj op restore <operation-id>`.

---

## 2. Bookmark Discipline

- **No Premature Main**: The canonical bookmark `main` is withheld during migration and will be set only upon passing the final admission gate `EV-15`.
- **Integration Bookmarks**: Active work streams use named integration bookmarks:
  - `integration/bootstrap` (`EV-01`)
  - `integration/governance` (`EV-02`)
  - `integration/source-freeze` (`EV-03`)
  - `integration/core-orchestrator` (`EV-04`)
  - `integration/hermes-oracle` (`EV-05`)
  - `integration/zigvm-runtime` (`EV-06`)
- **Moveable Head Markers**: Work continues on working copy `@`. Bookmarks are moved explicitly with `jj bookmark set <name> -r @`.

---

## 3. Parallel Development via Sibling Workspaces

To achieve maximal parallelization across worker holons and subagents:
- Do NOT create nested git clones or worktrees.
- Use Jujutsu sibling workspaces stored in `../.uos-workspaces/<workspace-name>`.
- Creation:
  ```sh
  jj workspace add ../.uos-workspaces/ws-agent-c3i -r integration/governance
  ```
- All sibling workspaces share the single underlying repository object store and op-log.
- Integration gates are serialized back into the primary workspace.

---

## 4. Disaster Recovery and Operation Log Protocols

In case of merge conflicts, corrupted working copy, or failed validation:
1. Inspect the operation log:
   ```sh
   jj --no-pager op log -n 10
   ```
2. Undo the immediately preceding operation:
   ```sh
   jj --no-pager op undo
   ```
3. Restore exact previous operation state:
   ```sh
   jj --no-pager op restore <operation-id>
   ```
