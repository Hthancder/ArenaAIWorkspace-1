import {
  CHAPTERS, LEVELS_PER_CHAPTER, TOTAL_LEVELS, generateLevel,
} from './levels.js';
import { Board, starPathD } from './board.js';
import { audio } from './audio.js';
import { loadSave, persist, clearSave } from './storage.js';
import { Starfield, FX } from './fx.js';

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

const save = loadSave();
const starfield = new Starfield($('#starfield'));
const fx = new FX($('#fx'));

const state = {
  screen: 'home',
  levelIndex: 0,
  level: null,
  board: null,
  moves: 0,
  hints: 3,
  undo: [],
  solved: false,
  dir: 1,
  selectedChapter: 0,
  selectedTile: null,
  toastTimer: 0,
  winTimer: 0,
};

/* ------------------------------------------------------------
   settings / accent
   ------------------------------------------------------------ */

function applyAccent(chapter) {
  const root = document.documentElement;
  root.style.setProperty('--accent', chapter.accent);
  root.style.setProperty('--accent-2', chapter.accent2);
}

function applySettings() {
  audio.enabled = save.settings.sound;
  document.body.classList.toggle('muted', !save.settings.sound);
  document.documentElement.classList.toggle('reduce-motion', !save.settings.motion);
  starfield.setMotion(save.settings.motion);
  fx.setMotion(save.settings.motion);
  $('#screen-game').classList.toggle('zen', save.settings.zen);
}

/* ------------------------------------------------------------
   progress helpers
   ------------------------------------------------------------ */

function totalStars() {
  return Object.values(save.progress).reduce((sum, p) => sum + (p.stars || 0), 0);
}

function completedCount() {
  return Object.values(save.progress).filter((p) => p.stars > 0).length;
}

function chapterStars(ci) {
  let sum = 0;
  for (let i = 0; i < LEVELS_PER_CHAPTER; i++) {
    sum += save.progress[ci * LEVELS_PER_CHAPTER + i]?.stars || 0;
  }
  return sum;
}

function continueTarget() {
  let last = Number.isInteger(save.lastLevel) ? save.lastLevel : 0;
  last = Math.max(0, Math.min(TOTAL_LEVELS - 1, last));
  const solved = (save.progress[last]?.stars || 0) > 0;
  return solved ? Math.min(TOTAL_LEVELS - 1, last + 1) : last;
}

/* ------------------------------------------------------------
   screens
   ------------------------------------------------------------ */

function showScreen(name) {
  state.screen = name;
  $$('.screen').forEach((s) => s.classList.toggle('active', s.id === `screen-${name}`));
  if (name === 'home') renderHome();
  if (name === 'levels') renderLevelSelect(state.selectedChapter);
}

function renderHome() {
  const stars = totalStars();
  const done = completedCount();
  $('#home-stars').textContent = String(stars);
  $('#home-done').textContent = String(done);
  const target = continueTarget();
  const chapter = CHAPTERS[Math.floor(target / LEVELS_PER_CHAPTER)];
  $('#continue-label').textContent = done === 0 ? 'Bắt đầu' : done >= TOTAL_LEVELS ? 'Chơi lại' : 'Chơi tiếp';
  $('#continue-meta').textContent = `Màn ${target + 1} · ${chapter.name}`;
  applyAccent(chapter);
}

