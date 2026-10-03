---
name: add-dependency
description: Evaluate a third-party package before you add it, then add it with the package manager only and record the reason in the PR. Checks need, maintenance, license, advisories, install scripts, typosquatting, and size. Use whenever you are about to add or upgrade a dependency in any ecosystem.
allowed-tools: Bash, Read, Edit, Grep, Glob, WebFetch
---

# /add-dependency: vet, add, record

**Arguments:** `$ARGUMENTS` (package name, and the ecosystem if unclear)

Every dependency is code you ship and do not review. Add one only when it earns its place. Read `.claude/rules/dependencies.md` first.

## 1. Do you need it?

- Can the standard library or a dependency already in the project do this? Check the manifest and lockfile first.
- Is the feature fewer than about 50 lines to write and test yourself? Then write it, unless it is crypto, parsing of a complex format, or a protocol.
- Never add a package for crypto that the platform already provides.

If you do not need it, stop. Record the decision.

## 2. Check the exact name

Typosquats copy popular names. Confirm the exact name and publisher on the registry page:
- npm: `npm view <pkg> name version repository.url maintainers time.modified`
- PyPI: `pip index versions <pkg>` and the project page
- crates.io: `cargo search <pkg> --limit 3`
- Go: the module path matches the real repository

Reject a name that differs by one character from a popular package, or that has a recent first publish and few downloads.

## 3. Health

Reject or flag the package when any of these is true:
- Last release over 2 years ago with open security issues.
- One maintainer and a large blast radius (runs at install time or in auth paths).
- Weekly downloads very low for its category, with no known backer.
- Source repository missing, archived, or does not match the published package.

## 4. License

Allowed by default: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, 0BSD, Unlicense, MPL-2.0 (file-level).
Ask (attended) or record under Blocked (autonomous): GPL, AGPL, LGPL, SSPL, BUSL, no license, custom terms.
The project may set its own list in `CLAUDE.md`. That list wins.

## 5. Advisories

Run the scanner for the ecosystem after you add it, and before you commit:

| Ecosystem | Command |
|---|---|
| npm, pnpm, yarn | `npm audit --omit=dev` (or `pnpm audit --prod`, `yarn npm audit`) |
| Python | `pip-audit` or `uv pip audit` if available |
| Rust | `cargo audit` and `cargo deny check` if configured |
| Go | `govulncheck ./...` |
| Any | `osv-scanner --lockfile=<lockfile>` |

A HIGH or CRITICAL advisory with a fix: use the fixed version. Without a fix: do not add it.

## 6. Install scripts

- npm: check `npm view <pkg> scripts`. A `preinstall`, `install`, or `postinstall` script is a flag. Record why it is acceptable, or reject.
- Python: prefer packages with wheels. An sdist runs `setup.py` at install.

## 7. Size and scope

- Check install size and transitive count: `npm view <pkg> dist.unpackedSize dependencies`, or `cargo tree -p <pkg>` after adding.
- For frontend code, check the bundle cost. Prefer a smaller package or a deep import.
- Add dev-only tools as dev dependencies.

## 8. Add it

Use the package manager. Never edit a lockfile by hand. A hook warns when you do.

```bash
npm install <pkg>@<version>        # or pnpm add, yarn add, bun add
uv add <pkg>                       # or poetry add, pip install + requirements pin
cargo add <pkg>@<version>
go get <module>@<version>
```

Pin exact versions in apps. Use ranges only in libraries. Commit the manifest and the lockfile together.

## 9. Record

Add to the PR body:

```markdown
## Dependencies
- <pkg>@<version> (<license>): <why it is needed>. Alternatives: <stdlib or other package and why not>. Audit: clean. Install scripts: none.
```
