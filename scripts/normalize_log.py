#!/usr/bin/env python3
"""
normalize_log.py
────────────────
Normalises both Android (Legado) and iOS (yuedu app) pipeline logs into a
common text format so they can be compared with a standard diff tool.

Usage:
  # Normalise an Android logcat capture:
  python3 normalize_log.py --side android < legado.txt > legado_norm.txt

  # Normalise an iOS pipeline log export:
  python3 normalize_log.py --side ios < ios_pipeline.txt > ios_norm.txt

  # Called automatically by compare_logs.py
"""

import sys
import re
import argparse

# ── Android log patterns ───────────────────────────────────────────────────────
# Example raw line:
#   04-15 14:32:01.234  1234  5678 D AppLog  : [AnalyzeRule] rule: //div
ANDROID_LINE = re.compile(
    r"^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+\d+\s+\d+\s+[VDIWEF]\s+"
    r"(?P<tag>\S+)\s*:\s*(?P<msg>.*)"
)

# Legado BookSourceDebug emits lines like:
#   <br>搜索URL: https://...
#   <br>书名: 三体
#   <br>规则: //div[@class='title']
#   <br>结果: 三体
LEGADO_STAGE = re.compile(r"<br>|\\n")

# Key Android event labels → normalised step names
ANDROID_STEPS = {
    re.compile(r"rawUrl|搜索URL|Search URL", re.I):     "RAW_URL",
    re.compile(r"规则|rule\s*:", re.I):                 "RULE",
    re.compile(r"结果|result\s*:", re.I):               "RESULT",
    re.compile(r"书名|name\s*:", re.I):                 "BOOK_NAME",
    re.compile(r"作者|author\s*:", re.I):               "AUTHOR",
    re.compile(r"封面|cover\s*:", re.I):                "COVER_URL",
    re.compile(r"简介|intro\s*:", re.I):                "INTRO",
    re.compile(r"目录URL|tocUrl\s*:", re.I):            "TOC_URL",
    re.compile(r"章节标题|chapterTitle\s*:", re.I):     "CHAPTER_TITLE",
    re.compile(r"正文|content\s*:", re.I):              "CONTENT",
    re.compile(r"mode\s*:", re.I):                      "MODE",
    re.compile(r"\[Raw Data\]", re.I):                  "RAW_DATA",
    re.compile(r"\[Rule Parsed\]", re.I):               "RULES_PARSED",
    re.compile(r"\[Before Extract", re.I):              "BEFORE_EXTRACT",
    re.compile(r"\[String Extracted", re.I):            "STRING_EXTRACTED",
    re.compile(r"\[Nodes Extracted", re.I):             "NODES_EXTRACTED",
    re.compile(r"\[Regex Applied", re.I):               "REGEX_APPLIED",
    re.compile(r"\[JS\s*#", re.I):                      "JS_EXECUTED",
    re.compile(r"\[Final Result\]", re.I):              "FINAL_RESULT",
    re.compile(r"\[Final List\]", re.I):                "FINAL_LIST",
    re.compile(r"\[ERROR", re.I):                       "ERROR",
}

# ── iOS log patterns ───────────────────────────────────────────────────────────
# iOS pipeline events from legadoStyleLog:
#   [Raw Data] type=HTML length=1234 url=https://...
#   [Rule Parsed] "//div"
#   [Before Extract #0] mode=xpath rule=//div
#   [String Extracted #0] → "三体"
#   [Regex Applied #0] /.../ → "..."
#   [JS #0] ...
#   [Final Result] "三体" (3.2ms)
IOS_LINE = re.compile(r"^\[(?P<event>[^\]]+)\](?P<rest>.*)")

def classify_step(line: str) -> str | None:
    """Return the normalised step name for a line, or None if not a key step."""
    for pattern, name in ANDROID_STEPS.items():
        if pattern.search(line):
            return name
    return None

def extract_value(line: str) -> str:
    """
    Extract the semantic value from a log line, stripping timestamps,
    PIDs, tag prefixes and surrounding whitespace.
    """
    # Strip Android logcat prefix
    m = ANDROID_LINE.match(line)
    if m:
        line = m.group("msg")

    # Remove HTML breaks Legado injects
    line = LEGADO_STAGE.sub(" | ", line)

    # Collapse whitespace
    line = " ".join(line.split())

    # Truncate very long values so diffs stay readable
    if len(line) > 300:
        line = line[:300] + " …"

    return line.strip()


def normalise_android(lines):
    """Yield normalised (step, value) pairs from an Android logcat stream."""
    for raw in lines:
        raw = raw.rstrip("\n")
        step = classify_step(raw)
        if step is None:
            continue
        value = extract_value(raw)
        # Remove the step keyword from the value to keep it clean
        for pattern in ANDROID_STEPS:
            value = pattern.sub("", value, count=1).strip(": ").strip()
            break
        yield step, value


def normalise_ios(lines):
    """Yield normalised (step, value) pairs from an iOS pipeline log export."""
    for raw in lines:
        raw = raw.rstrip("\n")
        step = classify_step(raw)
        if step is None:
            continue
        value = extract_value(raw)
        yield step, value


def main():
    parser = argparse.ArgumentParser(description="Normalise Legado/iOS pipeline logs")
    parser.add_argument("--side", choices=["android", "ios"], required=True)
    parser.add_argument("input", nargs="?", type=argparse.FileType("r"), default=sys.stdin)
    parser.add_argument("output", nargs="?", type=argparse.FileType("w"), default=sys.stdout)
    args = parser.parse_args()

    lines = args.input.readlines()
    fn = normalise_android if args.side == "android" else normalise_ios

    for step, value in fn(lines):
        args.output.write(f"{step}: {value}\n")


if __name__ == "__main__":
    main()
