"""Restore exactly four Muzeum dumps into new isolated temporary databases only."""
import datetime,json,os,re,secrets,shutil,subprocess,time
from pathlib import Path
import production_capture
import monitoring


def restore(config,api):
    production_capture.validate(config)
    base=api['BASE'];record=json.loads((base/'state/last-backup.json').read_text())
    if record.get('mode')!='production' or not re.fullmatch('[a-f0-9]{64}',record['snapshot_id']):raise RuntimeError('Expected production snapshot')
    original=Path(record['capture_path'])
    if original.parent!=base/'captures':raise RuntimeError('Unexpected capture path')
    if shutil.disk_usage(base).free<8*1024**3:raise RuntimeError('Insufficient recovery headroom')
    target=base/'restores'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    target.mkdir(parents=True,mode=0o700)
    created=[];start=time.monotonic()
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
                created.append(name)
                with (restored/'databases'/(source+'.dump')).open('rb') as dump:
                    result=subprocess.run(['runuser','-u','postgres','--','pg_restore','--no-owner','--no-acl','--exit-on-error','--dbname',name],
                                          stdin=dump,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=180)
                if result.returncode:raise RuntimeError('Isolated production restore failed')
                if production_capture.fingerprints(name,restored=True)!=metadata['databases'][source]:raise RuntimeError('Restored table fingerprints differ')
            result={'snapshot_id':record['snapshot_id'],'verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    'mode':'production','databases_verified':4,'files_verified':len(manifest),'release_sha':metadata['release_sha'],
                    'seconds':round(time.monotonic()-start,3),'queue_policy':'restore durable primary checkpoints; operator re-enqueues incomplete imports before resuming workers'}
            api['atomic_json'](base/'state/last-production-restore.json',result)
            print(json.dumps(result))
        finally:
            for name in created:
                if not re.fullmatch('muzeum_recovery_[a-f0-9]{16}',name):raise RuntimeError('Unsafe recovery database cleanup')
                api['invoke'](['runuser','-u','postgres','--','dropdb',name],timeout=30)
            if target.parent==base/'restores' and not target.is_symlink():shutil.rmtree(target)
