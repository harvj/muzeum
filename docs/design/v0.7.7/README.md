# Blur discovery and release attribution

Production evidence was inspected read-only on v0.7.6. The desktop and mobile views use disposable data projected from checked MusicBrainz editions.

| Observation | Retained evidence | Corrected review |
|---|---|---|
| 293146 | Assessment 221 predates structured title interpretation. Its full-title search, punctuation fallback, and album query returned zero. It retained three complete Leisure editions with a track-one caption differing only in capitalization and apostrophe style after removing the mastering descriptor. | Recover track 1 from checked editions when indexed search is empty. The first-day US CD links recording `3f08ad45-0c00-436e-b737-80c137d4e081`. The Canadian CD and 2012 vinyl link `1c14202a-2ea7-4aff-bc41-6c97eb8a45e8`. Both exact IDs remain reviewable. |
| 293145 | Assessment 251 selected `a4f6872f-ff57-476c-8897-3ddc52d2169b`. Its exact-recording browse found track 14 on the UK Modern Life Is Rubbish mispressing `12625b09-8ea4-46d8-b4e3-b916e819e039`. The original-group traversal promoted that appearance into a proposal for first-day edition `32716c59-9347-4a32-aadb-ac46bdf27ead`, which does not contain that recording. | Track 12 of the first-day Leisure CD `dc2c22eb-9e48-4caa-8263-87c4cfe40a1a` remains in the primary 12-track review. The exact mispressing appears in a collapsed recording-provenance disclosure. Other candidates keep their own appearances. |

- [Wear Me Down desktop with provenance opened](wear-me-down-desktop.webp)
- [She’s So High mobile](shes-so-high-mobile.webp)
- [First-day Leisure CD](https://musicbrainz.org/release/dc2c22eb-9e48-4caa-8263-87c4cfe40a1a)
- [Mispressing source](https://musicbrainz.org/release/12625b09-8ea4-46d8-b4e3-b916e819e039)

A live artist and base-title search returned both She’s So High recording IDs among 38 indexed results. These recording identifiers do not establish the specific edition played or equivalence. Canonical confirmation remains manual.

```sh
bundle exec rspec spec/services/recording_resolution/blur_discovery_spec.rb
BROWSER_TESTS=1 bundle exec rspec spec/system/canonical_library_spec.rb -e 'selected Blur album'
```
