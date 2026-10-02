---
name: threat-model
description: STRIDE threat model for a feature, service, or whole app. Writes or updates docs/THREAT_MODEL.md and lists the security tests the change needs. Use before Yellow work (auth, crypto, permissions, migrations, infra, new external input) or when the user asks for a threat model.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# /threat-model: STRIDE pass

**Arguments:** `$ARGUMENTS` (the feature, service, or path to model; empty means the whole repo)

The output is a file and a list of tests. Keep it short and specific to this code. A generic list of threats has no value.

## 1. Scope

1. Name the thing you model in one line.
2. Read the code for it. Find entry points with Grep: route definitions, handlers, CLI argument parsing, message consumers, file readers, deep links, webhooks.
3. Read `docs/THREAT_MODEL.md` if it exists. You update it. You do not replace it.

## 2. Model

Record these in the file:

- **Assets**: data and capabilities an attacker wants. Examples: user PII, session tokens, payment state, admin actions, API keys held by the server.
- **Actors**: anonymous user, signed-in user, other tenant, admin, service account, CI, a compromised dependency.
- **Trust boundaries**: each point where data moves between actors or processes. Examples: browser to API, API to database, app to third-party API, mobile app to backend, CI to registry.
- **Data flows**: one line per flow. `source -> boundary -> sink: data`.

## 3. STRIDE per boundary

For each trust boundary, ask each question. Write a threat only when it applies to this code.

| Letter | Question |
|---|---|
| S, Spoofing | Can someone act as another user or service? Weak auth, missing signature check on a webhook, trusting a client-sent user ID. |
| T, Tampering | Can someone change data in transit or at rest? Missing integrity checks, mass assignment, unsigned tokens, client-side price. |
| R, Repudiation | Can someone deny an action? Missing audit log for admin and money actions. |
| I, Information disclosure | Can someone read data they should not? IDOR, verbose errors, logs with tokens, missing RLS, public buckets. |
| D, Denial of service | Can someone exhaust a resource? No rate limit, unbounded pagination, regex backtracking, large uploads. |
| E, Elevation of privilege | Can someone gain a role? Role in a client claim, missing authz on one route, SQL or command injection, path traversal. |

For each threat, rate likelihood and impact as Low, Medium, or High.

## 4. Mitigations

For each threat:
- Name the mitigation in the code, with `file:line`, if it exists.
- Else name the change you will make.
- Else record it as residual risk with the reason.

## 5. Write the file

Use this structure for `docs/THREAT_MODEL.md` (create `docs/` if needed). If the repo has `templates/THREAT_MODEL.md` or an existing file, follow its structure.

```markdown
# Threat model: <system>

Last updated: <YYYY-MM-DD>, <branch or PR>

## Assets
## Actors
## Trust boundaries
## Data flows
## Threats
| ID | Boundary | STRIDE | Threat | Likelihood | Impact | Mitigation | Status |
|---|---|---|---|---|---|---|---|
| T1 | browser -> API | E | ... | M | H | `src/api/orders.ts:42` ownership check | mitigated |

## Residual risk
## Required tests
```

Give each threat a stable ID. Keep IDs across updates.

## 6. Required tests

List one test per mitigated threat that the change touches. Each test names the attack it proves fails:

- `T1: user B gets 404 on GET /orders/<A's id>`
- `T4: login returns the same error and timing for unknown user and wrong password`

The `feature` skill adds these tests before the code.

## Rules

- Never paste secrets, tokens, or real user data into the file.
- A threat with status `open` and impact High goes under Blocked or into the PR Security-Review section.
