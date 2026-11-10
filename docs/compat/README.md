# Compatibility results

Live results from `dev/e2e.sh` against real GitLab CE images. A version is listed as supported only when its
row here is green. Re-run any row with `dev/compat.sh <tag> <overlay|hook>`, or run the whole matrix with the
[Compatibility workflow](../../.github/workflows/compat.yml).

| GitLab CE | Tier A: server hook (writes) | Tier B: overlay (writes, hiding, settings page) | Notes |
| --------- | ---------------------------- | ----------------------------------------------- | ----- |
| 19.5.3 | 23 of 23 ([results](./19-5-3-ce-0-hook.md)) | 68 of 68 ([results](./19-5-3-ce-0-overlay.md)) | fresh install |
| 19.0.11 | not run | 68 of 68 ([results](./upgrade-19.0.2-to-19.0.11-overlay.md)) | **in-place upgrade from 19.0.2**, same data volumes; the initializer was restored by `gitlab.rb` |
| 19.0.2 | 23 of 23 ([results](./19.0.2-ce.0-hook.md)) | 68 of 68 ([results](../e2e-results.md)) | fresh install |
| 17.11.0 | 23 of 23 ([results](./17-11-0-ce-0-hook.md)), with 2 web workers | **not completed**: the run was stopped before it finished | An earlier run on a single-process, single-worker instance had 4 failures, traced to GitLab's own web process returning 502 to plain git requests, not to vela |
| 18.x, 16.x, 15.11 | not run | not run | run `dev/compat.sh <tag> <tier>` or the workflow |

What "68" covers: forbidden writes (push, rename, delete, tags, API commit, merge by another user, spoofed
author), reads hidden in the API, web (real login session), GraphQL, search and diffs, admin and Owner exemption,
group removal, cache order (admin then user), fail-closed when rules are unreadable, and the Project Settings page.
What "23" covers: the same write cases, with only the server hook installed.
