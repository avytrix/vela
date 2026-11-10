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
      attr_reader :project, :user_access, :changed_paths

      def initialize(project:, user_access:, changed_paths:)
        @project = project
        @user_access = user_access
        @changed_paths = changed_paths
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

FakeProject = Struct.new(:id)
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
