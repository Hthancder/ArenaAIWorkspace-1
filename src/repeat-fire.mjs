import { finite } from './core.mjs';

// Native auto/burst and autoAttack melee already respond to shootHold. Never
// synthesize throwable edges: a repeated edge can cook/throw a grenade.
export function repeatFirePolicy(def) {
  if (def?.type === 'melee') {
    if (def.autoAttack === true) return { state: 'native-auto', interval: null };
    if (finite(def.attack?.cooldownTime) && def.attack.cooldownTime > 0) {
      // Bounded retry edges, not a client cooldown bypass. Server meleeUpdate
      // drops early edges (unlike gun buffering), so retry at most 20 times/s.
      return { state: 'melee-repeat', interval: Math.min(50, def.attack.cooldownTime * 1000) };
    }
  }
  if (def?.type === 'gun') {
    if (def.fireMode === 'auto' || def.fireMode === 'burst') return { state: 'native-auto', interval: null };
    if (def.fireMode === 'single' && finite(def.fireDelay) && def.fireDelay > 0) return { state: 'single-repeat', interval: Math.max(50, def.fireDelay * 1000) };
  }
  return { state: def?.type === 'throwable' ? 'throwable-excluded' : 'unsupported-weapon', interval: null };
}
export class RepeatFire {
  reset() { this.next = 0; this.frame = -1; this.value = false; this.weapon = null; this.state = 'disabled'; }
  constructor() { this.reset(); this.pulses = 0; }
  sample({ frame, now, weapon, def, held, enabled, paused, protocolMatches }) {
    if (!enabled || paused || !protocolMatches || !held) {
      this.reset(); this.state = !enabled ? 'disabled' : paused ? 'paused' : !protocolMatches ? 'waiting-protocol' : 'fire-not-held'; return false;
    }
    if (weapon !== this.weapon) { this.reset(); this.weapon = weapon; }
    const policy = repeatFirePolicy(def); this.state = policy.state;
    if (policy.interval === null) return false;
    if (this.frame === frame) return this.value;
    this.frame = frame; this.value = now >= this.next;
    if (this.value) { this.next = now + policy.interval; this.pulses++; }
    return this.value;
  }
}
