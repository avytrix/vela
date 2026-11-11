# frozen_string_literal: true

require 'json'
require 'net/http'
require 'open3'
require 'uri'
require_relative 'evaluator'

module PathPermissions
  # Portable write enforcement for any GitLab CE: a global pre-receive server hook, the one extension
  # point GitLab documents as stable (https://docs.gitlab.com/administration/server_hooks/).
  # No GitLab internals are used. Rules live in a project CI/CD variable (VARIABLE below), which only
  # Maintainers and Owners can read or change; group membership comes from GitLab's REST API.
  # Same stance as the overlay: any doubt means the push is rejected.
  module Hook
    VARIABLE = 'VELA_PATH_POLICY'
    ZERO = '0' * 40
    DENIED = 'You are not allowed to change a protected path in this push.'
    UNVERIFIABLE = 'Path permissions could not be verified for this push; it was rejected.'
    MAX_COMMITS = 20_000

    class Deny < StandardError; end

    # Thin wrappers so the logic can be tested without a network or a real GitLab.
    class Git
      def initialize(dir = nil)
        @dir = dir
      end

      def run(*args)
        out, err, status = Open3.capture3('git', *args, chdir: @dir || Dir.pwd)
        unless status.success?
          warn "vela: git #{args.first} failed: #{err.strip}" if ENV['VELA_DEBUG']
          raise Deny, UNVERIFIABLE
        end

        out
      rescue SystemCallError
        raise Deny, UNVERIFIABLE
      end
    end

    class Api
      ATTEMPTS = 3
      DELAYS = [0.5, 1.5].freeze # seconds before retry 2 and 3

      def initialize(base, token, sleeper: Kernel.method(:sleep))
        @base = URI(base.sub(%r{/+\z}, ''))
        @token = token
        @sleeper = sleeper
      end

      # Returns parsed JSON, or nil for 404. A brief outage (GitLab restarting a web worker, a 5xx, a timeout)
      # is retried; anything still wrong after that raises, so the push is rejected (fail closed).
      # missing: extra status codes that mean "nothing there" (see load_rules)
      def get(path, missing: [])
        attempt = 0
        begin
          attempt += 1
          fetch(path, missing)
        rescue Retry
          raise Deny, UNVERIFIABLE if attempt >= ATTEMPTS

          @sleeper.call(DELAYS[attempt - 1])
          retry
        end
      end

      Retry = Class.new(StandardError)

      private

      def fetch(path, missing)
        http = Net::HTTP.new(@base.host, @base.port)
        http.use_ssl = @base.scheme == 'https'
        http.open_timeout = 5
        http.read_timeout = 10
        res = http.request(Net::HTTP::Get.new("#{@base.path}/api/v4#{path}", 'PRIVATE-TOKEN' => @token))
        return nil if res.code == '404'
        # a project with CI/CD turned off answers 403 for its variables; a bad or under-scoped token is not that
        return nil if missing.include?(res.code) && !res.body.to_s.match?(/insufficient_scope|invalid_token|invalid_grant/)
        raise Retry if res.code.start_with?('5') || res.code == '429'
        raise Deny, UNVERIFIABLE unless res.code == '200' # 401/403: a wrong token will not fix itself

        JSON.parse(res.body)
      rescue SystemCallError, Timeout::Error, SocketError, IOError
        raise Retry
      rescue JSON::ParserError
        raise Deny, UNVERIFIABLE
      end
    end

    module_function

    # env: process env; changes: [[old, new, ref], ...]. Returns nil when allowed, else the message.
    def check(env:, changes:, git:, api:)
      project_id = env['GL_REPOSITORY'].to_s[/\Aproject-(\d+)\z/, 1]
      return nil unless project_id # wikis, snippets, design repositories are not covered

      rules, encrypted = load_policy(api, project_id)
      return nil unless rules

      verify_encrypted!(git, changes, encrypted) unless encrypted.empty?

      user = api.get("/users?username=#{URI.encode_www_form_component(env['GL_USERNAME'].to_s)}")&.first
      raise Deny, DENIED unless user && !env['GL_USERNAME'].to_s.empty?
      return nil if user['is_admin'] || owner?(api, project_id, user['id'])

      groups = rules.select { |r| r.principal_type == :group }.map(&:principal_id).uniq
                    .select { |g| api.get("/groups/#{g}/members/all/#{user['id']}") }
      default_ref = git.run('symbolic-ref', '-q', 'HEAD').strip rescue nil # rubocop:disable Style/RescueModifier
      ctx = { rules: rules, user_id: user['id'], groups: groups }

      changes.each do |old, new, ref|
        next if new == ZERO || !(ref.start_with?('refs/heads/') || ref.start_with?('refs/tags/'))

        commit_paths(git, new).each { |c| verify!(ctx, c) }
        verify_net!(git, ctx, old, new) if old != ZERO && ref == default_ref
      end
      nil
    rescue Deny => e
      e.message
    end

    def load_policy(api, project_id)
      # CI/CD off => GitLab says 403, and such a project cannot carry the variable, so it has no policy
      var = api.get("/projects/#{project_id}/variables/#{VARIABLE}", missing: ['403'])
      return nil unless var

      doc = JSON.parse(var['value'])
      return nil unless doc['enabled']

      encrypted = Array(doc['encrypted']).map(&:to_s)
      raise Deny, UNVERIFIABLE unless encrypted.all? { |d| PathPermissions.valid_path?(d) }

      rules = doc.fetch('rules').map do |r|
        Rule.new(path: r['path'], type: r['type'].to_sym, principal_type: r['principal_type'].to_sym,
                 principal_id: Integer(r['principal_id']), level: r['level'].to_sym, effect: r['effect'].to_sym)
      end
      [PathPermissions.validate!(rules), encrypted]
    rescue JSON::ParserError, KeyError, TypeError, NoMethodError, ArgumentError, InvalidRule => e
      warn "vela: bad policy: #{e.class}: #{e.message}" if ENV['VELA_DEBUG']
      raise Deny, UNVERIFIABLE
    end

    def owner?(api, project_id, user_id)
      m = api.get("/projects/#{project_id}/members/all/#{user_id}")
      !m.nil? && m['access_level'].to_i >= 50
    end

    # Every path every NEW commit touches (so a forbidden change that a later commit reverts is still
    # caught). Merge commits use the combined diff, which lists only paths that differ from all parents.
    AGE_MAGIC = 'age-encryption.org/v1'
    PLAINTEXT = 'Files under an encrypted path must be encrypted with vela-crypt before they are committed ' \
                '(run `vela-crypt init`, then commit again). Nothing was pushed.'

    # Everyone, admins included, must push ciphertext under the policy's "encrypted" folders: plaintext in
    # history can never be taken back. The message names no file.
    def verify_encrypted!(git, changes, encrypted)
      changes.each do |_old, new, ref|
        next if new == ZERO || !(ref.start_with?('refs/heads/') || ref.start_with?('refs/tags/'))

        git.run('rev-list', '--reverse', new, '--not', '--all').split.each do |sha|
          raw = git.run('diff-tree', '-r', '-z', '--root', '-m', '--no-commit-id', '--diff-filter=AMCR', '--raw', sha).split("\0")
          raw.each_slice(2) do |meta, path|
            next unless path && encrypted.any? { |d| path == d || path.start_with?("#{d}/") }

            mode, oid = meta.split[1], meta.split[3]
            next if mode == '160000' # submodule
            raise Deny, PLAINTEXT unless git.run('cat-file', 'blob', oid).start_with?(AGE_MAGIC)
          end
        end
      end
    end

    def commit_paths(git, new)
      commits = git.run('rev-list', '--reverse', '--parents', new, '--not', '--all').lines.map { |l| l.split }
      raise Deny, UNVERIFIABLE if commits.size > MAX_COMMITS

      commits.flat_map do |sha, *parents|
        args = parents.size > 1 ? ['-c', '--name-status'] : ['--root', '-M', '--name-status']
        parse(git.run('diff-tree', '-r', '-z', '--no-commit-id', *args, sha))
      end
    end

    # What a push does to the default branch: old tip vs new tip, which also catches a merge that lands
    # someone else's change (invisible to the combined diff above).
    def verify_net!(git, ctx, old, new)
      parse(git.run('diff-tree', '-r', '-z', '--no-commit-id', '-M', '--name-status', old, new)).each { |c| verify!(ctx, c) }
    end

    # NUL-separated `--name-status`: "M\0path\0", "R100\0old\0new\0", "C75\0old\0new\0".
    def parse(out)
      parts = out.split("\0")
      changes = []
      until parts.empty?
        status = parts.shift
        count = status.start_with?('R', 'C') ? 2 : 1
        names = parts.shift(count)
        raise Deny, UNVERIFIABLE if names.size != count

        changes << [status[0], names]
      end
      changes
    end

    def verify!(ctx, change)
      kind, names = change
      needs = case kind
              when 'R' then [[names[0], :write], [names[1], :write]]
              when 'C' then [[names[0], :read], [names[1], :write]]
              else [[names[0], :write]]
              end
      return if needs.all? { |p, lvl| allowed?(ctx, p, lvl) }

      path = names.last
      raise Deny, allowed?(ctx, path, :view) ? "You are not allowed to change '#{path}' (path permissions)." : DENIED
    end

    def allowed?(ctx, path, level)
      PathPermissions.allowed?(ctx[:rules], user_id: ctx[:user_id], group_ids: ctx[:groups], path: path, level: level)
    end
  end
end
