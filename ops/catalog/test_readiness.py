import contextlib
import datetime as dt
import io
import unittest
from unittest.mock import patch

import readiness


class ReadinessTests(unittest.TestCase):
    def snapshot(self, enabled):
        queues = "imports,default" + (",canonical_catalog" if enabled else "")
        return {
            "processes": [
                {"kind": kind, "age": 4, "metadata": {"queues": queues, "pool_size": 1} if kind == "Worker" else None}
                for kind in readiness.KINDS
            ],
            "ingestion": {"completed": 2, "unfinished": 0, "failed": 0},
        }

    def test_activation_and_rollback_subscriptions(self):
        for enabled in (True, False):
            snapshot = self.snapshot(enabled)
            catalog = "on" if enabled else "off"
            self.assertTrue(all(ok for ok, _ in readiness.queue_checks(snapshot, catalog).values()))
            wrong_catalog = "off" if enabled else "on"
            self.assertFalse(readiness.queue_checks(snapshot, wrong_catalog)["Queue subscription"][0])

    def test_heartbeat_and_ingestion_fail_independently(self):
        snapshot = self.snapshot(True)
        snapshot["processes"][0]["age"] = readiness.HEARTBEAT_MAX_AGE + 1
        snapshot["ingestion"]["completed"] = 0
        checks = readiness.queue_checks(snapshot, "on")
        self.assertTrue(checks["Queue subscription"][0])
        self.assertFalse(checks["Solid Queue heartbeats"][0])
        self.assertFalse(checks["Last.fm ingestion"][0])

    def test_wait_reports_recovery_from_startup_502(self):
        now = dt.datetime.now(dt.timezone.utc)
        with patch.object(readiness, "probe", side_effect=[
            {"Public HTTP": (False, "HTTP 502")}, {"Public HTTP": (True, "HTTP 200")},
        ]), patch.object(readiness.time, "sleep"), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(readiness.wait("on", now), 0)
        self.assertIn("WAIT  Public HTTP", output.getvalue())
        self.assertIn("PASS  Public HTTP", output.getvalue())

    def test_timeout_names_failed_condition(self):
        now = dt.datetime.now(dt.timezone.utc)
        checks = {"Public HTTP": (True, "HTTP 200"), "Queue subscription": (False, "unexpected")}
        with patch.object(readiness, "probe", return_value=checks), patch.object(
            readiness.time, "monotonic", side_effect=[0, readiness.TIMEOUT]
        ), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(readiness.wait("on", now), 1)
        self.assertIn("PASS  Public HTTP", output.getvalue())
        self.assertIn("FAIL  Queue subscription", output.getvalue())
