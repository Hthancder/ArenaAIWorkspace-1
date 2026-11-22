# Radio observation host checks

Run `./tests/radio-observation/run.sh [patched-Bruce-path]`. The tests cover
bounded 802.11 information-element parsing (including truncated FCS cases),
exact BSSID collision handling and capacity, overflow-safe sampling math, BLE
manufacturer-data validation, expiration and counter rollover. Random malformed
inputs run under ASan/UBSan; a Node test checks the WebUI's handling of missing
or invalid channel samples. These tests do not emulate radios or ESP-IDF.

ESP-IDF's promiscuous `sig_len` includes the four-byte FCS; WIDS and Channel
Analyzer exclude it before parsing tagged parameters. WIDS only observes the
current channel, learns its initial BSSID without authentication, and caps its
exact BSSID table at 64. A same-SSID BSSID can be a legitimate mesh AP. A high
beacon count or deauthentication observation is not proof of an attack.

Channel Analyzer uses packet-based load estimates with an assumed data rate and
fixed overhead, not hardware airtime measurement. Missed frames, non-Wi-Fi
signals, channel hopping and radio/regulatory limitations affect results.
The advisor waits for samples on channels 1–11; channel 12/13 gaps produce a
partial estimate. The JSON includes `sampled`, `neighborsComplete` and
`loadModel`, with `bestCh=0` / `bestScore=-1` when no recommendation is ready.

BLE Privacy Guard is a best-effort passive scan: UUID/manufacturer patterns can
be spoofed or missed and do not authenticate a tracker or establish stalking.
FindMy-like records require a complete Apple 0x12/0x19 payload, and ordinary
Apple Nearby records no longer count as tracker candidates. Each sweep retains
at most 96 advertisers and the candidate list at most 40 address/type pairs;
limits can hide observations. Candidates expire after 120 seconds during active
scans and hit counts saturate rather than wrap. Paused results may be stale;
the report includes candidate ages and coverage flags. A basic screen is used
when a sprite cannot be allocated.
