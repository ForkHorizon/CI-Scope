#!/usr/bin/env python3
"""Portable readability gate for humans and AI coding agents.

The checker intentionally uses only Python's standard library so this file can
be copied between repositories and run from GitHub Actions without setup.
"""

from __future__ import annotations

import argparse
import ast
import fnmatch
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence


LANGUAGE_BY_EXTENSION = {
    ".swift": "swift",
    ".cs": "csharp",
    ".js": "javascript",
    ".jsx": "javascript",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".py": "python",
    ".java": "java",
    ".kt": "kotlin",
    ".kts": "kotlin",
    ".go": "go",
    ".rs": "rust",
    ".php": "php",
    ".rb": "ruby",
}

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
    "linter-checker-300-lines.py",
    "*.designer.cs",
    "*.generated.*",
    "*.g.cs",
    "*.g.swift",
    "*.gen.*",
    "*.min.js",
    "*.pb.*",
    "*.snap",
    "*.snapshot",
]

DEFAULT_CONFIG = {
    "max_file_lines": 300,
    "max_function_lines": 50,
    "include_extensions": sorted(LANGUAGE_BY_EXTENSION),
    "ignore": DEFAULT_IGNORE,
    "language_overrides": {},
}

CONTROL_WORDS = {
    "catch",
    "do",
    "else",
    "for",
    "foreach",
    "guard",
    "if",
    "lock",
    "repeat",
    "switch",
    "try",
    "using",
    "when",
    "while",
    "with",
}

RUBY_BLOCK_START = re.compile(
    r"^\s*(class|module|if|unless|case|begin|for|while|until)\b|(^|[^A-Za-z0-9_])do\b"
)


@dataclass(frozen=True)
class Issue:
    path: str
    line: int
    kind: str
    message: str


@dataclass
class FunctionBlock:
    name: str
    start_line: int
    parent_depth: int


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    root = Path(args.root).resolve()
    config = load_config(root / args.config)

    paths = collect_paths(root, config, args)
    issues = check_paths(root, paths, config)
    print_report(issues, len(paths), args.mode)
    return 1 if issues else 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check source file and function length for AI-readable code."
    )
    parser.add_argument("--mode", choices=("all", "changed"), default="all")
    parser.add_argument("--base", default="origin/main", help="Base ref for changed mode.")
    parser.add_argument("--head", default="HEAD", help="Head ref for changed mode.")
    parser.add_argument("--config", default=".ai-readability.json")
    parser.add_argument("--root", default=".")
    return parser.parse_args(argv)


def load_config(path: Path) -> dict:
    config = dict(DEFAULT_CONFIG)
    config["ignore"] = list(DEFAULT_IGNORE)
    config["include_extensions"] = list(DEFAULT_CONFIG["include_extensions"])
    config["language_overrides"] = {}

    if path.exists():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"::error file={github_path(path)}::Invalid JSON config: {exc}", file=sys.stderr)
            sys.exit(2)
        if not isinstance(loaded, dict):
            print(f"::error file={github_path(path)}::.ai-readability config must be a JSON object", file=sys.stderr)
            sys.exit(2)
        config.update(loaded)

    config["max_file_lines"] = int(config.get("max_file_lines", 300))
    config["max_function_lines"] = int(config.get("max_function_lines", 50))
    config["ignore"] = list(config.get("ignore", []))
    config["include_extensions"] = [
        ext if ext.startswith(".") else f".{ext}"
        for ext in config.get("include_extensions", LANGUAGE_BY_EXTENSION)
    ]
    config["language_overrides"] = dict(config.get("language_overrides", {}))
    return config


def collect_paths(root: Path, config: dict, args: argparse.Namespace) -> list[Path]:
    if args.mode == "changed":
        candidates = changed_paths(root, args.base, args.head)
    else:
        candidates = all_repo_paths(root)

    include_extensions = set(config["include_extensions"])
    paths = []
    for path in candidates:
        if not path.is_file():
            continue
        relative = to_relative(root, path)
        if path.suffix not in include_extensions:
            continue
        if should_ignore(relative, config["ignore"]):
            continue
        paths.append(path)
    return sorted(paths)


