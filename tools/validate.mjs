import {
  generateLevel, computeLit, rotateMask, TOTAL_LEVELS, CHAPTERS, LEVELS_PER_CHAPTER,
} from '../js/levels.js';

let bad = 0;
const stats = [];
const parByChapter = CHAPTERS.map(() => []);
const sizeByChapter = CHAPTERS.map(() => new Set());

for (let i = 0; i < TOTAL_LEVELS; i++) {
  const lv = generateLevel(i);
  const errs = [];
  const idx = (x, y) => y * lv.w + x;

  if (lv.tiles.length < 4) errs.push('too few tiles');
  if (!lv.tiles.some((t) => t.role === 'source')) errs.push('no source');
  if (lv.beacons.length < 1) errs.push('no beacons');
  if (lv.par <= 0) errs.push('par <= 0');

  // Solution: every tile at rotation 0 must light every beacon.
  const solved = lv.tiles.map((t) => ({ ...t, rot: 0 }));
  const solvedLit = computeLit(lv.w, lv.h, solved);
  for (const b of lv.beacons) {
    if (!solvedLit.has(idx(b.x, b.y))) errs.push('solution does not light beacon');
  }

  // Initial state must not already be solved.
  const initialLit = computeLit(lv.w, lv.h, lv.tiles);
  if (lv.beacons.every((b) => initialLit.has(idx(b.x, b.y)))) errs.push('starts solved');

  // Source must be fixed.
  const src = lv.tiles.find((t) => t.role === 'source');
  if (!src || !src.locked) errs.push('source not locked');

  // Every beacon must be a tile.
  for (const b of lv.beacons) {
    if (!lv.tiles.some((t) => t.x === b.x && t.y === b.y)) errs.push('beacon not on tile');
  }

  // Connectivity sanity: all tiles reachable in solution graph.
  if (solvedLit.size !== lv.tiles.length) errs.push(`solution lights ${solvedLit.size}/${lv.tiles.length}`);

  // Check that par is achievable: orient the union of solution paths.
  const byIdx = new Map(lv.tiles.map((t) => [idx(t.x, t.y), t]));
  const adj = new Map();
  for (const t of lv.tiles) {
    const m = t.mask;
    const list = [];
    if (m & 1) list.push([t.x, t.y - 1]);
    if (m & 2) list.push([t.x + 1, t.y]);
    if (m & 4) list.push([t.x, t.y + 1]);
    if (m & 8) list.push([t.x - 1, t.y]);
    adj.set(idx(t.x, t.y), list.map(([x, y]) => idx(x, y)));
  }
  const srcIdx = idx(lv.source.x, lv.source.y);
  const parent = new Map([[srcIdx, -1]]);
  const q = [srcIdx];
  for (let h = 0; h < q.length; h++) {
    for (const n of adj.get(q[h])) {
      if (!parent.has(n)) { parent.set(n, q[h]); q.push(n); }
    }
  }
  const required = new Set();
  for (const b of lv.beacons) {
    let cur = idx(b.x, b.y);
    while (cur !== -1 && !required.has(cur)) {
      required.add(cur);
      cur = parent.get(cur);
    }
  }
  let achievable = 0;
  for (const i of required) {
    const t = byIdx.get(i);
    let best = 4;
    for (let r = 0; r < 4; r++) {
      if (rotateMask(t.mask, r) === t.mask) {
        const d = Math.min((r - t.rot + 4) % 4, (t.rot - r + 4) % 4);
        best = Math.min(best, d);
      }
    }
    achievable += best;
  }
  if (achievable !== lv.par) errs.push(`par mismatch ${lv.par} vs ${achievable}`);

  if (errs.length) {
    bad++;
    if (bad <= 15) console.log(`✗ level ${i + 1}:`, [...new Set(errs)].join(', '));
  }

  const ci = lv.chapterIndex;
  parByChapter[ci].push(lv.par);
  sizeByChapter[ci].add(lv.tiles.length);
  stats.push({ i, par: lv.par, tiles: lv.tiles.length, beacons: lv.beacons.length, locks: lv.tiles.filter((t) => t.locked && t.role !== 'source').length });
}

console.log('\n=== SUMMARY ===');
console.log(`levels: ${TOTAL_LEVELS}, invalid: ${bad}`);
for (let c = 0; c < CHAPTERS.length; c++) {
  const arr = parByChapter[c];
  const avg = arr.reduce((a, b) => a + b, 0) / arr.length;
  console.log(
    `ch${c + 1} ${CHAPTERS[c].name.padEnd(12)} tiles=${[...sizeByChapter[c]].sort((a,b)=>a-b).join('/')} par avg=${avg.toFixed(1)} min=${Math.min(...arr)} max=${Math.max(...arr)}`
  );
}
const sample = [0, 1, 2, 59, 60, 61, 119, 300, 450, 599];
for (const i of sample) {
  const s = stats[i];
  console.log(`level ${i + 1}: ${s.tiles} tiles, ${s.beacons} beacons, ${s.locks} locks, par ${s.par}`);
}
if (bad > 0) process.exit(1);
