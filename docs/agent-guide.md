# Agent playbook: install vela and set permissions on a GitLab server

For an AI agent (or a careful human) who has been asked to **put folder and file permissions on a GitLab project**. Work through the steps in order. Do not skip a gate. Each gate says what to check and when to stop and ask.

Rules for working on vela's own code are in [`AGENTS.md`](../AGENTS.md). The long human version of the install is in [`install.md`](./install.md). This page is the checklist an agent follows.

## What you can and cannot promise

Say this to the person who asked, before you change anything:

- vela **enforces write**: a push, web edit or API commit that changes a path the person may not write is rejected.
- vela does **not** stop `git clone` or `git fetch`. Anyone who can fetch has every file. View and Read hiding inside GitLab's pages and API is **not built yet**.
- It is pre-release and tested end to end on **GitLab CE 19.0.2** only.

If they need to keep secrets out of a repository people can clone, vela is the wrong tool. Stop and say so.

## Step 0: Get explicit approval for the target

- Ask which server and which project. Confirm it is **staging or a test project** unless a human clearly says production.
- For production, get an explicit yes **and** confirmation that a backup exists. Never infer approval from an earlier message about a different server.
- You will run commands as root on the GitLab host. Do not run anything you have not read.

**Stop and ask if** you cannot tell whether the server is production.

## Step 1: Discover

Record the answers in your report.

```bash
sudo gitlab-rake gitlab:env:info 2>/dev/null | grep -iE 'GitLab information|Version|Revision'
dpkg -l gitlab-ce gitlab-ee 2>/dev/null | grep ^ii    # or: rpm -q gitlab-ce gitlab-ee
```

| Check | Required |
| ----- | -------- |
| Edition | **CE** (package `gitlab-ce`, or an image `gitlab/gitlab-ce`). Stop on EE. |
| Version | **19.0.x**. Anything else: tell the human it is untested, and continue only if they agree. |
| Install method | Omnibus, Docker, source or Helm. Pick the matching option in [`install.md`](./install.md). Source and Helm are untested. |
| Database role Rails uses | Omnibus default is `gitlab`. Check `postgresql['sql_user']` in `/etc/gitlab/gitlab.rb`. |
| Already installed? | `ls /opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb` |

**Stop and ask if** the edition is not CE, or you cannot reach the database as a superuser (`gitlab-psql`).

## Step 2: Back up

```bash
sudo gitlab-backup create
sudo cp -a /etc/gitlab /root/gitlab-config-backup-$(date +%F)
```

Confirm both succeeded before continuing. Do not proceed on a failed backup.

## Step 3: Install

Follow [`install.md`](./install.md) steps 2 to 5 for the install method you found. Pin the vela commit and write it down.

Then **verify it loaded**. This check is mandatory:

```bash
sudo gitlab-rails runner 'puts Gitlab::Checks::DiffCheck.ancestors.first(2).inspect'
# must print: [PathPermissions::WriteCheck, Gitlab::Checks::DiffCheck]
```

If GitLab fails to boot with `IncompatibleGitLab`, remove the initializer, restart, and report the GitLab version. Do not work around the guard.

## Step 4: Turn the request into rules

The person will describe access in words ("the frontend team edits `frontend/`, everyone can read `docs/`"). Turn that into rules **and show them the plan before writing anything**.

1. Resolve names to **numeric IDs**. Rules use IDs, never names.

   ```bash
   curl -s -H "PRIVATE-TOKEN: $TOKEN" "$GITLAB/api/v4/groups?search=frontend" | python3 -c 'import sys,json;[print(g["id"],g["full_path"]) for g in json.load(sys.stdin)]'
   curl -s -H "PRIVATE-TOKEN: $TOKEN" "$GITLAB/api/v4/users?username=alice" | python3 -c 'import sys,json;[print(u["id"],u["username"]) for u in json.load(sys.stdin)]'
   ```

   Prefer groups over individual users. Do not print the token.

2. Write each rule as `(path, dir|file, group|user, id, level, allow|deny)`.

3. Apply these facts when you plan:
   - Levels: `view`, `read`, `write`. Each needs the ones before it. **Give all three for full access. A `write` rule alone grants nothing.**
   - A path with any allow rule becomes a list: only the people you name can use it. Everyone else loses access to that path, including people who had it before.
   - A path with no rule keeps normal GitLab access.
   - Deny beats allow at the same path. A more specific path beats its folder.
   - Paths have no leading or trailing slash. Case-sensitive.
   - Admins and project Owners are never blocked. Do not try to restrict them.

