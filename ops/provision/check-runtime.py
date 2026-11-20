#!/usr/bin/env python3
"""Private operator verification using Muzeum's restricted runtime credentials."""
import json,os,re,subprocess,sys
from pathlib import Path
try:
    if os.geteuid()!=0 or len(sys.argv) not in (2,3):raise RuntimeError()
    action=sys.argv[1];reference=sys.argv[2] if len(sys.argv)==3 else ''
    if action not in ('enqueue','probe','status','session') or (action in ('enqueue','probe') and not re.fullmatch('[a-f0-9]{32}',reference)):raise RuntimeError()
    release=Path('/var/www/muzeum/current').resolve(strict=True)
    if release.parent!=Path('/var/www/muzeum/releases'):raise RuntimeError()
    env={'LANG':'C.UTF-8',
         'HOME':'/home/muzeum','BUNDLE_IGNORE_CONFIG':'1','BUNDLE_DEPLOYMENT':'true','BUNDLE_FROZEN':'true',
         'BUNDLE_WITHOUT':'development:test','BUNDLE_GEMFILE':str(release/'Gemfile'),'MUZEUM_PROBE_REFERENCE':reference}
    for line in Path('/var/www/muzeum/shared/.env').read_text().splitlines():
        if line.strip():name,value=line.split('=',1);env[name]=value
    sys.path.insert(0, '/usr/local/lib/muzeum-runtime')
    from muzeum_runtime import release_runtime, runtime_environment
    directory, bundle_path = release_runtime(release)
    env = runtime_environment(env, directory, bundle_path)
    env.update(BUNDLE_IGNORE_CONFIG='1', BUNDLE_DEPLOYMENT='true', BUNDLE_FROZEN='true', BUNDLE_WITHOUT='development:test')
    script={
     'enqueue':'OpsProbeJob.set(wait: 15.seconds).perform_later(ENV.fetch("MUZEUM_PROBE_REFERENCE")); puts "Durable probe queued"',
     'probe':'puts({completed_at: Rails.cache.read("muzeum/worker-probe/#{ENV.fetch("MUZEUM_PROBE_REFERENCE")}")}.to_json)',
     'session':'''record=Session.unexpired.order(created_at: :desc).first; puts(record ? {sessions:Session.unexpired.count,age_seconds:(Time.current-record.created_at).to_i,last_seen_at:record.last_seen_at,verified_at:record.verified_at,grant_active:OidcClient.new.active?(record.grant_token,subject:record.user.oidc_subject)}.to_json : {sessions:0}.to_json)''',
     'status':'''ActiveRecord::Base.transaction(isolation: :repeatable_read) do; ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY'); run=ImportRun.order(:created_at).last;puts({observed_at:Time.current.utc.iso8601,revision:File.read('REVISION').strip,users:User.count,sessions:Session.unexpired.count,scrobbles:Scrobble.count,raw_pages:ImportPage.count,canonical_recordings:Recording.count,import:run && {status:run.status,page:run.next_page,inserted:run.scrobbles_processed,total:run.expected_count,total_pages:run.total_pages,last_error:run.last_error}}.to_json);end'''
    }[action]
    result=subprocess.run(['/usr/sbin/runuser','-u','muzeum','--',str(directory / 'bundle'),'exec','rails','runner',script],
                          env=env,cwd=release,capture_output=True,text=True,timeout=45)
    if result.returncode:
        fd=os.open('/etc/muzeum/runtime-last-error',os.O_WRONLY|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'w') as out:out.write(result.stderr)
        raise RuntimeError()
    print(result.stdout)
except Exception:
    print('Muzeum runtime verification stopped; sensitive details suppressed.',file=sys.stderr)
    raise SystemExit(1)
