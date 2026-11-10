# Security Policy

vela decides who may change or see paths in a GitLab project, so we treat
access-check bugs as security bugs.

## Reporting a vulnerability

**Please do not report security vulnerabilities through public issues, discussions or pull requests.**

Report privately through GitHub: [Report a vulnerability](https://github.com/avytrix/vela/security/advisories/new).
Only the maintainers can see the report.

Please include:

- what the vulnerability is and what an attacker could do with it
- steps to reproduce, ideally the rules involved (path, user or group, level) and the push or request you made
- the GitLab CE version, install method and vela version or commit

We acknowledge reports within **72 hours**, work with you on a fix, and agree a
disclosure date. Please give us reasonable time to ship a fix before disclosing
publicly. We credit reporters in the advisory unless you prefer otherwise.

## Scope

In scope:

- A push, web edit or API commit that changes a path the actor has no write permission on.
- Any way to switch the add-on off, or make it fail open, without an administrator doing it.
- A denial message that reveals the name of a path the actor cannot view.
- Privilege escalation in who can edit rules (for example a Maintainer granting more than they hold).
- Injection or unsafe handling in the add-on's own code and SQL.

Out of scope:

- **Git clone and fetch are not restricted.** Anyone who can fetch the repository gets
  every path in its history. View and Read rules only hide paths inside GitLab's own
  pages and API. This is a documented limit of the design, not a vulnerability.
  Do not use vela to keep secrets out of a repository people can clone.
- Vulnerabilities in GitLab itself. Report those to [GitLab](https://about.gitlab.com/security/disclosure/).
- Anything that needs administrator or database access to the GitLab server.

## Supported versions

vela is pre-release. Security fixes go to the `main` branch only.

| GitLab CE | Status                  |
| --------- | ----------------------- |
| 19.0.x    | Targeted, in development |
| Others    | Not supported yet        |

## How the repository is protected

- Nobody can push to `main` directly, force-push it or delete it. Every change lands through a reviewed pull request.
- Only maintainers can create release tags, and tags cannot be moved or deleted.
- Secret scanning with push protection, CodeQL, Semgrep and Gitleaks run on this repository.
  Every GitHub Action is pinned to a commit SHA.
- The add-on has no runtime dependencies, so there is no dependency tree to poison.
- The add-on fails closed. If it cannot read its rules, or GitLab no longer exposes the hook it
  relies on, it rejects the push or refuses to boot. It never quietly lets changes through.

Maintained by [Avytrix Technologies](https://avytrix.dev/?utm_source=vela&utm_medium=docs&utm_campaign=security).
