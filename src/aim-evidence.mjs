import { finite } from './core.mjs';

// Bounded local evidence, not network telemetry. No positions, directions,
// player IDs, names, message bodies or tokens are retained/exported.
export class AimEvidence {
  constructor() { this.reset(); }
  reset() {
    this.requests = 0; this.forwarded = 0; this.corrected = 0;
    this.lastLiveAttempt = null; this.lastGameplayForward = null; this.lastCorrection = null; this.transitions = [];
  }
  attempt(state, controls, rejections, now, live) {
    if (!live) return; // Opening Help or dying must not erase the live evidence.
    const record = { time: now, state, ...controls, rejections: { ...rejections } };
    this.lastLiveAttempt = record;
    if (this.transitions.at(-1)?.state !== state) {
      this.transitions.push({ time: now, state }); this.transitions = this.transitions.slice(-12);
    }
  }
  sent(native, output, applied, now, live) {
    this.forwarded++;
    if (!live) return;
    const a = native.toMouseDir, b = output.toMouseDir;
    const degrees = Math.abs(Math.atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)) * 180 / Math.PI;
    const record = { time: now, aimApplied: !!applied, correctionDegrees: finite(degrees) ? Math.round(degrees * 1000) / 1000 : 0,
      firePreserved: native.shootStart === output.shootStart && native.shootHold === output.shootHold,
      movementPreserved: ['moveLeft', 'moveRight', 'moveUp', 'moveDown'].every(k => native[k] === output[k]) };
    this.lastGameplayForward = record;
    if (record.aimApplied && degrees > .01) { this.corrected++; this.lastCorrection = { ...record }; }
  }
  snapshot(now) {
    const stamp = value => { if (!value) return null; const { time, ...rest } = value; return { ...rest, ...(rest.rejections ? { rejections: { ...rest.rejections } } : {}), ageMs: Math.max(0, Math.round(now - time)) }; };
    return { schedulerRequests: this.requests, forwardedInputs: this.forwarded, correctedGameplayInputs: this.corrected,
      lastLiveAttempt: stamp(this.lastLiveAttempt), lastGameplayForward: stamp(this.lastGameplayForward), lastCorrection: stamp(this.lastCorrection),
      transitions: this.transitions.map(stamp), meaning: 'Observed native sender forwards only; not a server acknowledgement or proof of hit.' };
  }
}
