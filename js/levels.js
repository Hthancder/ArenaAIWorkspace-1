// LUMEN level generator.
// Every level is built from a random spanning tree, so a solution always exists.
// The player rotates tiles to carry light from the source star to every beacon.

import { mulberry32, hashString, randInt, pick, shuffle } from './rng.js';

export const LEVELS_PER_CHAPTER = 60;

export const CHAPTERS = [
  {
    name: 'Khởi Nguyên', sub: 'Origins', w: 3, h: 3, fill: 1.0,
    bMin: 1, bMax: 3, locks: 0,
    accent: '#5eead4', accent2: '#22d3ee', hue: 186,
    blurb: 'Một ngôi sao, một tia sáng. Làm quen với cách xoay ô.',
  },
  {
    name: 'Ánh Sao', sub: 'Starlight', w: 4, h: 4, fill: 1.0,
    bMin: 2, bMax: 3, locks: 0,
    accent: '#7dd3fc', accent2: '#60a5fa', hue: 205,
    blurb: 'Nhiều ngôi sao hơn, nhiều hướng sáng hơn.',
  },
  {
    name: 'Dòng Chảy', sub: 'Current', w: 4, h: 4, fill: 1.0,
    bMin: 2, bMax: 3, locks: 1,
    accent: '#a78bfa', accent2: '#818cf8', hue: 252,
    blurb: 'Những ô khoá xuất hiện. Chúng đã đúng hướng — hãy dùng chúng.',
  },
  {
    name: 'Tinh Vân', sub: 'Nebula', w: 5, h: 5, fill: 0.95,
    bMin: 3, bMax: 4, locks: 1,
    accent: '#f0abfc', accent2: '#c084fc', hue: 292,
    blurb: 'Bản đồ bắt đầu loãng ra. Hãy nhìn những ô trống.',
  },
  {
    name: 'Hư Không', sub: 'Void', w: 5, h: 5, fill: 0.85,
    bMin: 3, bMax: 4, locks: 2,
    accent: '#fda4af', accent2: '#fb7185', hue: 344,
    blurb: 'Khoảng trống là một phần của câu đố.',
  },
  {
    name: 'Cực Quang', sub: 'Aurora', w: 6, h: 6, fill: 0.9,
    bMin: 3, bMax: 4, locks: 2,
    accent: '#fcd34d', accent2: '#fbbf24', hue: 43,
    blurb: 'Ánh sáng ấm hơn, nhưng cũng nhiều ngã rẽ hơn.',
  },
  {
    name: 'Thiên Hà', sub: 'Galaxy', w: 6, h: 6, fill: 0.8,
    bMin: 4, bMax: 5, locks: 3,
    accent: '#86efac', accent2: '#34d399', hue: 152,
    blurb: 'Một thiên hà thu nhỏ. Mỗi ô đều có thể là chìa khoá.',
  },
  {
    name: 'Hố Đen', sub: 'Black Hole', w: 7, h: 7, fill: 0.8,
    bMin: 4, bMax: 5, locks: 3,
    accent: '#93c5fd', accent2: '#3b82f6', hue: 219,
    blurb: 'Không gian rộng hơn. Hãy bình tĩnh và lần theo ánh sáng.',
  },
  {
    name: 'Siêu Tân', sub: 'Supernova', w: 7, h: 7, fill: 0.75,
    bMin: 4, bMax: 5, locks: 4,
    accent: '#fca5a5', accent2: '#f87171', hue: 2,
    blurb: 'Bùng nổ nhưng vẫn có trật tự. Tìm trật tự đó.',
  },
  {
    name: 'Vĩnh Cửu', sub: 'Eternity', w: 8, h: 8, fill: 0.75,
    bMin: 5, bMax: 6, locks: 4,
    accent: '#e9d5ff', accent2: '#a78bfa', hue: 272,
    blurb: 'Chặng cuối. Sáu ngôi sao, một dải ngân hà.',
  },
];

export const TOTAL_LEVELS = CHAPTERS.length * LEVELS_PER_CHAPTER;

// Direction bits: N=1, E=2, S=4, W=8
export const DIRS = [
  { bit: 1, dx: 0, dy: -1, opp: 4 },
  { bit: 2, dx: 1, dy: 0, opp: 8 },
  { bit: 4, dx: 0, dy: 1, opp: 1 },
  { bit: 8, dx: -1, dy: 0, opp: 2 },
];

export function rotateMask(mask, k) {
  k = ((k % 4) + 4) % 4;
  if (k === 0) return mask;
  return ((mask << k) | (mask >> (4 - k))) & 15;
}

export function minMoves(mask, rot) {
  let best = 4;
  for (let r = 0; r < 4; r++) {
    if (rotateMask(mask, r) === mask) {
      const d = Math.min((r - rot + 4) % 4, (rot - r + 4) % 4);
      if (d < best) best = d;
    }
  }
  return best;
}

