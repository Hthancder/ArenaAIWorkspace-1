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


def added(source: str, start: str = "", end: str = "") -> str:
    """Return only the lines a diff slice *adds* (post-patch code).

    Whole-file sections (new files) are fully reconstructible, but a section for
    a modified file only contains its hunks -- the unchanged lines between them
    are absent. So assertions about current behaviour read the added lines,
    which is exactly what the patch introduces.
    """
    seg = source if not start else region(source, start, end)
    return "\n".join(ln[1:] for ln in seg.splitlines() if ln.startswith("+"))


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


def whole_file(path: str) -> str:
    """Reconstruct a file the patch *creates* (every line is an addition)."""
    return "\n".join(
        ln[1:] for ln in section(path).splitlines()
        if ln.startswith("+") and not ln.startswith("+++")
    )


def region(source: str, start: str, end: str) -> str:
    """Slice a fragment of the reconstructed file between two markers."""
    a = source.find(start)
    assert a >= 0, f"missing marker: {start}"
    b = source.find(end, a)
    assert b >= 0, f"missing end marker: {end}"
    return source[a:b]


portal_napt_raw = section("src/modules/wifi/portal_napt.cpp")
evil_portal_raw = section("src/modules/wifi/evil_portal.cpp")
napt_router_raw = section("src/modules/wifi/napt_router.cpp")
logic = section("src/modules/wifi/evil_twin_logic.h")

portal_napt = portal_napt_raw
evil_portal = evil_portal_raw
napt_router = napt_router_raw

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
assert all(ln.startswith("-") for ln in evil_portal_raw.splitlines() if "> 250 && _deauth" in ln), \
    "permanent deauth flood removed"
assert "_deauthPulseAt" in evil_portal, "chain-driven deauth pulse missing"
assert "_deauthPulseAt" not in creds

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


# ------------------------------------------- manual mode (WiFi Atks -> target)
# The device path is WiFi -> WiFi Tools -> WiFi Attacks -> target -> Deauth /
# Clone / Verify, i.e. EvilPortal(deauth=true, verify=true, autoMode=true) with
# backgroundMode=false. Two regressions lived here and both look like "the
# attack does nothing":
#   * deauth was either a 250 ms flood forever (phones blacklist the SSID and
#     fall back to mobile data) or never sent at all in manual mode,
#   * verify was dropped entirely ((void)verifyPwd) so no key was ever checked.
ctor = added(evil_portal, "@@ -26,6 +48,15 @@", "cleanlyStopWebUiForWiFiFeature")
assert "_chainKick = !_backgroundMode && _deauth" in ctor, \
    "manual mode must own a kick window (chain-less deauth)"
assert "_asyncVerify = _verifyPwd" in ctor, "manual verify must run off the HTTP task"

loop = added(evil_portal, "if (!isDeauthHeld && _deauth && _deauthPulseAt)", "if (totalCapturedCredentials !=")
# Bounded kick: budget + backoff + safety gate, never a bare timer.
assert "_chainKick" in loop, "manual kick window missing from the portal loop"
assert "evilTwinDeauthGapMs(" in loop, "manual kick must use the backed-off gaps"
assert "_kickBursts < kickTiming.maxBursts" in loop, "manual kick must stay inside the burst budget"
# Safety gate: kicking while the victim is already on the clone throws it off
# the clone too (the "phone falls back to mobile data" symptom).
assert "apClientCount() > 0" in loop, "manual kick must stop once the victim joined the clone"
assert "_deauthPulseAt" in loop, "chain-driven pulse must still work"
# Async verify inside the portal loop, not inside the request handler.
assert "takePendingCredentials(" in loop, "portal loop must pick up the queued key"
assert "verifyCredentialsLocked(vSsid" in loop, "portal loop must run the handshake test"
assert "notifyVerifyResult(" in loop, "verify result must reach the routing gate"
# A wrong key must not end the manual attack: the remaining budget pulls a
# victim that fell back to mobile data in again (bounded, never a new flood).
assert "if (!vOk && _chainKick && apClientCount() == 0)" in loop, \
    "manual mode must re-arm the bounded kick after a wrong key"
# The old unconditional flood may only survive as a removed line.
assert all(ln.startswith("-") for ln in evil_portal_raw.splitlines() if "> 250 && _deauth" in ln)

evil_portal_h = section("src/modules/wifi/evil_portal.h")
for field in ("_chainKick", "_kickBursts", "_lastKickMs", "_asyncVerify"):
    assert field in evil_portal_h, f"missing portal state: {field}"

# ------------------------------------------------------- chain menu plumbing
# WiFi -> Chains used to bounce straight back: every submenu shared the global
# `options` vector and cleared it, so the menu that was still running lost its
# own entries from under the loop. Each level must own its vector.
chains = whole_file("src/modules/wifi/chain_orchestrator.cpp")
assert "options.clear()" not in chains, "chain menus must not clear the shared global menu vector"
assert "loopOptions(options" not in chains, "chain menus must pass their own vector"
assert chains.count("std::vector<Option> opts") >= 8, "every chain submenu needs a local vector"
# A tap must never dead-end silently.
assert "static void explainNoTarget" in chains, "a tap with no target must explain itself"
assert "static bool askEvilTwinTarget" in chains, "the evil-twin entry must be able to ask for a target"
assert "(need target)" not in chains, "stale dead-end label"
route_menu = body(chains, "static void evilTwinRouteMenu")
assert "askEvilTwinTarget(targetSsid" in route_menu, "evil-twin route must ask for a target in place"
assert "explainNoTarget(" in route_menu, "evil-twin route must explain a missing target"


# ------------------------------------------------------------ menu dispatch
# loopOptions() used to call `options[chosen].operation()` directly. `options`
# is the shared global vector and most operations rewrite it (EvilPortal::setup
# re-assigns it, target_atk_menu re-assigns it, chain menus rebuild it), so the
# std::function being executed was destroyed mid-flight. On the device that is
# either "the tap does nothing / jumps back" or a crash.
display_patch = section("src/core/display.cpp")
assert "std::function<void()> chosenOp = options[chosen].operation;" in display_patch, \
    "loopOptions must copy the callback before running it"
dispatch = display_patch[display_patch.index("Selected: "):]
assert dispatch.index("chosenOp = options[chosen].operation") < dispatch.index("chosenOp();"), \
    "the copy must happen before the call"
assert "options[chosen].operation();" not in added(display_patch), \
    "must not call through the shared vector"

print("evil-twin / portal-NAPT regression checks passed")
