# Qualification evidence

This evidence records the result for source revision `f4e5aa959b2d5464a9a2c82508c8f514acddbe0b`. The commit on this evidence branch does not define a new release candidate.

The official signed Application Shell v2.0.0 preflight passed via Muzeum’s existing operator entry point. The signed adapter ran the executable checks, and the exact-candidate review records SH-08 route and service-isolation evidence. The shared mandatory pointer and adoption registry were left untouched.

- [Signed preflight output](signed-preflight.txt)
- [Exact-candidate Shell review](application-shell-review.json)
- [Full GitHub CI](https://github.com/harvj/muzeum/actions/runs/45725619221)
- [Disposable Capistrano staging and systemd boot](https://github.com/harvj/muzeum/actions/runs/45725696679)
- [Visual acceptance index](https://github.com/harvj/muzeum/blob/f4e5aa959b2d5464a9a2c82508c8f514acddbe0b/docs/design/v0.7.4/README.md)

The disposable rehearsal verified the v0.7.4-rc.1 seal `0fcaaf6f8b5193be1dfa54a53eb4f1b86d02b5242f211118057a9dfc79cf3649` through Puma and Solid Queue startup. Production staging, activation, and publication were not run.
