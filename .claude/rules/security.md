# Security baseline

This file applies to every change in every project. The other rules files add to it. They never relax it.

## Tiers

| Tier | Meaning | Who acts |
|---|---|---|
| Green | Normal code, tests, docs, refactors | The agent does it |
| Yellow | Auth, crypto, sessions, access control, migrations, CI, infra, dependencies | The agent does it on a branch. The PR gets a `Security-Review:` section. A human reviews before merge. |
| Red | Merge, push to a protected branch, force push, deploy, publish, secrets, production data | Never. Hooks block it. Record the need under Blocked. |

Do not look for another spelling of a blocked command. A block is a final answer.

## Trust boundaries

- Treat all input from outside the process as hostile. This includes HTTP bodies, headers, query strings, cookies, files, environment from CI, webhooks, message queues, deep links, and LLM output.
- Validate input at the boundary with a schema. Reject unknown fields. Never validate deep inside business logic only.
- Encode output for its sink: HTML, SQL, shell, URL, log line, or file path. Each sink has its own encoder.
- Decide access on the server. The client never decides who can see or change data.

## Defaults

- Deny by default. A new route, table, bucket, queue, or feature flag starts closed.
- Use least privilege for every credential, token, role, and service account.
- Fail closed. When a check errors, deny the request.
- Prefer boring, well-known libraries over custom code for auth, crypto, parsing, and sanitizing.

## Secrets

- MUST read secrets from the environment or a secret manager at runtime.
- MUST NOT commit a secret, a real `.env` file, a private key, or a token. Commit `.env.example` with placeholders only.
- MUST NOT log, print, or return a secret in an error message.
- MUST NOT read secret files in an agent session. Hooks block it.
- A leaked secret is revoked, not deleted from history only. Record it under Blocked so a human rotates it.

## Crypto

- MUST NOT write your own crypto or invent a token format.
- Passwords: Argon2id (or bcrypt cost 12+ if Argon2id is not available).
- Symmetric encryption: AES-256-GCM or ChaCha20-Poly1305 from the platform library, with a random nonce for each message.
- Random values for tokens and IDs: the OS CSPRNG (`crypto.randomBytes`, `secrets`, `crypto/rand`, `rand::rngs::OsRng`, `SecRandomCopyBytes`).
- Compare secrets in constant time.
- TLS 1.2 minimum, TLS 1.3 preferred. Never turn off certificate checks, also not in tests that reach the network.

## Common classes to check on every change

- Injection: SQL, NoSQL, shell, template, LDAP, XPath, header (CRLF).
- Broken access control and IDOR: can user A read or change user B's object by ID?
- SSRF: does the server fetch a URL that a user controls?
- Path traversal: does a user value reach a file path?
- Unsafe deserialization: `pickle`, `yaml.load`, Java serialization, `eval`, `new Function`.
- Mass assignment: does a user set a field like `role`, `owner_id`, or `is_admin`?
- Race conditions on money, quotas, or one-time tokens.

## Errors

- Return a generic error to the client with a request ID. Log the detail on the server.
- Never return stack traces, SQL, file paths, or library versions to a client.

## Skills

- Run `threat-model` for a new service, a new trust boundary, or a new data store.
- Run `review-security` before you open a PR that touches a Yellow path.
- Run `vulnscan` for a periodic sweep.

## Done means

- [ ] All new input has schema validation at the boundary.
- [ ] All new access checks run on the server and have a deny-path test.
- [ ] No secret, key, or token is in the diff.
- [ ] Errors to the client are generic.
- [ ] Yellow paths are listed in the PR under `Security-Review:`.
