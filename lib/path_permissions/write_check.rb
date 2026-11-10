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

    # DiffCheck only sees paths per newly introduced commit (merge commits are diffed against ALL
    # parents), so a merge that lands someone else's change looks empty. On the default and protected
    # branches we therefore also check what the push does to the branch: old tip tree vs new tip tree.
    def validate!
      super
      state = path_permissions_state
      path_permissions_log("project=#{project.id} ref=#{ref rescue '?'} new_commits=#{commits.size rescue '?'} state=#{state.is_a?(Array) ? 'rules' : state}")
      return if state == :off

      raise ::Gitlab::GitAccess::ForbiddenError, UNVERIFIABLE if state == :error
      path_permissions_check_tag_commits!(state)
      path_permissions_check_applied_changes!(state)
    end

    def path_permissions_log(message)
      Rails.logger.info("path_permissions: #{message}") if defined?(Rails)
    end

    private

    # GitLab's new_commits() returns nothing for an annotated tag (newrev is the tag object, not a
    # commit), so commits smuggled in through a tag would never be checked, and would later count as
    # already present. Resolve the tag to its commit and check what is new ourselves.
    def path_permissions_check_tag_commits!(rules)
      return unless tag_ref? && !deletion? && commits.empty?

      repo = project.repository
      target = repo.raw_repository.commit(newrev)
      raise ::Gitlab::GitAccess::ForbiddenError, UNVERIFIABLE if target.nil?

      fresh = repo.new_commits(target.id)
      return if fresh.empty?

      repo.find_changed_paths(fresh, merge_commit_diff_mode: :all_parents).each do |path|
        error = path_permission_error(rules, path)
        raise ::Gitlab::GitAccess::ForbiddenError, error if error
      end
    end

    def path_permissions_check_applied_changes!(rules)
      return unless branch_ref? && update? && path_permissions_landing_branch?

      repo = project.repository
      left = repo.raw_repository.commit(oldrev)&.tree_id
      right = repo.raw_repository.commit(newrev)&.tree_id
      raise ::Gitlab::GitAccess::ForbiddenError, UNVERIFIABLE if left.nil? || right.nil?
      return if left == right

      paths = repo.find_changed_paths([::Gitlab::Git::DiffTree.new(left, right)])
      # The trees differ, so an empty answer means the listing failed (GitLab swallows Gitaly errors here).
      raise ::Gitlab::GitAccess::ForbiddenError, UNVERIFIABLE if paths.empty?

      paths.each do |path|
        error = path_permission_error(rules, path)
        raise ::Gitlab::GitAccess::ForbiddenError, error if error
      end
    end

    def path_permissions_landing_branch?
      project.default_branch == branch_name || ::ProtectedBranch.protected?(project, branch_name)
    end

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
