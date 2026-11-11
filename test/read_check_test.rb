# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'support/gitlab_stub'
require_relative '../lib/path_permissions/install'

# Stand-ins for the GitLab classes the read filters wrap.
class Project
  attr_reader :id

  def initialize(id)
    @id = id
  end
end

class User
  attr_reader :id, :groups

  def initialize(id, groups, admin: false, owner: false)
    @id = id
    @groups = groups
    @admin = admin
    @owner = owner
  end

  def admin?
    @admin
  end

  def can?(ability, _project)
    ability == :admin_project && @owner
  end
end

module Gitlab
  module ApplicationContext
    class << self
      attr_accessor :user

      def current_context_attribute(_name)
        user
      end
    end
  end

  class FileFinder
    attr_reader :project

    def initialize(project, blobs)
      @project = project
      @blobs = blobs
    end

    def find(_query, content_match_cutoff: nil)
      @blobs
    end
  end

  module Git
    class DiffCollection
      include Enumerable

      def initialize(items)
        @items = items
      end

      def each(&block)
        @items.each(&block)
      end
    end
  end

  module Diff
    module FileCollection
      class Base
        attr_reader :project

        def initialize(project, collection)
          @project = project
          @collection = collection
        end

        def diffs
          @collection
        end
      end
    end
  end
end

RepoType = Struct.new(:project) do
  def project?
    project
  end
end

class Repository
  attr_reader :container, :repo_type

  def initialize(container, project: true)
    @container = container
    @repo_type = RepoType.new(project)
  end

  def blob_at(_sha, path, limit: 1)
    "content of #{path}"
  end

  def ls_files(_ref)
    %w[README.md frontend/app.js backend/api.rb docs/a.md]
  end
end

Entry = Struct.new(:path, :dir) do
  def dir?
    dir
  end
end

class Tree
  def initialize(repository, entries)
    @repository = repository
    @entries = entries
  end

  attr_reader :entries
end

DiffItem = Struct.new(:new_path, :old_path)
Blob = Struct.new(:path)

