# Application Shell 1.1 consumer

Muzeum requests Auth consumer evidence v1 from the authenticated provider
introspection endpoint with the current refresh grant. Eligibility never
changes authorization at a destination. The browser uses an authenticated
same-origin endpoint, with private no-store responses. It clears the previous
result during recheck, expiry, or restoration and retains local settings and
logout if evidence is unavailable. Only Auth's verified username is displayed.

Configure `MUZEUM_SHELL_REGISTRY_CACHE` to point to the verified cache produced
by Infrastructure's `application-shell-registry --cache PATH`. Run the verifier under a trusted account. Its atomic cache is mode 0600;
arrange for the Muzeum service identity to read it through the approved cache
provisioning and protect its parent and every ancestor from untrusted writers.
The reader rejects symlinks and group- or world-writable cache files. Provision that refresh
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

The ordinary CI adapter exercises the registered canonical host and route
classes in a disposable environment. It does not exercise live ingress,
production Auth client mappings, or operator-managed refresh provisioning.
A scoped production acceptance decision and separate deployment approval
are still required. The audit does not replace the held release review.

SH-05 uses the signed mixed-case display fixture at the presentation boundary.
The separate transport tests accept only Auth's explicit lowercase contract
and verify issuer, consumer, subject and exact grant binding. A missing or
invalid username produces a generic warning with no grant or user fields,
and retains the local settings and logout controls.