function renderLevelSelect(ci) {
  state.selectedChapter = Math.max(0, Math.min(CHAPTERS.length - 1, ci));
  const chapter = CHAPTERS[state.selectedChapter];
  applyAccent(chapter);
  $('#levels-total').textContent = `${totalStars()} / ${TOTAL_LEVELS * 3} ★`;

  const tabs = $('#chapter-tabs');
  tabs.innerHTML = '';
  CHAPTERS.forEach((ch, i) => {
    const btn = document.createElement('button');
    btn.className = `chapter-tab${i === state.selectedChapter ? ' active' : ''}`;
    btn.style.setProperty('--tab-color', ch.accent);
    btn.setAttribute('role', 'tab');
    btn.setAttribute('aria-selected', String(i === state.selectedChapter));
    btn.innerHTML = `<span class="tab-dot"></span><span>${i + 1}. ${ch.name}</span><span class="tab-count">${chapterStars(i)}/180</span>`;
    btn.addEventListener('click', () => {
      audio.click();
      renderLevelSelect(i);
    });
    tabs.appendChild(btn);
  });

  $('#chapter-kicker').textContent = `Chương ${state.selectedChapter + 1} · ${chapter.sub}`;
  $('#chapter-name').textContent = chapter.name;
  $('#chapter-blurb').textContent = chapter.blurb;
  const stars = chapterStars(state.selectedChapter);
  $('#chapter-stars').textContent = String(stars);
  const pct = Math.round((stars / (LEVELS_PER_CHAPTER * 3)) * 100);
  $('#chapter-pct').textContent = `${pct}%`;
  $('#chapter-ring-fill').style.strokeDashoffset = String(113.1 * (1 - stars / (LEVELS_PER_CHAPTER * 3)));

  const grid = $('#level-grid');
  grid.innerHTML = '';
  const start = state.selectedChapter * LEVELS_PER_CHAPTER;
  const current = continueTarget();
  for (let i = 0; i < LEVELS_PER_CHAPTER; i++) {
    const idx = start + i;
    const s = save.progress[idx]?.stars || 0;
    const btn = document.createElement('button');
    btn.className = `level-cell${s ? ' done' : ''}${idx === current ? ' current' : ''}`;
    btn.setAttribute('aria-label', `Màn ${idx + 1}${s ? `, ${s} sao` : ''}`);
    btn.innerHTML = `<span class="num">${idx + 1}</span><span class="mini-stars">${[0, 1, 2].map((k) => `<span class="${k < s ? 'on' : ''}">★</span>`).join('')}</span>`;
    btn.addEventListener('click', () => {
      audio.click();
      startLevel(idx);
    });
    grid.appendChild(btn);
  }
}

/* ------------------------------------------------------------
   game lifecycle
   ------------------------------------------------------------ */

function startLevel(index) {
  clearTimeout(state.winTimer);
  const idx = Math.max(0, Math.min(TOTAL_LEVELS - 1, index));
  state.levelIndex = idx;
  state.level = generateLevel(idx);
  state.moves = 0;
  state.hints = 3;
  state.undo = [];
  state.solved = false;
  state.selectedTile = null;

  applyAccent(state.level.chapter);
  save.lastLevel = idx;
  persist(save);

  const board = new Board($('#board'), state.level, {
    onRotate: handleRotate,
    onBlocked: handleBlocked,
  });
  board.setDirection(state.dir);
  board.build();
  state.board = board;

  $('#game-chapter').textContent = `Chương ${state.level.chapterIndex + 1} · ${state.level.chapter.name}`;
  $('#game-level').textContent = `Màn ${idx + 1}`;
  $('#moves-val').textContent = '0';
  $('#par-val').textContent = String(state.level.par);
  $('#hint-count').textContent = String(state.hints);
  $('#btn-undo').disabled = true;
  $('#btn-hint').disabled = false;
  $('#board-wrap').classList.remove('solved');
  $('#btn-next').hidden = true;
  $('#coach').classList.toggle('show', idx === 0 && !save.seenHowTo);

  renderBeaconMeter([]);
  updateProgress();
  closeModal();
  showScreen('game');
  $('#screen-game').scrollTop = 0;
}

function handleRotate(tile, dir, newly) {
  state.moves++;
  state.undo.push({ idx: tile.idx, dir });
  const mv = $('#moves-val');
  mv.textContent = String(state.moves);
  mv.classList.remove('bump');
  void mv.offsetWidth;
  mv.classList.add('bump');
  $('#btn-undo').disabled = false;
  $('#coach').classList.remove('show');

  audio.rotate(tile.x, tile.y);
  if (save.settings.haptics && navigator.vibrate) navigator.vibrate(8);

  if (newly.length) {
    audio.connect();
    newly.forEach((t) => {
      const p = state.board.getScreenCenter(t);
      fx.burst(p.x, p.y, '#fcd34d', 16);
    });
    if (save.settings.haptics && navigator.vibrate) navigator.vibrate([10, 30, 12]);
  }

  renderBeaconMeter(newly);
  updateProgress();
  checkWin();
}

