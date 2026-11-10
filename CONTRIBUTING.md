# Contributing to vela

Thanks for your interest in contributing. This project is open source (MIT) and
welcomes issues and pull requests from everyone.

## Ways to contribute

- **Report a bug:** open a [Bug report](https://github.com/avytrix/vela/issues/new/choose) issue.
- **Request a feature:** open a Feature request issue.
- **Fix or improve:** send a pull request (see below). Merged PRs make you a project contributor.
- **Test it on your GitLab:** we only have CE 19.0.2 covered. Reports from other versions and install methods are very welcome.
- **Ask or discuss:** use [Discussions](https://github.com/avytrix/vela/discussions).
- **Fund the work:** [sponsor on GitHub](https://github.com/sponsors/avytrix). It keeps vela maintained and free.

## Development setup

Requirements: **Ruby 3.3 or newer** (GitLab CE 19.0 uses 3.3). The core has no gems to install.

```bash
# 1. Fork the repo on GitHub, then clone YOUR fork
git clone https://github.com/<your-username>/vela.git
cd vela

# 2. Add the upstream remote (to keep your fork in sync)
git remote add upstream https://github.com/avytrix/vela.git

# 3. Run the tests
bin/test
```

The tests run against a small stand-in for GitLab's classes (`test/support/gitlab_stub.rb`),
so they are fast, but they do not prove behaviour on a real GitLab. For that, start the
local container and run your change against it:

```bash
dev/up.sh     # GitLab CE 19.0.2 in Docker, http://localhost:8929
```

Docker is needed for that step only. It is a throwaway instance with no mirrors, webhooks or email.

## Pull request workflow

External contributors work from a **fork**; you do not need write access.

1. Sync your fork's `main` with upstream: `git fetch upstream && git rebase upstream/main`.
2. Create a branch off `main`: `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`, `test/<short-name>` or `chore/<short-name>`.
3. Make your change **with tests**, and keep `bin/test` green.
4. Update the docs in the same change if behaviour changes.
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/), for example `fix(write-check): reject renames out of a protected folder`.
6. Push to your fork and open a pull request against `avytrix/vela:main`.
7. Fill in the PR template. CI runs automatically and must pass. On your first PRs a maintainer
   approves the CI run before it starts; that is a safety rule for outside contributors, not a judgement.
8. A maintainer reviews. Address feedback by pushing more commits to the same branch.

## Collaborator guidelines

These rules apply to everyone with write access, and GitHub enforces most of them.

**Branches and merging**

- `main` is protected by a ruleset: no direct pushes, no force pushes, no deletion.
- A PR merges only when it has an approving review from a code owner (`.github/CODEOWNERS`),
  every review conversation is resolved, the branch is up to date with `main`, and these
  checks pass: `test (Ruby 3.3)`, `test (Ruby 3.4)`, `Semgrep SAST` and `Gitleaks secret scan`.
- PRs are squash-merged, so the PR title becomes the commit on `main`. Write it as a
  Conventional Commit. Branches are deleted after merge.
- New pushes to a PR dismiss earlier approvals; ask for a fresh review.

**Reviews**

- Review for correctness, tests and docs. For anything that touches an access check, ask
  "what does this let through that it did not before?"
- Do not approve your own work through a second account, and do not merge a PR you have not read.

**Releases**

- Only maintainers create `v*` tags. Tags are protected; they cannot be moved or deleted.

**Security**

- Never commit secrets or `.env` files. Push protection blocks known secret formats; if it
  flags something, rotate the secret instead of bypassing the block.
- New GitHub Actions must be pinned to a full commit SHA.
- Keep the core free of runtime dependencies. An access-control add-on should be small enough to read in one sitting.
- Vulnerabilities go through [SECURITY.md](./SECURITY.md), never public issues.

## Coding standards

- Plain Ruby, no gems in `lib/`. Keep `lib/path_permissions/evaluator.rb` free of any GitLab or Rails reference.
- Every access decision fails closed: on an error, deny.
- Never put a path name in a message for someone who cannot view that path.
- Add or adjust tests for any behaviour change, and write the test that fails first.
- Keep changes focused: one logical change per PR.
- Write docs in plain language. No filler, and no em dashes used as punctuation.
