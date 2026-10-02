---
paths:
  - "**/api/**"
  - "**/routes/**"
  - "**/handlers/**"
  - "**/controllers/**"
  - "**/endpoints/**"
  - "**/graphql/**"
  - "**/rpc/**"
  - "**/functions/**"
  - "**/*.proto"
  - "**/openapi*.{yaml,yml,json}"
  - "**/swagger*.{yaml,yml,json}"
---

# APIs

Run the `api-design` skill for a new endpoint or a change to a contract.

## Contract first

- Write or update the contract before the handler: OpenAPI, GraphQL schema, protobuf, or a shared zod/pydantic schema.
- Generate types or validators from the contract. Do not hand-copy shapes.
- Breaking changes need a new version (`/v2`, a new field, or a new RPC). Never change the meaning of an existing field.

## Every endpoint

- Authentication is on by default. Public routes are on an explicit allowlist in one place.
- Authorization checks the caller against the object (see `auth.md`).
- Validate path, query, headers, and body with a schema. Reject unknown fields. Set max lengths and numeric ranges.
- Limit request body size. Limit array length and nesting depth.
- Paginate every list. Set a default and a maximum page size. Prefer cursor pagination.
- Return one error shape for the whole API, for example `{ "error": { "code": "...", "message": "...", "request_id": "..." } }`.
- Never return internal fields: password hashes, internal IDs that grant access, tokens, or other users' PII.
- Use response DTOs or serializers. Do not return ORM objects directly.

## Writes

- Accept an `Idempotency-Key` header on non-idempotent writes that move money, send messages, or create resources.
- Use transactions for multi-step writes.
- Guard against mass assignment: allowlist the fields a caller can set.
- Use optimistic concurrency (`ETag`/`If-Match` or a version column) where lost updates matter.

## Abuse

- Rate limit by user and by IP. Use stricter limits on auth, search, export, and expensive endpoints.
- Return 429 with `Retry-After`.
- Set timeouts on every outbound call. Use circuit breakers for flaky dependencies.

## Browser-facing APIs

- CORS: allowlist exact origins. Never reflect the `Origin` header. Never combine `*` with credentials.
- CSRF: cookie-auth endpoints that change state need `SameSite` cookies plus a CSRF token or an `Origin` check.
- Set `Content-Type` on every response. Send `X-Content-Type-Options: nosniff`.

## Server-side fetches (SSRF)

- Never fetch a URL from user input without an allowlist of hosts.
- Block private, loopback, link-local, and metadata ranges (`169.254.169.254`, `fd00::/8`) after DNS resolution.
- Turn off redirects or check each redirect target.

## GraphQL

- Set query depth and cost limits. Turn off introspection in production.
- Authorize in resolvers or a field-level layer, not only at the gateway.

## Webhooks

- Verify the signature with the provider's secret and a constant-time compare.
- Reject old timestamps to stop replays. Make handlers idempotent.

## Done means

- [ ] The contract changed first and types come from it.
- [ ] Auth, authz, validation, pagination, and rate limits are in place.
- [ ] Tests cover 400, 401, 403/404, 429, and the success path.
- [ ] No internal fields in responses.