export function getLevelConfig(index) {
  const safe = Math.max(0, Math.min(TOTAL_LEVELS - 1, index));
  const chapterIndex = Math.floor(safe / LEVELS_PER_CHAPTER);
  const inChapter = safe % LEVELS_PER_CHAPTER;
  const t = inChapter / (LEVELS_PER_CHAPTER - 1);
  const chapter = CHAPTERS[chapterIndex];
  const beacons = Math.round(chapter.bMin + (chapter.bMax - chapter.bMin) * t);
  const locks = Math.round(chapter.locks * t);
  const fill = chapter.fill - 0.06 * t;
  return {
    index: safe, chapterIndex, inChapter, t,
    w: chapter.w, h: chapter.h, beacons, locks, fill, chapter,
  };
}

function neighbors(idx, w, h) {
  const x = idx % w;
  const y = (idx / w) | 0;
  const out = [];
  if (y > 0) out.push(idx - w);
  if (x < w - 1) out.push(idx + 1);
  if (y < h - 1) out.push(idx + w);
  if (x > 0) out.push(idx - 1);
  return out;
}

function dirBetween(a, b, w) {
  if (b === a - w) return 0;
  if (b === a + 1) return 1;
  if (b === a + w) return 2;
  if (b === a - 1) return 3;
  return -1;
}

function bfs(start, adj) {
  const dist = new Map([[start, 0]]);
  const parent = new Map([[start, -1]]);
  const queue = [start];
  let head = 0;
  while (head < queue.length) {
    const cur = queue[head++];
    const d = dist.get(cur);
    for (const n of adj.get(cur)) {
      if (!dist.has(n)) {
        dist.set(n, d + 1);
        parent.set(n, cur);
        queue.push(n);
      }
    }
  }
  return { dist, parent };
}

export function computeLit(w, h, tiles) {
  const grid = new Map();
  let source = null;
  for (const t of tiles) {
    grid.set(t.y * w + t.x, t);
    if (t.role === 'source') source = t;
  }
  const lit = new Set();
  if (!source) return lit;
  const startIdx = source.y * w + source.x;
  lit.add(startIdx);
  const queue = [source];
  let head = 0;
  while (head < queue.length) {
    const t = queue[head++];
    const mask = rotateMask(t.mask, t.rot);
    for (const d of DIRS) {
      if (!(mask & d.bit)) continue;
      const nx = t.x + d.dx;
      const ny = t.y + d.dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      const ni = ny * w + nx;
      if (lit.has(ni)) continue;
      const n = grid.get(ni);
      if (!n) continue;
      const nm = rotateMask(n.mask, n.rot);
      if (nm & d.opp) {
        lit.add(ni);
        queue.push(n);
      }
    }
  }
  return lit;
}

