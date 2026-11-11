#!/bin/bash
# End-to-end tests for the write check against the local GitLab CE from dev/up.sh.
# Real git clients over HTTP, real API calls. Throwaway instance only: it creates users, groups
# and projects, and it temporarily revokes a DB grant to prove fail-closed behaviour.
# Usage: dev/e2e.sh            (writes the results table to docs/e2e-results.md)
set -uo pipefail
cd "$(dirname "$0")/.."

export DOCKER_CONFIG="$(mktemp -d)"
[ -S "$HOME/.colima/default/docker.sock" ] && export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
export GIT_TERMINAL_PROMPT=0
BASE="${BASE:-http://localhost:8929}"
C="${C:-vela-gitlab-ce}"
RESULTS="${RESULTS:-docs/e2e-results.md}"
MODE="${VELA_MODE:-overlay}"   # overlay = Rails overlay (rules in DB); hook = server hook only (rules in a CI/CD variable)
W="$(mktemp -d)"                      # clones live here, outside the repo
RUN=$(date +%s | tail -c 6)           # unique suffix so the script can be re-run
PASS=0; FAIL=0; ROWS=""
REPO_ROOT="$(pwd -P)"
# Run git only inside a test clone under $W. An empty or overwritten variable must never run git in the
# vela repo (git -C "" means "here"), which once pushed junk branches to the real remote.
g() { local d="$1"; shift
  case "$d" in "$W"/*) ;; *) echo "REFUSING git in '$d': not a test clone under $W" >&2; exit 3;; esac
  [ "$(cd "$d" 2>/dev/null && pwd -P)" != "$REPO_ROOT" ] || { echo "REFUSING git in the repo root" >&2; exit 3; }
  git -C "$d" "$@"; }

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
# the token must work before any fixture is built; if not, say what the server answered instead of failing later on empty JSON
chk=$(curl -s -i -H "PRIVATE-TOKEN: $RT" "$BASE/api/v4/user" | tr -d '\r' | head -12)
echo "$chk" | grep -q '"username":"root"' || { echo "root token does not work against $BASE; server answered:"; echo "$chk" | cut -c1-200; exit 2; }

if [ "$MODE" = hook ]; then
  docker exec $C sh -c "mkdir -p /etc/vela /var/opt/gitlab/gitaly/custom_hooks/pre-receive.d && rm -f /var/opt/gitlab/gitaly/custom_hooks/pre-receive.d/vela && cp /opt/vela-path-permissions/server-hook/vela /var/opt/gitlab/gitaly/custom_hooks/pre-receive.d/vela && chown -R git:git /var/opt/gitlab/gitaly/custom_hooks && chmod 755 /var/opt/gitlab/gitaly/custom_hooks/pre-receive.d/vela && printf 'VELA_GITLAB_URL=%s\nVELA_TOKEN=%s\n' '$BASE' '$RT' > /etc/vela/hook.env && chmod 644 /etc/vela/hook.env" || { echo "could not install the hook"; exit 2; }
fi
break_rules() { if [ "$MODE" = hook ]; then docker exec $C sh -c "sed -i 's/^VELA_TOKEN=.*/VELA_TOKEN=glpat-broken/' /etc/vela/hook.env"; else psql "REVOKE SELECT ON path_permission_settings FROM gitlab" >/dev/null; fi; }
fix_rules() { if [ "$MODE" = hook ]; then docker exec $C sh -c "sed -i 's/^VELA_TOKEN=.*/VELA_TOKEN=$RT/' /etc/vela/hook.env"; else psql "GRANT SELECT ON path_permission_settings TO gitlab" >/dev/null; fi; }

# A crashed earlier run must never leave the rules unreadable (that rejects every request on the instance).
[ "$MODE" = overlay ] && fix_rules
trap 'fix_rules >/dev/null 2>&1' EXIT

mkuser() { # username -> prints "id token"
  local id pw="$(openssl rand -hex 12)Aa1!"
  id=$(api $RT -X POST $BASE/api/v4/users -d "email=$1-$RUN@example.com&username=$1$RUN&name=$1&password=$pw&skip_confirmation=true" | json 'd["id"]')
  echo "$id $pw $(api $RT -X POST $BASE/api/v4/users/$id/impersonation_tokens -d "name=e2e&scopes[]=api&expires_at=$(date -v+7d +%F 2>/dev/null || date -d +7days +%F)" | json 'd["token"]')"
}
read AID APW AT <<<"$(mkuser alice)"; read BID BPW BT <<<"$(mkuser bob)"
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
POLICY=""
rule() {
  if [ "$MODE" = hook ]; then POLICY="$POLICY{\"path\":\"$1\",\"type\":\"$2\",\"principal_type\":\"group\",\"principal_id\":$3,\"level\":\"$4\",\"effect\":\"$5\"},"
  else psql "INSERT INTO path_permission_rules (project_id,path,path_type,principal_type,principal_id,level,effect) VALUES ($PID,'$1','$2','group',$3,'$4','$5')" >/dev/null; fi
}
[ "$MODE" = hook ] || psql "INSERT INTO path_permission_settings (project_id,enabled) VALUES ($PID,true)" >/dev/null
for l in view read write; do
  rule frontend dir $FEG $l allow; rule backend dir $BEG $l allow
  rule frontend/security-config.json file $FEG $l deny
done
for l in view read; do rule docs dir $FEG $l allow; rule docs dir $BEG $l allow; done
rule docs dir $FEG write allow
if [ "$MODE" = hook ]; then
  VAL=$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "{\"enabled\":true,\"rules\":[${POLICY%,}]}")
  api $RT -X POST $BASE/api/v4/projects/$PID/variables -H 'Content-Type: application/json' -d "{\"key\":\"VELA_PATH_POLICY\",\"value\":$VAL}" >/dev/null
