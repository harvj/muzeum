# Muzeum deployments

Follow the [operator-managed Capistrano runbook](minimal-capistrano.md) for
release staging, migration, promotion, compatible code rollback, and footer
synchronization. Production changes require explicit operator authorization.
The deploy identity owns executable files, while systemd runs Muzeum under its
runtime identity. Migration authority stays with the operator and the scoped
PostgreSQL role. CI verifies exact revisions and never deploys.

Keep the deployment and backup lock files, archived receipts, local GitHub
deployment outbox, protected diagnostics, and verified recovery evidence.
The operator records the exact SHA and the verified production outcome in
GitHub Deployments. Historical receipts can be reconciled without redeploying.

The [post-release cleanup](legacy-deployment-retirement.md) does not apply to
the v0.4.0 cutover. Historical runbooks document earlier procedures and must
not be used to reinstall retired deployment components.
