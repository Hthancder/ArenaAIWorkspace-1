import { clamp, finite } from './core.mjs';
import { colorValue, ESP_PALETTE } from './esp.mjs';

export const DEFAULTS = Object.freeze({
  version: 1, aim: false, smoothEnabled: true, smooth: 50, knocked: false, sticky: true,
  showDot: true, fov: 100, showFov: true, wallcheck: true, predict: true,
  melee: false, autoMelee: false, autoSwitch: false, useOneGun: false, layerSpoofer: false, layerKey: 'KeyT', semi: false, xray: false, darkerSmokes: true, ceilings: true, mapHighlights: false, smallerTrees: true,
  smokeOpacity: 50, treeOpacity: 50, esp: false, nametags: true, lines: true,
  espShowAllies: true, espShowEnemies: true, espShowUnknown: true, espShowDowned: true,
  espSameLayerOnly: false, espLabels: true, espDistance: true, espWeapons: false,
  espMarkers: true, espOffscreen: false, espHighlightTarget: true, espLegend: true,
  espMaxDistance: 200, espFontSize: 12, espOpacity: 85, espLineWidth: 1.5,
  espEnemyColor: ESP_PALETTE.enemy, espAllyColor: ESP_PALETTE.ally,
  espUnknownColor: ESP_PALETTE.unknown, espTargetColor: ESP_PALETTE.target,
  ownFlashlight: false, othersFlashlight: false, bulletTrajectory: false, grenadeTrajectory: false, grenadeZones: false, zoom: false, zoomFactor: 1.5,
  autoLoot: false, lootMode: 'nearby', mobileMovement: false, movementSmooth: 50, menuKey: 'ShiftRight', aimKey: 'KeyB', stickyKey: 'KeyN', holdAim: false,
});
export const STORAGE_KEY = 'duality-reborn.config.v1';
const ranges = { movementSmooth: [0, 100], smooth: [0, 100], fov: [50, 400], smokeOpacity: [0, 100], treeOpacity: [0, 100], zoomFactor: [1, 3], espMaxDistance: [10, 500], espFontSize: [10, 18], espOpacity: [10, 100], espLineWidth: [.5, 3] };
const colors = new Set(['espEnemyColor', 'espAllyColor', 'espUnknownColor', 'espTargetColor']);
export function normalizeConfig(saved) {
  const result = { ...DEFAULTS };
  if (!saved || typeof saved !== 'object' || Array.isArray(saved)) return result;
  for (const [key, defaultValue] of Object.entries(DEFAULTS)) {
    const value = saved[key];
    if (typeof defaultValue === 'boolean' && typeof value === 'boolean') result[key] = value;
    if (colors.has(key) && colorValue(value)) result[key] = value.toLowerCase();
    if (ranges[key] && finite(value)) result[key] = clamp(value, ...ranges[key]);
    if (['menuKey', 'aimKey', 'stickyKey', 'layerKey'].includes(key) && typeof value === 'string'
      && /^(Key[A-Z]|Digit[0-9]|Shift(Left|Right)|Control(Left|Right)|Alt(Left|Right)|F([1-9]|1[0-2]))$/.test(value)) result[key] = value;
  }
  if (['nearby', 'mobile'].includes(saved.lootMode)) result.lootMode = saved.lootMode;
  result.version = 1;
  return result;
}
export function loadConfig(storage) {
  try { return normalizeConfig(JSON.parse(storage.getItem(STORAGE_KEY))); }
  catch { return { ...DEFAULTS }; }
}

