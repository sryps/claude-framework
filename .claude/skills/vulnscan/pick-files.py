#!/usr/bin/env python3
"""Pick N random source files from a directory tree.

Prints paths, one per line, on stdout. LLMs cannot do real randomness;
this script is the entropy source for the vuln scan so the same model
doesn't keep gravitating to the same "interesting-looking" files.

Language-agnostic: scans a broad set of source extensions by default and
prunes the usual build/dependency directories. Override with --ext.

Usage:
  pick-files.py --count 8 [--seed 42] [--root .] [--ext py,ts,go] [--include-tests]
"""

import argparse
import os
import random
import subprocess
import sys

# Default source extensions across common languages.
DEFAULT_EXTS = (
    "py pyi "
    "js jsx mjs cjs ts tsx "
    "rs go java kt kts scala "
    "rb php "
    "c h cc cpp cxx hpp hh "
    "cs swift m mm "
    "ex exs erl "
    "sh bash zsh "
    "sql graphql proto "
    "vue svelte"
).split()

# Directories that never contain first-party source worth auditing.
PRUNE_DIRS = {
    ".git", ".hg", ".svn",
    "node_modules", "bower_components",
    "target", "dist", "build", "out", "bin", "obj",
    "vendor", "deps", "_build",
    "venv", ".venv", "env", ".env", "virtualenv",
    "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox",
    ".next", ".nuxt", ".svelte-kit", ".cache",
    "coverage", ".gradle", ".idea", ".vscode",
    "Pods", "DerivedData",
    ".terraform", "site-packages",
}

# Path components / filename patterns that mark test code (excluded by default).
TEST_DIR_NAMES = {"tests", "test", "spec", "specs", "__tests__", "e2e", "fixtures"}


def is_test_file(rel_path: str, ext: str) -> bool:
    parts = rel_path.replace("\\", "/").split("/")
    if any(p in TEST_DIR_NAMES for p in parts):
        return True
    fname = parts[-1]
    base = fname[: -(len(ext) + 1)] if fname.endswith("." + ext) else fname
    if base.startswith("test_") or base.startswith("test-"):
        return True
    for suffix in ("_test", "_tests", ".test", ".spec", "_spec"):
        if base.endswith(suffix):
            return True
    return False


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--count", type=int, default=8, help="number of files to pick")
    p.add_argument("--seed", type=int, default=None, help="seed for reproducibility")
    p.add_argument("--root", default=".", help="root dir to search (default: cwd / repo root)")
    p.add_argument(
        "--ext",
        default=None,
        help="comma- or space-separated extensions to scan (default: a broad source set)",
    )
    p.add_argument(
        "--include-tests",
        action="store_true",
        help="include test files (default: excluded)",
    )
    args = p.parse_args()

    # Resolve root: absolute as-is, else relative to git toplevel when available,
    # otherwise relative to cwd.
    if os.path.isabs(args.root):
        root = args.root
    else:
        try:
            toplevel = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
            root = os.path.join(toplevel, args.root)
        except (subprocess.CalledProcessError, FileNotFoundError):
            root = os.path.abspath(args.root)

    if not os.path.isdir(root):
        print(f"error: root not a directory: {root}", file=sys.stderr)
        return 2

    if args.ext:
        exts = [e.strip().lstrip(".") for e in args.ext.replace(",", " ").split() if e.strip()]
    else:
        exts = DEFAULT_EXTS
    exts_set = set(exts)

    candidates: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in PRUNE_DIRS and not d.startswith(".")]
        for fname in filenames:
            dot = fname.rfind(".")
            if dot < 0:
                continue
            ext = fname[dot + 1 :]
            if ext not in exts_set:
                continue
            full = os.path.join(dirpath, fname)
            rel = os.path.relpath(full, root)
            if not args.include_tests and is_test_file(rel, ext):
                continue
            candidates.append(full)

    if not candidates:
        print(f"error: no candidate files found under {root}", file=sys.stderr)
        return 1

    rng = random.Random(args.seed)
    rng.shuffle(candidates)
    for path in candidates[: args.count]:
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
