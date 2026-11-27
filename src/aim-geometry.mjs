import { finite, read, sameLayer, vec } from './core.mjs';
import { muzzleAt } from './aim.mjs';
import { rayHit } from './previews.mjs';

// Take one fresh registry snapshot per aim solve. Never invoke registry getters or
// reuse membership across packets: newly spawned/moved cover must be visible.
export function geometryObjects(registry) {
  const obstacles = [], structures = [];
  if (!registry || typeof registry !== 'object' && typeof registry !== 'function' || Array.isArray(registry)) return { obstacles, structures, valid: false };
  let valid = true;
  try {
    for (const key of Object.getOwnPropertyNames(registry)) {
      const descriptor = Object.getOwnPropertyDescriptor(registry, key);
      // A disappearing entry or accessor could hide a world object. Do not
      // invoke it, and do not claim the wallcheck snapshot is complete.
      if (!descriptor || !('value' in descriptor)) { valid = false; continue; }
      const o = descriptor.value;
      if (Array.isArray(read(o, 'stairs'))) structures.push(o);
      if (read(o, '__type') === 2 || read(o, 'collider') !== null && typeof read(o, 'collider') === 'object' && typeof read(o, 'collidable') === 'boolean') obstacles.push(o);
    }
  } catch { return { obstacles: [], structures: [], valid: false }; }
  return { obstacles, structures, valid };
}

