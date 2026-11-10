# Portability: every GitLab CE, every install method, upgrades and downgrades

The goal is that vela works on any GitLab Community Edition, however it was installed, and keeps working through upgrades and downgrades. This page says honestly what is possible, what GitLab's documentation allows, and how vela covers the rest.

## What GitLab documents as an extension point

From GitLab's own docs ([file hooks](https://docs.gitlab.com/administration/file_hooks/), [server hooks](https://docs.gitlab.com/administration/server_hooks/), [extending GitLab](https://docs.gitlab.com/api/get_started/get_started_extending/)):

| Mechanism | Can block something? | Stable across versions? |
| --------- | -------------------- | ----------------------- |
| **Server hooks** (`pre-receive`, `update`, `post-receive`), global or per repository | **Yes**, a push | Yes. Documented for Linux package, source and Helm installs |
| File hooks, system hooks, webhooks | No, they run after the event | Yes |
| REST and GraphQL APIs | No | Versioned (`v4`) |
| Anything else (hide a path in the UI, add a settings page) | **No documented way** | GitLab's advice is to change the source and contribute upstream |

So no supported plugin API can hide paths or add a page to Project Settings. What can be done in a supported, version-proof way is **write enforcement through a global pre-receive server hook**. That is Tier A.

## The two tiers

| | **Tier A: server hook** | **Tier B: overlay** |
| --- | --- | --- |
| Enforces | Write (push, web edit, API commit, merge, tag) | Write, plus **hides paths** (View and Read) in the UI, API, search and diffs |
| Relies on | Only documented behaviour: hook environment variables, the REST API, plain `git` | GitLab internals (the push-check hook, `Repository`, `Tree` and others) |
| Versions | Any CE with global server hooks | Tested versions only. Refuses to start if an internal it needs is missing |
| Install methods | Linux package, Docker, source, Helm | Linux package, Docker, source (Helm needs a custom image) |
| Where rules live | A project CI/CD variable `VELA_PATH_POLICY` (only Maintainers and Owners can read or change it) | Database tables |
| Survives a GitLab upgrade | Yes, it lives outside GitLab's files | Yes, if installed the persistent way below |

You can run Tier A alone on any GitLab. Add Tier B when you also want paths hidden. If both run, a push is checked twice, which is harmless.

## How vela stays safe across versions

1. **Capability checks, not version numbers.** At boot the overlay checks that every method it wraps still exists. If one is missing, GitLab refuses to start rather than run unprotected. The server hook uses no GitLab internals at all.
2. **Fail closed everywhere.** If rules cannot be read, a push is rejected and a read is a 404. Never "allow because we could not check".
3. **Automated compatibility tests.** `dev/e2e.sh` runs the same live suite against any GitLab version, in either tier. A scheduled workflow runs it across a version matrix, and results are published in [compat/](./compat/). A version is listed as supported only when its results are green.
4. **Upgrades:** see below.
5. **Downgrades:** the add-on tables are separate from GitLab's own and are never touched by GitLab migrations, so a downgrade leaves them intact. The overlay re-checks its hooks on the older version at the next start. (GitLab itself only supports downgrades through a database restore.)

## Surviving an upgrade, per install method

A GitLab upgrade can replace files under its own directories. vela puts nothing there that it cannot restore on its own.

| Install | Tier A (hook) | Tier B (overlay) |
| ------- | ------------- | ---------------- |
| **Linux package** | The hook lives in `custom_hooks_dir`, which upgrades do not touch | Add a copy step to `/etc/gitlab/gitlab.rb`. It runs on **every reconfigure**, which is part of every package upgrade, so the initializer is put back automatically. See [install.md](./install.md#upgrading-gitlab) |
| **Docker** | Mount the hook directory | Mount `lib/` and `overlay/` as directories and copy the initializer from `gitlab.rb` as above. This is what `dev/up.sh` does. It was tested through an in-place container upgrade |
| **Source** | `custom_hooks_dir` in `gitlab-shell/config.yml` | Copy the initializer after each `git checkout` of a new tag. The doctor script reports if it is missing |
| **Helm** | Set the Gitaly chart's global server hooks | Build a custom image with the initializer baked in |

## The doctor check

After any upgrade or downgrade, run `sudo bin/doctor --deep`. It is read-only. It reports which tiers are active, whether the hook can still reach GitLab's API with its token, whether the overlay initializer is still in place and loaded, and whether the database role can still read the add-on tables.

## Running Tier A in production: what to know

- **The hook calls GitLab's REST API** (about three to five small requests per push: the project's policy, the user, their access, and group membership). The Gitaly server must be able to reach GitLab's web address. A brief outage is retried three times (after 0.5 s and 1.5 s) before the push is rejected. A wrong token is not retried.
- **It adds time to every push to a project that has path permissions on.** About 2.5 seconds on a small test VM. Projects without the `VELA_PATH_POLICY` variable cost one small request.
- **Commits made inside GitLab** (API, web editor, merge button) also run the hook, and the hook then calls back into GitLab's web process. Keep at least two web workers (the default Linux package setup has them) so the nested call has a free thread. On a single-process, single-thread setup it would time out and the commit would be rejected.
- **If GitLab's API is down, pushes to protected projects are rejected.** That is the fail-closed choice. Pushes to projects without a policy variable are also affected, because the hook must ask GitLab whether one exists.
- **Group membership counts inherited members**, but not groups shared into another group.

## What cannot be promised

- Version coverage beyond what the compatibility results show. Untested versions may work, and the boot check will say if the overlay cannot.
- Tier A cannot hide anything. Hiding needs Tier B.
- Neither tier restricts `git clone` or `git fetch`.
