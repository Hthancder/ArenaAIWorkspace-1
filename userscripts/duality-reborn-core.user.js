// ==UserScript==
// @name         Duality - Injection Core
// @namespace    arena.survev.injection-core
// @version      1.1.0
// @description  Capture the game and install reversible hooks; no cheat features.
// @match        https://survev.io/*
// @match        https://*.survev.io/*
// @run-at       document-start
// @grant        none
// @inject-into  page
// @sandbox      raw
// @noframes
// ==/UserScript==
/*
 * Lõi thuần, không menu, canvas, cấu hình hoặc chức năng cheat.
 * Chạy trong page world từ document-start. API:
 *   const core = window[Symbol.for('duality.injection.core.v1')];
 *   core.onReady(({app, game}) => { ... });
 *   core.onDefinitions(({definitions, mapDefinitions}) => { ... });
 *   core.hookSender((forward, type, message, ...rest) => forward(type, message, ...rest));
 *   core.hookSender(handler, knownMethodName); // nếu biết chính xác tên sender
 *   core.addTicker(callback, priority); // trả hàm gỡ
 *   core.status(); core.dispose();
 * Dò sender tự động chỉ nhận một method chứa lệnh gọi serializeMsg trực tiếp.
 * Đây là kiểm tra văn bản hẹp, không phải phân tích AST: nếu game đổi hoặc
 * minify khác, có thể không tìm được hoặc cần tự xác minh và chỉ định tên.
 * Handler tự chịu trách nhiệm bảo toàn input và gọi forward. Không tự thêm Fire.
 */
