#!/usr/bin/env python3
"""Static regression checks for the portal-to-NAPT handoff in the Bruce patch."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = (ROOT / "firmware/dsolution-183-2mic-bruce.patch").read_text()


def section(path: str) -> str:
    marker = f"diff --git a/{path} b/{path}"
    start = PATCH.find(marker)
    assert start >= 0, f"missing patch section: {path}"
    end = PATCH.find("\ndiff --git ", start + len(marker))
    return PATCH[start:] if end < 0 else PATCH[start:end]


portal_napt = section("src/modules/wifi/portal_napt.cpp")
evil_portal = section("src/modules/wifi/evil_portal.cpp")

# A verify-enabled portal must wait for verified credentials and pass those
# exact SSID/password values through the handoff (not the initially empty pwd).
assert "s_verify ? s_portal->hasVerifiedPassword()" in portal_napt
assert "getLastVerifiedSsid()" in portal_napt
assert "getLastVerifiedPassword()" in portal_napt
assert "naptStartBackground(staSsid, staPwd, &err)" in portal_napt

# Background handoff has one owner: portalNaptTask. The request pump must not
# race it by independently stopping the portal or starting NAPT.
process_start = evil_portal.find("void EvilPortal::processRequests()")
assert process_start >= 0
process_end = evil_portal.find("@@ ", process_start)
process_body = evil_portal[process_start:process_end if process_end >= 0 else None]
assert "_naptHandoffPending" not in process_body
assert "portalNaptTask()" in process_body

# Incorrect passwords cannot arm a portal-triggered handoff when verification
# is enabled; unverified credential submissions must not route.
assert "(!_verifyPwd || _lastVerifyOk)" in evil_portal
print("portal/NAPT handoff regression checks passed")