fi

# ---------- git helpers ----------
clone() { # user token dir project -> clone with identity set
  git clone -q "http://$1:$2@${BASE#http://}/root/$4.git" "$3" 2>/dev/null || return 1
  g "$3" config user.name "$1"; g "$3" config user.email "$1@example.com"
}
PNAME=$(api $RT $BASE/api/v4/projects/$PID | json 'd["path"]')
ONAME=$(api $RT $BASE/api/v4/projects/$OPEN | json 'd["path"]')
# the project lives under root, whose path is "root"
clone $AU $AT $W/alice $PNAME || { echo "clone failed"; exit 2; }
clone $BU $BT $W/bob $PNAME || exit 2

fresh() { g "$1" fetch -q origin 2>/dev/null; g "$1" checkout -q -B "${2:-work}" origin/main; }
edit() { mkdir -p "$(dirname "$1/$2")"; echo "$RANDOM$RANDOM" > "$1/$2"; g "$1" add -A; }
commit() { g "$1" commit -q -m "${2:-change}" ${3:+--author="$3"}; }
push() { g "$1" push -q origin "${@:2}" 2>&1; }
verdict() { [ "$1" -eq 0 ] && echo allowed || echo rejected; }

# ---------- push tests ----------
D=$W/alice; fresh $D t1; edit $D frontend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t1); record "alice edits own folder (frontend/)" allowed $(verdict $?)

fresh $D t2; edit $D backend/api.rb; commit $D; out=$(push $D HEAD:refs/heads/t2); rc=$?
record "alice edits other team's folder (backend/)" rejected $(verdict $rc)

fresh $D t3; edit $D backend/api.rb; commit $D c1; g $D checkout -q HEAD~1 -- backend/api.rb; g $D add -A; commit $D "revert c1"
g $D diff --quiet origin/main HEAD -- backend && NET=none || NET=changed
out=$(push $D HEAD:refs/heads/t3); record "forbidden change then revert in same push (net diff empty: $NET)" rejected $(verdict $?)

fresh $D t4; g $D mv frontend/app.js backend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t4); record "rename out of own folder into backend/" rejected $(verdict $?)
fresh $D t5; g $D mv backend/api.rb frontend/api.rb; commit $D; out=$(push $D HEAD:refs/heads/t5); record "rename out of backend/ into own folder" rejected $(verdict $?)
fresh $D t6; g $D rm -q backend/api.rb; commit $D; out=$(push $D HEAD:refs/heads/t6); record "delete a file in backend/" rejected $(verdict $?)

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

