#!/usr/bin/env python3
"""Compare independently retrieved 1Password bytes, never extract or print secrets."""
import datetime,hashlib,hmac,json,os,stat,sys,tempfile
from pathlib import Path
from prepare_muzeum_escrow import SOURCE,material,validate


def main():
    if os.geteuid()!=0 or sys.stdin.isatty() or len(sys.argv)!=1:raise RuntimeError('Root and private document stream required')
    os.umask(0o077)
    info=SOURCE.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid!=0 or stat.S_IMODE(info.st_mode)!=0o600:raise RuntimeError('Unsafe source')
    expected=SOURCE.read_bytes()
    received=sys.stdin.buffer.read(262145)
    if len(received)>262144 or not hmac.compare_digest(hashlib.sha256(received).digest(),hashlib.sha256(expected).digest()):
        raise RuntimeError('Independent document differs')
    validate(received,material())
    target=SOURCE.parent/'independent-verification.json'
    fd,name=tempfile.mkstemp(dir=SOURCE.parent,prefix='.verified-')
    try:
        with os.fdopen(fd,'w') as out:
            os.fchmod(out.fileno(),0o600)
            json.dump({'verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sha256':hashlib.sha256(received).hexdigest(),
                       'scope':'Operator-retrieved 1Password bytes match current restricted backup material; production application restore remains separate'},out)
            out.flush();os.fsync(out.fileno())
        os.replace(name,target)
    finally:Path(name).unlink(missing_ok=True)
    print('Independent Muzeum 1Password recovery-document retrieval verified; no secrets displayed.')


if __name__=='__main__':
    try:main()
    except Exception:
        print('Muzeum recovery verification failed; sensitive details suppressed.',file=sys.stderr)
        raise SystemExit(1)
