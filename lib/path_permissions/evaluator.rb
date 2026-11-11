# frozen_string_literal: true

# Pure policy evaluator: no GitLab/Rails dependency, shared by the pre-receive hook and read patches.
# Semantics (see plan): most-specific selector wins per level; deny beats allow; a selector with
# any allow rule is an allow-list; no applicable rule => allow (native GitLab decides).
module PathPermissions
  LEVELS = %i[view read write].freeze # each level requires the ones before it
  Rule = Struct.new(:path, :type, :principal_type, :principal_id, :level, :effect, keyword_init: true)

  class InvalidRule < StandardError; end

  module_function

  def valid_path?(path)
    path.is_a?(String) && !path.empty? && !path.start_with?('/') && !path.include?("\0") &&
      path.split('/', -1).none? { |s| s.empty? || s == '.' || s == '..' }
  end

  def validate!(rules)
    seen = {}
    rules.each do |r|
      raise InvalidRule, "bad path #{r.path.inspect}" unless valid_path?(r.path)
      raise InvalidRule, 'bad type' unless %i[file dir].include?(r.type)
      raise InvalidRule, 'bad principal' unless %i[user group].include?(r.principal_type) && r.principal_id.is_a?(Integer)
      raise InvalidRule, 'bad level' unless LEVELS.include?(r.level)
      raise InvalidRule, 'bad effect' unless %i[allow deny].include?(r.effect)

      key = [r.path, r.type, r.principal_type, r.principal_id, r.level]
      raise InvalidRule, "conflicting rules for #{r.path}" if seen.key?(key) && seen[key] != r.effect

      seen[key] = r.effect
    end
    rules
  end

  def selector_matches?(rule, path)
    rule.type == :file ? rule.path == path : (path == rule.path || path.start_with?("#{rule.path}/"))
  end

  # Decision for one level: [allowed, deciding selector path or nil, reason symbol].
  def level_decision(rules, user_id, group_ids, path, level)
    # group by selector across ALL levels: any allow rule makes the selector an allow-list for every
    # level (an unchecked cell in the UI grid means "not granted")
    rules.select { |r| selector_matches?(r, path) }
         .group_by { |r| [r.path, r.type] }
         .sort_by { |(p, _), _| -p.count('/') }
         .each do |(selector, _), group|
      mine = group.select do |r|
        r.level == level &&
          ((r.principal_type == :user && r.principal_id == user_id) ||
           (r.principal_type == :group && group_ids.include?(r.principal_id)))
      end
      return [false, selector, :denied] if mine.any? { |r| r.effect == :deny }
      return [true, selector, :allowed] if mine.any? { |r| r.effect == :allow }
      return [false, selector, :not_listed] if group.any? { |r| r.effect == :allow } # allow-list excludes this user/level
      # deny-only selector that doesn't hit this user: fall through to less specific
    end
    [true, nil, :no_rule] # ponytail: default allow per plan; flip to false here for default-deny projects
  end

  # Does this principal set (user + groups) pass a single level for path?
  def level_allowed?(rules, user_id, group_ids, path, level)
    level_decision(rules, user_id, group_ids, path, level).first
  end

  # Write requires read requires view for that path.
  def allowed?(rules, user_id:, group_ids:, path:, level:)
    LEVELS.take(LEVELS.index(level) + 1).all? { |l| level_allowed?(rules, user_id, group_ids, path, l) }
  end

  REASONS = {
    denied: 'denied by the rule on %s',
    allowed: 'allowed by the rule on %s',
    not_listed: '%s is a list and you are not on it',
    no_rule: "no rule applies, so GitLab's normal permissions decide"
  }.freeze

  # { view: {allowed:, why:}, read: ..., write: ... } with the same chaining as allowed? (Write needs Read
  # needs View). Used by the "Test as user" box; the reasons never include anything but rule paths.
  def explain(rules, user_id:, group_ids:, path:)
    blocked = nil
    LEVELS.each_with_object({}) do |level, out|
      ok, selector, why = level_decision(rules, user_id, group_ids, path, level)
      if blocked
        out[level] = { allowed: false, why: "needs #{blocked} first" }
      else
        out[level] = { allowed: ok, why: format(REASONS.fetch(why), selector) }
        blocked = level unless ok
      end
    end
  end
end
