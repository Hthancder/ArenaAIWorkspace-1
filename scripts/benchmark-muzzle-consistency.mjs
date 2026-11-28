// Synthetic model consistency, not gameplay accuracy or server hit rate.
// AIM_MODULE may point to a local historical/experimental solver for comparison.
import { clippedMuzzle } from '../src/aim-geometry.mjs';
const { predictShot } = await import(process.env.AIM_MODULE || '../src/aim.mjs');
const groups = {};
for (const cover of [false, true]) for (let i = 0; i < 30000; i++) {
  const angle = i * 2.399963, d = 1 + ((i * 13) % 490) / 10;
  const target = { x: d * Math.cos(angle), y: d * Math.sin(angle) };
  const profile = { offset: ((i % 19) - 9) * .1, barrel: 1 + (i % 30) * .1, speed: 40 + i % 150, range: 1000, variance: 1 };
  const track = { pos: target, vx: i % 23 - 11, vy: i % 29 - 14, age: .03, error: 0, velocityError: 0 };
  const obstacles = cover ? [{ active: true, dead: false, collidable: true, layer: 0, height: 1, collider: { type: 0, pos: { x: 1.3, y: 0 }, rad: .5 } }] : [];
  const muzzleFor = (origin, dir, model) => clippedMuzzle(origin, dir, model, obstacles, 0, 0);
  const shot = predictShot({ origin: { x: 0, y: 0 }, target, track, profile, muzzleFor });
  const name = `${cover ? 'circle' : 'open'}:${d < 4 ? '1-4' : d < 10 ? '4-10' : '10-50'}`;
  const g = groups[name] ||= { n: 0, fallback: 0, rejected: 0, inconsistent: 0, max: 0 };
  g.n++;
  if (!shot.dir) { g.rejected++; continue; }
  if (shot.state === 'unresolved-muzzle-solution') g.fallback++;
  const error = Math.hypot(shot.muzzle.x + shot.dir.x * profile.speed * shot.time - shot.world.x,
    shot.muzzle.y + shot.dir.y * profile.speed * shot.time - shot.world.y);
  if (error > .02000001) g.inconsistent++;
  g.max = Math.max(g.max, error);
}
console.log('Synthetic final muzzle/flight/point consistency; no spread, walls after muzzle, lag, human input or live hit rate.');
for (const [name, g] of Object.entries(groups)) console.log(`${name}: n=${g.n} rejected=${g.rejected} fallback=${g.fallback} error>0.02=${g.inconsistent} max=${g.max.toFixed(3)} wu`);
