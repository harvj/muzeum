# Application Shell 1.1 consumer

Muzeum requests Auth consumer evidence v1 from the authenticated provider
introspection endpoint with the current refresh grant. Eligibility never
changes authorization at a destination. The browser uses an authenticated
same-origin endpoint, with private no-store responses. It clears the previous
result during recheck, expiry, or restoration and retains local settings and
logout if evidence is unavailable. Only Auth's verified username is displayed.

Configure `MUZEUM_SHELL_REGISTRY_CACHE` to point to the verified cache produced
by Infrastructure's `application-shell-registry --cache PATH`. The cache and
its parent must be protected from untrusted writers. Provision that refresh
independently of Muzeum deployment. The verifier atomically replaces a complete
cache only after verification. Muzeum reads it locally, checks the envelope,
version/schema, registry byte digest and entry shape, and preserves publication
order. Muzeum never fetches a registry on the request path. With no cache or
affirmative Auth evidence, the Applications section stays hidden.

The draft Auth implementation and approved production client mapping must be
verified separately. The PR exercises Auth's contract over a disposable local
session and Infrastructure's actual signed fixture refresh over two versions.
The signed fixture command is:

```sh
python3 -B script/test_application_shell_registry.py /path/to/reviewed/infrastructure
```

The ordinary CI adapter records independently tested cases. Full acceptance
requires scoped evidence for every remaining case, including an explicit
registered-host and route-class acceptance rehearsal for SH-08. A partial CI
audit cannot authorize deployment or replace the held release review.
