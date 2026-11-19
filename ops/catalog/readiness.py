"""Read-only readiness probe for the Muzeum catalog rollout. Run on the Muzeum host."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urlsplit

ENV_FILE = Path("/var/www/muzeum/shared/.env")
KINDS = ("Supervisor(fork)", "Dispatcher", "Worker", "Scheduler")
TIMEOUT = 45
INTERVAL = 2
HEARTBEAT_MAX_AGE = 90


def command(*args, env=None, sql=None):
    return subprocess.run(args, env=env, input=sql, capture_output=True,
                          text=True, timeout=4, check=False)


def service(unit):
    result = command("systemctl", "show", "--property=ActiveState,SubState,MainPID,User", unit)
    states = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    pid = int(states.get("MainPID", "0"))
    active = result.returncode == 0 and states.get("ActiveState") == "active"
    ok = active and states.get("SubState") == "running" and states.get("User") == "muzeum" and pid > 0
    return ok, f"{states.get('ActiveState', 'unknown')}/{states.get('SubState', 'unknown')}, PID {pid}", pid


def public_http():
    result = command("curl", "--silent", "--max-time", "3", "--output", "/dev/null",
                     "--write-out", "%{http_code}", "https://muzeum.fm/up")
    return result.returncode == 0 and result.stdout == "200", f"HTTP {result.stdout or 'unavailable'}"


def queue_database(worker_pid, since):
    settings = dict(line.split("=", 1) for line in ENV_FILE.read_text().splitlines()
                    if line.strip() and not line.lstrip().startswith("#"))
    url = urlsplit(settings["QUEUE_DATABASE_URL"])
    if (url.hostname, url.username, url.path) != ("127.0.0.1", "muzeum_runtime", "/muzeum_production_queue"):
        raise ValueError("Unexpected queue connection")
    env = {
        "PATH": os.defpath, "PGHOST": url.hostname, "PGPORT": str(url.port or 5432),
        "PGUSER": url.username, "PGDATABASE": url.path[1:], "PGCONNECT_TIMEOUT": "3",
        "PGOPTIONS": "-c default_transaction_read_only=on -c statement_timeout=3000",
    }
    if url.password:
        env["PGPASSWORD"] = unquote(url.password)
    elif "PGPASSFILE" in settings:
        env["PGPASSFILE"] = settings["PGPASSFILE"]
    # Inputs are a systemd integer PID and a parsed UTC timestamp.
    sql = f"""
    WITH supervisor AS (
      SELECT id FROM solid_queue_processes WHERE pid = {worker_pid} AND kind = 'Supervisor(fork)'
    ), processes AS (
      SELECT kind, metadata::jsonb AS metadata,
             extract(epoch FROM ((now() AT TIME ZONE 'UTC') - last_heartbeat_at))::int AS age
      FROM solid_queue_processes
      WHERE id IN (SELECT id FROM supervisor) OR supervisor_id IN (SELECT id FROM supervisor)
    ), ingestion AS (
      SELECT count(*) FILTER (WHERE finished_at >= '{since.isoformat()}'::timestamptz AT TIME ZONE 'UTC') AS completed,
             count(*) FILTER (WHERE finished_at IS NULL AND NOT EXISTS (
               SELECT 1 FROM solid_queue_failed_executions WHERE job_id = solid_queue_jobs.id
             )) AS unfinished,
             count(*) FILTER (WHERE EXISTS (
               SELECT 1 FROM solid_queue_failed_executions WHERE job_id = solid_queue_jobs.id
             )) AS failed
      FROM solid_queue_jobs
      WHERE queue_name = 'imports' AND
            (finished_at IS NULL OR finished_at >= '{since.isoformat()}'::timestamptz AT TIME ZONE 'UTC')
    )
    SELECT json_build_object('processes', coalesce((SELECT json_agg(processes) FROM processes), '[]'),
                             'ingestion', (SELECT row_to_json(ingestion) FROM ingestion));
    """
    result = command("psql", "-XAt", "-v", "ON_ERROR_STOP=1", "-f", "-", env=env, sql=sql)
    if result.returncode:
        raise RuntimeError("Queue query failed")
    return json.loads(result.stdout)


def queue_checks(snapshot, catalog):
    expected = "imports,default,canonical_catalog" if catalog == "on" else "imports,default"
    processes = snapshot["processes"]
    workers = [row for row in processes if row["kind"] == "Worker"]
    configurations = [((row["metadata"] or {}).get("queues"), (row["metadata"] or {}).get("pool_size"))
                      for row in workers]
    ages = {kind: [row["age"] for row in processes if row["kind"] == kind] for kind in KINDS}
    fresh = all(len(values) == 1 and 0 <= values[0] <= HEARTBEAT_MAX_AGE for values in ages.values())
    ingestion = snapshot["ingestion"]
    return {
        "Queue subscription": (configurations == [(expected, 1)], f"expected {expected} with one thread; observed {configurations}"),
        "Solid Queue heartbeats": (fresh, ", ".join(f"{kind} {values or 'missing'}" for kind, values in ages.items()) + " (seconds)"),
        "Last.fm ingestion": (ingestion["completed"] > 0, "since marker: "
                              f"{ingestion['completed']} completed; queue: {ingestion['unfinished']} unfinished, {ingestion['failed']} failed"),
    }


def probe(catalog, since):
    checks = {}
    worker_pid = 0
    for label, name in (("Web process", "muzeum-web"), ("Worker process", "muzeum-worker")):
        try:
            ok, detail, pid = service(name)
            checks[label] = (ok, detail)
            if label == "Worker process" and ok:
                worker_pid = pid
        except (OSError, ValueError, subprocess.TimeoutExpired):
            checks[label] = (False, "systemd status unavailable")
    try:
        checks["Public HTTP"] = public_http()
    except (OSError, subprocess.TimeoutExpired):
        checks["Public HTTP"] = (False, "probe unavailable")
    try:
        checks.update(queue_checks(queue_database(worker_pid, since), catalog))
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.TimeoutExpired):
        for name in ("Queue subscription", "Solid Queue heartbeats", "Last.fm ingestion"):
            checks[name] = (False, "queue evidence unavailable")
    return checks


def wait(catalog, since):
    start = time.monotonic()
    previous = {}
    while True:
        checks = probe(catalog, since)
        elapsed = time.monotonic() - start
        for name, (ok, detail) in checks.items():
            if name not in previous or previous[name][0] != ok:
                print(f"{elapsed:5.1f}s  {'PASS' if ok else 'WAIT'}  {name} — {detail}", flush=True)
        if all(ok for ok, _ in checks.values()):
            return 0
        if elapsed >= TIMEOUT:
            for name, (ok, detail) in checks.items():
                print(f"{'PASS' if ok else 'FAIL'}  {name} — {detail}", flush=True)
            return 1
        previous = checks
        time.sleep(min(INTERVAL, TIMEOUT - elapsed))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", required=True, choices=("on", "off"))
    parser.add_argument("--since", required=True,
                        type=lambda value: dt.datetime.fromisoformat(value.replace("Z", "+00:00")),
                        help="UTC timestamp captured immediately after the stage restart returns")
    args = parser.parse_args()
    if args.since.utcoffset() != dt.timedelta(0):
        parser.error("--since must carry a UTC offset")
    return wait(args.catalog, args.since)


if __name__ == "__main__":
    raise SystemExit(main())
