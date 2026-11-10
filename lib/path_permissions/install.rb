# frozen_string_literal: true

require_relative 'write_check'
require_relative 'read_check'
require_relative 'ui'

module PathPermissions
  class IncompatibleGitLab < StandardError; end

  # Boot guard: refuse to start unprotected if GitLab changed the hook we rely on.
  module Install
    TESTED = %w[19.0].freeze

    module_function

    def call(diff_check = ::Gitlab::Checks::DiffCheck, version = ::Gitlab::VERSION, read: true)
      verify!(diff_check)
      diff_check.prepend(WriteCheck) unless diff_check.include?(WriteCheck)
      install_read_checks if read
      UI.install if read # the page is optional: a failure is logged and never blocks boot
      warn_untested(version)
    end

    # Each target must still have the method we wrap, or GitLab refuses to boot (same stance as writes).
    def install_read_checks
      [
        [::Repository, ReadCheck::RepositoryReads, %i[blob_at ls_files]],
        [::Tree, ReadCheck::TreeReads, %i[initialize]],
        [::Gitlab::FileFinder, ReadCheck::FileFinderReads, %i[find]],
        [::Gitlab::Git::DiffCollection, ReadCheck::DiffCollectionFilter, %i[each]]
      ].each do |klass, mod, methods|
        missing = methods.reject { |m| klass.method_defined?(m) || klass.private_method_defined?(m) }
        raise IncompatibleGitLab, "#{klass}##{missing.join(', ')} missing; cannot hide paths. Refusing to boot." if missing.any?

        klass.prepend(mod) unless klass.include?(mod)
      end
      # every FileCollection class that defines its own #diffs needs the filter too
      ::Gitlab::Diff::FileCollection.constants.map { |c| ::Gitlab::Diff::FileCollection.const_get(c) }
        .select { |k| k.is_a?(Class) && k.instance_methods(false).include?(:diffs) }
        .push(::Gitlab::Diff::FileCollection::Base).uniq.each do |k|
        k.prepend(ReadCheck::DiffFileCollectionReads) unless k.include?(ReadCheck::DiffFileCollectionReads)
      end
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
