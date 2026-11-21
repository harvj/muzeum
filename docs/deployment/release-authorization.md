# Muzeum release authorization v1

This is the proposed successor to the historical per-release selector and
migrator SHA lists. Existing controls and v0.3.6 remain active until privileged
installation is separately reviewed and authorized.

## One review and one invocation

Prepare one JSON review with the following fields. Use full lowercase SHA and
SHA-256 values. The release reviewer approves the scope, policy and rollback
classification together.

| Field | Contract |
| --- | --- |
| `format`, `application` | Integer `1` and `muzeum` |
| `sha`, `baseline`, `branch`, `version` | Exact reviewed candidate, current deployed SHA, its synchronized `main` or `release/vX.Y.Z` branch, and target `vX.Y.Z` |
| `scope`, `ci` | Durable operator scope reference and reviewed exact branch-push CI run in this repository |
| `policy`, `migrations` | `code-only` with an empty object, or `additive-verified` with the exact pending migration path-to-SHA-256 mapping. Pending file bytes still require matching additive reviews in the application checkout |
| `rollback` | `stop` if the prior app's compatibility with the resulting schema has not been approved. `verified-forward-compatible` only with a disposable baseline boot against the resulting schema. Code-only failures can recover automatically because schema is unchanged |
| `issued_at`, `expires_at` | Timezone-aware ISO 8601 timestamps, valid when beginning, with a maximum 24-hour interval |

Run the signing tool on the approved key custodian's machine. Do not put the
private key in the repository, deployment host or application CI. Supply the
resulting envelope to a single deployment invocation alongside the existing
Shell evidence. The signed bytes are kept intact through invocation.

```sh
ops/deploy/approve-release review.json approval.json --key /reviewer/ed25519.pem
MUZEUM_RELEASE_AUTHORIZATION=/review/approval.json \
APPLICATION_SHELL_REVIEW=/review/application-shell-review.json \
bundle exec cap production 'muzeum:release_deploy[v0.4.0,/review/v040-checkout]'
```

This illustrates the reviewed operation once the new controls are authorized.
For a signed `main` release use the existing `cap production deploy` entry point.
There is no separate selector or service-pause approval. The routine approval
covers the app-only pause, recovery checks, listed migrations, promotion and
bounded rollback allowed by its policy. A changed baseline, pending scope or
CI identity halts the attempt. If a failed migration changed the observed
schema, review the new scope before retrying. The original signed review is
retained by the operator and its payload digest is in the protected receipt.

## Initial privileged review

Install the coordinator, inspector and authorization library together under
the root-owned deployment directory and install the restricted migrator and
runtime library with the existing owner and permission rules. Enroll only the
authorized public key in `/etc/muzeum/release-approval.pub`. Keep the existing
restricted sudo entry and review that the deployment identity cannot execute the
migrator directly. Confirm Caddy route ownership, backup escrow, four-database
restore, and absence of an active failed or migrating receipt before changing
the installed contract. Verify the installed component digest from the controls
checkout. The digest changes only when the helper code actually changes.
A key rotation or privileged install is a separate operation.

The host verifies the Ed25519 signature, binds the active receipt to the exact
baseline and candidate, and compares Rails' pending inventory with the signed
scope before any pause. The migrator reads that protected receipt and rehashes
its approved files before running only the named database/version tasks under
the existing constrained OS and database identity. The application staging
tree remains within Muzeum's existing deployment identity boundary. This
change does not add an artifact attestation or a new activation broker.

A code-only release uses existing backup freshness and health checks without a
new isolated restore. Current additive policy retains fresh encrypted backup
and four-database recovery before migration and again before exposing the new
release. Destructive migrations and live data restore remain exceptional.
For approved compatible rollback, the coordinator restores the exact prior
pointer, restarts only Muzeum, checks the prior process and reactivates its
route. The inspector can accept only extra versions recorded for that exact
baseline after verified additive migration. No down migration or live restore
is automatic. If an interruption leaves schema or routing uncertain, the
protected receipt and lock remain for review. After a verified safe recovery
the lock can admit a later release.

## Disposable evidence

`ops/deploy/test_release_authorization.py` archives the exact v0.3.6 and
v0.4.0 trees. It uses the same signature verifier, coordinator, inspector, and
scoped Rails migrator call against four disposable PostgreSQL schemas with
encrypted Restic snapshot and restore verification. Route and systemd
effects are substituted with fixture controls. Check the actual production
unit, route and installer boundary in a disposable Linux host before
authorizing privileged installation.
