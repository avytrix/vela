# Compatibility results

Live results from `dev/e2e.sh` against real GitLab CE images. A version is listed as supported only when its
row here is green. Re-run any row with `dev/compat.sh <tag> <overlay|hook>`, or run the whole matrix with the
[Compatibility workflow](../../.github/workflows/compat.yml).

| GitLab CE | Tier A: server hook (writes) | Tier B: overlay (writes, hiding, settings page) | Notes |
| --------- | ---------------------------- | ----------------------------------------------- | ----- |
| 19.5.3 | 23 of 23 ([results](./19-5-3-ce-0-hook.md)) | 68 of 68 ([results](./19-5-3-ce-0-overlay.md)) | fresh install |
| 19.0.11 | 23 of 23 | 68 of 68 ([results](./upgrade-19.0.2-to-19.0.11-overlay.md)) | overlay: **in-place Docker upgrade from 19.0.2**, the initializer was restored by `gitlab.rb` |
| 19.0.2 | 23 of 23 ([results](./19.0.2-ce.0-hook.md)) | 68 of 68 ([results](../e2e-results.md)) | fresh install |
| 18.11, 17.11, 16.11 | 23 of 23 | 68 of 68 | fresh installs, 2 web workers |
| 15.11 | 23 of 23 | 69 of 69 | needed a fix for older GitLab (plain-diff fallback); the 69th case covers it |

The overlay runs for 16.11 to 19.5 were made **before** the last overlay change (admins exempt first, plain-diff
fallback). That change is covered by unit tests and by the 15.11 and 19.x-era hook runs, but those versions were not
re-run on the final overlay code. The scheduled full matrix does that.

**Real package upgrade (`dpkg`/`apt`, 19.0.2 to 19.0.11 and back):** after both the upgrade and the downgrade the
initializer was still in place and the overlay classes were loaded (see `dev/upgrade-test.sh`). The full suite
**did not finish** inside that container in the last run (its test setup could not create fixtures through the API
after the package reconfigure; the cause was not found). So package upgrades are verified as "overlay present and
loaded", not as a full 68-case pass. The Docker in-place upgrade above did pass in full.

Not tested at all: source installs, Helm, Praefect (Gitaly Cluster).

What "68" covers: forbidden writes (push, rename, delete, tags, API commit, merge by another user, spoofed
author), reads hidden in the API, web (real login session), GraphQL, search and diffs, admin and Owner exemption,
group removal, cache order (admin then user), fail-closed when rules are unreadable, and the Project Settings page.
What "23" covers: the same write cases, with only the server hook installed.