4. **Dry-run the rules** in the pure evaluator before touching the database. Check at least one allowed and one denied case per rule.

   ```bash
   ruby -I lib -e '
     require "path_permissions/evaluator"; P = PathPermissions
     r = ->(path, type, gid, level, effect) { P::Rule.new(path: path, type: type, principal_type: :group, principal_id: gid, level: level, effect: effect) }
     rules = %i[view read write].map { |l| r.("frontend", :dir, 101, l, :allow) }
     P.validate!(rules)
     puts P.allowed?(rules, user_id: 1, group_ids: [101], path: "frontend/a.js", level: :write)  # true
     puts P.allowed?(rules, user_id: 1, group_ids: [102], path: "frontend/a.js", level: :write)  # false
     puts P.allowed?(rules, user_id: 1, group_ids: [102], path: "README.md",     level: :write)  # true (no rule)
   '
   ```

5. Warn about **lock-out**: if a rule makes a folder an allow-list, say exactly who loses access.

**Stop and ask if** the request says "hide" a path from people who can clone, or asks to restrict an admin or Owner. Explain the limit instead.

## Step 5: Apply

Enable the project, then add rules, in one transaction so a mistake leaves nothing half-applied. Use the SQL in [`install.md`](./install.md) steps 6 and 7.

```bash
sudo gitlab-psql -f - <<'SQL'
BEGIN;
INSERT INTO path_permission_settings (project_id, enabled) VALUES (<PROJECT_ID>, true);
INSERT INTO path_permission_rules (project_id, path, path_type, principal_type, principal_id, level, effect) VALUES
  (<PROJECT_ID>, 'frontend', 'dir', 'group', 101, 'view', 'allow'),
  (<PROJECT_ID>, 'frontend', 'dir', 'group', 101, 'read', 'allow'),
  (<PROJECT_ID>, 'frontend', 'dir', 'group', 101, 'write', 'allow');
COMMIT;
SQL
```

Read the rules back and compare with the plan you showed:

```bash
sudo gitlab-psql -c "SELECT path, path_type, principal_type, principal_id, level, effect FROM path_permission_rules WHERE project_id = <PROJECT_ID> ORDER BY path, principal_id, level;"
```

To undo: `UPDATE path_permission_settings SET enabled = false WHERE project_id = <PROJECT_ID>;`.

## Step 6: Test with real pushes

Do not report success from the database alone. Use two real non-admin users with Developer access, one inside and one outside the allowed group.

| Case | Expect |
| ---- | ------ |
| Allowed user edits an allowed path and pushes | accepted |
| Same user edits a path they may not write | rejected, message does not name a path they cannot view |
| Other user edits the first user's folder | rejected |
| Admin or Owner edits any path | accepted |
| User renames a file out of or into a forbidden folder | rejected |
| A different project with no rules | unchanged |

A protected `main` may refuse Developer pushes on its own. Test on a feature branch, or check the branch's protection first, so you do not blame vela for GitLab's own rule.

If **every** push is rejected with `Path permissions could not be verified`, the database role cannot read the tables. Re-run `schema.sql` with the right `-v app_role=`. Do not leave the server like that. If you cannot fix it quickly, disable the project (`enabled = false`) and report.

## Step 7: Report

Tell the human, plainly:

- GitLab version and edition, install method, the vela commit installed, which project was enabled.
- The exact rules, in a table, and who lost access because of an allow-list.
- Which tests you ran and the real results, including anything that failed or that you did not run.
- The limit: `git clone` and `git fetch` are not restricted; View and Read hiding is not built yet.
- How to roll back, and that **a GitLab upgrade can remove the initializer** (they must re-check after each upgrade, see [`install.md`](./install.md#upgrading-gitlab)).

## Hard rules

- Never edit GitLab's own files. Only add vela's files.
- Never disable GitLab's branch protection or another GitLab check to make a test pass.
- Never run on production without the approval in step 0.
- Never print or store tokens in reports, commits or PRs.
- If something fails and you do not understand why, **stop, roll back with `enabled = false`, and report**. Do not guess at fixes on a live server.
