# frozen_string_literal: true

# Entry point for the pre-receive hook. Logic lives in lib/path_permissions/hook.rb.
require File.join(ENV.fetch('VELA_HOME', '/opt/vela-path-permissions'), 'lib', 'path_permissions', 'hook')

url = ENV['VELA_GITLAB_URL'].to_s
token = ENV['VELA_TOKEN'].to_s
if url.empty? || token.empty?
  warn 'GL-HOOK-ERR: vela is not configured (VELA_GITLAB_URL / VELA_TOKEN), push rejected'
  exit 1
end

changes = $stdin.each_line.map(&:split).select { |c| c.size == 3 }
message = PathPermissions::Hook.check(env: ENV, changes: changes, git: PathPermissions::Hook::Git.new,
                                      api: PathPermissions::Hook::Api.new(url, token))
if message
  warn "GL-HOOK-ERR: #{message}"
  exit 1
end
