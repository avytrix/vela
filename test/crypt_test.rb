# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'open3'

# Real git, real age, real SSH keys: alice can read the secret, bob can only clone ciphertext.
class CryptTest < Minitest::Test
  CRYPT = File.expand_path('../client/vela-crypt', __dir__)

  def run!(dir, env, *cmd)
    out, st = Open3.capture2e(env.merge('PATH' => "#{File.dirname(CRYPT)}:#{ENV['PATH']}"), *cmd, chdir: dir)
    assert st.success?, "#{cmd.join(' ')} failed:\n#{out}"
    out
  end

  def test_only_the_recipient_can_read_and_the_other_user_is_locked_out
    skip 'age is not installed' unless system('which age >/dev/null 2>&1')
    Dir.mktmpdir do |root|
      %w[alice bob].each { |u| system('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', "#{root}/key_#{u}", out: File::NULL) }
      a = { 'VELA_IDENTITY' => "#{root}/key_alice", 'GIT_CONFIG_GLOBAL' => '/dev/null' }
      b = { 'VELA_IDENTITY' => "#{root}/key_bob", 'GIT_CONFIG_GLOBAL' => '/dev/null' }
      src = "#{root}/src"; Dir.mkdir(src)
      run!(src, a, 'git', 'init', '-q', '-b', 'main')
      run!(src, a, 'git', 'config', 'user.email', 'a@x'); run!(src, a, 'git', 'config', 'user.name', 'a')
      run!(src, a, 'vela-crypt', 'init')
      Dir.mkdir("#{src}/.vela"); File.write("#{src}/.vela/recipients", File.read("#{root}/key_alice.pub"))
      run!(src, a, 'vela-crypt', 'protect', 'secrets')
      Dir.mkdir("#{src}/secrets"); File.write("#{src}/secrets/key.txt", "hunter2\n"); File.write("#{src}/open.txt", "hello\n")
      run!(src, a, 'git', 'add', '-A'); run!(src, a, 'git', 'commit', '-q', '-m', 'x')

      stored = run!(src, a, 'git', 'show', 'HEAD:secrets/key.txt')
      assert stored.start_with?('age-encryption.org/v1'), 'the repository must hold ciphertext'
      refute_includes stored, 'hunter2'
      assert_equal '', run!(src, a, 'git', 'status', '--porcelain'), 'status must stay clean (stable ciphertext)'

      File.write("#{src}/secrets/key.txt", "hunter3\n")
      diff = run!(src, a, 'git', 'diff')
      assert_includes diff, '+hunter3', 'the owner sees a readable local diff'
      run!(src, a, 'git', 'checkout', '--', 'secrets/key.txt')

      [[a, 'alice'], [b, 'bob']].each do |env, name|
        d = "#{root}/#{name}"
        run!(root, env, 'git', 'clone', '-q', '--no-checkout', src, d)
        run!(d, env, 'vela-crypt', 'init')
        run!(d, env, 'git', 'checkout', '-q', 'main')
        run!(d, env, 'vela-crypt', 'sync')
      end
      assert_equal "hunter2\n", File.read("#{root}/alice/secrets/key.txt")
      refute File.exist?("#{root}/bob/secrets/key.txt"), 'a locked file must not be in bob\'s working tree'
      assert_equal "hello\n", File.read("#{root}/bob/open.txt")
      assert_equal '', run!("#{root}/bob", b, 'git', 'status', '--porcelain'), 'bob must see no changes'
    end
  end
end
