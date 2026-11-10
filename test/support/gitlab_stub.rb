# frozen_string_literal: true

# Minimal stand-in for the parts of GitLab CE 19.0.2 the overlay touches. DiffCheck mirrors
# lib/gitlab/checks/diff_check.rb (validate! loop + EE injection point) so the overlay is exercised
# through the same call shape. The real thing is only proven on a live instance.
module Gitlab
  VERSION = '19.0.2'
  class GitAccess
    ForbiddenError = Class.new(StandardError)
  end

  module Checks
    class DiffCheck
      attr_reader :project, :user_access, :changed_paths, :oldrev, :newrev, :branch_name

      def initialize(project:, user_access:, changed_paths:, branch: nil, tag: nil, oldrev: 'a' * 40, newrev: 'b' * 40)
        @project = project
        @user_access = user_access
        @changed_paths = changed_paths
        @branch_name = branch
        @tag = tag
        @oldrev = oldrev
        @newrev = newrev
      end

      def branch_ref?
        !@branch_name.nil?
      end

      def tag_ref?
        !@tag.nil?
      end

      def commits
        []
      end

      def validate!
        return unless should_run_validations?

        changed_paths.each do |path|
          validations_for_path.each do |v|
            error = v.call(path)
            raise ::Gitlab::GitAccess::ForbiddenError, error if error
          end
        end
      end

      private

      def update?
        true
      end

      def deletion?
        false
      end

      def should_run_validations?
        validations_for_path.present?
      end

      def validations_for_path
        []
      end
    end
  end
end

class Object
  def present?
    respond_to?(:empty?) ? !empty? : !!self
  end
end

module Gitlab
  module Git
    DiffTree = Struct.new(:left_tree_id, :right_tree_id)
  end
end
FakeCommit = Struct.new(:tree_id) do
  def id
    'c' * 40
  end
end
# net_paths: what GitLab returns for the old-tip vs new-tip tree diff ([] simulates a swallowed error).
FakeRepo = Struct.new(:trees, :net_paths, :tag_new_commits) do
  def raw_repository
    self
  end

  def commit(rev)
    trees.key?(rev) ? FakeCommit.new(trees[rev]) : nil
  end

  def new_commits(_id)
    tag_new_commits || []
  end

  def find_changed_paths(_objects, **_opts)
    net_paths
  end
end
class ProtectedBranch
  def self.protected?(_project, name)
    name == 'release'
  end
end
FakeProject = Struct.new(:id, :default_branch, :repository)
FakeUser = Struct.new(:id, :admin, :groups, :owner) do
  def admin?
    admin
  end
end
FakeAccess = Struct.new(:user) do
  def can_do_action?(action)
    action == :admin_project && user && user.owner
  end
end
FakePath = Struct.new(:status, :path, :old_path) do
  def initialize(status, path, old_path = nil)
    super(status, path, old_path || path)
  end
end
