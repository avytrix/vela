# frozen_string_literal: true

require 'json'
require_relative 'evaluator'
require_relative 'store'

module PathPermissions
  # Reads and writes the add-on's tables for the settings page. Every change is validated as a whole rule
  # set, runs in one transaction, bumps the project's revision and writes an audit row.
  module Admin
    class Error < StandardError; end

    module_function

    def db
      ::ApplicationRecord
    end

    def q(sql, *binds)
      db.sanitize_sql_array([sql, *binds])
    end

    def conn
      db.connection
    end

    def enabled?(project_id)
      conn.select_value(q('SELECT enabled FROM path_permission_settings WHERE project_id = ?', project_id)) == true
    end

    def revision(project_id)
      conn.select_value(q('SELECT revision FROM path_permission_settings WHERE project_id = ?', project_id)).to_i
    end

    # [{id:, rule: Rule}]
    def rules(project_id)
      conn.select_rows(q('SELECT id, path, path_type, principal_type, principal_id, level, effect FROM path_permission_rules ' \
                         'WHERE project_id = ? ORDER BY path, principal_type, principal_id', project_id)).map do |id, path, type, pt, pid, level, effect|
        { id: id.to_i, rule: Rule.new(path: path, type: type.to_sym, principal_type: pt.to_sym, principal_id: pid.to_i,
                                     level: level.to_sym, effect: effect.to_sym) }
      end
    end

    def audits(project_id, limit = 20)
      conn.select_rows(q('SELECT created_at, actor_id, action, after_state::text FROM path_permission_audits ' \
                         'WHERE project_id = ? ORDER BY id DESC LIMIT ?', project_id, limit))
    end

    def set_enabled!(project_id, on, actor_id)
      transaction(project_id, actor_id, on ? 'enable' : 'disable', {}) do
        conn.execute(q('INSERT INTO path_permission_settings (project_id, enabled, revision) VALUES (?, ?, 1) ' \
                       'ON CONFLICT (project_id) DO UPDATE SET enabled = EXCLUDED.enabled, revision = path_permission_settings.revision + 1',
                       project_id, on))
      end
    end

    # Adds one row per ticked level. Raises Error for anything invalid or conflicting.
    def add_rule!(project_id, path:, type:, principal_type:, principal_id:, levels:, effect:, actor_id:)
      clean = path.to_s.strip.sub(%r{\A/+}, '').sub(%r{/+\z}, '')
      raise Error, 'Path must not be empty' if clean.empty?
      raise Error, 'Pick at least one level' if levels.empty?

      new_rules = levels.map do |l|
        Rule.new(path: clean, type: type.to_sym, principal_type: principal_type.to_sym, principal_id: principal_id.to_i,
                 level: l.to_sym, effect: effect.to_sym)
      end
      begin
        PathPermissions.validate!(rules(project_id).map { |r| r[:rule] } + new_rules)
      rescue InvalidRule => e
        raise Error, e.message
      end
      transaction(project_id, actor_id, 'add_rule', new_rules.map(&:to_h)) do
        ensure_settings!(project_id)
        new_rules.each do |r|
          conn.execute(q('INSERT INTO path_permission_rules (project_id, path, path_type, principal_type, principal_id, level, effect, created_by) ' \
                         'VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING',
                         project_id, r.path, r.type.to_s, r.principal_type.to_s, r.principal_id, r.level.to_s, r.effect.to_s, actor_id))
        end
      end
    end

    # Removes every level of one (path, principal) pair.
    def delete_pair!(project_id, path:, type:, principal_type:, principal_id:, actor_id:)
      transaction(project_id, actor_id, 'delete_rule', { path: path, principal_type: principal_type, principal_id: principal_id }) do
        conn.execute(q('DELETE FROM path_permission_rules WHERE project_id = ? AND path = ? AND path_type = ? AND principal_type = ? AND principal_id = ?',
                       project_id, path, type, principal_type, principal_id))
      end
    end

    def ensure_settings!(project_id)
      conn.execute(q('INSERT INTO path_permission_settings (project_id, enabled, revision) VALUES (?, false, 0) ON CONFLICT DO NOTHING', project_id))
    end

    def transaction(project_id, actor_id, action, detail)
      db.transaction do
        yield
        conn.execute(q('UPDATE path_permission_settings SET revision = revision + 1 WHERE project_id = ?', project_id)) unless action.start_with?('enable', 'disable')
        conn.execute(q('INSERT INTO path_permission_audits (project_id, actor_id, action, after_state) VALUES (?, ?, ?, ?::jsonb)',
                       project_id, actor_id, action, JSON.generate(detail)))
      end
    end
  end
end
