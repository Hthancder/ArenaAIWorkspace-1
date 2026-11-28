#!/usr/bin/env python3
"""Extract the beacon-spam engine and transmit loop from the firmware source.

The tests must exercise the shipped code, so nothing is duplicated here: the two
regions below are lifted verbatim from src/modules/wifi/wifi_atks.cpp before the
host compiler sees them. If the source is restructured, this fails loudly rather
than testing a stale copy.
"""
import sys, pathlib

src_path = pathlib.Path(sys.argv[1]) / "src/modules/wifi/wifi_atks.cpp"
src = src_path.read_text()

ENGINE_START = "namespace {\n\nstruct SpamSsidSource"
ENGINE_END = "} // namespace\n"
LOOP_START = "    while (!done) {"
LOOP_END = "    };\n    runFrames();"

try:
    a = src.index(ENGINE_START)
    b = src.index(ENGINE_END, a) + len(ENGINE_END)
    engine = src[a:b]
    c = src.index(LOOP_START, b)
    d = src.index(LOOP_END, c)
    loop = src[c:d]
except ValueError as exc:  # pragma: no cover - reported as a test failure
    sys.exit(f"prepare.py: cannot locate code to extract from wifi_atks.cpp ({exc})")

if "spamNextSsid" not in engine or "emitOneBeacon" not in engine:
    sys.exit("prepare.py: extracted engine is missing spamNextSsid/emitOneBeacon")
if "deauths++" not in loop:
    sys.exit("prepare.py: extracted loop does not contain the deauth emission")

pathlib.Path("engine.inc").write_text(engine)
pathlib.Path("loop.inc").write_text(loop)
print(f"extracted engine ({len(engine)} B) and loop ({len(loop)} B)")
