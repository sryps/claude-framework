---
paths:
  - ".github/**"
  - ".gitlab-ci.yml"
  - ".circleci/**"
  - "Jenkinsfile"
  - "azure-pipelines.yml"
  - "bitbucket-pipelines.yml"
  - ".buildkite/**"
  - "codemagic.yaml"
  - "fastlane/**"
---

# CI and CD

Every file here is Yellow tier. Running a deploy, a release, or a workflow dispatch is Red tier.

## Workflow hardening (GitHub Actions, and the same idea elsewhere)

- Set `permissions: contents: read` at the top. Grant more per job, only what the job needs.
- Pin every third-party action to a full commit SHA, with the version in a comment. First-party `actions/*` also get pinned.
- MUST NOT use `pull_request_target` with a checkout of the PR head. MUST NOT expose secrets to workflows that run fork code.
- Never interpolate untrusted input (`github.event.*.title`, `body`, `head_ref`, branch names) into `run:` directly. Pass it through `env:` and quote it.
- Set `persist-credentials: false` on `actions/checkout` unless the job pushes.
- Use OIDC to cloud providers instead of long-lived keys.
- Set `timeout-minutes` on every job.
- Self-hosted runners never run jobs from forks.

## Required checks

- Lint, typecheck, unit tests, and build on every PR.
- Secret scan (gitleaks), SAST (semgrep or CodeQL), and dependency scan (osv-scanner or the ecosystem audit).
- Dependency review on PRs that change manifests.
- Container scan (trivy) when the repo builds images.
- The templates in `templates/ci/github/` give a starting point.

## Deploys

- Deploys run from CI only, never from a laptop or an agent session.
- Production deploys need a protected environment with required reviewers.
- Build once, promote the same artifact through environments.
- Keep a rollback path for every deploy.

## Branch protection (a human sets this)

- Protect the default branch: required reviews, required status checks, no force push, no deletion.
- Require signed commits if the team uses them.
- CODEOWNERS for auth, migrations, CI, and infra paths.

## Done means

- [ ] Top-level `permissions` is read-only.
- [ ] Every action is pinned by SHA.
- [ ] No untrusted input in `run:` lines.
- [ ] Secret, SAST, and dependency scans run on PRs.
