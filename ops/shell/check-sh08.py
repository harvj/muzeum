#!/usr/bin/env python3
"""Verify SH-08 through the existing signed verifier and retained evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def run(*argv):
    return subprocess.check_output(argv, text=True)


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def github_run(run_id):
    result = run("gh", "run", "view", run_id, "--repo", "harvj/muzeum", "--json",
                 "headSha,headBranch,event,conclusion,jobs,url")
    return json.loads(result)


def successful_steps(result):
    return {step["name"] for job in result["jobs"] if job["conclusion"] == "success"
            for step in job["steps"] if step["conclusion"] == "success"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-run")
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--sha256")
    parser.add_argument("--transcript", type=Path)
    parser.add_argument("--transcript-sha256")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    revision = os.environ["APPLICATION_SHELL_REVISION"]
    version = os.environ["APPLICATION_SHELL_VERSION"]
    verifier = Path(os.environ["APPLICATION_SHELL_VERIFIER"]) / "bin/application-shell-preflight"
    requirements = json.loads(run(str(verifier), "--app", "muzeum", "--revision", revision,
                                  "--version", version, "--adopted-version", "2.0.0", "--describe"))
    exception = {"id": "muzeum-public-profiles", "application": "muzeum",
                 "scope": "Additional public Archive and catalog links on public profiles"}
    require(requirements["exceptions"] == {exception["id"]: exception}, "SH-08 exception scope changed")
    registry = json.loads(Path(os.environ["APPLICATION_SHELL_REGISTRY"]).read_text())
    app = [entry for entry in registry["applications"] if entry["id"] == "muzeum"]
    require(len(app) == 1 and app[0]["canonical_url"] == "https://muzeum.fm/" and
            app[0]["availability"] == "production", "Muzeum canonical origin changed in the signed registry")

    controls = "2c2ed7fd8ef413cffce3e444e1e81a4f6ff9e32c"
    require(not run("git", "diff", "--name-only", controls, revision, "--", "ops/deploy",
                    "ops/provision", "ops/backups", "config/deploy.rb", "config/deploy"),
            "Muzeum deployment or recovery controls changed since the isolation rehearsal")
    isolation = github_run("45709546534")
    require(isolation["headSha"] == "dbf36a9bc2b00b69c2f584c3616e775c6f7431d2" and
            isolation["conclusion"] == "success" and "Boot both sealed releases with real systemd services"
            in successful_steps(isolation), "Isolated two-release systemd rehearsal is unavailable")
    installed = json.loads(run("gh", "api", "repos/harvj/muzeum/issues/comments/7176090204"))
    require(controls in installed["body"] and "four-database recovery receipt" in installed["body"],
            "Installed isolation and recovery evidence is unavailable")
    checks = {"application": "muzeum", "revision": revision, "exception": exception,
              "exception_policy_sha256": requirements["exception_policy_sha256"],
              "isolation": isolation["url"], "recovery": installed["html_url"], "controls_source": controls}

    if args.artifact:
        require(all((args.release_run, args.sha256, args.transcript, args.transcript_sha256)),
                "Retained acceptance needs a release run and pinned artifact and transcript digests")
        ci = github_run(args.release_run)
        require(ci["headSha"] == revision and ci["conclusion"] == "success" and ci["event"] == "push" and
                ci["headBranch"].startswith("release/v") and "Run bundle exec rspec" in successful_steps(ci) and
                "Rehearse Muzeum deploy success and failure paths in disposable databases" in successful_steps(ci),
                "Exact release-branch browser and recovery checks must pass")
        identity = json.loads(run("ruby", str(args.artifact / "script/muzeum_release_identity.rb"), "verify", revision))
        require(identity["artifact_sha256"] == args.sha256, "Retained artifact digest mismatch")
        require(digest(args.transcript) == args.transcript_sha256, "Disposable boot transcript digest mismatch")
        transcript = args.transcript.read_text()
        routes = ["/archive", "/artists", "/recordings", "/releases", "/resolution"]
        require(all(f"{route} 200" in transcript.splitlines() for route in routes) and
                "Started Supervisor" in transcript and "Started Worker" in transcript and
                "Exact digest unchanged" in transcript, "Disposable runtime acceptance is incomplete")
        checks.update(artifact=identity, release_ci=ci["url"], authenticated_routes=routes,
                      disposable_runtime_sha256=args.transcript_sha256)
    else:
        subprocess.run(["bundle", "exec", "rspec", "spec/system/sign_in_spec.rb",
                        "spec/system/public_profiles_spec.rb", "spec/system/canonical_library_spec.rb",
                        "-e", "three production-derived", "-e", "protects the archive",
                        "-e", "keeps both anonymous entry points"],
                       check=True)
        checks["source_browser_coverage"] = ["public landing", "local login", "public profile navigation", "Resolution"]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(checks, sort_keys=True, indent=2) + "\n")
    require(args.artifact is not None, "Source checks passed; exact staged runtime evidence is required at preflight")


if __name__ == "__main__":
    main()
