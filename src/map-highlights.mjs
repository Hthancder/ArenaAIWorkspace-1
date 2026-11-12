import { ast, at, Disposables, entries, finite, methods, object, path, patchMethod, read, readMethod, walk } from './core.mjs';

// Exact original map markers, not a type-name guess for every map object.
export const MAP_MARKERS = Object.freeze({
  container_06: [14074643, 1], barn_01: [6959775, 1], stone_02: [1646367, 6],
  tree_03: [16777215, 8], tree_03sp: [255, 8], stone_04: [15406938, 6], stone_05: [15406938, 6],
  crate_03: [5342557, 1.8], bunker_storm_01: [6959775, 1.75], bunker_hydra_01: [10030546, 1.75],
  bunker_crossing_stairs_01b: [13571226, 2], bunker_crossing_stairs_01: [13571226, 2],
});
export function highlightMinimap(result, config) {
  if (!config.mapHighlights || !object(result) || !Array.isArray(read(result, 'shapes')) || typeof read(read(result, 'obj'), 'type') !== 'string') return result;
  const type = result.obj.type, marker = MAP_MARKERS[type], tree = config.smallerTrees && /^tree[_-]/.test(type);
  if (!marker && !tree) return result;
  const shapes = result.shapes.map(shape => {
    if (!object(shape) || !object(read(shape, 'collider')) || !finite(read(shape, 'color'))) return shape;
    const originalScale = finite(read(shape, 'scale')) ? shape.scale : 1;
    return { ...shape, ...(marker ? { color: marker[0], scale: marker[1] } : { scale: Math.min(originalScale, 1.8) }) };
  });
  // Never mutate result.shapes: they can be a shared MapObjectDefs.map.shapes array.
  return { ...result, zIdx: marker ? 999 : result.zIdx, shapes };
}
export function mapHighlightCompatible(map) {
  let returnsShape = false;
  const getter = ast(readMethod(map, 'getMinimapRender')), render = ast(readMethod(map, 'renderMap'));
  walk(getter, n => {
    if (n.type !== 'ReturnStatement' || n.argument?.type !== 'ObjectExpression') return;
    const names = n.argument.properties.map(p => p.key?.name ?? p.key?.value);
    if (['obj', 'shapes', 'zIdx'].every(key => names.includes(key))) returnsShape = true;
  });
  let consumesGetter = false, sorts = false;
  walk(render, n => {
    if (n.type !== 'CallExpression') return;
    const key = n.callee?.property?.name ?? n.callee?.property?.value;
    if (key === 'getMinimapRender') consumesGetter = true;
    if (key === 'sort') sorts = true;
  });
  return returnsShape && consumesGetter && sorts;
}
export function discoverMapRedraw(game, map) {
  const candidates = [];
  for (const [, fn] of methods(game)) walk(ast(fn), n => {
    if (n.type !== 'CallExpression' || n.arguments.length !== 2) return;
    const p = path(n.callee);
    if (p?.length !== 2 || p[1] !== 'renderMap' || at(game, [p[0]]) !== map) return;
    const renderer = at(game, path(n.arguments[0]) || []), canvasMode = at(game, path(n.arguments[1]) || []);
    if (object(renderer) && typeof canvasMode === 'boolean' && typeof renderer.render === 'function') candidates.push({ renderer, canvasMode });
  });
  if (!candidates.length || candidates.some(v => v.renderer !== candidates[0].renderer || v.canvasMode !== candidates[0].canvasMode)) return null;
  return candidates[0];
}
export class MapHighlights {
  constructor(config, report) { this.config = config; this.report = report; this.hooks = new Disposables(); this.map = null; this.enabled = false; this.dirty = false; this.signature = null; this.stats = { state: 'disabled', marked: 0, redraws: 0 }; }
  sync(game, map) {
    if (map !== this.map) {
      this.dispose(); this.map = map; this.signature = null;
      if (map && mapHighlightCompatible(map)) {
        const self = this;
        this.installed = patchMethod(map, 'getMinimapRender', original => function () {
          const result = Reflect.apply(original, this, arguments);
          if (!self.enabled) return result;
          const marked = highlightMinimap(result, self.config);
          if (marked !== result) { self.stats.marked++; self.dirty = true; }
          return marked;
        }, this.hooks);
      }
    }
    this.redrawArgs ||= map ? discoverMapRedraw(game, map) : null;
    this.available = !!(this.installed && this.redrawArgs);
    this.enabled = !!this.config.mapHighlights;
    if (!this.available || !read(map, 'mapLoaded')) { this.stats.state = this.enabled ? 'waiting-map-contract' : 'disabled'; return; }
    const signature = JSON.stringify([this.enabled, !!this.config.smallerTrees]);
    if (signature === this.signature) return;
    this.signature = signature;
    if (this.enabled || this.dirty) this.redraw();
    else this.stats.state = 'disabled';
  }
  redraw() {
    if (!this.map || !this.redrawArgs || !read(this.map, 'mapLoaded')) return;
    try {
      this.stats.marked = 0;
      Reflect.apply(readMethod(this.map, 'renderMap'), this.map, [this.redrawArgs.renderer, this.redrawArgs.canvasMode]);
      this.stats.redraws++; this.dirty = this.enabled;
      this.stats.state = this.enabled ? this.stats.marked ? 'redrawn-markers' : 'no-matching-map-objects' : 'disabled';
    } catch (error) { this.stats.state = 'redraw-error'; this.report('warning', `Map redraw: ${error.message}`); }
  }
  dispose() {
    this.enabled = false;
    if (this.dirty) this.redraw();
    this.hooks.clear(); this.map = null; this.installed = false; this.available = false; this.dirty = false; this.signature = null; this.redrawArgs = null;
  }
}
