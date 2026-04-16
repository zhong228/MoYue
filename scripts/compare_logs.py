#!/usr/bin/env python3
"""
compare_logs.py
───────────────
Diff two normalised pipeline logs (Android Legado vs iOS yuedu app) and
produce a human-readable report with colour-coded mismatches.

Usage:
  # Compare two pre-normalised files:
  python3 compare_logs.py legado_norm.txt ios_norm.txt

  # Or normalise on the fly:
  python3 compare_logs.py --android legado_raw.txt --ios ios_raw.txt

  # Save report:
  python3 compare_logs.py --android legado_raw.txt --ios ios_raw.txt --out report.html

Output: console diff + optional HTML report.
"""

import sys
import re
import argparse
import subprocess
import tempfile
import os
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
NORMALIZER = SCRIPT_DIR / "normalize_log.py"

# ANSI colours
RED    = "\033[91m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
RESET  = "\033[0m"
BOLD   = "\033[1m"


def normalise_file(path: str, side: str) -> list[str]:
    result = subprocess.run(
        ["python3", str(NORMALIZER), "--side", side, path],
        capture_output=True, text=True
    )
    return result.stdout.splitlines()


def parse_steps(lines: list[str]) -> list[tuple[str, str]]:
    """Return list of (step, value) from normalised lines."""
    out = []
    for line in lines:
        if ": " in line:
            step, _, value = line.partition(": ")
            out.append((step.strip(), value.strip()))
    return out


def compare(android_steps, ios_steps) -> list[dict]:
    """
    Align steps by name (in order) and flag mismatches.
    Returns list of result dicts.
    """
    results = []
    a_idx, i_idx = 0, 0

    while a_idx < len(android_steps) or i_idx < len(ios_steps):
        a = android_steps[a_idx] if a_idx < len(android_steps) else None
        b = ios_steps[i_idx] if i_idx < len(ios_steps) else None

        if a is None:
            results.append({"status": "ONLY_IOS",  "step": b[0], "android": "", "ios": b[1]})
            i_idx += 1
        elif b is None:
            results.append({"status": "ONLY_ANDROID", "step": a[0], "android": a[1], "ios": ""})
            a_idx += 1
        elif a[0] == b[0]:
            # Same step — compare values
            if values_match(a[1], b[1]):
                results.append({"status": "MATCH", "step": a[0], "android": a[1], "ios": b[1]})
            else:
                results.append({"status": "MISMATCH", "step": a[0], "android": a[1], "ios": b[1]})
            a_idx += 1
            i_idx += 1
        else:
            # Step name mismatch — Android has an extra step
            results.append({"status": "ONLY_ANDROID", "step": a[0], "android": a[1], "ios": ""})
            a_idx += 1

    return results


def values_match(a: str, b: str) -> bool:
    """
    Semantic equality: normalise whitespace, ignore timing suffixes,
    ignore leading/trailing quotes.
    """
    def clean(s):
        s = re.sub(r"\s+", " ", s).strip().strip('"').strip("'")
        s = re.sub(r"\(\d+\.\d+ms\)$", "", s).strip()
        return s

    return clean(a) == clean(b)


def print_report(results: list[dict]):
    match   = sum(1 for r in results if r["status"] == "MATCH")
    mismatch= sum(1 for r in results if r["status"] == "MISMATCH")
    only_a  = sum(1 for r in results if r["status"] == "ONLY_ANDROID")
    only_i  = sum(1 for r in results if r["status"] == "ONLY_IOS")
    total   = len(results)

    print(f"\n{BOLD}{'═'*70}{RESET}")
    print(f"{BOLD}  Legado Android  ↔  yuedu iOS  —  Pipeline Diff Report{RESET}")
    print(f"{'═'*70}")
    print(f"  Total steps : {total}")
    print(f"  {GREEN}✅ Match     : {match}{RESET}")
    print(f"  {RED}❌ Mismatch  : {mismatch}{RESET}")
    print(f"  {YELLOW}⬡  Android-only: {only_a}{RESET}")
    print(f"  {CYAN}⬡  iOS-only    : {only_i}{RESET}")
    pct = int(match / total * 100) if total else 0
    print(f"\n  Compatibility: {BOLD}{pct}%{RESET}")
    print(f"{'═'*70}\n")

    for r in results:
        s = r["status"]
        step = r["step"]
        if s == "MATCH":
            print(f"  {GREEN}✅ {step}{RESET}")
        elif s == "MISMATCH":
            print(f"  {RED}❌ {step}{RESET}")
            print(f"     Android: {r['android'][:120]}")
            print(f"     iOS    : {r['ios'][:120]}")
        elif s == "ONLY_ANDROID":
            print(f"  {YELLOW}🤖 {step}  (Android only){RESET}")
            print(f"     Android: {r['android'][:120]}")
        elif s == "ONLY_IOS":
            print(f"  {CYAN}📱 {step}  (iOS only){RESET}")
            print(f"     iOS    : {r['ios'][:120]}")

    print()


