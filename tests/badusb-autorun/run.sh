#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
src=${1:-"$root/firmware/Bruce"}
python3 "$root/tests/badusb-autorun/logic-test.py" "$src"
