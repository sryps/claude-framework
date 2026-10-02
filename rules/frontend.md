---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.vue"
  - "**/*.svelte"
  - "**/*.html"
  - "**/components/**"
  - "**/pages/**"
  - "**/app/**"
  - "**/web/**"
  - "**/client/**"
  - "**/frontend/**"
  - "**/public/**"
---

# Frontend

## Trust model

- The client is not a security boundary. Every check in the client is for UX only. The server repeats it.
- Hiding a button does not protect an action.

## Secrets and config

- MUST NOT put a secret in client code. Anything in the bundle is public.
- Env vars with a public prefix (`NEXT_PUBLIC_`, `VITE_`, `EXPO_PUBLIC_`, `PUBLIC_`, `REACT_APP_`) are public. Only put public values there: a publishable key, a public URL, a Supabase anon key with RLS on.
- Never put a `service_role` key, a private API key, or a signing secret in the client.

## XSS

- Let the framework escape output. Do not bypass it.
- MUST NOT use `dangerouslySetInnerHTML`, `v-html`, `{@html}`, `innerHTML`, or `document.write` with untrusted data. If rich HTML is required, sanitize with DOMPurify and a strict allowlist.
- Validate URLs before you put them in `href`, `src`, or `window.location`. Allow `https:` and relative paths only. Block `javascript:` and `data:`.
- Do not build HTML or CSS strings from user input.

## Headers

- Set a Content Security Policy. Start from `default-src 'self'`. Use nonces or hashes for inline scripts. No `unsafe-eval`. Avoid `unsafe-inline` for scripts.
- Set `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, and `frame-ancestors` in CSP (or `X-Frame-Options`).
- Load third-party scripts with Subresource Integrity, or self-host them.

## Auth in the browser

- Prefer `HttpOnly` cookies set by the server. Do not keep tokens in `localStorage`.
- Send CSRF protection with state-changing requests when auth uses cookies.
- Clear client state and caches on logout.

## Data

- Do not log PII or tokens to the console. Remove debug logs before merge.
- Do not put PII in URLs, query strings, or analytics events.
- `postMessage`: check `event.origin` against an allowlist. Send with an exact target origin.

## Quality

- Accessibility: semantic HTML, labels on inputs, keyboard access, visible focus, color contrast AA.
- Handle loading, empty, and error states for every async view.
- Type all props and API responses. Parse API responses with the shared schema at the edge.

## Done means

- [ ] No secret in the bundle. Public env vars hold public values only.
- [ ] No raw HTML injection of untrusted data.
- [ ] CSP and security headers are set or unchanged.
- [ ] Every access check also runs on the server.
