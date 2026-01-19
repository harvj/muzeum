### Clients boundary

External system adapters live under:

app/clients/clients/*

This is required so Zeitwerk can map:

Clients::Lastfm
Clients::Musicbrainz

without colliding with provider namespaces such as:

Lastfm::Importer

Clients contain:
- HTTP / I/O only
- No persistence
- No orchestration
- No domain decisions

All workflows live in services.
