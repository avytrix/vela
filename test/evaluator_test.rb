# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/path_permissions/evaluator'

class EvaluatorTest < Minitest::Test
  P = PathPermissions

  def rule(path, type, pt, pid, level, effect)
    P::Rule.new(path: path, type: type, principal_type: pt, principal_id: pid, level: level, effect: effect)
  end

  # Brief's example: group 101 = frontend, 102 = backend, docs shared, one denied file.
  def rules
    r = []
    P::LEVELS.each do |l|
      r << rule('frontend', :dir, :group, 101, l, :allow)
      r << rule('backend', :dir, :group, 102, l, :allow)
      r << rule('frontend/security-config.json', :file, :group, 101, l, :deny)
    end
    %i[view read].each { |l| [101, 102].each { |g| r << rule('docs', :dir, :group, g, l, :allow) } }
    r
  end

  def ok?(groups, path, level)
    P.allowed?(rules, user_id: 1, group_ids: groups, path: path, level: level)
  end

  def test_allow_list_and_default_allow
    assert ok?([101], 'frontend/app.js', :write)
    refute ok?([102], 'frontend/app.js', :view)
    assert ok?([102], 'README.md', :write) # no rule => native
  end

  def test_file_deny_beats_dir_allow_and_falls_through_for_others
    refute ok?([101], 'frontend/security-config.json', :view)
    refute ok?([102], 'frontend/security-config.json', :view) # dir allow-list excludes 102
  end

  def test_write_requires_read
    assert ok?([101], 'docs/a.md', :read)
    refute ok?([101], 'docs/a.md', :write) # docs has no write allow rule => allow-list absent => write rules don't exist
  end

  def test_deny_only_selector_does_not_lock_others
    rs = [rule('secrets', :dir, :group, 5, :view, :deny)]
    refute P.allowed?(rs, user_id: 1, group_ids: [5], path: 'secrets/k', level: :view)
    assert P.allowed?(rs, user_id: 1, group_ids: [6], path: 'secrets/k', level: :view)
  end

  def test_prefix_is_segment_aware_and_case_sensitive
    assert ok?([102], 'frontend2/x', :write) # 'frontend2' is not under 'frontend'
    assert ok?([102], 'Frontend/x', :write)
  end

  def test_validation
    [['../x', :dir], ['/x', :dir], ['a//b', :file], ['', :file], ["a\0b", :file]].each do |path, t|
      assert_raises(P::InvalidRule) { P.validate!([rule(path, t, :user, 1, :view, :allow)]) }
    end
    assert_raises(P::InvalidRule) do
      P.validate!([rule('a', :dir, :user, 1, :view, :allow), rule('a', :dir, :user, 1, :view, :deny)])
    end
  end
end

class ExplainTest < Minitest::Test
  P = PathPermissions

  def rule(path, type, gid, level, effect)
    P::Rule.new(path: path, type: type, principal_type: :group, principal_id: gid, level: level, effect: effect)
  end

  def test_explain_names_the_deciding_rule_and_chains_levels
    rules = %i[view read].map { |l| rule('docs', :dir, 101, l, :allow) } + [rule('docs/secret.md', :file, 101, :read, :deny)]
    e = P.explain(rules, user_id: 1, group_ids: [101], path: 'docs/a.md')
    assert_equal [true, true, false], e.values.map { |v| v[:allowed] }
    assert_match(/list and you are not on it/, e[:write][:why])
    e = P.explain(rules, user_id: 1, group_ids: [101], path: 'docs/secret.md')
    assert_match(/denied by the rule on docs\/secret.md/, e[:read][:why])
    assert_match(/needs read first/, e[:write][:why])
    e = P.explain(rules, user_id: 1, group_ids: [], path: 'README.md')
    assert e.values.all? { |v| v[:allowed] }
    assert_match(/GitLab's normal permissions/, e[:view][:why])
  end
end
