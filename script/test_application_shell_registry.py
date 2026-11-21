"""Exercise the Infrastructure signed fixture publisher with a running Muzeum reader."""

import argparse
import importlib.util
import json
import shutil
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
        new = case.workspace / "consumer-patch"
        payloads = {name: (fixtures.ROOT / path).read_bytes() for name, path in fixtures.PAYLOADS.items()}
        name = "application-shell-registry.json"
        registry = fixtures.decode(payloads[name])
        registry["specification_version"] = "1.1.1"
        registry["applications"][-1]["availability"] = "withdrawn"
        registry["applications"][2:2] = [
            {"id": app, "name": app.title(), "canonical_url": f"https://{app}.example/", "availability": "production"}
            for app in ("zebra", "apple")
        ]
        payloads[name] = fixtures.encode(registry)
        fixtures.publisher.build_publication(new, "b" * 40, "1.1.1", "shell-v1", 2, fixtures.NOW - 10,
                                             payloads, case.publisher_key)
        case.release = new
        approved = "muzeum remote-gaming zebra apple continuum continuum-engine"
        expected = ["Remote-Gaming", "Zebra", "Apple", "Library"]
        refresh()
        assert read(first, approved) == expected
        unsupported = case.workspace / "unsupported-schema"
        shutil.copytree(new, unsupported)
        manifest_path = unsupported / "versions/1.1.1/manifest.json"
        manifest = fixtures.decode(manifest_path.read_bytes())
        manifest["registry_schema"] = 2
        raw_manifest = fixtures.encode(manifest)
        manifest_path.write_bytes(raw_manifest)
        pointer_path = unsupported / "current.json"
        pointer = fixtures.decode(pointer_path.read_bytes())
        pointer.update(sequence=3, manifest_sha256=fixtures.digest(raw_manifest))
        pointer_path.write_bytes(fixtures.encode(pointer))
        case.sign(pointer_path, case.publisher_key)
        saved = path.read_bytes()
        pointer_sig = new / "current.json.sig"
        original_sig = pointer_sig.read_bytes()
        pointer_sig.write_bytes(b"invalid")
        for scenario in ("tampered", "replay", "expired", "outage", "unsupported"):
            if scenario != "tampered":
                pointer_sig.write_bytes(original_sig)
                case.release = {"replay": old, "expired": new, "outage": case.workspace / "unavailable", "unsupported": unsupported}[scenario]
            try:
                refresh(fixtures.NOW + 86400 if scenario == "expired" else fixtures.NOW)
            except (fixtures.GateError, OSError):
                pass
            else:
                raise AssertionError(scenario)
            assert path.read_bytes() == saved
            assert read(first, approved) == expected
        first.stdin.close()
    with consumer() as restarted:
        assert read(restarted, approved) == expected
        assert read(restarted, "") == []
        restarted.stdin.close()
    print("PASS: two signed versions, live replacement, insertion order, unsupported schema, failed refresh retention, restart, and empty eligibility.")
finally:
    case.doCleanups()
