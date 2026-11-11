# End-to-end results

GitLab CE 19.5.3 (Docker), tier: overlay, vela commit 92f5e41, 2026-11-10. Script: `dev/e2e.sh`.

| Result | Case | Expected | Got |
| --- | --- | --- | --- |
| PASS | alice edits own folder (frontend/) | allowed | allowed |
| PASS | alice edits other team's folder (backend/) | rejected | rejected |
| PASS | forbidden change then revert in same push (net diff empty: none) | rejected | rejected |
| PASS | rename out of own folder into backend/ | rejected | rejected |
| PASS | rename out of backend/ into own folder | rejected | rejected |
| PASS | delete a file in backend/ | rejected | rejected |
| PASS | alice edits docs/ (write granted) | allowed | allowed |
| PASS | bob edits docs/ (read only) | rejected | rejected |
| PASS | bob edits own folder (backend/) | allowed | allowed |
| PASS | alice edits file with explicit deny | rejected | rejected |
| PASS | denial message hides names of paths alice cannot view | hidden | hidden |
| PASS | forbidden change with spoofed author (root) | rejected | rejected |
| PASS | multi-ref push containing a forbidden ref: forbidden branch created? | absent | absent |
| PASS | new annotated tag on a commit with a forbidden change | rejected | rejected |
| PASS | new lightweight tag on a commit with a forbidden change | rejected | rejected |
| PASS | admin edits any path (never locked out) | allowed | allowed |
| PASS | API commit to forbidden path (HTTP 400) | rejected | rejected |
| PASS | API commit to allowed path (HTTP 201) | allowed | allowed |
| PASS | alice merges root's MR that changes backend/ (merge HTTP 422, state opened) | rejected | rejected |
| PASS | admin reads backend/api.rb (fills any cache) | 200 | 200 |
| PASS | alice: tree root hides backend/ | no | no |
| PASS | alice: tree root shows frontend/ | yes | yes |
| PASS | alice: tree root shows an unrestricted file (README.md) | yes | yes |
| PASS | alice: file in own folder | 200 | 200 |
| PASS | alice: file in other team's folder is 404 (after admin read) | 404 | 404 |
| PASS | alice: raw file in other team's folder is 404 | 404 | 404 |
| PASS | alice (web session): raw file in own folder | 200 | 200 |
| PASS | alice (web session): raw file in other team's folder is 404 | 404 | 404 |
| PASS | alice (web session): blob page of a hidden file looks exactly like a missing file | 302 | 302 |
| PASS | alice (web session): blame page of a hidden file looks exactly like a missing file | 302 | 302 |
| PASS | alice (web session): edit page of a hidden file looks exactly like a missing file | 302 | 302 |
| PASS | alice: GraphQL tree (web file list) hides backend/ | no | no |
| PASS | alice: GraphQL tree shows frontend/ | yes | yes |
| PASS | alice: encoded slash variant is still 404 | 404 | 404 |
| PASS | alice: dot-segment variant is not a way in (HTTP 400) | blocked | blocked |
| PASS | alice: listing backend/ shows nothing | no | no |
| PASS | alice: explicit-deny file is not listed | no | no |
| PASS | alice: explicit-deny file is 404 | 404 | 404 |
| PASS | alice: recursive tree hides backend/api.rb | no | no |
| PASS | alice: recursive tree shows frontend/app.js | yes | yes |
| PASS | bob: reads own folder | 200 | 200 |
| PASS | bob: reads shared docs/ | 200 | 200 |
| PASS | bob: frontend/ is 404 | 404 | 404 |
| PASS | admin: tree root shows backend/ | yes | yes |
| PASS | admin: reads any file | 200 | 200 |
| PASS | other project without path permissions: files unaffected | 200 | 200 |
| PASS | alice: code search hides backend/notes.txt | no | no |
| PASS | alice: code search finds frontend/notes.txt | yes | yes |
| PASS | admin: code search finds backend/notes.txt | yes | yes |
| PASS | alice: commit diff hides backend/notes.txt | no | no |
| PASS | alice: commit diff shows frontend/notes.txt | yes | yes |
| PASS | admin: commit diff shows backend/notes.txt | yes | yes |
| PASS | settings page: admin can open it | 200 | 200 |
| PASS | settings page: a Developer gets 404 | 404 | 404 |
| PASS | settings page: shows the clone-limit warning | yes | yes |
| PASS | settings page: adding a rule through the form | 302 | 302 |
| PASS | settings page: the rule is stored (2 levels) | 2 | 2 |
| PASS | settings page: the rule is listed | yes | yes |
| PASS | settings page: Test as user explains a blocked write | yes | yes |
| PASS | settings page: a malformed path is refused (nothing stored) | 0 | 0 |
| PASS | settings page: removing the rule | 0 | 0 |
| PASS | settings page: changes are in the audit log | 2 | 2 |
| PASS | settings page: a request without a session or CSRF token is refused (HTTP 422) | refused | refused |
| PASS | after removal from fe group, alice edits frontend/ | rejected | rejected |
| PASS | project without path permissions keeps native behaviour | allowed | allowed |
| PASS | rules unreadable: even an allowed push is rejected (fail closed) | rejected | rejected |
| PASS | rules unreadable: reads fail closed too (404) | 404 | 404 |
| PASS | after the grant is restored, pushes work again | allowed | allowed |

**68 passed, 0 failed.**