class ReadCheckTest < Minitest::Test
  P = PathPermissions

  def self.rule(path, type, gid, level, effect = :allow)
    P::Rule.new(path: path, type: type, principal_type: :group, principal_id: gid, level: level, effect: effect)
  end

  # group 101 owns frontend/, group 102 owns backend/, docs/ is readable by both, deep/open.txt allowed for 101
  RULES = (
    P::LEVELS.map { |l| rule('frontend', :dir, 101, l) } +
    P::LEVELS.map { |l| rule('backend', :dir, 102, l) } +
    %i[view read].flat_map { |l| [101, 102].map { |g| rule('docs', :dir, g, l) } } +
    P::LEVELS.map { |l| rule('secret/open.txt', :file, 101, l) } +
    P::LEVELS.map { |l| rule('secret', :dir, 102, l) }
  ).freeze

  Install = P::Install
  [
    [Repository, P::ReadCheck::RepositoryReads],
    [Tree, P::ReadCheck::TreeReads],
    [Gitlab::FileFinder, P::ReadCheck::FileFinderReads],
    [Gitlab::Git::DiffCollection, P::ReadCheck::DiffCollectionFilter],
    [Gitlab::Diff::FileCollection::Base, P::ReadCheck::DiffFileCollectionReads]
  ].each { |k, m| k.prepend(m) }

  def setup
    @project = Project.new(7)
    @repo = Repository.new(@project)
    rules = RULES
    P::Store.define_singleton_method(:rules_for) { |_id| rules }
    P::Store.define_singleton_method(:group_ids_for) { |u| u.groups }
    P::Guard.begin_request!
    Gitlab::ApplicationContext.user = User.new(1, [101])
  end

  def teardown
    P::Guard.end_request!
  end

  def test_blob_content_needs_read
    assert_equal 'content of frontend/app.js', @repo.blob_at('sha', 'frontend/app.js')
    assert_nil @repo.blob_at('sha', 'backend/api.rb')
  end

  def test_leading_slash_and_trailing_slash_are_normalized_not_bypassed
    assert_nil @repo.blob_at('sha', '/backend/api.rb')
    assert_nil @repo.blob_at('sha', 'backend//api.rb')
    assert_nil @repo.blob_at('sha', 'frontend/../backend/api.rb')
    assert_nil @repo.blob_at('sha', "backend/api.rb\0")
  end

  def test_case_variants_are_different_paths
    assert @repo.blob_at('sha', 'Backend/api.rb') # no rule on 'Backend', native decides
  end

  def test_file_list_is_filtered
    assert_equal %w[README.md frontend/app.js docs/a.md], @repo.ls_files('main')
  end

  def test_tree_hides_entries_but_keeps_folder_with_an_allowed_file
    entries = [Entry.new('frontend', true), Entry.new('backend', true), Entry.new('docs', true),
               Entry.new('secret', true), Entry.new('README.md', false)]
    visible = Tree.new(@repo, entries).entries.map(&:path)
    assert_equal %w[frontend docs secret README.md], visible
  end

  def test_search_results_need_read
    finder = Gitlab::FileFinder.new(@project, [Blob.new('frontend/app.js'), Blob.new('backend/api.rb')])
    assert_equal ['frontend/app.js'], finder.find('x').map(&:path)
  end

  def test_diffs_hide_files_without_read_including_rename_source
    items = [DiffItem.new('frontend/app.js', 'frontend/app.js'), DiffItem.new('backend/api.rb', 'backend/api.rb'),
             DiffItem.new('frontend/moved.js', 'backend/old.rb'), DiffItem.new('docs/a.md', 'docs/a.md')]
    collection = Gitlab::Diff::FileCollection::Base.new(@project, Gitlab::Git::DiffCollection.new(items)).diffs
    assert_equal %w[frontend/app.js docs/a.md], collection.map(&:new_path)
    assert_equal 2, collection.count
  end

  def test_admin_and_owner_see_everything
    [User.new(2, [], admin: true), User.new(3, [], owner: true)].each do |u|
      Gitlab::ApplicationContext.user = u
      P::Guard.begin_request!
      assert_equal 4, @repo.ls_files('main').size
      assert @repo.blob_at('sha', 'backend/api.rb')
    end
  end

  def test_anonymous_is_treated_as_outsider
    Gitlab::ApplicationContext.user = nil
    P::Guard.begin_request!
    assert_nil @repo.blob_at('sha', 'frontend/app.js')
    assert_equal %w[README.md], @repo.ls_files('main')
  end

  def test_nothing_is_filtered_outside_a_user_request
    P::Guard.end_request!
    assert @repo.blob_at('sha', 'backend/api.rb')
    assert_equal 4, @repo.ls_files('main').size
  end

  def test_project_without_path_permissions_is_untouched
    P::Store.define_singleton_method(:rules_for) { |_id| nil }
    P::Guard.begin_request!
    assert @repo.blob_at('sha', 'backend/api.rb')
  end

  def test_wiki_and_snippet_repositories_are_never_filtered
    wiki = Repository.new(@project, project: false)
    assert wiki.blob_at('sha', 'backend/api.rb')
  end

  def test_unreadable_rules_fail_closed
    P::Store.define_singleton_method(:rules_for) { |_id| raise 'db down' }
    P::Guard.begin_request!
    assert_nil @repo.blob_at('sha', 'frontend/app.js')
    assert_empty @repo.ls_files('main')
  end

  def test_middleware_marks_user_requests_but_skips_internal_api
    seen = nil
    app = ->(_env) { seen = P::Guard.active?; [200, {}, []] }
    P::Guard.end_request!
    P::Middleware.new(app).call('PATH_INFO' => '/api/v4/internal/allowed')
    refute seen
    P::Middleware.new(app).call('PATH_INFO' => '/api/v4/projects/1/repository/tree')
    assert seen
    refute P::Guard.active?, 'marker must be cleared after the request'
  end
end
