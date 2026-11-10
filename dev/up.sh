#!/bin/bash
# Local GitLab CE 19.0.2 for testing the overlay. Dev only: fresh instance, no mirrors/webhooks/email.
# UI http://localhost:8929, git over ssh on 2224. Root password: dev/.root_password
set -euo pipefail
cd "$(dirname "$0")/.."
# Isolated docker config: the user's ~/.docker/config.json names a credential helper that is not
# installed (public image needs no login). Talk to Colima directly instead of the saved context.
export DOCKER_CONFIG="$(mktemp -d)"
[ -S "$HOME/.colima/default/docker.sock" ] && export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
[ -f dev/.root_password ] || { openssl rand -base64 18 | tr -d '/+=' > dev/.root_password; chmod 600 dev/.root_password; }

NAME="${NAME:-vela-gitlab-ce}"; TAG="${GITLAB_TAG:-19.0.2-ce.0}"; VOL="${VOL:-vela_gitlab}"
HTTP_PORT="${HTTP_PORT:-8929}"; SSH_PORT="${SSH_PORT:-2224}"
# VELA_OVERLAY=0 starts plain GitLab (for testing the server-hook tier on its own).
OVERLAY_MOUNTS=(-v "$PWD/lib:/opt/vela-path-permissions/lib:ro" -v "$PWD/overlay:/opt/vela-path-permissions/overlay:ro")
OVERLAY_RB="require 'fileutils'
    FileUtils.cp('/opt/vela-path-permissions/overlay/zz_path_permissions.rb', '/opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb')"
# Linux package installs only run global server hooks once custom_hooks_dir is set (GitLab docs: server hooks).
HOOKS_RB="gitaly['configuration'] = { hooks: { custom_hooks_dir: '/var/opt/gitlab/gitaly/custom_hooks' } }"
[ "${VELA_OVERLAY:-1}" = 1 ] && HOOKS_RB="" || { OVERLAY_RB=""; OVERLAY_MOUNTS=(-v "$PWD/server-hook:/opt/vela-path-permissions/server-hook:ro" -v "$PWD/lib:/opt/vela-path-permissions/lib:ro"); }

docker run -d --name "$NAME" --hostname localhost --shm-size 256m \
  -p "$HTTP_PORT:$HTTP_PORT" -p "$SSH_PORT:22" \
  -e GITLAB_ROOT_PASSWORD="$(cat dev/.root_password)" \
  -e GITLAB_OMNIBUS_CONFIG="
    external_url 'http://localhost:${HTTP_PORT}'
    gitlab_rails['gitlab_shell_ssh_port'] = ${SSH_PORT}
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
    ${OVERLAY_RB}
    ${HOOKS_RB}" \
  -v ${VOL}_config:/etc/gitlab -v ${VOL}_data:/var/opt/gitlab -v ${VOL}_logs:/var/log/gitlab \
  "${OVERLAY_MOUNTS[@]}" \
  "gitlab/gitlab-ce:$TAG"
echo "First boot takes ~5-10 min: docker logs -f $NAME"
