# frozen_string_literal: true

require_relative 'write_check'

module PathPermissions
  class IncompatibleGitLab < StandardError; end

  # Boot guard: refuse to start unprotected if GitLab changed the hook we rely on.
  module Install
    TESTED = %w[19.0].freeze

    module_function

    def call(diff_check = ::Gitlab::Checks::DiffCheck, version = ::Gitlab::VERSION)
      verify!(diff_check)
      diff_check.prepend(WriteCheck) unless diff_check.include?(WriteCheck)
      warn_untested(version)
    end

    def verify!(klass)
      m = klass.private_instance_methods(true).include?(:validations_for_path) &&
          klass.instance_method(:validations_for_path)
      return if m && m.arity.zero?

      raise IncompatibleGitLab,
            'Gitlab::Checks::DiffCheck#validations_for_path is missing or changed; path permissions ' \
            'cannot be enforced on this GitLab version. Refusing to boot unprotected.'
    end

    def warn_untested(version)
      return if TESTED.include?(version.split('.').first(2).join('.'))

      Rails.logger.warn("path_permissions: GitLab #{version} is not in the tested list #{TESTED}") if defined?(Rails)
    end
  end
end
