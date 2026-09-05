# UOS Parent Repository Boundary Evidence

**Document ID:** `UOS-EVID-PARENT-BOUNDARY-001`  
**Generated At:** `2026-09-05T16:35:00+02:00`  
**Host:** `nas-1` (Machine ID: `37e22406dc804d57aeac9924b5519720`)  
**Target Repository:** `/home/an/NAS-setup/uos`  
**Parent Directory:** `/home/an/NAS-setup`  

---

## 1. Boundary Invariant Attestation

1. **Parent VCS Status**:
   - The parent workspace directory `/home/an/NAS-setup` is NOT an active Git repository.
   - An empty `.git/` directory exists as a historical artifact (dated 2026-05-02), containing zero Git metadata, no `HEAD`, no `config`, and no object store. `git status` fails with code 128 (`fatal: not a git repository`).
   - No enclosing Git repository exists above `/home/an/NAS-setup` (verified: neither `/home/an/.git` nor `/home/.git` exists).
2. **Exclusion Configuration**:
   - `/home/an/NAS-setup/.gitignore` has been established with explicit isolation rules:
     ```text
     /uos/
     /.uos-workspaces/
     ```
   - This ensures the parent directory structure can never accidentally track, index, or snapshot UOS repository state.
3. **Target VCS Independence**:
   - Target repository was initialized using Jujutsu 0.44.0 in non-colocated mode:
     ```bash
     jj git init --no-colocate /home/an/NAS-setup/uos
     ```
   - Top-level `/home/an/NAS-setup/uos/.git` is absent.
   - All Git storage is hidden inside `/home/an/NAS-setup/uos/.jj/repo/store/git`.
   - Native Git mutations inside `/home/an/NAS-setup/uos` are strictly prohibited.
4. **Sibling Workspace Isolation**:
   - Per Codex and Claude review stipulations, all concurrent leaf workspaces must reside strictly under:
     ```text
     /home/an/NAS-setup/.uos-workspaces/<workspace-id>
     ```
   - Sibling workspaces are isolated from the parent workspace and ignored by parent `.gitignore`.
