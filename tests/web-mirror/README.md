# Screen mirror regression checks

The tracked firmware is the Bruce patch, not the ignored Bruce checkout. Apply
`firmware/dsolution-183-2mic-bruce.patch` to the pinned Bruce revision before
running these checks:

```sh
./tests/web-mirror/run.sh /path/to/patched/Bruce
```

They exercise the real logger source with a small host display/FreeRTOS stub
(ASan/UBSan) and the browser renderer with a canvas stub. They cover ring wrap
ordering, duplicate draw commands, logging while the panel sleeps, image-slot
exhaustion, consistent frame metadata, malformed packets, signed pixel coordinates,
image failures, exact navigation parsing, and coalesced refreshes.
These are regression tests, **not** an ESP32 build or a hardware test.

The navigator replays logged drawing commands; it is not a framebuffer capture.
The NV3023 board has no display readback. Raw image buffers, sprites, arbitrary
fonts and animations that bypass the logger may be missing or inaccurate, and
log overflow can drop the background. The UI reports incomplete history, but
cannot detect every unlogged drawing operation. Full pixel-accurate mirroring
requires a shadow framebuffer or lower-level display interception, with memory,
performance and power tradeoffs, plus on-device verification.

The renderer also checks per-string text datum alignment and reports known
sprite and bitmap bypasses using `X-Screen-Unmapped`. JavaScript interpreter
drawing targets the logger for supported primitives instead of the base driver;
bitmap, gradient and sprite calls still report an incomplete mirror. Browser
font rendering remains an approximation, and detection is not exhaustive.
The screen endpoint uses a new `DRAWSTRING_DATUM` packet (22). Serial output
converts it back to legacy packet 16, without datum information.
