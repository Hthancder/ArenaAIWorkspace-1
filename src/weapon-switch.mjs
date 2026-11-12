// Queue at most one native equip per frame; never send a packet out of band or
// pretend that a weapon's server-side cooldown has been reset by switching.
export class WeaponSwitch {
  constructor() { this.reset(); }
  reset() { this.last = null; this.pending = null; this.next = 0; this.state = 'disabled'; }
  sample({ enabled, ready, slot, weapons, definitions, held, oneGun, now }) {
    if (!enabled || !ready) { this.reset(); this.state = enabled ? 'waiting-contract' : 'disabled'; return null; }
    const eligible = weapon => weapon?.type && definitions?.[weapon.type]?.type === 'gun' && ['single', 'burst'].includes(definitions[weapon.type].fireMode);
    const current = weapons?.[slot];
    if (this.pending) {
      const p = this.pending;
      if (now > p.expires || !held || !weapons?.[p.returnSlot] || weapons[p.returnSlot].type !== p.type || ![p.via, p.returnSlot].includes(slot)) this.pending = null;
      else if (slot === p.via && now >= p.at) {
        this.pending = null; this.last = null; this.state = 'return-requested'; return p.returnSlot;
      } else { this.state = 'waiting-equip'; return null; }
    }
    if (![0, 1].includes(slot) || !eligible(current)) { this.last = null; this.state = 'unsupported-weapon'; return null; }
    const prior = this.last;
    this.last = { slot, type: current.type, ammo: current.ammo };
    const shot = prior?.slot === slot && prior.type === current.type && (current.ammo < prior.ammo || held && prior.ammo === 0 && current.ammo > 0);
    this.state = 'watching-ammo';
    if (!held || !shot || now < this.next) return null;
    const other = weapons[1 - slot];
    if (!oneGun && eligible(other) && other.ammo > 0) {
      this.next = now + 200; this.state = 'other-gun-requested'; return 1 - slot;
    }
    const via = other?.type ? 1 - slot : weapons[2]?.type ? 2 : null;
    if (via === null) { this.state = 'no-secondary-slot'; return null; }
    this.pending = { via, returnSlot: slot, type: current.type, at: now + 100, expires: now + 1000 };
    this.next = now + 250; this.state = 'cycle-requested'; return via;
  }
}
