# Qualification evidence

This evidence records the result for source revision `5779b79ed8d10f39f056fff04f3f13ce309e4d94`. The commit on this evidence branch does not define a new release candidate.

The official signed Application Shell v2.0.0 preflight passed via Muzeum’s existing operator entry point. The signed adapter ran the executable checks, and the exact-candidate review records SH-08 route and service-isolation evidence. The shared mandatory pointer and adoption registry were left untouched.

- [Signed preflight output](signed-preflight.txt)
- [Exact-candidate Shell review](application-shell-review.json)
- [Full GitHub CI](https://github.com/harvj/muzeum/actions/runs/45723067358)
- [Disposable Capistrano staging and systemd boot](https://github.com/harvj/muzeum/actions/runs/45723242163)
- [Visual acceptance index](https://github.com/harvj/muzeum/blob/5779b79ed8d10f39f056fff04f3f13ce309e4d94/docs/design/v0.7.4/README.md)

The disposable rehearsal verified the v0.7.4-rc.1 seal `505dd634f0d89b669a0eb647ada28726a35ad900c024cbf80cf0e12c56d93e18` through Puma and Solid Queue startup. Production staging, activation, and publication were not run.
