#!/usr/bin/env python3
"""Instrument one pinned gmrunner source copy to measure a synthetic background fill.

Never use the resulting runner in a build, release, or with real saves. It
intentionally paints the target magenta once. Only the exact pinned source is
accepted. This is a desktop graphics diagnostic, not an iOS patch.
"""
import argparse
import hashlib
from pathlib import Path

SOURCE_SHA = 'e17d59e8ec81d26acff54b25e32216a186ec68a23c90b19354283627239430ac'
START = 'void Graphics::drawRoomPass() {\n    if (rt_.bgShowColor) {'
END = '    drawRoomBackgrounds(false);\n    runDrawEvent(DRAW_BEGIN, true);'
BEGIN_PROBE = '''void Graphics::drawRoomPass() {
    // Diagnostic only: prepaint a known color on one isolated desktop pass.
    static bool dt_measured = false;
    const char* dt_mode = getenv("GMR_BACKGROUND_PROBE");
    bool dt_active = dt_mode && !dt_measured && enabled_ && rt_.bgShowColor && !customMats_
        && appSurface_ >= 0 && curTarget_ == surfaces_[appSurface_]
        && vpX_ == 0 && vpY_ == 0 && vpW_ == curTargetW_ && vpH_ == curTargetH_
        && curTargetW_ == 1232 && curTargetH_ == 693 && std::fabs(projAngle_) > 1.0;
    TargetState dt_saved = currentState();
    if (dt_active) {
        if (dt_mode[0] == 'z') { auto state = dt_saved; state.pa = 0; restoreState(state); }
        r_.clear(0xff00ff, 1);
    }
    if (rt_.bgShowColor) {'''
END_PROBE = '''    if (dt_active) {
        std::vector<uint8_t> dt_pixels;
        if (readCurrentTarget(0, 0, curTargetW_, curTargetH_, dt_pixels)) {
            size_t dt_pink = 0;
            for (size_t i = 0; i + 3 < dt_pixels.size(); i += 4)
                if (dt_pixels[i] >= 250 && dt_pixels[i+1] <= 5 && dt_pixels[i+2] >= 250) dt_pink++;
            std::fprintf(stderr, "DT_BG_COVERAGE|%s|%.4f|%d|%d|%zu\\n", dt_mode,
                         projAngle_, curTargetW_, curTargetH_, dt_pink);
            dt_measured = true;
        }
        if (dt_mode[0] == 'z') restoreState(dt_saved);
    }
    drawRoomBackgrounds(false);
    runDrawEvent(DRAW_BEGIN, true);'''


def patch_source(source):
    if source.count(START) != 1 or source.count(END) != 1 or 'DT_BG_COVERAGE' in source:
        raise ValueError('unexpected source layout')
    return source.replace(START, BEGIN_PROBE).replace(END, END_PROBE)


def prepare(path):
    path = Path(path)
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA:
        raise ValueError('unexpected runner source SHA-256')
    path.write_text(patch_source(data.decode('utf-8')), encoding='utf-8')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('graphics_cpp', type=Path)
    args = p.parse_args()
    prepare(args.graphics_cpp)
    print('BACKGROUND_PROBE: synthetic marker instrumented; desktop diagnostic only')


if __name__ == '__main__':
    main()