function handleBlocked(tile) {
  audio.blocked();
  if (tile.role === 'source') showToast('Đây là nguồn sáng — nó luôn đúng hướng.');
  else if (tile.mask === 15) showToast('Ô này có 4 hướng, xoay cũng không thay đổi.');
  else showToast('Ô này đã khoá, không thể xoay.');
}

function renderBeaconMeter(newly = []) {
  const meter = $('#beacon-meter');
  const w = state.level.w;
  const lit = state.board.lit;
  meter.innerHTML = '';
  state.level.beacons.forEach((b) => {
    const idx = b.y * w + b.x;
    const isLit = lit.has(idx);
    const just = newly.some((t) => t.idx === idx);
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', starPathD(12, 12, 9.5, 2.8));
    path.setAttribute('class', `bm-star${isLit ? ' lit' : ''}${just ? ' just-lit' : ''}`);
    svg.appendChild(path);
    meter.appendChild(svg);
  });
}

function updateProgress() {
  const total = state.level.beacons.length;
  const count = state.board.litCount();
  $('#progress-fill').style.width = `${(count / total) * 100}%`;
  const note = $('#foot-note');
  if (count >= total) note.textContent = 'Hoàn thành! Mọi ngôi sao đã sáng.';
  else note.textContent = `Đã thắp ${count}/${total} ngôi sao. Tiếp tục nhé.`;
}

function calcStars() {
  const par = state.level.par;
  if (state.moves <= par + 1) return 3;
  if (state.moves <= par + Math.max(3, Math.ceil(par * 0.75))) return 2;
  return 1;
}

function checkWin() {
  if (state.solved || !state.board.isSolved()) return;
  state.solved = true;
  $('#board-wrap').classList.add('solved');
  const stars = calcStars();
  const prev = save.progress[state.levelIndex] || { stars: 0 };
  save.progress[state.levelIndex] = {
    stars: Math.max(prev.stars || 0, stars),
    best: Math.min(prev.best || Infinity, state.moves),
  };
  persist(save);

  audio.win();
  if (save.settings.haptics && navigator.vibrate) navigator.vibrate([16, 40, 16, 40, 26]);
  fx.confetti([state.level.accent, state.level.accent2, '#fcd34d', '#ffffff']);

  $('#btn-next').hidden = false;
  const next = state.levelIndex + 1;
  if (next < TOTAL_LEVELS) {
    const nextChapter = CHAPTERS[Math.floor(next / LEVELS_PER_CHAPTER)];
    $('#next-meta').textContent = `Màn ${next + 1} · ${nextChapter.name}`;
  } else {
    $('#next-meta').textContent = 'Bạn đã hoàn thành tất cả';
  }

  clearTimeout(state.winTimer);
  state.winTimer = setTimeout(() => showWinModal(stars), 560);
}

/* ------------------------------------------------------------
   actions
   ------------------------------------------------------------ */

function undo() {
  if (!state.board || state.solved || !state.undo.length) return;
  const last = state.undo.pop();
  state.board.rotateBy(last.idx, -last.dir, true);
  state.moves = Math.max(0, state.moves - 1);
  $('#moves-val').textContent = String(state.moves);
  $('#btn-undo').disabled = state.undo.length === 0;
  $('#coach').classList.remove('show');
  audio.click();
  renderBeaconMeter([]);
  updateProgress();
}

function solutionPathTiles() {
  const { w, tiles, source, beacons } = state.level;
  const adj = new Map();
  for (const t of tiles) {
    const list = [];
    if (t.mask & 1) list.push([t.x, t.y - 1]);
    if (t.mask & 2) list.push([t.x + 1, t.y]);
    if (t.mask & 4) list.push([t.x, t.y + 1]);
    if (t.mask & 8) list.push([t.x - 1, t.y]);
    adj.set(t.y * w + t.x, list.map(([x, y]) => y * w + x));
  }
  const src = source.y * w + source.x;
  const parent = new Map([[src, -1]]);
  const queue = [src];
  for (let head = 0; head < queue.length; head++) {
    for (const n of adj.get(queue[head]) || []) {
      if (!parent.has(n)) {
        parent.set(n, queue[head]);
        queue.push(n);
      }
    }
  }
  const path = new Set();
  for (const b of beacons) {
    let cur = b.y * w + b.x;
    let guard = 0;
    while (cur !== -1 && cur !== undefined && !path.has(cur) && guard++ < w * 4 + 8) {
      path.add(cur);
      cur = parent.get(cur);
    }
  }
  return path;
}

