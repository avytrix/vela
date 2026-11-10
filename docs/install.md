# Install (tier 1: write enforcement) — NOT yet proven on a live GitLab

Omnibus example, on the GitLab server, **staging first**:

1. Copy `lib/` to `/opt/vela-path-permissions/lib/` (or set `VELA_PP_ROOT`).
2. Create tables: `gitlab-psql -f db/schema.sql` (back up first).
3. Copy `overlay/zz_path_permissions.rb` to `/opt/gitlab/embedded/service/gitlab-rails/config/initializers/`.
4. `gitlab-ctl reconfigure && gitlab-ctl restart`. Boot fails loudly if GitLab no longer exposes `DiffCheck#validations_for_path`.
5. Enable a project: `INSERT INTO path_permission_settings (project_id, enabled) VALUES (<id>, true);` then add rules.

Uninstall: set `enabled=false` (or delete the initializer) and restart. Package upgrades overwrite `/opt/gitlab/embedded/...`: re-run step 3.
