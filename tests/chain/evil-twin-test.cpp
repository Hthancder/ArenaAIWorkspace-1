// Host-side regression tests for the Deauth -> Clone -> Verify -> Route
// policy (src/modules/wifi/evil_twin_logic.h). The interesting bugs in this
// chain are timing/state bugs that kick a victim off *both* the real and the
// fake network, so every rule below is a rule about NOT dropping the victim.
#include "modules/wifi/evil_twin_logic.h"
#include <cassert>
#include <cstdio>
#include <cstring>

static EvilTwinDeauthInput baseInput(EvilTwinTiming t) {
    EvilTwinDeauthInput in{};
    in.nowMs = 10000;
    in.windowStartMs = 9000; // clone up 1s ago
    in.burstsDone = 0;
    in.lastBurstMs = 9000;
    in.victimOnOurAp = false;
    in.verifying = false;
    in.routed = false;
    in.pmfRequired = false;
    in.portalUp = true;
    in.rejoinGraceUntilMs = 0;
    in.timing = t;
    return in;
}

int main() {
    EvilTwinTiming t = evilTwinDefaultTiming();

    // --- timing / backoff ---------------------------------------------------
    assert(t.maxBursts >= 3 && t.maxBursts <= 10);          // short kick window
    assert(t.burstGapMs < t.maxBurstGapMs);
    assert(evilTwinDeauthGapMs(t, 0) == t.burstGapMs);
    assert(evilTwinDeauthGapMs(t, 1) == t.burstGapMs * 2);
    assert(evilTwinDeauthGapMs(t, 2) == t.burstGapMs * 4);
    assert(evilTwinDeauthGapMs(t, 3) == t.maxBurstGapMs);   // capped
    assert(evilTwinDeauthGapMs(t, 99) == t.maxBurstGapMs);  // no overflow
    assert(evilTwinDeauthGapMs(t, 255) == t.maxBurstGapMs); // uint8 max, no overflow

    // --- deauth must be a bounded kick window, never a permanent flood ------
    EvilTwinDeauthInput in = baseInput(t);
    in.nowMs = in.windowStartMs + t.pmkidGraceMs + 1;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_SEND);      // first burst
    in = baseInput(t);
    in.nowMs = in.windowStartMs + 100;                       // too early
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_WAIT);
    in = baseInput(t);
    in.burstsDone = t.maxBursts;                             // budget spent
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_STOP_BUDGET);
    in = baseInput(t);
    in.nowMs = in.windowStartMs + t.pmkidGraceMs + 1;
    in.burstsDone = 1;
    // pause before burst #2 is the base gap (backoff grows from there)
    uint32_t gap1 = evilTwinDeauthGapMs(t, 0);
    in.lastBurstMs = in.nowMs - (gap1 - 1);                  // just before the gap
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_WAIT);
    in.lastBurstMs = in.nowMs - gap1;                        // gap elapsed
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_SEND);
    // pause before burst #3 is twice as long: no machine-gun bursts
    in.burstsDone = 2;
    uint32_t gap2 = evilTwinDeauthGapMs(t, 1);
    in.lastBurstMs = in.nowMs - gap1;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_WAIT);
    in.lastBurstMs = in.nowMs - gap2;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_SEND);

    // --- every "victim safety" gate wins over sending ----------------------
    in = baseInput(t);
    in.nowMs = in.windowStartMs + t.pmkidGraceMs + 1;
    in.victimOnOurAp = true;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_STOP_JOINED);
    in = baseInput(t);
    in.nowMs = in.windowStartMs + t.pmkidGraceMs + 1;
    in.verifying = true;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_STOP_VERIFY);
    in = baseInput(t);
    in.routed = true;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_STOP_ROUTED);
    in = baseInput(t);
    in.pmfRequired = true;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_STOP_PMF);
    in = baseInput(t);
    in.portalUp = false;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_STOP_NO_PORTAL);
    // routed outranks everything: a routed victim is never kicked
    in = baseInput(t);
    in.nowMs = in.windowStartMs + t.pmkidGraceMs + 1;
    in.routed = true;
    in.victimOnOurAp = true;
    in.verifying = true;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_STOP_ROUTED);

    // --- rejoin grace: a freshly joined victim is left alone ---------------
    in = baseInput(t);
    in.nowMs = 20000;
    in.rejoinGraceUntilMs = evilTwinJoinGraceDeadline(20000, t);
    assert(in.rejoinGraceUntilMs == 20000 + t.rejoinGraceMs);
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_WAIT);
    in.nowMs = in.rejoinGraceUntilMs;               // grace over -> may kick again
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_SEND);
    // millis() wraparound must not turn the grace into a 49-day silence
    in = baseInput(t);
    in.rejoinGraceUntilMs = 0xFFFFF000u;
    in.nowMs = 0x00001000u;                          // wrapped past the deadline
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_SEND);
    // ...and must not expire early either
    in.nowMs = 0xFFFFE000u;
    assert(evilTwinDeauthAction(in) == ET_DEAUTH_WAIT);

    // --- verify plan: never hop the AP off the victim's channel ------------
    EvilTwinVerifyPlan vp = evilTwinVerifyPlan(6, 6, true, t);
    assert(vp.lockChannel && vp.lockBssid && vp.keepAp && vp.autoReconnectOff);
    assert(vp.channel == 6 && vp.channelUsable);
    vp = evilTwinVerifyPlan(0, 11, false, t);        // clone ch unknown -> target
    assert(vp.channel == 11 && !vp.lockBssid);
    vp = evilTwinVerifyPlan(99, 99, true, t);        // garbage -> safe default
    assert(vp.channel == 6 && !vp.channelUsable);
    vp = evilTwinVerifyPlan(6, 11, true, t);         // mismatch is flagged
    assert(!vp.channelUsable && vp.channel == 6);
    assert(!evilTwinCloneChannelMatchesTarget(6, 11));
    assert(evilTwinCloneChannelMatchesTarget(11, 11));
    assert(evilTwinCloneChannelMatchesTarget(1, 0));  // unknown target: no opinion
    assert(evilTwinSanitizeChannel(0) == 6);
    assert(evilTwinSanitizeChannel(14) == 14);

    // --- verify result classification --------------------------------------
    assert(evilTwinClassifyVerify(true, 0) == ET_VERIFY_OK);
    assert(evilTwinClassifyVerify(false, 15) == ET_VERIFY_WRONG_KEY);  // 4-way timeout
    assert(evilTwinClassifyVerify(false, 204) == ET_VERIFY_WRONG_KEY);
    assert(evilTwinClassifyVerify(false, 23) == ET_VERIFY_WRONG_KEY);  // 802.1X
    assert(evilTwinClassifyVerify(false, 201) == ET_VERIFY_NO_AP);
    assert(evilTwinClassifyVerify(false, 200) == ET_VERIFY_NO_AP);
    assert(evilTwinClassifyVerify(false, 3) == ET_VERIFY_REJECTED);
    assert(evilTwinClassifyVerify(false, 999) == ET_VERIFY_TIMEOUT);
    assert(evilTwinVerifyResultName(ET_VERIFY_WRONG_KEY) != nullptr);
    // a wrong key keeps the clone alive for a retry; only "ok" routes
    assert(evilTwinPhaseForVerify(ET_VERIFY_WRONG_KEY) == ET_PHASE_CLONE);
    assert(evilTwinPhaseForVerify(ET_VERIFY_TIMEOUT) == ET_PHASE_CLONE);
    assert(evilTwinPhaseForVerify(ET_VERIFY_PENDING) == ET_PHASE_VERIFY);
    assert(evilTwinPhaseForVerify(ET_VERIFY_OK) == ET_PHASE_ROUTE);

    // --- handoff: in place, or refuse -------------------------------------
    assert(evilTwinHandoffMode(true, true, 6, 6, true) == ET_HANDOFF_IN_PLACE);
    assert(evilTwinHandoffMode(true, true, 6, 6, false) == ET_HANDOFF_IN_PLACE);
    assert(evilTwinHandoffMode(false, true, 6, 6, true) == ET_HANDOFF_RESTART_AP);
    assert(evilTwinHandoffMode(true, false, 6, 6, true) == ET_HANDOFF_RESTART_AP);
    // channel differs and our STA is not up yet -> cannot move the AP safely
    assert(evilTwinHandoffMode(true, true, 1, 6, false) == ET_HANDOFF_BLOCKED);
    // ...but once the STA is connected the driver has already co-located them
    assert(evilTwinHandoffMode(true, true, 1, 6, true) == ET_HANDOFF_IN_PLACE);
    assert(strcmp(evilTwinHandoffModeName(ET_HANDOFF_IN_PLACE), "in-place") == 0);

    // --- captive probes: Android must be told "you have internet" ----------
    assert(evilTwinClassifyProbe("http://connectivitycheck.gstatic.com/generate_204") == ET_PROBE_ANDROID_204);
    assert(evilTwinClassifyProbe("/generate_204") == ET_PROBE_ANDROID_204);
    assert(evilTwinClassifyProbe("http://captive.apple.com/hotspot-detect.html") == ET_PROBE_APPLE);
    assert(evilTwinClassifyProbe("http://www.msftconnecttest.com/connecttest.txt") == ET_PROBE_WINDOWS);
    assert(evilTwinClassifyProbe("http://detectportal.firefox.com/success.txt") == ET_PROBE_FIREFOX);
    assert(evilTwinClassifyProbe("/something") == ET_PROBE_OTHER);
    assert(evilTwinClassifyProbe("") == ET_PROBE_NONE);
    assert(evilTwinClassifyProbe(nullptr) == ET_PROBE_NONE);
    assert(evilTwinProbeStatus(ET_PROBE_ANDROID_204, false) == 302);
    assert(evilTwinProbeStatus(ET_PROBE_ANDROID_204, true) == 204);
    assert(evilTwinProbeStatus(ET_PROBE_APPLE, true) == 200);

    // --- phase naming is what the WebUI shows ------------------------------
    assert(strcmp(evilTwinPhaseName(ET_PHASE_DEAUTH), "Deauth") == 0);
    assert(strcmp(evilTwinPhaseName(ET_PHASE_CLONE), "Clone") == 0);
    assert(strcmp(evilTwinPhaseName(ET_PHASE_VERIFY), "Verify") == 0);
    assert(strcmp(evilTwinPhaseName(ET_PHASE_ROUTE), "Route") == 0);
    assert(evilTwinPhaseIsActive(ET_PHASE_CLONE));
    assert(!evilTwinPhaseIsActive(ET_PHASE_IDLE));
    assert(!evilTwinPhaseIsActive(ET_PHASE_FAILED));

    // --- snapshot json is bounded and well formed -------------------------
    char buf[256];
    EvilTwinSnapshot snap{ET_PHASE_DEAUTH, 2, true, false, ET_VERIFY_WRONG_KEY, "stop-joined"};
    size_t n = evilTwinSnapshotJson(snap, buf, sizeof(buf));
    assert(n > 0 && n < sizeof(buf));
    assert(strstr(buf, "\"phase\":\"Deauth\""));
    assert(strstr(buf, "\"deauth\":\"stop-joined\""));
    assert(strstr(buf, "\"victim\":true"));
    assert(strstr(buf, "\"verify\":\"wrong-key\""));
    assert(evilTwinSnapshotJson(snap, buf, 8) < 8);      // truncated, still bounded
    assert(evilTwinSnapshotJson(snap, nullptr, 0) == 0);
    assert(evilTwinSnapshotJson(snap, buf, 0) == 0);

    printf("evil-twin policy tests passed\n");
    return 0;
}
