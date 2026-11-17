# Shared Auth application entry

A top-level browser navigation to the protected dashboard automatically enters the existing confidential OIDC code flow. The redirect through `/session/new` consumes a server-set, one-use initiation marker without rendering the manual page. Automatic and manual initiation share the same rate-limited implementation, browser-bound state, nonce, S256 verifier, callback validation and session creation. Private redirects are also non-cacheable.

Automatic initiation is limited to dashboard GET/HTML document navigations with browser Fetch Metadata. Missing metadata, Turbo frames, fetches, prefetch/prerender requests, HEAD/JSON, mutations, health and assets do not initiate authentication. Direct `/session/new` remains a deliberate manual entry point. The dashboard path/query is retained in the signed application session; callback destinations are restricted to the local dashboard. Request parameters cannot select an external return location.

Only one automatic attempt is allowed per application browser session until successful authentication resets the session. Returning from provider-owned access denial or login pages, callback/token failures, provider outages and rate limits therefore offers manual retry instead of redirecting repeatedly. Logout and failed native admission checks suppress automatic retries too. After explicit logout, selecting Muzeum again in that browser requires deliberate sign-in. Other applications retain their independent cookies and authorization checks.

Auth's established `openid offline_access` contract requires `prompt=consent` for its revocable durable grant. This change removes Muzeum's intermediate button; it does not bypass provider login, MFA, consent or application admission. No Auth/CE configuration or deployment is required.

## Verification and deployment review

Request tests cover automatic entry, signed token exchange/PKCE, session continuity, destination restriction, denial/login-required/provider errors, failed discovery/token verification, abandoned attempts, rate limiting, logout and excluded request types. Separate-origin Chrome fixtures exercise cross-application navigation with existing SSO, provider-owned fresh login, access denial, invalid authentication and logout using the real OIDC client/JWT verification. The existing positive-CSRF manual sign-in and responsive dashboard tests remain enabled.

This change has no migrations, dependency updates, import/job changes or environmental assets. The previous production OIDC revision `b2dc302078b86cd4960e130e96908d64a2feb25a` is a schema/session-compatible rollback target. Use the existing immutable-SHA Capistrano, CI and fresh backup/isolated recovery gates; only Muzeum services restart. The production navigation check should use an absent/expired Muzeum session and an active Auth session, without logging out of Auth. Verify the manual landing after Muzeum logout separately.
