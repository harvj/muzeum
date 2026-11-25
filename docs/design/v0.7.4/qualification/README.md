# Qualification evidence

This evidence records the result for source revision `9d52918453b3e04f4559b2a671bbadbe401a9625`. The commit on this evidence branch does not define a new release candidate.

The official signed Application Shell v2.0.0 preflight passed via Muzeum’s existing operator entry point. The signed adapter ran the executable checks, and the exact-candidate review records SH-08 route and service-isolation evidence. The shared mandatory pointer and adoption registry were left untouched.

- [Signed preflight output](signed-preflight.txt)
- [Exact-candidate Shell review](application-shell-review.json)
- [Full GitHub CI](https://github.com/harvj/muzeum/actions/runs/45723904500)
- [Disposable Capistrano staging and systemd boot](https://github.com/harvj/muzeum/actions/runs/45723934586)
- [Visual acceptance index](https://github.com/harvj/muzeum/blob/9d52918453b3e04f4559b2a671bbadbe401a9625/docs/design/v0.7.4/README.md)

The disposable rehearsal verified the v0.7.4-rc.1 seal `0db8b18460d9d727ede79b95e0715a9d22fb8a476d1820ae8a9a63bbfa12baae` through Puma and Solid Queue startup. Production staging, activation, and publication were not run.