fresh $D t11; edit $D frontend/app.js; commit $D; g $D checkout -q -b t12 origin/main; edit $D backend/api.rb; commit $D
out=$(g $D push origin t11:refs/heads/t11 t12:refs/heads/t12 2>&1)
api $RT $BASE/api/v4/projects/$PID/repository/branches/t12 | grep -q '"name"' && has=exists || has=absent
record "multi-ref push containing a forbidden ref: forbidden branch created?" absent $has

fresh $D t13; edit $D backend/api.rb; commit $D; g $D tag -a v-bad -m bad; out=$(push $D v-bad)
record "new annotated tag on a commit with a forbidden change" rejected $(verdict $?)
fresh $D t13b; edit $D backend/api.rb; commit $D; g $D tag v-bad-lw; out=$(push $D v-bad-lw)
record "new lightweight tag on a commit with a forbidden change" rejected $(verdict $?)
g $D tag -d v-bad v-bad-lw >/dev/null 2>&1

R=$W/root; clone root $RT $R $PNAME 2>/dev/null; g $R config user.name root; g $R config user.email root@example.com
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

# ---------- read hiding (View and Read), overlay tier only ----------
if [ "$MODE" = overlay ]; then
# One root commit touching both teams' folders, so search and diffs have something to hide.
NEEDLE="needle$RUN"
NOTES_RESP=$(api $RT -X POST $BASE/api/v4/projects/$PID/repository/commits -H 'Content-Type: application/json' -d "{
  \"branch\":\"main\",\"commit_message\":\"notes for both\",\"actions\":[
  {\"action\":\"create\",\"file_path\":\"frontend/notes.txt\",\"content\":\"$NEEDLE\"},
  {\"action\":\"create\",\"file_path\":\"backend/notes.txt\",\"content\":\"$NEEDLE\"}]}")
NOTES_SHA=$(api $RT $BASE/api/v4/projects/$PID/repository/commits/main | json 'd["id"]')
P4=$BASE/api/v4/projects/$PID
code() { curl -s -o /dev/null -w '%{http_code}' -H "PRIVATE-TOKEN: $1" "$2"; }
list() { api $1 "$2" | python3 -c "import sys,json;d=json.load(sys.stdin);print(' '.join(sorted(x.get('path',x.get('name','')) for x in d)) if isinstance(d,list) else 'ERR')"; }
has() { case " $1 " in *" $2 "*) echo yes;; *) echo no;; esac; }
record "root: the API commit that creates the notes files (setup for search and diff)" 200 $(code $RT "$BASE/api/v4/projects/$PID/repository/files/frontend%2Fnotes.txt?ref=main")
[ "$(code $RT "$BASE/api/v4/projects/$PID/repository/files/frontend%2Fnotes.txt?ref=main")" = 200 ] || echo "--- notes commit response: $(echo "$NOTES_RESP" | cut -c1-300)" >&2

