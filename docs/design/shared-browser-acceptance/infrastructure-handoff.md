# Infrastructure handoff

Muzeum reused the shared `runCandidate` and `nativeLogin` exports unchanged
at Infrastructure commit `21771e1d5690fef6509cd383933a8029b4834d77`.
[Acceptance evidence](README.md) · [Disposable reproduction](../../../spec/browser_acceptance/README.md)

| Ownership | Follow-up |
|---|---|
| Infrastructure shared runner | Accept explicit Chromium executable and proxy options while retaining the runner's background-network restrictions, blocked service workers, and request policy. This removes the launch wrapper used by the Muzeum scenario. |
| Infrastructure disposable tooling | Share the loopback-only TLS proxy. It should accept an explicit authority-to-loopback map, refuse other destinations, preserve Host and HTTPS, and use fixture-only trust. Cover application-to-provider routing as well as browser-to-preview routing. |
| Infrastructure Ruby guidance | Document process-scoped routing for server-side OIDC clients. Ruby Net::HTTP uses `TCPSocket.open`, while other clients can use `TCPSocket.new` or `Socket.tcp`. Preserve the canonical issuer and TLS hostname verification. The Muzeum shim is confined to the disposable process. |
| Muzeum | Keep Archive fixture setup, route and disclosure assertions, screenshot masks, logout synchronization, and database checks in the application scenario. |

To reproduce, use the pinned Infrastructure checkout, a disposable Auth
checkout and PostgreSQL cluster, and the retained, independently verified
Muzeum staging archive. The Muzeum harness generates local-only Auth keys and
a fixture registration, runs the shared browser scenario, verifies the seal
again, and removes its disposable databases and generated credentials. Run
outside production and share only the sanitized evidence.

This handoff proposes shared-runner changes for the existing Infrastructure
work. Muzeum's pilot leaves the shared runner and Infrastructure worktrees
untouched.
