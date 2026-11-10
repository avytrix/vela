# frozen_string_literal: true

require_relative 'guard'

module PathPermissions
  # Read-side filters, prepended onto GitLab classes (see install.rb). All of them are no-ops outside a
  # user request, for projects without path permissions, and for admins and project Owners.
  module ReadCheck
    # File content: web viewer, raw, blame, API files. A nil blob is a 404 in GitLab.
    module RepositoryReads
      def blob_at(*args, &block)
        return nil unless Guard.permit?(Guard.project_of(self), args[1], :read)

        super
      end

      # "Find file".
      def ls_files(*args, &block)
        files = super
        project = Guard.project_of(self)
        return files unless Guard.restricting?(project)

        files.select { |p| Guard.permit?(project, p, :view) }
      end
      ruby2_keywords(:blob_at, :ls_files) if respond_to?(:ruby2_keywords, true)
    end

    # Directory listings (web tree, README lookup, API repository/tree).
    module TreeReads
      def initialize(*args, &block)
        super
        project = Guard.project_of(@repository)
        return unless Guard.restricting?(project)

        @entries = @entries.select do |e|
          e.dir? ? Guard.dir_visible?(project, e.path) : Guard.permit?(project, e.path, :view)
        end
      end
      ruby2_keywords(:initialize) if respond_to?(:ruby2_keywords, true)
    end

    # Project code search (content and file name).
    module FileFinderReads
      def find(*args, &block)
        found = super
        return found unless Guard.restricting?(project) && found.respond_to?(:select)

        found.select { |blob| Guard.permit?(project, blob.path, :read) }
      end
      ruby2_keywords(:find) if respond_to?(:ruby2_keywords, true)
    end

    # Commit, compare and merge request diffs: attach a filter to the raw diff collection.
    module DiffFileCollectionReads
      def diffs
        collection = super
        return collection unless Guard.restricting?(project) && collection.respond_to?(:vela_filter=)

        project_ref = project
        collection.vela_filter ||= lambda do |diff|
          [diff.new_path, diff.old_path].all? { |p| p.to_s.empty? || Guard.permit?(project_ref, p, :read) }
        end
        collection
      end
    end

    module DiffCollectionFilter
      attr_writer :vela_filter

      def vela_filter
        @vela_filter
      end

      def each(&block)
        filter = @vela_filter
        return super unless filter && block

        super { |diff| block.call(diff) if filter.call(diff) }
      end
    end
  end
end
