# Threat model: {{system or feature}}

- Date: {{YYYY-MM-DD}}
- Author: {{name or agent run}}
- Status: {{draft | reviewed}}
- Scope: {{what is in and out of scope}}

## Summary

{{Two or three sentences: what the system does and the main risks.}}

## Assets

| Asset | Data class | Why it matters |
|---|---|---|
| {{user credentials}} | restricted | {{account takeover}} |
| {{user PII}} | confidential | {{privacy, legal}} |
| {{payment data}} | restricted | {{fraud}} |

## Actors

| Actor | Trust | Access |
|---|---|---|
| Anonymous user | none | public endpoints |
| Authenticated user | low | own data |
| Admin | high | all tenant data |
| {{third-party service}} | partial | {{webhooks}} |

## Trust boundaries

1. {{Internet -> edge / CDN}}
2. {{Client app -> API}}
3. {{API -> database}}
4. {{API -> third-party APIs}}

## Data flows

| # | From | To | Data | Protocol | Auth | Crosses boundary |
|---|---|---|---|---|---|---|
| 1 | {{browser}} | {{API}} | {{credentials}} | HTTPS | {{none -> session}} | 1, 2 |
| 2 | {{API}} | {{Postgres}} | {{user rows}} | TLS | {{db role + RLS}} | 3 |

## Threats (STRIDE)

| ID | Category | Flow or component | Threat | Likelihood | Impact | Mitigation | Status |
|---|---|---|---|---|---|---|---|
| T1 | Spoofing | {{1}} | {{credential stuffing}} | {{M}} | {{H}} | {{rate limit, breached password check, MFA}} | {{done / todo}} |
| T2 | Tampering | {{2}} | {{mass assignment of owner_id}} | | | {{field allowlist, RLS WITH CHECK}} | |
| T3 | Repudiation | | {{admin denies a change}} | | | {{audit log}} | |
| T4 | Information disclosure | | {{IDOR on /items/:id}} | | | {{owner in query, deny-path test}} | |
| T5 | Denial of service | | {{unbounded list endpoint}} | | | {{pagination limit, rate limit}} | |
| T6 | Elevation of privilege | | {{user calls admin RPC}} | | | {{role check, SECURITY DEFINER review}} | |

Categories: Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege.

## Mitigations and tests

| Threat | Control | Test that proves it |
|---|---|---|
| T4 | {{query scoped by owner}} | {{items.spec.ts: "returns 404 for another user's item"}} |

## Residual risk

| Risk | Why it stays | Owner | Review date |
|---|---|---|---|
| {{risk}} | {{reason}} | {{name}} | {{date}} |

## Open questions

- {{question for a human}}
