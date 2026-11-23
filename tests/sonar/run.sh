#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
src=${1:-"$root/firmware/Bruce"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
g++ -std=c++17 -Wall -Wextra -Werror -I"$src/src" "$root/tests/sonar/signal-test.cpp" -o "$tmp/signal-test"
"$tmp/signal-test"
