# Muzeum agent instructions

Muzeum is a Rails 8 application with its own independent production deployment. Before proposing or implementing work, read **docs/roadmap.md** and the authoritative product specifications in **docs/domain/**:

- [Principles](docs/domain/principles.md)
- [Recording resolution](docs/domain/recording-resolution.md)
- [Release assignment](docs/domain/release-assignment.md)
- [Listening statistics](docs/domain/listening-statistics.md)

## Authority and change discipline

1. The domain documents define intended product behavior; they do not imply a feature has already shipped. Dated P1.0 proposals are historical, especially their superseded local-password design. Existing production source immutability, Auth OIDC and recovery contracts remain binding.
2. When requirements are uncertain, record an **Open** question rather than silently inventing thresholds, album cutoffs, provider semantics or identity equivalences. Propose a concrete decision to the operator when needed.
3. If a requested implementation would contradict a domain rule, explicitly flag the conflict and seek a policy revision first. Update affected domain documents, examples, tests and numbered roadmap together when a decision is revised; preserve revision history in Git.
4. Keep source observations separate from canonical interpretation and from derived statistics. Do not change immutable Last.fm evidence or overwrite user decisions. Treat source account associations as public archive access, not proof of ownership.
5. MusicBrainz and Discogs supply evidence; Muzeum owns the resolution policy. Spotify lookup and playlist export are deferred. Do not let provider outages block ingestion.
6. The primary user experience is canonical artists, releases and recordings, not raw scrobbles. Release membership controls visibility; per-play credited release controls disjoint release rankings. Explicit user overrides take precedence over automated reassessment.
7. Prefer measured near-term needs over speculative 10,000-account architecture. Preserve simple, safe paths to later scaling.

## Engineering and deployment

- Maintain independently deployable Muzeum web/worker/services. Never restart, redeploy or disrupt CE, Auth, Remote Gaming or other applications as a side effect.
- Preserve existing auth.harvj.com OIDC login, single identity/MFA, scoped access, and current operational security boundaries. Do not add local passwords or alternative identity mechanisms.
- All timestamps are stored in UTC and presented in browser-local time.
- Use Rails-native/Hotwire interfaces and retain Muzeum's limestone/onyx environmental design and shared harvj navigation conventions. The legacy Muzeus repo is a one-time UI reference, not a code or data migration source.
- Make relevant small legibility improvements without widening milestone scope.
- Keep the canonical roadmap numbered and current. Only the next 2–3 milestones should be treated as relatively firm.
- Run appropriate tests, security checks and CI; report outcomes and meaningful limitations. Production schema changes require hash-matched reviewed additive migrations, fresh encrypted backup and isolated four-database recovery evidence. Preserve original source and interpretation history.
- **Never deploy, restart production services, enable a new scheduler, or create a GitHub release without explicit authorization.** An operator invocation of `cap production deploy` authorizes its reviewed code and ordinary additive migrations; agents must not infer deployment authorization from an implementation request. Commit/push only when requested; report exact SHAs.
- Routine deployments use **`cap production deploy`**, with a clean synchronized local `main`, exact-SHA passing CI, Muzeum-only lock/preflight, automatic reviewed migrations, conditional backup/recovery, and readiness verification. Follow [the deployment workflow](docs/deployment/workflow.md); do not assemble environment approval flags. Destructive data migrations, live restoration, credential rotation, shared-infrastructure changes and privileged-helper changes require separate review/authorization. Never automatically reverse migrations, restore over live data, or fall back to an incompatible release.
- P1.2 was deployed at `8942bc41ae76f3c4e3d63a20552b0541c5cd3412`; [deployment evidence](docs/p1.2/deployment-2026-11-17.md). P1.1 is an unsafe functional rollback target after source-account cutover. The new deployment automation is **not installed/deployed** and requires separate safety review before production use. Documentation-only changes do not authorize deployment.
