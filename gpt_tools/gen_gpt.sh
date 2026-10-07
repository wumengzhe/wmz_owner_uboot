#!/bin/bash
# gen_gpt.sh - Generate GPT (.bin) images from every JSON layout in a directory.
#
# Usage:
#   ./gen_gpt.sh <SRC_JSON_DIR> <DST_BIN_DIR>
#
# For each <name>.json in SRC_JSON_DIR (non-recursive; the template/ subdir is
# skipped automatically since it only holds mt798x_gpt_template_*.json), produce
#   <DST_BIN_DIR>/gpt-<name>.bin
#
# This mirrors bl-mt798x-dhcpd's generate_gpt.sh but runs on python3 (the
# MediaTek mtk_gpt.py tooling is a python3 port shipped in this repo under
# gpt_tools/), so it works on a stock ubuntu-latest runner with no python2.7.
#
# eMMC models ship multiple layouts per JSON name: default / _2G / _4G / _2m / _4m
# etc. (the _2m/_4m suffix marks the fip-partition size axis). Every *.json in the
# source dir is auto-built, so adding a layout is as simple as dropping a JSON here.

set -u

SRC="${1:-./mt798x_gpt}"
DST="${2:-./output_gpt}"

TOOLS="$(cd "$(dirname "$0")" && pwd)"
PY="${PYTHON:-python3}"

mkdir -p "$DST"

if [ ! -d "$SRC" ]; then
    echo "[ERROR] source dir not found: $SRC"
    exit 1
fi
if [ ! -f "$TOOLS/mtk_gpt.py" ]; then
    echo "[ERROR] gpt_tools/mtk_gpt.py not found next to this script ($TOOLS)"
    exit 1
fi

ok=0
fail=0
for j in "$SRC"/*.json; do
    [ -e "$j" ] || continue
    name="$(basename "$j" .json)"
    out="$DST/gpt-$name.bin"
    if "$PY" "$TOOLS/mtk_gpt.py" --i "$j" --o "$out" >/dev/null 2>&1; then
        sz="$(stat -c%s "$out" 2>/dev/null || echo '?')"
        echo "[OK]   $name -> gpt-$name.bin ($sz bytes)"
        ok=$((ok + 1))
    else
        echo "[FAIL] $name ($j)"
        fail=$((fail + 1))
    fi
done

echo "==========================================="
echo "GPT generation done: $ok ok, $fail failed"
echo "Output: $DST/"
echo "==========================================="
[ "$fail" -eq 0 ]
