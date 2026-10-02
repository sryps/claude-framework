---
name: api-design
description: Contract-first design for a new or changed API endpoint, RPC, or GraphQL field. Writes the schema first, then handlers and contract tests, with auth on by default, per-resource authz, validation, limits, and one error shape. Use when adding or changing any route, handler, RPC procedure, or webhook.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# /api-design: contract first

**Arguments:** `$ARGUMENTS` (the endpoint or capability)

Order: contract, then tests, then handler. Read `.claude/rules/api.md` and `.claude/rules/backend.md` first.

## 1. Find the contract format the repo uses

Check in this order and use the first one you find:
- OpenAPI: `openapi.yaml`, `openapi.json`, `**/openapi/**`
- tRPC or zod schemas: `**/routers/**`, `z.object(`
- Protobuf or gRPC: `**/*.proto`
- GraphQL: `**/*.graphql`, `schema.gql`
- JSON Schema: `**/*.schema.json`
- Pydantic or FastAPI models, serde structs, Go structs with validation tags

If none exists, use OpenAPI 3.1 for HTTP, and record it as a decision.

## 2. Write the contract

For each operation, define:

| Item | Rule |
|---|---|
| Path and method | Nouns for resources. `GET` never changes state. |
| Auth | Required by default. A public route goes on an explicit allowlist in code, with a comment that says why. |
| Authz | Name the rule: owner only, same tenant, role X. Check it in the handler or policy layer, never in the client. |
| Request schema | Every field typed, with max length, ranges, and enums. Reject unknown fields. |
| Response schema | Return only the fields the caller may see. Never return password hashes, internal IDs of other tenants, or tokens. |
| Pagination | Cursor or limit plus offset. Default limit 20 to 50. Hard max (for example 100). |
| Idempotency | `POST` that creates or charges accepts an `Idempotency-Key` header. Store the key with the result. |
| Rate limit | Per user and per IP. Tighter on auth, signup, password reset, and costly operations. |
| Errors | One shape for the whole API, for example `{ "error": { "code": "not_found", "message": "..." } }`. No stack traces, SQL, or file paths. |
| Status codes | 400 bad input, 401 no or bad auth, 403 known user without permission, 404 missing or not yours (prefer 404 to hide existence), 409 conflict, 422 validation, 429 rate limit. |
| Versioning | Additive changes in place. A breaking change gets a new version (`/v2` or a new procedure name). |

## 3. Contract tests

Write tests before the handler. Each operation gets:
- Happy path, with the response checked against the schema.
- 401 with no auth, and with an expired or malformed token.
- 403 or 404 when user B targets user A's resource (IDOR).
- 400 or 422 for each validation rule: missing field, too long, wrong type, unknown field.
- Limit at the max page size and above it.
- Repeat with the same idempotency key returns the first result, with no second side effect.
- 429 after the rate limit, if the test setup can drive it.

## 4. Handler

1. Parse and validate input with the schema at the edge. Code after this point uses typed values only.
2. Authenticate, then authorize against the specific resource.
3. Use parameterized queries or the ORM query builder. Never build SQL, shell, or file paths from strings.
4. Call outbound URLs only from an allowlist when the URL comes from input (SSRF).
5. Log the operation with a request ID and the user ID. Never log tokens, passwords, or full PII.
6. Map every error to the one error shape.

## 5. Webhooks in

- Verify the provider signature with a constant-time compare before you parse the body.
- Reject old timestamps to stop replay.
- Make the handler idempotent on the event ID.

## 6. Done

- The contract file, tests, and handler are in the same PR.
- Generated clients or types are regenerated with the repo's command, not edited by hand.
- The PR lists each new route and its auth rule.
