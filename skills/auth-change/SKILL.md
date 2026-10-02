---
name: auth-change
description: Checklist for any change to authentication, sessions, tokens, passwords, permissions, RLS, or crypto. Covers vetted libraries, cookie flags, token lifetimes, password hashing, MFA, enumeration, brute force, and IDOR tests, and ends with a security review of the diff. Use for every Yellow-tier auth or crypto edit.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, Skill
---

# /auth-change: auth, session, and crypto checklist

**Arguments:** `$ARGUMENTS` (the change)

Auth code is Yellow tier. You may change it on a branch. A human reviews it before merge. Read `.claude/rules/auth.md` first.

## 1. Rules that never bend

- Use a vetted provider or library: the platform auth (Supabase Auth, Auth0, Clerk, Cognito, Firebase Auth), or a mature library (Auth.js, Lucia patterns, Passport, Devise, django.contrib.auth, `golang.org/x/crypto`, `ring`, libsodium).
- Never write your own crypto, token format, password hash, or random generator.
- Use the platform CSPRNG: `crypto.randomBytes`, `crypto.getRandomValues`, `secrets`, `crypto/rand`, `rand::rngs::OsRng`.
- Never trust identity or role from the client. Read it from the verified session or token on the server.
- Never log passwords, tokens, session IDs, reset links, or MFA codes.

## 2. Checklist

Check each item that the change touches. Write the result in the PR `Security-Review:` section.

**Passwords**
- [ ] Hash with Argon2id (memory 19 MiB or more, iterations 2 or more). bcrypt with cost 12 or more is the fallback. Never SHA or MD5.
- [ ] Minimum length 8 or more. No forced composition rules. Check against a breached-password list if the provider supports it.
- [ ] Compare hashes with the library verify function, which is constant time.

**Sessions and cookies**
- [ ] Cookie flags: `HttpOnly`, `Secure`, `SameSite=Lax` or `Strict`, narrow `Path`, `__Host-` prefix where possible.
- [ ] Rotate the session ID on login, privilege change, and password change.
- [ ] Logout invalidates the session on the server, not only in the client.
- [ ] Idle and absolute timeouts are set.
- [ ] CSRF protection on state-changing requests that use cookies.

**Tokens**
- [ ] Access tokens live 15 minutes or less. Refresh tokens rotate on use, with reuse detection.
- [ ] Verify signature, `exp`, `nbf`, `iss`, and `aud`. Pin the algorithm. Reject `alg: none`.
- [ ] Mobile and native: store tokens in Keychain, Keystore, or SecureStore. Never in AsyncStorage, localStorage, or plain files.
- [ ] Web: prefer HttpOnly cookies to localStorage for session tokens.

**Login, signup, reset**
- [ ] Same response and similar timing for unknown user and wrong password (no account enumeration).
- [ ] Rate limit and back off per account and per IP.
- [ ] Reset tokens are single use, expire in 1 hour or less, and are stored hashed.
- [ ] Email change and password change need the current password or a recent re-auth.
- [ ] OAuth: validate `state`, use PKCE, exact-match redirect URIs.

**MFA**
- [ ] TOTP or WebAuthn through the provider. Recovery codes are single use and stored hashed.
- [ ] Sensitive actions need a fresh MFA check.

**Authorization**
- [ ] Deny by default. Each route or query checks the specific resource, not only "signed in".
- [ ] Postgres or Supabase: RLS is enabled on every table with user data, with a policy per operation. The service role key never reaches a client.
- [ ] Roles live on the server. A user cannot change their own role.

## 3. Tests you must add

- Unauthenticated request gets 401.
- User B cannot read, update, or delete user A's resource (403 or 404).
- A normal user cannot call an admin route.
- Expired, tampered, and wrong-audience tokens fail.
- Logout then reuse of the old session fails.
- RLS: a query as user B returns no rows of user A. Use pgTAP or the repo's DB test setup.
- Enumeration: unknown user and wrong password give the same response.

## 4. Finish

1. Run the full test suite.
2. Run `/review-security` on the branch diff, or delegate to the `security-reviewer` subagent. Fix every CRITICAL and HIGH finding.
3. Add the `Security-Review:` section to the PR body. Name each auth file, the risk, and the test that covers it.
