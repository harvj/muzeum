# Muzeum v0.7.6-rc.1 qualification

Source revision `5f4a6e83303e724904dd9a273b1809d35983c4b6`.

- [Exact release CI](https://github.com/harvj/muzeum/actions/runs/45756954923)
- [Disposable Linux Capistrano staging and systemd rehearsal](https://github.com/harvj/muzeum/actions/runs/45756980201)
- [Title interpretation desktop and mobile](../title-interpretation/README.md)
- [Listening History visual acceptance](../README.md)

The live MusicBrainz exact query for Blur's `Wear Me Down - 2012 Remaster` reported zero candidates. The artist plus base-title query returned five results, including the album recording `a4f6872f-ff57-476c-8897-3ddc52d2169b`, three live recordings, and a demo. The retained MusicBrainz fixture verifies track 12 on the US CD of [Leisure](https://musicbrainz.org/release/d81bfb74-5d2e-4dcf-956f-550cfde5eed5). The observation's mastering text is search context. The specific edition played is unverified.

The staged artifact inventory was verified following Rails maintenance, Puma and Solid Queue boot, authenticated Archive, catalog and Resolution requests, and a disposable same-process RC-to-final footer test. The candidate introduces no database migrations.

The [catalog evidence projection](blur-release-evidence.json) records the identical recording MBID in three distinct track slots, including track 12 on the [12-track first-day US CD](https://musicbrainz.org/release/dc2c22eb-9e48-4caa-8263-87c4cfe40a1a) and track 12 on the [2012 digital edition](https://musicbrainz.org/release/b59d1131-4a58-4648-b9dd-b78b8f9c80fd). These are separate release appearances of the same catalog recording.

The complete local Rails and Chrome suite passed 404 examples. The sealed disposable artifact SHA-256 is `53f0702749451dbc12b53d23006621493b29faee3feb87d726cfc5760fc65e5d`.

Exact-SHA CI passed Rails and Chrome, disposable migration replay and recovery, zeitwerk, production asset compilation, Capistrano validation, Brakeman, RuboCop, and Bundler Audit. The signed Shell v2.0.0 verifier passed all ten checks, including [executable SH-08](sh08-executable.json), and [operator preflight](signed-preflight.txt) accepted the [exact review](application-shell-review.json). [The qualification result](application-shell-ci.json) records review SHA-256 `121367114af6f574b0e68bb0ecfaf94404538239986674bdce6a422f36794be0`.

Repository selection and adoption configuration specifies v2.0.0. The signed registry still reports Muzeum at v1.3.0 and v1.3.0 as the shared mandatory version. The signed verifier accepted explicit v2.0.0 selection. No production deployment, publication or pointer change was performed.
