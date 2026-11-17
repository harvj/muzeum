#!/usr/bin/env python3
"""Persist a sanitized failure event and signal the configured Healthchecks check."""
import datetime
import json
import os
from pathlib import Path
import re
import sys
import syslog
import monitoring

unit = sys.argv[1] if len(sys.argv) == 2 else ''
if not re.fullmatch(r'muzeum-backup[-a-zA-Z0-9@_.]*\.service', unit):
    raise SystemExit('Unexpected backup unit name')
os.umask(0o077)
state = Path('/var/lib/harvj-backups/muzeum/state')
state.mkdir(parents=True, exist_ok=True, mode=0o700)
job = 'restoration' if 'restore' in unit else 'verification' if 'check' in unit else 'backup'
acknowledged = monitoring.safe_signal(job, 'failure')
event = {'unit': unit, 'failed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'intended_email': 'jimrharvey@gmail.com', 'healthchecks_acknowledged': acknowledged,
         'delivery': 'healthchecks-and-local' if acknowledged else 'local-journal-and-state'}
with (state / 'failures.jsonl').open('a') as handle:
    handle.write(json.dumps(event) + '\n')
syslog.openlog('muzeum-backup-alert')
syslog.syslog(syslog.LOG_CRIT, 'Backup unit failed: ' + unit + '; see scoped journal; Healthchecks acknowledged=' + str(acknowledged))
print(json.dumps(event))

