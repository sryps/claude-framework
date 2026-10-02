# {{Feature name}}

Status: draft | agreed | changed
Owner: {{who decides open questions}}

## Goal

{{One or two sentences: the problem, for whom, and how we know it is solved.}}

## Users and permissions

| Role | May | May not |
|---|---|---|
| {{role}} | {{actions}} | {{actions}} |

## Acceptance criteria

Each criterion can pass or fail in a test. Keep the IDs stable: tests and the PR refer to them.

- AC-1: Given {{state}}, when {{action}}, then {{observable result}}.
- AC-2: Given {{state}}, when {{action}}, then {{observable result}}.

## Edge cases

Decide each one, or mark it out of scope.

- Empty input, zero, and maximum values: {{behavior}}
- Invalid or malicious input: {{behavior}}
- Not signed in, wrong user, wrong role: {{behavior}}
- Network or dependency failure, timeout, retry: {{behavior}}
- Concurrent edits or double submit: {{behavior}}
- Existing data (migration, old clients): {{behavior}}

## Limits

- Size, rate, and time limits: {{values}}
- Performance target: {{value}}

## Out of scope

- {{What this change does not do.}}

## Open questions

Gaps the user must decide. The agent records its interim choice here and in the PR.

- {{question}}: interim choice {{choice}}, because {{reason}}.

## Changes

- {{date}}: {{what changed in this spec and why}}