def write_html(results: list[dict], path: str):
    rows = ""
    for r in results:
        status = r["status"]
        if status == "MATCH":
            colour = "#d4edda"; icon = "✅"
        elif status == "MISMATCH":
            colour = "#f8d7da"; icon = "❌"
        elif status == "ONLY_ANDROID":
            colour = "#fff3cd"; icon = "🤖"
        else:
            colour = "#d1ecf1"; icon = "📱"

        rows += f"""
        <tr style="background:{colour}">
            <td>{icon}</td>
            <td><code>{r['step']}</code></td>
            <td><pre style="margin:0;white-space:pre-wrap">{r['android'][:300]}</pre></td>
            <td><pre style="margin:0;white-space:pre-wrap">{r['ios'][:300]}</pre></td>
        </tr>"""

    html = f"""<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<title>Legado ↔ yuedu 書源解析對比</title>
<style>
  body {{ font-family: -apple-system, sans-serif; margin: 20px; }}
  h1 {{ font-size: 20px; }}
  table {{ border-collapse: collapse; width: 100%; font-size: 13px; }}
  th,td {{ border: 1px solid #ccc; padding: 6px 10px; vertical-align: top; }}
  th {{ background: #343a40; color: white; }}
  pre {{ font-family: "SF Mono", Menlo, monospace; font-size: 12px; }}
</style>
</head>
<body>
<h1>Legado Android ↔ yuedu iOS — 書源解析管道對比</h1>
<table>
  <tr>
    <th width="40">狀態</th>
    <th width="180">步驟</th>
    <th>Android (Legado)</th>
    <th>iOS (yuedu)</th>
  </tr>
  {rows}
</table>
</body>
</html>"""

    Path(path).write_text(html, encoding="utf-8")
    print(f"📄  HTML report: {path}")


def main():
    ap = argparse.ArgumentParser(description="Diff Legado vs yuedu pipeline logs")
    ap.add_argument("--android", metavar="FILE",
                    help="Raw Android logcat file (will be normalised)")
    ap.add_argument("--ios", metavar="FILE",
                    help="Raw iOS pipeline log file (will be normalised)")
    ap.add_argument("--out", metavar="HTML",
                    help="Save HTML report to this path")
    ap.add_argument("norm_android", nargs="?",
                    help="Pre-normalised Android file (alternative to --android)")
    ap.add_argument("norm_ios", nargs="?",
                    help="Pre-normalised iOS file (alternative to --ios)")
    args = ap.parse_args()

    if args.android:
        android_lines = normalise_file(args.android, "android")
    elif args.norm_android:
        android_lines = Path(args.norm_android).read_text().splitlines()
    else:
        ap.error("Provide --android <file> or a pre-normalised android file as first arg")

    if args.ios:
        ios_lines = normalise_file(args.ios, "ios")
    elif args.norm_ios:
        ios_lines = Path(args.norm_ios).read_text().splitlines()
    else:
        ap.error("Provide --ios <file> or a pre-normalised ios file as first arg")

    android_steps = parse_steps(android_lines)
    ios_steps     = parse_steps(ios_lines)

    results = compare(android_steps, ios_steps)
    print_report(results)

    if args.out:
        write_html(results, args.out)


if __name__ == "__main__":
    main()
