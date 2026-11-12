import { finite, read, sameLayer, vec } from './core.mjs';
import { muzzleAt } from './aim.mjs';
import { rayHit } from './previews.mjs';

// Structure.stairs is public client state built from shared map definitions.
// Server checkStructureStairs uses circle/AABB, then cardinal facing to choose aimLayer.
export function shotLayer(pos, direction, layer, radius, structures) {
  for (const structure of structures.slice(0, 256)) {
    if (structure.active !== true || !Array.isArray(structure.stairs)) continue;
    for (const stair of structure.stairs.slice(0, 32)) {
      if (stair.lootOnly || !vec(stair.collision?.min) || !vec(stair.collision?.max)) continue;
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

// Broadphase only: far map objects must not consume the narrow-phase budget.
// Unsupported/invalid shapes stay relevant so wallcheck still fails closed.
export function segmentCandidates(obstacles, from, to, padding = 0) {
  const minX = Math.min(from.x, to.x) - padding, maxX = Math.max(from.x, to.x) + padding;
  const minY = Math.min(from.y, to.y) - padding, maxY = Math.max(from.y, to.y) + padding;
  return obstacles.filter(o => {
    const c = read(o, 'collider'); let left, right, bottom, top;
    if (read(c, 'type') === 0 && vec(read(c, 'pos')) && finite(read(c, 'rad')) && c.rad >= 0) {
      left = c.pos.x - c.rad; right = c.pos.x + c.rad; bottom = c.pos.y - c.rad; top = c.pos.y + c.rad;
    } else if (read(c, 'type') === 1 && vec(read(c, 'min')) && vec(read(c, 'max'))) {
      left = c.min.x; right = c.max.x; bottom = c.min.y; top = c.max.y;
    } else return true;
    return right >= minX && left <= maxX && top >= minY && bottom <= maxY;
  });
}
