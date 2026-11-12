import { at, clamp, finite, overlayPosition, project, read, sameLayer, teamRelations, vec } from './core.mjs';

export const ESP_PALETTE = Object.freeze({ enemy: '#ff6262', ally: '#56b6ff', unknown: '#b9bfc9', target: '#ffd166' });
export const colorValue = value => typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value);
export function safeLabel(value, limit = 24) {
  if (typeof value !== 'string') return '';
  return [...value.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]/g, '').replace(/\s+/g, ' ').trim()].slice(0, limit).join('');
}
function playerName(player) {
  const text = read(player, 'nameText');
  // PIXI Text 7.4.3 stores text in own _text; .text is a prototype accessor.
  // Do not invoke arbitrary getters or read unmasked playerInfo names as fallback.
  return safeLabel(read(text, 'text') ?? read(text, '_text'));
}
export function espColor(kind, config, selected = false) {
  const key = selected ? 'target' : kind;
  const custom = config[{ enemy: 'espEnemyColor', ally: 'espAllyColor', unknown: 'espUnknownColor', target: 'espTargetColor' }[key]];
  return colorValue(custom) ? custom : ESP_PALETTE[key] || ESP_PALETTE.unknown;
}
export function edgeIndicator(point, width, height, margin = 18) {
  if (!vec(point) || !finite(width) || !finite(height) || width <= margin * 2 || height <= margin * 2) return null;
  const cx = width / 2, cy = height / 2, dx = point.x - cx, dy = point.y - cy;
  // Zero components impose no limit.
  const tx = dx ? (cx - margin) / Math.abs(dx) : Infinity;
  const ty = dy ? (cy - margin) / Math.abs(dy) : Infinity;
  const t = Math.min(tx, ty);
  if (!finite(t)) return null;
  return { x: cx + dx * t, y: cy + dy * t, angle: Math.atan2(dy, dx) };
}
export function emptyEspStats(state = 'disabled') {
  return { state, considered: 0, drawn: 0, enemy: 0, ally: 0, unknown: 0, downed: 0, otherLayer: 0, offscreen: 0, labels: 0, labelsSkipped: 0, culled: 0 };
}
export function buildEspFrame(mapping, players, config, width, height, target = null) {
  const stats = emptyEspStats('ready'), rows = [];
  if (!mapping?.active || !mapping.schema || !mapping.camera) return { origin: null, rows, stats: { ...stats, state: 'waiting-mapping' } };
  const ownPos = overlayPosition(mapping.active, mapping), origin = project(mapping.camera, ownPos);
  if (!origin || !vec(ownPos)) return { origin: null, rows, stats: { ...stats, state: 'invalid-projection' } };
  const relations = teamRelations(mapping.barn, mapping.active.__id);
  const reject = () => { stats.culled++; };
  const maxDistance = finite(config.espMaxDistance) ? config.espMaxDistance : 200;
  for (const player of players.slice(0, 256)) {
    if (player === mapping.active) continue;
    stats.considered++;
    if (read(player, 'active') !== true || at(player, [mapping.schema.netKey, mapping.schema.deadKey])) { reject(); continue; }
    const relation = relations.classify(read(player, '__id'));
    if (relation.kind === 'self') { reject(); continue; }
    if ((relation.kind === 'ally' && config.espShowAllies === false) || (relation.kind === 'enemy' && config.espShowEnemies === false)
      || (relation.kind === 'unknown' && config.espShowUnknown === false)) { reject(); continue; }
    const downed = read(player, 'downed') === true;
    if (downed && config.espShowDowned === false) { reject(); continue; }
    const knownLayer = finite(read(player, 'layer')) && finite(read(mapping.active, 'layer'));
    const layerMatch = knownLayer && sameLayer(player.layer, mapping.active.layer);
    if (!layerMatch && config.espSameLayerOnly) { reject(); continue; }
    const pos = overlayPosition(player, mapping), screen = project(mapping.camera, pos);
    if (!screen || !vec(pos)) { reject(); continue; }
    const distance = Math.hypot(pos.x - ownPos.x, pos.y - ownPos.y);
    if (!finite(distance) || distance > maxDistance) { reject(); continue; }
    const offscreen = screen.x < 0 || screen.x > width || screen.y < 0 || screen.y > height;
    const edge = offscreen && config.espOffscreen ? edgeIndicator(screen, width, height) : null;
    if (offscreen && !edge) { reject(); continue; }
    rows.push({ player, relation: relation.kind, squad: relation.squad, selected: false, downed, offscreen, layerMatch, screen: edge || screen,
      color: espColor(relation.kind, config, false), dash: !layerMatch ? [7, 4] : relation.kind === 'unknown' ? [2, 4] : downed ? [3, 2] : [],
      distance, label: '' });
    stats.drawn++; stats[relation.kind]++; if (downed) stats.downed++; if (!layerMatch) stats.otherLayer++; if (offscreen) stats.offscreen++;
  }
  if (players.length > 256) stats.culled += players.length - 256;
  return { origin, rows, stats };
}

