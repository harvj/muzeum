# Muzeum – Current State & Immediate Next Steps

## Current State (High Level)

- **Core ingest pipeline is complete**
  - Scrobbles → RecordingSurfaces
  - MusicBrainz search → ReleaseCandidates
  - Candidate selection → ReleaseIngestor
  - Canonical Artists / Releases / Recordings created correctly
  - Join models (ReleaseArtist, RecordingArtist, ReleaseRecording) handled

- **Edge cases are handled**
  - Video tracks are detected and skipped
  - Forced recording MBIDs supported when search yields no results
  - Digital / non-physical releases without media sections handled
  - Canonical recording selection no longer assumes title equality

- **Logging + specs are in a good place**
  - Ingest logging lives on RecordingSurface (JSON array)
  - ReleaseIngestor specs cover real-world behavior
  - ReleaseCandidates in specs are generated, not hard-coded

At this point, Muzeum *works*.
The remaining work is about **exposing it safely and usefully**.

---

## What’s Next

### A. Make Muzeum Deployable (Production-Ready but Safe)

**Goal:**
Deploy the app publicly without allowing accidental or unauthorized mutation.

#### 1. Public vs Admin Boundary
- Public routes:
  - View canonical Artists
  - View canonical Releases
  - View canonical Recordings
- Admin routes:
  - RecordingSurface management
  - MusicBrainz search
  - Candidate selection
  - Ingest actions

Admin actions should:
- Live under an `/admin` namespace
- Return `403 Forbidden` unless a valid admin token is present
- Be callable via header (`X-Muzeum-Token`) or query param

No users, no sessions, no auth system.

#### 2. Environment Setup
- Production environment variables:
  - `MUZEUM_ADMIN_TOKEN`
  - MusicBrainz client config
- App should boot and be usable read-only with *zero* configuration beyond DB

#### 3. Deployment Target
- Choose and configure hosting (Fly.io / Render / Railway / etc.)
- Ensure:
  - DB migrations run cleanly
  - Assets compile
  - Admin routes are gated in production

Outcome:
> Visiting `muzeum.fm` is safe.
> Only intentional actions mutate data.

---

### B. Start the Minimal UI

**Goal:**
A UI that lets *you* operate the system end-to-end while also defining how it will exist publicly later.

#### 1. Public UI (Read-Only)
Initial pages:
- Artist index + show
- Release show
- Recording show

Focus:
- Clarity over completeness
- Correct associations
- No admin controls visible by default

This establishes Muzeum as an *archive*, not a tool.

---

#### 2. RecordingSurface UI (Admin-Aware)

For a given RecordingSurface:
1. View surface details + ingest log
2. Run MusicBrainz search
3. View release candidates
4. Select a candidate
5. Trigger ingest

Same page for:
- Public viewers (see status only)
- Admin (controls appear when token present)

No separate admin UI.

---

#### 3. Admin Affordances (Subtle, Not Loud)

- Buttons and actions appear only when admin token is present
- No “login”
- No visual distinction beyond controls existing

Admin-ness is a *capability*, not an identity.

---

## Guiding Constraints

- Do not introduce users, roles, or permissions yet
- Do not split into multiple apps
- Do not hide the canonical data behind auth
- UI should reveal model shape, not obscure it

---

## Success Criteria

Muzeum is “there” when:
- It’s deployed
- You can open it in a browser
- Canonical data is browsable
- You can ingest new releases without touching the CLI
- Nobody else can accidentally do anything destructive

At that point, Muzeum stops being a project and starts being a place.
