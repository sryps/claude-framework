---
paths:
  - "**/*log*"
  - "**/*logger*"
  - "**/telemetry/**"
  - "**/analytics/**"
  - "**/monitoring/**"
  - "**/*sentry*"
  - "**/*tracing*"
  - "**/*metrics*"
---

# Logging, telemetry, and privacy

## Logging

- Use structured logs (JSON) with a level, a timestamp in UTC, a request ID, and a service name.
- MUST NOT log passwords, tokens, API keys, session IDs, full card numbers, private keys, or raw auth headers.
- MUST NOT log full request or response bodies on auth, payment, or PII endpoints.
- Mask or hash PII (email, phone, IP where required) unless the log needs it and the retention policy allows it.
- Strip CR and LF from user values before they reach a log line (log injection).
- Log security events: login success and failure, MFA change, password reset, role change, access denied, admin actions, and rate limit hits.
- Set the log level from config. Debug logs stay off in production.

## Error reporting

- Scrub PII and secrets in the error reporter (Sentry `beforeSend`, or the equivalent) before the event leaves the process.
- Do not attach request bodies or cookies by default.

## Analytics

- Collect only what a named purpose needs. Record the purpose.
- No PII in event names, properties, or URLs.
- Respect consent and do-not-track settings where law requires it (GDPR, CCPA).

## Retention and deletion

- Set a retention period for logs and analytics.
- User deletion requests remove or anonymize the user's data in the main store and in derived stores within the stated time.

## Data classes

- Know the data class of each field you add: public, internal, confidential, or restricted (credentials, health, payment, government IDs).
- Restricted data needs encryption at rest, access logging, and a note in the threat model.

## Done means

- [ ] No secret or raw PII in new log lines.
- [ ] Security events are logged.
- [ ] Error reporter scrubs PII.
- [ ] New data fields have a known data class.
