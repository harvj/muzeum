import copy
import json
import subprocess
import unittest
from unittest import mock

import manage_healthchecks as management


class ManagementTests(unittest.TestCase):
    def fixture(self):
        checks = [{'uuid': 'daily', 'name': 'Muzeum - Daily Backup', 'channels': 'email',
                   'ping_url': 'https://hc-ping.com/00000000-0000-0000-0000-000000000001',
                   'timeout': 86400, 'grace': 7200}]
        calls = []

        def api(method, path, payload=None):
            calls.append((method, path))
            if path == 'channels/':
                return {'channels': [{'id': 'email', 'kind': 'email'}]}
            if method == 'POST':
                identifier = '00000000-0000-0000-0000-' + str(len(checks) + 1).zfill(12)
                check = {**payload, 'uuid': identifier, 'ping_url': 'https://hc-ping.com/' + identifier}
                checks.append(check)
                return copy.deepcopy(check)
            return {'checks': copy.deepcopy(checks)}
        return checks, calls, api

    def test_create_then_rerun_preserves_daily_and_avoids_duplicates(self):
        checks, calls, api = self.fixture()
        before = copy.deepcopy(checks[0])
        urls, created = management.reconcile(api, {'backup': checks[0]['ping_url']})
        self.assertEqual(created, ['verification', 'restoration'])
        self.assertEqual(checks[0], before)
        second, created = management.reconcile(api, urls)
        self.assertEqual(created, [])
        self.assertEqual(second, urls)
        self.assertEqual(len(checks), 3)
        self.assertEqual(sum(method == 'POST' for method, _ in calls), 2)

    def test_conflicting_existing_schedule_is_not_updated(self):
        checks, calls, api = self.fixture()
        checks.append({**management.SPECS['verification'], 'schedule': '0 1 * * 0',
                       'uuid': 'conflict', 'channels': 'email'})
        with self.assertRaises(RuntimeError):
            management.reconcile(api, {'backup': checks[0]['ping_url']})
        self.assertFalse(any(method == 'POST' for method, _ in calls))

    def test_credentials_only_in_stdin_and_bounded_request(self):
        key = 'test-only-key-' + 'x' * 32
        result = subprocess.CompletedProcess([], 0, json.dumps({'checks': []}) + '\n200', '')
        with mock.patch.object(management.subprocess, 'run', return_value=result) as run:
            management.api_client(key)('GET', 'checks/')
            args, kwargs = run.call_args
            self.assertNotIn(key, repr(args))
            self.assertIn(key, kwargs['input'])
            self.assertEqual(kwargs['timeout'], 12)
            self.assertNotIn('--location', args[0])


if __name__ == '__main__':
    unittest.main()
