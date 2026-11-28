import { finite, vec } from './core.mjs';

// Only use the auxiliary track built from complete, continuous, source-shaped
// updates. Absence is evidence of a stop, never an observed movement sample.
// This function cannot prove the target will remain stationary after receipt.
export function inferredStationary(track, stationary, requireNewer = false) {
  if (!stationary || !vec(stationary.pos) || !finite(stationary.age) || stationary.age < 0 || stationary.age > .15
    || !finite(stationary.time) || !finite(stationary.vx) || !finite(stationary.vy)
    || Math.hypot(stationary.vx,stationary.vy) >= .2 || !Array.isArray(stationary.samples) || stationary.samples.length < 2
    || !stationary.samples.every(s => vec(s?.p) && Math.hypot(s.p.x-stationary.pos.x,s.p.y-stationary.pos.y)<.02)) return null;
  if (requireNewer && (!track || !finite(track.time) || stationary.time <= track.time
    || !vec(track.pos) || Math.hypot(track.pos.x-stationary.pos.x,track.pos.y-stationary.pos.y)>=.02
    || track.layer !== stationary.layer)) return null;
  return { ...stationary, vx:0, vy:0, error:0, velocityError:0, motion:[] };
}
