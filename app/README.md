# Lantern standalone mock executable

This is a zero-dependency Rust Windows executable that embeds the browser UI and a small local HTTP/JSON API. It exists so you can try the **interactive mock** on the Inspiron without installing Node.js or Rust.

## Download and run

1. Open the GitHub Actions run for the branch and download artifact **`lantern-mock-windows-x64`**.
2. Extract `lantern-mock.exe` and double-click it. It binds only to `127.0.0.1` on an available port, then opens the browser. If the browser does not open, use the URL printed in the console.
3. Keep the console window open while testing; close it to stop the server.

Mock settings persist under `%LOCALAPPDATA%\LanternMock\settings.json`.

**This is not yet the remote desktop implementation.** The “Kiểm tra máy thật” panel reads host/GPU/RAM/Wi-Fi/monitor facts and checks installed GStreamer plugins. Only after you click “Chạy 5 giây”, the exe asks GStreamer to read 150 DXGI frames and discard them into a local `fakesink`; it does not save or transmit the pixels. No WebRTC session, remote input, camera/microphone/audio stream, or LAN/Internet listener is implemented. The normal server binds only loopback. Do not expose it to the LAN/Internet. The old `rd-windows-x64` artifact is the CLI pipeline spike; choose `lantern-mock-windows-x64` for this browser app.
