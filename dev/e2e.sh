#!/bin/bash
# End-to-end tests for the write check against the local GitLab CE from dev/up.sh.
# Real git clients over HTTP, real API calls. Throwaway instance only: it creates users, groups
# and projects, and it temporarily revokes a DB grant to prove fail-closed behaviour.
# Usage: dev/e2e.sh            (writes the results table to docs/e2e-results.md)
set -uo pipefail
cd "$(dirname "$0")/.."

export DOCKER_CONFIG="$(mktemp -d)" DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
export GIT_TERMINAL_PROMPT=0
BASE=http://localhost:8929
C=vela-gitlab-ce
W="$(mktemp -d)"                      # clones live here, outside the repo
RUN=$(date +%s | tail -c 6)           # unique suffix so the script can be re-run
PASS=0; FAIL=0; ROWS=""

psql() { docker exec -i $C gitlab-psql -tA -c "$1"; }
api()  { curl -s -H "PRIVATE-TOKEN: $1" "${@:2}"; }
json() { python3 -c "import sys,json;d=json.load(sys.stdin);print($1)"; }

record() { # name expected actual detail
  local ok="PASS"; [ "$2" = "$3" ] || ok="FAIL"
  [ $ok = PASS ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
  ROWS="$ROWS| $ok | $1 | $2 | $3 |\n"
  printf '%-5s %s (expected %s, got %s)\n' "$ok" "$1" "$2" "$3"
}

# ---------- fixtures ----------
RT="glpat-$(openssl rand -hex 10)"
docker exec -e T="$RT" $C gitlab-rails runner \
  "u=User.find_by_username('root'); t=u.personal_access_tokens.build(name: 'e2e-$RUN', scopes: [:api], expires_at: 7.days.from_now); t.set_token(ENV['T']); t.save!" >/dev/null 2>&1 \
  || { echo "could not create root token"; exit 2; }

mkuser() { # username -> prints "id token"
  local id
  id=$(api $RT -X POST $BASE/api/v4/users -d "email=$1-$RUN@example.com&username=$1$RUN&name=$1&password=$(openssl rand -hex 12)Aa1!&skip_confirmation=true" | json 'd["id"]')
  echo "$id $(api $RT -X POST $BASE/api/v4/users/$id/impersonation_tokens -d "name=e2e&scopes[]=api&expires_at=$(date -v+7d +%F 2>/dev/null || date -d +7days +%F)" | json 'd["token"]')"
}
read AID AT <<<"$(mkuser alice)"; read BID BT <<<"$(mkuser bob)"
AU=alice$RUN; BU=bob$RUN
FEG=$(api $RT -X POST $BASE/api/v4/groups -d "name=fe-$RUN&path=fe-$RUN" | json 'd["id"]')
BEG=$(api $RT -X POST $BASE/api/v4/groups -d "name=be-$RUN&path=be-$RUN" | json 'd["id"]')
api $RT -X POST $BASE/api/v4/groups/$FEG/members -d "user_id=$AID&access_level=30" >/dev/null
api $RT -X POST $BASE/api/v4/groups/$BEG/members -d "user_id=$BID&access_level=30" >/dev/null

mkproject() {
  local pid
  pid=$(api $RT -X POST $BASE/api/v4/projects -d "name=$1-$RUN&visibility=private&initialize_with_readme=true" | json 'd["id"]')
  for u in $AID $BID; do api $RT -X POST $BASE/api/v4/projects/$pid/members -d "user_id=$u&access_level=30" >/dev/null; done
  # Developers may push to main, so the path rules are the only thing standing in the way.
  api $RT -X DELETE $BASE/api/v4/projects/$pid/protected_branches/main >/dev/null
  api $RT -X POST $BASE/api/v4/projects/$pid/protected_branches -d "name=main&push_access_level=30&merge_access_level=30" >/dev/null
  echo $pid
}
PID=$(mkproject e2e); OPEN=$(mkproject e2e-open)

seed() { # create files as root (admin, exempt), before the add-on is switched on for the project
  api $RT -X POST $BASE/api/v4/projects/$PID/repository/commits -H 'Content-Type: application/json' -d '{
    "branch":"main","commit_message":"seed","actions":[
    {"action":"create","file_path":"frontend/app.js","content":"1"},
    {"action":"create","file_path":"frontend/security-config.json","content":"{}"},
    {"action":"create","file_path":"backend/api.rb","content":"1"},
    {"action":"create","file_path":"docs/readme.md","content":"1"}]}' >/dev/null
}
seed

