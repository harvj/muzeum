"""Restore exactly four Muzeum dumps into new isolated temporary databases only."""
import datetime,json,os,pwd,re,secrets,shutil,stat,subprocess,time
from pathlib import Path
import production_capture
import monitoring

RUBY = Path('/opt/muzeum/ruby-3.4.13/bin')
BUNDLE = '/var/www/muzeum/shared/bundle/ruby-3.4.13'
DROP_RECOVERY_TIMEOUT = 90



def recovery_environment(values,targets,release):
    from urllib.parse import urlsplit,urlunsplit
    if set(targets)!=set(production_capture.DATABASES) or any(not re.fullmatch('muzeum_recovery_[a-f0-9]{16}',v) for v in targets.values()):
        raise RuntimeError('Exact isolated recovery targets required')
    env=dict({key:value for key,value in values.items() if not
              key.startswith(('LD_', 'DYLD_', 'BUNDLE_', 'RUBY', 'GEM_', 'RBENV_'))},
             HOME='/home/muzeum', PATH=f'{RUBY}:/usr/bin:/bin', BUNDLE_PATH=BUNDLE,
             BUNDLE_IGNORE_CONFIG='1',BUNDLE_WITHOUT='development:test',BUNDLE_DEPLOYMENT='true',BUNDLE_FROZEN='true',
             BUNDLE_GEMFILE=str(release/'Gemfile'),DISABLE_BOOTSNAP='1',PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=30000')
    for key,source in zip(('DATABASE_URL','CACHE_DATABASE_URL','QUEUE_DATABASE_URL','CABLE_DATABASE_URL'),production_capture.DATABASES):
        url=urlsplit(values[key])
        if url.hostname!='127.0.0.1' or url.username!='muzeum_runtime' or url.path!='/'+source:
            raise RuntimeError('Unexpected restored runtime connection')
        env[key]=urlunsplit((url.scheme,url.netloc,'/'+targets[source],url.query,url.fragment))
    return env


def retained_release(sha, releases=Path('/var/www/muzeum/releases')):
    if not isinstance(sha, str) or not re.fullmatch(r'[a-f0-9]{40}', sha):
        raise RuntimeError('Invalid snapshot application revision')
    for release in sorted(releases.iterdir(), reverse=True):
        if not re.fullmatch(r'[0-9]{14}', release.name) or release.is_symlink() or not release.is_dir():
            continue
        revision = release / 'REVISION'
        if revision.is_symlink() or not revision.is_file():
            continue
        if revision.read_text().strip() == sha:
            return release
    raise RuntimeError('Snapshot application revision is missing from retained Muzeum releases')


def verify_retained_tree(release, sha, invoke):
    app = release.parent.parent
    shared_tmp = app / 'shared/tmp'
    shared_runtime = (release / 'tmp').is_symlink()
    if shared_runtime:
        account = pwd.getpwnam('muzeum')
        for location in (shared_tmp, shared_tmp / 'pids', shared_tmp / 'sockets'):
            info = location.lstat()
            if (location.resolve(strict=True) != location or not stat.S_ISDIR(info.st_mode)
                    or (info.st_uid, info.st_gid) != (account.pw_uid, account.pw_gid)
                    or info.st_mode & 0o027):
                raise RuntimeError('Unsafe Muzeum shared runtime directory')
    # Apply the minimal Capistrano tree check under its trusted deployment identity.
    script = """set -eu
index=$(mktemp -d)
trap 'rm -rf -- "$index"' EXIT
export GIT_INDEX_FILE="$index/index"
git --no-replace-objects --git-dir="$1" --work-tree="$2" read-tree "$3"
for link in .env storage log; do
    test "$(readlink "$2/$link")" = "$4/$link"
done
if test "$5" = shared; then
    test "$(readlink "$2/tmp")" = "$4/tmp"
    set -- "$@" tmp/.keep tmp/pids/.keep tmp/storage/.keep
else
    test ! -L "$2/tmp"
    for link in tmp/pids tmp/sockets; do
        test "$(readlink "$2/$link")" = "$4/$link"
    done
    set -- "$@" tmp/pids/.keep
fi
git_dir=$1 work_tree=$2 revision=$3
shift 5
git --no-replace-objects --git-dir="$git_dir" --work-tree="$work_tree" update-index --skip-worktree -- log/.keep storage/.keep "$@"
git --no-replace-objects --git-dir="$git_dir" --work-tree="$work_tree" update-index --refresh
git --no-replace-objects --git-dir="$git_dir" --work-tree="$work_tree" diff-index --exit-code "$revision" --
"""
    invoke(['/usr/sbin/runuser', '-u', 'muzeum', '--', '/bin/bash', '-c', script,
            'verify-tree', str(app/'repo'), str(release), sha, str(app/'shared'), 'shared' if shared_runtime else 'legacy'], timeout=60)
    if shared_runtime:
        invoke(['/usr/sbin/runuser', '-u', 'muzeum', '--', str(RUBY/'ruby'),
                str(release/'script/muzeum_release_identity.rb'), 'verify', sha], timeout=60)

    assets = release / 'public/assets'
    manifest = assets / '.manifest.json'
    if (not assets.is_dir() or assets.resolve(strict=True) != assets
            or not manifest.is_file() or manifest.is_symlink()):
        raise RuntimeError('Recovery requires release-local Propshaft assets')
    entries = json.loads(manifest.read_text())
    if not isinstance(entries, dict) or not {'application.css', 'application.js'} <= entries.keys():
        raise RuntimeError('Recovery asset manifest is missing application entry points')
    for entry in entries.values():
        relative = entry['digested_path'] if isinstance(entry, dict) else entry
        path = assets / relative
        if (not path.is_relative_to(assets) or not path.is_file()
                or path.resolve(strict=True) != path or not path.stat().st_size):
            raise RuntimeError('Recovery asset manifest references an unsafe or missing file')


def verify_application(restored,targets,metadata,invoke):
    sha = metadata['release_sha']
    release = retained_release(sha)
    verify_retained_tree(release, sha, invoke)
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
    result=subprocess.run(['/usr/sbin/runuser','-u','muzeum','--',str(RUBY/'ruby'),str(RUBY/'bundle'),
                           'exec','rails','runner',script],
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
            import sys
            restore_failed = sys.exc_info()[0] is not None
            cleanup_failures = []
            for name in created:
                if not re.fullmatch('muzeum_recovery_[a-f0-9]{16}',name):raise RuntimeError('Unsafe recovery database cleanup')
                started_drop = time.monotonic()
                try:
                    api['invoke'](['runuser','-u','postgres','--','dropdb',name],
                                  timeout=DROP_RECOVERY_TIMEOUT)
                except (RuntimeError, subprocess.TimeoutExpired) as error:
                    cleanup_failures.append(name)
                    print(f'Isolated recovery DROP DATABASE {name} failed after '
                          f'{time.monotonic()-started_drop:.1f}s ({type(error).__name__})',
                          file=sys.stderr)
            if not cleanup_failures and target.parent==base/'restores' and not target.is_symlink():
                shutil.rmtree(target)
            if cleanup_failures and not restore_failed:
                raise RuntimeError('Isolated recovery database cleanup failed')
        api['atomic_json'](base/'state/last-production-restore.json',result)
        print(json.dumps(result))
