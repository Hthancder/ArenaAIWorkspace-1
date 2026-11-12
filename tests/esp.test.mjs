import test from 'node:test';
import assert from 'node:assert/strict';
import { teamRelations } from '../src/core.mjs';
import { buildEspFrame, colorValue, edgeIndicator, EspRenderer, placeLabel, prepareOverlay, safeLabel } from '../src/esp.mjs';
import { DEFAULTS, normalizeConfig } from '../src/menu.mjs';

function fixture() {
  const self = { __id: 1, active: true, layer: 0, p: { x: 0, y: 0 }, n: { dead: false, weapon: 'fists' } };
  const player = (id, x) => ({ __id: id, active: true, layer: 0, downed: false, p: { x, y: 0 }, n: { dead: false, weapon: 'mp5' }, nameText: { _text: `Player ${id}` } });
  const players = [self, player(2, 2), player(3, 4), player(4, 6), player(5, 8)];
  const barn = { teamInfo: { 10: { playerIds: [1, 2, 3] }, 20: { playerIds: [4] } }, groupInfo: { 100: { playerIds: [1, 2] }, 200: { playerIds: [3] }, 300: { playerIds: [4] } } };
  const camera = { camera: { p: { x: 0, y: 0 }, w: 800, h: 600, unit: 16, z: 1 }, posKey: 'p', widthKey: 'w', heightKey: 'h', scaleKeys: ['unit', 'z'] };
  const mapping = { active: self, barn, camera, schema: { posKey: 'p', netKey: 'n', deadKey: 'dead', weaponKey: 'weapon' } };
  return { mapping, players, config: { ...DEFAULTS, esp: true } };
}
function context() {
  const calls = [], stack = [];
  const ctx = { calls, font: '12px sans-serif', globalAlpha: 1, lineWidth: 1, dash: [], strokeStyle: '', fillStyle: '',
    save() { stack.push({ font: this.font, globalAlpha: this.globalAlpha, lineWidth: this.lineWidth, dash: this.dash, strokeStyle: this.strokeStyle, fillStyle: this.fillStyle }); },
    restore() { Object.assign(this, stack.pop()); },
    setLineDash(value) { this.dash = value; }, setTransform(...args) { calls.push(['transform', args]); },
    beginPath() {}, closePath() {}, moveTo(x, y) { calls.push(['moveTo', x, y]); }, lineTo(x, y) { calls.push(['lineTo', x, y]); },
    arc(x, y, r) { calls.push(['arc', x, y, r]); }, stroke() { calls.push(['stroke', this.strokeStyle, this.dash]); },
    fillRect(...args) { calls.push(['rect', this.fillStyle, ...args]); }, fillText(text, ...args) { calls.push(['text', text, this.fillStyle, ...args]); },
    measureText(text) { return { width: text.length * 5 }; },
  };
  return ctx;
}

test('relation indexing distinguishes squad, faction allies, enemies and missing membership', () => {
  const { mapping } = fixture(), relations = teamRelations(mapping.barn, 1);
  assert.equal(relations.ready, true);
  assert.deepEqual(relations.classify(1), { kind: 'self', squad: false });
  assert.deepEqual(relations.classify(2), { kind: 'ally', squad: true });
  assert.deepEqual(relations.classify(3), { kind: 'ally', squad: false });
  assert.deepEqual(relations.classify(4), { kind: 'enemy', squad: false });
  assert.deepEqual(relations.classify(5), { kind: 'unknown', squad: false });
});

test('ambiguous/missing team data never becomes enemy; group alone is not team evidence', () => {
  const { mapping } = fixture();
  mapping.barn.teamInfo[20].playerIds.push(2);
  mapping.barn.groupInfo[100].playerIds.push(4);
  let r = teamRelations(mapping.barn, 1);
  assert.equal(r.classify(2).kind, 'unknown'); assert.equal(r.classify(4).kind, 'enemy'); assert.equal(r.classify(4).squad, false);
  delete mapping.barn.teamInfo[10]; r = teamRelations(mapping.barn, 1);
  assert.equal(r.ready, false); assert.equal(r.classify(4).kind, 'unknown');
});

test('membership handles team zero, duplicate ids within one team, throwing accessors and scan limits', () => {
  const barn = { teamInfo: { 0: { playerIds: [0, 1, 1] }, 1: { playerIds: [2] } } };
  Object.defineProperty(barn.teamInfo, 'evil', { get() { throw Error('do not execute'); } });
  assert.equal(teamRelations(barn, 0).classify(1).kind, 'ally');
  assert.equal(teamRelations(barn, 0).classify(2).kind, 'enemy');
  barn.teamInfo[3] = { playerIds: Array(8193).fill(3) };
  assert.equal(teamRelations(barn, 0).classify(2).kind, 'unknown');
});