# root reads first, so any cache filled by an admin could leak to the next user
record "admin reads backend/api.rb (fills any cache)" 200 $(code $RT "$P4/repository/files/backend%2Fapi.rb?ref=main")
T=$(list $AT "$P4/repository/tree?ref=main"); record "alice: tree root hides backend/" no $(has "$T" backend)
record "alice: tree root shows frontend/" yes $(has "$T" frontend)
record "alice: tree root shows an unrestricted file (README.md)" yes $(has "$T" README.md)
record "alice: file in own folder" 200 $(code $AT "$P4/repository/files/frontend%2Fapp.js?ref=main")
record "alice: file in other team's folder is 404 (after admin read)" 404 $(code $AT "$P4/repository/files/backend%2Fapi.rb?ref=main")
record "alice: raw file in other team's folder is 404" 404 $(code $AT "$P4/repository/files/backend%2Fapi.rb/raw?ref=main")
websession() { # user password cookiejar
  local tok; tok=$(curl -s -c "$3" $BASE/users/sign_in | python3 -c "import sys,re;print(re.search(r'name=\"authenticity_token\" value=\"([^\"]+)\"',sys.stdin.read()).group(1))")
  curl -s -o /dev/null -b "$3" -c "$3" -X POST $BASE/users/sign_in --data-urlencode "authenticity_token=$tok" --data-urlencode "user[login]=$1" --data-urlencode "user[password]=$2"
}
wcode() { curl -s -o /dev/null -w '%{http_code}' -b "$1" "$2"; }
websession $AU "$APW" $W/alice.jar
record "alice (web session): raw file in own folder" 200 $(wcode $W/alice.jar "$BASE/root/$PNAME/-/raw/main/frontend/app.js")
record "alice (web session): raw file in other team's folder is 404" 404 $(wcode $W/alice.jar "$BASE/root/$PNAME/-/raw/main/backend/api.rb")
record "alice (web session): blob page of a hidden file looks exactly like a missing file" "$(wcode $W/alice.jar "$BASE/root/$PNAME/-/blob/main/frontend/does-not-exist.rb")" "$(wcode $W/alice.jar "$BASE/root/$PNAME/-/blob/main/backend/api.rb")"
record "alice (web session): blame page of a hidden file looks exactly like a missing file" "$(wcode $W/alice.jar "$BASE/root/$PNAME/-/blame/main/frontend/does-not-exist.rb")" "$(wcode $W/alice.jar "$BASE/root/$PNAME/-/blame/main/backend/api.rb")"
record "alice (web session): edit page of a hidden file looks exactly like a missing file" "$(wcode $W/alice.jar "$BASE/root/$PNAME/-/edit/main/frontend/does-not-exist.rb")" "$(wcode $W/alice.jar "$BASE/root/$PNAME/-/edit/main/backend/api.rb")"
GQ=$(curl -s -H "Authorization: Bearer $AT" -H 'Content-Type: application/json' $BASE/api/graphql -d "{\"query\":\"{ project(fullPath: \\\"root/$PNAME\\\") { repository { paginatedTree(path: \\\"\\\", ref: \\\"main\\\") { nodes { trees { nodes { name } } blobs { nodes { name } } } } } } }\"}")
GN=$(echo "$GQ" | python3 -c "import sys,json;d=json.load(sys.stdin);n=d['data']['project']['repository']['paginatedTree']['nodes'];print(' '.join(x['name'] for g in n for k in ('trees','blobs') for x in g[k]['nodes']))" 2>/dev/null || echo "ERR")
record "alice: GraphQL tree (web file list) hides backend/" no $(has "$GN" backend)
record "alice: GraphQL tree shows frontend/" yes $(has "$GN" frontend)
record "alice: encoded slash variant is still 404" 404 $(code $AT "$P4/repository/files/backend%252Fapi.rb?ref=main")
c=$(code $AT "$P4/repository/files/frontend%2F..%2Fbackend%2Fapi.rb?ref=main"); [ "$c" = 200 ] && v=served || v=blocked
record "alice: dot-segment variant is not a way in (HTTP $c)" blocked $v
T=$(list $AT "$P4/repository/tree?ref=main&path=backend"); record "alice: listing backend/ shows nothing" no $(has "$T" api.rb)
T=$(list $AT "$P4/repository/tree?ref=main&path=frontend"); record "alice: explicit-deny file is not listed" no $(has "$T" security-config.json)
record "alice: explicit-deny file is 404" 404 $(code $AT "$P4/repository/files/frontend%2Fsecurity-config.json?ref=main")
T=$(list $AT "$P4/repository/tree?ref=main&recursive=true&per_page=100"); record "alice: recursive tree hides backend/api.rb" no $(has "$T" backend/api.rb)
record "alice: recursive tree shows frontend/app.js" yes $(has "$T" frontend/app.js)
record "bob: reads own folder" 200 $(code $BT "$P4/repository/files/backend%2Fapi.rb?ref=main")
record "bob: reads shared docs/" 200 $(code $BT "$P4/repository/files/docs%2Freadme.md?ref=main")
record "bob: frontend/ is 404" 404 $(code $BT "$P4/repository/files/frontend%2Fapp.js?ref=main")
T=$(list $RT "$P4/repository/tree?ref=main"); record "admin: tree root shows backend/" yes $(has "$T" backend)
record "admin: reads any file" 200 $(code $RT "$P4/repository/files/frontend%2Fsecurity-config.json?ref=main")
record "other project without path permissions: files unaffected" 200 $(code $AT "$BASE/api/v4/projects/$OPEN/repository/files/README.md?ref=main")
S=$(api $AT "$P4/search?scope=blobs&search=$NEEDLE" | python3 -c "import sys,json;print(' '.join(sorted(x['path'] for x in json.load(sys.stdin))))")
record "alice: code search hides backend/notes.txt" no $(has "$S" backend/notes.txt)
record "alice: code search finds frontend/notes.txt" yes $(has "$S" frontend/notes.txt)
S=$(api $RT "$P4/search?scope=blobs&search=$NEEDLE" | python3 -c "import sys,json;print(' '.join(sorted(x['path'] for x in json.load(sys.stdin))))")
record "admin: code search finds backend/notes.txt" yes $(has "$S" backend/notes.txt)
DF=$(api $AT "$P4/repository/commits/$NOTES_SHA/diff" | python3 -c "import sys,json;print(' '.join(sorted(x['new_path'] for x in json.load(sys.stdin))))")
record "alice: commit diff hides backend/notes.txt" no $(has "$DF" backend/notes.txt)
record "alice: commit diff shows frontend/notes.txt" yes $(has "$DF" frontend/notes.txt)
DF=$(api $RT "$P4/repository/commits/$NOTES_SHA/diff" | python3 -c "import sys,json;print(' '.join(sorted(x['new_path'] for x in json.load(sys.stdin))))")
record "admin: commit diff shows backend/notes.txt" yes $(has "$DF" backend/notes.txt)


