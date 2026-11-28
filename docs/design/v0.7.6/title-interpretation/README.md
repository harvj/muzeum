# Structured recording title interpretation

The disposable Resolution fixture reproduces the reported title from observation 293145. The exact-title search returns no hits in the test. The artist and base-title search then returns [Wear Me Down](https://musicbrainz.org/recording/a4f6872f-ff57-476c-8897-3ddc52d2169b). The retained [US Leisure edition](https://musicbrainz.org/release/d81bfb74-5d2e-4dcf-956f-550cfde5eed5) establishes track 12. MusicBrainz also documents a [2012 digital edition](https://musicbrainz.org/release/b59d1131-4a58-4648-b9dd-b78b8f9c80fd). The fixture makes no claim about the specific edition played.

- [Desktop Resolution](wear-me-down-interpretation-desktop.webp)
- [Mobile Resolution](wear-me-down-interpretation-mobile.webp)

The original observation remains in the heading. The disclosure explains the remaster interpretation and catalog candidates remain separate choices.

```sh
bundle exec rspec spec/services/recording_resolution/title_interpretation_spec.rb spec/services/recording_resolution/provider_cache_spec.rb
bundle exec rspec spec/system/canonical_library_spec.rb -e 'reported Blur title'
```