test('a new relation pass observes team recomputation and reused player ids without stale colors', () => {
  const { mapping } = fixture(), previous = teamRelations(mapping.barn, 1);
  assert.equal(previous.classify(4).kind, 'enemy');
  mapping.barn.teamInfo = { 99: { playerIds: [1, 4] } };
  assert.equal(teamRelations(mapping.barn, 1).classify(4).kind, 'ally');
  assert.equal(teamRelations(mapping.barn, 1).classify(2).kind, 'unknown');
});

test('ESP labels, colors and counts preserve team identity for other layers and downed players', () => {
  const { mapping, players, config } = fixture(); players[3].layer = 1; players[3].downed = true;
  const frame = buildEspFrame(mapping, players, config, 800, 600);
  assert.deepEqual(frame.rows.map(r => r.relation), ['ally', 'ally', 'enemy', 'unknown']);
  assert.match(frame.rows[0].label, /^SQUAD/); assert.match(frame.rows[1].label, /^ALLY/);
  assert.match(frame.rows[2].label, /^ENEMY.*DOWNED.*OTHER LAYER/);
  assert.equal(frame.rows[2].color, config.espEnemyColor); assert.deepEqual(frame.rows[2].dash, [7, 4]);
  assert.match(frame.rows[3].label, /^UNKNOWN/); assert.equal(frame.rows[3].color, config.espUnknownColor);
  assert.deepEqual(frame.rows[3].dash, [2, 4]);
  assert.equal(frame.stats.ally, 2); assert.equal(frame.stats.enemy, 1); assert.equal(frame.stats.unknown, 1);
});

test('ESP filters ally/enemy/unknown, dead/inactive/downed, layer and max range consistently', () => {
  const { mapping, players, config } = fixture();
  config.espShowAllies = false; config.espShowUnknown = false;
  assert.deepEqual(buildEspFrame(mapping, players, config, 800, 600).rows.map(r => r.player.__id), [4]);
  config.espShowEnemies = false; assert.equal(buildEspFrame(mapping, players, config, 800, 600).rows.length, 0);
  Object.assign(config, { espShowAllies: true, espShowEnemies: true, espShowUnknown: true, espShowDowned: false });
  players[1].n.dead = true; players[2].active = false; players[3].downed = true;
  assert.equal(buildEspFrame(mapping, players, config, 800, 600).rows.length, 1);
  config.espMaxDistance = 7; assert.equal(buildEspFrame(mapping, players, config, 800, 600).rows.length, 0);
  config.espMaxDistance = 200; config.espSameLayerOnly = true; players[4].layer = 1;
  assert.equal(buildEspFrame(mapping, players, config, 800, 600).rows.length, 0);
});

test('target highlight applies to enemies only and does not reveal unknown/ally as enemy', () => {
  const { mapping, players, config } = fixture();
  let frame = buildEspFrame(mapping, players, config, 800, 600, players[3]);
  assert.equal(frame.rows[2].selected, true); assert.equal(frame.rows[2].color, config.espTargetColor);
  frame = buildEspFrame(mapping, players, config, 800, 600, players[1]); assert.equal(frame.rows[0].selected, false);
  frame = buildEspFrame(mapping, players, config, 800, 600, players[4]); assert.equal(frame.rows[3].selected, false);
});

test('labels sanitize control/bidi characters, bound Unicode length and never invoke text getters', () => {
  assert.equal(safeLabel(' A\u202e\nB\u0000 '), 'AB');
  assert.equal([...safeLabel('🙂'.repeat(60))].length, 24);
  const { mapping, players, config } = fixture(); config.espWeapons = true;
  Object.defineProperty(players[3].nameText, 'text', { get() { throw Error('unsafe getter'); } });
  players[3].nameText._text = 'masked name'; players[3].n.weapon = 'mp5\u202e\n';
  const row = buildEspFrame(mapping, players, config, 800, 600).rows[2];
  assert.match(row.label, /masked name/); assert.match(row.label, /6 wu.*mp5$/);
  config.nametags = false; config.espWeapons = false; config.espDistance = false;
  assert.equal(buildEspFrame(mapping, players, config, 800, 600).rows[2].label, 'ENEMY');
});

test('off-screen arrows cover horizontal/vertical directions and only opted-in received entities', () => {
  assert.deepEqual(edgeIndicator({ x: 1000, y: 300 }, 800, 600), { x: 782, y: 300, angle: 0 });
  const vertical = edgeIndicator({ x: 400, y: -100 }, 800, 600); assert.equal(vertical.x, 400); assert.equal(vertical.y, 18);
  assert.equal(edgeIndicator({ x: 400, y: 300 }, 800, 600), null);
  assert.equal(edgeIndicator({ x: NaN, y: 300 }, 800, 600), null);
  assert.equal(edgeIndicator({ x: 50, y: 50 }, 20, 20), null);
  const { mapping, players, config } = fixture(); players[3].p.x = 40;
  assert.equal(buildEspFrame(mapping, [players[0], players[3]], config, 800, 600).rows.length, 0);
  config.espOffscreen = true;
  const frame = buildEspFrame(mapping, [players[0], players[3]], config, 800, 600);
  assert.equal(frame.rows[0].offscreen, true); assert.equal(frame.stats.offscreen, 1);
});

