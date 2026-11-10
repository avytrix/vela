# Design: hiding paths inside GitLab (View and Read)

Status: **design from reading GitLab CE 19.0.2 source. Nothing here is built or tested yet.** Tier 1 (write enforcement) is done; see [design.md](./design.md).

Reminder of the limit: `git clone` and `git fetch` stay open, so this is **not confidential**. It hides paths in GitLab's own pages and API so people see only what they are meant to work on.

## Meaning of the two levels

| Level | Effect inside GitLab |
| ----- | -------------------- |
| **View** | The path appears in file lists, search results and diffs. Without View it is **omitted**, as if it did not exist. |
| **Read** | The file's content can be opened (file viewer, raw, API, blame, diff body). Without Read, opening it returns **404**, the same as a missing file, so its existence is not revealed. |

A path you can view but not read is listed and shown as restricted. That state only arises when an admin deliberately grants View without Read.

## The funnels (verified in source)

GitLab has no request-scoped "current user" the repository layer can see (`Current` holds only organization and token info), but most reads funnel through three model-level calls:

| Funnel | Code | Covers |
| ------ | ---- | ------ |
| File content | `Repository#blob_at(sha, path, limit:)` | web blob page, raw (`raw_controller.rb:24`), API `repository/files` (`files.rb:51`), blame and edit pages (`blob_controller.rb:188`) |
| Directory listing | `Tree#initialize` (`app/models/tree.rb`), builds `@entries` via `Gitlab::Git::Tree.tree_entries` | web tree and README lookup. The API tree uses `Repositories::TreeFinder` and the same Git call, with keyset pagination |
| Flat file list | `Repository#ls_files(ref)` | "Find file" (`find_file_controller.rb:27`) |

Plan: prepend small modules onto these, and give them the **actor** (who is asking) through a request-scoped value.

### The actor

- Web: a `before_action` prepended onto `ApplicationController` stores `current_user` (which may be nil for anonymous) in `Gitlab::SafeRequestStore`.
- API: the same through a Grape `before` block, using the API's `current_user` helper.
- The store also holds a marker "this is a user request". **No marker means background or system work, which is never filtered.** A marker with no user means an anonymous visitor, who is filtered like anyone else.
- The store lives for one request, so nothing leaks between requests.

### Per-funnel behaviour

- `blob_at`: if the project has path permissions on and the actor lacks Read on `path`, return `nil`. GitLab already turns a nil blob into a 404.
- `Tree#initialize`: after loading, drop entries the actor cannot View. Keep a directory if it **contains** anything they can view (so you can reach an allowed file inside a mostly hidden folder).
- `ls_files`: remove paths without View.
- All of it is skipped when the project is not enabled, when the actor is an admin or Owner, and when there is no user-request marker.

## Surfaces beyond the funnels

| Surface | Where | Plan | Phase |
| ------- | ----- | ---- | ----- |
| Code search (blobs) | `Gitlab::ProjectSearchResults` (`project_search_results.rb:25`) | Filter results by Read | 2b |
| Blame | `projects/blame_controller.rb` | Goes through `blob_at`; confirm, and check the line-level data | 2b |
| Commit, compare and MR diffs | `Gitlab::Diff::FileCollection`, `merge_requests/diffs_controller.rb` | Filter files by Read, including old and new path of renames, and the diff stats | 2c |
| API tree pagination | `Repositories::TreeFinder` | Filtering after Gitaly pagination yields short pages. Accept and document, or over-fetch | 2a |
| Commit history and messages | `projects/commits_controller.rb` | **Left visible.** Commit messages and which commits exist are not filtered | known gap |
| Archives, `repository/blobs/:sha`, exports, forks, snippets, GraphQL, Web IDE | various | Not covered. Clone is open anyway. List each in the endpoint table when audited | known gap |

## Fail-closed rules for reads

- If the project is enabled and rules cannot be read, **deny** the read (404), and log it. Same stance as writes.
- The reads run on every file request, so rules are cached **per request**, and keyed by project and a rule revision once we add one.
- Cached responses are a risk: GitLab caches rendered pages and the highlight cache by blob. Phase 2a must check that a cached page for an allowed user is never served to a restricted one (cache key includes the actor's access, or caching is skipped for enabled projects).
- A message never names a path the actor cannot view.

## Order of work

1. **2a:** actor plumbing, `blob_at`, `Tree#initialize`, `ls_files`, with unit tests against the stand-in and e2e cases.
2. **2b:** search and blame.
3. **2c:** diffs.
4. Then the Settings page, and the other GitLab versions.

## Test plan (extends `dev/e2e.sh`)

- A user in the frontend group requests `GET repository/tree`, `repository/files/backend%2Fapi.rb`, the web blob and raw URLs, and Find file: backend paths absent or 404, frontend present.
- Encoded and double-encoded separators, dot segments, and case variants of a hidden path: still hidden.
- A file inside a hidden folder that was explicitly allowed stays reachable.
- Admin, Owner and a user with View but not Read behave as described above.
- Anonymous request on a public project with an allow-list.
- Cache isolation: an admin opens a file, then the restricted user opens the same URL.
- Rules unreadable: reads fail closed.
- Background jobs (for example a Sidekiq mirror or export) are not filtered.

## Open questions to settle by running it

- Do any GitLab caches sit in front of `blob_at` and `Tree`?
- Does the web UI break (README, "last commit" column, breadcrumbs) when entries disappear?
- Does the API tree pagination return a usable `X-Next-Page` after filtering?
