#!/usr/bin/env python3
"""Portable Swift quality gate installed by CI Scope.

The checker intentionally uses only Python's standard library so it can be
copied into Swift repositories without requiring a package manager for the
Python side of the workflow.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


DEFAULT_IGNORE = [
    ".git",
    ".svn",
    ".hg",
    ".build",
    ".dart_tool",
    ".gradle",
    ".next",
    ".nuxt",
    ".pytest_cache",
    ".tox",
    ".venv",
    "DerivedData",
    "Pods",
    "bin",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "obj",
    "out",
    "target",
    "vendor",
    "*.designer.swift",
    "*.generated.*",
    "*.g.swift",
    "*.gen.*",
    "*.snap",
    "*.snapshot",
]

DEFAULT_CONFIG = {
    "ignore": DEFAULT_IGNORE,
    "xcode_workspace": "",
    "xcode_project": "",
    "xcode_scheme": "",
    "xcode_destination": "generic/platform=macOS",
    "xcode_configuration": "Debug",
    "swift_format_config": ".swift-format",
    "fallback_swift_format_config": ".ci-scope-swift-format.json",
    "dead_code_enabled": True,
    "dead_code_install_periphery": True,
    "periphery_arguments": [],
}


@dataclass(frozen=True)
class SwiftProject:
    kind: str
    project_path: str | None = None
    scheme: str | None = None
    destination: str = ""
    configuration: str = "Debug"


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    root = Path(args.root).resolve()
    config = load_config(root / args.config)

    if args.stage == "all":
        for stage in ("build", "format", "dead-code"):
            run_stage(stage, root, config, args)
        return 0

    run_stage(args.stage, root, config, args)
    return 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Swift build, format, and dead-code gates.")
    parser.add_argument("--stage", choices=("all", "build", "format", "dead-code"), default="all")
    parser.add_argument("--mode", choices=("all", "changed"), default="all")
    parser.add_argument("--base", default="origin/main", help="Base ref for changed mode.")
    parser.add_argument("--head", default="HEAD", help="Head ref for changed mode.")
    parser.add_argument("--config", default=".swift-quality-gate.json")
    parser.add_argument("--root", default=".")
    return parser.parse_args(argv)


def run_stage(stage: str, root: Path, config: dict, args: argparse.Namespace) -> None:
    title = {
        "build": "Build",
        "format": "Format",
        "dead-code": "DeadCodeGate",
    }[stage]
    print(f"::group::{title}", flush=True)
    try:
        if stage == "build":
            run_build(root, config)
        elif stage == "format":
            run_format(root, config, args)
        elif stage == "dead-code":
            run_dead_code(root, config)
    finally:
        print("::endgroup::", flush=True)


def load_config(path: Path) -> dict:
    config = dict(DEFAULT_CONFIG)
    config["ignore"] = list(DEFAULT_IGNORE)
    config["periphery_arguments"] = []

    if path.exists():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            error(github_path(path), 1, "invalid_config", f"Invalid JSON config: {exc}")
            sys.exit(2)
        if not isinstance(loaded, dict):
            error(github_path(path), 1, "invalid_config", "Swift quality gate config must be a JSON object.")
            sys.exit(2)
        config.update(loaded)

    config["ignore"] = list(config.get("ignore", []))
    config["periphery_arguments"] = list(config.get("periphery_arguments", []))
    return config


def run_build(root: Path, config: dict) -> None:
    project = detect_project(root, config)
    if project.kind == "spm":
        run(["swift", "build"], root)
        return

    cmd = xcodebuild_base_command(project)
    cmd.append("build")
    run(cmd, root)


def run_format(root: Path, config: dict, args: argparse.Namespace) -> None:
    swift_files = collect_swift_paths(root, config, args)
    if not swift_files:
        print(f"Swift format skipped: no Swift files in {args.mode} mode.")
        return

    formatter = ["xcrun", "swift-format", "lint", "--strict", "--parallel"]
    format_config = swift_format_config(root, config)
    if format_config is not None:
        formatter.extend(["--configuration", str(format_config)])
    formatter.extend([str(path) for path in swift_files])
    run(formatter, root)


def run_dead_code(root: Path, config: dict) -> None:
    if not bool(config.get("dead_code_enabled", True)):
        print("DeadCodeGate skipped: dead_code_enabled is false.")
        return
    if not collect_swift_paths(root, config, argparse.Namespace(mode="all", base="", head="")):
        print("DeadCodeGate skipped: no Swift files found.")
        return

    periphery = ensure_periphery(config)
    project = detect_project(root, config)
    cmd = [periphery, "scan", "--format", "xcode"]
    cmd.extend(str(arg) for arg in config.get("periphery_arguments", []))

    if project.kind == "xcode-workspace":
        cmd.extend(["--workspace", project.project_path or "", "--schemes", project.scheme or ""])
    elif project.kind == "xcode-project":
        cmd.extend(["--project", project.project_path or "", "--schemes", project.scheme or ""])

    xcode_args = []
    if project.kind.startswith("xcode"):
        if project.destination:
            xcode_args.extend(["-destination", project.destination])
        if project.configuration:
            xcode_args.extend(["-configuration", project.configuration])
        xcode_args.append("CODE_SIGNING_ALLOWED=NO")
    if xcode_args:
        cmd.append("--")
        cmd.extend(xcode_args)

    run(cmd, root)


def detect_project(root: Path, config: dict) -> SwiftProject:
    configuration = str(config.get("xcode_configuration") or "Debug")
    destination = str(config.get("xcode_destination") or "")
    scheme = stripped(config.get("xcode_scheme"))
    workspace = stripped(config.get("xcode_workspace"))
    project = stripped(config.get("xcode_project"))

    if workspace:
        workspace_path = root / workspace
        require_path(workspace_path, "xcode_workspace")
        return SwiftProject("xcode-workspace", workspace, scheme or detect_scheme(root, "-workspace", workspace), destination, configuration)

    if project:
        project_path = root / project
        require_path(project_path, "xcode_project")
        return SwiftProject("xcode-project", project, scheme or detect_scheme(root, "-project", project), destination, configuration)

    workspaces = sorted(path for path in root.glob("*.xcworkspace") if path.is_dir())
    projects = sorted(path for path in root.glob("*.xcodeproj") if path.is_dir())

    if len(workspaces) == 1:
        rel = workspaces[0].relative_to(root).as_posix()
        return SwiftProject("xcode-workspace", rel, scheme or detect_scheme(root, "-workspace", rel), destination, configuration)
    if len(projects) == 1:
        rel = projects[0].relative_to(root).as_posix()
        return SwiftProject("xcode-project", rel, scheme or detect_scheme(root, "-project", rel), destination, configuration)
    if not workspaces and not projects and (root / "Package.swift").exists():
        return SwiftProject("spm")

    if len(workspaces) + len(projects) > 1:
        fail("Multiple Xcode projects/workspaces found. Set xcode_workspace or xcode_project in .swift-quality-gate.json.")
    fail("No SwiftPM package or root Xcode project/workspace found.")


def detect_scheme(root: Path, flag: str, project_path: str) -> str:
    result = subprocess.run(
        ["xcodebuild", "-list", "-json", flag, project_path],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        fail(trimmed_error(result.stdout + result.stderr, f"Unable to inspect schemes for {project_path}."))
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        fail(f"Unable to parse xcodebuild scheme list for {project_path}.")

    container_key = "workspace" if flag == "-workspace" else "project"
    schemes = payload.get(container_key, {}).get("schemes", [])
    if len(schemes) == 1:
        return str(schemes[0])
    if not schemes:
        fail(f"No shared schemes found for {project_path}. Set xcode_scheme in .swift-quality-gate.json.")
    fail(f"Multiple schemes found for {project_path}: {', '.join(map(str, schemes))}. Set xcode_scheme in .swift-quality-gate.json.")


def xcodebuild_base_command(project: SwiftProject) -> list[str]:
    cmd = ["xcodebuild"]
    if project.kind == "xcode-workspace":
        cmd.extend(["-workspace", project.project_path or ""])
    else:
        cmd.extend(["-project", project.project_path or ""])
    cmd.extend(["-scheme", project.scheme or ""])
    if project.configuration:
        cmd.extend(["-configuration", project.configuration])
    if project.destination:
        cmd.extend(["-destination", project.destination])
    cmd.append("CODE_SIGNING_ALLOWED=NO")
    return cmd


def swift_format_config(root: Path, config: dict) -> Path | None:
    preferred = stripped(config.get("swift_format_config"))
    fallback = stripped(config.get("fallback_swift_format_config"))
    if preferred and (root / preferred).exists():
        return root / preferred
    if fallback and (root / fallback).exists():
        return root / fallback
    return None


def ensure_periphery(config: dict) -> str:
    periphery = shutil.which("periphery")
    if periphery:
        return periphery

    if not bool(config.get("dead_code_install_periphery", True)):
        fail("DeadCodeGate requires periphery, but it was not found on PATH.")

    brew = shutil.which("brew")
    if not brew:
        fail("DeadCodeGate requires periphery. Homebrew is not available, so CI Scope cannot install it automatically.")

    print("periphery not found; installing with Homebrew...")
    run([brew, "install", "periphery"], Path.cwd())
    periphery = shutil.which("periphery")
    if not periphery:
        fail("Homebrew completed, but periphery is still not available on PATH.")
    return periphery


def collect_swift_paths(root: Path, config: dict, args: argparse.Namespace) -> list[Path]:
    if args.mode == "changed":
        candidates = changed_paths(root, args.base, args.head)
    else:
        candidates = all_repo_paths(root)

    paths = []
    for path in candidates:
        if path.suffix != ".swift" or not path.is_file():
            continue
        relative = to_relative(root, path)
        if should_ignore(relative, config.get("ignore", [])):
            continue
        paths.append(path)
    return sorted(paths)


def changed_paths(root: Path, base: str, head: str) -> list[Path]:
    attempts = [
        ["git", "diff", "--name-only", "--diff-filter=ACMRT", f"{base}...{head}"],
        ["git", "diff", "--name-only", "--diff-filter=ACMRT", base, head],
    ]
    for command in attempts:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)
        if result.returncode == 0:
            return [root / line.strip() for line in result.stdout.splitlines() if line.strip()]
    fail(trimmed_error(result.stdout + result.stderr, "Unable to collect changed files."))


def all_repo_paths(root: Path) -> list[Path]:
    result = subprocess.run(["git", "ls-files"], cwd=root, text=True, capture_output=True, check=False)
    if result.returncode == 0:
        return [root / line.strip() for line in result.stdout.splitlines() if line.strip()]

    paths = []
    for current_root, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name != ".git"]
        for filename in filenames:
            paths.append(Path(current_root) / filename)
    return paths


def should_ignore(relative_path: str, patterns: Sequence[str]) -> bool:
    parts = relative_path.split("/")
    basename = parts[-1]
    for pattern in patterns:
        normalized = str(pattern).strip().replace("\\", "/")
        if not normalized:
            continue
        if "/" not in normalized:
            if any(part == normalized for part in parts):
                return True
            if fnmatch.fnmatch(basename, normalized):
                return True
            continue
        if fnmatch.fnmatch(relative_path, normalized):
            return True
        if fnmatch.fnmatch(relative_path, f"**/{normalized}"):
            return True
    return False


def require_path(path: Path, key: str) -> None:
    if not path.exists():
        fail(f"{key} points to a missing path: {path}")


def run(command: Sequence[str], cwd: Path) -> None:
    print("$ " + " ".join(shell_display(arg) for arg in command), flush=True)
    result = subprocess.run(command, cwd=cwd, text=True, check=False)
    if result.returncode != 0:
        sys.exit(result.returncode)


def fail(message: str) -> None:
    print(f"::error::{escape_github_message(message)}", file=sys.stderr)
    sys.exit(2)


def error(path: str, line: int, title: str, message: str) -> None:
    print(f"::error file={path},line={line},title={title}::{escape_github_message(message)}")


def stripped(value: object) -> str:
    return str(value or "").strip()


def trimmed_error(message: str, fallback: str) -> str:
    text = message.strip()
    return text if text else fallback


def shell_display(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_@%+=:,./-]+", value):
        return value
    return "'" + value.replace("'", "'\\''") + "'"


def escape_github_message(message: str) -> str:
    return message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def to_relative(root: Path, path: Path) -> str:
    return path.resolve().relative_to(root).as_posix()


def github_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return path.as_posix()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
