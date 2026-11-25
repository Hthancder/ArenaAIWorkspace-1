import { ast, entries, finite, methods, object, path, paths, read, vec, walk } from './core.mjs';

// Recognize SmokeBarn's update data flow even while its particle array is empty.
// No texture getter probing, first-array selection or m_* name dependency.
export function discoverSmokeSources(game) {
  const sources = [];
  for (const [, barn] of entries(game)) {
    if (!object(barn) || !entries(barn).some(([, value]) => Array.isArray(value))) continue;
    const candidates = new Map();
    for (const [method, fn] of methods(barn)) {
      const tree = ast(fn);
      walk(tree, n => {
        if (n.type !== 'VariableDeclarator' || n.id?.type !== 'Identifier' || n.init?.type !== 'MemberExpression' || !n.init.computed) return;
        const arrayPath = path(n.init.object), root = n.id.name;
        if (arrayPath?.length !== 1 || !Array.isArray(read(barn, arrayPath[0]))) return;
        const refs = paths(tree, root).map(p => p.join('.'));
        if (!['fadeTicker', 'fadeDuration', 'posTarget', 'radTarget'].every(p => refs.includes(p))) return;
        const writes = new Set();
        walk(tree, assignment => {
          if (assignment.type === 'AssignmentExpression') {
            const p = path(assignment.left, root); if (p) writes.add(p.join('.'));
          }
        });
        if (!['sprite.alpha', 'sprite.tint', 'sprite.visible'].every(p => writes.has(p))) return;
        candidates.set(arrayPath[0], { barn, key: arrayPath[0], method });
      });
    }
    if (candidates.size === 1) sources.push([...candidates.values()][0]);
  }
  return sources;
}
export function smokeParticles(sources) {
  const found = [], seen = new Set();
  for (const { barn, key } of sources) {
    const list = read(barn, key);
    if (!Array.isArray(list)) continue;
    for (const particle of list.slice(0, 2048)) {
      if (seen.has(particle)) continue; seen.add(particle);
      if (read(particle, 'active') !== true || !object(read(particle, 'sprite'))
        || !finite(read(particle, 'fadeTicker')) || !finite(read(particle, 'fadeDuration'))
        || !vec(read(particle, 'posTarget')) || !finite(read(particle, 'radTarget'))
        || read(read(particle, 'sprite'), '_destroyed') === true) continue;
      found.push(particle);
    }
  }
  return found;
}
// Legacy Duality deliberately used value / 1000, not percent multiplication.
// Cap rather than overwrite so native fading may still reduce alpha below it.
export function smokeAlpha(raw, setting) {
  return finite(raw) && finite(setting) ? Math.min(Math.max(0, raw), Math.max(0, Math.min(100, setting)) / 1000) : raw;
}
export const emptyXrayStats = (state = 'disabled') => ({ state, smokeSources: 0, smokeActive: 0, smokeModified: 0, smokeUnsupported: 0, darkened: 0, ceilings: 0, vegetation: 0 });
