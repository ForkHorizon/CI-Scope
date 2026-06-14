#!/usr/bin/env python3
"""Portable Swift compile gate installed by CI Scope.

The checker intentionally uses only Python's standard library so it can be
copied into Swift repositories without requiring package-manager setup.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Pattern, Sequence


DEFAULT_IGNORE = [
    ".git",
    ".svn",
    ".hg",
    ".build",
    ".build/**",
    "DerivedData",
    "DerivedData/**",
    "Pods",
    "Pods/**",
    "Carthage",
    "Carthage/**",
    "build",
    "build/**",
    "vendor",
    "vendor/**",
    "node_modules",
    "node_modules/**",
    "*.designer.swift",
    "*.generated.*",
    "*.g.swift",
    "*.gen.*",
]

DEFAULT_CRITICAL_WARNING_PATTERNS = [
    r"will be an error in Swift 6",
    r"\bSendable\b",
    r"\bnon[- ]?sendable\b",
    r"\bactor[- ]isolated\b",
    r"\bMainActor\b",
    r"\bdata race\b",
    r"\bconcurrently[- ]executing\b",
]

DEFAULT_CONFIG = {
    "ignore": DEFAULT_IGNORE,
    "xcode_workspace": "",
    "xcode_project": "",
    "xcode_scheme": "",
    "xcode_destination": "generic/platform=macOS",
    "xcode_configuration": "Debug",
    "xcode_code_signing_allowed": False,
    "xcodebuild_arguments": [],
    "swift_build_arguments": [],
    "fail_on_any_warning": False,
    "critical_warning_patterns": DEFAULT_CRITICAL_WARNING_PATTERNS,
    "critical_warning_exclude_patterns": [],
}


@dataclass(frozen=True)
class SwiftProject:
    kind: str
    project_path: str | None = None
    scheme: str | None = None
    destination: str = ""
    configuration: str = "Debug"


@dataclass(frozen=True)
class WarningRecord:
    raw_line: str
    path: str | None
    line: int | None
    message: str

    def summary(self) -> str:
        if self.path and self.line:
            return f"{self.path}:{self.line}: {self.message}"
        if self.path:
            return f"{self.path}: {self.message}"
        return self.message or self.raw_line.strip()


@dataclass(frozen=True)
class WarningPolicy:
    fail_on_any_warning: bool
    include_patterns: list[Pattern[str]]
    exclude_patterns: list[Pattern[str]]


@dataclass(frozen=True)
class BuildResult:
    exit_code: int
    critical_warnings: list[WarningRecord]


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    root = Path(args.root).resolve()
    config_path = root / args.config
    config = load_config(config_path)
    policy = warning_policy(config, config_path)
    command = build_command(root, config)

    result = run_and_collect(command, root, config, policy)
    if result.exit_code != 0:
        emit_error(f"Swift Compile Gate failed: compile command exited with code {result.exit_code}.")
        return result.exit_code

    if result.critical_warnings:
        annotate_critical_warnings(root, result.critical_warnings)
        first = truncate(result.critical_warnings[0].summary(), 240)
        emit_error(f"Swift Compile Gate failed: found {len(result.critical_warnings)} critical warning(s). First: {first}")
        return 1

    print("Swift Compile Gate passed: compile completed with no blocking warnings.")
    return 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compile a Swift project and fail on configured critical warnings.")
    parser.add_argument("--config", default=".swift-compile-gate.json")
    parser.add_argument("--root", default=".")
    return parser.parse_args(argv)


def load_config(path: Path) -> dict:
    config = dict(DEFAULT_CONFIG)
    config["ignore"] = list(DEFAULT_IGNORE)
    config["xcodebuild_arguments"] = []
    config["swift_build_arguments"] = []
    config["critical_warning_patterns"] = list(DEFAULT_CRITICAL_WARNING_PATTERNS)
    config["critical_warning_exclude_patterns"] = []

    if path.exists():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            emit_file_error(github_path(path), 1, "invalid_config", f"Invalid JSON config: {exc}")
            sys.exit(2)
        if not isinstance(loaded, dict):
            emit_file_error(github_path(path), 1, "invalid_config", "Swift Compile Gate config must be a JSON object.")
            sys.exit(2)
        config.update(loaded)

    config["ignore"] = as_string_list(config.get("ignore"))
    config["xcodebuild_arguments"] = as_string_list(config.get("xcodebuild_arguments"))
    config["swift_build_arguments"] = as_string_list(config.get("swift_build_arguments"))
    config["critical_warning_patterns"] = as_string_list(config.get("critical_warning_patterns"))
    config["critical_warning_exclude_patterns"] = as_string_list(config.get("critical_warning_exclude_patterns"))
    return config


def warning_policy(config: dict, config_path: Path) -> WarningPolicy:
    return WarningPolicy(
        fail_on_any_warning=bool(config.get("fail_on_any_warning", False)),
        include_patterns=compile_patterns(config["critical_warning_patterns"], "critical_warning_patterns", config_path),
        exclude_patterns=compile_patterns(
            config["critical_warning_exclude_patterns"],
            "critical_warning_exclude_patterns",
            config_path,
        ),
    )


def compile_patterns(patterns: Sequence[str], key: str, config_path: Path) -> list[Pattern[str]]:
    compiled = []
    for index, pattern in enumerate(patterns, start=1):
        try:
            compiled.append(re.compile(pattern, re.IGNORECASE))
        except re.error as exc:
            emit_file_error(
                github_path(config_path),
                1,
                "invalid_regex",
                f"{key}[{index}] is not a valid regular expression: {exc}",
            )
            sys.exit(2)
    return compiled


def build_command(root: Path, config: dict) -> list[str]:
    project = detect_project(root, config)
    if project.kind == "spm":
        return ["swift", "build", *config["swift_build_arguments"]]

    command = xcodebuild_base_command(project, config)
    command.extend(config["xcodebuild_arguments"])
    command.append("build")
    return command


def detect_project(root: Path, config: dict) -> SwiftProject:
    configuration = str(config.get("xcode_configuration") or "Debug")
    destination = str(config.get("xcode_destination") or "")
    scheme = stripped(config.get("xcode_scheme"))
    workspace = stripped(config.get("xcode_workspace"))
    project = stripped(config.get("xcode_project"))

    if workspace:
        require_path(root / workspace, "xcode_workspace")
        return SwiftProject(
            "xcode-workspace",
            workspace,
            scheme or detect_scheme(root, "-workspace", workspace),
            destination,
            configuration,
        )

    if project:
        require_path(root / project, "xcode_project")
        return SwiftProject(
            "xcode-project",
            project,
            scheme or detect_scheme(root, "-project", project),
            destination,
            configuration,
        )

    workspaces = sorted(path for path in root.glob("*.xcworkspace") if path.is_dir())
    projects = sorted(path for path in root.glob("*.xcodeproj") if path.is_dir())

    if len(workspaces) == 1:
        relative = workspaces[0].relative_to(root).as_posix()
        return SwiftProject("xcode-workspace", relative, scheme or detect_scheme(root, "-workspace", relative), destination, configuration)
    if len(projects) == 1:
        relative = projects[0].relative_to(root).as_posix()
        return SwiftProject("xcode-project", relative, scheme or detect_scheme(root, "-project", relative), destination, configuration)
    if not workspaces and not projects and (root / "Package.swift").exists():
        return SwiftProject("spm")

    if len(workspaces) + len(projects) > 1:
        fail("Multiple Xcode projects/workspaces found. Set xcode_workspace or xcode_project in .swift-compile-gate.json.")
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
        fail(f"No shared schemes found for {project_path}. Set xcode_scheme in .swift-compile-gate.json.")
    fail(f"Multiple schemes found for {project_path}: {', '.join(map(str, schemes))}. Set xcode_scheme in .swift-compile-gate.json.")


def xcodebuild_base_command(project: SwiftProject, config: dict) -> list[str]:
    command = ["xcodebuild"]
    if project.kind == "xcode-workspace":
        command.extend(["-workspace", project.project_path or ""])
    else:
        command.extend(["-project", project.project_path or ""])
    command.extend(["-scheme", project.scheme or ""])
    if project.configuration:
        command.extend(["-configuration", project.configuration])
    if project.destination:
        command.extend(["-destination", project.destination])
    if not bool(config.get("xcode_code_signing_allowed", False)):
        command.append("CODE_SIGNING_ALLOWED=NO")
    return command


def run_and_collect(command: Sequence[str], root: Path, config: dict, policy: WarningPolicy) -> BuildResult:
    print("$ " + " ".join(shell_display(part) for part in command), flush=True)
    try:
        process = subprocess.Popen(
            command,
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except FileNotFoundError as exc:
        fail(f"Unable to run compile command: {exc}")

    critical_warnings = []
    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="", flush=True)
        warning = parse_warning_line(line)
        if warning and is_critical_warning(root, warning, config, policy):
            critical_warnings.append(warning)

    return BuildResult(process.wait(), critical_warnings)


def parse_warning_line(line: str) -> WarningRecord | None:
    text = line.strip()
    if "warning:" not in text.lower():
        return None

    for pattern in (
        r"^(?P<path>.*?):(?P<line>\d+):(?P<column>\d+):\s*warning:\s*(?P<message>.*)$",
        r"^(?P<path>.*?):(?P<line>\d+):\s*warning:\s*(?P<message>.*)$",
    ):
        match = re.match(pattern, text, flags=re.IGNORECASE)
        if match:
            return WarningRecord(
                raw_line=text,
                path=match.group("path"),
                line=int(match.group("line")),
                message=match.group("message").strip(),
            )

    match = re.search(r"warning:\s*(?P<message>.*)$", text, flags=re.IGNORECASE)
    if match:
        return WarningRecord(raw_line=text, path=None, line=None, message=match.group("message").strip())
    return None


def is_critical_warning(root: Path, warning: WarningRecord, config: dict, policy: WarningPolicy) -> bool:
    if warning.path and should_ignore(normalized_warning_path(root, warning.path), config["ignore"]):
        return False

    searchable = "\n".join(value for value in [warning.raw_line, warning.path or "", warning.message] if value)
    if any(pattern.search(searchable) for pattern in policy.exclude_patterns):
        return False
    if policy.fail_on_any_warning:
        return True
    return any(pattern.search(searchable) for pattern in policy.include_patterns)


def normalized_warning_path(root: Path, warning_path: str) -> str:
    clean_path = warning_path.removeprefix("file://")
    path = Path(clean_path)
    if path.is_absolute():
        try:
            return path.resolve().relative_to(root).as_posix()
        except ValueError:
            return path.as_posix().lstrip("/")
    return path.as_posix().lstrip("./")


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


def annotate_critical_warnings(root: Path, warnings: Sequence[WarningRecord]) -> None:
    for warning in warnings[:10]:
        message = escape_github_message(truncate(warning.message or warning.raw_line.strip(), 400))
        if warning.path:
            path = normalized_warning_path(root, warning.path)
            line = f",line={warning.line}" if warning.line else ""
            print(f"::error file={path}{line},title=critical_warning::{message}")
        else:
            print(f"::error title=critical_warning::{message}")
    if len(warnings) > 10:
        print(f"::notice::Swift Compile Gate suppressed {len(warnings) - 10} additional critical warning annotations.")


def require_path(path: Path, key: str) -> None:
    if not path.exists():
        fail(f"{key} points to a missing path: {path}")


def fail(message: str) -> None:
    emit_error(message)
    sys.exit(2)


def emit_error(message: str) -> None:
    print(f"::error::{escape_github_message(message)}", file=sys.stderr)


def emit_file_error(path: str, line: int, title: str, message: str) -> None:
    print(f"::error file={path},line={line},title={title}::{escape_github_message(message)}", file=sys.stderr)


def as_string_list(value: object) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value]
    if value is None:
        return []
    return [str(value)]


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


def truncate(value: str, limit: int) -> str:
    text = value.strip()
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "..."


def github_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return path.as_posix()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
