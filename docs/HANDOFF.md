# Handoff: state of the project

Written when active development paused. Everything below is either verified (with the evidence named) or
listed as untested. Nothing is claimed beyond that.

## What exists

| Part | Evidence |
| ---- | -------- |
| Rules engine (View, Read, Write, allow and deny, allow-lists, explain) | 60 unit tests (`bin/test`) |
| **Tier A**, server hook (writes on any CE) | 23 of 23 live cases on GitLab CE 19.0.2, 19.5.3 and 17.11.0, no overlay installed. 16 unit tests against real git repositories |
| **Tier B**, overlay (writes, read hiding, settings page) | 68 of 68 live cases on 19.0.2, on 19.5.3 (fresh) and on 19.0.11 after an **in-place upgrade from 19.0.2** |
| `bin/doctor` | Run by hand only; not part of any test |
| Weekly compatibility workflow (`compat.yml`) | Written, **never run on GitHub Actions** |

Per-version results: [compat/](./compat/README.md). How to install: [install.md](./install.md). Why two tiers:
[portability.md](./portability.md). Rules for agents: [../AGENTS.md](../AGENTS.md), [agent-guide.md](./agent-guide.md).

## Not tested (please try these)

- **GitLab 15.11, 16.11, 17.11 overlay, 18.x** and every other version. The 17.11 overlay run was stopped before it finished.
- **Source installs and Helm/Kubernetes.** The install guide describes them, but they were never run.
- **Gitaly Cluster (Praefect) and multi-node setups.** The hook must be on every Gitaly node.
- **A GitLab downgrade.** Only reasoned about (the add-on tables are separate from GitLab's), never run.
- **Package upgrades on a real Linux package host.** Tested with Docker image upgrades, where `gitlab.rb` restored the overlay; a `dpkg`/`rpm` upgrade was not run.
- **The web editor and Web IDE** as separate paths. API commits and merges were tested and share the same commit code.
- **Large repositories and load.** The hook adds about 2.5 s to a push on a small VM. Nothing was measured at scale.
- Pushes by **deploy keys and CI job tokens** to a project with rules. A deploy key has no user, so the overlay and hook both reject it while rules exist. That is deliberate and untested against a real setup.

## Known gaps (documented, by design or not yet built)

- `git clone` and `git fetch` are **not restricted**. View and Read only hide things inside GitLab.
- Not filtered: commit history and messages, archives, `repository/blobs/:sha`, project export, the compare endpoint, `.diff`/`.patch` downloads.
- Group membership counts inherited members but not groups shared into another group (Tier A).
- Refs that are neither branches nor tags are not checked.
- The settings page edits rules for one project at a time. No bulk import or export.
- GitLab's own `find_changed_paths` swallows Gitaly errors; the per-commit write check cannot tell an error from "no changes". The branch-level check treats it as unverifiable.
- Fail-closed has a wide blast radius. If the overlay cannot read its tables, **every** request on the instance fails. `bin/doctor` checks the database grant.

## Things that went wrong, so you do not repeat them

- The Linux package ignores global server hooks until `gitaly['configuration'][:hooks][:custom_hooks_dir]` is set. This was missing from the first install guide and was found by a live test.
- GitLab 19.5's container reports healthy before its web server answers; wait for HTTP 200.
- A test script once ran `git` in this repository because a variable was overwritten, and pushed junk branches. `dev/e2e.sh` now routes every git call through a guard that refuses to run outside a test clone.

## Repository housekeeping

- Three junk branches from that mistake may still exist on GitHub: `frontend/notes.txt`, `t15`, `t16`. Delete with
  `git push origin --delete frontend/notes.txt t15 t16`.
- All local test infrastructure (VM, containers, volumes, GitLab images, scratch sources) was deleted. To test again you need Docker
  and about 8 GB of RAM: `dev/up.sh`, `dev/e2e.sh`, `dev/compat.sh <tag> <overlay|hook>`.

## Reporting a bug

Open an issue (template asks for GitLab version and install method). Access-check bypasses go through
[../SECURITY.md](../SECURITY.md), not a public issue.
