# v0.7.0 implementation review

This branch builds on the published v0.6.10 artifact. It is a milestone review branch.

## Production regression audit

Production was inspected in read-only transactions. Public MusicBrainz checks ran outside production. The audit created no production observations, assessments, or requests.

| Example | Finding |
| --- | --- |
| Queen of the Clouds, 293095 | Assessment 147 retained 31 appearances and four same-day sequences of 16, 17, 19, and 20 tracks. The 20-track worldwide edition includes “Out Of Mind - Bonus Track.” Its first 16 tracks differ from the Canadian 16-track edition at track 16, so prefix comparison alone cannot establish the base. The Canadian edition has an explicit label, and both list September 24, 2014. The evidence still warrants a sequence choice. |
| Lady Wood, 293072 | Assessment 58 retained separate clean and explicit MusicBrainz candidates. This completed assessment lacks recording-first publication or checked construction evidence. |
| Lady Wood, 293087 | Assessment 37 retained clean, explicit, remix, and other versions. It records competing recordings, an unresolved version, and an unverified edition slot. It lacks recording-first publication or checked construction evidence. A separate public browse returned 49 explicit-recording appearances in two pages and nine edition references for the album group. |
| Walk ’em With Grace, 293004 | Request 73 had finished in state `imported` with zero retries. Assessment 149 retained two plausible recording MBIDs and checked original *There Are Rules* editions. The persisted result does not indicate an active queue or future retry. |
| Narrow Stairs, 293082 | Assessment 125 retains May 13, 2008 album evidence and separate later, compilation, and single appearances. The existing 11-track fixture and confirmation regression protect the original sequence and the one-release admission boundary. |
| Guilt Show | The provider fixture retains the 13-track original. The later Japanese addition is shown separately. A resolved addition contributes to this release's totals only after inclusion. |

MusicBrainz lists both explicit recording IDs in the official October 28, 2016, 12-track US CD. The clean versions have a separately labeled digital appearance. The explicit “Don’t Talk About It” release browse returned HTTP 503 during the audit, so this is corroboration of album membership and a diagnostic lead for replay. [Official US CD](https://musicbrainz.org/release/e3f12607-2004-448a-9a6a-421a8a59ee9b) · [Provider release history](https://musicbrainz.org/artist/56756959-1e78-429c-b897-e1d056cb0225/releases)

## Collection evidence and status

The existing client follows MusicBrainz pagination within its result bound and reuses the shared provider cache. Recording-first investigation verifies the original candidates, then checks dated official edition details within the existing comparison limit and records which edition IDs were verified or remain unchecked. Original selection still uses the established launch-date, verified sequence, and representative-edition rules. A first-publication compilation without another supported original context remains outside this construction path. A materially different plausible launch sequence stays a choice. The selection changes the visible tracklist and write preview, while the existing transaction revalidates the approved edition and writes at most one release.

Known additional tracks remain in edition evidence even if they are outside the narrow catalog admission. Release pages group their retained edition links in a collapsed section and link recordings only when the release already has a canonical membership for them.

The worker sends a Turbo refresh when it claims or finishes investigation work. Status is read from the persisted request and lease. A retry badge requires a matching Solid Queue scheduled execution. The manual refresh link and subsequent page loads read durable state after a missed broadcast. The UI does not report a more detailed processing phase than the worker currently persists.

### Representative sequence and source identity

Previously the ordered recording MBID array defined sequence equality and prefix matching. Any additional slot with a different recording MBID was counted as an addition. The representative release fingerprint reconstructed source IDs from the current canonical recording, so it would fail verification if a slot later pointed to a canonical record with another MBID.

The comparison now has equivalent, different, and uncertain outcomes. Equivalent alternate source IDs require compatible title, credit, duration and version evidence plus corroboration from a shared ISRC or a shared track MBID. Uncertain look-alikes remain inspectable and do not become additional memberships. A competing sequence remains selectable if the musical difference is meaningful or the available evidence cannot establish equivalence. The exact selected edition supplies every base slot.

The Queen of the Clouds regression replays three retained editions. The September 24 and September 30 Canadian 16-track editions carry the exact same recording sequence. The worldwide edition shares its first fifteen recording IDs but inserts “Love Ballad” at 16, moves the same Hippie Sabotage remix to 17, and adds three further tracks. The source evidence supports a real choice between those programs. [Worldwide MusicBrainz edition](https://musicbrainz.org/release/1f21b9a1-0b81-4f3b-8b1b-3ff9e44a91ae)

## Listening policy and migration

The approved STAT-003 revision defaults to base memberships and leaves additional tracks outside release totals until the listener includes them. The latest user, release, and recording decision takes precedence. The release detail, combined histories, catalog index totals, and artist release ranking totals use the same counted-membership query. Membership visibility, per-recording counts, and release-ranking eligibility are independent of the decision.

Migration `20261123230000` adds an empty append-only decision table with three foreign keys and a lookup index. It has no backfill. Existing rows retain their values. Application rollback can keep the table and the preferences, although v0.6.10 displays its previous all-membership totals until a compatible release is restored. A disposable database replayed all migrations and applied, reversed, and reapplied the new migration. The v0.6.10 app booted and read the upgraded schema. Production migration still requires the existing hash-matched review and backup/recovery qualification.

Migration `20261123231500` adds nullable source recording MBID, duration, and credit columns to existing slots. New slots retain exact provider data. Older slots keep the prior recording-MBID fallback for fingerprint verification, with no guessed provenance or backfill. Older app versions can read the additive schema.

## Open

- **Provider recording equivalence.** Muzeum currently identifies a canonical recording by one MusicBrainz MBID. Distinct provider IDs remain distinct candidates, with the source's clean or explicit description visible. A revisable mapping needs to bind source MBIDs to a canonical recording while preserving each slot's source recording identity. The new per-slot source identity preserves verified fingerprints independently from the canonical pointer. A future mapping still needs an append-only source-identity decision with transactional lookup and confirmation-plan revalidation. Existing confirmed canonicals and decisions should remain intact.
- Full original-edition adjudication for *Queen of the Clouds* and new bounded replays for the *Lady Wood* observations still require verification. The retained production assessments establish the prior evidence gap, while they do not establish a fresh provider result.
- A connected browser receives worker refresh broadcasts. Reopening or manually refreshing reconstructs missed outcomes. Automatic reconnect catch-up and explicit engineering-failure classification have no qualification evidence yet.
