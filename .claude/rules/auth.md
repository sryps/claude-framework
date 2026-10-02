---
paths:
  - "**/auth/**"
  - "**/authn/**"
  - "**/authz/**"
  - "**/*auth*"
  - "**/*login*"
  - "**/*logout*"
  - "**/*signup*"
  - "**/*signin*"
  - "**/*session*"
  - "**/*token*"
  - "**/*jwt*"
  - "**/*oauth*"
  - "**/*oidc*"
  - "**/*password*"
  - "**/*permission*"
  - "**/*rbac*"
  - "**/*policy*"
  - "**/*policies*"
  - "**/middleware*"
  - "**/guards/**"
---

# Authentication, sessions, and access control

Every file here is Yellow tier. Run the `auth-change` skill before you open the PR. Run `review-security` at the end.

## Identity

- MUST use a vetted provider or library: Supabase Auth, Auth0, Clerk, Cognito, Firebase Auth, Keycloak, `next-auth`/Auth.js, `passport`, Django auth, `golang.org/x/oauth2`, `oauth2` crate, AppAuth on mobile.
- MUST NOT write your own password storage, token format, or OAuth flow.
- OAuth and OIDC: use Authorization Code with PKCE. Check `state` and `nonce`. Never use the implicit flow.
- Validate `iss`, `aud`, `exp`, `nbf`, and the signature on every JWT. Pin the algorithm. Reject `alg: none` and HS/RS confusion.
- Fetch JWKS from the issuer over TLS and cache it with a short TTL.

## Passwords

- Hash with Argon2id. bcrypt with cost 12 or more is the fallback.
- Minimum length 8, maximum at least 64. No composition rules. Check against a breached-password list when possible.
- Login, signup, and reset return the same response and timing for "no such user" and "wrong password".
- Password reset tokens: single use, random 128 bits or more, expire in 30 minutes or less, stored hashed.

## Sessions

- Web: session cookie with `HttpOnly`, `Secure`, `SameSite=Lax` (or `Strict`), and a `__Host-` prefix when possible.
- Rotate the session ID at login, logout, and privilege change.
- Access tokens live 15 minutes or less. Refresh tokens rotate on each use. Detect refresh token reuse and revoke the family.
- Logout revokes the session on the server, not only in the client.
- Mobile: store tokens in the Keychain or Android Keystore (`expo-secure-store`). Never in AsyncStorage, `localStorage`, or plain files.
- Browsers: do not store long-lived tokens in `localStorage` or `sessionStorage`.

## MFA and abuse

- Support TOTP or WebAuthn for admin roles. Use a library for TOTP.
- Rate limit login, signup, reset, and MFA checks by IP and by account.
- Lock or slow down after repeated failures. Never lock with no way to recover.
- Log auth events (login, failure, reset, MFA change, role change) without the password or token.

## Access control

- Check authorization on the server for every request, on every object.
- Load objects with the owner or tenant in the query (`WHERE id = $1 AND org_id = $2`). Do not load by ID and then compare.
- One central policy function or layer. Do not scatter role checks through handlers.
- Deny by default. A new route needs auth unless it is on the public allowlist.
- Admin features need a separate role check and an audit log entry.
- Supabase and Postgres: enable RLS on every table in an exposed schema. Write policies for `select`, `insert`, `update`, and `delete` one by one. Never ship the `service_role` key to a client.

## Tests that MUST exist

- No credentials -> 401.
- Valid user, other user's object -> 403 or 404 (IDOR).
- Valid user, admin action -> 403 (privilege escalation).
- Expired token -> 401. Tampered token -> 401.
- Reused refresh token -> session family revoked.
- RLS: a pgTAP or SQL test for each policy, as two different users.

## Done means

- [ ] A vetted library handles the identity flow.
- [ ] Every new route has an auth test and a deny-path test.
- [ ] Object loads include the owner or tenant.
- [ ] Tokens are stored in secure storage only.
- [ ] `auth-change` and `review-security` ran. The PR has `Security-Review:`.