# ---------- settings page (Project Settings, overlay tier) ----------
websession root "$(cat dev/.root_password)" $W/root.jar
PAGE="$BASE/root/$PNAME/-/path_permissions"
csrf() { curl -s -b "$1" "$2" | python3 -c "import sys,re;print(re.search(r'name=\"authenticity_token\" value=\"([^\"]+)\"',sys.stdin.read()).group(1))"; }
record "settings page: admin can open it" 200 $(wcode $W/root.jar $PAGE)
record "settings page: a Developer gets 404" 404 $(wcode $W/alice.jar $PAGE)
case "$(curl -s -b $W/root.jar $PAGE)" in *"Path permissions"*"git clone"*) sees=yes;; *) sees=no;; esac
record "settings page: shows the clone-limit warning" yes $sees
CT=$(csrf $W/root.jar $PAGE)
ac=$(curl -s -o /dev/null -w '%{http_code}' -b $W/root.jar -X POST $PAGE/add --data-urlencode "authenticity_token=$CT" -d path=uitest -d path_type=dir -d principal_type=group --data-urlencode "principal=fe-$RUN" -d effect=allow -d 'levels[]=view' -d 'levels[]=read')
record "settings page: adding a rule through the form" 302 $ac
record "settings page: the rule is stored (2 levels)" 2 "$(psql "SELECT count(*) FROM path_permission_rules WHERE project_id=$PID AND path='uitest'")"
case "$(curl -s -b $W/root.jar $PAGE)" in *uitest*) shows=yes;; *) shows=no;; esac
record "settings page: the rule is listed" yes $shows
case "$(curl -s -b $W/root.jar "$PAGE?explain_user=$AU&explain_path=uitest/x.txt")" in *"you are not on it"*) ex=yes;; *) ex=no;; esac
record "settings page: Test as user explains a blocked write" yes $ex
bad=$(curl -s -o /dev/null -w '%{http_code}' -b $W/root.jar -X POST $PAGE/add --data-urlencode "authenticity_token=$CT" -d 'path=../evil' -d path_type=dir -d principal_type=group --data-urlencode "principal=fe-$RUN" -d effect=allow -d 'levels[]=view')
record "settings page: a malformed path is refused (nothing stored)" 0 "$(psql "SELECT count(*) FROM path_permission_rules WHERE project_id=$PID AND path LIKE '%evil%'")"
rc=$(curl -s -o /dev/null -w '%{http_code}' -b $W/root.jar -X POST $PAGE/remove --data-urlencode "authenticity_token=$CT" -d path=uitest -d path_type=dir -d principal_type=group -d "principal_id=$FEG")
record "settings page: removing the rule" 0 "$(psql "SELECT count(*) FROM path_permission_rules WHERE project_id=$PID AND path='uitest'")"
record "settings page: changes are in the audit log" 2 "$(psql "SELECT count(*) FROM path_permission_audits WHERE project_id=$PID AND action IN ('add_rule','delete_rule')")"
nc=$(curl -s -o /dev/null -w '%{http_code}' -X POST $PAGE/add -d path=x)
[ "$nc" = 200 ] && v=accepted || v=refused
record "settings page: a request without a session or CSRF token is refused (HTTP $nc)" refused $v
fi
# ---------- revocation, disabled project, fail closed ----------
api $RT -X DELETE $BASE/api/v4/groups/$FEG/members/$AID >/dev/null
fresh $D t14; edit $D frontend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t14); record "after removal from fe group, alice edits frontend/" rejected $(verdict $?)
api $RT -X POST $BASE/api/v4/groups/$FEG/members -d "user_id=$AID&access_level=30" >/dev/null

