# Coding-agent instructions: GitLab folder and file access extension

Prepared: 10 November 2026. Target: GitLab Free, self-managed; exact version and CE/EE edition must be discovered.

## Mission

Implement folder/file access controls for an existing GitLab project while retaining ONE GitLab project and ONE canonical repository. Do not solve this by creating separate projects, mirrors, filtered repositories, or per-user Git histories. Do not require a paid GitLab tier.

Deliver actual code, deployment packaging, documentation, and adversarial tests. Treat this document as implementation instructions, not evidence that GitLab already supports the proposed extension.

Required capabilities: control which users/groups can discover paths, read content, and create/change/delete files. Preserve GitLab's existing membership and protected-branch checks.

## 1. Established facts and architecture limits

- GitLab documents APIs, integrations, webhooks, and server hooks. These do not establish a general, supported plugin interface for intercepting every repository read.
- GitLab integration development adds code to the Rails application. An integration model alone does not implement repository authorization.
- Self-managed Free supports pre-receive hooks, which can reject writes before references change. Hooks cannot filter clone/fetch reads.
- GitLab authorization guidelines require checks across all entry points. Native repository permissions are project-oriented.
- Ordinary clone/fetch of the canonical repository must not be allowed for a principal with path-restricted reads. Git object graphs and history can contain forbidden content. Sparse checkout, shallow/partial clone, hidden UI elements, and protected branches are not confidentiality controls.

Consequently, distinguish two deliverables:

1. **Write-only extension:** a supported server-hook implementation. Everyone with existing repository read access can still read all code. This is a useful component, but does NOT satisfy the full mission by itself.
2. **Confidential path-access extension:** a version-pinned GitLab source patch plus policy engine and administration UI. Restricted users receive controlled browser/API file operations; ordinary Git transfer and unreviewed native surfaces are denied. This is the target architecture for the full mission.

Do not promise a drop-in supported plugin unless the exact installed version exposes and documents all required interception points. If standard Git clone/fetch for path-restricted users becomes mandatory while keeping the same canonical history, report the incompatibility and the required tradeoff; do not silently replace the architecture with filtered repositories.

## 2. Mandatory discovery before implementation

Inspect an authorized development environment, not production. Establish:

- Exact GitLab version, source commit/tag, CE or EE package/image, installation method, deployment topology, and Gitaly/Praefect/Geo involvement.
- Languages, runtimes, frontend framework and build tooling actually used by that tag.
- Authentication methods, inherited memberships, tokens, deploy keys, bot identities, job tokens, runners, and repository visibility.
- All repository read/write entry points available in that tag, including feature flags.

Do not guess controller names, RPC methods, database migrations, hook invocation coverage, or internal API contracts. Record verified source paths and call chains in `docs/version-audit.md`.

Read the official sources listed at the end, then the source and documentation at the installed release tag. Latest documentation is orientation only. Report extension-point findings and unsupported assumptions in `docs/feasibility.md`. Implement locally wherever feasible; mark missing environment evidence explicitly rather than inventing test results.

## 3. License requirements

The official licensing documentation identifies CE as MIT-licensed and EE as separately licensed. The repository root license lists exceptions, including EE, documentation, and third-party components. A Free subscription does not prove that the installed package is CE.

### Allowed implementation route

- Create original hook/policy/UI code and modify MIT-covered CE code as needed. MIT permits modification and distribution, including commercial distribution, with the required copyright and permission notices.
- Preserve the relevant MIT notices when copying or distributing substantial MIT-covered code.
- Prefer an implementation based on CE/MIT-covered code. Do not copy proprietary EE backend functionality, remove license checks, unlock paid features, or assume all files inside an EE installation are MIT.
- Independently implementing a new feature is distinct from copying or unlocking proprietary implementation. Do not rely on EE-only mechanisms to meet the Free requirement.
- Inspect licenses for GitLab Shell, Gitaly, packaging, dependencies, and other modified components at their exact tags. The Rails root license does not establish every component's license.
- Link to GitLab documentation rather than copying substantial passages. If adapting documentation, assess its CC BY-SA 4.0 obligations separately.
- Identify the product as an independent extension; do not imply official GitLab endorsement or trademark permission.

