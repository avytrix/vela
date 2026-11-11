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
# "healthy" and a 200 on the sign-in page are not enough after a package upgrade: the web server restarts
# at the end. Also wait until the API answers with real JSON three times in a row.
api_ready() { local ok=0; for i in $(seq 1 120); do
    if [ "$(curl -s http://localhost:$PORT/api/v4/projects | head -c1)" = "[" ]; then ok=$((ok+1)); [ $ok -ge 3 ] && break; else ok=0; fi; sleep 5; done; [ $ok -ge 3 ]; }
ready() { for i in $(seq 1 120); do [ "$(docker inspect -f '{{.State.Health.Status}}' $NAME 2>/dev/null)" = healthy ] && break; sleep 10; done
          local up=; for i in $(seq 1 90); do [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:$PORT/users/sign_in)" = 200 ] && up=1 && break; sleep 5; done
          [ -n "$up" ] && api_ready && sleep 20; }
state() { docker exec $NAME sh -c 'cat /opt/gitlab/embedded/service/gitlab-rails/VERSION; ls /opt/gitlab/embedded/service/gitlab-rails/config/initializers/zz_path_permissions.rb 2>&1 | tail -1'; docker exec $NAME gitlab-rails runner 'puts Gitlab::Checks::DiffCheck.ancestors.first, Repository.ancestors.first' 2>&1 | grep -v '^\s*from' | tr '\n' ' '; }
step() { echo "## $1"; echo; echo '```'; shift; "$@" 2>&1 | tail -${TAIL:-12}; echo '```'; echo; }

# A CI runner has about 7 GB. GitLab plus its monitoring services plus a second Rails process (gitlab-rails runner)
# can starve the web workers, so stop the monitoring services before each suite; they are not part of the test.
lean() { docker exec $NAME sh -c 'for s in prometheus redis-exporter postgres-exporter gitlab-exporter node-exporter alertmanager; do gitlab-ctl stop $s >/dev/null 2>&1; done; true'; }
health() { echo '```'; docker exec $NAME sh -c 'free -m; echo; gitlab-ctl status 2>&1 | cut -c1-80 | head -20' 2>&1
  echo; for u in /api/v4/version /api/v4/projects /users/sign_in; do
    curl -s -m 60 -o /dev/null -w "GET $u: HTTP %{http_code} in %{time_total}s\n" http://localhost:$PORT$u; done
  echo; echo '--- from inside the container (is the problem the published port or the server?)'
  docker exec $NAME sh -c "curl -s -m 20 -o /dev/null -w 'GET /users/sign_in on :$PORT: HTTP %{http_code}\n' http://localhost:$PORT/users/sign_in; curl -s -m 20 -o /dev/null -w 'GET /users/sign_in on :80: HTTP %{http_code}\n' http://localhost/users/sign_in; (ss -ltn 2>/dev/null || netstat -ltn) | grep LISTEN | awk '{print \$4}' | tr '\n' ' '; echo; grep -E '^external_url|omnibus_config' /etc/gitlab/gitlab.rb; grep -m2 -E 'listen' /var/opt/gitlab/nginx/conf/gitlab-http.conf" 2>&1
  docker port $NAME 2>&1
  echo; echo '--- last errors in the Rails log'
  docker exec $NAME sh -c 'tail -n 400 /var/log/gitlab/gitlab-rails/production_json.log 2>/dev/null | grep -E "\"severity\":\"(ERROR|FATAL)\"|exception|\"status\":(500|502|503)" | tail -n 6 | cut -c1-400; echo "--- puma stderr"; tail -n 8 /var/log/gitlab/puma/puma_stderr.log 2>/dev/null | cut -c1-300; echo "--- workhorse"; tail -n 6 /var/log/gitlab/gitlab-workhorse/current 2>/dev/null | grep -o "\"method\":\"[A-Z]*\"\|\"status\":[0-9]*\|\"uri\":\"[^\"]*\"\|\"time\":\"[^\"]*\"" | paste -sd" " -' 2>&1
  echo '```'; }
suite() { # label -> runs the overlay suite and prints its summary, any failures, and the log tail if it never finished
  lean
  C=$NAME BASE=http://localhost:$PORT VELA_MODE=overlay RESULTS=/tmp/suite.md dev/e2e.sh > /tmp/suite.log 2>&1
  echo "## Full overlay suite $1"; echo
  summary=$(grep -E 'passed|failed' /tmp/suite.log | tail -1)
  case "$summary" in *" 0 failed"*) ;; *) SUITE_FAILED=1 ;; esac # a suite that did not finish, or had failures, fails the job
  if [ -n "$summary" ]; then echo "\`$summary\`"; else echo "The suite did not finish. First and last lines of its log:"; echo; echo '```'; head -12 /tmp/suite.log | cut -c1-200; echo '...'; tail -8 /tmp/suite.log | cut -c1-200; echo '```'; fi
  [ -n "$summary" ] || { echo 'Server memory and services right after the failure:'; health; }
  echo; grep -E '^FAIL' /tmp/suite.log | sed 's/^/    /'; echo
}
# The server must answer on the published port after a package change; if it does not, the suites cannot pass,
# so say why and stop instead of running them out.
reachable() { ready && return; echo "The server does not answer on http://localhost:$PORT $1:"; health; echo "server not reachable $1; see $OUT" >&2; exit 1; }

NAME=$NAME VOL=vela_upgrade GITLAB_TAG=$FROM HTTP_PORT=$PORT SSH_PORT=$((PORT+1)) dev/up.sh >/dev/null 2>&1 || { echo "could not start $FROM"; exit 2; }
ready || { echo "$FROM never became ready"; exit 2; }
docker exec -i $NAME gitlab-psql -v app_role=gitlab -f - < db/schema.sql >/dev/null 2>&1
docker exec $NAME gitlab-ctl restart puma >/dev/null 2>&1; ready
{
echo "# Package upgrade and downgrade (real dpkg/apt inside a running container)"
echo; echo "From $FROM to $TO and back, $(date -u +%Y-%m-%d). Script: \`dev/upgrade-test.sh\`."; echo
step "Before the upgrade ($FROM): version, initializer, loaded classes" state
# the real package path: add GitLab's apt repository and install the newer package
docker exec $NAME sh -c 'apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq curl gnupg apt-transport-https >/dev/null 2>&1; curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash >/dev/null 2>&1'
# The Docker image patches the package cookbook to read GITLAB_OMNIBUS_CONFIG via /assets/gitlab.rb; installing a
# package replaces the cookbook, so its reconfigure reads only /etc/gitlab/gitlab.rb (external_url, the add-on, ...).
# Put the config where a package install keeps it.
docker exec $NAME sh -c 'printf "%s\n" "$GITLAB_OMNIBUS_CONFIG" >> /etc/gitlab/gitlab.rb'
step "apt-get install gitlab-ce=$TO (the package upgrade; runs the package's own reconfigure)" docker exec $NAME sh -c "DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-ce=$TO"
reachable "after the upgrade"
step "After the upgrade: version, initializer, loaded classes" state
suite "after the upgrade"
step "apt-get install --allow-downgrades gitlab-ce=$FROM (the downgrade attempt)" docker exec $NAME sh -c "DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades gitlab-ce=$FROM"
sleep 20; reachable "after the downgrade attempt"
step "After the downgrade attempt: version, initializer, loaded classes" state
suite "after the downgrade attempt"
} > $OUT
echo "written $OUT"
[ -z "${SUITE_FAILED:-}" ] || { echo "a suite did not pass; see $OUT"; exit 1; }
