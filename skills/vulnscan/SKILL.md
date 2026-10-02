---
name: vulnscan
description: Random-file vulnerability scanner for any code repo. Picks random source files, fans out parallel scout subagents to find exploitable bugs, then deduplicates and runs a devil's-advocate counterpoint pass. Writes findings to .vuln-scan/. Use when the user asks to run a vuln scan, security sweep, or audit pass on a codebase.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# /vulnscan — Random-File Vulnerability Scanner

A language-agnostic security sweep for any repo. One run flows through three
auto-pipelined phases — **scan → consolidate → counterpoint** — and writes the
result to `.vuln-scan/report.md`. The human drives in plain English ("scan this
repo", "focus on auth, 12 scouts", "scan src/handlers/*.ts"); start the scan and
let the pipeline run to the end without asking for approval between phases.

Defaults when unspecified: **8 scouts**, no seed, general focus, root = repo root.

---

## Output layout

Everything goes under `.vuln-scan/` at the repo root. Each run overwrites the
previous one — if they want history, tell them to rename the folder first.

**Always gitignore the output.** Scan reports name exploitable bugs and their
file:line locations — do not commit them. In the scan phase, ensure `.vuln-scan/`
is listed in the repo's `.gitignore` (add the line if missing), so the findings
never get committed.

```
.vuln-scan/
  files.txt                # the files scanned this run, one per line
  scans/
    scan-01-<slug>.md      # one scout's report, OR a single line "NO_VULN_FOUND"
    scan-02-<slug>.md
    ...
  report.md                # deduplicated findings, each with a Counterpoint
```

---

## Phase: scan

1. Create `.vuln-scan/scans/` (clear any stale `scan-*.md` from a prior run first).
   Ensure `.vuln-scan/` is in the repo's `.gitignore` — append the line if it isn't
   already there (create `.gitignore` if the repo has none). The scan output must
   never be committed.

2. Pick files to scan:
   - If the human named files/globs → use those (expand globs with Glob).
   - Otherwise → `python3 <skill-base-dir>/pick-files.py --count <count> [--seed <seed>] [--root <path>] [--ext <list>]`.
     `<skill-base-dir>` is the base directory Claude Code states when it loads this
     skill. `pick-files.py` sits next to this SKILL.md, for a plugin or a user install.
     The script picks random non-test source files and prunes build/dependency
     dirs. Pass `--ext` if the human names a language (e.g. `--ext py`).
   - Write the chosen paths to `.vuln-scan/files.txt`.

3. **Spawn scouts in parallel.** ONE message containing N parallel `Agent` calls,
   `subagent_type: general-purpose`. Each scout's prompt is the **SCOUT PROMPT**
   below with substitutions:
   - `<TARGET_FILE>` → the assigned file path
   - `<FOCUS>` → the focus statement, or "general"
   - `<OUTPUT_PATH>` → `.vuln-scan/scans/scan-MM-<slug>.md` (slug = basename without extension, MM = zero-padded index)

4. After all scouts return, keep every scan file (including `NO_VULN_FOUND` ones).
   Print a one-line-per-scout summary. **Auto-trigger consolidate immediately** —
   do not ask the human. If a scout produced no file at all, note it in the summary.

## Phase: consolidate (auto, runs after scan)

1. Confirm `.vuln-scan/scans/scan-*.md` exists; if not, say so and stop.

2. Spawn ONE consolidator subagent (`subagent_type: general-purpose`) with the
   **CONSOLIDATOR PROMPT** below, substituting:
   - `<OUTPUT_PATH>` → `.vuln-scan/report.md`
   - `<SCANS>` → every scan file's full text, separated by `---FILE: scan-MM-<slug>.md---` markers

3. After return, **auto-trigger counterpoint.**

## Phase: counterpoint (auto, runs after consolidate)

Appends a `### Counterpoint` section to each finding making the strongest
reasonable argument for why it might NOT be real, or might be lower-severity than
scored. The reader uses these to spend remediation budget on the findings that
survive devil's-advocate review.

1. Require `.vuln-scan/report.md`; if missing, say so and stop.

2. Spawn ONE counterpoint subagent with the **COUNTERPOINT PROMPT** below,
   substituting `<FILE_PATH>` → `.vuln-scan/report.md`.

3. After return, print the final summary: unique-finding count, severity mix, and
   a one-line-per-finding listing with title. The pipeline ends here.

---

## Subagent etiquette

- Scouts in parallel, always — single message, N tool calls.
- Never inline scout reasoning into chat. Scouts Write their own files; you relay counts only.
- Scouts do not read each other's reports.
- Phases auto-pipeline (scan → consolidate → counterpoint). Do not stop between
  phases to ask the human; only stop at the end or on a hard error.
- Talk to the human in plain English. Never ask them to remember a flag.

---

## SCOUT PROMPT

```
You are doing a security audit of a code repository. Find exploitable vulnerabilities starting from the file: <TARGET_FILE>

Instructions:
- Read <TARGET_FILE> first, then follow its imports/dependencies to understand the full context.
- Look for real, exploitable vulnerabilities — anything where you can describe a concrete attack scenario. Examples: injection (SQL/command/template), auth/authorization bypass, missing signature/token verification, path traversal, SSRF, insecure deserialization, secrets in code, broken access control, unsafe use of untrusted input, race conditions with security impact, cryptographic misuse.
- Do NOT report: missing rate limiting, missing CSRF tokens (unless you can show concrete impact), dependency version bumps, style issues, or theoretical issues without a concrete exploit path.
- If <FOCUS> is something other than "general", prioritize findings matching that theme, but still flag any CRITICAL/HIGH that fall outside it.
- Pick the single most serious real vulnerability you can substantiate. Do not produce a list.
- If you find one, write your report to <OUTPUT_PATH> using the Write tool, in the format below.
- If nothing exploitable is found, write to <OUTPUT_PATH> with exactly one line: NO_VULN_FOUND

Report format (write this to <OUTPUT_PATH>):

# Vulnerability Report

## Severity: [CRITICAL/HIGH/MEDIUM/LOW]

## Title
<one-line summary>

## Affected File(s)
<list of files involved, with line numbers when pointing at specific calls>

## Description
<what the vulnerability is, plain English>

## Exploit Scenario
<step-by-step how an attacker would exploit this>

## Suggested Fix
<how to fix it — shape only, do not write the patch>

## Starting Point
This analysis began from: <TARGET_FILE>

Return one line to the parent: "<severity> — <title>" or "NO_VULN_FOUND".

--- FOCUS ---
<FOCUS>
```

## CONSOLIDATOR PROMPT

```
You are the consolidator for a vulnerability scan. Several scouts ran independently; each scout's file is either a single vulnerability report or the string NO_VULN_FOUND. Produce one deduplicated list of unique vulnerabilities.

Inputs:
- Output: <OUTPUT_PATH>
- Scan reports: in the SCANS block below.

Method:
1. Skip every NO_VULN_FOUND report.
2. Read the rest. Group duplicates — same underlying bug = duplicate, even if location/wording differs. Dedup key is the bug itself (function/module + class of attack), not file:line.
3. For each unique bug, merge the best version: clearest description, all cited locations, all exploit angles. Preserve every contributing scout under Source Reports.
4. Order the unique bugs severity-sorted descending (CRITICAL > HIGH > MEDIUM > LOW), ties alphabetical by title. Do NOT assign finding IDs — each scan overwrites the last and samples different files, so a persistent-looking identifier is misleading; the title is the finding's handle.
5. Write <OUTPUT_PATH>:

# Vulnerability scan — consolidated findings

- Scouts: N
- Reports with a vuln: X
- Unique vulnerabilities: Y
- Severity mix: ...

## <Title>

### Severity: [CRITICAL/HIGH/MEDIUM/LOW]

### Source Reports
- scan-03-foo.md
- scan-07-bar.md

### Affected Files
- path/to/file:LINE — what it does
- ...

### Description
<merged plain-English description>

### Impact
<merged impact statement — what breaks and for whom>

### Exploit Scenario
<merged step-by-step. If scouts gave different angles on the same bug, list them as Scenario 1, Scenario 2, ...>

### Suggested Fix
<merged, shape only>

## <Next Title>

...

Return one line: "report.md: Y unique vulns from X reports across N scouts"

Constraints:
- Never drop a finding silently. Every discarded duplicate is listed under Source Reports of the surviving finding.
- Never invent. Inputs are scout reports only.
- Take the higher severity when scouts disagreed; note both in the description.
- If every report is NO_VULN_FOUND, still write <OUTPUT_PATH> with the header and "No vulnerabilities found." and return accordingly.
- Exactly one output file.

--- SCANS ---
<SCANS>
```

## COUNTERPOINT PROMPT

```
You are the counterpoint reviewer for a vulnerability scan. The consolidator has produced a set of findings; an experienced engineer who knows this codebase wants a "devil's advocate" pass before spending remediation budget on each one.

For each finding in <FILE_PATH>, your job is to argue against it. Provide the strongest reasonable counter-argument for why this finding might NOT be a real exploitable vulnerability, OR why its severity should be lowered. Be adversarial in the *defending the code* direction: a security finding is innocent until proven guilty; what is the most charitable read of the existing code that makes the bug claim wrong, unreachable, or trivial?

You are NOT a verifier — do not render CONFIRMED/REFUTED. Output is appended to each finding as a "### Counterpoint" section. The reader uses it to decide whether the finding is worth fixing.

Inputs:
- Consolidated findings file: <FILE_PATH> (read this first)
- The codebase: open any cited file and adjacent code to check for mitigating context

Output: edit <FILE_PATH> in-place, appending a `### Counterpoint` section to each finding after its existing `### Suggested Fix`. Do NOT modify anything else in the file. Section format:

### Counterpoint
<2-6 sentence argument for why this might not be real or not as serious as scored. Cite specific code, types, callers, or invariants if you find them. If you cannot find a credible counter-argument, say so explicitly in one sentence ("No credible counter-argument found — the bug appears to hold as described") — that itself is useful signal.>

Method for each finding:
1. Read the cited files and enough surrounding context to understand what a *defender* would say.
2. Look for: upstream gates that make the exploit unreachable from outside; type/state-machine guarantees that prevent the bug; validation or middleware that already exists at a different layer; operational mitigations that constrain the window; cost-of-exploit arguments (attacker needs credentials AND timing AND a second compromised actor); severity-lowering arguments (worst case is recoverable, actual damage is bounded, etc.).
3. Synthesize the strongest version of the defense. Don't strawman.
4. Be honest: if no credible counter-argument exists, say so in one sentence.

Constraints:
- The counterpoint is *one paragraph per finding* (2-6 sentences).
- Cite file:line when the counter-argument depends on specific code.
- Do not add new findings. Do not modify existing finding bodies. Only append `### Counterpoint`.
- Do not invent code that isn't there. If you can't find the upstream gate, say "I could not find an upstream gate that prevents this" rather than fabricating one.
- Return one line: "counterpoints appended to N findings" where N is the count you appended to.
```
