"""Restore exactly four Muzeum dumps into new isolated temporary databases only."""
import datetime,json,os,re,secrets,shutil,subprocess,time
from pathlib import Path
import production_capture
import monitoring



def recovery_environment(values,targets,release):
    from urllib.parse import urlsplit,urlunsplit
    if set(targets)!=set(production_capture.DATABASES) or any(not re.fullmatch('muzeum_recovery_[a-f0-9]{16}',v) for v in targets.values()):
        raise RuntimeError('Exact isolated recovery targets required')
    env=dict({key:value for key,value in values.items() if not
              key.startswith(('LD_', 'DYLD_', 'BUNDLE_', 'RUBY', 'GEM_', 'RBENV_'))},
             PATH='/opt/muzeum/ruby-3.4.13/bin:/usr/bin:/bin',
             BUNDLE_PATH='/var/www/muzeum/shared/bundle/ruby-3.4.13',HOME='/home/muzeum',
             BUNDLE_IGNORE_CONFIG='1',BUNDLE_WITHOUT='development:test',BUNDLE_DEPLOYMENT='true',BUNDLE_FROZEN='true',
             BUNDLE_GEMFILE=str(release/'Gemfile'),DISABLE_BOOTSNAP='1',PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=30000')
    for key,source in zip(('DATABASE_URL','CACHE_DATABASE_URL','QUEUE_DATABASE_URL','CABLE_DATABASE_URL'),production_capture.DATABASES):
        url=urlsplit(values[key])
        if url.hostname!='127.0.0.1' or url.username!='muzeum_runtime' or url.path!='/'+source:
            raise RuntimeError('Unexpected restored runtime connection')
        env[key]=urlunsplit((url.scheme,url.netloc,'/'+targets[source],url.query,url.fragment))
    return env


def verify_application(restored,targets,metadata,invoke):
    release=Path('/var/www/muzeum/current').resolve(strict=True)
    sha = metadata['release_sha']
    if (release.parent != Path('/var/www/muzeum/releases') or not re.fullmatch(r'[0-9]{14}', release.name)
            or not re.fullmatch(r'[a-f0-9]{40}', sha) or (release/'REVISION').read_text().strip() != sha):
        raise RuntimeError('Restore requires the matching reviewed application code')
    values={}
    for line in (restored/'files/var/www/muzeum/shared/.env').read_text().splitlines():
        if line.strip():key,value=line.split('=',1);values[key]=value
    env=recovery_environment(values,targets,release)
    for database in targets.values():
        invoke(['runuser','-u','postgres','--','psql','-X','-v','ON_ERROR_STOP=1','-d',database,'-c',
                'GRANT USAGE ON SCHEMA public TO muzeum_runtime; GRANT SELECT ON ALL TABLES IN SCHEMA public TO muzeum_runtime;'])
    script='''raise 'Unexpected identity' if User.where.not(oidc_subject:nil).any? { |u| !u.login_enabled? && u.disabled_at.nil? }
Session.find_each { |s| raise 'Session recovery failed' if s.grant_token.blank? }
puts 'MUZEUM_RECOVERY_PROOF:'+{users:User.count,sessions:Session.count,scrobbles:Scrobble.count,raw_pages:ImportPage.count,grant_decryption_verified:true}.to_json'''
    ruby = '/opt/muzeum/ruby-3.4.13/bin/'
    result=subprocess.run(['/usr/sbin/runuser','-u','muzeum','--',ruby+'ruby',ruby+'bundle','exec','rails','runner',script],
                          cwd=release,env=env,capture_output=True,text=True,timeout=60)
    if result.returncode:raise RuntimeError('Isolated application identity/session recovery failed')
    line=next((line for line in result.stdout.splitlines() if line.startswith('MUZEUM_RECOVERY_PROOF:')),None)
    if not line:raise RuntimeError('Missing isolated application recovery proof')
    return json.loads(line.split(':',1)[1])


def restore(config,api):
    production_capture.validate(config)
    base=api['BASE'];record=json.loads((base/'state/last-backup.json').read_text())
    if record.get('mode')!='production' or not re.fullmatch('[a-f0-9]{64}',record['snapshot_id']):raise RuntimeError('Expected production snapshot')
    original=Path(record['capture_path'])
    if original.parent!=base/'captures':raise RuntimeError('Unexpected capture path')
    if shutil.disk_usage(base).free<8*1024**3:raise RuntimeError('Insufficient recovery headroom')
    target=base/'restores'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    target.mkdir(parents=True,mode=0o700)
    created=[];targets={};start=time.monotonic()
    with monitoring.job_run('restoration'):
        try:
            api['restic'](config,['restore',record['snapshot_id'],'--target',str(target),'--verify'])
            restored=target/str(original).lstrip('/')
            if api['file_hash'](restored/'manifest.json')!=record['manifest_sha256']:raise RuntimeError('Independent manifest mismatch')
            manifest=json.loads((restored/'manifest.json').read_text())
            for relative,digest in manifest.items():
                path=(restored/relative).resolve(strict=True)
                if not path.is_relative_to(restored.resolve()) or not path.is_file() or api['file_hash'](path)!=digest:raise RuntimeError('Restored source checksum mismatch')
            metadata=json.loads((restored/'production.json').read_text())
            if set(metadata['databases'])!=set(production_capture.DATABASES):raise RuntimeError('Incomplete database capture')
            for source in production_capture.DATABASES:
                name='muzeum_recovery_'+secrets.token_hex(8)
                api['invoke'](['runuser','-u','postgres','--','createdb','--template=template0',name],timeout=30)
                created.append(name);targets[source]=name
                with (restored/'databases'/(source+'.dump')).open('rb') as dump:
                    result=subprocess.run(['runuser','-u','postgres','--','pg_restore','--no-owner','--no-acl','--exit-on-error','--dbname',name],
                                          stdin=dump,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=180)
                if result.returncode:raise RuntimeError('Isolated production restore failed')
                if production_capture.fingerprints(name,restored=True)!=metadata['databases'][source]:raise RuntimeError('Restored table fingerprints differ')
            proof=verify_application(restored,targets,metadata,api['invoke']) if metadata['release_sha'] else None
            result={'application_recovery':proof,'snapshot_id':record['snapshot_id'],'verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    'mode':'production','databases_verified':4,'files_verified':len(manifest),'release_sha':metadata['release_sha'],
                    'seconds':round(time.monotonic()-start,3),'queue_policy':'restore durable primary checkpoints; operator re-enqueues incomplete imports before resuming workers'}
        finally:
            for name in created:
                if not re.fullmatch('muzeum_recovery_[a-f0-9]{16}',name):raise RuntimeError('Unsafe recovery database cleanup')
                api['invoke'](['runuser','-u','postgres','--','dropdb',name],timeout=30)
            if target.parent==base/'restores' and not target.is_symlink():shutil.rmtree(target)
        api['atomic_json'](base/'state/last-production-restore.json',result)
        print(json.dumps(result))
