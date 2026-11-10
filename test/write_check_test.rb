# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'support/gitlab_stub'
require_relative '../lib/path_permissions/install'

class WriteCheckTest < Minitest::Test
  P = PathPermissions
  Forbidden = Gitlab::GitAccess::ForbiddenError

  def self.setup_once
    return if @done

    P::Install.call(read: false) # write side only; read side has its own test
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

  # A merge of someone else's backend change: per-commit paths are empty (all-parents diff), but the
  # branch tree changes under backend/.
  def landing(branch, net_paths, user: FakeUser.new(1, false, [101]), trees: { 'a' * 40 => 't1', 'b' * 40 => 't2' })
    P::Store.define_singleton_method(:rules_for) { |_id| RULES }
    P::Store.define_singleton_method(:group_ids_for) { |u| u.groups }
    project = FakeProject.new(7, 'main', FakeRepo.new(trees, net_paths))
    Gitlab::Checks::DiffCheck.new(project: project, user_access: FakeAccess.new(user), changed_paths: [],
                                  branch: branch).validate!
  end

  def test_merge_landing_foreign_change_on_default_branch_is_rejected
    assert_raises(Forbidden) { landing('main', [FakePath.new(:MODIFIED, 'backend/api.rb')]) }
    landing('main', [FakePath.new(:MODIFIED, 'frontend/app.js')])
  end

  def test_protected_branch_is_checked_but_plain_feature_branch_is_not
    assert_raises(Forbidden) { landing('release', [FakePath.new(:MODIFIED, 'backend/api.rb')]) }
    landing('feature/x', [FakePath.new(:MODIFIED, 'backend/api.rb')])
  end

  def test_admin_may_land_anything
    landing('main', [FakePath.new(:MODIFIED, 'backend/api.rb')], user: FakeUser.new(3, true, []))
  end

  def test_empty_listing_for_different_trees_is_unverifiable
    e = assert_raises(Forbidden) { landing('main', []) }
    assert_equal P::WriteCheck::UNVERIFIABLE, e.message
    e = assert_raises(Forbidden) { landing('main', [FakePath.new(:MODIFIED, 'x')], trees: {}) }
    assert_equal P::WriteCheck::UNVERIFIABLE, e.message
  end

  def test_same_tree_means_nothing_to_check
    landing('main', [], trees: { 'a' * 40 => 't1', 'b' * 40 => 't1' })
  end

  def test_unreadable_rules_reject_even_a_push_with_no_new_commits
    P::Store.define_singleton_method(:rules_for) { |_id| raise 'db down' }
    project = FakeProject.new(9, 'main', FakeRepo.new({}, []))
    assert_raises(Forbidden) do
      Gitlab::Checks::DiffCheck.new(project: project, user_access: FakeAccess.new(FakeUser.new(1, false, [])),
                                    changed_paths: [], branch: 'main').validate!
    end
  end

  def tag_push(net_paths, new_commits, user: FakeUser.new(1, false, [101]))
    P::Store.define_singleton_method(:rules_for) { |_id| RULES }
    P::Store.define_singleton_method(:group_ids_for) { |u| u.groups }
    project = FakeProject.new(7, 'main', FakeRepo.new({ 'b' * 40 => 't2' }, net_paths, new_commits))
    Gitlab::Checks::DiffCheck.new(project: project, user_access: FakeAccess.new(user), changed_paths: [],
                                  tag: 'v1').validate!
  end

  def test_annotated_tag_carrying_a_forbidden_commit_is_rejected
    assert_raises(Forbidden) { tag_push([FakePath.new(:MODIFIED, 'backend/api.rb')], [:c1]) }
    tag_push([FakePath.new(:MODIFIED, 'frontend/app.js')], [:c1])
  end

  def test_tag_on_an_existing_commit_is_not_blocked
    tag_push([FakePath.new(:MODIFIED, 'backend/api.rb')], [])
  end

  def test_boot_guard_refuses_when_hook_is_gone
    bare = Class.new
    assert_raises(P::IncompatibleGitLab) { P::Install.verify!(bare) }
    changed = Class.new { private; def validations_for_path(extra); []; end }
    assert_raises(P::IncompatibleGitLab) { P::Install.verify!(changed) }
  end
end