test('label placement clamps to viewport, avoids occupied rectangles and skips labels that cannot fit', () => {
  const used = [], corner = placeLabel({ x: 795, y: 5 }, 120, 20, 800, 600, used);
  assert.ok(corner.x >= 4 && corner.x + corner.w <= 796 && corner.y >= 4);
  assert.equal(placeLabel({ x: 795, y: 5 }, 120, 20, 800, 600, used), null);
  const a = placeLabel({ x: 400, y: 300 }, 120, 20, 800, 600, used);
  const b = placeLabel({ x: 400, y: 300 }, 120, 20, 800, 600, used);
  assert.ok(a); assert.ok(b);
  assert.ok(a.y + a.h <= b.y || b.y + b.h <= a.y || a.x + a.w <= b.x || b.x + b.w <= a.x);
  assert.equal(placeLabel({ x: 0, y: 0 }, 900, 20, 800, 600, used), null);
});

test('DPR backing size is capped while CSS and drawing coordinates remain unchanged', () => {
  const canvas = { width: 1, height: 1, style: {} }, ctx = context();
  assert.equal(prepareOverlay(canvas, ctx, 800, 600, 3), true);
  assert.equal(canvas.width, 1600); assert.equal(canvas.height, 1200); assert.equal(canvas.style.width, '800px');
  assert.deepEqual(ctx.calls[0], ['transform', [2, 0, 0, 2, 0, 0]]);
  assert.equal(prepareOverlay(canvas, ctx, NaN, 600), false);
});

test('renderer uses relation colors/patterns, labels/legend and restores context state', () => {
  const { mapping, players, config } = fixture(), ctx = context(), renderer = new EspRenderer();
  players[3].layer = 1;
  const frame = buildEspFrame(mapping, players, config, 800, 600); renderer.draw(ctx, frame, config, 800, 600);
  assert.ok(ctx.calls.some(c => c[0] === 'stroke' && c[1] === config.espEnemyColor && c[2].join() === '7,4'));
  assert.ok(ctx.calls.some(c => c[0] === 'stroke' && c[1] === config.espUnknownColor && c[2].join() === '2,4'));
  assert.ok(ctx.calls.some(c => c[0] === 'text' && c[1].startsWith('ENEMY')));
  assert.equal(frame.stats.state, 'drawn'); assert.ok(frame.stats.labels > 0);
  assert.equal(ctx.globalAlpha, 1); assert.equal(ctx.lineWidth, 1); assert.deepEqual(ctx.dash, []);
});

test('text measurement cache is bounded, resets, and context restores even on renderer errors', () => {
  const renderer = new EspRenderer(), ctx = context();
  for (let i = 0; i < 400; i++) renderer.measure(ctx, String(i));
  assert.equal(renderer.widths.size, 256); renderer.reset(); assert.equal(renderer.widths.size, 0);
  const { mapping, players, config } = fixture(); ctx.fillText = () => { throw Error('render failed'); };
  assert.throws(() => renderer.draw(ctx, buildEspFrame(mapping, players, config, 800, 600), config, 800, 600));
  assert.equal(ctx.globalAlpha, 1); assert.equal(ctx.lineWidth, 1);
});

test('new ESP configuration validates colors and limits without enabling gameplay features by migration', () => {
  const c = normalizeConfig({ esp: false, espEnemyColor: '#ABCDEF', espAllyColor: 'red', espUnknownColor: '#123', espMaxDistance: Infinity, espLineWidth: 100, espFontSize: -2, espOpacity: 0 });
  assert.equal(c.espEnemyColor, '#abcdef'); assert.equal(c.espAllyColor, DEFAULTS.espAllyColor); assert.equal(c.espUnknownColor, DEFAULTS.espUnknownColor);
  assert.equal(c.espMaxDistance, 200); assert.equal(c.espLineWidth, 3); assert.equal(c.espFontSize, 10); assert.equal(c.espOpacity, 10);
  assert.equal(c.esp, false); assert.equal(c.aim, false); assert.equal(colorValue('#123456'), true); assert.equal(colorValue('url(test)'), false);
});

test('partial mappings and duplicate self identities cannot produce spurious enemy rows or NaN counts', () => {
  const { mapping, players, config } = fixture();
  assert.equal(buildEspFrame({}, players, config, 800, 600).stats.state, 'waiting-mapping');
  const clone = { ...players[1], __id: 1 };
  const frame = buildEspFrame(mapping, [players[0], clone], config, 800, 600);
  assert.equal(frame.rows.length, 0); assert.equal(frame.stats.culled, 1);
  assert.ok(Object.values(frame.stats).every(v => typeof v !== 'number' || Number.isFinite(v)));
});
