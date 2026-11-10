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

## Pick your tier

vela has two tiers. Read [portability.md](./portability.md) for why.

| | Tier A: server hook | Tier B: overlay |
| --- | --- | --- |
| Blocks forbidden **writes** | Yes | Yes |
| **Hides** paths (View and Read) in the UI, API, search | No | Yes |
| Depends on GitLab internals | **No**, only documented behaviour | Yes, with a boot check |
| Works on any CE version and install method | **Yes** | Tested versions only |

Start with **Tier A** if you want the most portable setup, or if you only need to stop unwanted changes. Add **Tier B** to hide paths. The options below install Tier B (A, B and C are the install methods). Tier A has its own section next.

## Tier A: the server hook (any GitLab CE)

This uses GitLab's documented [global server hooks](https://docs.gitlab.com/administration/server_hooks/). Nothing inside GitLab is changed, so upgrades and downgrades cannot remove it.

**1. Copy the files** on every server that runs Gitaly (one server on most installs):

```bash
sudo mkdir -p /opt/vela-path-permissions
sudo cp -r lib server-hook /opt/vela-path-permissions/
```

**2. Turn on global server hooks and install the hook.** On a Linux package install, global hooks are **off until you set a directory**. Add this to `/etc/gitlab/gitlab.rb` (it is GitLab's own suggested value), then run `sudo gitlab-ctl reconfigure`:

```ruby
gitaly['configuration'] = { hooks: { custom_hooks_dir: '/var/opt/gitlab/gitaly/custom_hooks' } }
```

If your `gitlab.rb` already has a `gitaly['configuration']` block, add the `hooks:` entry to it instead of replacing it. Then create the hook, **owned by the git user and executable**:

```bash
D=/var/opt/gitlab/gitaly/custom_hooks
sudo mkdir -p $D/pre-receive.d
sudo cp /opt/vela-path-permissions/server-hook/vela $D/pre-receive.d/vela
sudo chown -R git:git $D && sudo chmod 755 $D/pre-receive.d/vela
```

For source installs the directory is `custom_hooks_dir` in `gitaly/config.toml` under `[hooks]` (or `gitlab-shell/config.yml`), and for Helm see the [Gitaly chart](https://docs.gitlab.com/charts/charts/gitlab/gitaly/#global-server-hooks). GitLab's own page is [Git server hooks](https://docs.gitlab.com/administration/server_hooks/).

**3. Give it a token.** Create a token for an admin user with the `read_api` scope (Admin Area, or Profile, Access tokens). The hook uses it to read each project's policy and to check group membership.

```bash
sudo mkdir -p /etc/vela
sudo sh -c 'printf "VELA_GITLAB_URL=http://127.0.0.1:8080\nVELA_TOKEN=<your token>\n" > /etc/vela/hook.env'
sudo chown root:git /etc/vela/hook.env && sudo chmod 640 /etc/vela/hook.env
```

`VELA_GITLAB_URL` is an address the Gitaly server can reach GitLab on (on a single-server Linux package install, `http://127.0.0.1:8080`, or your external URL). If this file is wrong or missing, **every push to an enabled project is rejected**. That is deliberate.

**3b. (Docker or non-standard Ruby)** The hook script runs GitLab's own embedded Ruby, or `ruby` from `PATH`. It needs no gems.

**4. Turn it on per project.** Add a project CI/CD variable named `VELA_PATH_POLICY` (Project, Settings, CI/CD, Variables). Only Maintainers and Owners can see or change it, and it is not part of the repository. Its value is JSON, using the same rules as the database tables:

```json
{
  "enabled": true,
  "rules": [
    {"path": "frontend", "type": "dir", "principal_type": "group", "principal_id": 101, "level": "view",  "effect": "allow"},
    {"path": "frontend", "type": "dir", "principal_type": "group", "principal_id": 101, "level": "read",  "effect": "allow"},
    {"path": "frontend", "type": "dir", "principal_type": "group", "principal_id": 101, "level": "write", "effect": "allow"}
  ]
}
```

The rule semantics are the same as in step 7 of the install below. Set `"enabled": false` or delete the variable to switch a project off. A malformed policy rejects every push to that project, so keep a second Owner ready.

Do not mark the variable "Masked" (it holds JSON, not a secret). Group membership counts inherited members, but not groups shared into another group.

**5. Test it** the same way as step 8 below. A rejected push shows `GL-HOOK-ERR:` followed by the reason. Set `VELA_DEBUG=1` in the hook environment to see why a push was rejected as "could not be verified".

Run `bin/doctor` any time, and after every upgrade, to see what is installed and working.

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

## Upgrading and downgrading GitLab

**Tier A (hook)** needs nothing: it lives outside GitLab's files. Run `bin/doctor` afterwards.

**Tier B (overlay)** is one file inside GitLab's directory, which a package upgrade may replace. Make it restore itself by adding this to `/etc/gitlab/gitlab.rb`. That file survives upgrades, and Chef evaluates it on **every** `gitlab-ctl reconfigure`, which every package upgrade runs:

```ruby
require 'fileutils'
FileUtils.cp('/opt/vela-path-permissions/overlay/zz_path_permissions.rb',
             '/opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb')
```

Then `sudo gitlab-ctl reconfigure`. (`dev/up.sh` uses exactly this for Docker, and it survives container recreation.) For installs without `gitlab.rb` (source), copy the file again after each upgrade.

After **every** upgrade or downgrade:

```bash
sudo bin/doctor --deep
```

A missing initializer means **no write checks and no hiding from the overlay**. If GitLab refuses to start with `IncompatibleGitLab`, the new version changed something the overlay wraps: install Tier A (it still protects writes) and open an issue with the version. Test new GitLab versions on staging first, and check [compat/](./compat/) for which versions have passed.

Downgrades: the add-on's tables are not touched by GitLab's migrations, so they are still there. GitLab itself only supports a downgrade through a database restore.

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
