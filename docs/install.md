# Install guide

This guide installs vela on a self-hosted GitLab Community Edition (CE) server and turns on path permissions for one project. It takes about 20 minutes.

> **Read this first**
>
> - vela is pre-release. It is tested end to end on **GitLab CE 19.0.2 (Omnibus and Docker)** only. See [e2e-results.md](./e2e-results.md).
> - Try it on a **staging copy** before production. A wrong install can block every push on your server.
> - vela **does not stop `git clone` or `git fetch`**. Write rules are enforced. View and Read rules only hide things inside GitLab. See the [README](../README.md#the-one-limit-you-must-know-about).

## What you need

| Need | Notes |
| ---- | ----- |
| GitLab CE **19.0.x** | Check at Admin Area, Overview, or run `gitlab-rake gitlab:env:info`. Other versions may work, and the boot guard tells you if they cannot. |
| Root or sudo on the GitLab server | For Omnibus, you run `gitlab-ctl` and `gitlab-psql`. |
| A recent backup | `gitlab-backup create` (and copy `/etc/gitlab`). |
| An admin account in GitLab | To find group IDs and test. |

GitLab Enterprise Edition (EE) is not covered. vela is built for CE.

## How the install works

You add three things to your server. Nothing in GitLab's own files is edited.

1. The vela `lib/` folder, copied to `/opt/vela-path-permissions/lib`.
2. One initializer file, `overlay/zz_path_permissions.rb`, copied into GitLab's `config/initializers/` folder.
3. Three database tables, created from `db/schema.sql`.

When GitLab boots it loads the initializer. The initializer checks that GitLab still has the push-check hook vela needs. If the hook is gone, GitLab refuses to start rather than run unprotected.

Until you enable a project (step 6), vela changes nothing.

## Option A: Omnibus package (Debian, Ubuntu, RHEL and others)

### 1. Back up

```bash
sudo gitlab-backup create
sudo cp -a /etc/gitlab /root/gitlab-config-backup-$(date +%F)
```

### 2. Get vela

Pick a released tag when one exists. Until then use a commit you have reviewed.

```bash
git clone https://github.com/avytrix/vela.git /tmp/vela
cd /tmp/vela
git log --oneline -1          # note this commit; it is the version you are installing
bin/test                      # needs Ruby 3.3+; optional but quick
```

### 3. Copy the files

```bash
sudo mkdir -p /opt/vela-path-permissions
sudo cp -r lib /opt/vela-path-permissions/
sudo cp overlay/zz_path_permissions.rb \
  /opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb
```

### 4. Create the database tables

`app_role` is the database user GitLab connects as. On Omnibus it is `gitlab`. **Do not skip the role name:** without the grant GitLab cannot read the tables and rejects every push.

```bash
sudo gitlab-psql -v app_role=gitlab -f /tmp/vela/db/schema.sql
```

You should see `CREATE TABLE` three times and `GRANT` twice. If you changed `postgresql['sql_user']` in `gitlab.rb`, use that name instead of `gitlab`.

### 5. Restart GitLab and check it loaded

```bash
sudo gitlab-ctl restart
sudo gitlab-rails runner 'puts Gitlab::Checks::DiffCheck.ancestors.first(2).inspect'
```

Expected output:

```
[PathPermissions::WriteCheck, Gitlab::Checks::DiffCheck]
```

If GitLab does not start and the log mentions `IncompatibleGitLab`, your GitLab version no longer exposes the hook vela uses. Remove the initializer (see [Uninstall](#uninstall)) and open an issue with your version.

### 6. Turn it on for one project

Find the project ID (Project, Settings, General, or the number on the project page) and the IDs of the groups you want to give access to (Group, Settings, General, "Group ID").

Start with a test project, not a live one.

```bash
sudo gitlab-psql -f - <<'SQL'
-- Replace 42 with your project ID.
INSERT INTO path_permission_settings (project_id, enabled) VALUES (42, true);
SQL
```

At this point nothing is restricted. A project with vela enabled but no rules behaves exactly like normal GitLab.

### 7. Add rules

A rule says: for this path, this user or group is **allowed** or **denied** this level (`view`, `read` or `write`). Each level includes the one before it, so give `view`, `read` and `write` together for full access. **A `write` rule on its own grants nothing**, because Write also needs Read and View.

Example: group 101 owns `frontend/`, group 102 owns `backend/`, both can read `docs/` and only 101 can edit it.

```bash
sudo gitlab-psql -f - <<'SQL'
-- columns: project, path, path_type (dir|file), principal_type (group|user), principal id, level, effect
INSERT INTO path_permission_rules
  (project_id, path, path_type, principal_type, principal_id, level, effect) VALUES
  (42, 'frontend', 'dir', 'group', 101, 'view',  'allow'),
  (42, 'frontend', 'dir', 'group', 101, 'read',  'allow'),
  (42, 'frontend', 'dir', 'group', 101, 'write', 'allow'),
  (42, 'backend',  'dir', 'group', 102, 'view',  'allow'),
  (42, 'backend',  'dir', 'group', 102, 'read',  'allow'),
  (42, 'backend',  'dir', 'group', 102, 'write', 'allow'),
  (42, 'docs',     'dir', 'group', 101, 'view',  'allow'),
  (42, 'docs',     'dir', 'group', 101, 'read',  'allow'),
  (42, 'docs',     'dir', 'group', 101, 'write', 'allow'),
  (42, 'docs',     'dir', 'group', 102, 'view',  'allow'),
  (42, 'docs',     'dir', 'group', 102, 'read',  'allow');
SQL
```

Rules to remember:

- Paths have **no leading slash** and no trailing slash: `frontend`, not `/frontend/`. A `dir` rule covers everything inside it. Matching is case-sensitive.
- A path with **no rule** keeps GitLab's normal permissions.
- A path with **any allow rule** is a list: only the people you name can use it.
- A **deny** always wins over an allow at the same path. A more specific path (a file inside a folder) wins over the folder.
- Instance admins and project Owners are never blocked.
- vela only takes access away. Someone who cannot push in GitLab still cannot push.

To undo a rule: `DELETE FROM path_permission_rules WHERE id = ...;`. To switch a project off: `UPDATE path_permission_settings SET enabled = false WHERE project_id = 42;`.

A settings page inside GitLab for managing rules is planned. Until then, the database is the interface.

### 8. Test it

Use two non-admin users, one in each group, with Developer access to the project.

1. As a user in group 101, edit a file in `frontend/` and push. It should **succeed**.
2. As the same user, edit a file in `backend/` and push. It should be **rejected** with `You are not allowed to change ...` or `... a protected path in this push`.
3. See what vela decided: `sudo grep -rh path_permissions /var/log/gitlab/gitlab-rails/ | tail`. Each push logs the project, ref, and whether rules applied.

You can also run the full test suite against a throwaway GitLab instead: see [Try it locally](../README.md#try-it-locally).

Branch protection still applies. If your Developers cannot push to `main` anyway, test on a feature branch.

### 9. Roll out

Enable the next project only after the first one behaves. Keep the backup from step 1 until you are sure.

## Option B: Docker

Mount the two vela pieces into the official image. Create the tables after the first start (step 4 above, using `docker exec -i <container> gitlab-psql ...`).

```bash
docker run -d --name gitlab ... \
  -v /path/to/vela/lib:/opt/vela-path-permissions/lib:ro \
  -v /path/to/vela/overlay/zz_path_permissions.rb:/opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb:ro \
  gitlab/gitlab-ce:19.0.2-ce.0
```

Docker Compose is the same two `volumes:` lines. [`dev/up.sh`](../dev/up.sh) is a complete working example, and it is the setup the end-to-end tests run on. Because the mounts are read-only host files, a container upgrade does not remove them.

## Option C: GitLab installed from source

Same three pieces, different paths. Not tested yet.

```bash
# as the git user, in /home/git/gitlab (adjust to your install)
cp -r /path/to/vela/lib /opt/vela-path-permissions/lib
cp /path/to/vela/overlay/zz_path_permissions.rb config/initializers/
sudo -u postgres psql -d gitlabhq_production -v app_role=git -f /path/to/vela/db/schema.sql
sudo service gitlab restart
```

Set `app_role` to the database user in your `config/database.yml`.

## Option D: Kubernetes (Helm chart)

Not tested. The initializer must exist in the **webservice** and **sidekiq** images, and `lib/` must be readable at `/opt/vela-path-permissions/lib` in both. The usual route is a small custom image built `FROM` the GitLab CE images that adds those files. Create the tables against the chart's PostgreSQL with the same `schema.sql`. If you try this, please tell us how it went.

## Upgrading GitLab

A GitLab upgrade can replace files under `/opt/gitlab/embedded/service/gitlab-rails`. After **every** upgrade:

```bash
ls /opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb
sudo gitlab-rails runner 'puts Gitlab::Checks::DiffCheck.ancestors.first(2).inspect'
```

If the file is gone, copy it back (step 3) and restart. A missing initializer means **no write checks at all**, so make this check part of your upgrade routine. Test the new GitLab version on staging first: only 19.0.x is tested.

## Uninstall

1. Switch projects off, or leave the tables in place:

   ```bash
   sudo gitlab-psql -c "UPDATE path_permission_settings SET enabled = false;"
   ```

2. Remove the initializer and restart:

   ```bash
   sudo rm /opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb
   sudo gitlab-ctl restart
   ```

3. Optional, deletes your rules and audit history for good:

   ```bash
   sudo gitlab-psql -c "DROP TABLE path_permission_audits, path_permission_rules, path_permission_settings;"
   ```

**Removing vela removes the protection.** Pushes that were blocked will go through again, and rules do nothing.

## Troubleshooting

| What you see | Likely cause and fix |
| ------------ | -------------------- |
| **Every push is rejected** with `Path permissions could not be verified` | GitLab cannot read the tables. Re-run `schema.sql` with the right `-v app_role=`. vela fails closed on purpose. |
| GitLab does not boot, log says `IncompatibleGitLab` | Your GitLab version changed the hook vela uses. Remove the initializer and open an issue with the version. |
| GitLab does not boot, log says `cannot load such file -- path_permissions/install` | `lib/` is not at `/opt/vela-path-permissions/lib`. Check the path, or set `VELA_PP_ROOT`. |
| **Every push to one project is rejected** after adding a rule | A rule row is malformed (for example a path with a trailing slash). vela fails closed. Fix or delete the row. The schema blocks the common mistakes. |
| Nothing is ever rejected | The initializer is missing or GitLab was not restarted, or the project is not enabled. Run the check in step 5, and `SELECT * FROM path_permission_settings;`. |
| A path you did not expect is blocked | Run `SELECT * FROM path_permission_rules WHERE project_id = 42;` and look for an allow rule on a parent folder. Any allow rule turns that path into a list. |
| The reject message names no file | Intended. People who cannot view a path are not told its name. |
| An admin or Owner is not blocked | Intended. They are never locked out. |

## Known limits

- `git clone` and `git fetch` are not restricted. Do not rely on vela to hide secrets.
- Only pushes, web edits and API commits are checked for **write**. Pushes to refs that are not branches or tags are not covered.
- View and Read hiding covers the file browser, file content, raw, blame, search, diffs, the API and GraphQL. It does **not** cover commit history and messages, archives, `repository/blobs/:sha`, project export, or the compare endpoint. See [read-design.md](./read-design.md).
- Tested on GitLab CE 19.0.2. See [e2e-results.md](./e2e-results.md) for exactly what was run.

Questions and bug reports: [open an issue](https://github.com/avytrix/vela/issues/new/choose). Security problems: see [SECURITY.md](../SECURITY.md).
