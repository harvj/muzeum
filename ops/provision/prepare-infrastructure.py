#!/usr/bin/env python3
"""Additive Muzeum-only bootstrap; no services, routes, timers, or deploy are started."""
import json,os,pwd,re,secrets,stat,subprocess,sys
from pathlib import Path
ROOT=Path('/etc/muzeum')
DATABASES=('muzeum_production','muzeum_production_cache','muzeum_production_queue','muzeum_production_cable')
ROLES=('muzeum_migrator','muzeum_runtime','muzeum_backup')


def run(argv,input=None):
    result=subprocess.run(argv,input=input,capture_output=True,timeout=120)
    if result.returncode:raise RuntimeError('Operation failed: '+argv[0])
    return result.stdout


def psql(sql,database='postgres'):
    return run(['/usr/sbin/runuser','-u','postgres','--','psql','-XAt','-v','ON_ERROR_STOP=1','-d',database],sql.encode()).decode().strip()


def write(path,data,uid=0,gid=0,mode=0o600):
    if path.exists():
        info=path.lstat()
        if not stat.S_ISREG(info.st_mode) or path.read_bytes()!=data:raise RuntimeError('Existing file differs: '+str(path))
    else:
        fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,mode)
        with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
    os.chown(path,uid,gid);path.chmod(mode)


