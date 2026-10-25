---
name: using-jj-workspaces
description: Use when starting feature work or executing implementation plans in a Jujutsu repository (like UOS) that requires workspace isolation via jj workspace add
---

# Using Jujutsu Workspaces (using-jj-workspaces)

## Overview

Ensure feature work in Jujutsu-based repositories (such as UOS) occurs in an isolated workspace. In UOS, native Git commands are strictly prohibited, so `using-git-worktrees` is replaced with `using-jj-workspaces`.

**Core principle:** Detect existing workspace first. Use sibling workspaces (`.uos-workspaces/*` or `../uos-*`). Never mutate the root working copy during parallel feature implementation.

**Announce at start:** "I am using the using-jj-workspaces skill to set up an isolated Jujutsu workspace."

## Step 0: Detect Existing Workspace Isolation

Before creating anything, inspect current Jujutsu workspaces:

```bash
jj workspace list
```

Check your current working directory against the workspace list:
- If current directory is already a non-root sibling workspace:
  "Already in isolated Jujutsu workspace at `<path>` on change `<change_id>`."
- If current directory is the root workspace:
  Proceed to Step 1 to create an isolated sibling workspace.

## Step 1: Create Isolated Jujutsu Workspace

Create a dedicated sibling workspace for the feature or plan:

```bash
jj workspace add ../uos-<feature-name> -r <parent-revision-or-bookmark>
```

Navigate or target commands to the isolated workspace.

## Step 2: Implement and Verify Inside Isolated Workspace

1. Perform edits, builds, and test runs inside the sibling workspace.
2. Verify all gates and assertions locally:
   ```bash
   gleam test
   ```
3. Commit with descriptive Jujutsu descriptions:
   ```bash
   jj describe -m "feat(subsystem): descriptive change summary"
   ```

## Step 3: Complete and Reintegrate

When work passes all verification gates:
1. Create or advance the target bookmark:
   ```bash
   jj bookmark create feature/<name> -r @
   ```
2. Switch back to the main workspace.
3. Once integrated, clean up the sibling workspace:
   ```bash
   jj workspace forget ../uos-<feature-name>
   rm -rf ../uos-<feature-name>
   ```