### EE caution

The reviewed EE license text imposes additional production, modification, ownership, and distribution conditions on EE-covered code; development/testing permissions are not unrestricted production/distribution permissions. Do not infer rights from the repository page's generic MIT badge. Read the actual files at the target tag and applicable subscription terms. If a required change is EE-covered, document the issue and obtain qualified review before shipping that component; continue the independent CE-compatible work.

Produce `LICENSE`, `THIRD_PARTY_NOTICES.md`, dependency inventory, and `docs/license-review.md`. Include source tags, license paths, component scope, copied/adapted code, and internal-use versus distribution assumptions. Do not claim a legal opinion or blanket clearance for every EE deployment.

## 4. Policy semantics

Use stable GitLab project/user/group IDs, not usernames, commit-author emails, or client headers. Resolve authenticated identity through verified server mechanisms. Bound group membership caches and revoke access promptly when membership changes.

For enabled projects, default deny. Existing GitLab authorization AND the extension's authorization must both allow an operation. Never elevate a user above native GitLab permissions.

Define three operations:

- `discover`: reveal the path/name in listings.
- `read`: return file bytes and allowed metadata; implies discover.
- `write`: create, modify, delete, or rename; requires read and discover for that path in v1.

Use exact file selectors and directory-prefix selectors in v1, with case-sensitive Git path matching. A directory rule applies to descendants. The most-specific matching selector wins for each operation; within equal specificity, explicit deny wins and otherwise any matching principal grant allows. No match means deny. Reject invalid/ambiguous rules. Lock these semantics in tests before adding glob syntax.

Example policy data (proposed schema, NOT built-in GitLab configuration):

```yaml
schema_version: 1
project_id: 123
default: deny
rules:
  - directory: frontend/
    allow:
      discover: {group_ids: [101]}
      read: {group_ids: [101]}
      write: {group_ids: [101]}
  - directory: backend/
    allow:
      discover: {group_ids: [102]}
      read: {group_ids: [102]}
      write: {group_ids: [102]}
  - directory: docs/
    allow:
      discover: {group_ids: [101, 102]}
      read: {group_ids: [101, 102]}
  - file: frontend/security-config.json
    deny:
      discover: {group_ids: [101]}
      read: {group_ids: [101]}
      write: {group_ids: [101]}
```

Keep policies outside the target repository's developer-controlled content, preferably in the extension's database with transactional revisioning. Only instance administrators may change ACLs in v1. Policy changes must invalidate authorization/content caches and generate audit records. Administrative access and any emergency override must be explicit and audited. Host administrators and authorized instance administrators are trusted; this cannot protect against an administrator with storage access.

## 5. Confidentiality architecture

Build a shared policy evaluator used by backend enforcement and write hooks. Prefer GitLab's existing language/framework for native patches; avoid an extra service unless justified. Any separate policy service requires authenticated communication, bounded timeouts, and fail-closed behavior.

For path-restricted principals:

1. Deny canonical Git clone/fetch over SSH and HTTPS, including direct object requests and protocol variants. Do not rely solely on hiding clone buttons.
2. Deny push until a separately verified write path is available; v1 can provide controlled web/API edits only.
3. Expose only an allowlisted file browser and controlled single/multi-file mutation endpoints. A native UI integration is preferred, but every backend path must enforce policy independently.
4. Deny all other source-bearing routes until proved safe. This includes archives, exports, forks, mirrors, raw/object-ID endpoints, blame/history, diffs/patches, comparisons, search, GraphQL, Web IDE, cached MR diffs, notifications, source previews, LFS, snippets, and code intelligence/AI integrations. Write a concrete endpoint inventory for the installed version.
5. Prevent restricted users from scheduling/running/editing arbitrary CI jobs that obtain the full repository or privileged credentials. Treat runner workspaces, artifacts, logs, caches, packages, deployment output, and job-token access as separate possible disclosure paths. Deny unsafe access in v1 rather than trusting caller-controlled CI scripts.
6. Cover PAT/OAuth/session identities and alternative deploy/job/bot credentials. An unknown or unmapped identity must not bypass ACLs. Repository-wide credentials remain available only to explicitly trusted operators and isolated automation.

