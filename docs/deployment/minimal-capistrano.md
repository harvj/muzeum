# Muzeum operator-managed Capistrano release

The minimal Capistrano entry lives under `ops/capistrano`. It is separate from
the installed workflow until explicitly reviewed and installed. The operator's
ordinary authenticated checkout, exact CI, established Shell evidence, and
production approval are the release authority. No per-release privileged
executable, runtime selector entry, or signing key is needed.

## One-time host changes for review

- Use the app-specific `muzeum-deploy` transport identity for Capistrano. Allow
  only the operator's SSH key and a read-only repository fetch credential on
  that identity. The existing `muzeum` runtime and `muzeum-migrate` identities
  must not be able to authenticate as the deployment account or write through
  its directories. The deployment account receives no root or migrator sudo.
- Transfer ownership of the release parent, retained release trees, repository
  mirror, shared compiled assets and Ruby 3.4.13 bundle to the deployment
  identity. Verify service readability and traversal. Runtime-writable
  storage, logs and PID/socket paths stay in their existing shared locations.
  Keep the environment and migration credentials under their existing
  protected owners and restrict write access to shared-path parents. Review
  every symlink and ACL before the transfer. Preserve the v0.3.6 release and
  never run a recursive ownership change across the shared credential tree.
- Install the two root-owned `30-capistrano.conf` unit drop-ins and daemon
  reload only during authorized installation. They select the existing
  Muzeum Ruby through absolute commands for both artifacts. Retain the older
  drop-ins for installation rollback. Use the existing Muzeum service units
  and scoped route helper. Remove the legacy deployment identity's coordinator
  sudo grant at the approved transition, after verifying the operator's
  rollback access. No neighboring services or routes change.

## v0.4.0 release procedure

Keep the coordinator's historical failed receipt and matching four-database
recovery evidence. Record the candidate, baseline, CI URL, Shell review,
staged path, migration digest, new snapshot, restore, verification and release
outcome against Issue #28. Use the installed exclusive lock for the complete
operator session. Acquire the established backup lock through the backup
tool, in the established order. If the operator session is lost, reconcile
the recorded phase before another invocation.

1. From the reviewed controls checkout's `ops/capistrano` directory, run
   `bundle exec cap production muzeum:stage` with `MUZEUM_CHECKOUT`,
   `MUZEUM_BRANCH`, `MUZEUM_REVISION`, `MUZEUM_BASELINE` and
   `APPLICATION_SHELL_REVIEW` pointing at the approved inputs. This is
   Capistrano's normal Git, bundle and asset staging, without the publication
   hook. The two relevant SHAs are
   `96597aa6f94e64b6bb9cfdb7399de1ed98124a11` and
   `c37a00dcf058e87fdc59644e9e444c001e29622f`. Verify the actual bundle and
   that the runtime and migration accounts cannot change the release, mirror,
   bundle, assets or pointer. Audit the allowed linked shared paths. Confirm
   the only pending migration is primary version `20261121160000`, with
   SHA-256 `ccf5ac6f930dde4487cc537cb6a77112fc7bb2e5df63abb9d02107a47d2288e8`.
2. Withdraw only Muzeum with the existing scoped Caddy tool and stop its
   web and worker. Use the installed encrypted backup and isolated restore
   tools. Check that the new receipt binds the exact v0.3.6 snapshot and
   all four databases. Retain original-column fingerprints and schema
   protections using the existing read-only checks.
3. Under the operator's restricted migration session, run only
   `bundle exec rails db:migrate:up:primary` with `VERSION=20261121160000`
   from that staged release. Use the existing protected migration environment,
   explicit Ruby/Bundler paths, frozen bundle, disabled Bootsnap, and existing
   PostgreSQL lock/statement and process timeouts. Never pass migration
   credentials to the deployment or runtime account. Check the migration
   version and valid/ready index, schema invariants, and original-column
   fingerprints before publication. An uncertain or invalid concurrent
   index stops the attempt for inspection.
4. With the approved revisions and staged timestamp in
   `MUZEUM_REVISION`, `MUZEUM_BASELINE` and `MUZEUM_STAGED_RELEASE`,
   run `bundle exec cap production muzeum:select`. This uses the standard
   Capistrano publication hook. Start only Muzeum web and worker. Verify
   loopback, all four database connections and queue heartbeats. Retain the
   required post-migration encrypted backup and matching isolated restore
   before activating Muzeum's public route. Verify neighbors, application
   behavior and exact running SHA before publishing. Then use
   `bundle exec cap production 'muzeum:sync_release[v0.4.0]'` to sync the footer.
5. On a known compatible schema, run the same publication hook with the
   explicitly approved v0.3.6 directory and expected current SHA. Restart
   Muzeum only and health-check before reactivating its route. Retain a valid
   additive index. No down migration or restore over the live archive is
   part of rollback.

An ordinary code-only release stages and selects the candidate after checking
that no migration is pending. Existing backup freshness, health and rollback
checks still apply. There is no helper installation in the release procedure.
