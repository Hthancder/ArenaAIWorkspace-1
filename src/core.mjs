import { parse } from 'acorn';

// This module never evaluates source text or calls a discovered game method.
const nativeSource = Function.prototype.toString;
export const object = v => v !== null && typeof v === 'object';
export const finite = v => typeof v === 'number' && Number.isFinite(v);
export const vec = v => object(v) && finite(read(v, 'x')) && finite(read(v, 'y'));
export const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
export const point = v => ({ x: read(v, 'x'), y: read(v, 'y') });
export const sameLayer = (a, b) => finite(a) && finite(b) && ((a & 1) === (b & 1) || !!((a & 2) && (b & 2)));

// Ignore getters during graph discovery. Accessors are only read by trusted feature code.
export function entries(o) {
  if (!object(o) && typeof o !== 'function') return [];
  try {
    return Object.entries(Object.getOwnPropertyDescriptors(o))
      .filter(([, d]) => 'value' in d).map(([k, d]) => [k, d.value]);
  } catch { return []; }
}
export function read(o, k) {
  if ((!object(o) && typeof o !== 'function') || k === null || k === undefined) return undefined;
  try { const d = Object.getOwnPropertyDescriptor(o, k); return d && 'value' in d ? d.value : undefined; }
  catch { return undefined; }
}
export function at(o, path) { for (const k of path) o = read(o, k); return o; }
export function unique(xs) { const values = [...new Set(xs)]; return values.length === 1 ? values[0] : null; }
export function methods(o) {
  const found = new Map();
  try {
    for (let i = 0; o && i < 4 && o !== Object.prototype; o = Object.getPrototypeOf(o), i++) {
      for (const [k, v] of entries(o)) if (!found.has(k) && typeof v === 'function' && k !== 'constructor') found.set(k, v);
    }
  } catch { /* A hostile proxy is not a compatible object. */ }
  return [...found];
}
const astCache = new WeakMap();
export function ast(fn) {
  if (typeof fn !== 'function') return null;
  if (astCache.has(fn)) return astCache.get(fn);
  let tree = null;
  try {
    const code = Reflect.apply(nativeSource, fn, []);
    try { tree = parse(`(${code})`, { ecmaVersion: 'latest' }).body[0].expression; }
    catch { tree = parse(`({${code}})`, { ecmaVersion: 'latest' }).body[0].expression.properties[0].value; }
  } catch { /* Native/unsupported source => capability unavailable. */ }
  astCache.set(fn, tree);
  return tree;
}
export function walk(node, visit) {
  if (!node || typeof node !== 'object') return;
  if (typeof node.type === 'string') visit(node);
  for (const [k, v] of Object.entries(node)) {
    if (k === 'start' || k === 'end') continue;
    if (Array.isArray(v)) v.forEach(child => walk(child, visit));
    else if (v && typeof v === 'object') walk(v, visit);
  }
}
function prop(node) {
  return node?.type === 'Identifier' ? node.name : node?.type === 'Literal' && typeof node.value === 'string' ? node.value : null;
}
export function path(node, root = 'this') {
  if (node?.type === 'ChainExpression') return path(node.expression, root);
  if (root === 'this' && node?.type === 'ThisExpression') return [];
  if (node?.type === 'Identifier' && node.name === root) return [];
  if (node?.type !== 'MemberExpression') return null;
  const base = path(node.object, root);
  const key = node.computed ? (node.property.type === 'Literal' ? prop(node.property) : null) : prop(node.property);
  return base && key !== null ? [...base, key] : null;
}
export function paths(tree, root = 'this') {
  const result = new Map();
  walk(tree, n => { const p = path(n, root); if (p?.length) result.set(JSON.stringify(p), p); });
  return [...result.values()];
}
function memberName(node) { return node?.type === 'MemberExpression' ? (node.computed ? node.property.value : node.property.name) : null; }
function calls(tree, name) {
  const found = [];
  walk(tree, n => { if (n.type === 'CallExpression' && memberName(n.callee) === name) found.push(n); });
  return found;
}
export function isPlayer(p) {
  return object(p) && finite(read(p, '__id')) && typeof read(p, 'active') === 'boolean'
    && object(read(p, 'container')) && object(read(p, 'nameText'));
}
export function isApplication(app) {
  const pixi = read(app, 'pixi');
  if (!object(app) || !object(read(app, 'game')) || !object(read(pixi, 'stage'))) return false;
  const ticker = read(pixi, 'ticker') || read(pixi, '_ticker');
  // PIXI exposes ticker through a prototype getter: narrowly permit it only here.
  let resolved = ticker;
  try { resolved ||= pixi?.ticker; } catch { return false; }
  return object(app) && object(read(app, 'game')) && object(read(pixi, 'stage'))
    && object(resolved) && typeof resolved.add === 'function' && typeof resolved.remove === 'function';
}
export function discoverSender(game) {
  return unique(methods(game).filter(([, fn]) => {
    const tree = ast(fn);
    // Semantic serialization boundary, NOT function.length or property count.
    return calls(tree, 'serializeMsg').length === 1;
  }).map(([k]) => k));
}
export function discoverCamera(game) {
  const candidates = [];
  for (const [gameKey, camera] of entries(game)) {
    if (!object(camera) || Array.isArray(camera) || isPlayer(camera)) continue;
    const values = entries(camera).map(([, value]) => value);
    if (!values.some(vec) || !values.some(finite)) continue;
    for (const [method, fn] of methods(camera)) {
      const tree = ast(fn), param = tree?.params?.[0]?.name;
      if (!param) continue;
      walk(tree?.body, node => {
        if (node.type !== 'ReturnStatement' || node.argument?.type !== 'ObjectExpression') return;
        const xp = node.argument.properties.find(p => prop(p.key) === 'x')?.value;
        const yp = node.argument.properties.find(p => prop(p.key) === 'y')?.value;
        if (!xp || !yp) return;
        // Forward projection: x/y of the argument must be present, inverse projection divides.
        const px = paths(xp, param), py = paths(yp, param);
        if (!px.some(p => p.length === 1 && p[0] === 'x') || !py.some(p => p.length === 1 && p[0] === 'y')) return;
        let multiplication = false, division = false;
        walk(node.argument, n => {
          if (n.type === 'BinaryExpression' && n.operator === '*') multiplication = true;
          if (n.type === 'BinaryExpression' && n.operator === '/') division = true;
        });
        if (!multiplication || division) return;
        const self = paths(node.argument);
        const posKey = unique(self.filter(p => p.length === 2 && ['x', 'y'].includes(p[1]) && vec(read(camera, p[0]))).map(p => p[0]));
        const widthKey = unique(paths(xp).filter(p => p.length === 1 && finite(at(camera, p))).map(p => p[0]));
        const heightKey = unique(paths(yp).filter(p => p.length === 1 && finite(at(camera, p))).map(p => p[0]));
        const scaleCalls = [];
        walk(node.argument, n => {
          if (n.type === 'CallExpression') {
            const p = path(n.callee);
            if (p?.length === 1 && typeof readMethod(camera, p[0]) === 'function') scaleCalls.push(p[0]);
          }
        });
        const scaleMethod = unique(scaleCalls);
        if (!posKey || !widthKey || !heightKey || !scaleMethod) return;
        const isPath = (node, keys, root = 'this') => JSON.stringify(path(node, root)) === JSON.stringify(keys);
        const product = (node, left, right) => node?.type === 'BinaryExpression' && node.operator === '*'
          && ((left(node.left) && right(node.right)) || (right(node.left) && left(node.right)));
        const half = node => node?.type === 'Literal' && node.value === .5;
        const scaledDelta = (node, axis) => product(node,
          n => n?.type === 'BinaryExpression' && n.operator === '-'
            && isPath(n.left, [axis], param) && isPath(n.right, [posKey, axis]),
          n => n?.type === 'CallExpression' && n.arguments.length === 0 && isPath(n.callee, [scaleMethod]));
        const dimension = (node, key) => product(node, n => isPath(n, [key]), half);
        if (!(xp.type === 'BinaryExpression' && xp.operator === '+' && dimension(xp.left, widthKey) && scaledDelta(xp.right, 'x')
          && yp.type === 'BinaryExpression' && yp.operator === '-' && dimension(yp.left, heightKey) && scaledDelta(yp.right, 'y'))) return;
        const scaleTree = ast(readMethod(camera, scaleMethod));
        const scaleKeys = paths(scaleTree).filter(p => p.length === 1 && finite(at(camera, p))).map(p => p[0]);
        if (new Set(scaleKeys).size !== 2) return;
        let zoomKey = null;
        // Named adapter is allowed only when validated against the projection's scale expression.
        if (scaleKeys.includes('m_zoom')) zoomKey = 'm_zoom';
        // Obfuscated adapter: zoom assignment references the same zoom field and a distinct target.
        for (const [, gameFn] of methods(game)) {
          walk(ast(gameFn), n => {
            if (n.type !== 'AssignmentExpression' || n.right?.type !== 'CallExpression') return;
            const lhs = path(n.left);
            if (lhs?.length !== 2 || lhs[0] !== gameKey || !scaleKeys.includes(lhs[1])) return;
            const rhs = paths(n.right).filter(p => p[0] === gameKey && p.length === 2);
            if (rhs.some(p => p[1] === lhs[1]) && rhs.some(p => p[1] !== lhs[1] && finite(at(game, p)))) zoomKey = lhs[1];
          });
        }
        candidates.push({ camera, gameKey, method, posKey, widthKey, heightKey, scaleMethod, scaleKeys, zoomKey });
      });
    }
  }
  return candidates.length === 1 ? candidates[0] : null;
}
export function readMethod(o, key) { return methods(o).find(([k]) => k === key)?.[1]; }
export function project(mapping, world) {
  // Calculate the recognized projection ourselves; don't execute unknown candidate methods.
  if (!mapping || !vec(world)) return null;
  const { camera, posKey, widthKey, heightKey, scaleKeys } = mapping;
  const center = read(camera, posKey), width = read(camera, widthKey), height = read(camera, heightKey);
  const scale = read(camera, scaleKeys[0]) * read(camera, scaleKeys[1]);
  if (!vec(center) || !finite(width) || !finite(height) || width <= 0 || height <= 0 || !finite(scale) || scale <= 0) return null;
  return { x: width * .5 + (world.x - center.x) * scale, y: height * .5 - (world.y - center.y) * scale };
}
// Game.update derives desktop input relative to the active network position and
// viewport midpoint, NOT the (interpolated/shaken) camera center used by render.
export function aimPoint(camera, world, playerPos) {
  const target = project(camera, world), origin = project(camera, playerPos);
  if (!target || !origin) return null;
  return { x: read(camera.camera, camera.widthKey) * .5 + target.x - origin.x,
    y: read(camera.camera, camera.heightKey) * .5 + target.y - origin.y };
}
// Match the rendered position by data flow, not vector names or declaration order.
// Public Player.render: const screen = camera.<projection>(this.<visual>);
// this.container.position.set(screen.x, screen.y). Never execute render to probe it.
export function discoverVisualPosition(player, projectionMethod) {
  const tree = ast(readMethod(player, 'render')), root = tree?.params?.[0]?.name;
  if (!root || !projectionMethod) return null;
  const candidates = [];
  walk(tree, n => {
    if (n.type !== 'VariableDeclarator' || n.id?.type !== 'Identifier' || n.init?.type !== 'CallExpression') return;
    const callee = path(n.init.callee, root), source = path(n.init.arguments[0]);
    if (callee?.length !== 1 || callee[0] !== projectionMethod || n.init.arguments.length !== 1
      || source?.length !== 1 || !vec(at(player, source))) return;
    let consumed = false;
    walk(tree, call => {
      if (call.type !== 'CallExpression') return;
      const dest = path(call.callee);
      if (dest?.join('.') === 'container.position.set' && call.arguments.length === 2
        && path(call.arguments[0], n.id.name)?.join('.') === 'x'
        && path(call.arguments[1], n.id.name)?.join('.') === 'y') consumed = true;
    });
    if (consumed) candidates.push(source[0]);
  });
  return unique(candidates);
}
export function overlayPosition(player, mapping) {
  const visual = read(player, mapping.visualPosKey);
  return vec(visual) ? visual : read(player, mapping.schema?.posKey);
}
export function discoverPlayerSchema(player) {
  if (!isPlayer(player)) return null;
  const idle = ast(readMethod(player, 'selectIdlePose'));
  const interact = ast(readMethod(player, 'canInteract'));
  const melee = ast(readMethod(player, 'getMeleeCollider'));
  const netPath = unique(paths(idle).filter(p => p.length === 2 && typeof at(player, p) === 'string').map(p => p.join('\0')))?.split('\0');
  const negated = [];
  walk(interact, n => {
    if (n.type === 'UnaryExpression' && n.operator === '!') {
      const p = path(n.argument);
      if (p?.length === 2 && typeof at(player, p) === 'boolean') negated.push(p.join('\0'));
    }
  });
  const deadPath = unique(negated)?.split('\0');
  const dirs = new Set();
  for (const call of calls(melee, 'atan2')) for (const p of paths(call)) if (p.length === 2 && ['x', 'y'].includes(p[1])) dirs.add(p[0]);
  const posKey = unique(paths(melee).filter(p => p.length === 1 && vec(at(player, p)) && !dirs.has(p[0])).map(p => p[0]));
  if (!netPath || !deadPath || netPath[0] !== deadPath[0] || !posKey) return null;
  return { netKey: netPath[0], weaponKey: netPath[1], deadKey: deadPath[1], posKey, dirKey: unique([...dirs]) };
}
export function discover(game) {
  const objects = entries(game).filter(([, v]) => object(v) && !Array.isArray(v));
  const barns = objects.filter(([, v]) => object(read(v, 'teamInfo')) && Array.isArray(read(v, 'playerIds')) && object(read(v, 'playerPool')));
  const barn = barns.length === 1 ? barns[0][1] : null;
  const pool = read(barn, 'playerPool');
  const arrays = entries(pool).filter(([, v]) => Array.isArray(v) && v.length > 0 && v.every(isPlayer));
  const poolKey = arrays.length === 1 ? arrays[0][0] : null;
  const players = () => {
    const current = read(pool, poolKey);
    return Array.isArray(current) ? current.filter(p => isPlayer(p) && read(p, 'active')) : [];
  };
  const active = unique(objects.filter(([, p]) => isPlayer(p) && players().includes(p)).map(([, p]) => p));
  const schema = active ? discoverPlayerSchema(active) : null;
  const ui = unique(objects.filter(([, v]) => typeof readMethod(v, 'setSpectating') === 'function' && typeof read(v, 'spectating') === 'boolean').map(([, v]) => v));
  const map = unique(objects.filter(([, v]) => entries(v).some(([k]) => k === 'mapTexture') && typeof readMethod(v, 'getGroundSurface') === 'function').map(([, v]) => v));
  const creators = objects.filter(([, v]) => entries(v).some(([, x]) => object(x) && !Array.isArray(x) && entries(x).some(([, entity]) => finite(read(entity, '__id')) && finite(read(entity, '__type')))));
  const creator = creators.length === 1 ? creators[0][1] : null;
  const registryKey = unique(entries(creator).filter(([, x]) => object(x) && !Array.isArray(x) && entries(x).some(([, e]) => finite(read(e, '__id')) && finite(read(e, '__type')))).map(([k]) => k));
  const obstacles = () => entries(read(creator, registryKey)).map(([, v]) => v).filter(v => object(read(v, 'collider')) && typeof read(v, 'collidable') === 'boolean');
  const activeKey = unique(objects.filter(([, value]) => value === active).map(([key]) => key));
  const camera = discoverCamera(game);
  const visualPosKey = active && camera ? discoverVisualPosition(active, camera.method) : null;
  return { game, barn, barnKey: barns.length === 1 ? barns[0][0] : null, pool, poolKey, players, active, activeKey, schema, ui, map, camera, visualPosKey, obstacles, creator, registryKey };
}
// The public LootBarn getter returns one own field. Read that field ourselves;
// never execute an unknown getter or choose the first loot-like object.
export function discoverLootSource(game) {
  const found = [];
  for (const [, owner] of entries(game)) {
    const tree = ast(readMethod(owner, 'getClosestLoot'));
    const body = tree?.body?.body;
    if (body?.length !== 1 || body[0].type !== 'ReturnStatement') continue;
    const p = path(body[0].argument);
    if (p?.length === 1 && (read(owner, p[0]) === null || object(read(owner, p[0])))) found.push({ owner, key: p[0] });
  }
  return found.length === 1 ? found[0] : null;
}
export function teamOf(barn, id) {
  return unique(entries(read(barn, 'teamInfo')).filter(([, team]) => Array.isArray(read(team, 'playerIds')) && read(team, 'playerIds').includes(id)).map(([key]) => key));
}
// One index per feature pass, shared by ESP and aim. Conflicting or missing
// membership is unknown, never an implicit enemy. Group/squad is NOT the team.
function membershipIndex(table) {
  const index = new Map(); let budget = 8192;
  const records = entries(table);
  if (records.length > 1024) return new Map();
  for (const [key, group] of records) {
    const ids = read(group, 'playerIds');
    if (!Array.isArray(ids)) continue;
    for (const id of ids) {
      if (--budget < 0) return new Map();
      if (!Number.isInteger(id) || id < 0) continue;
      if (!index.has(id)) index.set(id, key);
      else if (index.get(id) !== key) index.set(id, null);
    }
  }
  return index;
}
export function teamRelations(barn, ownId) {
  const teams = membershipIndex(read(barn, 'teamInfo'));
  const groups = membershipIndex(read(barn, 'groupInfo'));
  const ownTeam = teams.get(ownId), ownGroup = groups.get(ownId);
  return {
    ready: ownTeam !== undefined && ownTeam !== null,
    classify(id) {
      if (id === ownId) return { kind: 'self', squad: false };
      const team = teams.get(id), group = groups.get(id);
      if (ownTeam === undefined || ownTeam === null || team === undefined || team === null) return { kind: 'unknown', squad: false };
      const ally = team === ownTeam;
      return { kind: ally ? 'ally' : 'enemy', squad: ally && ownGroup !== undefined && ownGroup !== null && group === ownGroup };
    },
  };
}
export function localWeapon(mapping) {
  const { active, schema } = mapping || {};
  return active && schema ? at(active, [schema.netKey, schema.weaponKey]) : null;
}

