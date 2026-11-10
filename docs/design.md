# Design: portable overlay add-on

Goal: work on any GitLab CE (Omnibus, Docker, Helm, source), any host. So: **no forked source, no per-file patches.**

```
core/      evaluator (pure Ruby, version-independent)            <- lib/path_permissions/evaluator.rb
overlay/   one Rails initializer + prepended modules             <- copied into config/initializers/
adapters/  per-GitLab-version shims (method names/signatures)    <- v19_0.rb, ... selected by Gitlab::VERSION
installer  creates tables, copies overlay, verifies, can uninstall
```

## Why overlay
- Write: prepend `Gitlab::Checks::DiffCheck#validations_for_path` (CE no-op) -> evaluator on every changed path (+ `old_path` for renames), actor = `user_access.user`. Runs in Rails for every push; no Gitaly hook install per node.
- Read: prepend guards on controllers/API (needs user; `Repository` has none).
- UI: one new route + controller + Vue/HAML page under Settings -> Repository.
- Upgrade safety: adapter selected by `Gitlab::VERSION`; at boot assert every prepended method still exists with the expected arity, else **disable the add-on and lock enabled projects** (fail closed), never silently open.

## Tiers (ship in this order)
1. **v19.0.2 write enforcement** (DiffCheck overlay) + evaluator + tables + audit.
2. v19.0.2 read hiding (tree/blob/raw/files API/search/diffs/blame/history).
3. Settings UI.
4. Adapters for other CE versions; Docker/Helm/source installers; compatibility matrix in CI.

## Known limits
- Git clone/fetch stays open: View/Read are not confidential (accepted decision).
- DB: add-on tables (`path_permission_*`) created by the add-on installer, not GitLab migrations, to avoid upgrade schema-check conflicts (UNVERIFIED).
