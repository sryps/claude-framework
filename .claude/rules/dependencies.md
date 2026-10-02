---
paths:
  - "**/package.json"
  - "**/Cargo.toml"
  - "**/go.mod"
  - "**/pyproject.toml"
  - "**/requirements*.txt"
  - "**/Pipfile"
  - "**/Gemfile"
  - "**/composer.json"
  - "**/Podfile"
  - "**/pubspec.yaml"
  - "**/build.gradle*"
  - "**/pom.xml"
  - "**/Package.swift"
  - "**/deno.json"
---

# Dependencies and supply chain

A new dependency is Yellow tier. Run the `add-dependency` skill for each new package.

## Before you add a package

- Check that the standard library or an existing dependency cannot do the job.
- Check the package: maintained (a release or commit in the last 12 months), real adoption, known maintainers, no open critical advisories, a license that fits the project (no AGPL or unknown license without a human decision).
- Check the exact name for typosquats. Check the publisher matches the official project.
- Prefer packages with few transitive dependencies.
- Record the reason in the PR under `Security-Review:`.

## Install

- Add packages with the package manager (`npm install`, `pnpm add`, `uv add`, `cargo add`, `go get`). Hooks block hand edits to lockfiles.
- Commit the lockfile with the manifest change.
- CI installs from the lockfile only: `npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`, `cargo build --locked`, `go mod download` with `go.sum`.
- Turn off install scripts where the ecosystem allows it, or review them (`npm config set ignore-scripts true` with an allowlist).
- MUST NOT install global packages in an agent run. MUST NOT pipe a download into a shell.

## Versions

- Pin exact versions or use the lockfile as the pin. Avoid `latest` and open ranges in applications.
- Update with a bot (Dependabot or Renovate). Review changelogs for major versions.
- Expo projects: align native packages with `npx expo install`.

## Scanning

- Run the ecosystem audit: `npm audit`, `pnpm audit`, `pip-audit`, `cargo audit` or `cargo deny`, `govulncheck`, `osv-scanner`.
- CI fails on high and critical advisories that have a fix.
- Generate an SBOM for releases.

## Vendored and copied code

- Copied code keeps its license header and a link to the source.
- Vendored code updates through a script, not by hand.

## Done means

- [ ] Each new package has a recorded reason and passed the checks above.
- [ ] The lockfile changed through the package manager.
- [ ] The audit shows no new high or critical advisory.
