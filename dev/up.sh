#!/bin/bash
# Local GitLab CE 19.0.2 for testing the overlay. Dev only: fresh instance, no mirrors/webhooks/email.
# UI http://localhost:8929, git over ssh on 2224. Root password: dev/.root_password
set -euo pipefail
cd "$(dirname "$0")/.."
# Isolated docker config: the user's ~/.docker/config.json names a credential helper that is not
# installed (public image needs no login). Talk to Colima directly instead of the saved context.
export DOCKER_CONFIG="$(mktemp -d)"; export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
[ -f dev/.root_password ] || { openssl rand -base64 18 | tr -d '/+=' > dev/.root_password; chmod 600 dev/.root_password; }

docker run -d --name vela-gitlab-ce --hostname localhost --shm-size 256m \
  -p 8929:8929 -p 2224:22 \
  -e GITLAB_ROOT_PASSWORD="$(cat dev/.root_password)" \
  -e GITLAB_OMNIBUS_CONFIG="
    external_url 'http://localhost:8929'
    gitlab_rails['gitlab_shell_ssh_port'] = 2224
    gitlab_rails['usage_ping_enabled'] = false
    puma['worker_processes'] = 0
    sidekiq['concurrency'] = 5
    postgresql['shared_buffers'] = '256MB'
    prometheus_monitoring['enable'] = false
    gitlab_kas['enable'] = false
    registry['enable'] = false
    letsencrypt['enable'] = false
    # Re-install the add-on on every reconfigure (runs at each container start and after every upgrade),
    # so a GitLab upgrade can never leave the initializer behind.
    require 'fileutils'
    FileUtils.cp('/opt/vela-path-permissions/overlay/zz_path_permissions.rb', '/opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb')" \
  -v vela_gitlab_config:/etc/gitlab -v vela_gitlab_data:/var/opt/gitlab -v vela_gitlab_logs:/var/log/gitlab \
  -v "$PWD/lib:/opt/vela-path-permissions/lib:ro" \
  -v "$PWD/overlay:/opt/vela-path-permissions/overlay:ro" \
  gitlab/gitlab-ce:19.0.2-ce.0
echo "First boot takes ~5-10 min: docker logs -f vela-gitlab-ce"
