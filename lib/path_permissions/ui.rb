# frozen_string_literal: true

module PathPermissions
  # Project Settings page. Isolated on purpose: its own route and controller, one sidebar link. If any of
  # it fails to install, GitLab still boots and the write and read checks are unaffected.
  module UI
    PATH = '/-/path_permissions'

    module_function

    # Called while GitLab loads its routes (before the catch-all project routes).
    def draw(mapper)
      mapper.constraints(namespace_id: ::Gitlab::PathRegex.full_namespace_route_regex,
                         project_id: ::Gitlab::PathRegex.project_route_regex) do
        base = "*namespace_id/:project_id#{PATH}"
        mapper.get base, to: 'vela/path_permissions#show', as: :vela_path_permissions
        mapper.post "#{base}/toggle", to: 'vela/path_permissions#toggle'
        mapper.post "#{base}/add", to: 'vela/path_permissions#add'
        mapper.post "#{base}/remove", to: 'vela/path_permissions#remove'
      end
    rescue StandardError => e
      Rails.logger.warn("path_permissions: settings page routes not installed: #{e.class}: #{e.message}")
    end

    # Called after GitLab has booted.
    def install
      require_relative 'ui/controller'
      menu = ::Sidebars::Projects::Menus::SettingsMenu
      menu.prepend(SidebarLink) unless menu.include?(SidebarLink)
    rescue StandardError, LoadError => e
      Rails.logger.warn("path_permissions: settings page not installed: #{e.class}: #{e.message}")
    end

    def can_manage?(user, project)
      return false unless user

      user.admin? || project.team.max_member_access(user.id) >= ::Gitlab::Access::MAINTAINER
    end

    # Adds "Path permissions" under Settings for admins, Owners and Maintainers.
    module SidebarLink
      def configure_menu_items
        shown = super
        project = context.project
        return shown unless project && UI.can_manage?(context.current_user, project)

        add_item(::Sidebars::MenuItem.new(title: 'Path permissions', link: "/#{project.full_path}#{PATH}",
                                          active_routes: { path: 'vela/path_permissions#show' }, item_id: :vela_path_permissions))
        true
      end
    end
  end
end