(() => {
  'use strict';
  const win = window, key = Symbol.for('duality.injection.core.v1');
  win[key]?.dispose?.();
  const nativeApply = Reflect.apply, source = Function.prototype.toString;
  const readyListeners = new Set(), definitionListeners = new Set(), cleanups = [];
  const wrappers = new WeakMap();
  let alive = true, app = null, definitions = null, mapDefinitions = null;
  let state = 'waiting', captureBusy = false, defsBusy = false;

  // Chỉ đọc data property trong lúc nhận dạng; không gọi getter lạ.
  const read = (object, name) => {
    if (object == null || (typeof object !== 'object' && typeof object !== 'function')) return undefined;
    try { const d = Object.getOwnPropertyDescriptor(object, name); return d && 'value' in d ? d.value : undefined; }
    catch { return undefined; }
  };
  const addCleanup = fn => { cleanups.push(fn); return fn; };
  const patch = (owner, name, factory) => {
    let original, descriptor;
    try { original = owner?.[name]; descriptor = Object.getOwnPropertyDescriptor(owner, name); }
    catch { return null; }
    if (typeof original !== 'function' || descriptor && !descriptor.configurable && !descriptor.writable) return null;
    const wrapper = factory(original);
    if (typeof wrapper !== 'function' || wrapper === original) return null;
    try { Object.defineProperty(owner, name, { configurable: true, enumerable: descriptor?.enumerable ?? false, writable: true, value: wrapper }); }
    catch { return null; }
    wrappers.set(wrapper, original);
    let active = true;
    const remove = () => {
      if (!active) return; active = false;
      try {
        if (owner[name] !== wrapper) return;
        if (descriptor) Object.defineProperty(owner, name, descriptor); else delete owner[name];
      } catch { /* Another owner may have changed the descriptor. */ }
    };
    addCleanup(remove); return remove;
  };
  const isApplication = candidate => {
    const pixi = read(candidate, 'pixi');
    if (!read(candidate, 'game') || !pixi || !read(pixi, 'stage')) return false;
    let ticker = read(pixi, 'ticker') || read(pixi, '_ticker');
    try { ticker ||= pixi.ticker; } catch { return false; }
    return !!ticker && typeof ticker.add === 'function' && typeof ticker.remove === 'function';
  };
  const findSender = game => {
    const candidates = [], names = new Set();
    try {
      for (let owner = game, depth = 0; owner && owner !== Object.prototype && depth < 4; owner = Object.getPrototypeOf(owner), depth++) {
        for (const name of Object.getOwnPropertyNames(owner)) {
          if (name === 'constructor' || names.has(name)) continue;
          names.add(name);
          const d = Object.getOwnPropertyDescriptor(owner, name);
          if (!d || typeof d.value !== 'function') continue;
          let fn = d.value;
          while (wrappers.has(fn)) fn = wrappers.get(fn);
          const text = nativeApply(source, fn, []);
          // Exactly one direct call, not merely a property name or assignment.
          const calls = text.match(/(?:\.serializeMsg|\[\s*["']serializeMsg["']\s*\])\s*\(/g);
          if (calls?.length === 1) candidates.push(name);
        }
      }
    } catch { return null; }
    return candidates.length === 1 ? candidates[0] : null;
  };
  const notify = (fn, value) => {
    try { fn(value); } catch (error) { win.console?.error?.('[Injection core] callback failed', error); }
  };
  const publishDefinitions = () => {
    const value = { definitions, mapDefinitions };
    for (const fn of [...definitionListeners]) notify(fn, value);
  };
  const core = {
    status() { return { state, captured: !!app, definitionsCaptured: !!definitions, mapDefinitionsCaptured: !!mapDefinitions, sender: app ? findSender(app.game) : null }; },
    onReady(fn) {
      if (typeof fn !== 'function') throw new TypeError('onReady requires a function');
      if (!alive) return () => {};
      readyListeners.add(fn); if (app) notify(fn, { app, game: app.game });
      return () => readyListeners.delete(fn);
    },
    onDefinitions(fn) {
      if (typeof fn !== 'function') throw new TypeError('onDefinitions requires a function');
      if (!alive) return () => {};
      definitionListeners.add(fn); if (definitions || mapDefinitions) notify(fn, { definitions, mapDefinitions });
      return () => definitionListeners.delete(fn);
    },
    hookSender(handler, knownMethodName = null) {
      if (!alive || !app || typeof handler !== 'function') return false;
      const game = app.game, name = knownMethodName === null ? findSender(game) : knownMethodName;
      if (typeof name !== 'string' || !name) return false;
      return !!patch(game, name, original => function (...args) {
        const receiver = this;
        return nativeApply(handler, receiver, [(...next) => nativeApply(original, receiver, next), ...args]);
      });
    },
    addTicker(fn, priority = 0) {
      if (!alive || !app || typeof fn !== 'function' || !Number.isFinite(priority)) return null;
      const ticker = app.pixi.ticker; ticker.add(fn, null, priority);
      let active = true;
      return addCleanup(() => { if (active) { active = false; ticker.remove(fn, null); } });
    },
    dispose() {
      if (!alive) return;
      alive = false; state = 'disposed';
      for (const fn of cleanups.splice(0).reverse()) { try { fn(); } catch { /* continue cleanup */ } }
      readyListeners.clear(); definitionListeners.clear(); app = null; definitions = null; mapDefinitions = null;
      if (win[key] === core) delete win[key];
    },
  };
  win[key] = core;

  let stopCapture = () => {};
  const capture = patch(win.Function.prototype, 'call', original => function (self) {
    let found = false;
    if (alive && !app && !captureBusy) {
      captureBusy = true;
      try { found = isApplication(self); } catch { /* incompatible object */ }
      finally { captureBusy = false; }
    }
    if (found) {
      stopCapture();
      win.queueMicrotask(() => {
        if (!alive || app) return;
        app = self; state = 'captured';
        for (const fn of [...readyListeners]) notify(fn, { app, game: app.game });
      });
    }
    return nativeApply(original, this, arguments);
  });
  let captureTimer;
  stopCapture = () => { capture?.(); win.clearTimeout(captureTimer); };
  if (capture) captureTimer = win.setTimeout(() => { if (alive && !app) { stopCapture(); state = 'timeout'; } }, 15000);
  else state = 'unavailable';
  addCleanup(stopCapture);

  let stopDefinitions = () => {};
  const defsHook = patch(win.Object, 'keys', original => function (value) {
    if (alive && !defsBusy) {
      defsBusy = true;
      try {
        const type = name => read(read(value, name), 'type');
        if (!definitions && type('mp5') === 'gun' && type('bullet_mp5') === 'bullet' && type('frag') === 'throwable' && type('explosion_frag') === 'explosion') {
          definitions = value; win.queueMicrotask(() => { if (alive) publishDefinitions(); });
        }
        const marker = name => type(name) === 'obstacle' && typeof read(read(value, name), 'reflectBullets') === 'boolean' && !!read(read(value, name), 'collision');
        if (!mapDefinitions && marker('tree_01') && marker('stone_01')) {
          mapDefinitions = value; win.queueMicrotask(() => { if (alive) publishDefinitions(); });
        }
        if (definitions && mapDefinitions) stopDefinitions();
      } catch { /* incompatible object */ }
      finally { defsBusy = false; }
    }
    return nativeApply(original, this, arguments);
  });
  let defsTimer;
  stopDefinitions = () => { defsHook?.(); win.clearTimeout(defsTimer); };
  if (defsHook) defsTimer = win.setTimeout(stopDefinitions, 15000);
  addCleanup(stopDefinitions);
  const onPageHide = () => core.dispose();
  win.addEventListener('pagehide', onPageHide, { once: true });
  addCleanup(() => win.removeEventListener('pagehide', onPageHide));
})();