The one-project constraint is preserved, but ordinary Git workflows for read-restricted users change. Document this prominently in product behavior and installation requirements. Fully trusted users may retain normal Git workflows under native permissions plus the write policy.

## 6. History, objects, and metadata

Current path checks alone are insufficient. A file may previously have lived under a forbidden directory, have been copied into an allowed directory, or share its blob with restricted content.

For v1, serve only an explicitly selected current ref through path-addressed operations. Deny arbitrary commit/blob retrieval and history traversal for restricted principals. Resolve and pin the ref server-side for the authorization/read transaction. Do not return repository-wide commit messages, changed-path lists, filenames, counts, or generated previews that reveal forbidden data.

Define whether trusted editors may deliberately publish restricted content into an allowed path. Path ACLs alone are not data-loss prevention: copies in source, comments, issue text, artifacts, and screenshots need separate handling. Preserve confidentiality by denying unaudited source-bearing features, not by claiming to detect arbitrary copied secrets.

Store user/policy/project/ref context in cache keys; prevent privileged cached responses from being served to restricted users. Avoid serving reusable unscoped signed download URLs. Treat indexes, cached diffs, email/webhook payloads, and background jobs as disclosure channels. Existing clones/downloads cannot be revoked retroactively.

## 7. Write enforcement

Build a pre-receive component using authenticated server identity and supported hook variables. Never trust commit author/committer identity as the actor. Install through the documented Gitaly mechanism on every required storage node; do not overwrite GitLab's own hooks.

- Check every updated ref and relevant newly introduced commit, not just the old-tip/new-tip net diff. Reject unauthorized intermediate modifications even if reverted later.
- Handle root commits, new branches, merges, force updates, annotated tags, nonstandard refs, deletions, and multi-ref pushes. Resolve tags safely. Define allowed ref namespaces and deny unsupported ref manipulation.
- Evaluate both source and destination of renames. Handle copies as destination additions; validate deletion, file modes, symlinks, gitlinks, and directory/file transitions.
- Parse Git output with NUL delimiters and safe argument passing. Do not interpolate paths into shell commands or dereference symlink targets.
- Use Git quarantine correctly, avoid mutating incoming objects, and bound traversal costs. Reject when limits prevent a complete decision.
- Distinguish ref deletion permission from path-change permission. Retain GitLab branch/tag protections.
- Verify actual hook coverage for API commits, Web IDE, merge/squash/rebase, bots, and background actions on the installed tag. Add backend checks for uncovered mutation paths and recheck the eventual merge actor and full applied changes.
- Return useful `GL-HOOK-ERR:` messages without exposing forbidden path names to principals who cannot discover them.

For web/API edits use expected revision checks to avoid lost updates. Authorize all actions atomically before committing. No partial mutation on denial. Do not use an unrestricted bot as a way to bypass the acting user's ACL.

## 8. Administration and operation

Provide project selection, user/group selectors, folder/file selectors, policy preview, validation, effective-permission explanation, revision history, and audit search. Explain rule precedence in the UI. Audit records must not disclose forbidden content to ordinary users.

Enabled protected projects fail closed on missing policy, policy service failure, cache inconsistency, unknown identity, or unsupported access route. Disabled unrelated projects must retain native behavior. Feature toggles must not silently turn an enabled protected project into unrestricted access.

Package a reproducible, version-pinned build and patch series. Include backup, staging install, migration, rollback, hook uninstall, and upgrade compatibility checks. A rollback of enforcement must lock protected projects or restrict them to trusted users first; uninstall must not accidentally expose code. Never auto-apply source patches across unsupported GitLab versions.

