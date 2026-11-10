# frozen_string_literal: true

require_relative 'evaluator'

module PathPermissions
  # Reads rules from the add-on's tables (db/schema.sql) in GitLab's own database.
  # Returns nil when the project has not enabled path permissions.
  module Store
    module_function

    def rules_for(project_id)
      db = ::ApplicationRecord
      return unless db.connection.select_value(db.sanitize_sql_array(
        ['SELECT enabled FROM path_permission_settings WHERE project_id = ?', project_id]
      )) # ponytail: one query per push; add request-store caching if it shows up in profiles

      db.connection.select_rows(db.sanitize_sql_array(
        ['SELECT path, path_type, principal_type, principal_id, level, effect ' \
         'FROM path_permission_rules WHERE project_id = ?', project_id]
      )).map do |path, type, ptype, pid, level, effect|
        Rule.new(path: path, type: type.to_sym, principal_type: ptype.to_sym,
                 principal_id: pid.to_i, level: level.to_sym, effect: effect.to_sym)
      end.tap { |rules| PathPermissions.validate!(rules) }
    end

    # Direct + inherited + shared groups, as GitLab itself resolves them.
    def group_ids_for(user)
      user.authorized_groups.pluck(:id)
    end
  end
end
