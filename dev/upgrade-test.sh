#!/bin/bash
# Real package upgrade and downgrade, inside a running GitLab container (the same dpkg/apt path a server uses).
# Usage: dev/upgrade-test.sh [from-tag] [to-version]   defaults: 19.0.2-ce.0 -> 19.0.11-ce.0
# Writes docs/compat/package-upgrade.md. Needs Docker. Throwaway only.
set -uo pipefail
cd "$(dirname "$0")/.."
FROM="${1:-19.0.2-ce.0}"; TO="${2:-19.0.11-ce.0}"
export DOCKER_CONFIG="$(mktemp -d)"
[ -S "$HOME/.colima/default/docker.sock" ] && export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
NAME=vela-upgrade; PORT=$((20000 + RANDOM % 20000)); OUT=docs/compat/package-upgrade.md
cleanup() { docker rm -f -v $NAME >/dev/null 2>&1; for v in config data logs; do docker volume rm -f vela_upgrade_$v >/dev/null 2>&1; done; }
trap cleanup EXIT
mkdir -p docs/compat
ready() { for i in $(seq 1 120); do [ "$(docker inspect -f '{{.State.Health.Status}}' $NAME 2>/dev/null)" = healthy ] && break; sleep 10; done
          for i in $(seq 1 90); do [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:$PORT/users/sign_in)" = 200 ] && break; sleep 5; done; }
state() { docker exec $NAME sh -c 'cat /opt/gitlab/embedded/service/gitlab-rails/VERSION; ls /opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb 2>&1 | tail -1'; docker exec $NAME gitlab-rails runner 'puts Gitlab::Checks::DiffCheck.ancestors.first, Repository.ancestors.first' 2>&1 | grep -v '^\s*from' | tr '\n' ' '; }
step() { echo "## $1"; echo; echo '```'; shift; "$@" 2>&1 | tail -${TAIL:-12}; echo '```'; echo; }

NAME=$NAME VOL=vela_upgrade GITLAB_TAG=$FROM HTTP_PORT=$PORT SSH_PORT=$((PORT+1)) dev/up.sh >/dev/null 2>&1 || { echo "could not start $FROM"; exit 2; }
ready
docker exec -i $NAME gitlab-psql -v app_role=gitlab -f - < db/schema.sql >/dev/null 2>&1
docker exec $NAME gitlab-ctl restart puma >/dev/null 2>&1; ready
{
echo "# Package upgrade and downgrade (real dpkg/apt inside a running container)"
echo; echo "From $FROM to $TO and back, $(date -u +%Y-%m-%d). Script: \`dev/upgrade-test.sh\`."; echo
step "Before the upgrade ($FROM): version, initializer, loaded classes" state
# the real package path: add GitLab's apt repository and install the newer package
docker exec $NAME sh -c 'apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq curl gnupg apt-transport-https >/dev/null 2>&1; curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash >/dev/null 2>&1'
step "apt-get install gitlab-ce=$TO (the package upgrade; runs the package's own reconfigure)" docker exec $NAME sh -c "DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-ce=$TO"
ready
step "After the upgrade: version, initializer, loaded classes" state
suite() { # label -> runs the overlay suite and prints its summary, any failures, and the log tail if it never finished
  C=$NAME BASE=http://localhost:$PORT VELA_MODE=overlay RESULTS=/tmp/suite.md dev/e2e.sh > /tmp/suite.log 2>&1
  echo "## Full overlay suite $1"; echo
  summary=$(grep -E 'passed|failed' /tmp/suite.log | tail -1)
  if [ -n "$summary" ]; then echo "\`$summary\`"; else echo "The suite did not finish. Last lines of its log:"; echo; echo '```'; tail -8 /tmp/suite.log | cut -c1-200; echo '```'; fi
  echo; grep -E '^FAIL' /tmp/suite.log | sed 's/^/    /'; echo
}
suite "after the upgrade"
step "apt-get install --allow-downgrades gitlab-ce=$FROM (the downgrade attempt)" docker exec $NAME sh -c "DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades gitlab-ce=$FROM"
sleep 20; ready
step "After the downgrade attempt: version, initializer, loaded classes" state
suite "after the downgrade attempt"
} > $OUT
echo "written $OUT"