function tryGenerate(index, cfg, attempt) {
  const rand = mulberry32(hashString(`lumen|${index}|${attempt}`));
  const { w, h } = cfg;
  const total = w * h;
  let target = Math.max(cfg.beacons + 2, Math.min(total, Math.round(total * cfg.fill)));
  // Gentle onboarding: the first few constellations are deliberately tiny.
  if (cfg.chapterIndex === 0 && cfg.inChapter < 4) target = Math.min(target, 6);

  // 1. Grow a connected blob of cells.
  const cells = new Set();
  const start = randInt(rand, total);
  cells.add(start);
  let frontier = neighbors(start, w, h);
  while (cells.size < target && frontier.length) {
    const i = randInt(rand, frontier.length);
    const c = frontier[i];
    frontier.splice(i, 1);
    if (cells.has(c)) continue;
    cells.add(c);
    for (const n of neighbors(c, w, h)) {
      if (!cells.has(n) && !frontier.includes(n)) frontier.push(n);
    }
  }
  if (cells.size < Math.max(cfg.beacons + 1, 4)) return null;

  // 2. Randomised Prim spanning tree over the blob.
  const cellArr = [...cells];
  const treeStart = pick(rand, cellArr);
  const inTree = new Set([treeStart]);
  const edges = [];
  let frontierEdges = [];
  for (const n of neighbors(treeStart, w, h)) {
    if (cells.has(n)) frontierEdges.push([treeStart, n]);
  }
  while (inTree.size < cells.size && frontierEdges.length) {
    const i = randInt(rand, frontierEdges.length);
    const [a, b] = frontierEdges[i];
    frontierEdges.splice(i, 1);
    if (inTree.has(b)) continue;
    inTree.add(b);
    edges.push([a, b]);
    for (const n of neighbors(b, w, h)) {
      if (cells.has(n) && !inTree.has(n)) frontierEdges.push([b, n]);
    }
  }
  if (inTree.size !== cells.size) return null;

  const adj = new Map(cellArr.map((i) => [i, []]));
  for (const [a, b] of edges) {
    adj.get(a).push(b);
    adj.get(b).push(a);
  }

  const masks = new Map();
  for (const i of cellArr) {
    let mask = 0;
    for (const n of adj.get(i)) {
      const d = dirBetween(i, n, w);
      if (d >= 0) mask |= DIRS[d].bit;
    }
    masks.set(i, mask);
  }

  // 3. Source is a leaf of the tree, fixed in place.
  const leaves = cellArr.filter((i) => adj.get(i).length === 1);
  const source = leaves.length ? pick(rand, leaves) : pick(rand, cellArr);

  const fromSource = bfs(source, adj);
  const distFromSource = fromSource.dist;
  const allDist = new Map(cellArr.map((i) => [i, bfs(i, adj).dist]));
  const dist = (a, b) => allDist.get(a).get(b);

  // 4. Beacons via farthest-point sampling, so they are spread out.
  const candidates = cellArr.filter((i) => i !== source);
  const beaconCount = Math.min(cfg.beacons, candidates.length);
  const beacons = [];
  let best = candidates[0];
  let bestScore = -1;
  for (const i of candidates) {
    const score = distFromSource.get(i) + (adj.get(i).length === 1 ? 0.25 : 0);
    if (score > bestScore) {
      bestScore = score;
      best = i;
    }
  }
  beacons.push(best);
  while (beacons.length < beaconCount) {
    let bestC = -1;
    let bestS = -1;
    for (const i of candidates) {
      if (beacons.includes(i)) continue;
      let d = distFromSource.get(i);
      for (const b of beacons) d = Math.min(d, dist(b, i));
      const score = d + (adj.get(i).length === 1 ? 0.25 : 0);
      if (score > bestS) {
        bestS = score;
        bestC = i;
      }
    }
    if (bestC < 0) break;
    beacons.push(bestC);
  }

  // 5. A few locked tiles (already in solution orientation) as anchors.
  const lockCandidates = shuffle(
    rand,
    cellArr.filter((i) => i !== source && !beacons.includes(i) && masks.get(i) !== 15)
  );
  const locks = new Set();
  for (const i of lockCandidates) {
    if (locks.size >= cfg.locks) break;
    if (adj.get(i).length === 2) locks.add(i);
  }
  for (const i of lockCandidates) {
    if (locks.size >= cfg.locks) break;
    locks.add(i);
  }

  // 6. Scramble every rotatable tile.
  const rots = new Map();
  for (const i of cellArr) {
    const mask = masks.get(i);
    if (i === source || locks.has(i) || mask === 15) {
      rots.set(i, 0);
      continue;
    }
    const options = [];
    for (let k = 1; k < 4; k++) {
      if (rotateMask(mask, k) !== mask) options.push(k);
    }
    rots.set(i, pick(rand, options));
  }

  // 7. Par = moves needed to orient the union of the solution paths
  //    from the source to every beacon. This is the fair "3 star" target:
  //    the player never has to fix tiles that are not on a light path.
  const required = new Set();
  for (const b of beacons) {
    let cur = b;
    let guard = 0;
    while (cur !== -1 && guard++ < total + 2) {
      required.add(cur);
      cur = fromSource.parent.get(cur);
    }
  }
  let par = 0;
  for (const i of required) {
    par += minMoves(masks.get(i), rots.get(i));
  }
  if (par <= 0) return null;

  const tiles = cellArr.map((i) => ({
    x: i % w,
    y: (i / w) | 0,
    mask: masks.get(i),
    rot: rots.get(i),
    locked: i === source || locks.has(i),
    role: i === source ? 'source' : beacons.includes(i) ? 'beacon' : 'relay',
  }));

  const initialLit = computeLit(w, h, tiles);
  if (beacons.every((b) => initialLit.has(b))) return null;

  return {
    index,
    w,
    h,
    chapterIndex: cfg.chapterIndex,
    chapter: cfg.chapter,
    inChapter: cfg.inChapter,
    t: cfg.t,
    tiles,
    source: { x: source % w, y: (source / w) | 0 },
    beacons: beacons.map((i) => ({ x: i % w, y: (i / w) | 0 })),
    par,
    accent: cfg.chapter.accent,
    accent2: cfg.chapter.accent2,
  };
}

export function generateLevel(index) {
  const cfg = getLevelConfig(index);
  for (let attempt = 0; attempt < 40; attempt++) {
    const level = tryGenerate(index, cfg, attempt);
    if (level) return level;
  }
  // Extremely defensive fallback: full grid, no locks, deterministic seed.
  const fallbackCfg = { ...cfg, fill: 1, locks: 0 };
  for (let attempt = 0; attempt < 200; attempt++) {
    const level = tryGenerate(index, fallbackCfg, 1000 + attempt);
    if (level) return level;
  }
  throw new Error(`Could not generate level ${index}`);
}

export function levelKey(index) {
  return `lumen.level.${index}`;
}
