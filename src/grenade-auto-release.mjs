import { finite } from './core.mjs';

// Packet-level gate, independent of aiming and server state. Never starts Fire.
// A rejected/unstable opportunity relinquishes the remainder of this physical hold.
export class GrenadeAutoRelease {
  constructor() { this.reset(); }
  reset() { this.phase = 'idle'; this.target = null; this.since = null; this.lastTime = null; }
  observe({ held, edge, enabled, ready, target, viable, now }) {
    if (held !== true) { this.reset(); return 'native'; }
    if (this.phase === 'released') return 'suppress';
    if (!finite(now) || (this.lastTime !== null && now < this.lastTime)) { this.phase = 'manual'; return 'native'; }
    this.lastTime = now;
    if (this.phase === 'manual') return 'native';
    if (this.phase === 'idle') {
      if (!edge || !enabled || !ready) { this.phase = 'manual'; return 'native'; }
      this.phase = 'armed'; return 'native';
    }
    if (!enabled || !ready) { this.phase = 'manual'; return 'cancel'; }
    // Once acquired, any target change or plan loss permanently cancels the hold.
    if (this.target !== null && target !== this.target) { this.phase = 'manual'; return 'cancel'; }
    if (target === null || target === undefined) return 'native';
    if (this.target === null) { this.target = target; this.since = now; return 'native'; }
    if (!viable || now - this.since < 200) return 'native';
    this.phase = 'released'; return 'release';
  }
}
