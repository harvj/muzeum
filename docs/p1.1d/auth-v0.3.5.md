# Auth v0.3.5 interoperability

[Issue #29](https://github.com/harvj/muzeum/issues/29) reviewed Auth candidate
[500f9eb8bd0dd09620d9990546e194115bd8c866](https://github.com/harvj/auth/commit/500f9eb8bd0dd09620d9990546e194115bd8c866)
against Muzeum `2126b610e83233854cc31749b297dada75169bb9`.
The existing Muzeum client is compatible with the candidate's direct TOTP and
recovery flows. The production Auth revision observed during the review was
`ad487e132b8628ae9b7a8b26190628272b608c48` (v0.3.4). This is isolated
interoperability evidence. A live v0.3.5 smoke test can follow the separately
authorized Auth rollout.

## Registration and session contract

| Item | Verified behavior |
| --- | --- |
| Issuer | `https://auth.harvj.com` with same-origin HTTPS discovery endpoints |
| Registered public client ID | `d70b5086500616a27a14dd926d896924be739b14270dd97e` |
| Registration | Enabled confidential client with `client_secret_basic`, authorization code grant, and code response |
| Registered and configured callback | `https://muzeum.fm/oidc/callback` |
| Registered and requested scopes | `openid offline_access`. Muzeum sends `prompt=consent`. |
| Membership and assurance | Auth checks active membership and uses its native assurance policy for Muzeum. No Muzeum-specific assurance profile or required-MFA ID is configured. Enrolled users complete Auth MFA. Native policy can allow password-only authorization for an unenrolled member. |
| Authorization transaction | Ten-minute, browser-bound, single-use state with nonce and S256 PKCE. Muzeum validates the signed RS256 ID token, issuer, audience, nonce, subject and authorized party as applicable. |
| Session and logout | Muzeum keys users by issuer and subject, encrypts the refresh grant server-side, and uses a signed HttpOnly, Secure-in-production, SameSite=Lax cookie. Sessions have a seven-day absolute limit, a 12-hour inactivity limit, and refresh-grant introspection after 60 seconds. Logout terminates the local session and requests Auth grant revocation. |

Auth v0.3.5 sends enrolled users directly to `/otp-auth` after the password
step. The recovery form preserves the pending authorization request when
switching methods. Auth's same-origin continuation starts a fresh authorization
GET before the browser returns to Muzeum. This preserves the credential form's
CSP and the existing validated callback flow. Muzeum continues to rely on Auth
for credentials, factor handling, membership and assurance. It does not request
an ACR or interpret Auth's MFA UI.

## Verification

- Ran the actual Auth candidate and Muzeum in separate processes and browser
  origins with disposable PostgreSQL databases, signing keys and accounts.
  The harness substituted loopback issuer, discovery transport, callback and
  Muzeum's form destination for production HTTPS. Browser navigation,
  Auth credential/MFA and consent forms, code exchange, signing-key fetch,
  Muzeum ID-token validation, grant introspection and logout used real app code.
- Chromium passed three journeys. Desktop direct TOTP reached the consent
  screen and returned to an authenticated Archive. Grant revalidation, local
  logout, manual relogin with Auth SSO and absolute session expiry behaved as
  expected. At 390 × 844, switching from TOTP to recovery, back, then to
  recovery again preserved the destination and returned to Muzeum after
  authorization. Consent cancellation consumed the attempt, created no local
  session and left subsequent navigation on manual sign-in.
- The exact Auth candidate's direct TOTP and OIDC request suites passed 31
  examples, including expired TOTP, missing CSRF, single-use recovery,
  enrollment/assurance policies and denied consent. Muzeum's request and
  browser authentication suites passed 33 examples, including expired and
  browser-mismatched state, replay, invalid nonce, CSRF, inactivity, logout
  and redirect-loop prevention. The existing tests already cover these
  consumer checks, so this review adds no runtime code or test duplication.

## Separate first-party authorization decision

Muzeum meets the observed registration prerequisites for consideration. It
currently has no first-party consent entry and still uses interactive consent.
Before authorizing a future change, verify first-party ownership and control
of the exact registered callback, recheck the enabled confidential registration,
review active membership and its native assurance policy, and obtain explicit
administrative consent for both scopes. In particular, review the seven-day
offline refresh grant and the revocation procedure.

Under separate Auth production authorization, the exact proposed entry in the
protected `AUTH_APPLICATION_APPROVALS` file would be:

```json
{
  "first_party_consent": {
    "d70b5086500616a27a14dd926d896924be739b14270dd97e": {
      "redirect_uri": "https://muzeum.fm/oidc/callback",
      "scopes": ["openid", "offline_access"]
    }
  }
}
```

Merge the entry into the existing document while retaining the `applications`
array, other entries, and Auth's file protection. Auth validates the request,
redirect, S256 PKCE, membership and assurance before considering prior consent.
The code request must contain state and nonce, omit custom claims, and request
only registered and approved scopes. Muzeum's `prompt=consent` is eligible
because `offline_access` is included and would be explicitly preapproved.
Removing the entry restores interactive authorization for future requests.
Existing grants retain their lifetime unless revoked.
[Auth first-party consent contract](https://github.com/harvj/auth/blob/500f9eb8bd0dd09620d9990546e194115bd8c866/docs/first-party-consent.md)
