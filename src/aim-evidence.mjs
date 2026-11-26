import { finite } from './core.mjs';

// Bounded local evidence, not network telemetry. No positions, directions,
// player IDs, names, message bodies or tokens are retained/exported.
export class AimEvidence {
  constructor() { this.reset(); }
  reset() {
    this.requests = 0; this.forwarded = 0; this.corrected = 0; this.inputCalls = 0; this.invalidInputs = 0; this.inputErrors = 0;
    this.lastLiveAttempt = null; this.lastEngagedAttempt = null; this.lastEngagedFailure = null; this.lastGameplayForward = null; this.lastCorrection = null; this.lastFireForward = null; this.lastFireFailure = null; this.transitions = [];
  }
  attempt(state, controls, rejections, now, live) {
    if (!live) return; // Opening Help or dying must not erase the live evidence.
    const record = { time: now, state, ...controls, rejections: { ...rejections } };
    this.lastLiveAttempt = record;
    if (state !== 'waiting-activation' && state !== 'disabled') {
      this.lastEngagedAttempt = record;
      if (state !== 'input-applied' && state !== 'ready-to-send') this.lastEngagedFailure = record;
    }
    if (this.transitions.at(-1)?.state !== state) {
      this.transitions.push({ time: now, state }); this.transitions = this.transitions.slice(-12);
    }
  }
  sent(native, output, applied, now, live, fireContext = null) {
    this.forwarded++;
    if (!live) return;
    const a = native.toMouseDir, b = output.toMouseDir;
    const degrees = Math.abs(Math.atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)) * 180 / Math.PI;
    const record = { time: now, aimApplied: !!applied, correctionDegrees: finite(degrees) ? Math.round(degrees * 1000) / 1000 : 0,
      firePreserved: native.shootStart === output.shootStart && native.shootHold === output.shootHold,
      movementPreserved: ['moveLeft', 'moveRight', 'moveUp', 'moveDown'].every(k => native[k] === output[k]) };
    this.lastGameplayForward = record;
    if (fireContext && (native.shootStart || native.shootHold || fireContext.physicalHeld)) {
      this.lastFireForward = { ...record, packetStart: native.shootStart, packetHeld: native.shootHold,
        physicalHeld: !!fireContext.physicalHeld, aimKeyHeld: !!fireContext.aimKeyHeld,
        aimState: fireContext.aimState, rejections: { ...fireContext.rejections },
        directMouseEnabled: !!fireContext.directMouseEnabled, directMouseActive: !!fireContext.directMouseActive };
      if (!record.aimApplied) this.lastFireFailure = this.lastFireForward;
    }
    if (record.aimApplied && degrees > .01) { this.corrected++; this.lastCorrection = { ...record }; }
  }
  snapshot(now) {
    const stamp = value => { if (!value) return null; const { time, ...rest } = value; return { ...rest, ...(rest.rejections ? { rejections: { ...rest.rejections } } : {}), ageMs: Math.max(0, Math.round(now - time)) }; };
    return { schedulerRequests: this.requests, inputCalls: this.inputCalls, invalidInputs: this.invalidInputs, inputErrors: this.inputErrors,
      forwardedInputs: this.forwarded, correctedGameplayInputs: this.corrected,
      lastLiveAttempt: stamp(this.lastLiveAttempt), lastEngagedAttempt: stamp(this.lastEngagedAttempt), lastEngagedFailure: stamp(this.lastEngagedFailure),
      lastGameplayForward: stamp(this.lastGameplayForward), lastFireForward: stamp(this.lastFireForward), lastFireFailure: stamp(this.lastFireFailure), lastCorrection: stamp(this.lastCorrection),
      transitions: this.transitions.map(stamp), meaning: 'Observed native sender forwards only; not a server acknowledgement or proof of hit.' };
  }
}
