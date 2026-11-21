"""Exercise the Infrastructure signed fixture publisher with a running Muzeum reader."""

import argparse
import importlib.util
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("infrastructure", type=Path)
infra = parser.parse_args().infrastructure.resolve()
located = importlib.util.spec_from_file_location("fixtures", infra / "tests/test_application_shell_gate.py")
fixtures = importlib.util.module_from_spec(located)
located.loader.exec_module(fixtures)
case = fixtures.GateTests()
case.setUp()
path = case.workspace / "registry.json"
source = """
require "active_support/all"
require "json"
require "digest"
require "uri"
require_relative "./app/services/application_shell_evidence"
require_relative "./app/services/application_shell_registry"
STDOUT.sync = true
STDIN.each_line { |line| puts ApplicationShellRegistry.destinations(line.split, path: ARGV.first).pluck(:name).to_json }
"""
def consumer():
    return subprocess.Popen(["bundle", "exec", "ruby", "-e", source, str(path)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def read(process, eligible="muzeum remote-gaming continuum continuum-engine"):
    process.stdin.write(eligible + "\n")
    process.stdin.flush()
    return json.loads(process.stdout.readline())
def refresh(at=fixtures.NOW):
    return fixtures.refresh(path, case.fetch, [case.publisher_public], clock=lambda: at)
try:
    old = case.release
    refresh()
    with consumer() as first:
        assert read(first) == ["Remote-Gaming", "Library", "Continuum Engine"]
        new = case.publication("1.1.1", 2, name="consumer-patch")
        case.release = new
        refresh()
        assert read(first) == ["Remote-Gaming", "Library"]
        saved = path.read_bytes()
        pointer_sig = new / "current.json.sig"
        original_sig = pointer_sig.read_bytes()
        pointer_sig.write_bytes(b"invalid")
        for scenario in ("tampered", "replay", "expired", "outage"):
            if scenario != "tampered":
                pointer_sig.write_bytes(original_sig)
                case.release = {"replay": old, "expired": new, "outage": case.workspace / "unavailable"}[scenario]
            try:
                refresh(fixtures.NOW + 86400 if scenario == "expired" else fixtures.NOW)
            except (fixtures.GateError, OSError):
                pass
            else:
                raise AssertionError(scenario)
            assert path.read_bytes() == saved
            assert read(first) == ["Remote-Gaming", "Library"]
        first.stdin.close()
    with consumer() as restarted:
        assert read(restarted) == ["Remote-Gaming", "Library"]
        assert read(restarted, "") == []
        restarted.stdin.close()
    print("PASS: two signed versions, live replacement, failed refresh retention, restart, and empty eligibility.")
finally:
    case.doCleanups()
