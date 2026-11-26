# Exact-source qualification evidence

Candidate source `9a5e658f5ebfdf2d37077a60c4c2a445935535db` (v0.7.5-rc.1). This evidence branch does not change the application candidate.

- [Signed Application Shell v2.0.0 preflight](signed-preflight.txt) passed using the [candidate-bound review](application-shell-review.json). The selected and operator-adopted version are 2.0.0. The shared mandatory pointer and registry were not changed.
- [Disposable Capistrano rehearsal](https://github.com/harvj/muzeum/actions/runs/45731794085) staged v0.7.4 and the candidate, booted Puma and Solid Queue, and verified the candidate seal before and after startup. Disposable artifact SHA-256 `479bb46261a9741295ae2abab8ab789799e15e9f545570621e63d297cefb30d7`.
- [Exact-source GitHub CI](https://github.com/harvj/muzeum/actions/runs/45731633151). Local Rails and Chrome suite passed, 388 examples and zero failures.
- [Three-case visual acceptance and detail timing](https://github.com/harvj/muzeum/blob/9a5e658f5ebfdf2d37077a60c4c2a445935535db/docs/design/resolution-provenance/README.md).

There are no schema changes. Production activation, publication, and canonical writes were outside this qualification.
