import { finite, vec } from './core.mjs';

// Optional, bounded experiment: last received own snapshot is behind server
// fire time. Only extrapolate when fresh observed velocity agrees with current
// desktop movement intent and RTT is known. No prediction of future turns.
export function projectOwnOrigin(origin, track, movement, timing, now) {
  if (!vec(origin) || !track || !vec(movement) || !finite(now)) return null;
  if (!finite(track.age) || track.age < 0 || track.age > .1 || !Array.isArray(track.samples) || track.samples.length < 3) return null;
  const first = track.samples[0], last = track.samples.at(-1);
  if (!finite(first?.t) || !finite(last?.t) || last.t - first.t < 60 || !finite(track.error) || track.error > .12) return null;
  const { vx, vy } = track, speed = Math.hypot(vx, vy), magnitude = Math.hypot(movement.x, movement.y);
  if (!finite(vx) || !finite(vy) || speed < .6 || speed > 20 || magnitude < .5) return null;
  if ((vx * movement.x + vy * movement.y) / (speed * magnitude) < .9) return null;
  if (!finite(timing?.rtt) || !finite(timing?.lastRtt) || !finite(timing?.rttAt)
      || timing.rtt < 0 || timing.rtt > 200 || timing.lastRtt < 0 || timing.lastRtt > 200
      || now < timing.rttAt || now - timing.rttAt > 1500) return null;
  const seconds = Math.min(.2, track.age + timing.rtt / 1000);
  return { x: origin.x + vx * seconds, y: origin.y + vy * seconds, seconds };
}
