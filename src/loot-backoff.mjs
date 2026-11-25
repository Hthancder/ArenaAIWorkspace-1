// Server pickupLoot enforces a 100 ms cooldown. Bound retries per pooled item
// and across changing targets; keep no references once they expire or on reset.
export class LootBackoff {
  constructor() { this.reset(); }
  reset() { this.items = new Map(); this.lastPulse = -Infinity; }
  attempt(entity, now) {
    if (!entity || !Number.isFinite(now)) return null;
    const previous = this.items.get(entity);
    const unchanged = previous && now >= previous.last && now - previous.last <= 10000
      && previous.id === entity.__id && previous.type === entity.type && previous.count === entity.count;
    if (now >= this.lastPulse && now - this.lastPulse < 120 || unchanged && now < previous.next) return null;
    for (const [key, record] of this.items) if (now < record.last || now - record.last > 10000) this.items.delete(key);
    const attempts = unchanged ? previous.attempts + 1 : 1;
    const record = { id: entity.__id, type: entity.type, count: entity.count, attempts, last: now,
      next: now + Math.min(2000, 350 * 2 ** Math.min(attempts - 1, 3)) };
    this.items.delete(entity);
    this.items.set(entity, record);
    if (this.items.size > 128) this.items.delete(this.items.keys().next().value);
    this.lastPulse = now;
    return record;
  }
}
