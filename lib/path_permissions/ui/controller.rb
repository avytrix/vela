# frozen_string_literal: true

require_relative '../admin'

module Vela
  class PathPermissionsController < Projects::ApplicationController
    layout 'project_settings'
    before_action :authorize_vela!
    feature_category :source_code_management
    urgency :low

    TEMPLATE = File.read(File.join(__dir__, 'show.html.erb'))

    def show
      @enabled = PathPermissions::Admin.enabled?(project.id)
      stored = PathPermissions::Admin.rules(project.id)
      @pairs = stored.group_by { |r| [r[:rule].path, r[:rule].type, r[:rule].principal_type, r[:rule].principal_id] }
      @names = names_for(stored.map { |r| r[:rule] })
      @audits = PathPermissions::Admin.audits(project.id)
      @explain = explain(stored.map { |r| r[:rule] }) if params[:explain_user].present? && params[:explain_path].present?
      render inline: TEMPLATE, type: :erb, layout: 'project_settings'
    end

    def toggle
      PathPermissions::Admin.set_enabled!(project.id, params[:enabled] == '1', current_user.id)
      redirect_to page_path, notice: params[:enabled] == '1' ? 'Path permissions turned on.' : 'Path permissions turned off.'
    end

    def add
      principal_type = params[:principal_type].to_s
      principal = resolve(principal_type, params[:principal].to_s.strip)
      raise PathPermissions::Admin::Error, "No #{principal_type} named '#{params[:principal]}' was found" unless principal

      PathPermissions::Admin.add_rule!(project.id, path: params[:path], type: params[:path_type], principal_type: principal_type,
                                                    principal_id: principal.id, levels: Array(params[:levels]), effect: params[:effect],
                                                    actor_id: current_user.id)
      redirect_to page_path, notice: 'Rule added.'
    rescue PathPermissions::Admin::Error, ArgumentError, NoMethodError => e
      redirect_to page_path, alert: "Could not add the rule: #{e.message}"
    end

    def remove
      PathPermissions::Admin.delete_pair!(project.id, path: params[:path], type: params[:path_type], principal_type: params[:principal_type],
                                                       principal_id: params[:principal_id].to_i, actor_id: current_user.id)
      redirect_to page_path, notice: 'Rule removed.'
    end

    private

    def authorize_vela!
      render_404 unless PathPermissions::UI.can_manage?(current_user, project)
    end

    def page_path
      "/#{project.full_path}#{PathPermissions::UI::PATH}"
    end

    def resolve(type, text)
      case type
      when 'group' then Group.find_by_full_path(text)
      when 'user' then User.find_by_username(text)
      end
    end

    def names_for(rules)
      groups = Group.where(id: rules.select { |r| r.principal_type == :group }.map(&:principal_id)).index_by(&:id)
      users = User.where(id: rules.select { |r| r.principal_type == :user }.map(&:principal_id)).index_by(&:id)
      ->(type, id) { type == :group ? (groups[id]&.full_path || "group ##{id}") : "@#{users[id]&.username || "user ##{id}"}" }
    end

    # "Test as user": what the stored rules say about one user and path.
    def explain(rules)
      user = User.find_by_username(params[:explain_user].to_s.strip)
      return { error: "No user named '#{params[:explain_user]}'" } unless user
      return { user: user, exempt: true } if user.admin? || project.team.max_member_access(user.id) >= ::Gitlab::Access::OWNER

      clean = PathPermissions::Guard.normalize(params[:explain_path])
      return { error: 'That is not a valid path (no leading slash, no .. segments)' } if clean.nil?

      { user: user, path: clean == :root ? '' : clean,
        levels: PathPermissions.explain(rules, user_id: user.id, group_ids: PathPermissions::Store.group_ids_for(user), path: clean.to_s) }
    end
  end
end
