#!/usr/bin/env bash
# Fetch the Salamander Grand Piano V3 OGG set into public/samples/ —
# self-hosting is mandatory for this fork (research 41.1.6: the upstream
# samples.notefall.app bucket is CORS-locked to notefall.app).
#
# Source: d-buckner/salamander-piano (GitHub), a mirror of the same
# pre-encoded OGG release NoteFall's own scripts/fetch-salamander.sh
# prepares: 30 root keys × 16 velocity layers, `A0v1.ogg`-style names
# ("s" for sharp — `Ds1v1.ogg` = D♯1), ~150 MB.
#
# License: Salamander Grand Piano V3 by Alexander Holm, CC BY 3.0 —
# attribution lives in ATTRIBUTIONS.md. Keep it when redistributing.
#
# Requirements: curl, tar. The GitHub tarball comes from codeload.github.com.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="public/samples/salamander-v3-close"
REPO="d-buckner/salamander-piano"
BRANCH="main"

if [ -d "$OUT" ] && [ "$(ls "$OUT" | wc -l)" -ge 480 ]; then
  echo "Samples already present in $OUT ($(ls "$OUT" | wc -l) files) — nothing to do."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $REPO ($BRANCH)…"
curl -sL -o "$WORK/sal.tar.gz" "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"

echo "Extracting the 480 sample files…"
tar -xzf "$WORK/sal.tar.gz" -C "$WORK"
mkdir -p "$OUT"
# Match `^[A-G](s)?[0-8]v[0-9]+\.ogg$` — the harmonic/resonance extras
# (harm*, SA*…) in the repo are not used by the descriptor and are skipped.
(
  cd "$WORK/$REPO-$BRANCH"
  # shellcheck disable=SC2046
  cp $(ls | grep -E '^[A-G](s)?[0-8]v[0-9]+\.ogg$') "$OLDPWD/$OUT/"
)

echo "Done: $(ls "$OUT" | wc -l) files in $OUT"
echo "Remember: samples are gitignored (~150 MB). Re-run this script after a fresh clone."
