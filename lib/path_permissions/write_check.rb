# frozen_string_literal: true

require_relative 'evaluator'
require_relative 'store'

module PathPermissions
  # Prepended to Gitlab::Checks::DiffCheck. DiffCheck#validate! calls every lambda returned by
  # #validations_for_path once per changed path (across ALL newly pushed commits, so an
  # unauthorized intermediate change is caught even if a later commit reverts it) and raises
  # GitAccess::ForbiddenError with the returned string.
  module WriteCheck
    DENIED = 'You are not allowed to change a protected path in this push.'
    UNVERIFIABLE = 'Path permissions could not be verified for this push; it was rejected.'

    private

    def validations_for_path
      base = super
      state = path_permissions_state
      return base if state == :off

      base + [->(path) { path_permission_error(state, path) }]
    end

    # :off (feature disabled), :error (fail closed), or the rules array.
    def path_permissions_state
      return @path_permissions_state if defined?(@path_permissions_state)

      @path_permissions_state = Store.rules_for(project.id) || :off
    rescue StandardError => e
      Rails.logger.error("path_permissions: #{e.class}: #{e.message}") if defined?(Rails)
      @path_permissions_state = :error
    end

    def path_permission_error(rules, path)
      return UNVERIFIABLE if rules == :error

      user = user_access.user
      # ponytail: deploy keys / unmapped actors have no user id, so they cannot be matched to a rule.
      # Denied while rules exist; allow explicit trusted deploy keys later if needed.
      return DENIED if user.nil?
      return if path_permission_exempt?(user)

      groups = Store.group_ids_for(user)
      needs = path_permission_requirements(path)
      return if needs.all? { |p, level| PathPermissions.allowed?(rules, user_id: user.id, group_ids: groups, path: p, level: level) }

      # Do not reveal a path name to someone who cannot even view it.
      visible = PathPermissions.allowed?(rules, user_id: user.id, group_ids: groups, path: path.path, level: :view)
      visible ? "You are not allowed to change '#{path.path}' (path permissions)." : DENIED
    rescue StandardError => e
      Rails.logger.error("path_permissions: #{e.class}: #{e.message}") if defined?(Rails)
      UNVERIFIABLE
    end

    # Admins and project Owners are never locked out (plan guardrail).
    def path_permission_exempt?(user)
      user.admin? || user_access.can_do_action?(:admin_project)
    end

    # [path, level] pairs that must all pass. Rename: both sides. Copy: read source, write destination.
    def path_permission_requirements(path)
      case path.status
      when :RENAMED then [[path.old_path, :write], [path.path, :write]]
      when :COPIED then [[path.old_path, :read], [path.path, :write]]
      else [[path.path, :write]]
      end
    end
  end
end
