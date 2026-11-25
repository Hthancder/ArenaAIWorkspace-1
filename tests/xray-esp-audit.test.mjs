import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { DEFAULTS, normalizeConfig } from '../src/menu.mjs';
import { fadeObjectKind } from '../src/xray.mjs';
import { buildEspFrame } from '../src/esp.mjs';
import { Features } from '../src/features.mjs';

class Camera {
  constructor() { this.p = { x: 0, y: 0 }; this.unit = 16, this.zoom = 1; this.w = 800; this.h = 600; }
}
test('fadeObjectKind: regex fallback covers brush_* and latest def flags are authoritative when the registry is present', () => {
  // No registry captured: regex fallback, now including latest brush_* bushes.
  assert.equal(fadeObjectKind('tree_03'), 'vegetation');
  assert.equal(fadeObjectKind('bush_01'), 'vegetation');
  assert.equal(fadeObjectKind('brush_01sv'), 'vegetation');
  assert.equal(fadeObjectKind('brush_02sv'), 'vegetation');
  assert.equal(fadeObjectKind('table_01'), 'furniture');
  assert.equal(fadeObjectKind('table_09'), 'furniture');
  assert.equal(fadeObjectKind('stairs_03'), 'furniture');
  assert.equal(fadeObjectKind('stone_01'), null);
  assert.equal(fadeObjectKind('barrel_01'), null);
  assert.equal(fadeObjectKind(''), null);
  assert.equal(fadeObjectKind(undefined), null);
  // Registry captured: def flags decide, even for renamed/changed type names.
  const defs = {
    brush_01sv: { type: 'obstacle', isBush: true },
    tree_02: { type: 'obstacle', isTree: true },
    tree_future_01: { type: 'obstacle', isTree: true },
    table_02: { type: 'obstacle', category: 'furniture' },
    crate_01: { type: 'obstacle' },
    tree_fake: { type: 'obstacle' }, // known def without flags must win over the regex
  };
  assert.equal(fadeObjectKind('brush_01sv', defs), 'vegetation');
  assert.equal(fadeObjectKind('tree_02', defs), 'vegetation');
  assert.equal(fadeObjectKind('tree_future_01', defs), 'vegetation');
  assert.equal(fadeObjectKind('table_02', defs), 'furniture');
  assert.equal(fadeObjectKind('crate_01', defs), null);
  // A declared-but-flagless def is authoritative: do not fade by name guess.
  assert.equal(fadeObjectKind('tree_fake', defs), null);
});

function engineFixture() {
  const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://survev.io/', pretendToBeVisual: true, runScripts: 'outside-only' });
  const input = { mousePos: { x: 440, y: 300 }, mouseButtons: { 0: false }, mouseButtonsOld: { 0: false }, keys: {}, keysOld: {}, flush() {} };
  const ticker = { add() {}, remove() {} };
  const game = {
    initialized: true, connected: true, camera: new Camera(),
    hero: { __id: 1, __type: 1, active: true, layer: 0, container: {}, nameText: { visible: false, style: { fill: 65535 } }, p: { x: 0, y: 0 }, d: { x: 1, y: 0 }, n: { weapon: 'mp5', dead: false, downed: false }, l: { zoom: 48, index: 0, weapons: [] } },
    barn: { playerIds: [1], teamInfo: {}, playerPool: { list: [] } },
    ui: { spectating: false, setSpectating() {} }, timeout: 1,
    touch: {}, binds: { isBindDown() { return false; }, isBindPressed() { return false; } },
    map: null, sent: [],
  };
  const app = { game, input, pixi: { ticker, stage: {} } };
  const config = { ...DEFAULTS, xray: true, esp: false };
  const engine = new Features(dom.window, app, config, () => {}, null);
  engine.mapping = {
    active: game.hero, barn: game.barn, players: () => [],
    camera: { camera: game.camera, posKey: 'p', widthKey: 'w', heightKey: 'h', scaleKeys: ['unit', 'zoom'] },
    schema: { posKey: 'p', netKey: 'n', deadKey: 'dead', weaponKey: 'weapon' },
    map: game.map, ui: game.ui,
  };
  return { dom, app, engine, config };
}

