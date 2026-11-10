# End-to-end results

GitLab CE 19.0.2 (Docker, arm64), vela commit 8260e1b, 2026-11-10. Script: `dev/e2e.sh`.

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
| PASS | after removal from fe group, alice edits frontend/ | rejected | rejected |
| PASS | project without path permissions keeps native behaviour | allowed | allowed |
| PASS | rules unreadable: even an allowed push is rejected (fail closed) | rejected | rejected |
| PASS | after the grant is restored, pushes work again | allowed | allowed |

**23 passed, 0 failed.**
