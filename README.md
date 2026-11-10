# vela

[![license](https://img.shields.io/github/license/avytrix/vela?color=E0234E)](./LICENSE)
[![CI](https://github.com/avytrix/vela/actions/workflows/ci.yml/badge.svg)](https://github.com/avytrix/vela/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/avytrix/vela?style=social)](https://github.com/avytrix/vela)
[![Sponsor @avytrix](https://img.shields.io/badge/Sponsor-%40avytrix-db61a2?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/avytrix)

**Folder and file permissions for self-hosted GitLab CE.** Decide which users and groups can view, read or write each path in a project, without paying for a higher GitLab tier.

Built and maintained by **[Avytrix Technologies](https://avytrix.dev/?utm_source=vela&utm_medium=docs&utm_campaign=readme)**. Need help shipping? [Hire the team behind it](#work-with-avytrix).

> **Early days.** Write enforcement is built and tested against a stand-in for GitLab. It has not been proven on a live GitLab yet, so do not rely on it in production. See [Status](#status).

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
| Write enforcement on push (GitLab CE 19.0.x) | Built. Tested against a stand-in. Live end-to-end tests are next |
| Hiding paths in the GitLab web UI, API and search | Planned |
| Settings page under Project Settings | Planned |
| Other GitLab CE versions, Docker, Helm, source installs | Planned |

## The one limit you must know about

**vela does not stop `git clone` or `git fetch`.** Git sends the whole history in
one piece, and one repository cannot hide part of itself from someone who can
fetch it.

- **Write rules are enforced.** A push that touches a path the person may not
  change is rejected before it lands.
- **View and Read rules hide things inside GitLab**: file lists, the file
  viewer, search and the API. They are not a vault. Anyone who can clone the
  repository has every file.

So use vela to keep people from changing the wrong things and to tidy what they
see. Do not use it to keep secrets out of a repository people can clone. If you
need that, split the secret into its own project.

## How it works

vela is an overlay, not a fork of GitLab. It is one initializer file plus a few
small Ruby modules, and it does not patch GitLab's source.

```
lib/path_permissions/
  evaluator.rb     the rules engine, plain Ruby, knows nothing about GitLab
  write_check.rb   plugs into GitLab's push checks and rejects forbidden changes
  store.rb         reads rules from the add-on's own tables
  install.rb       boot guard, refuses to start if GitLab changed the hook it uses
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

## Try it locally

You need Docker (Colima works too). This starts a throwaway GitLab CE 19.0.2 with vela loaded:

```bash
dev/up.sh                # first boot takes 5 to 10 minutes
# open http://localhost:8929, sign in as root, password is in dev/.root_password
docker exec -i vela-gitlab-ce gitlab-psql -v app_role=gitlab -f - < db/schema.sql
```

The instance has no mirrors, webhooks or email. Install notes for a real server
are in [docs/install.md](./docs/install.md). Read them as untested for now.

## Develop

Ruby 3.3 or newer. There are no gems to install.

```bash
bin/test                 # all tests
ruby test/evaluator_test.rb
```

The design notes and what we checked in GitLab's source are in
[docs/design.md](./docs/design.md) and [docs/version-audit.md](./docs/version-audit.md).

## Security

CI runs CodeQL, Semgrep and Gitleaks on every push and pull request, and every
action is pinned to a commit SHA. `main` cannot be pushed to directly. The core
has no runtime dependencies. Report vulnerabilities privately through
[SECURITY.md](./SECURITY.md).

## Work with Avytrix

vela is one of the things we build at **[Avytrix Technologies](https://avytrix.dev/?utm_source=vela&utm_medium=docs&utm_campaign=readme-services)**.
We also build software for other teams, from a first prototype to something you
run in production.

- **Custom software:** web apps, APIs and internal tools, built and handed over cleanly.
- **Your GitLab or CI setup:** access controls, migrations, hosting and pipelines.
- **Open source with a maintainer:** we ship and support the libraries we publish.

Have a project in mind? [Tell us about it at avytrix.dev](https://avytrix.dev/?utm_source=vela&utm_medium=docs&utm_campaign=readme-contact),
or email **hello@avytrix.dev**.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the PR workflow. Testing on a GitLab
version or install method we have not tried is one of the most useful things you
can do right now.

vela is an independent project. It is not made by, endorsed by or affiliated with
GitLab Inc. GitLab is a trademark of GitLab Inc.

## License

MIT
