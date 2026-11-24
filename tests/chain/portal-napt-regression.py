#!/usr/bin/env python3
"""Static regression checks for the Evil Twin / portal-to-NAPT path.

Every assertion below pins a rule that exists because breaking it kicks the
victim off *both* the real network and the clone:

  * a form submit must never block on a 4-way handshake,
  * verification must never re-tune the SoftAP (AP+STA follows the STA channel),
  * routing must upgrade the running AP instead of tearing it down,
  * deauth must be a bounded, backed-off window,
  * after routing, the captive DNS hijack and probe redirects must stop.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = (ROOT / "firmware/dsolution-183-2mic-bruce.patch").read_text()


def section(path: str) -> str:
    marker = f"diff --git a/{path} b/{path}"
    start = PATCH.find(marker)
    assert start >= 0, f"missing patch section: {path}"
    end = PATCH.find("\ndiff --git ", start + len(marker))
    return PATCH[start:] if end < 0 else PATCH[start:end]


def body(source: str, signature: str) -> str:
    """Return one function body from a patch section, comments stripped.

    Mirrors the added/context/removed line prefixes of a unified diff and stops
    at the next hunk so a "must not appear here" assertion cannot see a
    neighbouring function or a hunk trailer.
    """
    start = source.find(signature)
    assert start >= 0, f"missing function: {signature}"
    out, depth, seen_brace = [], 0, False
    for raw in source[start:].splitlines():
        if raw.startswith(("@@", "diff --git")):
            break
        sign = raw[:1] if raw[:1] in "+- " else "+"
        line = raw[1:] if raw[:1] in "+- " else raw
        if sign == "-":
            continue  # removed line: not part of the current code
        stripped = line.strip()
        out.append(line)
        depth += line.count("{") - line.count("}")
        if "{" in line:
            seen_brace = True
        if seen_brace and depth <= 0:
            break
    code = [ln for ln in out if not ln.strip().startswith("//")]
    return "\n".join(code)


portal_napt = section("src/modules/wifi/portal_napt.cpp")
evil_portal = section("src/modules/wifi/evil_portal.cpp")
napt_router = section("src/modules/wifi/napt_router.cpp")
logic = section("src/modules/wifi/evil_twin_logic.h")

# ---------------------------------------------------------------- verification
creds = body(evil_portal, "void EvilPortal::credsController")
# The HTTP handler must not run the handshake: it answers and hands off.
assert "verifyCredentialsLocked(" not in creds, "verification must not run in the HTTP handler"
assert "_pendingCredReady = true;" in creds, "async verify must queue the submitted key"
assert "verifyWaitPage()" in creds, "the victim needs an immediate 'checking' page"
assert "(!_verifyPwd || _lastVerifyOk)" in evil_portal, "unverified keys must never arm routing"

verify = body(evil_portal, "bool EvilPortal::verifyCredentialsLocked")
# Pin the STA to the clone channel; never let the AP follow a channel hop.
assert "esp_wifi_set_channel(channel" in verify
assert "setAutoReconnect(false)" in verify, "background retries fight the SoftAP"
assert "softAPdisconnect(" not in verify, "verification must not drop the AP"
assert "WIFI_MODE_NULL" not in verify and "WiFi.mode(WIFI_OFF)" not in verify
# Our own AP MAC must never be passed as the association BSSID.
assert "s_cloneBssid" not in body(portal_napt, "static void etServiceVerify")

# ------------------------------------------------------------------- deauth
deauth = body(portal_napt, "static void etServiceDeauth")
assert "evilTwinDeauthAction(" in deauth, "deauth must follow the bounded policy"
assert "victimOnOurAp" in deauth and "verifying" in deauth, "safety gates missing"
# The portal must only send when pulsed by the chain, not on a 250 ms timer.
# Only the *removed* line (prefixed "-") may mention the old flood.
assert all(ln.startswith("-") for ln in evil_portal.splitlines() if "> 250 && _deauth" in ln), \
    "permanent deauth flood removed"
assert "_deauthPulseAt" in evil_portal, "chain-driven deauth pulse missing"
assert "_deauthPulseAt" not in body(evil_portal, "void EvilPortal::credsController")

# ------------------------------------------------------------------- routing
route = body(portal_napt, "static bool etRouteInPlace")
assert "naptEnableOnRunningAp(" in route, "routing must upgrade the running AP"
assert "naptStartBackground(" not in route, "routing must not rebuild (and drop) the AP"
assert "setInternetUp(true)" in route, "captive hijack must stop before routing"
assert "ET_HANDOFF_BLOCKED" in route, "a channel-moving handoff must be refused"

napt_fn = body(napt_router, "bool naptEnableOnRunningAp")
assert "softAPdisconnect(" not in napt_fn, "in-place NAPT must keep the AP (and its BSSID)"
assert "enableNAPT(true)" in napt_fn
assert "WiFi.mode(WIFI_AP_STA)" in napt_fn, "AP must not be turned off for the uplink"
# Re-running softAPConfig() on a live AP restarts DHCP under the clients.
assert "softAPConfig(" not in napt_fn, "in-place NAPT must not touch the running DHCP server"

# Handoff must be single-owner: portalNaptTask, not the request pump.
process_body = body(evil_portal, "void EvilPortal::processRequests")
assert "_naptHandoffPending" not in process_body
# One owner: the request pump must not stop the portal or start NAPT itself.
assert "_naptHandoffPending" not in process_body
assert "naptStart" not in process_body and "naptEnable" not in process_body

# ------------------------------------------------------------------- recovery
# A wrong key must not end the chain: the clone stays up and, if the victim has
# left (mobile data), the *remaining* bounded budget pulls it back.
rearm = body(portal_napt, "static void etServiceVerify")
assert "apClientCount() == 0" in rearm, "victim that left after a wrong key is lost"
assert "maxBursts" in rearm, "the second chance must stay inside the burst budget"
# Deauth must never overwrite a routed/failed phase (vulnerable-window regression).
deauth_svc = body(portal_napt, "static void etServiceDeauth")
# The phase assignment must be inside the "kick window owns the chain" guard.
guard = "s_phase == ET_PHASE_IDLE || s_phase == ET_PHASE_DEAUTH || s_phase == ET_PHASE_CLONE"
assert guard in deauth_svc, "deauth must not drive ROUTE/ONLINE phases"
assert deauth_svc.index(guard) < deauth_svc.index("s_phase = (action == ET_DEAUTH_SEND")
# A dropped uplink after routing must be detected and repaired.
assert "uplink_lost" in portal_napt

# ------------------------------------------------------------------ DNS/probes
internet_up = body(evil_portal, "void EvilPortal::setInternetUp")
assert "stopCaptiveDns()" in internet_up, "wildcard DNS must be released for the NAPT resolver"
assert "serveProbe" in evil_portal
assert "evilTwinProbeStatus(" in evil_portal, "probes must succeed once the victim is routed"

# --------------------------------------------------------------- policy sanity
for rule in (
    "ET_DEAUTH_STOP_JOINED",
    "ET_DEAUTH_STOP_ROUTED",
    "ET_HANDOFF_IN_PLACE",
    "evilTwinJoinGraceDeadline",
    "evilTwinClassifyVerify",
):
    assert rule in logic, f"missing evil-twin rule: {rule}"

print("evil-twin / portal-NAPT regression checks passed")
