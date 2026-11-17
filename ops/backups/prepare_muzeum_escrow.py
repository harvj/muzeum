#!/usr/bin/env python3
"""Package existing restricted Muzeum recovery material without displaying it."""
import hashlib,io,json,os,stat,sys,tarfile
from pathlib import Path

BASE=Path('/var/lib/harvj-backups/muzeum')
SOURCE=BASE/'escrow/muzeum-backup-recovery-v1.tar.gz'
FILES={
 'restic-password':Path('/etc/harvj-backups/muzeum/restic-password'),
 'muzeum-ed25519':Path('/etc/harvj-backups/ssh/muzeum-ed25519'),
 'muzeum-ed25519.pub':Path('/etc/harvj-backups/ssh/muzeum-ed25519.pub'),
 'storagebox_known_hosts':Path('/etc/harvj-backups/ssh/storagebox_known_hosts'),
}


def material():
    values={}
    for name,path in FILES.items():
        st=path.lstat()
        allowed = 0o022 if name.endswith('.pub') else 0o077
        if not stat.S_ISREG(st.st_mode) or st.st_uid!=0 or stat.S_IMODE(st.st_mode)&allowed:
            raise RuntimeError('Unsafe recovery source')
        values[name]=path.read_bytes()
    profile=Path('/etc/harvj-backups/muzeum/subaccount-readiness.json')
    st=profile.lstat()
    if not stat.S_ISREG(st.st_mode) or st.st_uid!=0 or stat.S_IMODE(st.st_mode)!=0o600:raise RuntimeError('Unsafe profile')
    config=json.loads(profile.read_text())
    if config.get('credential_scope')!='subaccount' or config.get('ssh_user')!='u720116-sub1' or config.get('repository_id')!='76a36c7d3bd30fe1fd6d242f55a5f2adc7a43b3c7d978ecd2974c4f0a808bb51':
        raise RuntimeError('Unexpected repository identity')
    values['repository.json']=(json.dumps({k:config[k] for k in ('repository','repository_id','ssh_host','ssh_user')},sort_keys=True)+'\n').encode()
    return values


def validate(data,values):
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as archive:
        members=archive.getmembers()
        if len(members)!=len(values) or set(m.name for m in members)!=set(values):raise RuntimeError('Unexpected recovery contents')
        for member in members:
            if not member.isfile() or member.size>65536 or archive.extractfile(member).read(65537)!=values[member.name]:
                raise RuntimeError('Stale recovery document')


def main():
    if os.geteuid()!=0:raise RuntimeError('Root required')
    os.umask(0o077)
    values=material()
    if SOURCE.parent.is_symlink():raise RuntimeError('Unsafe escrow directory')
    SOURCE.parent.mkdir(mode=0o700,exist_ok=True)
    if SOURCE.exists():
        st=SOURCE.lstat()
        if not stat.S_ISREG(st.st_mode) or st.st_uid!=0 or stat.S_IMODE(st.st_mode)!=0o600:raise RuntimeError('Unsafe archive')
        validate(SOURCE.read_bytes(),values)
    else:
        buffer=io.BytesIO()
        with tarfile.open(fileobj=buffer,mode='w:gz') as archive:
            for name,value in values.items():
                entry=tarfile.TarInfo(name);entry.size=len(value);entry.mode=0o600
                archive.addfile(entry,io.BytesIO(value))
        data=buffer.getvalue();validate(data,values)
        fd=os.open(SOURCE,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'wb') as output:output.write(data);output.flush();os.fsync(output.fileno())
    print('Existing Muzeum restricted backup recovery document prepared: '+str(SOURCE))
    print('SHA256: '+hashlib.sha256(SOURCE.read_bytes()).hexdigest())
    print('Independent 1Password retrieval is not yet verified. Timers remain disabled.')


if __name__=='__main__':
    try:main()
    except Exception:
        print('Muzeum escrow preparation failed; sensitive details suppressed.',file=sys.stderr)
        raise SystemExit(1)
