# Catalog activation readiness failure, 2026-11-19 UTC

Production remained on `364996ed0528a9e94a4287255dc7680c3fe39354`. The first activation attempt restarted both Muzeum units and rolled back before any catalog or listener write.

| Event | Web UTC | Worker UTC |
|---|---|---|
| Activation stop requested | 00:31:54.051521 | 00:31:54.047711 |
| Previous process stopped | 00:31:54.098181 | 00:31:54.199335 |
| systemd marked new unit started | 00:31:54.112007 | 00:31:54.221822 |
| Application startup | Puma listening at 00:31:58.050790 | Supervisor at 00:31:58.222140, catalog subscription at 00:31:58.409481, scheduler at 00:31:58.503929 |
| Rollback stop requested | 00:32:18.653754 | 00:32:18.651110 |
| Activated process stopped | 00:32:18.676771 | 00:32:18.797373 |
| systemd marked rollback unit started | 00:32:18.692836 | 00:32:18.814713 |
| Application startup after rollback | Puma listening at 00:32:22.625301 | Supervisor at 00:32:23.110536, original subscription at 00:32:23.362342 |

Puma opened its socket about four seconds after each restart. The activation transcript captured two HTTP 502 probes and rollback captured two more. Caddy retained no matching access or error events and Rails retained no individual `/up` requests for this window. The exact first and last 502 timestamps and the first public 200 during activation cannot be recovered. The socket was open 20.6 seconds before rollback. Solid Queue recorded the expected activated subscription with one thread and the queue database retained 20 imports completions from 00:31:59.352985 to 00:32:18.115604.

The old aggregate checker required the enabled flag in the worker supervisor's `/proc/<pid>/environ` before querying queue evidence. A control on the same running release after rollback found zero environment entries for the Solid Queue supervisor, while Puma exposed its environment entries. Solid Queue 1.7.2 rewrites its supervisor process title through Ruby's `$0`. The enabled subscription independently proves that the worker loaded the flag. The worker environment predicate is therefore the evidence-supported false-negative mechanism. The exited process's environment and per-iteration statuses were not retained, so the exact state of every other predicate cannot be reconstructed. The off check had passed because an empty environment also satisfied a negative membership test.

The flag is read at worker boot for queue subscription, and at request time by Rails for web dispatch and paused-state copy. The systemd environment file is loaded when each process starts. There is no web boot branch for this flag. Both processes ultimately need the flag for end-to-end use, and the worker can be restarted and verified before web is restarted. The revised probe uses systemd, HTTP, current-generation queue registrations and imports completions. It prints each condition's transition and its verdict at timeout.

## Verification of the revised procedure

A disposable rehearsal used Rails production configuration, real Puma, Solid Queue 1.7.2 and an isolated PostgreSQL 16 cluster. It substituted local process IDs and loopback HTTP for systemd and Caddy. The existing web PID and HTTP 200 were preserved while the worker switched queues. After the web restart, the probe showed HTTP transition from unavailable to 200. Rollback restored the original subscription, all heartbeats and successful scheduled imports. No provider or production data was required. Against the existing disabled production state the read-only probe independently passed all six conditions. Four diagnostic tests, 65 focused Rails examples, 40 deployment tests and 28 backup tests passed.
