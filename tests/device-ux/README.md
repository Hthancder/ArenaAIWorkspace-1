# DSolution UX host tests

`./tests/device-ux/run.sh /path/to/patched/Bruce` compiles the real notification and find-device code against fake I2S, I2C, task and preference APIs, with ASan/UBSan. It verifies fixed I2S pins and 48 kHz, stereo nonzero samples plus a silent DMA tail, mute and microphone/player-busy checks, I2C NACK and write failure cleanup, menu tone mode, alert throttling, low-battery debounce/hysteresis, find cooldown/expiration/cancellation, favorite toggles and recent tool selection, and the browser control payloads and CSRF header.

These are mocked host tests, not an ESP32 build and not a hardware/audio/acoustic test. They cannot prove actual GPIO clocks, speaker audibility, register correctness, race freedom with concurrent serial/audio tasks, LED behavior, timing, flash fit or WebUI response on the device. Build the board and verify on real hardware before relying on the result.

The file UI regression tests cover multi-batch folder drops, per-file destinations and failure recovery, out-of-order folder responses, and failed editor saves. The audio test also simulates cancelling and restarting Find while a tone is being written. These mocks do not exercise the real filesystem or browser/device network.
