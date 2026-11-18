# P1.3a provider contracts and verification

## MusicBrainz

The adapter uses recording search, recording lookup and edition lookup. Search phrases escape quote and backslash and omit the source album from discovery. The consumer keeps the search envelope and treats a truncated page as incomplete. It supports offsets; the pilot reads one page per group to bound requests. The lookup verifies the reported recording MBID with a direct request, handles missing IDs, and follows one validated same-host HTTPS recording redirect. Edition evidence includes the edition and release-group identifiers, country and partial date, and the medium and track slots with their nested recording MBIDs. Public metadata reads use no credentials. [MusicBrainz API](https://musicbrainz.org/doc/MusicBrainz_API) · [Search parameters](https://musicbrainz.org/doc/MusicBrainz_API/Search)

A shared PostgreSQL budget spaces MusicBrainz requests by at least one second. The transport identifies Muzeum, bounds connection/read/write waits, and honors 429/503 and Retry-After (seconds or HTTP date). Transient failures enter bounded durable retry. A 404 for a claimed recording is missing evidence. The pilot caches validated MusicBrainz documents for up to one day and records the request parameters, retrieval timestamp and projection digest behind each assessment. [MusicBrainz rate limiting](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting) · [Data licensing](https://musicbrainz.org/doc/MusicBrainz_Database/License)

## Discogs

The adapter supports release and artist search, release lookup, master and paginated versions on the official catalog API. It projects ordered list entries, positions, nested subtracks, artist credits, country and chronology. The pilot uses relevant release search and track-list evidence, reports an incomplete result when it cannot isolate a release, and records corroboration or contradiction with typed release/master IDs, match count, and available country/year comparisons. Discogs identifiers stay distinct from MusicBrainz recording IDs.

Catalog requests use the application key and secret in the Authorization header and an identifying User-Agent. A public catalog integration needs no user OAuth. Muzeum's initial spacing is three seconds per request, with a shared cooldown on throttling or exhausted remaining quota. The developer portal returned HTTP 403 to the documentation browser, so confirm the published endpoint limits and auth method before enabling live access. [Discogs developer reference](https://www.discogs.com/developers/)

The projected cache expires after 30 minutes. It excludes images, marketplace data, collection/wantlist data and raw API responses. The append-only assessment stores the comparison outcome, provider object references and a provenance digest. It does not retain the Discogs catalog payload. There is no catalog display in P1.3a. Before a future display uses Discogs content, retrieve fresh data, suppress stale results on refresh failure, add the terms' prominent non-affiliation notice, and place a linked **Data provided by Discogs** credit beside applicable data with the required link behavior. Preserve only the minimum content needed for the service, within the applicable retention limits. [Discogs API terms](https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use)

### Protected credential setup

For a disposable development/staging worker, the operator should install `DISCOGS_CONSUMER_KEY` and `DISCOGS_CONSUMER_SECRET` in its existing protected environment configuration. For future approved production use, Muzeum's established worker reads `/var/www/muzeum/shared/.env`, owned by `muzeum` and mode 0600. Leave production configuration alone for this pilot. Use the environment's secret manager or a protected local file outside the checkout. The following Bash subshell installs a new development-only file and reads both values without terminal echo or command-line arguments.

```bash
(
  set -e
  umask 077
  set -o noclobber
  read -rs -p 'Discogs application key: ' discogs_key </dev/tty
  printf '\n' >/dev/tty
  read -rs -p 'Discogs application secret: ' discogs_secret </dev/tty
  printf '\n' >/dev/tty
  [[ $discogs_key =~ ^[a-zA-Z0-9]+$ && $discogs_secret =~ ^[a-zA-Z0-9]+$ ]]
  printf 'DISCOGS_CONSUMER_KEY=%s\nDISCOGS_CONSUMER_SECRET=%s\n' \
    "$discogs_key" "$discogs_secret" > "$HOME/.muzeum-discogs-pilot.env"
)
```

Run this in a shell with tracing off. Have the worker process load the file as environment variables using the approved launcher or with `set -a; source "$HOME/.muzeum-discogs-pilot.env"; set +a` in its startup shell. Never share the file or include values in logs, Git, task arguments, chat or fixtures. For authorized live validation, use an explicit one-observation disposable archive and start the normal pilot with `LIVE=authorized`. Confirm the request succeeds and the assessment retains the Discogs comparison. The [first live pilot](live-provider-pilot-2026-11-17.md) verified authenticated catalog search. Paginated results prevented live release-detail comparisons in that sample.

## Assessment rule and regression coverage

The proposed rule needs a verified source track claim, exact title and concatenated ordered artist credit, agreement with any reported artist MBID, an identified matching edition with complete media track lists and a slot for that recording. It abstains for an unverified claim, competing versions, incomplete lookup/search evidence, version markers and Discogs contradiction. Discordant edition country/year comparisons are recorded as context. Neither provider popularity nor text similarity is sufficient. If Discogs has no matching edition, MusicBrainz evidence can still yield a suggestion. A temporary Discogs failure defers the combined investigation. Approval of production acceptance requires a reviewed validation corpus and separate authorization.

Focused specs exercise exact tuples, later arrivals, protected overrides, revocation and privacy, ledger constraints, provider response shapes and headers, ambiguity and redirects, retry, lease contention and reclamation, immutable source rows, keyset bounds and replay. RSpec blocks external provider requests. The disposable migration rehearsal and isolated Solid Queue smoke test are described in the [implementation report](README.md).
