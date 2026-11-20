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
FINISH = '    drawRoomBackgrounds(true);\n    runDrawEvent(DRAW_END, true);\n}'
RECT = '''        drawRect(projX_ - 1, projY_ - 1, projX_ + projW_ + 1, projY_ + projH_ + 1, false, rt_.bgColor, rt_.bgColor,
                 rt_.bgColor, rt_.bgColor, 1);'''
RECT_PROBE = '''        auto dt_bg_state = currentState();
        if ((dt_active && dt_mode[0] == 'f') || dt_repair_next) { auto state = dt_bg_state; state.pa = 0; restoreState(state); }
''' + RECT + '''
        if ((dt_active && dt_mode[0] == 'f') || dt_repair_next) restoreState(dt_bg_state);'''
BEGIN_PROBE = '''void Graphics::drawRoomPass() {
    // Diagnostic only: prepaint a known color on one isolated desktop pass.
    static bool dt_measured = false;
    static bool dt_pending_next = false;
    static std::vector<uint8_t> dt_previous;
    const char* dt_mode = getenv("GMR_BACKGROUND_PROBE");
    bool dt_active = dt_mode && !dt_measured && enabled_ && rt_.bgShowColor && !customMats_
        && appSurface_ >= 0 && curTarget_ == surfaces_[appSurface_]
        && vpX_ == 0 && vpY_ == 0 && vpW_ == curTargetW_ && vpH_ == curTargetH_
        && curTargetW_ == 1232 && curTargetH_ == 693 && std::fabs(projAngle_) > 1.0;
    bool dt_repair_next = dt_pending_next && dt_mode && dt_mode[0] == 'r' && enabled_ && rt_.bgShowColor
        && !customMats_ && appSurface_ >= 0 && curTarget_ == surfaces_[appSurface_]
        && vpX_ == 0 && vpY_ == 0 && vpW_ == curTargetW_ && vpH_ == curTargetH_
        && curTargetW_ == 1232 && curTargetH_ == 693;
    TargetState dt_saved = currentState();
    std::vector<uint8_t> dt_mask;
    if (dt_active) {
        if (dt_mode[0] == 'z') { auto state = dt_saved; state.pa = 0; restoreState(state); }
        r_.clear(0xff00ff, 1);
    }
    if (rt_.bgShowColor) {'''
END_PROBE = '''    if (dt_active) {
        std::vector<uint8_t> dt_pixels;
        if (readCurrentTarget(0, 0, curTargetW_, curTargetH_, dt_pixels)) {
            size_t dt_pink = 0;
            dt_mask.resize(dt_pixels.size() / 4, 0);
            for (size_t i = 0; i + 3 < dt_pixels.size(); i += 4)
                if (dt_pixels[i] >= 250 && dt_pixels[i+1] <= 5 && dt_pixels[i+2] >= 250) {
                    dt_pink++;
                    dt_mask[i / 4] = 1;
                }
            std::fprintf(stderr, "DT_BG_COVERAGE|%s|%.4f|%d|%d|%zu\\n", dt_mode,
                         projAngle_, curTargetW_, curTargetH_, dt_pink);
            dt_measured = true;
        }
        if (dt_mode[0] == 'z') restoreState(dt_saved);
    }
    drawRoomBackgrounds(false);
    runDrawEvent(DRAW_BEGIN, true);'''


FINISH_PROBE = '''    drawRoomBackgrounds(true);
    runDrawEvent(DRAW_END, true);
    if (dt_active && !dt_mask.empty()) {
        auto dt_after_game = currentState();
        restoreState(dt_saved);
        std::vector<uint8_t> dt_final_pixels;
        if (readCurrentTarget(0, 0, curTargetW_, curTargetH_, dt_final_pixels)
            && dt_final_pixels.size() / 4 == dt_mask.size()) {
            size_t dt_initial = 0, dt_surviving = 0;
            dt_previous.assign(dt_mask.size(), 0);
            for (size_t i = 0; i < dt_mask.size(); i++) {
                if (!dt_mask[i]) continue;
                dt_initial++;
                size_t p = i * 4;
                if (dt_final_pixels[p] >= 250 && dt_final_pixels[p+1] <= 5 && dt_final_pixels[p+2] >= 250) {
                    dt_surviving++;
                    dt_previous[i] = 1;
                }
            }
            std::fprintf(stderr, "DT_BG_FINAL|%s|%zu|%zu\\n", dt_mode, dt_initial, dt_surviving);
            dt_pending_next = true;
        }
        restoreState(dt_after_game);
    } else if (dt_pending_next && dt_mode && appSurface_ >= 0 && dt_saved.target == surfaces_[appSurface_]
               && curTargetW_ == 1232 && curTargetH_ == 693) {
        auto dt_after_game = currentState();
        restoreState(dt_saved);
        std::vector<uint8_t> dt_followup;
        if (readCurrentTarget(0, 0, curTargetW_, curTargetH_, dt_followup)
            && dt_followup.size() / 4 == dt_previous.size()) {
            size_t dt_before = 0, dt_still = 0;
            for (size_t i = 0; i < dt_previous.size(); i++) {
                if (!dt_previous[i]) continue;
                dt_before++;
                size_t p = i * 4;
                if (dt_followup[p] >= 250 && dt_followup[p+1] <= 5 && dt_followup[p+2] >= 250)
                    dt_still++;
            }
            std::fprintf(stderr, "DT_BG_NEXT|%s|%zu|%zu\\n", dt_mode, dt_before, dt_still);
            dt_pending_next = false;
        }
        restoreState(dt_after_game);
    }
}'''


def patch_source(source):
    if source.count(START) != 1 or source.count(END) != 1 or source.count(RECT) != 1 or source.count(FINISH) != 1 or 'DT_BG_COVERAGE' in source:
        raise ValueError('unexpected source layout')
    return source.replace(START, BEGIN_PROBE).replace(RECT, RECT_PROBE).replace(END, END_PROBE).replace(FINISH, FINISH_PROBE)


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