function hint() {
  if (!state.board || state.solved) return;
  if (state.hints <= 0) {
    showToast('Bạn đã dùng hết gợi ý cho màn này.');
    return;
  }
  const candidates = state.board.incorrectTiles();
  if (!candidates.length) {
    showToast('Mọi ô đã đúng hướng.');
    return;
  }
  const path = solutionPathTiles();
  const preferred = candidates.filter((t) => path.has(t.idx));
  const pool = preferred.length ? preferred : candidates;
  const target = pool[Math.floor(Math.random() * pool.length)];
  const newly = state.board.hintTile(target.idx);
  state.hints--;
  $('#hint-count').textContent = String(state.hints);
  if (state.hints <= 0) $('#btn-hint').disabled = true;
  audio.hint();
  if (newly.length) {
    audio.connect();
    newly.forEach((t) => {
      const p = state.board.getScreenCenter(t);
      fx.burst(p.x, p.y, '#fcd34d', 14);
    });
  }
  renderBeaconMeter(newly);
  updateProgress();
  showToast('Đã xoay một ô về đúng hướng.');
  checkWin();
}

function restart() {
  if (!state.board) return;
  state.board.reset();
  state.moves = 0;
  state.hints = 3;
  state.undo = [];
  state.solved = false;
  $('#moves-val').textContent = '0';
  $('#hint-count').textContent = '3';
  $('#btn-hint').disabled = false;
  $('#btn-undo').disabled = true;
  $('#board-wrap').classList.remove('solved');
  $('#btn-next').hidden = true;
  renderBeaconMeter([]);
  updateProgress();
  closeModal();
  audio.click();
  showToast('Đã chơi lại màn này.');
}

function setDir(dir) {
  state.dir = dir;
  state.board?.setDirection(dir);
  $('#dir-cw').classList.toggle('active', dir === 1);
  $('#dir-ccw').classList.toggle('active', dir === -1);
}

function toggleDir() {
  setDir(-state.dir);
  audio.click();
  showToast(state.dir === 1 ? 'Xoay theo chiều kim đồng hồ' : 'Xoay ngược chiều kim đồng hồ');
}

function nextLevel() {
  closeModal();
  if (state.levelIndex >= TOTAL_LEVELS - 1) {
    state.selectedChapter = CHAPTERS.length - 1;
    renderLevelSelect(state.selectedChapter);
    showScreen('levels');
    showToast('Bạn đã hoàn thành 600 màn. Cảm ơn bạn!');
    return;
  }
  startLevel(state.levelIndex + 1);
}

function backToLevels() {
  closeModal();
  state.selectedChapter = Math.floor(state.levelIndex / LEVELS_PER_CHAPTER);
  renderLevelSelect(state.selectedChapter);
  showScreen('levels');
}

function toggleSound() {
  save.settings.sound = !save.settings.sound;
  persist(save);
  applySettings();
  if (save.settings.sound) audio.click();
  showToast(save.settings.sound ? 'Đã bật âm thanh' : 'Đã tắt âm thanh');
}

/* ------------------------------------------------------------
   modals
   ------------------------------------------------------------ */

function openModal(html, opts = {}) {
  const root = $('#modal-root');
  root.innerHTML = `<div class="modal" role="dialog" aria-modal="true">${html}</div>`;
  root.classList.add('open');
  root.onclick = (e) => {
    if (e.target === root && opts.dismissible !== false) closeModal();
  };
  root.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', closeModal));
}

function closeModal() {
  const root = $('#modal-root');
  root.classList.remove('open');
  root.innerHTML = '';
  root.onclick = null;
}

