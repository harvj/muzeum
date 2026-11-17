"""Bounded Healthchecks.io signals; credential URLs are never logged or put in argv."""
import contextlib
import datetime as dt
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import uuid

CONFIG = Path('/etc/harvj-backups/muzeum/monitoring.json')
STATE = Path('/var/lib/harvj-backups/muzeum/state')


def signal(job, phase, run_id=None):
    reason = 'not-configured'
    success = False
    try:
        info = CONFIG.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('unsafe-configuration')
        urls = json.loads(CONFIG.read_text())
        url = urls[job]
        if not re.fullmatch(r'https://hc-ping\.com/[0-9a-fA-F-]{36}', url):
            raise ValueError('unsupported-url-format')
        suffix = {'start': '/start', 'success': '', 'failure': '/fail'}[phase]
        endpoint = url + suffix
        if run_id:
            endpoint += '?rid=' + str(uuid.UUID(run_id))
        # URL is passed over stdin, not command arguments, environment or a shell.
        request = 'url = "' + endpoint + '"\nrequest = "POST"\ndata = "job=' + job + ' phase=' + phase + '"\n'
        result = subprocess.run(['/usr/bin/curl', '--config', '-', '--proto', '=https',
                                 '--connect-timeout', '2', '--max-time', '5', '--retry', '0',
                                 '--silent', '--show-error', '--fail'], input=request,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=7)
        success = result.returncode == 0 and result.stdout.strip() == 'OK'
        reason = 'ok' if success else 'request-failed-or-unacknowledged'
    except FileNotFoundError:
        reason = 'not-configured'
    except subprocess.TimeoutExpired:
        reason = 'timeout'
    except Exception as error:
        reason = type(error).__name__  # Never stringify errors containing URLs.
    try:
        STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
        record = {'job': job, 'phase': phase, 'acknowledged': success, 'reason': reason,
                  'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'run_id': run_id}
        path = STATE / ('last-monitoring-' + job + '.json')
        temporary = path.with_suffix('.' + uuid.uuid4().hex + '.tmp')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as handle:
            json.dump(record, handle)
        temporary.replace(path)
    except Exception:
        success = False
        reason = 'state-write-failed'
    if not success:
        print('Healthchecks signal not acknowledged: job=' + job + ' phase=' + phase + ' reason=' + reason,
              file=sys.stderr, flush=True)
    if success:
        print('Healthchecks signal acknowledged: job=' + job + ' phase=' + phase + ' run_id=' + str(run_id), flush=True)
    return success


def safe_signal(job, phase, run_id=None):
    try:
        return signal(job, phase, run_id)
    except Exception:
        # An internal monitoring/logging fault must not replace the data job's result.
        try:
            print('Healthchecks integration failed; backup exit status preserved', file=sys.stderr, flush=True)
        except OSError:
            pass
        return False


@contextlib.contextmanager
def job_run(job):
    run_id = str(uuid.uuid4())
    safe_signal(job, 'start', run_id)
    try:
        yield
    except BaseException:
        safe_signal(job, 'failure', run_id)
        raise
    else:
        safe_signal(job, 'success', run_id)
