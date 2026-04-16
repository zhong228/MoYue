#!/usr/bin/env bash
# capture_legado_log.sh
#
# Captures Legado's book-source debug output from a running Android AVD/device,
# normalises it, and writes it to a file for diff-driven comparison against the
# iOS yuedu app pipeline logs.
#
# Usage:
#   ./scripts/capture_legado_log.sh [output_file]
#
# Default output: scripts/logs/legado_<timestamp>.txt
#
# The script filters logcat for Legado's known debug tags:
#   AppLog, AnalyzeRule, BookSource, io.legado.app
#
# Stop capture with Ctrl+C — the output file is written on exit.

set -euo pipefail

ADB="${HOME}/Library/Android/sdk/platform-tools/adb"
LEGADO_PKG="io.legado.app"        # release / debug both use this prefix

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUT_DIR="$(dirname "$0")/logs"
OUT_FILE="${1:-${OUT_DIR}/legado_${TIMESTAMP}.txt}"

mkdir -p "${OUT_DIR}"

# ── Verify device/emulator is reachable ───────────────────────────────────────
echo "📡  Checking adb connection..."
DEVICES=$("${ADB}" devices | grep -v "^List" | grep "device$" | wc -l | tr -d ' ')
if [[ "${DEVICES}" == "0" ]]; then
    echo ""
    echo "❌  No device/emulator found."
    echo "    Start an Android Virtual Device in Android Studio first, then re-run."
    exit 1
fi
echo "✅  Found ${DEVICES} device(s)."

# ── Detect Legado package variant ─────────────────────────────────────────────
PKG=$("${ADB}" shell pm list packages 2>/dev/null | grep "${LEGADO_PKG}" | head -1 | sed 's/package://')
if [[ -z "${PKG}" ]]; then
    echo ""
    echo "⚠️  Legado not found on device. Install it first:"
    echo "   adb install path/to/legado.apk"
    echo ""
    echo "   Continuing capture anyway (tags: AppLog, AnalyzeRule, BookSourceDebug)..."
    PKG="${LEGADO_PKG}"
fi
echo "📦  Legado package: ${PKG}"

# ── Clear old logcat buffer ────────────────────────────────────────────────────
"${ADB}" logcat -c

echo ""
echo "📝  Capturing to: ${OUT_FILE}"
echo "    Open Legado → 書源管理 → 偵錯 → 執行搜索/解析"
echo "    Press Ctrl+C to stop."
echo "────────────────────────────────────────────────"

# ── Stream logcat, filter, normalise ──────────────────────────────────────────
# Legado's key tags:
#   AppLog          — general app log (search URLs, results)
#   AnalyzeRule     — per-rule extraction steps
#   BookSourceDebug — high-level stage log (from BookSourceDebugService)
#   OkHttp          — HTTP requests (useful for URL verification)
"${ADB}" logcat -v time \
    AppLog:D AnalyzeRule:D BookSourceDebug:D OkHttp:D "*:S" \
  | python3 "$(dirname "$0")/normalize_log.py" --side android \
  | tee "${OUT_FILE}"

echo ""
echo "✅  Log saved to: ${OUT_FILE}"