def changed_paths(root: Path, base: str, head: str) -> list[Path]:
    diff_args = ["git", "diff", "-z", "--name-only", "--diff-filter=ACMRT", f"{base}...{head}"]
    result = subprocess.run(diff_args, cwd=root, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        diff_args = ["git", "diff", "-z", "--name-only", "--diff-filter=ACMRT", base, head]
        result = subprocess.run(diff_args, cwd=root, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip()
        print(f"::error::Unable to collect changed files: {stderr}", file=sys.stderr)
        sys.exit(2)
    return [root / path for path in result.stdout.split('\0') if path]


def all_repo_paths(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode == 0:
        return [root / path for path in result.stdout.split('\0') if path]

    paths = []
    for current_root, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name != ".git"]
        for filename in filenames:
            paths.append(Path(current_root) / filename)
    return paths


def check_paths(root: Path, paths: Iterable[Path], config: dict) -> list[Issue]:
    issues: list[Issue] = []
    for path in paths:
        relative = to_relative(root, path)
        language = LANGUAGE_BY_EXTENSION.get(path.suffix)
        if language is None:
            continue

        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = path.read_text(encoding="utf-8", errors="replace")

        lines = text.splitlines()
        limits = limits_for_language(config, language)
        max_file_lines = limits["max_file_lines"]
        max_function_lines = limits["max_function_lines"]

        if len(lines) > max_file_lines:
            issues.append(
                Issue(
                    path=relative,
                    line=1,
                    kind="file_length",
                    message=f"File has {len(lines)} lines; limit is {max_file_lines}.",
                )
            )

        for name, start_line, length in function_lengths(text, language):
            if length > max_function_lines:
                issues.append(
                    Issue(
                        path=relative,
                        line=start_line,
                        kind="function_length",
                        message=(
                            f"{name} has {length} lines; function/method limit is "
                            f"{max_function_lines}."
                        ),
                    )
                )
    return issues


def limits_for_language(config: dict, language: str) -> dict[str, int]:
    limits = {
        "max_file_lines": int(config["max_file_lines"]),
        "max_function_lines": int(config["max_function_lines"]),
    }
    override = config.get("language_overrides", {}).get(language, {})
    if isinstance(override, dict):
        for key in limits:
            if key in override:
                limits[key] = int(override[key])
    return limits


def function_lengths(text: str, language: str) -> list[tuple[str, int, int]]:
    if language == "python":
        return python_function_lengths(text)
    if language == "ruby":
        return ruby_function_lengths(text)
    return brace_function_lengths(text, language)


def python_function_lengths(text: str) -> list[tuple[str, int, int]]:
    try:
        tree = ast.parse(text)
    except SyntaxError as exc:
        line = exc.lineno or 1
        return [(f"Python syntax error near line {line}", line, len(text.splitlines()) - line + 1)]

    results = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            end_line = getattr(node, "end_lineno", node.lineno)
            results.append((node.name, node.lineno, end_line - node.lineno + 1))
    return results


def ruby_function_lengths(text: str) -> list[tuple[str, int, int]]:
    stack: list[tuple[str, str, int]] = []
    results = []

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = strip_ruby_comment(raw_line)
        stripped = line.strip()
        if not stripped:
            continue

        def_match = re.match(r"\s*def\s+([A-Za-z_][A-Za-z0-9_!?=]*(?:\.[A-Za-z_][A-Za-z0-9_!?=]*)?)", line)
        if def_match:
            name = def_match.group(1)
            if re.search(r"\s=\s", line):
                results.append((name, line_number, 1))
            else:
                stack.append(("def", name, line_number))
            continue

        if RUBY_BLOCK_START.search(line):
            stack.append(("block", "", line_number))

        end_count = len(re.findall(r"(^|[^A-Za-z0-9_])end([^A-Za-z0-9_]|$)", line))
        for _ in range(end_count):
            if not stack:
                break
            kind, name, start_line = stack.pop()
            if kind == "def":
                results.append((name, start_line, line_number - start_line + 1))

    return results


def brace_function_lengths(text: str, language: str) -> list[tuple[str, int, int]]:
    results = []
    active: list[FunctionBlock] = []
    pending: tuple[str, int] | None = None
    brace_depth = 0
    in_block_comment = False

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line, in_block_comment = strip_c_style_comments(raw_line, in_block_comment)
        clean = strip_strings(line)
        stripped = clean.strip()
        depth_before = brace_depth

        detected = detect_brace_function(stripped, language)
        if detected:
            pending = (detected, line_number)

        opens = clean.count("{")
        closes = clean.count("}")

        if pending and opens:
            name, start_line = pending
            active.append(FunctionBlock(name=name, start_line=start_line, parent_depth=depth_before))
            pending = None

        if pending and stripped.endswith(";"):
            pending = None

        brace_depth += opens - closes
        if brace_depth < 0:
            brace_depth = 0

        while active and brace_depth <= active[-1].parent_depth:
            block = active.pop()
            results.append((block.name, block.start_line, line_number - block.start_line + 1))

    return results


def detect_brace_function(line: str, language: str) -> str | None:
    if not line:
        return None

    first_word = re.match(r"(?:@\w+\s+)*(?:[A-Za-z_][A-Za-z0-9_]*)", line)
    if first_word and first_word.group(0).split()[0] in CONTROL_WORDS:
        return None

    if language == "swift":
        match = re.search(r"\bfunc\s+(`[^`]+`|[A-Za-z_][A-Za-z0-9_]*)\b", line)
        if match:
            return match.group(1).strip("`")
        if re.search(r"\binit\s*\(", line):
            return "init"
        if re.search(r"\bdeinit\b", line):
            return "deinit"
        return None

    if language in {"kotlin"}:
        match = re.search(r"\bfun\s+(?:[A-Za-z_][A-Za-z0-9_<>.]*\.)?([A-Za-z_][A-Za-z0-9_]*)\s*\(", line)
        if match:
            return match.group(1)
        if re.search(r"\bconstructor\s*\(", line):
            return "constructor"
        return None

    if language == "go":
        match = re.search(r"\bfunc\s+(?:\([^)]*\)\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*\(", line)
        return match.group(1) if match else None

    if language == "rust":
        match = re.search(r"\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*[<(]", line)
        return match.group(1) if match else None

    if language == "php":
        match = re.search(r"\bfunction\s+&?\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(", line)
        return match.group(1) if match else None

    if language in {"javascript", "typescript"}:
        match = re.search(r"\bfunction\s+\*?\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\(", line)
        if match:
            return match.group(1)
        match = re.search(r"\b(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=.*=>", line)
        if match:
            return match.group(1)
        match = re.match(r"(?:async\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*\([^)]*\)\s*\{?", line)
        if match and match.group(1) not in CONTROL_WORDS:
            return match.group(1)
        return None

    if language in {"csharp", "java"}:
        if "(" not in line or "=>" in line:
            return None
        match = re.match(
            r"(?:\[[^\]]+\]\s*)*"
            r"(?:(?:public|private|protected|internal|static|virtual|override|async|sealed|extern|unsafe|partial|new|final|synchronized|abstract)\s+)*"
            r"(?:[A-Za-z_][A-Za-z0-9_<>,\[\].?]+\s+)?"
            r"([A-Za-z_][A-Za-z0-9_]*)\s*\(",
            line,
        )
        if match and match.group(1) not in CONTROL_WORDS:
            return match.group(1)
        return None

    return None


def strip_c_style_comments(line: str, in_block_comment: bool) -> tuple[str, bool]:
    output = []
    index = 0
    while index < len(line):
        if in_block_comment:
            end = line.find("*/", index)
            if end == -1:
                return "".join(output), True
            index = end + 2
            in_block_comment = False
            continue

        slash = line.find("//", index)
        block = line.find("/*", index)
        if slash == -1 and block == -1:
            output.append(line[index:])
            break
        if slash != -1 and (block == -1 or slash < block):
            output.append(line[index:slash])
            break
        output.append(line[index:block])
        index = block + 2
        in_block_comment = True

    return "".join(output), in_block_comment


def strip_strings(line: str) -> str:
    output = []
    quote: str | None = None
    escaped = False
    for char in line:
        if quote:
            if escaped:
                escaped = False
                output.append(" ")
                continue
            if char == "\\":
                escaped = True
                output.append(" ")
                continue
            if char == quote:
                quote = None
            output.append(" ")
            continue
        if char in {'"', "'", "`"}:
            quote = char
            output.append(" ")
        else:
            output.append(char)
    return "".join(output)


def strip_ruby_comment(line: str) -> str:
    quote: str | None = None
    escaped = False
    for index, char in enumerate(line):
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in {'"', "'"}:
            quote = char
        elif char == "#":
            return line[:index]
    return line


def should_ignore(relative_path: str, patterns: Sequence[str]) -> bool:
    parts = relative_path.split("/")
    basename = parts[-1]
    for pattern in patterns:
        normalized = pattern.strip().replace("\\", "/")
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


def print_report(issues: Sequence[Issue], checked_count: int, mode: str) -> None:
    if not issues:
        print(f"AI readability check passed: scanned {checked_count} file(s) in {mode} mode.")
        return

    for issue in issues:
        print(
            f"::error file={issue.path},line={issue.line},title={issue.kind}::"
            f"{escape_github_message(issue.message)}"
        )

    print(
        f"AI readability check failed: {len(issues)} issue(s) across "
        f"{checked_count} scanned file(s) in {mode} mode."
    )


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
