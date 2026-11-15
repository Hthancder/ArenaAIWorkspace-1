#!/usr/bin/env python3
"""Build the web sample set (research-piano/40 — Phương án B) from the
full Salamander V3 OGGs.

Recipe (40.3/40.4, adapted — see app/docs/decisions.md):
  - keep 8 of the 16 velocity layers (odd: v1,v3,...,v15 -> renumber v1..v8)
    so the softest extreme survives; each new layer sits ~6 dB apart
  - trim tails to 10 s (40.3.3 suggests ~2-3 s for looped samples; these
    are one-shots, so a longer cap keeps pedal sustain believable)
  - fade-out 250 ms at the trim point (40.3.3: 150-300 ms, no click)
  - no per-sample peak normalisation (40.3.4): Salamander layers are
    consistently recorded and their inter-layer amplitude IS the velocity
    dynamics — normalising per file would flatten it (upstream NoteFall's
    own pipeline also skips normalisation)
  - encode OGG Vorbis quality 0.4 (40.4: OGG safest; ~96-128 kbps stereo)

Input:  _local/salamander-full/*.ogg   (scripts/fetch-samples.sh)
Output: public/samples/salamander-v3-close/*.ogg  (240 files, ~20-25 MB)
"""
import glob
import os
import re
import sys

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, '_local', 'salamander-full')
DST = os.path.join(ROOT, 'public', 'samples', 'salamander-v3-close')

MAX_SEC = 10.0
FADE_SEC = 0.25
# libsndfile Vorbis `compression_level` is the INVERSE of Vorbis quality:
# 0.9 = most compressed. 0.55 ≈ 96-100 kbps stereo 44.1 kHz — the bitrate
# research 40.4 recommends as the safe default.
VORBIS_Q = 0.55
KEEP_LAYERS = (1, 3, 5, 7, 9, 11, 13, 15)  # odd layers -> v1..v8

NAME_RE = re.compile(r'^([A-G]s?[0-8])v(\d+)\.ogg$')


def main() -> int:
    srcs = glob.glob(os.path.join(SRC, '*.ogg'))
    if not srcs:
        print(f'no source samples in {SRC} — run scripts/fetch-samples.sh first', file=sys.stderr)
        return 1
    os.makedirs(DST, exist_ok=True)

    total = 0
    count = 0
    for path in sorted(srcs):
        m = NAME_RE.match(os.path.basename(path))
        if not m:
            continue
        name, layer = m.group(1), int(m.group(2))
        if layer not in KEEP_LAYERS:
            continue
        out_layer = KEEP_LAYERS.index(layer) + 1

        data, rate = sf.read(path, dtype='float32', always_2d=True)
        n = data.shape[0]
        max_n = int(MAX_SEC * rate)
        if n > max_n:
            n = max_n
            data = data[:n]
            fade_n = int(FADE_SEC * rate)
            ramp = np.linspace(1.0, 0.0, fade_n, dtype=np.float32)
            if data.ndim == 2:
                ramp = ramp[:, None]
            data[-fade_n:] *= ramp

        out = os.path.join(DST, f'{name}v{out_layer}.ogg')
        sf.write(out, data, rate, format='OGG', subtype='VORBIS', compression_level=VORBIS_Q)
        total += os.path.getsize(out)
        count += 1

    print(f'{count} files -> {DST}')
    print(f'total: {total / 1e6:.1f} MB')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
