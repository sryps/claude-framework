---
name: release-prep
description: Prepare a release for a human to ship. Changelog, version bump, SBOM, and a release checklist. Never runs the release, deploy, publish, or store submit.
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# /release-prep: get a release ready, then stop

**Arguments:** `$ARGUMENTS` (target version or bump type: major, minor, patch)

You prepare. A human ships. Release, deploy, publish, tag push, and store submit are Red tier. Hooks block them. Do not look for another way to run them.

## 1. Find the last release

```bash
git describe --tags --abbrev=0 2>/dev/null || echo "no tags"
git log "$(git describe --tags --abbrev=0 2>/dev/null)"..HEAD --oneline 2>/dev/null || git log --oneline
```

## 2. Pick the version

- Use the argument if given.
- Else apply SemVer to the commits since the last tag: a breaking change gives major, `feat:` gives minor, other changes give patch.
- Mobile apps: bump the marketing version and the build number (`app.json`, `Info.plist`, `build.gradle`) the way the repo does.

## 3. Bump the version

Edit the version in the files the repo uses: `package.json`, `Cargo.toml`, `pyproject.toml`, `app.json`, `version.go`, and similar. Use the tool when one exists (`npm version <v> --no-git-tag-version`, `cargo set-version` if installed). Do not create a git tag.

## 4. Changelog

Update `CHANGELOG.md` in Keep a Changelog form:

```markdown
## [<version>] - <YYYY-MM-DD>
### Added
### Changed
### Fixed
### Security
```

Write each line for a user, not for a developer. Put each security fix under Security.

## 5. SBOM and checks

Run what is installed. Skip with a note what is not.

```bash
syft dir:. -o cyclonedx-json > sbom.cdx.json          # or: npx @cyclonedx/cyclonedx-npm --output-file sbom.cdx.json
osv-scanner --recursive .                              # advisories
gitleaks dir . --no-banner --redact                    # secrets
```

Run the full test suite and the production build command locally. A failure stops the release prep. Record it.

## 6. Checklist for the human

Write `RELEASE_CHECKLIST.md` (or the PR body) with:

```markdown
## Release <version>
- [ ] CI green on the release PR
- [ ] Changelog reviewed
- [ ] SBOM attached: sbom.cdx.json
- [ ] No HIGH or CRITICAL advisories open (osv-scanner output)
- [ ] Migrations in this release: <list or none>, rollback plan: <link>
- [ ] Feature flags to flip: <list or none>
- [ ] Commands for the human to run:
  - <the exact tag, publish, deploy, or submit commands for this repo>
- [ ] Post-release check: <health URL, dashboard, smoke test>
```

## 7. PR

Commit on a branch `release/<version>-prep` or `chore/release-<version>`. Open a PR. Stop.