// Structure.stairs is public client state built from shared map definitions.
// Server checkStructureStairs uses circle/AABB, then cardinal facing to choose aimLayer.
export function shotLayer(pos, direction, layer, radius, structures) {
  // Never infer a clear layer from a truncated or malformed stair list.
  if (!Array.isArray(structures) || structures.length > 256) return null;
  for (const structure of structures) {
    if (structure.active !== true || !Array.isArray(structure.stairs)) continue;
    if (structure.stairs.length > 32) return null;
    for (const stair of structure.stairs) {
      if (stair?.lootOnly) continue;
      if (!vec(stair?.collision?.min) || !vec(stair?.collision?.max)
          || stair.collision.min.x > stair.collision.max.x || stair.collision.min.y > stair.collision.max.y) return null;
      const { min, max } = stair.collision;
      const x = Math.max(min.x, Math.min(max.x, pos.x)), y = Math.max(min.y, Math.min(max.y, pos.y));
      if ((x - pos.x) ** 2 + (y - pos.y) ** 2 > radius ** 2) continue;
      if (!vec(stair.downDir)) return null;
      const cardinal = dir => { const angle = Math.atan2(dir.y, dir.x) + Math.PI / 4; return Math.floor(((angle % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI) / (Math.PI / 2)); };
      const ori = cardinal(direction), downOri = cardinal(stair.downDir);
      return ori === downOri ? 3 : ori === (downOri + 2) % 4 ? 2 : layer;
    }
  }
  return layer;
}

// Match fireWeapon's central pellet muzzle clipping plane (+1.5 probe, .01
// surface bias, -.1 setback). Shotgun jitter/unknown dual hand remain uncertainty.
export function clippedMuzzle(pos, dir, profile, obstacles, layer, collisionLayer, radius = 1) {
  const gunPos = { x: pos.x - dir.y * profile.offset, y: pos.y + dir.x * profile.offset };
  let nearest = null;
  for (const o of obstacles.slice(0, 1024)) {
    if (!o.active || o.dead || !o.collidable || !sameLayer(o.layer, layer) || finite(o.height) && o.height < .25) continue;
    const shape = read(o, 'collider');
    // Server ignores containing obstacles when shooting across a stair boundary.
    if (!sameLayer(collisionLayer, layer) && shape) {
      let inside = false;
      if (shape.type === 0 && vec(shape.pos)) inside = Math.hypot(gunPos.x - shape.pos.x, gunPos.y - shape.pos.y) < radius + shape.rad;
      if (shape.type === 1 && vec(shape.min) && vec(shape.max)) {
        const x = Math.max(shape.min.x, Math.min(shape.max.x, gunPos.x)), y = Math.max(shape.min.y, Math.min(shape.max.y, gunPos.y));
        inside = Math.hypot(x - gunPos.x, y - gunPos.y) < radius;
      }
      if (inside) continue;
    }
    const hit = rayHit(gunPos, dir, profile.barrel + 1.5, shape);
    if (hit && (!nearest || hit.distance < nearest.distance)) nearest = hit;
  }
  if (!nearest || nearest.distance >= profile.barrel) return muzzleAt(pos, dir, profile);
  const dot = dir.x * nearest.normal.x + dir.y * nearest.normal.y;
  const length = nearest.distance + (dot < -1e-5 ? .01 / dot : 0) - .1;
  return { x: gunPos.x + dir.x * length, y: gunPos.y + dir.y * length };
}

// Stop at the near edge of the target's circular hitbox: an obstacle beyond
// the first player intersection does not block that hit on the server.
export function pathToTarget(muzzle, target, radius = 0) {
  const dx = target.x - muzzle.x, dy = target.y - muzzle.y, distance = Math.hypot(dx, dy);
  const r = finite(radius) ? Math.max(0, radius) : 0;
  // Source circle intersection uses the exit intersection if the segment starts
  // inside a player. Conservatively check through that exit instead of length 0.
  const length = distance < r ? distance + r : Math.max(0, distance - r);
  return distance > 0 ? { x: muzzle.x + dx * length / distance, y: muzzle.y + dy * length / distance } : { ...muzzle };
}

// For a smoothed/assisted direction, stop at the actual ray-circle entry (or
// exit when inside). If it misses, check the entire conservative segment as
// before: a hypothetical hit on a different direction is not a safe cutoff.
export function pathAlongAim(muzzle, direction, target, radius = 0) {
  const n = Math.hypot(direction.x, direction.y), dx = target.x - muzzle.x, dy = target.y - muzzle.y;
  const distance = Math.hypot(dx, dy), r = finite(radius) ? Math.max(0, radius) : 0;
  if (!finite(n) || n <= 1e-8) return { ...muzzle };
  const x = direction.x / n, y = direction.y / n, projection = dx * x + dy * y;
  const disc = projection * projection - (dx * dx + dy * dy - r * r);
  let length = distance + r;
  if (disc >= 0) {
    const root = Math.sqrt(disc), entry = projection - root, exit = projection + root;
    if (entry >= 0) length = Math.min(length, entry);
    else if (exit >= 0) length = Math.min(length, exit);
  }
  return { x: muzzle.x + x * length, y: muzzle.y + y * length };
}

// Broadphase only: far map objects must not consume the narrow-phase budget.
// Unsupported/invalid shapes stay relevant so wallcheck still fails closed.
export function segmentCandidates(obstacles, from, to, padding = 0) {
  const minX = Math.min(from.x, to.x) - padding, maxX = Math.max(from.x, to.x) + padding;
  const minY = Math.min(from.y, to.y) - padding, maxY = Math.max(from.y, to.y) + padding;
  return obstacles.filter(o => {
    const c = read(o, 'collider'); let left, right, bottom, top;
    if (read(c, 'type') === 0 && vec(read(c, 'pos')) && finite(read(c, 'rad')) && c.rad >= 0) {
      left = c.pos.x - c.rad; right = c.pos.x + c.rad; bottom = c.pos.y - c.rad; top = c.pos.y + c.rad;
    } else if (read(c, 'type') === 1 && vec(read(c, 'min')) && vec(read(c, 'max')) && c.min.x <= c.max.x && c.min.y <= c.max.y) {
      left = c.min.x; right = c.max.x; bottom = c.min.y; top = c.max.y;
    } else return true;
    return right >= minX && left <= maxX && top >= minY && bottom <= maxY;
  });
}
