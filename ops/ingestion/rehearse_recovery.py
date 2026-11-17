#!/usr/bin/env python3
"""Encrypted four-database recovery on a dedicated local synthetic cluster only."""
import hashlib,json,os,re,secrets,subprocess,time
from pathlib import Path

ROOT=Path('/private/tmp/muzeum-p12-recovery')
PG='/opt/homebrew/opt/postgresql@16/bin/'
RESTIC='/private/tmp/muzeum-p12-restic/restic'
SOURCE='muzeum_p12_legacy_migration'

def invoke(args,**kwargs):
    return subprocess.run(args,check=True,capture_output=True,**kwargs).stdout

def sql(database,query):
    return invoke([PG+'psql','-h','127.0.0.1','-p','56491','-d',database,'-XAt','-v','ON_ERROR_STOP=1','-c',query],text=True).strip()

def rails(code,**extra):
    env=os.environ.copy();env.update(DATABASE_URL=f'postgres://jim@127.0.0.1:56491/{SOURCE}',RAILS_ENV='test',BOOTSNAP_READONLY='1');env.update(extra)
    return invoke(['bundle','exec','rails','runner',code],env=env,text=True)

def fingerprint(database):
    tables=sql(database,"SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename").splitlines()
    result={}
    for table in tables:
        assert re.fullmatch('[a-z_][a-z0-9_]*',table)
        query=f'''COPY (SELECT row_to_json(t)::text FROM public."{table}" t ORDER BY row_to_json(t)::text COLLATE "C") TO STDOUT'''
        command=[PG+'psql','-h','127.0.0.1','-p','56491','-d',database,'-XAt','-v','ON_ERROR_STOP=1','-c',query]
        with subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE) as process:
            digest=hashlib.sha256();size=0
            for chunk in iter(lambda:process.stdout.read(65536),b''):digest.update(chunk);size+=len(chunk)
            assert process.wait()==0
        result[table]={'sha256':digest.hexdigest(),'bytes':size}
    return result

assert not ROOT.exists(), 'Retain previous recovery artifacts; choose explicit reviewed cleanup before rerunning'
ROOT.mkdir(mode=0o700);capture=ROOT/'capture';capture.mkdir(mode=0o700)
password=ROOT/'restic-password';password.write_text(secrets.token_hex(32));password.chmod(0o600)
env=os.environ.copy();env.update(RESTIC_PASSWORD_FILE=str(password),RESTIC_REPOSITORY=str(ROOT/'repository'))
started=time.monotonic()
sources={'primary':SOURCE}
for name in ('cache','queue','cable'):
    database='muzeum_p12_recovery_source_'+name;sources[name]=database
    invoke([PG+'createdb','-h','127.0.0.1','-p','56491',database])
    rails(f'ActiveRecord::Base.establish_connection("postgres://jim@127.0.0.1:56491/{database}"); load "db/{name}_schema.rb"')
    sql(database,"CREATE TABLE rehearsal_markers(id integer PRIMARY KEY,label text);INSERT INTO rehearsal_markers VALUES(1,'synthetic four-database recovery')")
rails('Session.create!(user:User.sole,expires_at:7.days.from_now,last_seen_at:Time.current,verified_at:Time.current,grant_token:"synthetic-recovery-grant")')
manifest={}
for name,database in sources.items():
    manifest[name]=fingerprint(database)
    invoke([PG+'pg_dump','-h','127.0.0.1','-p','56491','-Fc','--no-owner','--no-acl','-f',str(capture/f'{name}.dump'),database])
(capture/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(capture/'dump-checksums.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in capture.glob('*.dump')},indent=2)+'\n')
invoke([RESTIC,'init'],env=env)
backup=json.loads(invoke([RESTIC,'backup','--json',str(capture)],env=env,text=True).splitlines()[-1])
invoke([RESTIC,'check','--read-data'],env=env)
restored=ROOT/'restored';invoke([RESTIC,'restore','latest','--target',str(restored)],env=env)
retrieved=restored/str(capture).lstrip('/')
for filename,checksum in json.loads((retrieved/'dump-checksums.json').read_text()).items():
    assert hashlib.sha256((retrieved/filename).read_bytes()).hexdigest()==checksum
# Use the same restricted, read-only table grants required by production recovery.
sql(SOURCE,'CREATE ROLE muzeum_p12_recovery_reader NOLOGIN')
targets={}
for name in sources:
    target='muzeum_p12_recovery_restored_'+name;targets[name]=target
    invoke([PG+'createdb','-h','127.0.0.1','-p','56491',target])
    invoke([PG+'pg_restore','-h','127.0.0.1','-p','56491','--no-owner','--no-acl','--exit-on-error','-d',target,str(retrieved/f'{name}.dump')])
    assert fingerprint(target)==manifest[name]
    sql(target,'GRANT USAGE ON SCHEMA public TO muzeum_p12_recovery_reader; GRANT SELECT ON ALL TABLES IN SCHEMA public TO muzeum_p12_recovery_reader')
code='''raise "Wrong primary" unless ActiveRecord::Base.connection.current_database==ENV.fetch("EXPECTED_PRIMARY")
{SolidCache::Record=>ENV.fetch("CACHE_DATABASE_URL"),SolidQueue::Record=>ENV.fetch("QUEUE_DATABASE_URL"),SolidCable::Record=>ENV.fetch("CABLE_DATABASE_URL")}.each do |record,url|
 record.establish_connection(url)
 raise "Auxiliary remap failed" unless record.connection.current_database==URI(url).path.delete_prefix("/")
 raise "Recovery must be read only" unless record.connection.select_value("SHOW transaction_read_only")=="on"
end
raise "Identity recovery failed" unless User.sole.oidc_subject=="preserved-synthetic-subject"
raise "Grant decryption failed" unless Session.sole.grant_token=="synthetic-recovery-grant"
raise "Archive recovery failed" unless Scrobble.count==250000 && SourceDelivery.count==250000
puts({primary:ActiveRecord::Base.connection.current_database,scrobbles:Scrobble.count,deliveries:SourceDelivery.count,grant_decryption_verified:true,four_connections_remapped:true}.to_json)'''
proof=rails(code,DATABASE_URL=f'postgres://jim@127.0.0.1:56491/{targets["primary"]}',EXPECTED_PRIMARY=targets['primary'],
    CACHE_DATABASE_URL=f'postgres://jim@127.0.0.1:56491/{targets["cache"]}',QUEUE_DATABASE_URL=f'postgres://jim@127.0.0.1:56491/{targets["queue"]}',CABLE_DATABASE_URL=f'postgres://jim@127.0.0.1:56491/{targets["cable"]}',
    PGOPTIONS='-c default_transaction_read_only=on -c role=muzeum_p12_recovery_reader')
record={'snapshot_id':backup['snapshot_id'],'restic_version':invoke([RESTIC,'version'],text=True).strip(),'seconds':time.monotonic()-started,
        'databases_verified':4,'source_fingerprints':manifest,'proof':json.loads(proof.splitlines()[-1]),'production_changed':False}
Path('docs/p1.2/evidence/local-encrypted-recovery.json').write_text(json.dumps(record,indent=2)+'\n')
print('Encrypted local four-database restore and read-only application/session recovery verified')