O=$W/open; clone $AU $AT $O $ONAME; fresh $O o1; edit $O backend/anything.rb; commit $O; out=$(push $O HEAD:refs/heads/o1)
record "project without path permissions keeps native behaviour" allowed $(verdict $?)

# A project with CI/CD turned off: GitLab answers 403 (not 404) for the policy variable. This once rejected every push.
NOCI=$(mkproject e2e-noci); api $RT -X PUT $BASE/api/v4/projects/$NOCI -d "builds_access_level=disabled" >/dev/null
NNAME=$(api $RT $BASE/api/v4/projects/$NOCI | json 'd["path"]')
record "CI/CD really is off on that project (variables API says 403)" 403 $(code $RT "$BASE/api/v4/projects/$NOCI/variables/VELA_PATH_POLICY")
N=$W/noci; clone $AU $AT $N $NNAME; fresh $N n1; edit $N backend/anything.rb; commit $N; out=$(push $N HEAD:refs/heads/n1)
record "project with CI/CD turned off keeps native behaviour (push accepted)" allowed $(verdict $?)

break_rules
[ "$MODE" = overlay ] && RC=$(code $AT "$P4/repository/files/frontend%2Fapp.js?ref=main")
fresh $D t15; edit $D frontend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t15); rc=$?
fix_rules
record "rules unreadable: even an allowed push is rejected (fail closed)" rejected $(verdict $rc)
[ "$MODE" = overlay ] && record "rules unreadable: reads fail closed too (404)" 404 $RC
fresh $D t16; edit $D frontend/app.js; commit $D; out=$(push $D HEAD:refs/heads/t16); record "after the grant is restored, pushes work again" allowed $(verdict $?)

# ---------- report ----------
VER=$(docker exec $C cat /opt/gitlab/embedded/service/gitlab-rails/VERSION)
{
  echo "# End-to-end results"
  echo
  echo "GitLab CE $VER (Docker), tier: $MODE, vela commit $(git rev-parse --short HEAD), $(date -u +%Y-%m-%d). Script: \`dev/e2e.sh\`."
  echo
  echo "| Result | Case | Expected | Got |"; echo "| --- | --- | --- | --- |"
  printf "$ROWS"
  echo
  echo "**$PASS passed, $FAIL failed.**"
} > "$RESULTS"
echo; echo "$PASS passed, $FAIL failed (table in $RESULTS)"
rm -rf "$W"
[ $FAIL -eq 0 ]
