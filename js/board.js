// SVG board renderer + rotation logic.

import { rotateMask, computeLit, DIRS } from './levels.js';

const CELL = 100;
const HALF = 42;
const SVG_NS = 'http://www.w3.org/2000/svg';

function svgEl(tag, attrs = {}) {
  const el = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v !== undefined && v !== null) el.setAttribute(k, String(v));
  }
  return el;
}

export function starPathD(cx, cy, outer, inner) {
  return [
    `M ${cx} ${cy - outer}`,
    `Q ${cx + inner} ${cy - inner} ${cx + outer} ${cy}`,
    `Q ${cx + inner} ${cy + inner} ${cx} ${cy + outer}`,
    `Q ${cx - inner} ${cy + inner} ${cx - outer} ${cy}`,
    `Q ${cx - inner} ${cy - inner} ${cx} ${cy - outer}`,
    'Z',
  ].join(' ');
}

export class Board {
  constructor(svg, level, opts = {}) {
    this.svg = svg;
    this.level = level;
    this.onRotate = opts.onRotate || (() => {});
    this.onBlocked = opts.onBlocked || (() => {});
    this.tiles = [];
    this.grid = new Map();
    this.lit = new Set();
    this.angles = new Map();
    this.dir = 1;
    this.selected = null;
  }

