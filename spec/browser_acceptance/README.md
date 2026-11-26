# Disposable authenticated browser acceptance

This pilot uses Infrastructure's shared `runCandidate` and `nativeLogin` from
`21771e1d5690fef6509cd383933a8029b4834d77`. The scenario ports the relevant
checks from `automatic_sign_in_spec.rb` and `application_shell_spec.rb`.
It uses real Auth password, TOTP, consent and OIDC code/PKCE exchange, then
checks the private Archive, identity disclosure, layout, keyboard, logout,
and direct navigation to the private routes after logout.

Use the macOS loopback-only sandbox, an existing **disposable** PostgreSQL
cluster on port 55435, and a trusted Capistrano archive from disposable Linux
staging. The harness creates fresh fixture databases and removes them on exit.
It requires Ruby and the preinstalled Auth bundle, Node with Playwright Core,
Chromium, PostgreSQL tools, OpenSSL, jq and Python 3. Supply absolute paths.

| Environment variable | Input |
|---|---|
| `MUZEUM_BROWSER_WORK` | New private output directory |
| `AUTH_CHECKOUT` | Auth source checkout, exported from its committed tree |
| `INFRA_CHECKOUT` | Exact Infrastructure pilot checkout |
| `MUZEUM_CANDIDATE_ARCHIVE` | Retained disposable staging archive |
| `MUZEUM_CANDIDATE_SHA` | Expected full application source SHA |
| `MUZEUM_SEALED_DIGEST` | Independently verified Muzeum sealed inventory SHA-256 |
| `MUZEUM_ARCHIVE_DIGEST` | Retained archive SHA-256 |
| `PLAYWRIGHT_NODE_MODULES` | Local directory with Playwright Core and its package lock |
| `CHROME_BINARY` | Local Chromium executable |
| `MUZEUM_RUNTIME_GEMFILE` | Optional local bundle for testing on a different Ruby patch/platform |

Run `spec/browser_acceptance/run-muzeum.sh` with the inputs above. Verify the
full command succeeds. It checks the shared report, database logout effects,
and the seal after the browser run. The shared report binds the archive digest,
source commit and tree, and the environment digest. The environment manifest
includes the separately verified sealed inventory, harness inputs and runtime
dependency fingerprints.

The private fixture uses the existing listening-profile fixture without
publication helpers. The HTTPS proxy only routes the two known authorities to
loopback. Auth runs from exported source, with a disposable registration and
signing keys. The Ruby transport shim routes only the pinned OIDC authority;
issuer, TLS hostname, signatures and MFA remain checked. Chromium trusts only
the generated fixture public-key pin, and outbound connections are blocked
by the sandbox. Preserve only the shared `evidence/` output and sanitized
environment manifest for review. Keep process logs and all scratch material
private. Native traces are disabled.

## Shared-runner handoff

A first-class way to pass Chromium executable and proxy options would remove
the launch wrapper shared by the CE and Muzeum scenarios. A shared loopback TLS
proxy with an explicit authority allowlist would eliminate the per-app adapter.
Ruby applications also need a process-scoped route for server-side OIDC HTTP
clients. Net::HTTP uses `TCPSocket.open`, which is distinct from
`TCPSocket.new`. The pilot uses the existing shared runner and login helper
without changes.

For logout, wait for the actual session termination response and the landing
page load before re-opening a private route. The pilot asserts cookie removal,
checks the unauthenticated routes in the same browser context, and verifies
local session deletion and Auth grant revocation in the disposable databases.
