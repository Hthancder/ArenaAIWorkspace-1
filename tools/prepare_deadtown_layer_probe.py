#!/usr/bin/env python3
"""Add logging to a pinned, disposable desktop runner; never ship this runner.

Logs sprite calls made during obj_player's normal Draw event and the CPU quad
emitted by drawTexRect. No GPU readback, device execution or production fix.
"""
import argparse
import hashlib
from pathlib import Path

SOURCE_SHA = 'e17d59e8ec81d26acff54b25e32216a186ec68a23c90b19354283627239430ac'


def patch(source):
    if hashlib.sha256(source.encode()).hexdigest() != SOURCE_SHA:
        raise ValueError('unexpected Graphics.cpp SHA-256')
    patches = [
        ('namespace gm {\n\nGraphics::Graphics', '''namespace gm {

// Research only; single-threaded, bounded trace of normal player Draw events.
static Instance* dt_layer_instance = nullptr;
static int dt_layer_tick = 0, dt_layer_seq = 0;
static bool dt_layer_quad = false;

Graphics::Graphics'''),
        ('''    uint32_t c = packColor(col, a);
    const uint32_t cs[4] = {c, c, c, c};
    drawQuad(tex, px, py, sx / texW, sy / texH, (sx + sw) / texW, (sy + sh) / texH, cs);
}''', '''    if (dt_layer_quad) {
        std::fprintf(stderr, "DT_LAYER_VERT|%d|%d", dt_layer_tick, dt_layer_seq);
        for (int i = 0; i < 4; i++) std::fprintf(stderr, "|%.9f|%.9f", px[i], py[i]);
        std::fprintf(stderr, "\\n");
    }
    uint32_t c = packColor(col, a);
    const uint32_t cs[4] = {c, c, c, c};
    drawQuad(tex, px, py, sx / texW, sy / texH, (sx + sw) / texW, (sy + sh) / texH, cs);
}'''),
        ('''    drawTpag(tp, x, y, s.originX, s.originY, xs, ys, rot, col, a);
}''', '''    if (dt_layer_instance && tp >= 0 && static_cast<size_t>(tp) < rt_.dw.tpag.size()) {
        const auto& t = rt_.dw.tpag[tp];
        ++dt_layer_seq;
        std::fprintf(stderr, "DT_LAYER_SPRITE|%d|%d|%.*s|%.9f|%.9f|%.9f|%.9f|%.9f|%d|%d|%u|%u|%u|%u|%.9f|%u\\n",
                     dt_layer_tick, dt_layer_seq, static_cast<int>(s.name.size()), s.name.data(),
                     x, y, xs, ys, rot, s.originX, s.originY, static_cast<unsigned>(t.tgtX), static_cast<unsigned>(t.tgtY),
                     static_cast<unsigned>(t.tgtW), static_cast<unsigned>(t.tgtH), a, col);
        dt_layer_quad = true;
    }
    drawTpag(tp, x, y, s.originX, s.originY, xs, ys, rot, col, a);
    dt_layer_quad = false;
}'''),
        ('''            if (!rt_.performEvent(inst, EV_DRAW, DRAW_NORMAL)) drawSelf(inst);
        } else if (it.kind == 1) {''', '''            bool dt_trace = getenv("GMR_LAYER_PROBE") && inst->object >= 0
                && static_cast<size_t>(inst->object) < rt_.dw.objects.size()
                && rt_.dw.objects[inst->object].name == "obj_player" && dt_layer_tick < 45;
            if (dt_trace) {
                ++dt_layer_tick;
                dt_layer_seq = 0;
                dt_layer_instance = inst;
                auto dt_var = [&](const char* name) {
                    int id = rt_.vm.varIdForName(name);
                    if (!rt_.vm.memberExists(inst, id)) return static_cast<double>(NAN);
                    return rt_.vm.memberGet(inst, id).num();
                };
                std::fprintf(stderr, "DT_LAYER_EVENT|%d|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%d|%d\\n",
                    dt_layer_tick, inst->x, inst->y, dt_var("foot_right_x"), dt_var("foot_right_y"),
                    dt_var("foot_left_x"), dt_var("foot_left_y"), projX_, projY_, projW_, projH_, projAngle_,
                    customMats_ ? 1 : 0, (appSurface_ >= 0 && curTarget_ == surfaces_[appSurface_]) ? 1 : 0);
            }
            if (!rt_.performEvent(inst, EV_DRAW, DRAW_NORMAL)) drawSelf(inst);
            if (dt_trace) dt_layer_instance = nullptr;
        } else if (it.kind == 1) {'''),
    ]
    for old, new in patches:
        if source.count(old) != 1:
            raise ValueError('unexpected source layout')
        source = source.replace(old, new, 1)
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    args.source.write_text(patch(args.source.read_text()))
    print('LAYER_INSTRUMENT: bounded disposable desktop trace; not an IPA')


if __name__ == '__main__':
    main()