const CSS = `
:host{all:initial;position:fixed;inset:0;z-index:2147483646;pointer-events:none;color:#eaf6ff;font:13px system-ui,sans-serif}
*{box-sizing:border-box}button,input,select{font:inherit}select{max-width:200px;color:inherit;background:#17334c;border:1px solid #365168;padding:5px}button{cursor:pointer;color:inherit;background:#17334c;border:1px solid #365168;border-radius:5px;padding:7px 10px}button:hover{background:#23425b}button:disabled,input:disabled,select:disabled{cursor:not-allowed;opacity:.45}button:focus-visible,input:focus-visible,select:focus-visible{outline:2px solid #7dc5ff;outline-offset:2px}
canvas{position:fixed;inset:0;pointer-events:none}#ui{position:fixed;left:24px;top:24px;display:flex;width:720px;max-width:calc(100vw - 24px);max-height:85vh;border:1px solid #365168;border-radius:10px;background:#0c2335;pointer-events:auto;overflow:hidden}
.sidebar{width:180px;flex-shrink:0;padding:16px;background:#102a40;display:flex;flex-direction:column;gap:10px}.brand{font-weight:750;padding:6px 0 16px;cursor:move;touch-action:none;user-select:none}.version{font-size:11px;color:#91adc5;margin-top:6px}.nav{display:flex;flex-direction:column;gap:7px}.nav button{text-align:left;border-color:transparent;background:transparent}.nav button.active{background:#245377;border-color:#4076a0}.footer{margin-top:auto;display:flex;flex-direction:column;gap:8px}.content{min-width:0;flex:1;padding:20px;overflow-y:auto;overscroll-behavior:contain}h2{font-size:15px;margin:0 0 10px}fieldset{border:1px solid #29465d;border-radius:6px;margin:0 0 16px;padding:12px}legend{font-weight:650;padding:0 5px}.row{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:9px 0;min-height:24px}.row span{min-width:0}.row input[type=checkbox]{width:17px;height:17px;flex-shrink:0;accent-color:#65b7ef}.row input[type=color]{width:44px;height:26px;padding:1px;border:1px solid #365168;background:#17334c}.row input[type=range]{width:130px;accent-color:#65b7ef}.row output{width:36px;text-align:right}.hint{font-size:11px;color:#a3b9ca;line-height:1.6}#status{white-space:pre-wrap;word-break:break-word;font-size:11px;line-height:1.5;background:#081b2b;padding:10px;margin-bottom:14px;border:1px solid #29465d;border-radius:5px}p{line-height:1.6}a{color:#80c4ff}pre{white-space:pre-wrap;word-break:break-word;font-size:11px}.toolbar{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}[hidden]{display:none!important}@media(max-width:600px){#ui{left:12px;top:12px}.sidebar{width:122px;padding:10px}.content{padding:12px}.row{gap:6px}.row input[type=range]{width:85px}}
`;
const GROUPS = {
  Main: [
    ['Aimbot', [['aim', 'Enabled', 'aim'], ['smoothEnabled', 'Use Smooth', 'aim'], ['smooth', 'Smooth', 'aim'],
      ['knocked', 'Target Knocked', 'aim'], ['sticky', 'Sticky Target', 'aim'], ['showDot', 'Aimbot Dot'],
      ['fov', 'FOV'], ['showFov', 'Show FOV Circle'], ['wallcheck', 'Wallcheck', 'wallcheck'], ['predict', 'Prediction', 'prediction']]],
    ['Melee Lock', [['melee', 'Enabled', 'mobile'], ['autoMelee', 'Auto Melee (from gun, while firing)', 'switch']]],
    ['Auto Switch', [['autoSwitch', 'Enabled', 'switch'], ['useOneGun', 'Use One Gun (switch away then return)', 'switch'], [null, 'Ammo single/burst; equip từng frame, chờ slot cập nhật. Không bỏ qua cooldown server.']]],
    ['Semi Auto', [['semi', 'Held Fire: single guns + fists / melee', 'semi'], [null, 'Giữ nút Fire để lặp; auto/burst dùng shootHold gốc; không lặp lựu đạn. Server vẫn quyết định cooldown.']]],
  ],
  Visuals: [
    ['X-Ray', [['xray', 'Enabled', 'xray'], ['ceilings', 'Remove Ceilings', 'xray'], ['darkerSmokes', 'Darker Smokes', 'xray'], ['smokeOpacity', 'Smoke Opacity (legacy scale)', 'xray'], ['treeOpacity', 'Tree / Bush Opacity', 'xray'], [null, 'Khói: giá trị 50 = alpha tối đa 0.05 mỗi particle như bản gốc; 0 = ẩn, 100 = 0.1. Tắt X-Ray để trả opacity game.']]],
    ['Layer Spoofer', [['layerSpoofer', 'Hold layer key to preview other floor', 'layer'], [null, 'Chỉ đổi layer client 0/1, không đổi tầng server hoặc cho bắn xuyên tầng. Thả phím/blur khôi phục giá trị mới nhất.']]],
    ['ESP / Teams', [['esp', 'Enabled', 'visuals'], ['espShowEnemies', 'Show enemies', 'visuals'], ['espShowAllies', 'Show allies / squad', 'visuals'],
      ['espShowUnknown', 'Show unknown team', 'visuals'], ['espShowDowned', 'Show downed', 'visuals'], ['espSameLayerOnly', 'Same layer only', 'visuals'],
      ['espMaxDistance', 'Max range (world units)', 'visuals'], [null, 'ENEMY / ALLY / SQUAD / UNKNOWN theo teamInfo và groupInfo. Không mặc định unknown là địch.']]],
    ['ESP / Display', [['lines', 'Player lines', 'visuals'], ['espMarkers', 'Player markers', 'visuals'], ['espLabels', 'Relation / status labels', 'visuals'],
      ['nametags', 'Player names', 'visuals'], ['espDistance', 'Distance (world units)', 'visuals'], ['espWeapons', 'Equipped weapon', 'visuals'],
      ['espOffscreen', 'Off-screen arrows (received entities only)', 'visuals'], ['espHighlightTarget', 'Highlight current enemy target', 'visuals'], ['espLegend', 'Color legend / counts', 'visuals'],
      ['espFontSize', 'Label size', 'visuals'], ['espOpacity', 'Overlay opacity', 'visuals'], ['espLineWidth', 'Line width', 'visuals']]],
    ['ESP / Colors', [['espEnemyColor', 'Enemy', 'visuals'], ['espAllyColor', 'Ally / squad', 'visuals'], ['espUnknownColor', 'Unknown', 'visuals'], ['espTargetColor', 'Current enemy target', 'visuals']]],
    ['Grenades', [['grenadeZones', 'Nominal Explosion Radius', 'grenadeZones'], ['grenadeTrajectory', 'Throw preview (open-air estimate)', 'grenadeZones'], [null, 'Nét đứt = ước lượng vật lý không khí/drag; không biết fuse còn lại, perk, va chạm tương lai hoặc điểm nổ chắc chắn.']]],
    ['Flashlights', [['ownFlashlight', 'Own spread cone', 'previews'], ['othersFlashlight', 'Enemy spread cones', 'previews'], ['bulletTrajectory', 'Bullet path + nominal ricochets', 'previews'], [null, 'Circle/AABB; tối đa 3 phản xạ khi bắt được map defs, 8 cone / 256 obstacles. Không biết kết quả server hoặc mọi perk; thiếu collider hiển thị nét đứt.']]],
    ['Infinite Zoom', [['zoom', 'Enabled (bounded 1–3×)', 'zoom'], ['zoomFactor', 'Zoom Out', 'zoom']]],
  ],
  Misc: [
    ['Map Highlights', [['mapHighlights', 'Special map markers', 'mapHighlights'], ['smallerTrees', 'Smaller minimap trees', 'mapHighlights'], [null, 'Clone shape khi render minimap; chỉ redraw khi đổi setting/map. Không hook Array.sort hoặc đổi collider.']]],
    ['Auto Loot', [['autoLoot', 'Enabled', 'sender'], ['lootMode', 'Pickup mode', 'sender'], [null, 'Nearby: ammo / heal / boost / throwable; bỏ qua súng và gear. Mobile: cần Join mới, có cả mở cửa.']]],
    ['Mobile Movement', [['mobileMovement', 'Enabled', 'mobile'], ['movementSmooth', 'Direction Smooth', 'mobile'], [null, 'Làm mượt đổi hướng khi giữ phím; nhả phím dừng ngay, không ghi đè input gốc.']]],
  ],
};
export function createMenu(win, config, { onChange, retry, stop, diagnostics, onAimHold = () => {} }) {
  const doc = win.document, host = doc.createElement('div');
  host.id = 'duality-reborn-host';
  const root = host.attachShadow({ mode: 'open' }); // Deliberately inspectable, not a stealth boundary.
  const el = (tag, props = {}, ...children) => {
    const n = doc.createElement(tag);
    for (const [k, value] of Object.entries(props)) {
      if (k === 'text') n.textContent = value;
      else if (k === 'class') n.className = value;
      else n[k] = value;
    }
    children.forEach(c => n.append(c)); return n;
  };
  const style = el('style', { text: CSS });
  const canvas = el('canvas'); canvas.setAttribute('aria-hidden', 'true');
  const shell = el('section', { id: 'ui' }); shell.setAttribute('aria-label', 'Duality Client Reborn');
  const brand = el('div', { class: 'brand', text: 'Duality Client' }, el('div', { class: 'version', text: 'Reborn 0.4.0 • readable debug' }));
  const nav = el('nav', { class: 'nav' }); nav.setAttribute('aria-label', 'Menu tabs');
  const content = el('main', { class: 'content' });
  const status = el('div', { id: 'status', text: 'Đang chờ Application…' }); status.setAttribute('role', 'status');
  const panel = el('div');
  const close = el('button', { text: 'Close' }); close.onclick = () => { shell.hidden = true; };
  const retryButton = el('button', { text: 'Retry capture' }); retryButton.onclick = retry;
  const stopButton = el('button', { text: 'Stop / cleanup' }); stopButton.onclick = stop;
  const sidebar = el('aside', { class: 'sidebar' }, brand, nav, el('div', { class: 'footer' }, close, retryButton, stopButton));
  content.append(status, panel); shell.append(sidebar, content); root.append(style, canvas, shell);
  (doc.body || doc.documentElement).append(host);
  let tab = 'Main', caps = {}, dead = false, storageTimer = null, captureKey = null, keyTimeout = null;
  const listeners = new AbortController();
  // Browser/jsdom realms have distinct AbortSignal constructors.
  const controller = win.AbortController ? new win.AbortController() : listeners;
  const signal = controller.signal;
  const persist = () => {
    win.clearTimeout(storageTimer);
    storageTimer = win.setTimeout(() => {
      try { win.localStorage.setItem(STORAGE_KEY, JSON.stringify(config)); }
      catch { status.textContent = 'Không lưu được cấu hình; tiếp tục dùng trong bộ nhớ.'; }
    }, 200);
  };
  const set = (key, value) => { config[key] = value; persist(); onChange(key, value); };
  const cancelKey = () => { captureKey = null; win.clearTimeout(keyTimeout); };
  const row = ([key, label, capability]) => {
    if (key === null) return el('div', { class: 'hint', text: label });
    const title = el('span', { text: label }), labelEl = el('label', { class: 'row' }, title);
    const input = key === 'lootMode' ? el('select') : el('input', { type: colors.has(key) ? 'color' : ranges[key] ? 'range' : 'checkbox' });
    input.dataset.config = key;
    if (key === 'lootMode') {
      for (const [value, text] of [['nearby', 'Nearby supplies (now)'], ['mobile', 'Mobile loot / doors (next join)']]) input.append(el('option', { value, text }));
      input.value = config.lootMode; input.onchange = () => set(key, input.value);
    }
    if (capability && !caps[capability]) {
      input.disabled = true;
      labelEl.title = `Đang chờ contract: ${capability}. Chưa xác nhận trên build này.`;
    }
    if (colors.has(key)) {
      input.value = config[key]; input.onchange = () => { if (colorValue(input.value)) set(key, input.value.toLowerCase()); }; labelEl.append(input);
    } else if (key === 'lootMode') { labelEl.append(input); } else if (ranges[key]) {
      [input.min, input.max] = ranges[key]; input.step = key === 'zoomFactor' ? .1 : key === 'espLineWidth' ? .5 : 1; input.value = config[key];
      const output = el('output', { text: String(config[key]) });
      input.oninput = () => { const value = Number(input.value); set(key, value); output.textContent = String(value); };
      labelEl.append(input, output);
    } else {
      input.checked = config[key]; input.onchange = () => set(key, input.checked); labelEl.append(input);
    }
    return labelEl;
  };
  const render = () => {
    if (dead) return;
    cancelKey(); panel.replaceChildren();
    for (const button of nav.children) { button.classList.toggle('active', button.textContent === tab); button.setAttribute('aria-pressed', String(button.textContent === tab)); }
    if (GROUPS[tab]) {
      for (const [name, rows] of GROUPS[tab]) panel.append(el('fieldset', {}, el('legend', { text: name }), ...rows.map(row)));
      if (tab === 'Main') panel.append(el('p', { class: 'hint', text: 'Aim chỉ tác động khi giữ nút bắn và có đối thủ trong FOV quanh con trỏ. Trạng thái Aim ở trên cho biết vì sao đang chờ; wallcheck thiếu contract sẽ không âm thầm bị bỏ qua.' }));
      if (tab === 'Misc') panel.append(el('p', { class: 'hint', text: 'Nearby supplies hoạt động trong trận sau khi đủ contract; không tự đổi súng/gear và không giả nhặt thành công. Mobile mode dùng isMobile trong Join mới, có thể ảnh hưởng scope và tự mở cửa.' }));
      return;
    }
    if (tab === 'Keybinds') {
      for (const [key, label] of [['menuKey', 'Toggle Menu'], ['aimKey', 'Aimbot'], ['stickyKey', 'Sticky Target'], ['layerKey', 'Layer Spoofer (hold)']]) {
        const button = el('button', { text: config[key] });
        button.onclick = () => {
          cancelKey(); captureKey = { key, button }; button.textContent = 'Press key / Esc';
          keyTimeout = win.setTimeout(() => { cancelKey(); render(); }, 10000);
        };
        panel.append(el('div', { class: 'row' }, el('span', { text: label }), button));
      }
      panel.append(row(['holdAim', 'Hold Aimbot Key']));
      panel.append(el('p', { class: 'hint', text: 'Aimbot vẫn chỉ tác động khi đang giữ nút bắn. Phím tắt không chạy khi đang nhập văn bản. Esc hủy gán phím; focus/blur giải phóng hold.' }));
      return;
    }
    panel.append(el('h2', { text: 'Controls & Information' }), el('p', { text: 'Bản viết lại độc lập. Menu giữ Main / Visuals / Misc / Keybinds / Help; không tải font, ảnh hay thư viện UI từ bên ngoài.' }),
      el('p', { class: 'hint', text: 'ESP: màu + nhãn địch/ta/unknown; nét đứt cho layer khác / downed / unknown. Không suy đoán HP/armor của đối thủ. Layer Spoofer chỉ đổi render client; trajectory là preview có giới hạn, không phải kết quả server. Map Highlights chỉ đánh dấu minimap theo native renderer. Chỉ hiển thị dữ liệu client nhận được. Không bảo đảm tương thích mọi update hay tránh phát hiện. Feature thiếu contract sẽ bị khóa; có code không đồng nghĩa đã xác nhận trên live.' }));
    const pre = el('pre', { text: JSON.stringify(diagnostics(), null, 2) });
    const refresh = el('button', { text: 'Refresh diagnostics' }); refresh.onclick = () => { pre.textContent = JSON.stringify(diagnostics(), null, 2); };
    const copy = el('button', { text: 'Copy diagnostics' });
    copy.onclick = async () => {
      const text = JSON.stringify(diagnostics(), null, 2); pre.textContent = text;
      try {
        if (!win.navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
        await win.navigator.clipboard.writeText(text);
        if (!dead && copy.isConnected) copy.textContent = 'Copied';
      } catch {
        if (dead || !copy.isConnected) return;
        const field = el('textarea', { value: text, readOnly: true, rows: 10 });
        field.setAttribute('aria-label', 'Diagnostics JSON — Ctrl+C to copy');
        field.style.width = '100%'; pre.replaceChildren(field); field.focus(); field.select();
        copy.textContent = 'Nhấn Ctrl+C để copy JSON';
      }
    };
    const reset = el('button', { text: 'Reset config' }); reset.onclick = () => { Object.assign(config, DEFAULTS); persist(); onChange('reset'); render(); };
    panel.append(el('div', { class: 'toolbar' }, refresh, copy, reset), pre);
  };
  for (const name of ['Main', 'Visuals', 'Misc', 'Keybinds', 'Help']) {
    const button = el('button', { text: name }); button.onclick = () => { tab = name; render(); }; nav.append(button);
  }
  const typing = event => event.composedPath().some(n => ['INPUT', 'TEXTAREA', 'SELECT'].includes(n.tagName) || n.isContentEditable);
  let holdPrevious = null;
  const releaseHold = () => { if (holdPrevious !== null) { config.aim = holdPrevious; holdPrevious = null; onAimHold(false); onChange('aim', config.aim); render(); } };
  win.addEventListener('keydown', event => {
    if (captureKey) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (event.code !== 'Escape') {
        const candidate = normalizeConfig({ ...config, [captureKey.key]: event.code });
        set(captureKey.key, candidate[captureKey.key]);
      }
      cancelKey(); render(); return;
    }
    if (event.repeat || typing(event)) return;
    if (event.code === config.menuKey) { shell.hidden = !shell.hidden; event.preventDefault(); }
    if (event.code === config.aimKey) {
      if (config.holdAim) { if (holdPrevious === null) holdPrevious = config.aim; config.aim = true; onAimHold(true); onChange('aim', true); }
      else set('aim', !config.aim);
      render();
    }
    if (event.code === config.stickyKey) { set('sticky', !config.sticky); render(); }
  }, { capture: true, signal });
  win.addEventListener('keyup', event => { if (event.code === config.aimKey) releaseHold(); }, { signal });
  win.addEventListener('blur', () => { releaseHold(); cancelKey(); }, { signal });
  doc.addEventListener('visibilitychange', () => { if (doc.hidden) releaseHold(); }, { signal });
  let drag = null;
  brand.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    const rect = shell.getBoundingClientRect(); drag = { dx: event.clientX - rect.left, dy: event.clientY - rect.top };
    brand.setPointerCapture?.(event.pointerId); event.preventDefault();
  }, { signal });
  brand.addEventListener('pointermove', event => {
    if (!drag) return;
    shell.style.left = `${clamp(event.clientX - drag.dx, 0, Math.max(0, win.innerWidth - shell.offsetWidth))}px`;
    shell.style.top = `${clamp(event.clientY - drag.dy, 0, Math.max(0, win.innerHeight - 60))}px`;
  }, { signal });
  for (const name of ['pointerup', 'pointercancel', 'lostpointercapture']) brand.addEventListener(name, () => { drag = null; }, { signal });
  render();
  return {
    host, root, canvas, render,
    status(text) { if (!dead && status.textContent !== text) status.textContent = text; },
    capabilities(value) {
      if (JSON.stringify(caps) !== JSON.stringify(value)) { caps = { ...value }; render(); }
    },
    dispose() {
      if (dead) return;
      dead = true; releaseHold(); controller.abort(); win.clearTimeout(storageTimer); cancelKey();
      try { win.localStorage.setItem(STORAGE_KEY, JSON.stringify(config)); } catch { /* Storage optional. */ }
      host.remove();
    },
  };
}
