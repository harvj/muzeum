# Canonical membership and provenance acceptance

The production audit of v0.7.5 was read-only. Browser captures use disposable users and the retained MusicBrainz edition fixtures.

- [Desktop Release page](interpol-membership-desktop.webp)
- [Mobile Release page](interpol-membership-mobile.webp)

## Production diagnosis

Release 9, *Our Love to Admire*, had 11 base slots (128–138) from the [July 9 CD](https://musicbrainz.org/release/18484ef2-8dc4-30b1-8618-85950a374b1d). Catalog revision 189 established the initial sequence. Listener decision 24 resolved observation 293180 to recording 163, [Mind Over Time](https://musicbrainz.org/recording/2c1174e2-988b-484f-bfc9-c247cf9e46c5), with assessment 240. Catalog import 147 and release revision 206 retained that recording’s three exact spots as additional slots.

| Stored slot | Source edition | Position |
|---:|---|---:|
| 139 | [July 10 US digital](https://musicbrainz.org/release/aa66cd09-d320-48fc-97b4-19d256c82eae) | 12 |
| 140 | [July 10 digital, region unstated in the checked MusicBrainz data](https://musicbrainz.org/release/d7f505ba-5d4e-42aa-bd53-b0be58c2d72b) | 12 |
| 141 | [July 11 Japanese CD](https://musicbrainz.org/release/f4e04c18-2354-4362-a9db-c27753dd1717) | 12 |

Release revision 206 retained 39 additional appearances across 23 checked editions, which grouped to 24 distinct evidence entries. The old Release page rendered a union of the stored membership and those evidence entries. Only one distinct additional recording was admitted. The other 23 displayed entries, including CD-R instrumentals and Astoria recordings, had no canonical membership. The old checkbox endpoint could promote one of those entries to membership as a side effect of including it in listening totals.

There were no listening preferences for the release. Seven distinct base observations yielded 1,753,891 ms (29 estimated min). The sole effective *Mind Over Time* observation was excluded by default. Explicitly including it yields eight observations and 2,041,891 ms (34 estimated min), with one count for its observation across all three source slots. Release 9 was the only release with persisted additional slots at the audit. No invalid membership was identified and no production row correction was performed.

## Cross-source check

MusicBrainz verifies the same exact recording MBID in the Japanese CD and both digital appearances. Its release-group ID is 946e1aba-404a-3b0f-8cb4-3f12796a7d85. The named Japanese bonus-track designation is corroborated by the [Wikipedia track-list section](https://en.wikipedia.org/wiki/Our_Love_to_Admire#Track_listing), the [Japanese edition listing, TOCP-66683](https://www.cdjapan.co.jp/product/TOCP-66683), and the published track order. [Billboard’s June 2007 report](https://www.worldradiohistory.com/Archive-All-Music/Billboard/00s/2007/BB-2007-06-16.pdf) describes a separate iTunes bonus campaign. “Japanese bonus track” describes its place on that CD. It did not imply territorial exclusivity.

[Wikidata Q1422991](https://www.wikidata.org/wiki/Q1422991) identifies the album and points to the MusicBrainz release group. It lists July 10 as its album publication date. The checked MusicBrainz launch editions include July 9 CDs as well as the July 10 downloads and July 11 Japanese CD. Those claims stay scoped to their sources. Wikidata does not establish the exact audio or the Japanese slot.

## Regression coverage

- Resolving the actual *Mind Over Time* fixture writes only the 11 base tracks and the reviewed additional recording. The three appearances count as one when the listener includes it.
- The Release page lists only admitted recordings as listening choices. The collapsed source section preserves instrumental, live and other edition evidence and exposes a separate source-specific admission action.
- A listener can explicitly admit a checked track and separately include it in totals. The legacy source-only checkbox payload cannot admit a recording.
- Recording provenance uses exact MusicBrainz metadata and then bounded linked Wikimedia lookups. Wikipedia labels and revision/citation links supplement evidence. Admission, equivalence and listening accounting never consume these editorial notes.

Run the focused request, provider and browser checks with:

    bundle exec rspec spec/requests/canonical_workspace_spec.rb spec/services/canonical_catalog/import_spec.rb spec/services/recording_resolution/recording_provenance_spec.rb spec/services/recording_resolution/wikimedia_edition_context_spec.rb
    BROWSER_TESTS=1 bundle exec rspec spec/system/canonical_library_spec.rb -e 'only admitted Interpol tracks' -e 'authentic Queen of the Clouds'
