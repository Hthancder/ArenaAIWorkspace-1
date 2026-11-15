// The neutral hand pose for free play ("đánh tự do") — hands that are not
// part of any song's motion still show up and play the user's input.
//
// Baked from the REAL hands pipeline by scripts/extract-neutral-pose.ts
// (hands-worker.js + hands.wasm + the vendored motion DB, one held note
// per hand at the keyboard centre, mid-hold frame t=2.5 s), then rigid-
// shifted so each hand sits over its half of the keyboard (wrist x = ±1.5)
// and lifted 8 mm (z) so the fingers hover above the key tops instead of
// pressing into them. Units / frame: see types.ts (1 mm = 0.01).
//
// Treated as READ-ONLY: the live overlay copies it before animating.
import type { HandPose } from './types'

const NEUTRAL_R: HandPose = {
  hand: 'R',
  elbow: [1.8751, -4.326, 0.4858],
  wrist: [1.5, -2.368, 0.9532],
  bases: [
    [1.2686, -2.2384, 0.6897],
    [1.3571, -2.2216, 0.8913],
    [1.447, -2.2013, 0.9026],
    [1.5353, -2.1426, 0.9041],
    [1.6166, -2.1334, 0.9166],
  ],
  fingers: [
    [
      [1.1966, -2.207, 0.6519],
      [1.0354, -1.9307, 0.5535],
      [0.971, -1.6686, 0.4462],
      [1.0048, -1.4755, 0.3318],
    ],
    [
      [1.1864, -1.6453, 0.7139],
      [1.106, -1.3165, 0.5748],
      [1.0746, -1.1598, 0.445],
      [1.0589, -1.0543, 0.3086],
    ],
    [
      [1.3759, -1.6315, 0.7495],
      [1.3107, -1.3203, 0.4897],
      [1.2839, -1.2453, 0.2609],
      [1.2742, -1.2633, 0.0744],
    ],
    [
      [1.5762, -1.6386, 0.7339],
      [1.5796, -1.2938, 0.5728],
      [1.5417, -1.1808, 0.3691],
      [1.4954, -1.1775, 0.1882],
    ],
    [
      [1.7612, -1.7302, 0.6707],
      [1.8604, -1.4773, 0.5404],
      [1.9035, -1.3463, 0.447],
      [1.9413, -1.2158, 0.3375],
    ],
  ],
  press: [0, 0, 0, 0, 0],
  thumbRef: [
    [0.2323, 0.0526, 0.9712],
    [0.1832, 0.0864, 0.9793],
    [0.0243, 0.1953, 0.9804],
  ],
}

const NEUTRAL_L: HandPose = {
  hand: 'L',
  elbow: [-1.8751, -4.326, 0.4858],
  wrist: [-1.5, -2.368, 0.9532],
  bases: [
    [-1.2686, -2.2384, 0.6897],
    [-1.3571, -2.2216, 0.8913],
    [-1.447, -2.2013, 0.9026],
    [-1.5353, -2.1426, 0.9041],
    [-1.6166, -2.1334, 0.9166],
  ],
  fingers: [
    [
      [-1.1966, -2.207, 0.6519],
      [-1.0354, -1.9307, 0.5535],
      [-0.971, -1.6686, 0.4462],
      [-1.0048, -1.4755, 0.3318],
    ],
    [
      [-1.1864, -1.6453, 0.7139],
      [-1.106, -1.3165, 0.5748],
      [-1.0746, -1.1598, 0.445],
      [-1.0589, -1.0543, 0.3086],
    ],
    [
      [-1.3759, -1.6315, 0.7495],
      [-1.3107, -1.3203, 0.4897],
      [-1.2839, -1.2453, 0.2609],
      [-1.2742, -1.2633, 0.0744],
    ],
    [
      [-1.5762, -1.6386, 0.7339],
      [-1.5796, -1.2938, 0.5728],
      [-1.5417, -1.1808, 0.3691],
      [-1.4954, -1.1775, 0.1882],
    ],
    [
      [-1.7612, -1.7302, 0.6707],
      [-1.8604, -1.4773, 0.5404],
      [-1.9035, -1.3463, 0.447],
      [-1.9413, -1.2158, 0.3375],
    ],
  ],
  press: [0, 0, 0, 0, 0],
  thumbRef: [
    [-0.2323, 0.0526, 0.9712],
    [-0.1832, 0.0864, 0.9793],
    [-0.0243, 0.1953, 0.9804],
  ],
}

/** Read-only neutral pose for a hand that has no song motion to sample from. */
export function neutralHandPose(hand: 'L' | 'R'): HandPose {
  return hand === 'L' ? NEUTRAL_L : NEUTRAL_R
}