test('X-Ray fades brush_* obstacles via regex fallback and latest def flags via the captured registry', () => {
  const { dom, app, engine, config } = engineFixture();
  const brush = { active: true, type: 'brush_02sv', sprite: { alpha: 1 } };
  const shrub = { active: true, type: 'shrub_09', sprite: { alpha: 1 } };
  const tree = { active: true, type: 'tree_01', sprite: { alpha: 1 } };
  const rock = { active: true, type: 'stone_01', sprite: { alpha: 1 } };
  app.game.map = { mapTexture: null, getGroundSurface() {}, pool: { list: [brush, shrub, tree, rock] } };
  engine.mapping.map = app.game.map;
  engine.lastVisual = -Infinity; engine.lastScan = -Infinity;
  engine.post();
  assert.equal(brush.sprite.alpha, .5, 'brush_02sv (isBush in latest defs) fades without a registry');
  assert.equal(tree.sprite.alpha, .5);
  assert.equal(rock.sprite.alpha, 1, 'non-vegetation stays untouched');
  assert.equal(shrub.sprite.alpha, 1, 'unknown type without def flags stays untouched before the registry is captured');
  engine.dispose();
  // With the registry captured, a renamed isBush def fades too.
  const again = engineFixture();
  const defs = { shrub_09: { type: 'obstacle', isBush: true }, tree_01: { type: 'obstacle', isTree: true }, stone_01: { type: 'obstacle' } };
  const brush2 = { active: true, type: 'brush_02sv', sprite: { alpha: 1 } };
  const shrub2 = { active: true, type: 'shrub_09', sprite: { alpha: 1 } };
  const rock2 = { active: true, type: 'stone_01', sprite: { alpha: 1 } };
  again.app.game.map = { mapTexture: null, getGroundSurface() {}, pool: { list: [brush2, shrub2, rock2] } };
  again.engine.mapping.map = again.app.game.map;
  again.engine.mapDefinitions = defs;
  again.engine.lastVisual = -Infinity; again.engine.lastScan = -Infinity;
  again.engine.post();
  assert.equal(shrub2.sprite.alpha, .5, 'registry-driven isBush classification fades renamed vegetation');
  assert.equal(brush2.sprite.alpha, .5);
  assert.equal(rock2.sprite.alpha, 1);
  assert.ok(again.engine.stats.xray.vegetation >= 2);
  again.engine.dispose();
  dom.window.close(); again.dom.window.close();
});

test('ESP default range is the slider maximum, so distant replicated players are never culled client-side', () => {
  assert.equal(DEFAULTS.espMaxDistance, 500);
  assert.equal(normalizeConfig({}).espMaxDistance, 500);
  const self = { __id: 1, active: true, layer: 0, p: { x: 0, y: 0 }, n: { dead: false } };
  const far = { __id: 2, active: true, layer: 0, downed: false, p: { x: 250, y: 0 }, n: { dead: false }, nameText: { _text: 'Far' } };
  const barn = { teamInfo: { 10: { playerIds: [1] }, 20: { playerIds: [2] } } };
  const camera = { camera: { p: { x: 0, y: 0 }, w: 800, h: 600, unit: .5, z: 1 }, posKey: 'p', widthKey: 'w', heightKey: 'h', scaleKeys: ['unit', 'z'] };
  const mapping = { active: self, barn, camera, schema: { posKey: 'p', netKey: 'n', deadKey: 'dead' } };
  const withDefault = buildEspFrame(mapping, [self, far], { ...DEFAULTS }, 800, 600);
  assert.equal(withDefault.stats.culled, 0);
  assert.equal(withDefault.rows.length, 1);
  const legacyFallback = buildEspFrame(mapping, [self, far], { esp: true, espShowEnemies: true, espMaxDistance: undefined }, 800, 600);
  assert.equal(legacyFallback.stats.culled, 0, 'missing espMaxDistance falls back to the slider maximum, not the old 200');
});

test('X-Ray traverses source-shaped pools past 2048, tracks building ceilings and releases recycled objects', () => {
  const { dom, app, engine, config } = engineFixture();
  const filler = Array.from({ length: 2050 }, () => ({ active: false, type: 'stone_01', sprite: { alpha: 1 } }));
  const bush = { active: true, type: 'new_bush', isBush: true, sprite: { alpha: 1 } };
  const floor = { isCeiling: false, sprite: { visible: true } };
  const roof = { isCeiling: true, sprite: { visible: true } };
  const building = { active: true, type: 'house_01', imgs: [floor, roof] };
  app.game.map = { mapTexture: null, getGroundSurface() {}, m_obstaclePool: { m_pool: [...filler, bush] }, m_buildingPool: { m_pool: [building] } };
  engine.mapping.map = app.game.map;
  engine.lastVisual = engine.lastScan = -Infinity; engine.post();
  assert.equal(bush.sprite.alpha, .5);
  assert.equal(roof.sprite.visible, false);
  assert.equal(floor.sprite.visible, true);
  // Pool reuse between scans must release stale overrides immediately.
  bush.type = 'stone_01'; bush.isBush = false;
  building.active = false;
  engine.lastVisual = -Infinity; engine.post();
  assert.equal(bush.sprite.alpha, 1);
  assert.equal(roof.sprite.visible, true);
  building.active = true;
  const newRoof = { isCeiling: true, sprite: { visible: true } };
  building.imgs = [floor, newRoof];
  engine.lastVisual = engine.lastScan = -Infinity; engine.post();
  assert.equal(newRoof.sprite.visible, false);
  config.xray = false;
  engine.lastVisual = -Infinity; engine.post();
  assert.equal(newRoof.sprite.visible, true);
  engine.dispose(); dom.window.close();
});
