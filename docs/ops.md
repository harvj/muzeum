# Operational Notes

The [P1.1 production deployment plan](p1.1/production-deployment-plan.md) is the current proposed runbook; P1.1a is implemented locally; production deployment remains unauthorized. See the [verified inventory](p1.1/infrastructure-inventory.md), [runbook](p1.1/deployment-runbook.md) and [results](p1.1/p11a-results.md).

- Target: muzeum.fm on the existing shared Hetzner host and Caddy infrastructure.
- Capistrano deploys an explicitly approved commit manually; GitHub Actions runs CI on every main push and never deploys automatically.
- Independently managed Muzeum web/workers, secrets, persistent PostgreSQL and shared storage; preserve other apps/databases.
- PostgreSQL major version must be inventoried and aligned with tests; the former 15.x note conflicts with CI/baseline 16 and is not a verified production target.
- Authenticate before exposing personal history or controls. Use Rails-native ERB/Hotwire, Propshaft/import maps and server-side business rules.
- Full real historical import and asynchronous resolution execute on the server; local testing uses synthetic data.
- No push, deployment, DNS/service changes or production database operations without explicit approval.

P1.1b modernizes Ruby to 3.4.12 and resolves the dependency audit; see the [dependency report](p1.1b/dependency-modernization.md). Docker/Kamal/Thruster scaffolding is removed. Future deployment must provision the new runtime and apply the additive Solid Queue batch migration; no server changes have been made.