## 9. Tests and acceptance criteria

Use a disposable GitLab instance at the exact target version, real SSH/HTTPS clients, browser sessions, API clients, and representative credentials. Unit tests alone do not prove enforcement.

Required negative tests include direct forbidden paths, encoded/double-encoded separators, dot segments, newline/tab filenames, case and Unicode edge cases, blob IDs, old commits, moved files, search, GraphQL batching, archives, export/fork paths, MR diffs, LFS downloads, and alternate token identities. Unsupported routes must deny access.

Test unauthorized intermediate changes followed by reverts, rename into/out of forbidden directories, new branches/tags, merge parents, squash/rebase, multi-ref pushes, spoofed commit authors, symlinks, and policy modification attempts.

Test cache isolation between administrator and restricted user, revocation, group membership removal, policy update races, worker/service outages, direct backend reachability, and upgrade/rollback paths. Demonstrate that CI cannot be used to exfiltrate restricted source.

Acceptance:

1. Only one GitLab project and canonical repository exist for the application.
2. No paid feature or license bypass is used.
3. User A can discover/read/edit permitted paths but cannot discover/read restricted paths through any enabled surface.
4. Forbidden mutations fail before ref updates; native branch protections still apply.
5. Restricted clone/fetch is denied; the alternative file workflow works and its limitations are documented.
6. Every enabled endpoint is audited and tested; unaudited source-bearing endpoints are denied.
7. Edition/version/license findings and deployment limits are recorded. No claim of production readiness without end-to-end evidence.

## 10. Work sequence and deliverables

Work sequentially through discovery/license audit, threat model and endpoint matrix, policy evaluator, write hook, native read-route enforcement, administration UI, adversarial integration tests, and packaging. Do not stop after implementing write controls and call the full requirement complete.

Deliver:

- Original extension source and tests; exact GitLab patch series where required.
- `README.md` with supported version/edition and changed developer workflow.
- `docs/version-audit.md`, `docs/feasibility.md`, `docs/license-review.md`.
- `docs/threat-model.md` and `docs/endpoint-coverage.md` identifying enforced/denied/unresolved routes.
- Policy schema, examples, administrator guide, and effective-permission tests.
- Installation, backup, rollback/uninstall, and version-upgrade instructions.
- `LICENSE`, `THIRD_PARTY_NOTICES.md`, dependency inventory, and test evidence.

If access to the installed version is unavailable, complete the reusable policy/hook code and a reproducible development scaffold where possible, clearly identify unverified native integrations, and list the precise missing inputs. Do not modify production or represent a scaffold as a complete security boundary.

## Official sources to read and verify at the target version

Documentation reviewed for this brief; architecture above is a proposed design, not an official GitLab implementation recipe.

- Extending GitLab: https://docs.gitlab.com/api/get_started/get_started_extending/
- Integration development: https://docs.gitlab.com/development/integrations/
- Authorization development: https://docs.gitlab.com/development/permissions/
- Server hooks: https://docs.gitlab.com/administration/server_hooks/
- GitLab Shell development: https://docs.gitlab.com/development/gitlab_shell/
- Gitaly development: https://docs.gitlab.com/development/gitaly/
- Internal API (for source maintainers, not a public third-party contract): https://docs.gitlab.com/development/internal_api/
- Repository files API: https://docs.gitlab.com/api/repository_files/
- Roles and permissions: https://docs.gitlab.com/user/permissions/
- GitLab licensing: https://docs.gitlab.com/development/licensing/
- Root license: https://gitlab.com/gitlab-org/gitlab/-/blob/master/LICENSE
- EE license: https://gitlab.com/gitlab-org/gitlab/-/blob/master/ee/LICENSE
- Package licenses: https://docs.gitlab.com/administration/package_information/licensing/

The root license text and a commit-specific EE license were retrievable during research; the latest EE license body was not exposed by the web renderer. The agent must verify the actual EE license at the installed tag before relying on EE-specific rights.
