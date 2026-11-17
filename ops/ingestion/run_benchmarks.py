import os, subprocess
from pathlib import Path
pg='/opt/homebrew/opt/postgresql@16/bin/'
for mode in os.environ.get('BENCHMARK_MODES','A,B,C').split(','):
 for repetition in range(1,2 if mode=='C' else 4):
  database=f'muzeum_p12_bench_{mode.lower()}{repetition}'
  subprocess.run([pg+'dropdb','-h','127.0.0.1','-p','56491','--if-exists',database],check=True)
  subprocess.run([pg+'createdb','-h','127.0.0.1','-p','56491','-T','muzeum_p12_template',database],check=True)
  env=os.environ.copy();env.update(DATABASE_URL=f'postgres://jim@127.0.0.1:56491/{database}',RAILS_ENV='test',FIXTURE_DIR='/private/tmp/muzeum-p12-fixture',BENCHMARK_MODE=mode,RESULT_PATH=str(Path.cwd()/f'docs/p1.2/evidence/benchmark-{mode.lower()}{repetition}.json'))
  with open(f'/private/tmp/muzeum-p12-bench-{mode.lower()}{repetition}.log','w') as log:
   result=subprocess.run(['/usr/bin/time','-l','bundle','exec','rails','runner','ops/ingestion/benchmark.rb'],env=env,stdout=log,stderr=subprocess.STDOUT)
  if result.returncode: raise SystemExit(f'Benchmark {mode}{repetition} failed; retain DB/log for inspection')
  import re,json
  result_path=Path(env['RESULT_PATH']);data=json.loads(result_path.read_text())
  timing=Path(f'/private/tmp/muzeum-p12-bench-{mode.lower()}{repetition}.log').read_text()
  maximum=re.search(r'(\d+)\s+maximum resident set size',timing)
  data['external_peak_rss_bytes']=int(maximum.group(1)) if maximum else None
  result_path.write_text(json.dumps(data,indent=2)+'\n')
  print(f'Completed {mode}{repetition}',flush=True)
