# frozen_string_literal: true

# Copy to <gitlab-rails>/config/initializers/zz_path_permissions.rb (see docs/install.md).
# Raises at boot if the GitLab version no longer exposes the hook we rely on.
$LOAD_PATH.unshift(File.join(ENV.fetch('VELA_PP_ROOT', '/opt/vela-path-permissions'), 'lib'))
require 'path_permissions/install'

Rails.application.config.after_initialize { PathPermissions::Install.call }