// Canvas coordinates remain CSS pixels. Cap DPR at 2 to bound the backing buffer.
export function prepareOverlay(canvas, ctx, width, height, devicePixelRatio = 1) {
  const dpr = finite(devicePixelRatio) ? clamp(devicePixelRatio, 1, 2) : 1;
  if (!finite(width) || !finite(height) || width <= 0 || height <= 0) return false;
  const w = Math.round(width * dpr), h = Math.round(height * dpr);
  if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
  if (canvas.style) { canvas.style.width = `${width}px`; canvas.style.height = `${height}px`; }
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return true;
}
function overlaps(a, b) { return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y; }
export function placeLabel(anchor, w, h, width, height, occupied) {
  if (w > width - 8 || h > height - 8) return null;
  for (const [dx, dy] of [[12, -h - 6], [12, 8], [-w - 12, -h - 6], [-w - 12, 8]]) {
    const box = { x: clamp(anchor.x + dx, 4, width - w - 4), y: clamp(anchor.y + dy, 4, height - h - 4), w, h };
    if (!occupied.some(other => overlaps(box, other))) { occupied.push(box); return box; }
  }
  return null;
}
export class EspRenderer {
  widths = new Map();
  reset() { this.widths.clear(); }
  measure(ctx, text) {
    const key = `${ctx.font}\0${text}`;
    if (!this.widths.has(key)) {
      if (this.widths.size >= 256) this.widths.delete(this.widths.keys().next().value);
      this.widths.set(key, ctx.measureText(text).width);
    }
    return this.widths.get(key);
  }
  draw(ctx, frame, config, width, height) {
    if (!frame.origin) return frame.stats;
    const occupied = [], fontSize = finite(config.espFontSize) ? config.espFontSize : 12;
    ctx.save();
    try {
      ctx.font = `${fontSize}px system-ui, sans-serif`; ctx.textBaseline = 'top'; ctx.textAlign = 'left';
      ctx.globalAlpha = (finite(config.espOpacity) ? config.espOpacity : 85) / 100;
      ctx.lineWidth = finite(config.espLineWidth) ? config.espLineWidth : 1.5;
      // Stable priority gives the current enemy target first choice of label space.
      const rows = [...frame.rows].sort((a, b) => Number(b.selected) - Number(a.selected) || a.distance - b.distance);
      for (const row of rows) {
        const p = row.screen;
        ctx.strokeStyle = row.color; ctx.fillStyle = row.color; ctx.setLineDash(row.dash);
        if (config.lines) {
          ctx.beginPath(); ctx.moveTo(frame.origin.x, frame.origin.y); ctx.lineTo(p.x, p.y); ctx.stroke();
        }
        if (row.offscreen) {
          const a = p.angle, cos = Math.cos(a), sin = Math.sin(a);
          ctx.beginPath(); ctx.moveTo(p.x + cos * 8, p.y + sin * 8);
          ctx.lineTo(p.x - cos * 6 - sin * 5, p.y - sin * 6 + cos * 5);
          ctx.lineTo(p.x - cos * 6 + sin * 5, p.y - sin * 6 - cos * 5); ctx.closePath(); ctx.stroke();
        } else if (config.espMarkers) {
          ctx.beginPath(); ctx.arc(p.x, p.y, row.selected ? 11 : 7, 0, Math.PI * 2); ctx.stroke();
        }

      }
      frame.stats.state = 'drawn';
      return frame.stats;
    } finally { ctx.restore(); }
  }
}