export function intercept(relative, velocity, speed, maxTime = 2) {
  if (!vec(relative) || !vec(velocity) || !finite(speed) || speed <= 0) return null;
  const a = velocity.x ** 2 + velocity.y ** 2 - speed ** 2;
  const b = 2 * (relative.x * velocity.x + relative.y * velocity.y);
  const c = relative.x ** 2 + relative.y ** 2;
  if (c < 1e-12) return 0;
  let roots;
  if (Math.abs(a) < 1e-8) roots = Math.abs(b) > 1e-8 ? [-c / b] : [];
  else {
    const disc = b * b - 4 * a * c;
    if (disc < 0) return null;
    // Stable quadratic roots reduce catastrophic cancellation.
    const q = -.5 * (b + (b >= 0 ? 1 : -1) * Math.sqrt(disc));
    roots = q === 0 ? [-b / (2 * a)] : [q / a, c / q];
  }
  const positive = roots.filter(t => finite(t) && t >= 0 && t <= maxTime);
  return positive.length ? Math.min(...positive) : null;
}
export class Tracker {
  states = new WeakMap();
  reset() { this.states = new WeakMap(); }
  update(entity, pos, now) {
    const id = read(entity, '__id');
    let st = this.states.get(entity);
    if (!st || st.id !== id || now - st.time > 500 || now <= st.time) {
      st = { id, pos: point(pos), time: now, vx: 0, vy: 0 };
      this.states.set(entity, st); return st;
    }
    const dt = (now - st.time) / 1000;
    if (dt < .008) return st;
    const vx = (pos.x - st.pos.x) / dt, vy = (pos.y - st.pos.y) / dt;
    if (Math.hypot(vx, vy) > 80) { st.vx = st.vy = 0; }
    else {
      const len = Math.hypot(vx, vy) * Math.hypot(st.vx, st.vy);
      const turn = len > 1 && (vx * st.vx + vy * st.vy) / len < .35;
      const gain = turn ? 1 : 1 - Math.exp(-dt / .06);
      st.vx += (vx - st.vx) * gain; st.vy += (vy - st.vy) * gain;
    }
    st.pos = point(pos); st.time = now; return st;
  }
}
// Conservative segment tests. No shape/name guess: unsupported collider blocks wallcheck.
export function segmentBlocked(start, end, collider) {
  const dx = end.x - start.x, dy = end.y - start.y;
  const type = read(collider, 'type');
  if (type === 0 && vec(read(collider, 'pos')) && finite(read(collider, 'rad'))) {
    const c = read(collider, 'pos'), rad = read(collider, 'rad');
    const d2 = dx * dx + dy * dy;
    const t = d2 > 0 ? clamp(((c.x - start.x) * dx + (c.y - start.y) * dy) / d2, 0, 1) : 0;
    return (start.x + dx * t - c.x) ** 2 + (start.y + dy * t - c.y) ** 2 <= rad * rad;
  }
  if (type === 1 && vec(read(collider, 'min')) && vec(read(collider, 'max'))) {
    let lo = 0, hi = 1;
    for (const [axis, delta] of [['x', dx], ['y', dy]]) {
      const min = collider.min[axis], max = collider.max[axis];
      if (Math.abs(delta) < 1e-10) { if (start[axis] < min || start[axis] > max) return false; }
      else {
        const t1 = (min - start[axis]) / delta, t2 = (max - start[axis]) / delta;
        lo = Math.max(lo, Math.min(t1, t2)); hi = Math.min(hi, Math.max(t1, t2));
        if (lo > hi) return false;
      }
    }
    return true;
  }
  return true;
}

