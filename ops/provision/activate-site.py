#!/usr/bin/env python3
"""First Muzeum route activation/withdrawal with whole-config validation and compare-and-swap."""
import fcntl,hashlib,json,os,re,subprocess,sys,time
from pathlib import Path
ROOT=Path('/etc/muzeum');CADDY=Path('/etc/caddy/Caddyfile')
SITE='\n\nmuzeum.fm {\n  encode gzip zstd\n  log_skip /oidc/callback\n  reverse_proxy 127.0.0.1:3011\n  header {\n    X-Content-Type-Options nosniff\n    X-Frame-Options DENY\n  }\n}\n'


def run(args):
    result=subprocess.run(args,capture_output=True,timeout=45)
    if result.returncode:raise RuntimeError('Command failed: '+args[0])
    return result.stdout


def digest(value):return hashlib.sha256(value).hexdigest()


def write(path,value,mode=0o600):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,mode)
    with os.fdopen(fd,'wb') as output:os.fchmod(output.fileno(),mode);output.write(value);output.flush();os.fsync(output.fileno())


def replace_config(value,expected):
    if digest(CADDY.read_bytes())!=expected:raise RuntimeError('Shared Caddy configuration changed; reconcile without overwriting')
    info=CADDY.stat();candidate=CADDY.with_name('Caddyfile.muzeum-candidate')
    write(candidate,value,info.st_mode&0o777);os.chown(candidate,info.st_uid,info.st_gid)
    try:
        run(['caddy','validate','--config',str(candidate),'--adapter','caddyfile'])
        if digest(CADDY.read_bytes())!=expected:raise RuntimeError('Concurrent Caddy change')
        candidate.replace(CADDY)
        run(['systemctl','reload','caddy'])
    finally:candidate.unlink(missing_ok=True)


def main():
    if os.geteuid()!=0 or len(sys.argv)!=3 or sys.argv[1] not in ('activate','withdraw') or not re.fullmatch('[a-f0-9]{40}',sys.argv[2]):raise RuntimeError('Exact SHA and action required')
    action,sha=sys.argv[1:]
    os.umask(0o077)
    with (ROOT/'activation.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        revision=Path('/var/www/muzeum/current/REVISION').read_text().strip()
        if revision!=sha:raise RuntimeError('Running candidate SHA mismatch')
        receipt=ROOT/'site-activation.json';prior=ROOT/'caddy-before-muzeum'
        if action=='withdraw':
            record=json.loads(receipt.read_text())
            # Current revision is checked above; the route receipt can predate a compatible code update.
            replace_config(prior.read_bytes(),record['candidate_sha256'])
            run(['systemctl','stop','muzeum-web.service','muzeum-worker.service'])
            print('Only Muzeum route/services withdrawn; shared configuration restored and data retained.')
            return
        run(['systemctl','is-active','muzeum-web.service','muzeum-worker.service'])
        restore=json.loads(Path('/var/lib/harvj-backups/muzeum/state/last-production-restore.json').read_text())
        if restore.get('databases_verified')!=4:raise RuntimeError('Four-database recovery gate required')
        run(['curl','--fail','--silent','--max-time','8','-H','Host: muzeum.fm','-H','X-Forwarded-Proto: https','http://127.0.0.1:3011/up'])
        if CADDY.is_symlink():raise RuntimeError('Unexpected Caddy symlink')
        current=CADDY.read_bytes()
        if b'muzeum.fm {' in current:raise RuntimeError('Existing Muzeum route requires reviewed incremental deployment')
        if prior.exists() and prior.read_bytes()!=current:raise RuntimeError('Saved baseline differs')
        if not prior.exists():write(prior,current)
        candidate=current+SITE.encode()
        record={'sha':sha,'baseline_sha256':digest(current),'candidate_sha256':digest(candidate)}
        if receipt.exists() and json.loads(receipt.read_text())!=record:
            old=json.loads(receipt.read_text())
            if any(old.get(key)!=record[key] for key in ('baseline_sha256','candidate_sha256')):
                raise RuntimeError('Existing activation receipt differs')
            archived=ROOT/('site-activation-'+old['sha']+'.json')
            if archived.exists() and archived.read_bytes()!=receipt.read_bytes():raise RuntimeError('Prior receipt archive differs')
            if not archived.exists():write(archived,receipt.read_bytes())
            receipt.unlink()
        if not receipt.exists():write(receipt,(json.dumps(record)+'\n').encode())
        try:
            replace_config(candidate,digest(current))
            for attempt in range(12):
                result=subprocess.run(['curl','--fail','--silent','--max-time','8','https://muzeum.fm/up'],capture_output=True)
                if result.returncode==0:break
                time.sleep(2)
            else:raise RuntimeError('HTTPS health verification failed')
        except Exception:
            if digest(CADDY.read_bytes())==digest(candidate):replace_config(current,digest(candidate))
            run(['systemctl','stop','muzeum-web.service','muzeum-worker.service'])
            raise
        print('Muzeum-only route activated; HTTPS liveness verified. Other application blocks preserved byte-for-byte.')


if __name__=='__main__':
    try:main()
    except Exception as error:
        print('Muzeum activation stopped: '+str(error)+'; secret command output suppressed.',file=sys.stderr)
        raise SystemExit(1)
