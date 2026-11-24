from pathlib import Path
import sys

source = Path(sys.argv[1])
js = (source / "embedded_resources/web_interface/index.js").read_text()

# XHRs must settle even when the device loses Wi-Fi or the user navigates away.
request_helpers = js[js.index("async function requestGet"):js.index("function stringToId")]
assert request_helpers.count("req.timeout = 30000;") == 2
assert request_helpers.count("req.ontimeout =") == 2
assert request_helpers.count("req.onabort =") == 2

# Keep system telemetry from issuing duplicate/overlapping requests.
assert "let systemInfoRefreshBusy = false;" in js
assert "if (systemInfoRefreshBusy) return;" in js
assert "systemInfoRefreshBusy = false;" in js
assert "Keep the browser's applied palette/layout" not in js
assert js.count("}, 15000);") == 1
assert 'if (!document.hidden && $(".dialog-background.hidden") && !_runningUpload && !otaBusy)' in js

# High-cost device telemetry should poll conservatively, pause in background,
# and never render a second response batch while one is still being processed.
assert 'if (activeTab === "seclab" && !document.hidden' in js
assert "if (secLabRefreshBusy) return;" in js
assert "if (monRefreshBusy) return;" in js
assert "if (studioRefreshBusy) return;" in js
assert "monRefreshBusy = false;" in js
assert "studioRefreshBusy = false;" in js
assert "secLabRefreshBusy = false;" in js
assert '}, 8000);' in js
assert '}, 10000);' in js
print("WebUI polling and request-timeout regression checks passed")
