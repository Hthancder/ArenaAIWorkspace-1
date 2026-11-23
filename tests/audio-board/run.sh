#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
src=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 "$root/tests/audio-board/extract.py" "$src" "$tmp"
g++ -std=c++17 -Wall -Wextra -Werror -DDSOLUTION_183_2MIC -I"$tmp" "$root/tests/audio-board/codec-test.cpp" -o "$tmp/codec-test"
"$tmp/codec-test"
