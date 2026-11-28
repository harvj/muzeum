# Birthday Resolution review and observation order

## Production diagnosis

The authenticated v0.8.0 page for observation 293137 showed eight matching
“Birthday - 2012 Remaster” Last.fm observations. The candidate view proposed the
August 26, 1991 US edition as “Original release.” Its default construction chose
the edition matching the release-group first date. Release configurations and
independent release proposals had been implemented in separate catalog and
Evidence interfaces. Their integration did not replace that construction.

A read-only query found assessment 286 under `workspace-evidence-v2`. It already
retained the complete UK, September US and Japanese editions and the disputed
August US edition. It contained no additional-recording publication review.
There was no canonical Leisure parent. Availability of checked album source
tracklists and completeness of adjacent-recording investigation are distinct
facts. The deployed source itself matched v0.8.0.

## Corrective review

- Reviewed configuration alternatives are available on Candidates. Birthday
  confirmation applies to the eight matching observations independently of
  album admission or listener configuration selection.
- The disputed August US source remains accessible as evidence.
- Reviewed source leads trigger bounded edition checks for “She’s So High,”
  “There’s No Other Way,” and “Bang.” Each needs complete provider slots and
  an exact recording intersection. Uncertain audio identities stay separate.
- Older interpretation can be refreshed without discarding the displayed
  assessment. Valid album sources are reused. The documented failed “Won’t
  Do It” appearance browse is retried independently of successful edition
  lookups. An exact-source replay covers an HTTP 503 and the selective retry.
- All individual observation tables use the original `played_at` timestamp,
  newest first, then ID descending as a deterministic tie-breaker. Archive,
  public profiles and release details already used this order. Resolution
  matching observations and private recording detail now share their
  chronological cursor. Plot and timeline directions are unchanged.

## Browser evidence

The browser captures replay the catalog-only production assessment and the
same route ID. Source claims and the eight-observation scope are preserved;
timestamps and listener identities in the replay are disposable.

| Layout | v0.8.0 replay | Corrected review |
|---|---|---|
| Desktop | [Before](birthday-before-desktop.png) | [After](birthday-after-desktop.png) |
| Mobile | [Before](birthday-before-mobile.png) | [After](birthday-after-mobile.png) |

```sh
bundle exec rspec spec/requests/resolution_release_review_spec.rb spec/requests/observation_order_spec.rb
BROWSER_TESTS=1 bundle exec rspec spec/system/birthday_release_review_spec.rb
```
