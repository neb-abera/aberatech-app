# Security

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository, or write to support@alias.abera.tech. Do not open a public issue.

## What the app holds

- A session token for abera.tech: `abt_` and 43 base64url characters, 256 bits from the server's random number generator. The server stores only its SHA-256 hash.
- The token, with the person's name and role, lives in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. It is readable from the first passcode entry after a restart, so a HealthKit wake on a locked phone can send. It is never in a backup and never on another device.
- On the owner's phone, the last weigh-ins sent, in Application Support with `completeFileProtectionUntilFirstUserAuthentication`.
- The requests, wish list and fitness summary are held in memory while the app runs and are not written to disk.

## Threats and what answers them

| Threat | Answer |
|---|---|
| Another app on the phone catches the sign-in redirect | The redirect carries a one-time code that lives 2 minutes. Trading it needs the PKCE verifier only this sign-in holds (RFC 7636, S256). |
| A stolen or lost phone | Taking the person's address out of abera.tech's settings refuses every session they hold on the next request. Sign out on the phone ends that phone's session on abera.tech. |
| A household member reaches the owner's data or actions | abera.tech decides by the session's role: a household member's requests filter on their name, and weigh-ins take the owner's token alone. The app hides the owner's sections too, but the server is the control. |
| The token leaks through a server log or a proxy | It travels in an `Authorization` header over HTTPS, never in a query string. |
| A hostile or broken server answer | Answers over 2 MB are refused, and an answer that does not decode is an error on screen. |

## Accepted risks

- Weigh-ins wait for iOS to wake the app. A weigh-in logged with the phone locked reaches abera.tech after the next unlock.
- The `-demo` mode's in-memory server is compiled into Debug builds only (`#if DEBUG`).

## Standards checked

- RFC 7636 (PKCE) and RFC 8252 (OAuth 2.0 for native apps): the sign-in runs in a system browser sheet, never in a web view, with an S256 challenge.
- NIST SP 800-63B: a random 256-bit session secret, stored hashed by the verifier, revocable, with rate limits on sign-in (the server side is in aberaTech).
- NIST SP 800-53 SC-8 (transmission confidentiality): HTTPS only. App Transport Security is at its default, so plain HTTP is refused.
- NIST SP 800-53 SC-28 (protection of information at rest): the Keychain and file protection classes above.
- DISA Application Security and Development STIG: no secret in source or logs, no credential in a URL, input validated before use, and errors that name no secret.