# Policy: fe owns frontend/ (except one file), be owns backend/, docs/ readable by both and writable by fe.
rule() { psql "INSERT INTO path_permission_rules (project_id,path,path_type,principal_type,principal_id,level,effect) VALUES ($PID,'$1','$2','group',$3,'$4','$5')" >/dev/null; }
psql "INSERT INTO path_permission_settings (project_id,enabled) VALUES ($PID,true)" >/dev/null
for l in view read write; do
  rule frontend dir $FEG $l allow; rule backend dir $BEG $l allow
  rule frontend/security-config.json file $FEG $l deny
done
for l in view read; do rule docs dir $FEG $l allow; rule docs dir $BEG $l allow; done
rule docs dir $FEG write allow

# ---------- git helpers ----------
clone() { # user token dir project -> clone with identity set
  git clone -q "http://$1:$2@localhost:8929/root/$4.git" "$3" 2>/dev/null || return 1
  git -C "$3" config user.name "$1"; git -C "$3" config user.email "$1@example.com"
}
PNAME=$(api $RT $BASE/api/v4/projects/$PID | json 'd["path"]')
ONAME=$(api $RT $BASE/api/v4/projects/$OPEN | json 'd["path"]')
# the project lives under root, whose path is "root"
clone $AU $AT $W/alice $PNAME || { echo "clone failed"; exit 2; }
clone $BU $BT $W/bob $PNAME || exit 2

fresh() { git -C "$1" fetch -q origin 2>/dev/null; git -C "$1" checkout -q -B "${2:-work}" origin/main; }
edit() { mkdir -p "$(dirname "$1/$2")"; echo "$RANDOM$RANDOM" > "$1/$2"; git -C "$1" add -A; }
commit() { git -C "$1" commit -q -m "${2:-change}" ${3:+--author="$3"}; }
push() { git -C "$1" push -q origin "${@:2}" 2>&1; }
verdict() { [ "$1" -eq 0 ] && echo allowed || echo rejected; }

# ---------- push tests ----------
D=$W/alice; fresh $D t1; edit $D frontend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t1); record "alice edits own folder (frontend/)" allowed $(verdict $?)

fresh $D t2; edit $D backend/api.rb; commit $D; out=$(push $D HEAD:refs/heads/t2); rc=$?
record "alice edits other team's folder (backend/)" rejected $(verdict $rc)

fresh $D t3; edit $D backend/api.rb; commit $D c1; git -C $D checkout -q HEAD~1 -- backend/api.rb; git -C $D add -A; commit $D "revert c1"
git -C $D diff --quiet origin/main HEAD -- backend && NET=none || NET=changed
out=$(push $D HEAD:refs/heads/t3); record "forbidden change then revert in same push (net diff empty: $NET)" rejected $(verdict $?)

fresh $D t4; git -C $D mv frontend/app.js backend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t4); record "rename out of own folder into backend/" rejected $(verdict $?)
fresh $D t5; git -C $D mv backend/api.rb frontend/api.rb; commit $D; out=$(push $D HEAD:refs/heads/t5); record "rename out of backend/ into own folder" rejected $(verdict $?)
fresh $D t6; git -C $D rm -q backend/api.rb; commit $D; out=$(push $D HEAD:refs/heads/t6); record "delete a file in backend/" rejected $(verdict $?)

fresh $D t7; edit $D docs/readme.md; commit $D; out=$(push $D HEAD:refs/heads/t7); record "alice edits docs/ (write granted)" allowed $(verdict $?)
B=$W/bob; fresh $B b1; edit $B docs/readme.md; commit $B; out=$(push $B HEAD:refs/heads/b1); record "bob edits docs/ (read only)" rejected $(verdict $?)
fresh $B b2; edit $B backend/api.rb; commit $B; out=$(push $B HEAD:refs/heads/b2); record "bob edits own folder (backend/)" allowed $(verdict $?)

fresh $D t8; edit $D frontend/security-config.json; commit $D; out=$(push $D HEAD:refs/heads/t8); rc=$?
record "alice edits file with explicit deny" rejected $(verdict $rc)
case "$out" in *security-config*) leak=leaked;; *) leak=hidden;; esac
fresh $D t9; edit $D backend/api.rb; commit $D; out=$(push $D HEAD:refs/heads/t9)
case "$out" in *api.rb*) leak2=leaked;; *) leak2=hidden;; esac
record "denial message hides names of paths alice cannot view" hidden $leak2

fresh $D t10; edit $D backend/api.rb; commit $D "spoof" "root <root@example.com>"; out=$(push $D HEAD:refs/heads/t10)
record "forbidden change with spoofed author (root)" rejected $(verdict $?)

fresh $D t11; edit $D frontend/app.js; commit $D; git -C $D checkout -q -b t12 origin/main; edit $D backend/api.rb; commit $D
out=$(git -C $D push origin t11:refs/heads/t11 t12:refs/heads/t12 2>&1)
api $RT $BASE/api/v4/projects/$PID/repository/branches/t12 | grep -q '"name"' && has=exists || has=absent
record "multi-ref push containing a forbidden ref: forbidden branch created?" absent $has