function showToast(msg) {
  const toast = $('#toast');
  if (toast.textContent === msg && toast.classList.contains('show')) return;
  toast.textContent = msg;
  toast.classList.add('show');
  clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => toast.classList.remove('show'), 2300);
}

const ICON_ROTATE = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="5" width="14" height="14" rx="3.5"/><path d="M9 12h6"/><path d="M20 8a8 8 0 0 1-2 8" opacity=".55"/><path d="M18 4v4h-4" opacity=".55"/></svg>`;
const ICON_LINK = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M12 3l1.8 3.9L18 8.7l-4.2 1.8L12 14.4l-1.8-3.9L6 8.7l4.2-1.8L12 3z" fill="currentColor" fill-opacity=".18"/><circle cx="5" cy="18" r="2.2"/><circle cx="19" cy="18" r="2.2"/><path d="M7 17.2C9 14 15 14 17 17.2"/></svg>`;
const ICON_STAR = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M12 3l2.6 5.6 6.1.7-4.5 4.1 1.2 6-5.4-3-5.4 3 1.2-6L3.3 9.3l6.1-.7L12 3z" fill="currentColor" fill-opacity=".18"/></svg>`;

function openHowTo() {
  const html = `
    <button class="modal-close" data-close aria-label="Đóng">×</button>
    <div class="modal-kicker">Cách chơi</div>
    <h2>Nối ánh sáng</h2>
    <p>Mỗi màn là một chòm sao. Đưa ánh sáng từ ngôi sao nguồn đến mọi ngôi sao đích.</p>
    <div class="how-list">
      <div class="how-item">
        <div class="how-icon">${ICON_ROTATE}</div>
        <div class="how-copy"><strong>1. Xoay các ô</strong><span>Nhấn vào một ô để xoay 90°. Dùng nút ↻ / ↺ để chọn chiều xoay, hoặc nhấn chuột phải để xoay ngược.</span></div>
      </div>
      <div class="how-item">
        <div class="how-icon">${ICON_LINK}</div>
        <div class="how-copy"><strong>2. Nối đường sáng</strong><span>Ô nào được nối với nguồn sẽ sáng lên. Hãy xoay để ánh sáng chảy tới các ngôi sao đích.</span></div>
      </div>
      <div class="how-item">
        <div class="how-icon">${ICON_STAR}</div>
        <div class="how-copy"><strong>3. Nhận 3 sao</strong><span>Giải trong số nước đi tối ưu (hoặc chỉ hơn 1 nước) để nhận 3 sao. Không có giới hạn thời gian.</span></div>
      </div>
    </div>
    <div class="how-tip"><b>Mẹo:</b> Bắt đầu từ ngôi sao nguồn và lần theo những ô đang sáng. Ô có khoanh tròn nhỏ là ô đã khoá, không cần xoay.</div>
    <div class="modal-actions">
      <button class="btn btn-primary" data-close><span class="btn-text"><span class="btn-label">Đã hiểu</span><span class="btn-meta">Chơi thôi</span></span><span class="btn-arrow">→</span></button>
    </div>
  `;
  openModal(html);
  save.seenHowTo = true;
  persist(save);
}

function openSettings() {
  const rows = [
    ['sound', 'Âm thanh', 'Những nốt nhạc nhẹ khi xoay ô và thắp sáng ngôi sao.'],
    ['motion', 'Chuyển động', 'Sao, mây và hiệu ứng. Tắt để giảm kích thích.'],
    ['zen', 'Chế độ Zen', 'Ẩn bộ đếm nước đi và mức tối ưu.'],
    ['haptics', 'Rung', 'Phản hồi xúc giác trên thiết bị hỗ trợ.'],
  ];
  const html = `
    <button class="modal-close" data-close aria-label="Đóng">×</button>
    <div class="modal-kicker">Cài đặt</div>
    <h2>Chỉnh cho vừa bạn</h2>
    <p>LUMEN không có đồng hồ và không có thất bại. Chơi theo cách của bạn.</p>
    <div style="margin-top:12px">
      ${rows.map(([key, title, desc]) => `
        <div class="setting-row">
          <div class="setting-copy"><strong>${title}</strong><span>${desc}</span></div>
          <button class="switch" data-setting="${key}" aria-pressed="${save.settings[key] ? 'true' : 'false'}" aria-label="${title}"></button>
        </div>`).join('')}
    </div>
    <div class="modal-actions">
      <button class="btn-soft btn-danger" id="reset-progress">Xoá toàn bộ tiến trình</button>
    </div>
  `;
  openModal(html);
  $('#modal-root').querySelectorAll('[data-setting]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const key = btn.dataset.setting;
      save.settings[key] = !save.settings[key];
      btn.setAttribute('aria-pressed', save.settings[key] ? 'true' : 'false');
      persist(save);
      applySettings();
      if (key === 'sound' && save.settings.sound) audio.click();
    });
  });
  $('#reset-progress').addEventListener('click', openConfirmReset);
}

