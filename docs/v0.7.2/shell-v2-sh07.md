# Application Shell v2.0.0 release identity

Muzeum v0.7.2 starts from published v0.7.1 at `73d06e785e4dd673f9088650b75c406fdbf2c4c3`. Infrastructure records Muzeum and the mandatory minimum on Shell 1.3.0. The independently signed [Shell 2.0.0 manifest](https://infrastructure.harvj.com/versions/2.0.0/manifest.json) binds the SH-07 fixture used in the tests. The [Infrastructure adoption guide](https://github.com/harvj/infrastructure/blob/main/docs/application-shell-v2-adoption.md) describes explicit candidate qualification.

## Lifecycle

[Remote Gaming v0.4.6](https://github.com/harvj/remote-gaming/tree/da47452cb32ba8b03b1851335d01aef94a057461) packages an archive, verifies its revision and digest, pins the boot-time identity, and reads the matching local publication receipt. Its final tag and release asset have to identify the accepted artifact. Retained candidate and published deployments read their own receipts on recovery.

Muzeum uses the existing Capistrano staged tree after asset compilation. It hashes regular file contents, paths and executable bits in a stable order. Approved shared runtime symlinks are represented by their paths. Identity metadata is detached from that digest. A deploy-owned ledger allocates a positive RC number per target version. Retrying the same source and digest reuses its number. Changing packaged bytes, even at the same source commit, allocates another number. The packaged `VERSION` and `REVISION` must agree with the selected version and revision.

| Running state | Footer |
| --- | --- |
| Local development | `Muzeum v0.7.2-dev`, from the checkout's VERSION |
| Packaged candidate | `Muzeum vX.Y.Z-rc.N` |
| Verified acceptance and publication for that artifact | `Muzeum vX.Y.Z` |
| Retained release predating artifact identity | Existing revision-bound release metadata |

The existing GitHub Deployment outbox associates the approval's source SHA and the packaged artifact. Its production success status contains the artifact digest and candidate label after the running tree matches and the protected workflow completes. Publication must resolve the final tag to that SHA and include the exact packaged identity as the GitHub release asset `muzeum-artifact.json`. The existing `muzeum:sync_release[vX.Y.Z,DEPLOYMENT_ID,STATUS_ID]` verifies the source, acceptance, asset digest and publication chronology. It atomically installs an immutable local receipt for that artifact. This reuses the local authenticated GitHub CLI and keeps GitHub credentials off the server.

The next page render sees the receipt without a restart. There are no publication requests during rendering. A failed sync is retried through the same command, with bounded operator backoff. A mismatch leaves the previous receipt alone. Existing in-process and persisted verified state survive a publisher outage. A compatible, separately authorized restore of a retained artifact reads that artifact's own receipt. A still-running process keeps the release identity it resolved at boot even when the activation symlink moves.

## Qualification status

The matching SH-07 fixtures, miniature package tests, disposable Capistrano hooks and Rails footer requests exercise development and RC labels, digest binding, same-process publication, stale or contradictory evidence, and candidate and published recovery. Full Shell v2 adoption still needs the other checks from the v0.7.1 review, including the session and Site Art gaps. Before requesting production approval, qualify the exact adopting artifact and exercise this lifecycle with the operator's retained Capistrano configuration. Its integration uses the same `MuzeumReleaseIdentityTasks` package, verify and sync steps. Apply those steps in the existing staging, acceptance and sync call sites, without copying its deployment workflow or changing the installed production helpers.

## Writable runtime files

Capistrano links the entire release `tmp` directory to Muzeum's existing
`shared/tmp`. The shared directory retains the existing `pids` and `sockets`
subdirectories. Rails and Bootsnap use their ordinary paths, so web, Solid Queue,
and maintenance processes resolve their caches and temporary files outside the
sealed tree. The packager requires that exact symlink and still hashes
application files, their executable bits, compiled assets, and release metadata.
Runtime writes to the existing shared storage and log directories also stay
outside the artifact.

In the operator Capistrano configuration, mirror the same linked directories
and create `shared/tmp/pids`, `shared/tmp/sockets`, and `shared/tmp/storage`
before linking. The tracked-file comparison skips the three empty-directory
sentinels under `tmp` after validating the symlink. The protected backup,
migration, and recovery commands are unchanged.
