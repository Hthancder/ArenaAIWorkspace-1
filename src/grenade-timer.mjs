import { finite } from './core.mjs';

// Advisory timer based on a forwarded local input edge, NOT server cook state.
// Never synthesize input or restart from a repeated hold packet.
export class GrenadeTimer {
  constructor() { this.reset(); }
  reset() { this.active = null; }
  valid({ enabled, ready, owner, slot, type, activeType, definitions }) {
    const def = definitions?.[type];
    return !!(enabled && ready && owner && slot === 3 && typeof type === 'string' && type === activeType
      && def?.type === 'throwable' && def.cookable === true && finite(def.fuseTime) && def.fuseTime > 0 && def.fuseTime <= 30);
  }
  validate(context) {
    if (this.active && (!this.valid(context) || this.active.owner !== context.owner || this.active.type !== context.type
      || this.active.fuse !== context.definitions[context.type].fuseTime)) this.reset();
  }
  forwarded(context, input, now, switchesWeapon = false) {
    this.validate(context);
    if (!this.valid(context) || switchesWeapon || !input?.shootHold || !finite(now)) { this.reset(); return; }
    if (!this.active && input.shootStart === true) this.active = { owner: context.owner, type: context.type, fuse: context.definitions[context.type].fuseTime, start: now };
  }
  sample(context, now) {
    this.validate(context);
    if (!this.active || !finite(now)) return null;
    if (now < this.active.start) { this.reset(); return null; }
    return { seconds: Math.max(0, this.active.fuse - (now - this.active.start) / 1000) };
  }
}

export function drawGrenadeTimer(ctx, screen, seconds) {
  if (!ctx || !screen || !finite(screen.x) || !finite(screen.y) || !finite(seconds)) return;
  const value = Math.max(0, seconds);
  ctx.save(); ctx.font = 'bold 14px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  const label = `Bom ~${value.toFixed(1)}s`;
  ctx.fillStyle = 'rgba(0,0,0,.75)'; ctx.fillRect(screen.x - 61, screen.y - 90, 122, 40);
  ctx.fillStyle = value <= 1 ? '#ff6b6b' : '#fff0b0'; ctx.fillText(label, screen.x, screen.y - 78);
  ctx.font = '11px system-ui, sans-serif'; ctx.fillStyle = '#ffffff'; ctx.fillText('chưa xác nhận', screen.x, screen.y - 62);
  ctx.restore();
}
