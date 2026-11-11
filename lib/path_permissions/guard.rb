# frozen_string_literal: true

require_relative 'evaluator'
require_relative 'store'

module PathPermissions
  # Per-request state plus the read decision. Reads are filtered only inside a real user request
  # (web or API) marked by Middleware. Background jobs, Rails runner and GitLab's internal hook API
  # carry no marker and are never filtered.
  module Guard
    KEY = :vela_pp_request

    module_function

    def begin_request!
      Thread.current[KEY] = { rules: {}, groups: {} }
    end

    def end_request!
      Thread.current[KEY] = nil
    end

    def active?
      !Thread.current[KEY].nil?
    end

    # The Project for a main-repository read, nil for wikis, snippets and design repositories.
    def project_of(repository)
      return unless repository.respond_to?(:repo_type) && repository.repo_type.project?

      container = repository.container
      container if container.is_a?(::Project)
    end

    # true when rules apply to this actor in this project (feature on and actor not exempt).
    def restricting?(project)
      return false unless active? && project

      rules = rules_for(project)
      !rules.nil? && !exempt?(project)
    end

    # level: :view or :read. Fails closed (false) if rules cannot be read or the path is malformed.
    def permit?(project, path, level)
      return true unless restricting?(project)

      rules = rules_for(project)
      return false if rules == :error

      clean = normalize(path)
      return true if clean == :root
      return false if clean.nil?

      allowed?(rules, clean, level)
    end

    # A folder stays listed if it is viewable itself or holds something the actor may view,
    # so an allowed file inside a mostly hidden folder stays reachable.
    def dir_visible?(project, path)
      return true unless restricting?(project)

      rules = rules_for(project)
      return false if rules == :error

      clean = normalize(path)
      return true if clean == :root
      return false if clean.nil?
      return true if allowed?(rules, clean, :view)

      rules.any? { |r| r.effect == :allow && r.path.start_with?("#{clean}/") && allowed?(rules, r.path, :view) }
    end

    def allowed?(rules, clean, level)
      user = actor
      PathPermissions.allowed?(rules, user_id: user ? user.id : 0, group_ids: groups(user), path: clean, level: level)
    end

    def normalize(path)
      p = path.to_s.dup.force_encoding(Encoding::UTF_8)
      p = p.sub(%r{\A/+}, '').sub(%r{/+\z}, '')
      return :root if p.empty?

      PathPermissions.valid_path?(p) ? p : nil
    end

    def rules_for(project)
      memo = Thread.current[KEY][:rules]
      return memo[project.id] if memo.key?(project.id)

      memo[project.id] = begin
        Store.rules_for(project.id)
      rescue StandardError => e
        Rails.logger.error("path_permissions: #{e.class}: #{e.message}") if defined?(Rails)
        :error
      end
    end

    def actor
      state = Thread.current[KEY]
      return state[:user] if state.key?(:user)

      state[:user] = resolve_actor
    end

    def resolve_actor
      value = ::Gitlab::ApplicationContext.current_context_attribute(:user)
      return value if value.respond_to?(:admin?)

      value.to_s.empty? ? nil : ::User.find_by_username(value.to_s)
    rescue StandardError
      nil
    end

    def groups(user)
      return [] unless user

      memo = Thread.current[KEY][:groups]
      memo[user.id] ||= Store.group_ids_for(user)
    end

    def exempt?(project)
      user = actor
      !user.nil? && (user.admin? || user.can?(:admin_project, project))
    rescue StandardError
      false
    end
  end

  # Rack middleware: marks user requests. GitLab's internal API (used by git hooks) is skipped on purpose,
  # because the write check already runs there and must see whole repositories.
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) if env['PATH_INFO'].to_s.start_with?('/api/v4/internal')

      Guard.begin_request!
      @app.call(env)
    ensure
      Guard.end_request!
    end
  end
end
