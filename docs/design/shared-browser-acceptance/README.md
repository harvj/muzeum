# Muzeum shared browser-acceptance pilot

The Muzeum-specific scenario ran against the sealed disposable v0.7.7
Capistrano artifact using the shared Infrastructure runner and native Auth
login helper at `21771e1d5690fef6509cd383933a8029b4834d77`. The disposable
artifact was never deployed. The private Archive used the existing
listening-profile fixture without granting publication.

- [Shared acceptance report and timings](evidence.json)
- [Environment and sealed-inventory bindings](environment.json)
- [Sanitized desktop](desktop.png) and [sanitized mobile](mobile.png)
- [Reproduction instructions](../../../spec/browser_acceptance/README.md)
- [Infrastructure handoff](infrastructure-handoff.md)

The scenario verifies native password and TOTP, OIDC with PKCE, private Archive
access, the signed-in account disclosure, keyboard behavior, and desktop and
mobile layouts. Logout waits for Muzeum's session-termination response and
confirms the session cookie is gone before requesting either private route.
The harness verifies that the database session was deleted and Auth revoked
the grant. The existing 11 automatic sign-in and Shell browser examples are
retained and passed alongside the pilot.
