# WebUI control tests

`tests/webui-control/run.sh firmware/Bruce` compiles the actual menu/stop function bodies extracted from the patched firmware, using host mocks. It checks start/stop actions, WiFi preservation, cancellation still in progress, OTA/transition guards, and an OTA beginning during cancellation. Additional source-wiring checks cover the legacy Startup App and entry points. These tests do not simulate FreeRTOS scheduling, radio hardware, real OTA or concurrent AsyncTCP teardown; those still require hardware tests.
