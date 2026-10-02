---
paths:
  - "**/ios/**"
  - "**/android/**"
  - "**/app.json"
  - "**/app.config.*"
  - "**/eas.json"
  - "**/*.swift"
  - "**/*.kt"
  - "**/*.kts"
  - "**/*.m"
  - "**/AndroidManifest.xml"
  - "**/Info.plist"
  - "**/*.entitlements"
---

# Mobile apps

Store builds, store submits, and OTA updates to production are Red tier. Changes to entitlements, manifests, `app.json`, or `eas.json` are Yellow.

## Secrets

- The app binary is public. Anyone can extract strings from it. MUST NOT ship a private API key, a signing secret, or a `service_role` key.
- Call privileged APIs through your backend. The backend holds the secret.
- Signing keys, keystores, and provisioning profiles never enter the repo.

## Storage

- Tokens and secrets: Keychain (iOS) and Keystore-backed EncryptedSharedPreferences (Android). In Expo, use `expo-secure-store`.
- MUST NOT store tokens in AsyncStorage, `UserDefaults`, plain `SharedPreferences`, SQLite without encryption, or files.
- Exclude sensitive files from backups when needed.
- Clear secure storage and caches on logout.

## Network

- HTTPS only. Keep App Transport Security on (iOS). Set `usesCleartextTraffic=false` (Android).
- Do not turn off certificate checks, also not for debug builds that ship.
- Certificate pinning: decide it and record the decision in an ADR. If you pin, pin the public key, ship a backup pin, and plan rotation.

## Deep links and intents

- Validate every deep link parameter as hostile input.
- Prefer Universal Links and App Links over custom schemes for auth callbacks.
- OAuth on mobile: use the system browser (ASWebAuthenticationSession, Custom Tabs) with PKCE. Never a WebView.
- Android: exported components need `android:exported` set on purpose and a permission when they handle sensitive actions.

## WebViews

- Turn off JavaScript unless required. Never load untrusted URLs.
- Restrict the JS bridge to an allowlist of origins and methods.

## Permissions and privacy

- Request the fewest OS permissions. Ask at the moment of use with a clear reason.
- Fill the privacy manifest (iOS) and data safety form (Android) to match what the app collects.
- Background location, contacts, and photos need a written reason in the PR.

## Release hygiene

- Strip debug logs and dev menus from release builds.
- Turn on code shrinking and obfuscation for Android release builds.
- Keep the SDK and native modules on supported versions. Align Expo SDK packages with `npx expo install`.

## Done means

- [ ] No secret in the binary or the JS bundle.
- [ ] Tokens in secure storage only.
- [ ] Deep links validated.
- [ ] No new OS permission without a reason in the PR.
