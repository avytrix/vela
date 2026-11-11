# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require 'open3'
require_relative '../lib/path_permissions/hook'

# Runs the real hook logic against real git repositories. New commits live in a work repo and reach the
# bare repo only through GIT_ALTERNATE_OBJECT_DIRECTORIES, like a quarantine during a push.
class HookTest < Minitest::Test
  H = PathPermissions::Hook
  ZERO = H::ZERO

  class FakeApi
    attr_accessor :policy, :users, :owners, :members, :fail

    def initialize
      @users = { 'alice' => { 'id' => 1, 'is_admin' => false } }
      @owners = []
      @members = { 101 => [1] }
    end

    def get(path, missing: [])
      raise H::Deny, H::UNVERIFIABLE if fail

      case path
      when %r{\A/projects/\d+/variables/VELA_PATH_POLICY} then policy && { 'value' => policy }
      when %r{\A/users\?username=(.*)\z} then [users[Regexp.last_match(1)]].compact
      when %r{\A/projects/\d+/members/all/(\d+)\z} then owners.include?(Regexp.last_match(1).to_i) ? { 'access_level' => 50 } : { 'access_level' => 30 }
      when %r{\A/groups/(\d+)/members/all/(\d+)\z} then members[Regexp.last_match(1).to_i].to_a.include?(Regexp.last_match(2).to_i) ? {} : nil
      end
    end
  end

  def sh(dir, *args)
    out, err, st = Open3.capture3('git', '-c', 'user.name=t', '-c', 'user.email=t@example.com', *args, chdir: dir)
    raise "git #{args.join(' ')}: #{err}" unless st.success?

    out.strip
  end

  def write(path, body = rand.to_s)
    full = File.join(@work, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
    sh(@work, 'add', '-A')
  end

  def policy(extra = [])
    rules = %w[view read write].map { |l| { path: 'frontend', type: 'dir', principal_type: 'group', principal_id: 101, level: l, effect: 'allow' } }
    rules += %w[view read write].map { |l| { path: 'backend', type: 'dir', principal_type: 'group', principal_id: 102, level: l, effect: 'allow' } }
    JSON.generate(enabled: true, rules: rules + extra)
  end

  def setup
    require 'fileutils'
    @root = Dir.mktmpdir
    @bare = File.join(@root, 'bare.git')
    @work = File.join(@root, 'work')
    sh(@root, 'init', '-q', '--bare', '-b', 'main', @bare)
    sh(@root, 'init', '-q', '-b', 'main', @work)
    write('frontend/app.js'); write('backend/api.rb'); write('README.md')
    sh(@work, 'commit', '-q', '-m', 'base')
    sh(@work, 'push', '-q', @bare, 'main')
    @api = FakeApi.new
    @api.policy = policy
    ENV['GIT_ALTERNATE_OBJECT_DIRECTORIES'] = File.join(@work, '.git', 'objects')
  end

  def teardown
    ENV.delete('GIT_ALTERNATE_OBJECT_DIRECTORIES')
    FileUtils.rm_rf(@root)
  end

  def head
    sh(@work, 'rev-parse', 'HEAD')
  end

  def push(ref = 'refs/heads/feature', old = ZERO, user: 'alice')
    H.check(env: { 'GL_REPOSITORY' => 'project-7', 'GL_USERNAME' => user },
            changes: [[old, head, ref]], git: H::Git.new(@bare), api: @api)
  end

  def test_allowed_change_passes
    write('frontend/app.js'); sh(@work, 'commit', '-q', '-m', 'x')
    assert_nil push
  end

  def test_forbidden_change_is_rejected_without_naming_a_hidden_path
    write('backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'x')
    assert_equal H::DENIED, push
  end

  def test_intermediate_change_reverted_later_is_still_rejected
    write('backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'bad')
    sh(@work, 'checkout', 'HEAD~1', '--', 'backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'revert')
    assert_equal H::DENIED, push
  end

  def test_rename_checks_both_sides
    sh(@work, 'mv', 'frontend/app.js', 'backend/app.js'); sh(@work, 'commit', '-q', '-m', 'mv')
    assert_equal H::DENIED, push
  end

  def test_deleting_a_forbidden_file_is_rejected
    sh(@work, 'rm', '-q', 'backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'rm')
    assert_equal H::DENIED, push
  end

  def test_unrestricted_path_is_native
    write('README.md'); sh(@work, 'commit', '-q', '-m', 'x')
    assert_nil push
  end

  def test_admin_and_owner_are_never_locked_out
    write('backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'x')
    @api.users['alice']['is_admin'] = true
    assert_nil push
    @api.users['alice']['is_admin'] = false
    @api.owners = [1]
    assert_nil push
  end

  def test_unknown_user_is_denied_when_enabled
    write('frontend/app.js'); sh(@work, 'commit', '-q', '-m', 'x')
    assert_equal H::DENIED, push(user: 'mallory')
  end

  def encrypted_policy
    JSON.generate(enabled: true, rules: [], encrypted: ['secrets'])
  end

  def test_plaintext_under_an_encrypted_folder_is_rejected_even_for_an_admin
    @api.policy = encrypted_policy
    @api.users['root'] = { 'id' => 2, 'is_admin' => true }
    write('secrets/key.txt', 'hunter2'); sh(@work, 'commit', '-q', '-m', 'x')
    assert_equal H::PLAINTEXT, push(user: 'root')
  end

  def test_ciphertext_under_an_encrypted_folder_and_plaintext_elsewhere_pass
    @api.policy = encrypted_policy
    write('secrets/key.txt', "age-encryption.org/v1\n-> ssh-ed25519 x\n"); write('README.md', 'plain is fine here')
    sh(@work, 'commit', '-q', '-m', 'x')
    assert_nil push
  end

  def test_plaintext_hidden_in_an_intermediate_commit_is_rejected
    @api.policy = encrypted_policy
    write('secrets/key.txt', 'oops'); sh(@work, 'commit', '-q', '-m', 'a')
    write('secrets/key.txt', "age-encryption.org/v1\n"); sh(@work, 'commit', '-q', '-m', 'b')
    assert_equal H::PLAINTEXT, push
  end

  def test_project_without_policy_is_untouched
    @api.policy = nil
    write('backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'x')
    assert_nil push
  end

  def test_disabled_policy_is_untouched
    @api.policy = JSON.generate(enabled: false, rules: [])
    write('backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'x')
    assert_nil push
  end

  def test_api_failure_and_bad_policy_fail_closed
    write('frontend/app.js'); sh(@work, 'commit', '-q', '-m', 'x')
    @api.fail = true
    assert_equal H::UNVERIFIABLE, push
    @api.fail = false
    @api.policy = '{not json'
    assert_equal H::UNVERIFIABLE, push
    @api.policy = policy([{ path: '/bad/', type: 'dir', principal_type: 'group', principal_id: 1, level: 'view', effect: 'allow' }])
    assert_equal H::UNVERIFIABLE, push
  end

  def test_annotated_tag_carrying_a_forbidden_commit_is_rejected
    write('backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'x'); sh(@work, 'tag', '-a', 'v1', '-m', 'v1')
    new = sh(@work, 'rev-parse', 'v1')
    msg = H.check(env: { 'GL_REPOSITORY' => 'project-7', 'GL_USERNAME' => 'alice' },
                  changes: [[ZERO, new, 'refs/tags/v1']], git: H::Git.new(@bare), api: @api)
    assert_equal H::DENIED, msg
  end

  def test_merge_landing_a_foreign_change_on_the_default_branch_is_rejected
    base = head
    sh(@work, 'checkout', '-q', '-b', 'other'); write('backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'bob work')
    sh(@work, 'checkout', '-q', 'main'); write('frontend/app.js'); sh(@work, 'commit', '-q', '-m', 'alice work')
    sh(@work, 'merge', '-q', '--no-ff', '-m', 'merge', 'other')
    # the foreign commit already exists in the repo (pushed to its own branch earlier)
    sh(@work, 'push', '-q', @bare, 'other')
    msg = H.check(env: { 'GL_REPOSITORY' => 'project-7', 'GL_USERNAME' => 'alice' },
                  changes: [[base, head, 'refs/heads/main']], git: H::Git.new(@bare), api: @api)
    assert_equal H::DENIED, msg
  end

  def test_merging_main_into_a_feature_branch_is_not_blocked
    sh(@work, 'checkout', '-q', '-b', 'feature'); write('frontend/app.js'); sh(@work, 'commit', '-q', '-m', 'f')
    sh(@work, 'push', '-q', @bare, 'feature')
    old = head
    sh(@work, 'checkout', '-q', 'main'); write('backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'someone else')
    sh(@work, 'push', '-q', @bare, 'main')
    sh(@work, 'checkout', '-q', 'feature'); sh(@work, 'merge', '-q', '--no-ff', '-m', 'sync', 'main')
    msg = H.check(env: { 'GL_REPOSITORY' => 'project-7', 'GL_USERNAME' => 'alice' },
                  changes: [[old, head, 'refs/heads/feature']], git: H::Git.new(@bare), api: @api)
    assert_nil msg
  end

  def test_wikis_and_snippets_are_not_covered
    write('backend/api.rb'); sh(@work, 'commit', '-q', '-m', 'x')
    msg = H.check(env: { 'GL_REPOSITORY' => 'wiki-7', 'GL_USERNAME' => 'alice' },
                  changes: [[ZERO, head, 'refs/heads/main']], git: H::Git.new(@bare), api: @api)
    assert_nil msg
  end

  def test_filenames_with_odd_characters_are_handled
    write("frontend/new\nline.txt"); write("backend/tab\tname.rb"); sh(@work, 'commit', '-q', '-m', 'x')
    assert_equal H::DENIED, push
  end
end

# The API client retries brief outages, then fails closed. A tiny local HTTP server answers per script.
class ApiRetryTest < Minitest::Test
  H = PathPermissions::Hook

  def serve(statuses)
    require 'socket'
    server = TCPServer.new('127.0.0.1', 0)
    hits = []
    thread = Thread.new do
      statuses.each do |code|
        client = server.accept
        while (line = client.gets) && line != "\r\n"; end # drain the request headers
        hits << code
        body = code == 200 ? '{"ok":true}' : (code == 'scope' ? '{"error":"insufficient_scope"}' : 'x')
        code = 403 if code == 'scope'
        client.write "HTTP/1.1 #{code} X\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
        client.close
      end
    end
    [server, hits, thread]
  end

  def api(server)
    delays = []
    [H::Api.new("http://127.0.0.1:#{server.addr[1]}", 't', sleeper: ->(d) { delays << d }), delays]
  end

  def test_a_brief_5xx_is_retried_and_then_succeeds
    server, hits, thread = serve([502, 503, 200])
    client, delays = api(server)
    assert_equal({ 'ok' => true }, client.get('/x'))
    assert_equal [502, 503, 200], hits
    assert_equal [0.5, 1.5], delays
    thread.join(5)
  end

  def test_persistent_5xx_fails_closed_after_three_attempts
    server, hits, thread = serve([500, 500, 500])
    client, = api(server)
    assert_raises(H::Deny) { client.get('/x') }
    assert_equal 3, hits.size
    thread.join(5)
  end

  def test_a_wrong_token_is_not_retried
    server, hits, thread = serve([401])
    client, = api(server)
    assert_raises(H::Deny) { client.get('/x') }
    assert_equal [401], hits
    thread.join(5)
  end

  def test_403_on_a_lookup_that_may_be_missing_means_nothing_there
    server, hits, thread = serve([403])
    client, = api(server)
    assert_nil client.get('/x', missing: ['403'])
    assert_equal [403], hits
    thread.join(5)
  end

  def test_403_elsewhere_still_fails_closed
    server, = serve([403])
    client, = api(server)
    assert_raises(H::Deny) { client.get('/x') }
  end

  def test_403_for_a_token_without_scope_still_fails_closed
    server, = serve(['scope'])
    client, = api(server)
    assert_raises(H::Deny) { client.get('/x', missing: ['403']) }
  end

  def test_connection_refused_is_retried_then_fails_closed
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    delays = []
    client = H::Api.new("http://127.0.0.1:#{port}", 't', sleeper: ->(d) { delays << d })
    assert_raises(H::Deny) { client.get('/x') }
    assert_equal 2, delays.size
  end
end