function openConfirmReset() {
  const html = `
    <div class="modal-kicker">Xác nhận</div>
    <h2>Xoá toàn bộ tiến trình?</h2>
    <p>Toàn bộ số sao và kỷ lục sẽ bị xoá. Không thể hoàn tác.</p>
    <div class="modal-actions-row">
      <button class="btn-soft" data-close>Giữ lại</button>
      <button class="btn-soft btn-danger" id="confirm-reset">Xoá hết</button>
    </div>
  `;
  openModal(html, { dismissible: false });
  $('#confirm-reset').addEventListener('click', () => {
    clearSave();
    save.progress = {};
    save.lastLevel = 0;
    save.seenHowTo = false;
    persist(save);
    closeModal();
    renderHome();
    showToast('Đã xoá tiến trình.');
  });
}

function showWinModal(stars) {
  const next = state.levelIndex + 1;
  const hasNext = next < TOTAL_LEVELS;
  const nextChapterIndex = hasNext ? Math.floor(next / LEVELS_PER_CHAPTER) : -1;
  const chapterChange = hasNext && nextChapterIndex !== state.level.chapterIndex;
  const best = save.progress[state.levelIndex]?.best;
  const title = stars === 3 ? 'Hoàn hảo!' : stars === 2 ? 'Rất tốt!' : 'Đã xong!';
  const sub = stars === 3
    ? 'Bạn đã tìm ra con đường ngắn nhất.'
    : stars === 2
      ? 'Chỉ cần một chút nữa là hoàn hảo.'
      : 'Mỗi ngôi sao đều đã được thắp sáng.';
  const starSvg = (on) => `<svg class="win-star${on ? ' on' : ''}" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2.6l2.7 5.9 6.4.7-4.8 4.3 1.3 6.3L12 16.6 6.4 19.8l1.3-6.3L2.9 9.2l6.4-.7L12 2.6z"/></svg>`;
  const html = `
    <button class="modal-close" data-close aria-label="Đóng">×</button>
    <div class="win-stars">${starSvg(stars >= 1)}${starSvg(stars >= 2)}${starSvg(stars >= 3)}</div>
    <div class="win-title">
      <div class="modal-kicker">Màn ${state.levelIndex + 1} hoàn thành</div>
      <h2>${title}</h2>
      <p class="win-sub">${sub}</p>
    </div>
    <div class="win-stats">
      <div class="win-stat"><span>Nước đi</span><strong>${state.moves}</strong></div>
      <div class="win-stat"><span>Tối ưu</span><strong>${state.level.par}</strong></div>
      <div class="win-stat"><span>Kỷ lục</span><strong>${best ?? state.moves}</strong></div>
    </div>
    <div class="win-next">${hasNext
      ? (chapterChange
        ? `Chương tiếp theo: <strong>${CHAPTERS[nextChapterIndex].name}</strong>`
        : `Tiếp theo: <strong>Màn ${next + 1}</strong>`)
      : 'Bạn đã hoàn thành <strong>600 màn</strong> của LUMEN.'}</div>
    <div class="modal-actions">
      ${hasNext ? `<button class="btn btn-primary" id="win-next"><span class="btn-text"><span class="btn-label">Màn tiếp</span><span class="btn-meta">Màn ${next + 1} · ${CHAPTERS[nextChapterIndex].name}</span></span><span class="btn-arrow">→</span></button>` : ''}
      <div class="modal-actions-row">
        <button class="btn-soft" id="win-replay">Chơi lại</button>
        <button class="btn-soft" id="win-levels">Chọn màn</button>
      </div>
    </div>
  `;
  openModal(html);
  $('#win-next')?.addEventListener('click', nextLevel);
  $('#win-replay').addEventListener('click', () => {
    closeModal();
    startLevel(state.levelIndex);
  });
  $('#win-levels').addEventListener('click', () => {
    closeModal();
    backToLevels();
  });
}

