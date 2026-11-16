# P1.1a verified infrastructure inventory

Observed 2026-11-15 America/Chicago (host reported 2026-11-16 CET). Read-only SSH through the existing `harvj` alias, strict host-key checking, user admin at 88.99.245.24; no configuration, service or database writes. SSH/sudo access naturally creates normal host audit records. No private key, environment secret, application row or backup contents were read. This report intentionally omits unrelated application credentials/configuration values.

| Item | Verified evidence |
| --- | --- |
| OS/resources | Ubuntu 24.04.4 LTS, x86_64, Linux 6.8; 8 CPUs, 64,079 MiB RAM, 61,307 MiB available at sample; 32,767 MiB swap, 1 MiB used; load 2.85/2.77/2.60 |
| Disk | Root `/dev/sda3`, 436 GiB total, 112 GiB used, 302 GiB available; no `/srv` application layout found |
| Proxy | Caddy 2.11.1; systemd unit runs as caddy; `/etc/caddy/Caddyfile` is one monolithic config with no import convention visible; admin listener 127.0.0.1:2019; ports 80/443 owned by shared infrastructure |
| Domains | harvj.com static under `/var/www/harvj`; www redirect; arkham.radioactivita.com serves `/var/www/arkham/current/public` with shared Puma Unix socket; funding.harvj.com proxies localhost:8000 behind existing Basic Auth; default :80 static block |
| Baseline probes | HTTPS harvj.com 200; arkham.radioactivita.com 200; funding.harvj.com 401 as expected; no credentials supplied |
| Rails convention | arkham.service, User=deploy, `/var/www/arkham/current`, shared `.env`, `/home/deploy/.rbenv/shims/bundle exec puma`; systemd restart/logging; current/shared directories, not evidence of an existing Capistrano release history |
| Other apps | Separate arkham and self-funding services/databases; static personal site. Multiple ongoing self-funding jobs; leave these untouched |
| PostgreSQL | 16.15 cluster 16-main, listener 127.0.0.1:5432; databases postgres/postgres owner, arkham_production/arkham owner, self_funding_production/self_funding_owner owner; no Muzeum database |
| Roles | postgres superuser; arkham, self_funding_owner/writer/reader are non-superuser, no CREATEDB/CREATEROLE. No Muzeum role. Schema-level grants were not exhaustively inspected |
| Runtime | deploy's rbenv has Ruby 3.4.8 only. Muzeum requires 3.3.5; provision separately under proposed Muzeum identity rather than modifying existing app runtime |
| Network | UFW active, permits SSH and 80/443 IPv4/IPv6; no public PostgreSQL listener; loopback 8000 occupied, proposed 3011 unoccupied at inspection |
| Backups | Root-owned `/var/backups/continuum-engine-deploy` and postgres-owned `/var/backups/self-funding-engine` exist. No root/deploy crontab, no backup-specific systemd unit found in scoped search, no database backup timer in enumerated timers; ordinary dpkg backups/logrotate exist. This does not prove backups are absent. Off-host schedule, retention, encryption, restorability and restore ownership remain unverified |
| Isolation | Existing applications share host/PG cluster and at least some deploy identity; use a dedicated Muzeum identity/database roles and service limits. No existing resource limits were changed |

Access limitations/decisions: SSH initially blocked by sandbox, succeeded with approved network execution. First role metadata query had a typo; corrected read-only query succeeded. Admin has broad sudo; use only scoped actions in future and provision a narrow Muzeum service-control policy. No Muzeum home, deploy key, database, unit, domain or backups have been provisioned. DNS state, certificate issuance for muzeum.fm, manual approval record format, off-host backups, detailed PG grants/connection budget and alert destination require confirmation. No claim of production readiness is made.
