import { at, read, teamRelations } from './core.mjs';

// Source Player.createPlayerNameText uses a distinct PIXI TextStyle per player.
// Trusted Text API only, never mutate text/name/font or multiply cyan by red tint.
export class NativeNames {
  records = new Map();
  release(text) {
    const r = this.records.get(text); if (!r) return;
    try {
      if (r.style.fill === r.applied) r.style.fill = r.raw;
      const d = Object.getOwnPropertyDescriptor(text, 'visible');
      if (d?.get === r.get && d?.set === r.set) Object.defineProperty(text, 'visible', { ...r.descriptor, value: r.visible });
    } catch { /* A destroyed/replaced native text is no longer writable. */ }
    this.records.delete(text);
  }
  clear() { for (const text of this.records.keys()) this.release(text); }
  sync(mapping, players, config) {
    const keep = new Set(), relations = teamRelations(mapping?.barn, mapping?.active?.__id);
    if (config.esp && config.nametags && mapping?.schema) for (const p of players) {
      const kind = relations.classify(p.__id).kind, text = read(p, 'nameText');
      if (!text || p === mapping.active || !p.active || at(p, [mapping.schema.netKey, mapping.schema.deadKey]) || !['ally', 'enemy'].includes(kind)) continue;
      if (kind === 'ally' && config.espShowAllies === false || kind === 'enemy' && config.espShowEnemies === false) continue;
      try {
        // _style is the audited PIXI7 backing field; plain own style supports fixtures.
        const style = read(text, 'style') || read(text, '_style');
        if (!style || style.fill === undefined) continue;
        let r = this.records.get(text);
        if (r && (r.style !== style || r.player !== p || r.id !== p.__id)) { this.release(text); r = null; }
        if (!r) {
          const d = Object.getOwnPropertyDescriptor(text, 'visible');
          if (!d || !('value' in d) || !d.configurable || !d.writable) continue;
          r = { player: p, id: p.__id, style, raw: style.fill, applied: null, visible: d.value, descriptor: d };
          r.get = () => true; r.set = value => { r.visible = value; };
          Object.defineProperty(text, 'visible', { configurable: true, enumerable: d.enumerable, get: r.get, set: r.set });
          this.records.set(text, r);
        }
        if (style.fill !== r.applied) r.raw = style.fill;
        r.applied = kind === 'ally' ? '#56b6ff' : '#ff6262';
        if (style.fill !== r.applied) style.fill = r.applied;
        keep.add(text);
      } catch { this.release(text); }
    }
    for (const text of this.records.keys()) if (!keep.has(text)) this.release(text);
  }
}
