#!/usr/bin/env python3
"""Prepend a release entry to a plugin's site changelog JSON.

Reads the plugin repo's CHANGELOG.md, extracts the section for the release
version, and merges an entry into static/changelogs/<plugin>.json (the file the
dichoticstudios.com site renders). The file is kept newest-first; re-running for a
version already present just refreshes that entry in place (idempotent).

Usage:
  changelog-entry.py \
    --changelog plugins/guillotine/CHANGELOG.md \
    --out site/static/changelogs/guillotine.json \
    --version 1.2.4 \
    --repo noahbaxter/guillotine \
    --target Guillotine \
    --date 2026-07-14 \
    [--gated]

Entry shape (matches the existing committed files):
  { "version", "date": <str|null>, "notes": <markdown>, "assets": [ {os, url} ] }

- Gated plugins (e.g. pewpew): assets is always [] (downloads stay CDN-gated).
- Public plugins: assets point at the GitHub release download URLs the hub just
  attached (macOS .pkg / Windows .exe / Linux .zip), named version-last to match R2.
"""

import argparse
import json
import re
import sys
from pathlib import Path

# Heading forms we accept, in order of specificity:
#   ## [1.2.3] - 2026-07-12    ## [1.2.3]    ## 1.2.3    ## v1.2.3
_HEADING = re.compile(
    r"^\s{0,3}##\s+"
    r"(?:\[(?P<vb>[^\]]+)\]|v?(?P<vp>\d[\w.\-+]*))"
    r"\s*(?:[-–]\s*(?P<date>\d{4}-\d{2}-\d{2}))?"
    r"\s*$"
)


def _norm(v: str) -> str:
    return v.strip().lstrip("vV")


def extract_section(changelog: str, version: str):
    """Return (notes, date) for `version`, or (None, None) if not found."""
    want = _norm(version)
    lines = changelog.splitlines()
    starts = []  # (index, matched_version, date)
    for i, line in enumerate(lines):
        m = _HEADING.match(line)
        if m:
            ver = m.group("vb") or m.group("vp")
            starts.append((i, _norm(ver), m.group("date")))

    for idx, (line_no, ver, date) in enumerate(starts):
        if ver != want:
            continue
        end = starts[idx + 1][0] if idx + 1 < len(starts) else len(lines)
        body = "\n".join(lines[line_no + 1:end]).strip("\n")
        # Trim leading/trailing blank lines but keep internal structure.
        return body.strip(), date
    return None, None


def asset_urls(repo: str, target: str, version: str):
    base = f"https://github.com/{repo}/releases/download/v{version}"
    return [
        {"os": "macos", "url": f"{base}/{target}-macOS-{version}.pkg"},
        {"os": "windows", "url": f"{base}/{target}-Windows-{version}.exe"},
        {"os": "linux", "url": f"{base}/{target}-Linux-x64-{version}.zip"},
    ]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--changelog", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--date", default="")
    ap.add_argument("--gated", action="store_true")
    ap.add_argument("--notes-out", default="",
                    help="also write the raw notes markdown here (for the GitHub release body)")
    args = ap.parse_args()

    version = _norm(args.version)

    cl_path = Path(args.changelog)
    if not cl_path.is_file():
        print(f"::error::no CHANGELOG.md at {cl_path}", file=sys.stderr)
        return 1
    notes, heading_date = extract_section(cl_path.read_text(encoding="utf-8"), version)
    if notes is None:
        print(
            f"::error::CHANGELOG.md has no section for version {version} "
            f"(add a '## {version}' or '## [{version}] - <date>' heading)",
            file=sys.stderr,
        )
        return 1

    # Date precedence: heading date -> --date arg -> null.
    date = heading_date or (args.date.strip() or None)

    entry = {
        "version": version,
        "date": date,
        "notes": notes,
        "assets": [] if args.gated else asset_urls(args.repo, args.target, version),
    }

    out_path = Path(args.out)
    existing = []
    if out_path.is_file():
        try:
            existing = json.loads(out_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"::warning::{out_path} was not valid JSON, rewriting from scratch")
            existing = []

    # Drop any prior entry for this version, then put the fresh one on top.
    merged = [e for e in existing if _norm(str(e.get("version", ""))) != version]
    merged.insert(0, entry)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(merged, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {out_path} ({len(merged)} entries, {version} on top)")

    if args.notes_out:
        Path(args.notes_out).write_text(notes + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
