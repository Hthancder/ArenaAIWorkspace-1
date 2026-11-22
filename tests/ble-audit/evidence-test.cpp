#include "modules/ble/ble_audit_logic.h"
#include <cassert>
#include <cstdio>
int main() {
    const time_t failed = static_cast<time_t>(-1);
    // Timestamp 0 is success when NimBLE timestamps are disabled, even for an empty value.
    assert(bleAuditReadEvidence(0, true, false, false) == BleAuditEvidence::Unencrypted);
    assert(bleAuditReadEvidence(1, true, true, true) == BleAuditEvidence::Encrypted);
    assert(bleAuditReadEvidence(1, true, false, true) == BleAuditEvidence::Encrypted);
    assert(bleAuditReadEvidence(failed, true, false, false) == BleAuditEvidence::Unconfirmed);
    assert(bleAuditReadEvidence(1, false, false, false) == BleAuditEvidence::Unconfirmed);
    assert(bleAuditWriteEvidence(true, true, true, false, false) == BleAuditEvidence::Unencrypted);
    assert(bleAuditWriteEvidence(true, true, true, false, true) == BleAuditEvidence::Encrypted);
    assert(bleAuditWriteEvidence(true, false, true, false, false) == BleAuditEvidence::Unconfirmed);
    assert(bleAuditWriteEvidence(false, true, true, false, false) == BleAuditEvidence::Unconfirmed);
    assert(bleAuditWriteEvidence(true, true, false, false, false) == BleAuditEvidence::Unconfirmed);
    assert(!bleAuditUseBoundaryWrites(0, true));
    assert(!bleAuditUseBoundaryWrites(1, true));
    assert(!bleAuditUseBoundaryWrites(2, false));
    assert(bleAuditUseBoundaryWrites(2, true));
    std::puts("BLE audit evidence regression tests passed");
}
