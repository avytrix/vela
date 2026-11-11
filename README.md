# vela

[![license](https://img.shields.io/github/license/avytrix/vela?color=E0234E)](./LICENSE)
[![CI](https://github.com/avytrix/vela/actions/workflows/ci.yml/badge.svg)](https://github.com/avytrix/vela/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/avytrix/vela?style=social)](https://github.com/avytrix/vela)
[![Sponsor @avytrix](https://img.shields.io/badge/Sponsor-%40avytrix-db61a2?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/avytrix)

**Folder and file permissions for self-hosted GitLab CE.** Decide which users and groups can view, read or write each path in a project, without paying for a higher GitLab tier.

Built and maintained by **[Avytrix Technologies](https://avytrix.dev/?utm_source=vela&utm_medium=docs&utm_campaign=readme)**. Need help shipping? [Hire the team behind it](#work-with-avytrix).

> **Early days.** Write enforcement passes on real GitLab CE 15.11 to 19.5, and read hiding and the settings page on the same range ([results](./docs/compat/README.md)). Source installs, Helm and Gitaly Cluster are not tested yet. Try it on staging first. See [Status](#status).

## Sponsoring is what keeps this free

GitLab Free has no way to say "the frontend team can change `frontend/`, and
nobody else can." vela adds that. Getting it right means handling renames,
reverted commits, group inheritance and every other way a change can sneak
through, and then keeping up with each GitLab release. It is free under MIT, and
that upkeep takes steady work.

**Even $1 a month helps.** It pays for testing on more GitLab versions, bug fixes
and the next release.

### [Sponsor on GitHub →](https://github.com/sponsors/avytrix) &nbsp;·&nbsp; thank you

---

## What it does

You give each user or group up to three levels on a file or folder:

| Level | Lets them |
| ----- | --------- |
| **View** | see that the path exists in file lists |
| **Read** | open the file and see its contents |
| **Write** | create, change, rename or delete it |

Each level includes the one before it, so Write needs Read, and Read needs View.

A few rules keep it predictable:

- A folder rule covers everything inside it. A rule on a single file beats the folder around it.
- If a path has no rule, GitLab's normal permissions apply. Turning vela on changes nothing until you add a rule.
- If a path has rules, only the people you list can use it. An explicit deny always wins.
- vela can only take access away. It never gives anyone more than GitLab already allows.
- Instance admins and project Owners are never locked out. Maintainers can manage rules, but cannot grant more than they hold.

Here is a policy for a project with a frontend team, a backend team and shared docs:

```yaml
rules:
  - folder: frontend/      # group 101 can do everything here
    allow: { view: [101], read: [101], write: [101] }
  - folder: backend/       # group 102 can do everything here
    allow: { view: [102], read: [102], write: [102] }
  - folder: docs/          # both can read, only 101 can edit
    allow: { view: [101, 102], read: [101, 102], write: [101] }
  - file: frontend/security-config.json   # one file even frontend cannot touch
    deny: { view: [101], read: [101], write: [101] }
```

## Status

| Part | State |
| ---- | ----- |
| Rule engine (who may do what to which path) | Built and tested |
| Write enforcement on push, web edit, API commit, merge and tag (GitLab CE 19.0.x) | Built and tested live |
| Hiding paths in GitLab: file lists, file content, raw, blame, search, diffs, API and GraphQL | Built and tested live (commit history and some export routes are not filtered, see below) |
| Server hook tier (any CE, any install method) | Built. 23 live write cases pass on CE 19.0.2 and 19.5.3 with no overlay installed |
| Upgrades | Overlay survived an in-place GitLab upgrade 19.0.2 to 19.0.11 (68 of 68). See [docs/compat/](./docs/compat/) |
| Compatibility matrix on 15.11 to 19.5 | Hook tier 23 of 23 and overlay 68 of 68 on 16.11 to 19.5 (15.11: 69 of 69). See docs/compat/ |
| Settings page under Project Settings (Tier B) | Built. Passes live on CE 19.0.2, 19.0.11 and 19.5.3. Rules can also be set with SQL (Tier B) or a CI/CD variable (Tier A) |

## The one limit you must know about

**vela does not stop `git clone` or `git fetch`.** Git sends the whole history in
one piece, and one repository cannot hide part of itself from someone who can
fetch it.

- **Write rules are enforced.** A push that touches a path the person may not
  change is rejected before it lands.
- **View and Read rules hide things inside GitLab**: file lists, the file
  viewer, search, diffs and the API. They are not a vault. Anyone who can clone the
  repository has every file.

So use vela to keep people from changing the wrong things and to tidy what they
see. Do not use it to keep secrets out of a repository people can clone. If you
need that, split the secret into its own project.

## Two tiers, so it works on any GitLab CE

GitLab documents only one extension point that can block something: **global
pre-receive server hooks**. So vela comes in two tiers ([why](./docs/portability.md)):

- **Tier A, server hook.** Enforces writes on any CE version and install method (Linux
  package, Docker, source, Helm), and survives upgrades because it lives outside GitLab's
  files. Rules sit in a project CI/CD variable that only Maintainers and Owners can open.
- **Tier B, overlay.** Everything in Tier A, plus **hiding paths** in the web UI, API,
  search and diffs. It relies on GitLab internals, so it refuses to boot if GitLab changed
  something it needs, and each version is tested before it is listed as supported.

- **Tier C, encrypted paths (optional).** Hides file **content** even from people who clone, by encrypting it to their SSH keys. GitLab's web pages cannot show those files, and names stay visible. See [docs/encryption.md](./docs/encryption.md).

`bin/doctor` checks what is installed after any upgrade or downgrade.

## How it works (Tier B)

vela is an overlay, not a fork of GitLab. It is one initializer file plus a few
small Ruby modules, and it does not patch GitLab's source.

```
lib/path_permissions/
  evaluator.rb     the rules engine, plain Ruby, knows nothing about GitLab
  write_check.rb   plugs into GitLab's push checks and rejects forbidden changes
  read_check.rb    hides paths in file lists, content, search and diffs
  guard.rb         works out who is asking, for each request
  store.rb         reads rules from the add-on's own tables
  admin.rb, ui.rb, ui/  the settings page under Project Settings
  install.rb       boot guard, refuses to start if GitLab changed the hook it uses
  hook.rb          Tier A: the server hook logic (git and the REST API only)
server-hook/       Tier A: the script GitLab runs as a global pre-receive hook
overlay/           the initializer you copy into GitLab
db/schema.sql      the three tables the add-on uses
```

GitLab CE has a spot in its push checks that does nothing in the free edition
and is meant to be filled in. vela fills it. Every path in every commit of a push
goes through the rules, so a forbidden change is caught even if a later commit
undoes it. Renames are checked on both sides.

vela fails closed. If it cannot read its rules, it rejects the push. If a GitLab
upgrade removes the hook it relies on, GitLab refuses to boot rather than run
unprotected.

## Install

A step-by-step guide for Omnibus, Docker, source and Kubernetes installs is in
**[docs/install.md](./docs/install.md)**. In short:

1. Back up GitLab.
2. Copy `lib/` and one initializer file onto the server. No GitLab files are edited.
3. Create three tables with `db/schema.sql`.
4. Restart GitLab and check that vela loaded.
5. Enable one test project, add rules, and test with a real push.

Nothing is restricted until you enable a project and add rules.

## Use it with an AI agent

Want an agent to do the install and set the permissions for you? Point it at
[`docs/agent-guide.md`](./docs/agent-guide.md). It is a checklist with approval gates,
a backup step, a dry-run of the rules, real push tests and a plain report. Agents
working on vela's own code should read [`AGENTS.md`](./AGENTS.md).

## Try it locally

You need Docker (Colima works too). This starts a throwaway GitLab CE 19.0.2 with vela loaded:

```bash
dev/up.sh                # first boot takes 5 to 10 minutes
# open http://localhost:8929, sign in as root, password is in dev/.root_password
docker exec -i vela-gitlab-ce gitlab-psql -v app_role=gitlab -f - < db/schema.sql
```

The instance has no mirrors, webhooks or email. `dev/e2e.sh` then runs the end-to-end
suite against it with real `git push`, API commits and merges.

## Develop

Ruby 3.3 or newer. There are no gems to install.

```bash
bin/test                 # all unit tests
dev/e2e.sh               # live tests against the local GitLab (needs Docker)
```

The design notes and what we checked in GitLab's source are in
[docs/design.md](./docs/design.md) and [docs/version-audit.md](./docs/version-audit.md).

## Security

CI runs CodeQL, Semgrep and Gitleaks on every push and pull request, and every
action is pinned to a commit SHA. `main` cannot be pushed to directly. The core
has no runtime dependencies. Report vulnerabilities privately through
[SECURITY.md](./SECURITY.md).

## Work with Avytrix

vela is one of the [products we build](https://avytrix.dev/our-work?utm_source=vela&utm_medium=docs&utm_campaign=readme-our-work) at **[Avytrix Technologies](https://avytrix.dev/?utm_source=vela&utm_medium=docs&utm_campaign=readme-services)**.
We also build software for other teams, from a first prototype to something you
run in production.

- **Custom software:** web apps, APIs and internal tools, built and handed over cleanly.
- **Your GitLab or CI setup:** access controls, migrations, hosting and pipelines.
- **Open source with a maintainer:** we ship and support the libraries we publish.

Have a project in mind? [Tell us about it at avytrix.dev](https://avytrix.dev/?utm_source=vela&utm_medium=docs&utm_campaign=readme-contact),
or email **hello@avytrix.dev**.

## Project status and handoff

What is verified, what is untested and what to try next is in [docs/HANDOFF.md](./docs/HANDOFF.md). Per-version test results are in [docs/compat/](./docs/compat/README.md).

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the PR workflow. Testing on a GitLab
version or install method we have not tried is one of the most useful things you
can do right now.

vela is an independent project. It is not made by, endorsed by or affiliated with
GitLab Inc. GitLab is a trademark of GitLab Inc.

## License

MIT
