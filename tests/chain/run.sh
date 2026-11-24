#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
source_dir=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [[ ! -f "$source_dir/src/modules/wifi/chain_logic.h" ]]; then
  # This repository stores the Bruce integration as a patch, not a checkout.
  # Extract the standalone logic header from that patch for host-side tests.
  python3 - "$root/firmware/dsolution-183-2mic-bruce.patch" "$tmp/Bruce/src/modules/wifi/chain_logic.h" <<'PY'
from pathlib import Path
import sys
patch, output = map(Path, sys.argv[1:])
lines = patch.read_text().splitlines()
markers = [
    "diff --git a/src/modules/wifi/chain_logic.h b/src/modules/wifi/chain_logic.h",
    "diff --git a/src/modules/wifi/evil_twin_logic.h b/src/modules/wifi/evil_twin_logic.h",
]
for marker in markers:
    try:
        start = lines.index(marker)
    except ValueError:
        raise SystemExit(f"{marker.split(' ')[2]} diff not found in firmware patch")
    body = []
    for line in lines[start + 1:]:
        if line.startswith("diff --git "):
            break
        if line.startswith("+") and not line.startswith("+++"):
            body.append(line[1:])
    # output lives at <root>/src/modules/wifi/chain_logic.h -> parents[3] is <root>
    target = output.parents[3] / marker.split(" a/")[1].split(" b/")[0]
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(body) + "\n")
PY
  source_dir="$tmp/Bruce"
fi
g++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$source_dir/src" "$root/tests/chain/logic-test.cpp" -o "$tmp/logic-test"
"$tmp/logic-test"
# Evil Twin policy (deauth window, verify channel lock, in-place routing).
g++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$source_dir/src" "$root/tests/chain/evil-twin-test.cpp" -o "$tmp/evil-twin-test"
"$tmp/evil-twin-test"
python3 "$root/tests/chain/portal-napt-regression.py"