def main():
    if os.geteuid()!=0:raise RuntimeError('Root required')
    os.umask(0o077)
    receipt=json.loads(Path('/var/lib/harvj-backups/muzeum/escrow/independent-verification.json').read_text())
    if not receipt.get('verified_at'):raise RuntimeError('Independent backup escrow required')
    for required in ('oidc.env','lastfm.env'):
        p=ROOT/required
        info=p.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid!=0 or stat.S_IMODE(info.st_mode)!=0o600:raise RuntimeError('Missing protected provider configuration')
    version=run(['/opt/auth/ruby-3.4.12/bin/ruby','-e','print RUBY_VERSION'])
    if version!=b'3.4.12':raise RuntimeError('Verified runtime required')
    for name in ('muzeum','muzeum-migrate'):
        try:pwd.getpwnam(name)
        except KeyError:run(['useradd','--create-home','--shell','/bin/bash' if name=='muzeum' else '/usr/sbin/nologin',name])
    user=pwd.getpwnam('muzeum');migration=pwd.getpwnam('muzeum-migrate')
    run(['usermod','-a','-G','muzeum','muzeum-migrate'])
    creds=ROOT/'database-credentials.json'
    if creds.exists():
        values=json.loads(creds.read_text())
    else:
        # Never adopt unknown pre-existing resources with newly generated passwords.
        names=psql("SELECT rolname FROM pg_roles WHERE rolname LIKE 'muzeum_%'")
        if names:raise RuntimeError('Existing roles require reconciliation')
        values={role:secrets.token_hex(32) for role in ROLES}
        values['secret_key_base']=secrets.token_hex(64)
        write(creds,(json.dumps(values,sort_keys=True)+'\n').encode())
    if set(values)!=set((*ROLES,'secret_key_base')) or any(not re.fullmatch('[a-f0-9]{64,128}',v) for v in values.values()):raise RuntimeError('Unexpected credential format')
    if not psql("SELECT 1 FROM pg_roles WHERE rolname='muzeum_owner'"):
        psql('CREATE ROLE muzeum_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;')
    for role in ROLES:
        if not psql("SELECT 1 FROM pg_roles WHERE rolname='"+role+"'"):
            membership=' IN ROLE muzeum_owner' if role=='muzeum_migrator' else ''
            psql("CREATE ROLE "+role+" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION CONNECTION LIMIT 24 PASSWORD '"+values[role]+"'"+membership+';')
    for database in DATABASES:
        owner=psql("SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='"+database+"'")
        if not owner:psql('CREATE DATABASE '+database+' OWNER muzeum_owner TEMPLATE template0;')
        elif owner!='muzeum_owner':raise RuntimeError('Unexpected Muzeum database ownership')
        psql('REVOKE ALL ON DATABASE '+database+' FROM PUBLIC; GRANT CONNECT ON DATABASE '+database+' TO muzeum_migrator,muzeum_runtime,muzeum_backup;')
        psql('REVOKE CREATE ON SCHEMA public FROM PUBLIC; GRANT USAGE,CREATE ON SCHEMA public TO muzeum_owner; GRANT USAGE ON SCHEMA public TO muzeum_runtime,muzeum_backup; ALTER DEFAULT PRIVILEGES FOR ROLE muzeum_migrator IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO muzeum_runtime; ALTER DEFAULT PRIVILEGES FOR ROLE muzeum_migrator IN SCHEMA public GRANT USAGE,SELECT ON SEQUENCES TO muzeum_runtime; ALTER DEFAULT PRIVILEGES FOR ROLE muzeum_migrator IN SCHEMA public GRANT SELECT ON TABLES TO muzeum_backup; ALTER DEFAULT PRIVILEGES FOR ROLE muzeum_migrator IN SCHEMA public GRANT SELECT ON SEQUENCES TO muzeum_backup;',database)
    shared=Path('/var/www/muzeum/shared')
    for path in (Path('/var/www/muzeum'),Path('/var/www/muzeum/releases'),shared,shared/'storage',shared/'log',shared/'tmp/pids',shared/'tmp/sockets',shared/'bundle'):
        path.mkdir(parents=True,exist_ok=True,mode=0o750);os.chown(path,user.pw_uid,user.pw_gid);path.chmod(0o750)
    provider=(ROOT/'oidc.env').read_text()+(ROOT/'lastfm.env').read_text()
    def environment(role):
        result='RAILS_ENV=production\nSECRET_KEY_BASE='+values['secret_key_base']+'\nBUNDLE_PATH=/var/www/muzeum/shared/bundle\n'+provider
        for name,database in zip(('DATABASE_URL','CACHE_DATABASE_URL','QUEUE_DATABASE_URL','CABLE_DATABASE_URL'),DATABASES):
            result+=name+'=postgresql://'+role+':'+values[role]+'@127.0.0.1:5432/'+database+'\n'
        return result
    write(shared/'.env',environment('muzeum_runtime').encode(),user.pw_uid,user.pw_gid)
    write(ROOT/'migrate.env',environment('muzeum_migrator').encode())
    write(ROOT/'backup.pgpass',(''.join('127.0.0.1:5432:'+db+':muzeum_backup:'+values['muzeum_backup']+'\n' for db in DATABASES)).encode())
    for name in ('ruby','bundle'):
        path=Path('/home/muzeum/.rbenv/shims');path.mkdir(parents=True,exist_ok=True,mode=0o755)
        write(path/name,('#!/bin/sh\nexec /opt/auth/ruby-3.4.12/bin/'+name+' "$@"\n').encode(),0,0,0o755)
    ssh=Path('/home/muzeum/.ssh');ssh.mkdir(mode=0o700,exist_ok=True);os.chown(ssh,user.pw_uid,user.pw_gid)
    operator_key=Path('/opt/muzeum/operator-tools/operator.pub').read_bytes()
    if not operator_key.startswith(b'ssh-ed25519 '):raise RuntimeError('Expected approved operator public key')
    write(ssh/'authorized_keys',operator_key,user.pw_uid,user.pw_gid)
    if not (ssh/'github-ed25519').exists():
        run(['runuser','-u','muzeum','--','ssh-keygen','-q','-t','ed25519','-N','','-C','muzeum read-only repository','-f',str(ssh/'github-ed25519')])
    known=run(['ssh-keygen','-F','github.com','-f','/home/deploy/.ssh/known_hosts'])
    known=b'\n'.join(line for line in known.splitlines() if not line.startswith(b'#'))+b'\n'
    if not known.strip():raise RuntimeError('Existing verified GitHub host key required')
    write(ssh/'known_hosts',known,user.pw_uid,user.pw_gid)
    write(ssh/'config',b'Host github.com\n  IdentityFile ~/.ssh/github-ed25519\n  IdentitiesOnly yes\n  StrictHostKeyChecking yes\n',user.pw_uid,user.pw_gid)
    print('Muzeum-only OS users, four scoped databases, role grants and protected environment prepared. No services, proxy routes or timers started.')
    print('Deploy public key: '+(ssh/'github-ed25519.pub').read_text().strip())


if __name__=='__main__':
    try:main()
    except Exception as error:
        print('Muzeum preparation stopped: '+str(error)+'; no secret contents logged.',file=sys.stderr)
        raise SystemExit(1)
