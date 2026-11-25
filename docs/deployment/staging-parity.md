# Muzeum staging parity

Production v0.7.3 demonstrated that shared links alone do not define the sealed release. Capistrano also writes `REVISION_TIME`, `.bundle/config`, and the final Propshaft manifest and its backup. A complete archive and identical compiled asset payloads still produced different digests when those records differed.

Capistrano owns staging. Use its generated revision, Bundler and asset files as produced by the existing tasks. The package checks require those files when sealing and verify the four runtime links during sealing and verification. The digest binds the link entries and all immutable files. It does not traverse linked data. Keep Capistrano Rails' shared-assets hook disabled. The installed recovery verifier remains responsible for runtime ownership, permissions and isolated restoration.

## Disposable staging and evidence

Use an isolated Linux host with the reviewed operator checkout, matching Ruby and Bundler, and the same absolute application and bundle layout as production. Use an independent fixture database cluster and mode-0600 fixture `shared/.env`. Never mount production storage, copy the production environment, or forward production credentials. Use a local Git mirror of the exact candidate. Before an activation rehearsal, stage both revisions in separate Capistrano invocations.

Copy `ops/deploy/disposable-staging.rb` into the reviewed operator checkout as `config/deploy/disposable.rb`. Create the `/var/www/muzeum/.muzeum-disposable` marker only inside the isolated host. Provide `MUZEUM_DISPOSABLE_ROOT`, `MUZEUM_DISPOSABLE_REPO`, and `MUZEUM_DISPOSABLE_REVISION`, then run `bundle exec cap disposable muzeum:qualify_staging`. This uses the existing Capistrano stage task sequence, source and asset checks, packager and verifier over local transport. It stops at the sealed identity and invokes no protected production phases.

Keep the complete candidate identity with the existing qualification evidence. Run the established isolated web, queue, authenticated route and recovery checks. Reverify the sealed identity after boot and recovery. Compare the full staged identity to the qualified identity before activating a retained production artifact. Preserve the existing protected phase, lock, scope and backup procedures. A matching source SHA alone is insufficient.

## Installed-path inventory

On 2026-11-25 the live scheduled restore service called `/usr/local/lib/harvj-backups/verify-restore`; its production path calls `production_restore.py`. The installed restore file hashed to `46b3c0260c6409d22882a3cbc27c58878808dc96babeb0e1f7cf5368aa31d63e` and differs from the application checkout's historical copy. Its shared-runtime branch checks ownership and permissions of the real shared tmp, PID and socket directories and verifies the retained release's exact identity as the app identity. Its separate legacy branch remains reachable for old retained releases and snapshots. The latest inspected four-database recovery receipt verified snapshot `645ce503803b01fb35a0f47705dce0626465b858a2e418fafd14771d831a2ed3` with v0.7.2 and confirmed session grant decryption. That receipt predates this cleanup.

The installed protected deployment helper, migration helper, and inspector remain reachable. The web and worker have both `20-runtime.conf` and `30-capistrano.conf` loaded, with effective entry points using the fixed Ruby runtime. Their live unit configuration disables Bootsnap. An overridden command alone does not establish that the earlier drop-in has no effect. Keep both until a complete unit and privilege audit and a disposable successor/recovery rehearsal establish what can be retired. PR #37 is historical evidence and is not an installation source.
