/**
 * Shared rigid-transform primitives for hand poses.
 *
 * HARD RULE (2026-11-15 user feedback — "ngón tay méo mó, mềm oặt, ảo"):
 * every helper here preserves BONE LENGTHS exactly. Motion is expressed
 * as translations of whole chains and Rodrigues rotations around real
 * joint pivots — never as independent per-joint position blends.
 * World frame: see types.ts (1 mm = 0.01 world units).
 */
import type { HandPose, Vec3 } from './types'

export function copyVec(a: Vec3, b: Vec3): void {
  b[0] = a[0]
  b[1] = a[1]
  b[2] = a[2]
}

export function setVec(out: Vec3, x: number, y: number, z: number): void {
  out[0] = x
  out[1] = y
  out[2] = z
}

export function addVec(out: Vec3, dx: number, dy: number, dz: number): void {
  out[0] += dx
  out[1] += dy
  out[2] += dz
}

export function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v))
}

/** Unit vector a→b; returns its length (0 leaves `out` untouched). */
export function boneDir(a: Vec3, b: Vec3, out: Vec3): number {
  const dx = b[0] - a[0]
  const dy = b[1] - a[1]
  const dz = b[2] - a[2]
  const len = Math.hypot(dx, dy, dz)
  if (len > 1e-9) {
    out[0] = dx / len
    out[1] = dy / len
    out[2] = dz / len
  }
  return len
}

/** In-place normalize; falls back to (1,0,0) for degenerate vectors. */
export function normalize(v: Vec3): void {
  const len = Math.hypot(v[0], v[1], v[2])
  if (len > 1e-9) {
    v[0] /= len
    v[1] /= len
    v[2] /= len
  } else {
    setVec(v, 1, 0, 0)
  }
}

/** Rodrigues rotation of a DIRECTION (no pivot) around a unit axis. */
export function rotateVec(v: Vec3, axis: Vec3, theta: number): void {
  const c = Math.cos(theta)
  const s = Math.sin(theta)
  const ad = axis[0] * v[0] + axis[1] * v[1] + axis[2] * v[2]
  const cx = axis[1] * v[2] - axis[2] * v[1]
  const cy = axis[2] * v[0] - axis[0] * v[2]
  const cz = axis[0] * v[1] - axis[1] * v[0]
  v[0] = c * v[0] + s * cx + (1 - c) * ad * axis[0]
  v[1] = c * v[1] + s * cy + (1 - c) * ad * axis[1]
  v[2] = c * v[2] + s * cz + (1 - c) * ad * axis[2]
}

/** Rodrigues rotation of POINTS around a pivot on a unit axis. */
export function rotateAbout(pivot: Vec3, axis: Vec3, theta: number, pts: Vec3[]): void {
  const c = Math.cos(theta)
  const s = Math.sin(theta)
  for (const v of pts) {
    const x = v[0] - pivot[0]
    const y = v[1] - pivot[1]
    const z = v[2] - pivot[2]
    const ad = axis[0] * x + axis[1] * y + axis[2] * z
    const cx = axis[1] * z - axis[2] * y
    const cy = axis[2] * x - axis[0] * z
    const cz = axis[0] * y - axis[1] * x
    v[0] = pivot[0] + c * x + s * cx + (1 - c) * ad * axis[0]
    v[1] = pivot[1] + c * y + s * cy + (1 - c) * ad * axis[1]
    v[2] = pivot[2] + c * z + s * cz + (1 - c) * ad * axis[2]
  }
}

/**
 * Uniform translation of every JOINT — bone lengths preserved exactly.
 * `thumbRef` are twist DIRECTIONS (unit vectors), not positions: they
 * must never be translated, only rotated (rotateVec) with the thumb.
 */
export function shiftPose(p: HandPose, dx: number, dy: number, dz: number, includeElbow = true): void {
  if (includeElbow) addVec(p.elbow, dx, dy, dz)
  addVec(p.wrist, dx, dy, dz)
  for (const b of p.bases) addVec(b, dx, dy, dz)
  for (const chain of p.fingers) for (const j of chain) addVec(j, dx, dy, dz)
}