/* ------------------------------------------------------------
   keyboard
   ------------------------------------------------------------ */

function moveSelection(dx, dy) {
  const board = state.board;
  const w = state.level.w;
  const h = state.level.h;
  let cur = state.selectedTile;
  if (cur === null) {
    const src = state.level.tiles.find((t) => t.role === 'source') || state.level.tiles[0];
    cur = src.y * w + src.x;
  } else {
    let x = cur % w;
    let y = Math.floor(cur / w);
    for (let step = 0; step < Math.max(w, h); step++) {
      x += dx;
      y += dy;
      if (x < 0 || y < 0 || x >= w || y >= h) break;
      const idx = y * w + x;
      if (board.grid.has(idx)) {
        cur = idx;
        break;
      }
    }
  }
  state.selectedTile = cur;
  board.setSelected(cur);
  audio.click();
}

function onKeyDown(e) {
  if (state.screen !== 'game' || !state.board) return;
  const modalOpen = $('#modal-root').classList.contains('open');
  if (modalOpen) {
    if (e.key === 'Escape') closeModal();
    return;
  }
  if (e.key === 'Escape') {
    backToLevels();
    return;
  }
  const k = e.key.toLowerCase();
  if (k === 'q') { toggleDir(); return; }
  if (k === 'u') { undo(); return; }
  if (k === 'h') { hint(); return; }
  if (k === 'r') { restart(); return; }
  const moves = {
    arrowup: [0, -1], arrowdown: [0, 1], arrowleft: [-1, 0], arrowright: [1, 0],
  };
  if (moves[k]) {
    e.preventDefault();
    moveSelection(moves[k][0], moves[k][1]);
    return;
  }
  if (k === ' ' || k === 'enter') {
    e.preventDefault();
    if (state.selectedTile !== null) {
      state.board.rotateBy(state.selectedTile, state.dir);
    } else {
      const first = state.board.tiles[0];
      if (first) {
        state.selectedTile = first.idx;
        state.board.setSelected(first.idx);
      }
    }
  }
}

/* ------------------------------------------------------------
   wiring
   ------------------------------------------------------------ */

function bindEvents() {
  $('#btn-continue').addEventListener('click', () => {
    audio.ensure();
    audio.click();
    startLevel(continueTarget());
  });
  $('#btn-levels').addEventListener('click', () => {
    audio.click();
    state.selectedChapter = Math.floor(continueTarget() / LEVELS_PER_CHAPTER);
    renderLevelSelect(state.selectedChapter);
    showScreen('levels');
  });
  $('#btn-how').addEventListener('click', () => {
    audio.click();
    openHowTo();
  });
  $('#btn-home-settings').addEventListener('click', () => {
    audio.click();
    openSettings();
  });
  $('#btn-levels-back').addEventListener('click', () => {
    audio.click();
    showScreen('home');
  });
  $('#btn-game-back').addEventListener('click', () => {
    audio.click();
    backToLevels();
  });
  $('#btn-game-sound').addEventListener('click', toggleSound);
  $('#dir-cw').addEventListener('click', () => { setDir(1); audio.click(); });
  $('#dir-ccw').addEventListener('click', () => { setDir(-1); audio.click(); });
  $('#btn-undo').addEventListener('click', undo);
  $('#btn-hint').addEventListener('click', hint);
  $('#btn-restart').addEventListener('click', restart);
  $('#btn-next').addEventListener('click', nextLevel);
  document.addEventListener('keydown', onKeyDown);
  document.addEventListener('pointerdown', () => audio.ensure(), { once: true });
}

function init() {
  applyAccent(CHAPTERS[0]);
  applySettings();
  bindEvents();
  renderHome();
  showScreen('home');
}

init();
