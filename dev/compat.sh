#!/bin/bash
# Run the full end-to-end suite against one GitLab CE version on a throwaway container and volumes.
# Usage: dev/compat.sh <image tag, e.g. 19.0.11-ce.0> [overlay|hook]
# Writes docs/compat/<tag>-<tier>.md and removes the container and volumes afterwards.
set -uo pipefail
cd "$(dirname "$0")/.."
TAG="$1"; TIER="${2:-overlay}"
export DOCKER_CONFIG="$(mktemp -d)"
[ -S "$HOME/.colima/default/docker.sock" ] && export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
SLUG=$(echo "$TAG-$TIER" | tr -c 'a-z0-9\n' '-'); NAME="vela-compat-$SLUG"; PORT=$((20000 + RANDOM % 20000))
cleanup() { docker rm -f -v "$NAME" >/dev/null 2>&1; for v in config data logs; do docker volume rm -f "vela_compat_${SLUG}_$v" >/dev/null 2>&1; done; }
trap cleanup EXIT
mkdir -p docs/compat
[ "$TIER" = hook ] && OVERLAY=0 || OVERLAY=1
NAME=$NAME VOL=vela_compat_$SLUG GITLAB_TAG=$TAG HTTP_PORT=$PORT SSH_PORT=$((PORT+1)) VELA_OVERLAY=$OVERLAY dev/up.sh >/dev/null 2>&1 || { echo "could not start $TAG"; exit 2; }
for i in $(seq 1 120); do [ "$(docker inspect -f '{{.State.Health.Status}}' $NAME 2>/dev/null)" = healthy ] && break; sleep 10; done
[ "$(docker inspect -f '{{.State.Health.Status}}' $NAME 2>/dev/null)" = healthy ] || { echo "$TAG never became healthy"; docker logs --tail 20 $NAME; exit 2; }
# Some versions (19.5) report "healthy" before the web server answers; wait for it.
for i in $(seq 1 90); do [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:$PORT/users/sign_in)" = 200 ] && break; sleep 5; done
if [ "$TIER" = overlay ]; then
  docker exec -i $NAME gitlab-psql -v app_role=gitlab -f - < db/schema.sql >/dev/null 2>&1
  docker exec $NAME gitlab-ctl restart puma >/dev/null 2>&1
  for i in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:$PORT/users/sign_in)" = 200 ] && break; sleep 5; done
fi
C=$NAME BASE=http://localhost:$PORT VELA_MODE=$TIER RESULTS="docs/compat/$SLUG.md" dev/e2e.sh