export class Disposables {
  tasks = [];
  add(fn) { this.tasks.push(fn); return fn; }
  clear() {
    const errors = [];
    for (const fn of this.tasks.splice(0).reverse()) { try { fn(); } catch (e) { errors.push(e); } }
    return errors;
  }
}
export function patchMethod(owner, key, makeWrapper, bag) {
  const original = owner?.[key];
  if (typeof original !== 'function') return false;
  const descriptor = Object.getOwnPropertyDescriptor(owner, key);
  if (descriptor && !descriptor.configurable && !descriptor.writable) return false;
  const wrapper = makeWrapper(original);
  try {
    Object.defineProperty(owner, key, { configurable: true, enumerable: descriptor?.enumerable ?? false, writable: true, value: wrapper });
  } catch { return false; }
  bag.add(() => {
    if (owner[key] !== wrapper) return; // Never overwrite a later owner's hook.
    if (descriptor) Object.defineProperty(owner, key, descriptor);
    else delete owner[key];
  });
  return true;
}
export function captureApplication(win, onApp, { timeout = 15000, onTimeout = () => {} } = {}) {
  const bag = new Disposables(), proto = win.Function.prototype;
  const apply = win.Reflect.apply;
  let inHook = false, done = false, cancelled = false;
  const finish = () => { done = true; bag.clear(); };
  const cancel = () => { cancelled = true; finish(); };
  const installed = patchMethod(proto, 'call', original => function (self) {
    let captured = false;
    if (!done && !inHook) {
      inHook = true;
      try { captured = isApplication(self); } catch { /* Forward the original call. */ }
      finally { inHook = false; }
    }
    if (captured) {
      finish();
      // Don't initialize UI/scan graphs inside a fundamental call hook.
      // A Retry/Stop before this microtask must invalidate the pending delivery.
      win.queueMicrotask(() => { if (!cancelled) onApp(self); });
    }
    return apply(original, this, arguments);
  }, bag);
  if (!installed) { onTimeout(); return cancel; }
  const timer = win.setTimeout(() => { if (!done) { cancel(); onTimeout(); } }, timeout);
  bag.add(() => win.clearTimeout(timer));
  return cancel;
}
export function captureDefinitions(win, onDefs, timeout = 15000) {
  const bag = new Disposables(), apply = win.Reflect.apply;
  let busy = false, done = false;
  const cancel = () => { done = true; bag.clear(); };
  patchMethod(win.Object, 'keys', original => function (value) {
    if (!done && !busy) {
      busy = true;
      try {
        if (read(read(value, 'mp5'), 'type') === 'gun' && read(read(value, 'bullet_mp5'), 'type') === 'bullet'
          && read(read(value, 'frag'), 'type') === 'throwable' && read(read(value, 'explosion_frag'), 'type') === 'explosion') {
          cancel(); win.queueMicrotask(() => onDefs(value));
        }
      } catch { /* Cannot classify => don't touch. */ }
      finally { busy = false; }
    }
    return apply(original, this, arguments);
  }, bag);
  const timer = win.setTimeout(cancel, timeout);
  bag.add(() => win.clearTimeout(timer));
  return cancel;
}
