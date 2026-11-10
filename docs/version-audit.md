# Version audit: GitLab CE v19.0.2

Source: `gitlab-foss` tag `v19.0.2` (CE mirror, no `ee/` dir). Gitaly 19.0.2, GitLab Shell 14.51.0.
Target instance: Omnibus `gitlab-ce=19.0.2-ce.0`.
Status legend: **VERIFIED** = read in source at this tag; **UNVERIFIED** = needs a running instance.

## Write path (enforcement)
| Finding | Status |
|---|---|
| `Gitlab::GitAccess#check_change_access!` -> `Checks::ChangesAccess#validate!` runs per-change + bulk checks for pushes (`lib/gitlab/git_access.rb:405-433`, `lib/gitlab/checks/changes_access.rb`). | VERIFIED |
| `Checks::DiffCheck#validate!` iterates `find_changed_paths(commits, merge_commit_diff_mode: :all_parents)` over **all newly introduced commits** (not net diff) and calls `validations_for_path`; it is an explicit **EE injection point returning `[]` in CE** (`lib/gitlab/checks/diff_check.rb:12-52`). | VERIFIED |
| `Git::ChangedPath` exposes `status, path, old_path, old_mode, new_mode, commit_id` => renames (src+dest), deletes, modes, gitlinks are all checkable. | VERIFIED |
| `DiffCheck` returns early for ref deletions and non-branch/tag refs (e.g. `refs/notes`, custom refs) -> must be covered separately (deny unsupported namespaces). | VERIFIED |
| Web/API/Web IDE commits go through Gitaly `UserCommitFiles`, which runs hooks that call back to Rails `/internal/allowed` / `pre_receive`. | UNVERIFIED (needs instance test) |

## Read path (hiding)
| Finding | Status |
|---|---|
| Per-request controllers to guard: `projects/{tree,blob,raw,blame,commit,commits,compare,find_file,network,graphs,repositories}_controller.rb`, `projects/merge_requests/{diffs,diffs_stream,content}_controller.rb`, `commit_diffs_stream_controller`, `compare_diffs_stream_controller`. | VERIFIED (exist) |
| API: `lib/api/{files,commits,search,merge_requests,project_snapshots,project_export,branches,tags}.rb`; `repository.rb` not found at that name - locate (likely `lib/api/repositories.rb`). | PARTIAL |
| `Repository` model methods (`tree`, `blob_at`, `commits`, `ls_files`, `search_files_by_*`) have **no `current_user`** -> user-aware filtering must happen in controllers/finders/API, not the model. | VERIFIED |

## Extension mechanisms in CE
- `prepend_mod` / `prepend_mod_with` only load `ee/` modules (`config/initializers/0_inject_enterprise_edition_module.rb`); no CE plugin dir.
- `config/initializers/*.rb` (208 files) is auto-loaded -> an add-on can ship one initializer that `Module#prepend`s onto GitAccess/DiffCheck/controllers. No patched source files.
- `file_hooks/` runs on system events only; **not** an interception point.

## Settings UI
- Route: `resource :repository` in `config/routes/project.rb:146`; view `app/views/projects/settings/repository/show.html.haml`; controller `projects/settings/repository_controller`.

## Open (needs live instance)
Hook coverage for web/API/merge/squash/rebase/bot commits; Gitaly custom-hook dir path on Omnibus; DB table creation strategy vs GitLab schema checks; full endpoint matrix.
