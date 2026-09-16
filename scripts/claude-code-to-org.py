#!/usr/bin/env python3
"""Convert Claude Code JSON/JSONL conversations to Org mode.

This script intentionally depends only on Python's standard library so it can be
called from Doom Emacs without extra setup.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Iterable


ROLE_ALIASES = {
    "human": "user",
    "assistant": "assistant",
    "system": "system",
    "tool": "tool",
    "user": "user",
}


SENSITIVE_KEY_RE = re.compile(r"(api[_-]?key|token|secret|password|authorization)", re.I)


def org_escape(text: Any) -> str:
    """Return text safe enough for normal Org paragraphs."""
    if text is None:
        return ""
    if not isinstance(text, str):
        text = json.dumps(text, ensure_ascii=False, indent=2)
    # Avoid accidental Org headline creation inside message text.
    return "\n".join(("," + line if line.startswith("*") else line) for line in text.splitlines())


def block(text: Any, lang: str | None = None) -> str:
    """Render text as an Org source/example block."""
    if text is None:
        text = ""
    if not isinstance(text, str):
        text = json.dumps(text, ensure_ascii=False, indent=2)
    text = text.rstrip("\n")
    if lang:
        return f"#+begin_src {lang}\n{text}\n#+end_src"
    return f"#+begin_example\n{text}\n#+end_example"


def parse_timestamp(value: Any) -> tuple[str, str]:
    """Return (display timestamp, sortable timestamp)."""
    if value is None:
        return "Sin fecha", "9999-12-31T23:59:59"
    if isinstance(value, (int, float)):
        # Claude-related tools typically use seconds, but handle ms too.
        seconds = value / 1000 if value > 10_000_000_000 else value
        try:
            d = dt.datetime.fromtimestamp(seconds, tz=dt.timezone.utc).astimezone()
            return d.strftime("%Y-%m-%d %H:%M:%S %Z"), d.isoformat()
        except (OSError, OverflowError, ValueError):
            pass
    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return "Sin fecha", "9999-12-31T23:59:59"
        normalized = raw.replace("Z", "+00:00")
        try:
            d = dt.datetime.fromisoformat(normalized)
            if d.tzinfo is not None:
                d = d.astimezone()
            return d.strftime("%Y-%m-%d %H:%M:%S %Z").strip(), d.isoformat()
        except ValueError:
            return raw, raw
    return str(value), str(value)


def redact_if_sensitive(key: str, value: Any) -> Any:
    if SENSITIVE_KEY_RE.search(key):
        return "<redacted>"
    return value


def read_json_records(path: Path) -> list[Any]:
    """Read JSON, JSON array, or JSONL. Preserve parse errors as records."""
    text = path.read_text(encoding="utf-8", errors="replace")
    stripped = text.strip()
    if not stripped:
        return []

    # First try normal JSON: object or list.
    try:
        parsed = json.loads(stripped)
        return parsed if isinstance(parsed, list) else [parsed]
    except json.JSONDecodeError:
        pass

    records: list[Any] = []
    for lineno, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as exc:
            records.append(
                {
                    "type": "parse_error",
                    "line": lineno,
                    "error": str(exc),
                    "raw": line,
                }
            )
    return records


def find_first(mapping: dict[str, Any], keys: Iterable[str]) -> Any:
    for key in keys:
        if key in mapping and mapping[key] not in (None, ""):
            return mapping[key]
    return None


def normalize_record(record: Any, index: int) -> dict[str, Any]:
    """Normalize known Claude-ish shapes into a message-like object."""
    if not isinstance(record, dict):
        return {
            "role": "unknown",
            "timestamp": None,
            "uuid": f"record-{index}",
            "content": record,
            "raw": record,
            "type": "record",
        }

    if record.get("type") == "parse_error":
        return {
            "role": "parse-error",
            "timestamp": None,
            "uuid": f"parse-error-{record.get('line', index)}",
            "content": record.get("raw", ""),
            "raw": record,
            "type": "parse_error",
        }

    message = record.get("message") if isinstance(record.get("message"), dict) else record
    role = find_first(message, ("role", "speaker", "author")) or find_first(record, ("role", "speaker", "type")) or "unknown"
    role = ROLE_ALIASES.get(str(role), str(role))
    timestamp = find_first(record, ("timestamp", "created_at", "createdAt", "date", "time")) or find_first(
        message, ("timestamp", "created_at", "createdAt", "date", "time")
    )
    uuid = find_first(record, ("uuid", "id", "message_id", "messageId")) or find_first(
        message, ("uuid", "id", "message_id", "messageId")
    ) or f"record-{index}"
    content = find_first(message, ("content", "text", "message", "body"))

    return {
        "role": role,
        "timestamp": timestamp,
        "uuid": str(uuid),
        "content": content if content is not None else record,
        "raw": record,
        "type": str(record.get("type", "message")),
        "model": find_first(message, ("model",)) or find_first(record, ("model",)),
        "cwd": find_first(record, ("cwd", "project", "project_dir", "projectDir")),
    }


def render_content(content: Any, level: int = 3) -> list[str]:
    """Render Claude message content, including Anthropic content blocks."""
    lines: list[str] = []
    stars = "*" * level

    if isinstance(content, str):
        lines.append(org_escape(content))
        return lines

    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict):
                item_type = item.get("type")
                if item_type == "text":
                    lines.append(org_escape(item.get("text", "")))
                elif item_type == "tool_use":
                    name = item.get("name", "tool")
                    lines.append(f"{stars} Tool use: {org_escape(name)}")
                    if item.get("input") is not None:
                        lines.append(block(item.get("input"), "json"))
                elif item_type == "tool_result":
                    lines.append(f"{stars} Tool result")
                    lines.append(block(item.get("content", item)))
                else:
                    lines.append(f"{stars} Content block: {org_escape(item_type or 'unknown')}")
                    lines.append(block(item, "json"))
            else:
                lines.append(org_escape(item))
        return lines

    if isinstance(content, dict):
        # Common wrappers.
        if isinstance(content.get("content"), (str, list, dict)) and content.get("content") is not content:
            return render_content(content.get("content"), level=level)
        if isinstance(content.get("text"), str):
            lines.append(org_escape(content.get("text")))
            return lines
        lines.append(block(content, "json"))
        return lines

    lines.append(org_escape(content))
    return lines


def infer_title(source: Path, records: list[dict[str, Any]]) -> str:
    for rec in records:
        content = rec.get("content")
        if rec.get("role") == "user" and isinstance(content, str) and content.strip():
            first = " ".join(content.strip().split())[:80]
            return first
        if rec.get("role") == "user" and isinstance(content, list):
            for block_item in content:
                if isinstance(block_item, dict) and isinstance(block_item.get("text"), str):
                    first = " ".join(block_item["text"].strip().split())[:80]
                    if first:
                        return first
    return source.stem


def convert(input_path: Path, output_path: Path) -> None:
    raw_records = read_json_records(input_path)
    records = [normalize_record(record, i + 1) for i, record in enumerate(raw_records)]
    title = infer_title(input_path, records)
    source_mtime = dt.datetime.fromtimestamp(input_path.stat().st_mtime).astimezone().isoformat()
    generated = dt.datetime.now().astimezone().isoformat(timespec="seconds")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    lines: list[str] = [
        f"#+title: Claude Code Chat - {org_escape(title)}",
        f"#+source: {input_path}",
        f"#+generated_at: {generated}",
        "#+startup: overview",
        "",
        "* Metadata",
        f"- Archivo fuente: ={input_path}=",
        f"- Última modificación fuente: {source_mtime}",
        f"- Mensajes/registros: {len(records)}",
        "- Nota: este archivo es generado automáticamente; los cambios manuales pueden perderse al sincronizar.",
        "",
        "* Conversación",
    ]

    for idx, rec in enumerate(records, 1):
        display_ts, sort_ts = parse_timestamp(rec.get("timestamp"))
        role = rec.get("role", "unknown")
        heading = f"** {display_ts} {str(role).capitalize()}"
        lines.extend(
            [
                "",
                heading,
                ":PROPERTIES:",
                f":UUID: {rec.get('uuid')}",
                f":ROLE: {role}",
                f":SORT_TS: {sort_ts}",
                f":SOURCE_INDEX: {idx}",
            ]
        )
        if rec.get("model"):
            lines.append(f":MODEL: {rec.get('model')}")
        if rec.get("cwd"):
            lines.append(f":CWD: {rec.get('cwd')}")
        lines.append(":END:")
        lines.append("")

        if rec.get("type") == "parse_error":
            lines.append("No se pudo parsear esta línea del archivo fuente.")
            lines.append(block(rec.get("raw"), "json"))
        else:
            lines.extend(render_content(rec.get("content"), level=3))

    output_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Convert Claude Code JSON/JSONL chats to Org mode.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    convert_parser = subparsers.add_parser("convert", help="Convert a single chat file to Org mode.")
    convert_parser.add_argument("--input", required=True, type=Path, help="Claude Code JSON/JSONL source file.")
    convert_parser.add_argument("--output", required=True, type=Path, help="Destination .org file.")

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "convert":
            convert(args.input.expanduser(), args.output.expanduser())
            return 0
    except Exception as exc:  # noqa: BLE001 - show useful errors to Emacs users.
        print(f"claude-code-to-org.py: {exc}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
