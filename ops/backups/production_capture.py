"""Muzeum-only production capture. No provisioning or timer activation is implicit."""
import datetime,hashlib,json,os,re,shutil,stat,subprocess,time
from pathlib import Path
DATABASES=('muzeum_production','muzeum_production_cache','muzeum_production_queue','muzeum_production_cable')
SOURCES=('/var/www/muzeum/shared/storage','/var/www/muzeum/shared/.env','/etc/muzeum/migrate.env','/etc/muzeum/database-credentials.json','/etc/muzeum/oidc.env','/etc/muzeum/lastfm.env','/etc/muzeum/backup.pgpass')
UNITS=('muzeum-web.service','muzeum-worker.service')


def validate(config):
    if config.get('mode')!='production' or tuple(config['databases'])!=DATABASES or tuple(config['sources'])!=SOURCES:
        raise RuntimeError('Exact Muzeum production capture allowlist required')
    if config.get('credential_scope')!='subaccount' or config.get('ssh_user')!='u720116-sub1':raise RuntimeError('Restricted Muzeum identity required')
    if config.get('repository_id')!='76a36c7d3bd30fe1fd6d242f55a5f2adc7a43b3c7d978ecd2974c4f0a808bb51':raise RuntimeError('Unexpected repository')
    receipt=Path('/var/lib/harvj-backups/muzeum/escrow/independent-verification.json')
    if not json.loads(receipt.read_text()).get('verified_at'):raise RuntimeError('Independent backup escrow required')
    password=Path('/etc/muzeum/backup.pgpass')
    info=password.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid!=0 or stat.S_IMODE(info.st_mode)!=0o600:raise RuntimeError('Unsafe dump credentials')


def environment():
    return {'PATH':'/usr/bin:/bin','LANG':'C.UTF-8','PGPASSFILE':'/etc/muzeum/backup.pgpass','PGOPTIONS':'-c default_transaction_read_only=on -c statement_timeout=120000'}


def query(database,sql):
    result=subprocess.run(['psql','-XAt','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-U','muzeum_backup','-d',database],
                          input=sql.encode(),capture_output=True,env=environment(),timeout=130)
    if result.returncode:raise RuntimeError('Scoped backup metadata query failed')
    return result.stdout.decode().strip()


def fingerprints(database,restored=False):
    if restored:
        prefix=['runuser','-u','postgres','--','psql','-XAt','-v','ON_ERROR_STOP=1','-d',database]
        env=dict(os.environ, PGOPTIONS='-c statement_timeout=120000')
    else:
        prefix=['psql','-XAt','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-U','muzeum_backup','-d',database]
        env=environment()
    sql="SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"
    result=subprocess.run(prefix,input=sql.encode(),capture_output=True,env=env,timeout=30)
    if result.returncode:raise RuntimeError('Fingerprint table inventory failed')
    tables=result.stdout.decode().splitlines();values={}
    for table in tables:
        if not re.fullmatch('[a-z_][a-z0-9_]*',table):raise RuntimeError('Unexpected table identifier')
        # Stable row JSON ordering, streamed rather than retaining the archive in memory.
        sql='COPY (SELECT row_to_json(t)::text FROM public."'+table+'" t ORDER BY row_to_json(t)::text COLLATE "C") TO STDOUT'
        with subprocess.Popen(prefix+['-c',sql],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,env=env) as process:
            digest=hashlib.sha256();size=0
            for chunk in iter(lambda:process.stdout.read(65536),b''):digest.update(chunk);size+=len(chunk)
            if process.wait(timeout=120):raise RuntimeError('Streamed fingerprint failed')
        values[table]={'sha256':digest.hexdigest(),'bytes':size}
    return values


def capture(config,base,invoke,atomic_json,file_hash,maximum):
    validate(config)
    root=base/'captures';root.mkdir(exist_ok=True,mode=0o700)
    if sum(p.stat().st_size for p in root.rglob('*') if p.is_file())>6*1024**3 or shutil.disk_usage(base).free<8*1024**3:raise RuntimeError('Insufficient capture headroom')
    target=root/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    target.mkdir(mode=0o700);(target/'databases').mkdir(mode=0o700);(target/'files').mkdir(mode=0o700)
    active=[]
    for unit in UNITS:
        result=subprocess.run(['systemctl','is-active','--quiet',unit],capture_output=True)
        if result.returncode==0:active.append(unit)
        elif result.returncode not in (3,4):raise RuntimeError('Unable to inspect Muzeum writer state')
    try:
        if active:invoke(['systemctl','stop',*active],timeout=150)
        for unit in UNITS:
            if subprocess.run(['systemctl','is-active','--quiet',unit],capture_output=True).returncode==0:raise RuntimeError('Muzeum writer still active')
        metadata={'mode':'production','release_sha':None,'databases':{}}
        revision=Path('/var/www/muzeum/current/REVISION')
        if revision.exists():
            sha=revision.read_text().strip()
            if not re.fullmatch('[a-f0-9]{40}',sha):raise RuntimeError('Invalid release revision')
            metadata['release_sha']=sha
        for database in DATABASES:
            remaining=maximum-sum(p.stat().st_size for p in target.rglob('*') if p.is_file())
            if remaining<=0:raise RuntimeError('Capture budget exceeded')
            with (target/'databases'/(database+'.dump')).open('xb') as output:
                invoke(['pg_dump','--host=127.0.0.1','--username=muzeum_backup','--format=custom','--compress=1','--dbname='+database],
                       env=environment(),output=output,file_limit=remaining,timeout=180)
            metadata['databases'][database]=fingerprints(database)
        total=sum(p.stat().st_size for p in target.rglob('*') if p.is_file())
        for source in SOURCES:
            path=Path(source)
            if path.is_symlink() or not path.exists():raise RuntimeError('Required production source missing/unsafe')
            items=[path] if path.is_file() else sorted(path.rglob('*'))
            (target/'files'/source.lstrip('/')).mkdir(parents=True,mode=0o700,exist_ok=True) if path.is_dir() else None
            for item in items:
                if item.is_symlink() or not (item.is_file() or item.is_dir()):raise RuntimeError('Unsafe production file')
                if item.is_file():
                    total+=item.stat().st_size
                    if total>maximum:raise RuntimeError('Capture budget exceeded')
                    destination=target/'files'/str(item).lstrip('/')
                    destination.parent.mkdir(parents=True,mode=0o700,exist_ok=True)
                    shutil.copyfile(item,destination);destination.chmod(0o600)
        atomic_json(target/'production.json',metadata)
        atomic_json(target/'manifest.json',{str(p.relative_to(target)):file_hash(p) for p in target.rglob('*') if p.is_file()})
        return target
    finally:
        # Resume exactly the units previously running, including on partial stop failure.
        if active:invoke(['systemctl','start',*active],timeout=120)


def cleanup_capture(path,base):
    if path.parent!=base/'captures' or path.is_symlink() or not re.fullmatch(r'[0-9]{8}T[0-9]{12}Z',path.name):
        raise RuntimeError('Refusing unvalidated staging cleanup')
    shutil.rmtree(path)
