import { captureApplication, captureDefinitions, Disposables } from './core.mjs';
import { Features } from './features.mjs';
import { createMenu, loadConfig } from './menu.mjs';

export function start(win) {
  const key = Symbol.for('duality.reborn.controller.v1');
  win[key]?.dispose?.();
  const bag = new Disposables();
  let config;
  try { config = loadConfig(win.localStorage); } catch { config = loadConfig(null); }
  let menu = null, engine = null, defs = null, mapDefs = null, cancelCapture = null, alive = true;
  let status = 'Đang chờ Application…', lastWarning = '', captured = false, captureState = 'waiting';
  const startedAt = win.performance.now();
  win.console?.info?.('[Duality Reborn 0.5.0-preview.1] Script đã chạy. Nếu không có menu, gửi dòng lỗi Console sau thông báo này.');
  const report = (level, message) => {
    if (!alive) return;
    if (level === 'error' || level === 'warning') {
      lastWarning = message;
      win.console?.warn?.('[Duality Reborn]', message);
    }
    status = message;
  };
  const diagnostics = () => ({
    version: '0.5.0-preview.1', captured, captureState, status, lastWarning,
    menuMounted: !!menu?.host.isConnected, documentReadyState: win.document.readyState,
    definitionsCaptured: !!defs, mapDefinitionsCaptured: !!mapDefs, elapsedMs: Math.round(win.performance.now() - startedAt),
    ...(engine?.diagnostics() || {}),
  });
  const controller = {
    diagnostics,
    retry() {
      if (!alive) return;
      cancelCapture?.(); engine?.dispose(); engine = null; captured = false; captureState = 'waiting';
      menu?.capabilities({});
      status = 'Capture có timeout 15 giây. Nếu không bắt được, reload với userscript bật từ document-start.';
      cancelCapture = captureApplication(win, app => {
        if (!alive) return;
        captured = true; captureState = 'captured';
        try {
          engine = new Features(win, app, config, report, defs); engine.mapDefinitions = mapDefs;
          if (menu) engine.attachCanvas(menu.canvas);
          status = 'Đã bắt Application; chờ trạng thái trận và contract.';
        } catch (e) {
          engine?.dispose(); engine = null; captureState = 'error';
          report('error', `Không khởi tạo được: ${e.message}`);
        }
      }, { timeout: 15000, onTimeout: () => {
        captureState = 'timeout';
        report('warning', 'Không bắt được Application trong 15 giây; hook đã gỡ. Có thể sai page-world, lỡ bootstrap hoặc contract không khớp. Gửi diagnostics; chưa xác định nguyên nhân.');
      } });
    },
    dispose() {
      if (!alive) return;
      alive = false; cancelCapture?.(); engine?.dispose(); menu?.dispose(); bag.clear();
      if (win[key] === controller) delete win[key];
    },
  };
  win[key] = controller;
  bag.add(captureDefinitions(win, value => { defs = value; if (engine) { engine.definitions = defs; engine.lastMap = -Infinity; } }, 15000, value => { mapDefs = value; if (engine) engine.mapDefinitions = value; }));
  const makeMenu = () => {
    if (!alive || menu) return;
    menu = createMenu(win, config, {
      onChange: key => {
        engine?.configurationChanged(key);
        if (key === 'autoLoot' || key === 'lootMode') status = config.lootMode === 'mobile'
          ? 'Mobile loot: cần Join mới. Bật/tắt giữa trận không đổi mobile mode server đã nhận.'
          : 'Nearby supplies: dùng input Loot trong trận khi đủ contract; không tự đổi súng/gear.';
      },
      retry: () => controller.retry(), stop: () => controller.dispose(), diagnostics,
    });
    if (engine) engine.attachCanvas(menu.canvas);
  };
  if (win.document.body) makeMenu();
  else {
    win.document.addEventListener('DOMContentLoaded', makeMenu, { once: true });
    bag.add(() => win.document.removeEventListener('DOMContentLoaded', makeMenu));
  }
  const timer = win.setInterval(() => {
    if (!menu) return;
    menu.capabilities(engine?.capabilities || {});
    const d = diagnostics();
    menu.status(`Aim: ${d.stats?.aimState ?? 'chờ mapping'}${lastWarning ? ' • Xem Help / diagnostics' : ''}`);
  }, 1000);
  bag.add(() => win.clearInterval(timer));
  const onPageHide = () => controller.dispose();
  win.addEventListener('pagehide', onPageHide, { once: true });
  bag.add(() => win.removeEventListener('pagehide', onPageHide));
  controller.retry();
  return controller;
}

if (typeof window !== 'undefined') start(window);
