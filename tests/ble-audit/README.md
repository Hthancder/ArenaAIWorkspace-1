# BLE audit host checks

`./tests/ble-audit/run.sh [patched-Bruce-path]` tests the evidence and audit
mode policy with ASan/UBSan. It does not emulate NimBLE or a BLE device. The
read success sentinel is based on NimBLE-Arduino 2.5.1 `readValue(time_t*)`:
it writes a timestamp only on success, and writes zero when timestamps are
compiled out. If the clock returns the sentinel value, evidence is conservatively
unconfirmed. Reads and writes can initiate pairing in NimBLE, so link encryption
is checked after the operation too. A write without response only confirms
local queueing; long writes can be truncated by the library. Legacy finding
names `UNAUTH_READ`/`UNAUTH_WRITE` indicate unencrypted access, not proof of
missing application authorization or a vulnerability.

Ordinary Auto Security Audit does not do test writes. Boundary writes are off
by default on new configuration, require the setting and separate mode, and can
modify or disrupt the device. Existing saved settings are retained but cannot
make the ordinary audit perform boundary writes. A disconnected end-of-audit
link is reported as unknown, not inferred from the initial encryption state.
