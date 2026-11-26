# Muzeum v0.7.7-rc.1 qualification

- Source `824893b334fcccbe00ddab093339f1772f867e89`
- Disposable sealed artifact SHA-256 `d9bd1407acb0b7015c4b5a3075c631a85ca663241ce928d65a542483697c040f`
- [Exact-SHA release CI](https://github.com/harvj/muzeum/actions/runs/45766941804)
- [Isolated Linux Capistrano and systemd staging](https://github.com/harvj/muzeum/actions/runs/45767000840)
- [Signed Shell v2.0.0 result](application-shell-ci.json) and [exact review](application-shell-review.json)
- [Artifact-bound SH-08](sh08-executable.json) and [accepted preflight](signed-preflight.txt)
- [Blur findings and browser screenshots](../README.md)

The local Rails and Chrome rerun passed 407 examples. The initial run lost its ChromeDriver connection before exercising the Guilt Show test. The focused retry and full rerun passed. The disposable seal remained valid across maintenance, Puma and Solid Queue startup, authenticated Archive, catalog and Resolution requests, and the same-process RC footer transition. The candidate has no migration. Production evidence was read only.
