# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'support/gitlab_stub'
require_relative '../lib/path_permissions/install'

class WriteCheckTest < Minitest::Test
  P = PathPermissions
  Forbidden = Gitlab::GitAccess::ForbiddenError

  def self.setup_once
    return if @done

    P::Install.call # same entry point the initializer uses
    @done = true
  end
  setup_once

  def self.rule(path, type, pt, pid, level, effect)
    P::Rule.new(path: path, type: type, principal_type: pt, principal_id: pid, level: level, effect: effect)
  end

  # 101 owns frontend/ and may write docs/; 102 owns backend/ and may only view+read docs/
  RULES = (
    P::LEVELS.map { |l| rule('frontend', :dir, :group, 101, l, :allow) } +
    P::LEVELS.map { |l| rule('backend', :dir, :group, 102, l, :allow) } +
    %i[view read].flat_map { |l| [101, 102].map { |g| rule('docs', :dir, :group, g, l, :allow) } } +
    [rule('docs', :dir, :group, 101, :write, :allow)]
  ).freeze

  def run_check(paths, user: FakeUser.new(1, false, [101]), rules: RULES)
    P::Store.define_singleton_method(:rules_for) { |_id| rules }
    P::Store.define_singleton_method(:group_ids_for) { |u| u.groups }
    Gitlab::Checks::DiffCheck.new(project: FakeProject.new(7), user_access: FakeAccess.new(user),
                                  changed_paths: paths).validate!
  end

  def test_allowed_path_passes
    run_check([FakePath.new(:MODIFIED, 'frontend/app.js')])
  end

  def test_forbidden_path_rejected_and_hidden_name_not_leaked
    e = assert_raises(Forbidden) { run_check([FakePath.new(:MODIFIED, 'backend/secret.rb')], user: FakeUser.new(2, false, [101])) }
    assert_equal P::WriteCheck::DENIED, e.message
    refute_includes e.message, 'secret'
  end

  def test_visible_but_unwritable_path_names_the_path
    e = assert_raises(Forbidden) { run_check([FakePath.new(:MODIFIED, 'docs/a.md')], user: FakeUser.new(2, false, [102])) }
    assert_includes e.message, 'docs/a.md'
  end

  def test_one_bad_path_among_many_rejects_whole_push
    paths = [FakePath.new(:ADDED, 'frontend/ok.js'), FakePath.new(:DELETED, 'backend/x.rb')]
    assert_raises(Forbidden) { run_check(paths) }
  end

  def test_rename_checks_both_source_and_destination
    assert_raises(Forbidden) { run_check([FakePath.new(:RENAMED, 'frontend/a.js', 'backend/a.js')]) } # out of forbidden dir
    assert_raises(Forbidden) { run_check([FakePath.new(:RENAMED, 'backend/a.js', 'frontend/a.js')]) } # into forbidden dir
    run_check([FakePath.new(:RENAMED, 'frontend/b.js', 'frontend/a.js')])
  end

  def test_copy_needs_read_on_source_write_on_destination
    run_check([FakePath.new(:COPIED, 'frontend/copy.md', 'docs/a.md')])
    assert_raises(Forbidden) { run_check([FakePath.new(:COPIED, 'backend/copy.md', 'docs/a.md')]) }
  end

  def test_admin_and_owner_are_never_locked_out
    run_check([FakePath.new(:MODIFIED, 'backend/x.rb')], user: FakeUser.new(3, true, []))
    run_check([FakePath.new(:MODIFIED, 'backend/x.rb')], user: FakeUser.new(4, false, [], true))
  end

  def test_actor_without_user_is_denied_when_enabled
    assert_raises(Forbidden) { run_check([FakePath.new(:MODIFIED, 'frontend/a.js')], user: nil) }
  end

  def test_disabled_project_keeps_native_behaviour
    run_check([FakePath.new(:MODIFIED, 'backend/x.rb')], rules: nil)
  end

  def test_store_failure_fails_closed
    P::Store.define_singleton_method(:rules_for) { |_id| raise 'db down' }
    e = assert_raises(Forbidden) do
      Gitlab::Checks::DiffCheck.new(project: FakeProject.new(9), user_access: FakeAccess.new(FakeUser.new(1, false, [])),
                                    changed_paths: [FakePath.new(:MODIFIED, 'x')]).validate!
    end
    assert_equal P::WriteCheck::UNVERIFIABLE, e.message
  end

  def test_boot_guard_refuses_when_hook_is_gone
    bare = Class.new
    assert_raises(P::IncompatibleGitLab) { P::Install.verify!(bare) }
    changed = Class.new { private; def validations_for_path(extra); []; end }
    assert_raises(P::IncompatibleGitLab) { P::Install.verify!(changed) }
  end
end
