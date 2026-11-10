-- Add-on tables, created by the installer (not a GitLab migration) in GitLab's own database.
CREATE TABLE IF NOT EXISTS path_permission_settings (
  project_id bigint PRIMARY KEY REFERENCES projects(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT false,
  revision bigint NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS path_permission_rules (
  id bigserial PRIMARY KEY,
  project_id bigint NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  path text NOT NULL CHECK (path <> '' AND path !~ '^/' AND path !~ '//' AND path !~ '(^|/)\.\.?(/|$)'),
  path_type text NOT NULL CHECK (path_type IN ('file', 'dir')),
  principal_type text NOT NULL CHECK (principal_type IN ('user', 'group')),
  principal_id bigint NOT NULL,
  level text NOT NULL CHECK (level IN ('view', 'read', 'write')),
  effect text NOT NULL CHECK (effect IN ('allow', 'deny')),
  created_by bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (project_id, path, path_type, principal_type, principal_id, level)
);

CREATE TABLE IF NOT EXISTS path_permission_audits (
  id bigserial PRIMARY KEY,
  project_id bigint NOT NULL,
  actor_id bigint,
  action text NOT NULL,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Tables are created by a superuser, but Rails connects as the application role (Omnibus: gitlab).
-- Without this grant the add-on fails closed and rejects EVERY push. Run with: psql -v app_role=gitlab
GRANT SELECT, INSERT, UPDATE, DELETE ON path_permission_settings, path_permission_rules, path_permission_audits TO :"app_role";
GRANT USAGE, SELECT ON SEQUENCE path_permission_rules_id_seq, path_permission_audits_id_seq TO :"app_role";
