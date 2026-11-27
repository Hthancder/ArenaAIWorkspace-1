import { finite, read, sameLayer, vec } from './core.mjs';

// Loot input carries no target ID. The server can choose a different object
// from the client, because its pickup radius includes the player radius.
// Block when any observed eligible-owner loot is at least as close as the
// candidate, even if its client pickup radius is smaller. This is deliberately
// conservative and cannot see unreplicated or future server state.
export function nearbyLootSafety(registry, candidate, origin, layer, ownerId) {
  if (!registry || typeof registry !== 'object' || Array.isArray(registry) || !candidate || !vec(origin)
    || !Number.isInteger(layer) || !Number.isInteger(ownerId) || !vec(read(candidate, 'pos'))) return 'missing-registry';
  const p = read(candidate, 'pos'), candidateDistance = (p.x - origin.x) ** 2 + (p.y - origin.y) ** 2;
  if (!finite(candidateDistance)) return 'missing-registry';
  let found = false;
  try {
    const keys = Object.getOwnPropertyNames(registry);
    if (keys.length > 8192) return 'registry-budget';
    for (const key of keys) {
      const d = Object.getOwnPropertyDescriptor(registry, key);
      if (!d || !('value' in d)) return 'missing-registry';
      const loot = d.value;
      if (loot === candidate) { found = true; continue; }
      if (read(loot, '__type') !== 3 || read(loot, 'active') === false) continue;
      if (read(loot, 'active') !== true) return 'unknown-loot';
      const otherLayer = read(loot, 'layer'), owner = read(loot, 'ownerId'), pos = read(loot, 'pos');
      if (!Number.isInteger(otherLayer) || !Number.isInteger(owner) || !vec(pos)) return 'unknown-loot';
      if (!sameLayer(otherLayer, layer) || owner !== 0 && owner !== ownerId) continue;
      const distance = (pos.x - origin.x) ** 2 + (pos.y - origin.y) ** 2;
      if (!finite(distance) || distance <= candidateDistance) return 'competing-loot';
    }
  } catch { return 'missing-registry'; }
  return found ? 'clear-observed' : 'candidate-not-in-registry';
}
