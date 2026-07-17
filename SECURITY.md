# Security Policy

Piru is an on-device iOS app: your dose journal lives locally in SwiftData, there is no account and no
server, and backups are opt-in and end-to-end encrypted. Two things here are worth protecting, and they're
unusual for a phone app — the **privacy** of a record of controlled-substance use, and the **integrity** of
pharmacology data that people act on. Reports on either are welcome.

## Reporting a vulnerability

Please report security and privacy issues **privately**, not as public GitHub issues:

- Use GitHub's [private vulnerability reporting](https://github.com/kageroumado/piru/security/advisories/new)
  (Security → Advisories → "Report a vulnerability"), or
- Reach out to [@kageroumado on X](https://x.com/kageroumado).

Include a description, the affected version (Settings shows it), and reproduction steps. We aim to
acknowledge within a few days. Once a fix ships, we're happy to credit you — or keep you anonymous, your call.

## Scope — what matters most

- **Anything that moves journal data off the device.** Piru's core promise is that nothing leaves your
  phone unless you explicitly export or back up. A path that sends dose history, timestamps, location, or
  health data to the network, a system log, the pasteboard, or another app *without the user asking* is the
  most serious class of bug here.
- **Weaknesses in the encrypted-backup path.** Backups are AES-256-GCM, with a device key held in the
  iCloud Keychain or a user passphrase (PBKDF2). A backup that's weaker than advertised — recoverable
  without the key, leaking plaintext, nonce reuse, a broken or bypassable KDF — is in scope.
- **Data integrity that could cause physical harm.** Because people dose based on what Piru shows, a defect
  that makes it silently display a *wrong and dangerous* value is a safety issue, not merely a bug: an
  interaction rule that fails to fire for a genuinely dangerous pair, a dose ladder off by an order of
  magnitude, a half-life or PK curve that badly under-reports how much is still active. Report these like a
  vulnerability and we'll fast-track them.
- **The `piru://` URL scheme.** Deep links are an external input surface (`DeepLink.decode`). A crafted URL
  that crashes the app, corrupts the store, or navigates somewhere it shouldn't is in scope.

## Not a security boundary, and not medical advice

Piru's models are **estimates, not measurements.** A "cleared" curve or an absent interaction warning is not
a guarantee of safety — the app can't know your physiology, the real contents or purity of what you took, or
an interaction no source has documented yet. Don't treat it as a safety authority or a substitute for a
clinician, a test kit, or poison control. This is by design and stated throughout the app; it isn't a bug.

## Supported versions

Only the latest TestFlight release and `main` receive fixes.