fresh $D t13; edit $D backend/api.rb; commit $D; git -C $D tag -a v-bad -m bad; out=$(push $D v-bad)
record "new annotated tag on a commit with a forbidden change" rejected $(verdict $?)
fresh $D t13b; edit $D backend/api.rb; commit $D; git -C $D tag v-bad-lw; out=$(push $D v-bad-lw)
record "new lightweight tag on a commit with a forbidden change" rejected $(verdict $?)
git -C $D tag -d v-bad v-bad-lw >/dev/null 2>&1

R=$W/root; clone root $RT $R $PNAME 2>/dev/null; git -C $R config user.name root; git -C $R config user.email root@example.com
fresh $R r1; edit $R backend/api.rb; commit $R; out=$(push $R HEAD:refs/heads/r1); record "admin edits any path (never locked out)" allowed $(verdict $?)

# ---------- API commits and merges ----------
apicommit() { # token file -> http status
  curl -s -o /dev/null -w '%{http_code}' -H "PRIVATE-TOKEN: $1" -H 'Content-Type: application/json' \
    -X POST $BASE/api/v4/projects/$PID/repository/commits \
    -d "{\"branch\":\"api-$2-$RANDOM\",\"start_branch\":\"main\",\"commit_message\":\"api\",\"actions\":[{\"action\":\"update\",\"file_path\":\"$2\",\"content\":\"$RANDOM\"}]}"
}
st=$(apicommit $AT backend/api.rb); [ "$st" = 201 ] && v=allowed || v=rejected; record "API commit to forbidden path (HTTP $st)" rejected $v
st=$(apicommit $AT frontend/app.js); [ "$st" = 201 ] && v=allowed || v=rejected; record "API commit to allowed path (HTTP $st)" allowed $v

# Web editor, Web IDE and squash/rebase all use the same commit machinery as the API; the merge below
# is the case where the merge actor differs from the author.
api $RT -X POST $BASE/api/v4/projects/$PID/repository/commits -H 'Content-Type: application/json' \
  -d '{"branch":"rootfix","start_branch":"main","commit_message":"root edits backend","actions":[{"action":"update","file_path":"backend/api.rb","content":"root"}]}' >/dev/null
MR=$(api $RT -X POST $BASE/api/v4/projects/$PID/merge_requests -d "source_branch=rootfix&target_branch=main&title=root+backend+fix" | json 'd["iid"]')
sleep 3
st=$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H "PRIVATE-TOKEN: $AT" $BASE/api/v4/projects/$PID/merge_requests/$MR/merge)
sleep 3
state=$(api $RT $BASE/api/v4/projects/$PID/merge_requests/$MR | json 'd["state"]')
[ "$state" = merged ] && v=allowed || v=rejected
record "alice merges root's MR that changes backend/ (merge HTTP $st, state $state)" rejected $v

# ---------- revocation, disabled project, fail closed ----------
api $RT -X DELETE $BASE/api/v4/groups/$FEG/members/$AID >/dev/null
fresh $D t14; edit $D frontend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t14); record "after removal from fe group, alice edits frontend/" rejected $(verdict $?)
api $RT -X POST $BASE/api/v4/groups/$FEG/members -d "user_id=$AID&access_level=30" >/dev/null

O=$W/open; clone $AU $AT $O $ONAME; fresh $O o1; edit $O backend/anything.rb; commit $O; out=$(push $O HEAD:refs/heads/o1)
record "project without path permissions keeps native behaviour" allowed $(verdict $?)

psql "REVOKE SELECT ON path_permission_settings FROM gitlab" >/dev/null
fresh $D t15; edit $D frontend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t15); rc=$?
psql "GRANT SELECT ON path_permission_settings TO gitlab" >/dev/null
record "rules unreadable: even an allowed push is rejected (fail closed)" rejected $(verdict $rc)
fresh $D t16; edit $D frontend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t16); record "after the grant is restored, pushes work again" allowed $(verdict $?)

# ---------- report ----------
VER=$(docker exec $C cat /opt/gitlab/embedded/service/gitlab-rails/VERSION)
{
  echo "# End-to-end results"
  echo
  echo "GitLab CE $VER (Docker, arm64), vela commit $(git rev-parse --short HEAD), $(date -u +%Y-%m-%d). Script: \`dev/e2e.sh\`."
  echo
  echo "| Result | Case | Expected | Got |"; echo "| --- | --- | --- | --- |"
  printf "$ROWS"
  echo
  echo "**$PASS passed, $FAIL failed.**"
} > docs/e2e-results.md
echo; echo "$PASS passed, $FAIL failed (table in docs/e2e-results.md)"
rm -rf "$W"
[ $FAIL -eq 0 ]
