---
paths:
  - "**/cmd/**"
  - "**/cli/**"
  - "**/bin/**"
  - "**/src/main.rs"
  - "**/main.go"
  - "**/*.sh"
  - "**/Makefile"
  - "**/goreleaser*"
  - "**/.goreleaser*"
---

# Binaries, CLIs, and scripts

Publishing a release, tagging, or pushing an artifact is Red tier. Release config is Yellow.

## Process execution

- Run child processes with an argv array. MUST NOT pass user input through a shell string.
- When a shell is unavoidable, quote every variable and use `--` before user-supplied arguments.
- Resolve the binary path on purpose. Do not trust `PATH` in a privileged context.

## Files

- Create temp files with the safe API (`mkstemp`, `os.CreateTemp`, `tempfile`, `mktemp`). Never a fixed name in `/tmp`.
- Write files atomically: write to a temp file in the same directory, then rename.
- Set file modes on create (`0600` for secrets, `0644` for normal files). Never `0777`.
- Do not follow symlinks when writing into a shared directory.
- Check paths from arguments or archives against the target directory (zip slip).

## Input

- Validate flags and config files with a schema. Fail with a clear message and a non-zero exit code.
- Read secrets from the environment, a file with tight permissions, or the OS keychain. Never from a flag (flags show in `ps` and shell history).

## Output and exit codes

- Exit 0 on success, non-zero on failure. Document the codes.
- Write data to stdout and logs and errors to stderr.
- Support `--help` and `--version`.
- Never print secrets, also not in `--verbose` mode.

## Memory safety

- Prefer memory-safe languages for new binaries.
- C and C++: compile with `-Wall -Wextra -Werror`, sanitizers in CI, and fortify and stack protector flags in release.
- Rust: no `unsafe` without a safety comment. Run `cargo clippy -- -D warnings`.

## Shell scripts

- Start with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Write for bash 3.2 when the script must run on macOS. Avoid GNU-only flags.
- Pass `shellcheck` with no warnings.

## Releases

- Builds are reproducible: pinned toolchain, locked dependencies, no network at build time beyond the lockfile.
- Sign release artifacts (cosign, minisign, GPG, or platform signing). Publish checksums.
- Produce an SBOM (CycloneDX or SPDX) for each release.
- Run the `release-prep` skill. A human runs the release.

## Done means

- [ ] No shell interpolation of input.
- [ ] Safe temp files and atomic writes.
- [ ] Clear exit codes and `--help`.
- [ ] `shellcheck` or the language linter passes.
