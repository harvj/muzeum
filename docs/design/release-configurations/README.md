# Blur’s Leisure release configurations

Evidence captured for the v0.7.7 product baseline. [Ordered source tracklists](tracklists.json) retain the exact release, track and recording MBIDs by medium and position. [Recording-first bonus browse](bonus-recording-browse.json) retains the returned exact-recording appearances and distinguishes browse claims from checked slots. No catalog admissions follow from this research.

| Configuration | Checked program | Source |
|---|---|---|
| UK album | 12 tracks. “Bang” is second, “Sing” sixth and “There’s No Other Way” seventh. The band shop, Wikipedia and Wikidata place the original UK album in August 1991. MusicBrainz dates this specific CD August 27, one day after the reported launch. | [GB CD](https://musicbrainz.org/release/d550f756-9e71-3e6b-8492-84a37154c10f) · [Blur shop](https://shop.blur.co.uk/products/leisure-cd) · [Wikidata Q832560](https://www.wikidata.org/wiki/Q832560) |
| September US album | 12 tracks. “There’s No Other Way” moves to second and “Bang” to third. “I Know” occupies slot 4 and “Sing” is absent. All 11 shared track captions point to the same exact recording IDs as the checked UK CD. | [US CD, September 24, 1991](https://musicbrainz.org/release/d81bfb74-5d2e-4dcf-956f-550cfde5eed5) · [Editorial chronology and cited track lists](https://en.wikipedia.org/wiki/Leisure_(album)#Track_listing) |
| Japanese album | 15 tracks. The three additions are “I Know” (4), “Inertia” (11) and “Mr. Briggs” (12). “Sing” remains in slot 8. All 12 shared track captions point to the same exact recording IDs as the checked UK CD. The September US and Japanese CDs share the 3:33 “I Know” recording ID. | [Japan CD, September 20, 1991](https://musicbrainz.org/release/9ab639ba-9ad7-4128-9ba2-c5d607f56156) · [Later Japanese pressing and its three bonuses](https://www.cdjapan.co.jp/product/TOCP-54072) |
| 2012 anniversary | European vinyl and worldwide 12-track digital preserve the UK order and recording IDs. The European deluxe CD couples that program with 16 bonus tracks. The checked Japanese 2-CD edition adds “High Cool” (dub) as its seventeenth bonus. | [European vinyl](https://musicbrainz.org/release/2d855ad9-fbd5-4f73-86a1-949302680df6) · [Worldwide digital](https://musicbrainz.org/release/b59d1131-4a58-4648-b9dd-b78b8f9c80fd) · [European 2-CD](https://musicbrainz.org/release/5834ce7b-007f-4e47-84bb-b4b66a6bdabf) · [Japanese 2-CD](https://musicbrainz.org/release/fbeb5683-34f1-4192-93e8-38217598ba03) |

The separately indexed [August 26 US CD](https://musicbrainz.org/release/dc2c22eb-9e48-4caa-8263-87c4cfe40a1a) lacks “Repetition” and retains “Sing.” Seven comparable captions carry different recording MBIDs from the UK CD, and its “I Know” is a different catalog ID and duration from the September US and Japanese CD slot. The evidence does not establish whether every differing ID denotes a distinct performance. Keep this source separately reviewable. Its date alone cannot settle the conventional US configuration. Also keep the label’s [2013 Japanese SHM-CD program](https://wmg.jp/blur/discography/11150) separate from the 2012 2-CD edition.

## Adjacent programs

- The [October 1990 She’s So High single](https://musicbrainz.org/release/b11e8000-f0c2-4277-befb-b125a5edece7) provides exact slots for “I Know” (extended) and “Down.” The September US and 1991 Japan album “I Know” slot has a different exact ID.
- The [April 1991 There’s No Other Way single](https://musicbrainz.org/release/ea3df91a-d85f-435c-8c75-c0a5494e662c) provides exact slots for “Inertia,” “Mr. Briggs,” and “I’m All Over.” Editorial bonus notes also associate the extended title track, the remix, “Won’t Do It,” and the live “Day Upon Day” with the single campaign. Some exact reissue IDs only show 2012 appearances in the returned browse. Retain the earlier editorial relationship as a lead with identity unverified. [Bonus disc notes](https://en.wikipedia.org/wiki/Leisure_(album)#Track_listing)
- The [July 1991 Bang single](https://musicbrainz.org/release/7916ce29-57d6-40d8-b046-016a0a5f4417) verifies the extended “Bang,” “Explain,” “Luminous,” and “Uncle Love.” Editorial sources also place “Berserk” in the campaign, while the exact deluxe ID’s dated official browse begins in 2012. [Bonus disc notes](https://en.wikipedia.org/wiki/Leisure_(album)#Track_listing)
- The [February 1998 M.O.R. edition](https://musicbrainz.org/release/3f369479-72b3-4bb1-9f36-456bd2ec96b0) contains the exact “I Love Her” demo. The [November 1998 Close single](https://musicbrainz.org/release/955eefe1-ff4c-42d4-9316-e35e81705e1b) contains the exact “Close.” These are documented appearances; fan-club provenance is useful context but does not prove when the recordings were first issued. [2012 edition annotation](https://musicbrainz.org/release/5834ce7b-007f-4e47-84bb-b4b66a6bdabf)
- The exact “High Cool” dub browse finds the 2012 Japanese package and box-set context. An earlier independent release has not been established. “Won’t Do It” is present on the verified anniversary disc; its exact-recording browse returned HTTP 503 during the sampled attempts.

Sixteen of 17 exact bonus recording browses returned all entries in the provider's reported first page. That is coverage of the current index, not a claim of exhaustive discography. Only linked complete source editions in the tracklist projection have verified exact slots. Work/recording relationship traversal, unverified single variants and the provider outage case remain open for implementation and acceptance.

## Implementation acceptance

- [Desktop, September US configuration](leisure-desktop.png)
- [Mobile, September Japan configuration](leisure-mobile.png)
- The request specs replay the checked UK, September US, Japanese and anniversary source sequences. They exercise the September 1991 filter, selection history, restored totals after switching back, duplicate recording slots, listener isolation and explicit admission of the checked UK “She’s So High” single.
- The Chrome example uses a disposable listener and catalog, selects source configurations through the disclosure, and checks the resulting tracklists and September filter at desktop and mobile widths.
- The August US date and recording-relationship gaps remain source uncertainty. “Won’t Do It” still has no completed browse in the research sample. Selection does not assert the edition heard. Same-group siblings remain pending unless a distinct program is demonstrated.

```sh
bundle exec rspec spec/requests/release_configurations_spec.rb
BROWSER_TESTS=1 bundle exec rspec spec/system/canonical_library_spec.rb -e 'switches verified Leisure configurations'
```
