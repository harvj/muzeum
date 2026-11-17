"""Probe the installed read-only Rails inspector against four disposable application schemas."""
import getpass
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.environ.get('MUZEUM_DEPLOY_TEST_PGPORT'), 'Dedicated disposable PostgreSQL port required')
class InspectionTests(unittest.TestCase):
    @classmethod
    def invoke(cls, argv, env=None, input=None, success=True):
        result = subprocess.run(argv, env=env or cls.admin, input=input, capture_output=True, text=True, timeout=120)
        if success and result.returncode:
            raise RuntimeError('Disposable inspector fixture failed: ' + result.stderr[:2000])
        return result

    @classmethod
    def sql(cls, database, sql):
        return cls.invoke([str(cls.pg / 'psql'), '-XAt', '-v', 'ON_ERROR_STOP=1', '-d', database], input=sql).stdout.strip()

    @classmethod
    def setUpClass(cls):
        cls.pg = Path(os.environ.get('MUZEUM_DEPLOY_TEST_PGBIN', '/usr/bin'))
        cls.admin = dict(os.environ, PGHOST='127.0.0.1', PGPORT=os.environ['MUZEUM_DEPLOY_TEST_PGPORT'])
        # These production-like role names exist ONLY in the explicitly disposable cluster.
        roles = cls.sql('postgres', "SELECT count(*) FROM pg_roles WHERE rolname IN ('muzeum_runtime','muzeum_migrator','muzeum_owner')")
        if roles != '0':
            raise RuntimeError('Use a dedicated disposable cluster without Muzeum roles')
        cls.databases = []
        cls.addClassCleanup(cls.cleanup)
        cls.sql('postgres', "CREATE ROLE muzeum_runtime LOGIN PASSWORD 'disposable-fixture'; CREATE ROLE muzeum_migrator NOLOGIN; CREATE ROLE muzeum_owner NOLOGIN;")
        cls.databases = ['muzeum_deploy_test_' + secrets.token_hex(6) for _ in range(4)]
        for database in cls.databases:
            cls.invoke([str(cls.pg / 'createdb'), database])
        cls.temporary = tempfile.TemporaryDirectory(prefix='muzeum-inspector-')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.env = dict(cls.admin, RAILS_ENV='production', SECRET_KEY_BASE_DUMMY='1', BOOTSNAP_READONLY='1', SCHEMA=str(Path(cls.temporary.name) / 'structure.sql'))
        for key, database in zip(('DATABASE_URL', 'CACHE_DATABASE_URL', 'QUEUE_DATABASE_URL', 'CABLE_DATABASE_URL'), cls.databases):
            cls.env[key] = 'postgresql://' + cls.admin.get('PGUSER', getpass.getuser()) + '@127.0.0.1:' + cls.admin['PGPORT'] + '/' + database
        bootstrap = """%w[cache queue cable].each do |name|
 config=ActiveRecord::Base.configurations.configs_for(env_name:'production',name:name)
 ActiveRecord::Base.establish_connection(config)
 raise 'Fixture not empty' unless ActiveRecord::Base.connection.tables.empty?
 load Rails.root.join('db',name+'_schema.rb')
end"""
        cls.invoke(['bundle', 'exec', 'rails', 'runner', '-'], env=cls.env, input=bootstrap)
        cls.invoke(['bundle', 'exec', 'rails', 'db:migrate:primary'], env=cls.env)
        for key, database in zip(('DATABASE_URL', 'CACHE_DATABASE_URL', 'QUEUE_DATABASE_URL', 'CABLE_DATABASE_URL'), cls.databases):
            cls.sql(database, 'GRANT USAGE ON SCHEMA public TO muzeum_runtime; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO muzeum_runtime; GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO muzeum_runtime;')
            cls.env[key] = 'postgresql://muzeum_runtime:disposable-fixture@127.0.0.1:' + cls.admin['PGPORT'] + '/' + database
        cls.sql(cls.databases[2], "INSERT INTO solid_queue_processes(kind,last_heartbeat_at,pid,created_at,name) SELECT kind,CURRENT_TIMESTAMP AT TIME ZONE 'UTC',123,CURRENT_TIMESTAMP AT TIME ZONE 'UTC',kind FROM unnest(ARRAY['Supervisor(fork)','Dispatcher','Worker','Scheduler']) kind")
        cls.env['MUZEUM_DEPLOY_CHECK_HEALTH'] = '1'

    @classmethod
    def cleanup(cls):
        for database in cls.databases:
            assert database.startswith('muzeum_deploy_test_')
            cls.invoke([str(cls.pg / 'dropdb'), '--if-exists', database])
        cls.sql('postgres', 'DROP ROLE muzeum_runtime; DROP ROLE muzeum_migrator; DROP ROLE muzeum_owner;')

    def inspect(self, success=True):
        return self.invoke(['bundle', 'exec', 'rails', 'runner', str(Path(__file__).with_name('inspect.rb').resolve())], env=self.env, success=success)

    def test_all_four_schemas_grants_migration_versions_and_source_protection_pass(self):
        output = self.inspect().stdout
        line = next(line for line in output.splitlines() if line.startswith('MUZEUM_DEPLOY_INSPECTION:'))
        report = json.loads(line.split(':', 1)[1])
        self.assertEqual(set(report['databases']), {'primary', 'cache', 'queue', 'cable'})
        self.assertEqual(report['pending'], [])
        self.assertGreater(len(report['databases']['primary']['triggers']), 10)

    def test_missing_runtime_grant_is_rejected(self):
        self.sql(self.databases[0], 'REVOKE INSERT ON scrobbles FROM muzeum_runtime')
        try:
            result = self.inspect(success=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Missing runtime privilege', result.stderr)
        finally:
            self.sql(self.databases[0], 'GRANT INSERT ON scrobbles TO muzeum_runtime')

    def test_missing_source_protection_is_rejected(self):
        self.sql(self.databases[0], 'ALTER TABLE scrobbles DISABLE TRIGGER preserve_scrobble_source')
        try:
            result = self.inspect(success=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Disabled source protection', result.stderr)
        finally:
            self.sql(self.databases[0], 'ALTER TABLE scrobbles ENABLE TRIGGER preserve_scrobble_source')

    def test_stale_worker_heartbeat_is_rejected(self):
        self.sql(self.databases[2], "UPDATE solid_queue_processes SET last_heartbeat_at=(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')-INTERVAL '1 day' WHERE kind='Worker'")
        try:
            result = self.inspect(success=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('heartbeat unavailable', result.stderr)
        finally:
            self.sql(self.databases[2], "UPDATE solid_queue_processes SET last_heartbeat_at=CURRENT_TIMESTAMP AT TIME ZONE 'UTC' WHERE kind='Worker'")

    def test_invented_plain_supervisor_label_is_not_accepted(self):
        self.sql(self.databases[2], "UPDATE solid_queue_processes SET kind='Supervisor' WHERE kind='Supervisor(fork)'")
        try:
            result = self.inspect(success=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('heartbeat unavailable', result.stderr)
        finally:
            self.sql(self.databases[2], "UPDATE solid_queue_processes SET kind='Supervisor(fork)' WHERE kind='Supervisor'")
