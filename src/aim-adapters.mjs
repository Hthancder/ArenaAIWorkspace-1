import { ast, methods, path, paths, read, unique, walk } from './core.mjs';

// Identify native send scheduling by data flow, not the property's spelling.
export function discoverInputTimeout(game) {
  const found = [];
  for (const [, fn] of methods(game)) {
    const tree = ast(fn), tested = new Set(), reset = new Set(), decremented = new Set();
    walk(tree, n => {
      // Production minifiers turn `if (diff || timer < 0)` into a logical
      // expression. Inspect the comparison itself, independent of statement shape.
      if (n.type === 'BinaryExpression') {
        const left = path(n.left), right = path(n.right);
        if (n.operator === '<' && n.right?.value === 0 && left?.length === 1) tested.add(left[0]);
        if (n.operator === '>' && n.left?.value === 0 && right?.length === 1) tested.add(right[0]);
      }
      if (n.type === 'AssignmentExpression') {
        const p = path(n.left); if (p?.length !== 1) return;
        if (n.operator === '=' && n.right?.value === 1) reset.add(p[0]);
        if (n.operator === '-=' || n.operator === '=' && n.right?.type === 'BinaryExpression' && n.right.operator === '-' && path(n.right.left)?.join('.') === p.join('.')) decremented.add(p[0]);
      }
    });
    for (const key of tested) if (reset.has(key) && decremented.has(key)) found.push(key);
  }
  return unique(found);
}
export function discoverUpdateReceiver(game) {
  return unique(methods(game).filter(([, fn]) => {
    const tree = ast(fn), root = tree?.params?.[0]?.name;
    if (!root) return false;
    const refs = new Set(paths(tree, root).map(p => p[0]));
    return ['fullObjects', 'partObjects', 'delObjIds', 'activePlayerData'].every(key => refs.has(key));
  }).map(([key]) => key));
}
export function discoverSourceFields(player, schema) {
  const roles = { pos: [], layer: [], perks: [], scale: [] };
  for (const [, fn] of methods(player)) {
    const tree = ast(fn), root = tree?.params?.[0]?.name; if (!root) continue;
    walk(tree, n => {
      if (n.type !== 'AssignmentExpression' || n.operator !== '=') return;
      const left = path(n.left); if (left?.length !== 2 || left[0] !== schema.netKey) return;
      for (const p of paths(n.right, root)) if (p.length === 1 && roles[p[0]]) roles[p[0]].push(left[1]);
    });
  }
  return Object.fromEntries(Object.entries(roles).map(([role, keys]) => [role, unique(keys)]));
}

// Bounded local estimates; ACK includes scheduling and is not a server clock.
export class NetworkTiming {
  constructor() { this.reset(); }
  reset() { this.rtt = null; this.inFlightAt = null; this.lastSeq = null; }
  sent(msg, now) {
    if (msg?.seq !== this.lastSeq) { this.lastSeq = msg?.seq; this.inFlightAt = now; }
  }
  received(msg, now) {
    if (this.inFlightAt !== null && msg.ack === this.lastSeq) {
      const value = now - this.inFlightAt;
      if (value >= 0 && value < 1000) this.rtt = this.rtt === null ? value : .8 * this.rtt + .2 * value;
      this.inFlightAt = null;
    }
  }
  transit() { return this.rtt === null ? 0 : Math.min(.1, this.rtt / 2000); }
}