  build() {
    const { w, h } = this.level;
    this.svg.innerHTML = '';
    this.svg.setAttribute('viewBox', `${-6} ${-6} ${w * CELL + 12} ${h * CELL + 12}`);
    this.svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
    this.tiles = [];
    this.grid.clear();
    this.angles.clear();
    this.selected = null;

    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        this.svg.appendChild(svgEl('circle', {
          cx: x * CELL + 50,
          cy: y * CELL + 50,
          r: 1.4,
          class: 'grid-dot',
        }));
      }
    }

    for (const t of this.level.tiles) {
      const idx = t.y * w + t.x;
      const g = svgEl('g', {
        class: `tile${t.locked ? ' locked' : ''}${t.mask === 15 ? ' fixed' : ''}`,
        transform: `translate(${t.x * CELL + 50} ${t.y * CELL + 50})`,
        'data-idx': idx,
        role: 'gridcell',
        tabindex: '-1',
      });

      g.appendChild(svgEl('rect', {
        x: -HALF, y: -HALF, width: HALF * 2, height: HALF * 2, rx: 20, class: 'tile-bg',
      }));
      g.appendChild(svgEl('rect', {
        x: -HALF - 4, y: -HALF - 4, width: (HALF + 4) * 2, height: (HALF + 4) * 2, rx: 24, class: 'sel-ring',
      }));

      const rotor = svgEl('g', { class: 'rotor' });
      // invisible symmetric bounds keep transform-origin at the tile centre
      rotor.appendChild(svgEl('rect', { x: -60, y: -60, width: 120, height: 120, fill: 'none', stroke: 'none' }));
      for (const d of DIRS) {
        if (!(t.mask & d.bit)) continue;
        rotor.appendChild(svgEl('line', {
          x1: 0, y1: 0, x2: d.dx * 50, y2: d.dy * 50, class: 'pipe',
        }));
      }
      rotor.appendChild(svgEl('circle', { cx: 0, cy: 0, r: 5.5, class: 'node' }));
      g.appendChild(rotor);

      if (t.role === 'beacon') {
        g.appendChild(svgEl('circle', { cx: 0, cy: 0, r: 17, class: 'beacon-halo' }));
        g.appendChild(svgEl('path', { d: starPathD(0, 0, 17, 4.6), class: 'beacon-star' }));
      }

      if (t.role === 'source') {
        g.appendChild(svgEl('circle', { cx: 0, cy: 0, r: 16, class: 'source-glow' }));
        g.appendChild(svgEl('circle', { cx: 0, cy: 0, r: 14, class: 'source-ring' }));
        g.appendChild(svgEl('circle', { cx: 0, cy: 0, r: 8.5, class: 'source-core' }));
      }

      if (t.locked && t.role !== 'source') {
        g.appendChild(svgEl('circle', { cx: 30, cy: -30, r: 5.5, class: 'lock-mark' }));
        g.appendChild(svgEl('circle', { cx: 30, cy: -30, r: 1.5, class: 'lock-dot' }));
      }

      const title = svgEl('title');
      title.textContent = t.role === 'source'
        ? 'Nguồn sáng'
        : t.role === 'beacon'
          ? 'Ngôi sao đích'
          : t.locked
            ? 'Ô đã khoá'
            : t.mask === 15
              ? 'Ô cân xứng'
              : 'Ô xoay';
      g.appendChild(title);

      const tile = {
        ...t,
        idx,
        rot0: t.rot,
        el: g,
        rotor,
      };
      this.angles.set(idx, t.rot * 90);
      rotor.style.transform = `rotate(${t.rot * 90}deg)`;

      g.addEventListener('click', (e) => {
        e.preventDefault();
        this.rotateBy(idx, this.dir);
      });
      g.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        this.rotateBy(idx, -1);
      });

      this.tiles.push(tile);
      this.grid.set(idx, tile);
      this.svg.appendChild(g);
    }

    this.updateLit();
  }

  setDirection(dir) {
    this.dir = dir;
  }

  setSelected(idx) {
    if (this.selected !== null) {
      const prev = this.grid.get(this.selected);
      if (prev) prev.el.classList.remove('selected');
    }
    this.selected = idx;
    if (idx !== null) {
      const next = this.grid.get(idx);
      if (next) next.el.classList.add('selected');
    }
  }

  rotateBy(idx, dir, silent = false) {
    const tile = this.grid.get(idx);
    if (!tile) return null;
    if (tile.locked || tile.mask === 15) {
      this.onBlocked(tile);
      return null;
    }
    const a = this.angles.get(idx) + dir * 90;
    this.angles.set(idx, a);
    tile.rot = ((a / 90) % 4 + 4) % 4;
    tile.rotor.style.transform = `rotate(${a}deg)`;
    const newly = this.updateLit();
    if (!silent) this.onRotate(tile, dir, newly);
    return { tile, newly };
  }

  updateLit() {
    const prev = this.lit;
    const lit = computeLit(this.level.w, this.level.h, this.tiles);
    this.lit = lit;
    const newly = [];
    for (const tile of this.tiles) {
      const isLit = lit.has(tile.idx);
      tile.el.classList.toggle('lit', isLit);
      if (tile.role === 'beacon' && isLit && !prev.has(tile.idx)) newly.push(tile);
    }
    return newly;
  }

  isSolved() {
    return this.level.beacons.every((b) => this.lit.has(b.y * this.level.w + b.x));
  }

  litCount() {
    return this.level.beacons.filter((b) => this.lit.has(b.y * this.level.w + b.x)).length;
  }

  getTile(idx) {
    return this.grid.get(idx) || null;
  }

  getScreenCenter(tile) {
    const r = tile.el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }

  incorrectTiles() {
    return this.tiles.filter((t) => !t.locked && t.mask !== 15 && rotateMask(t.mask, t.rot) !== t.mask);
  }

  hintTile(idx) {
    const tile = this.grid.get(idx);
    if (!tile) return [];
    const current = this.angles.get(idx);
    let bestAngle = current;
    let bestDist = Infinity;
    for (let r = 0; r < 4; r++) {
      if (rotateMask(tile.mask, r) !== tile.mask) continue;
      const base = r * 90;
      const k = Math.round((current - base) / 360);
      const candidate = base + k * 360;
      const d = Math.abs(candidate - current);
      if (d < bestDist) {
        bestDist = d;
        bestAngle = candidate;
      }
    }
    this.angles.set(idx, bestAngle);
    tile.rot = ((bestAngle / 90) % 4 + 4) % 4;
    tile.rotor.style.transform = `rotate(${bestAngle}deg)`;
    tile.el.classList.add('hint-pulse');
    setTimeout(() => tile.el.classList.remove('hint-pulse'), 950);
    return this.updateLit();
  }

  reset() {
    this.svg.classList.add('no-anim');
    for (const tile of this.tiles) {
      const a = tile.rot0 * 90;
      this.angles.set(tile.idx, a);
      tile.rot = tile.rot0;
      tile.rotor.style.transform = `rotate(${a}deg)`;
    }
    // force style flush so the reset does not animate
    void this.svg.getBoundingClientRect();
    this.svg.classList.remove('no-anim');
    this.updateLit();
  }
}
