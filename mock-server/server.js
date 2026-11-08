'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'web');
const DATA_DIR = path.resolve(process.env.MOCK_DATA_DIR || path.join(ROOT, '.mock-data'));
const SETTINGS_FILE = path.join(DATA_DIR, 'settings.json');
const HOST = process.env.HOST || '127.0.0.1';
const PORT = Number(process.env.PORT || 4173);
const WINDOWS = [
  { id: 'desktop', title: 'Toàn bộ màn hình', detail: 'Desktop · 1920 × 1080', mode: 'screen' },
  { id: 'browser', title: 'Trình duyệt', detail: 'Chrome · Cửa sổ đang mở', mode: 'window' },
  { id: 'notes', title: 'Ghi chú', detail: 'Notepad · Cửa sổ đang mở', mode: 'window' },
];
const DEFAULTS = {
  quality: 'auto', display: 'real', aspect: 'fit', touch: 'scroll', 'cursor-mode': 'auto',
  keyboard: 'intent', audio: 'ask', volume: 70, 'hide-screen': false, 'hide-taskbar': false,
  language: 'vi', theme: 'light', 'max-bitrate': '10', 'max-fps': '30', keyframe: '2', scaler: 'balanced',
  sharpen: 'off', jitter: 'low', 'cursor-echo': 'on', ripple: 'on', resolution: 'auto', dpi: '100',
  monitor: 'primary', 'keyboard-layout': 'system', 'input-rate': '60', 'block-win-lock': 'on',
  'listen-port': '8443', certificate: 'self', 'stun-turn': 'auto', 'latency-hud': 'off',
  'log-level': 'normal', encoder: 'auto',
};
const ALLOWED = Object.keys(DEFAULTS);
const BOOL_SETTINGS = new Set(['hide-screen', 'hide-taskbar']);
const ENUMS = {
  quality: ['auto','sharp','smooth'], display: ['real','comfortable','large-text','sharp'], aspect: ['fit','fill','100'],
  touch: ['scroll','mouse'], 'cursor-mode': ['auto','local','video'], keyboard: ['intent','raw'], audio: ['ask','on','off'],
  language: ['vi','en'], theme: ['light','dark','system'], 'max-bitrate': ['5','10','15'], 'max-fps': ['15','30','60'],
  keyframe: ['1','2','3'], scaler: ['balanced','sharp','fast'], sharpen: ['off','low'], jitter: ['low','smooth'],
  'cursor-echo': ['on','off'], ripple: ['on','off'], resolution: ['auto','1080','720'], dpi: ['100','125','150'],
  monitor: ['primary','2'], 'keyboard-layout': ['system','vi','en'], 'input-rate': ['60','100'],
  'block-win-lock': ['on','off'], 'listen-port': ['8443','443'], certificate: ['self','custom'],
  'stun-turn': ['auto','tailnet'], 'latency-hud': ['off','on'], 'log-level': ['normal','verbose'], encoder: ['auto','qsv','nvenc'],
};
function validSetting(key, value) {
  if (!ALLOWED.includes(key)) return false;
  if (key === 'volume') return Number.isInteger(value) && value >= 0 && value <= 100;
  if (BOOL_SETTINGS.has(key)) return typeof value === 'boolean';
  return Array.isArray(ENUMS[key]) && ENUMS[key].includes(value);
}
const settings = loadSettings();
let activeSession = null;

function loadSettings() {
  try {
    const value = JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8'));
    return { ...DEFAULTS, ...Object.fromEntries(Object.entries(value).filter(([key, item]) => validSetting(key, item))) };
  } catch { return { ...DEFAULTS }; }
}
function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
  res.end(JSON.stringify(body));
}
function bodyJson(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => { data += chunk; if (data.length > 8192) reject(new Error('body_too_large')); });
    req.on('end', () => {
      try { resolve(data ? JSON.parse(data) : {}); } catch { reject(new Error('invalid_json')); }
    });
    req.on('error', reject);
  });
}
function persistSettings() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const temp = `${SETTINGS_FILE}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(settings, null, 2), { mode: 0o600 });
  fs.renameSync(temp, SETTINGS_FILE);
}
function staticFile(urlPath, res) {
  const cleanPath = decodeURIComponent(urlPath.split('?')[0]);
  const relative = cleanPath === '/' ? 'index.html' : cleanPath.replace(/^\/+/, '');
  const file = path.resolve(WEB, relative);
  if (!file.startsWith(`${WEB}${path.sep}`) && file !== WEB) return json(res, 404, { error: 'not_found' });
  let stat;
  try { stat = fs.statSync(file); } catch { return json(res, 404, { error: 'not_found' }); }
  if (!stat.isFile()) return json(res, 404, { error: 'not_found' });
  const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml' };
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-cache', 'x-content-type-options': 'nosniff' });
  fs.createReadStream(file).pipe(res);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const route = `${req.method} ${url.pathname}`;
  try {
    if (route === 'GET /api/health') return json(res, 200, { ok: true, app: 'lantern-mock', mode: 'mock' });
    if (route === 'GET /api/device') return json(res, 200, { id: 'inspiron-7467', name: 'Inspiron 7467', status: 'ready', platform: 'Windows 11', location: 'Ở nhà', mock: true });
    if (route === 'GET /api/windows') return json(res, 200, { windows: WINDOWS, mock: true });
    if (route === 'GET /api/settings') return json(res, 200, { settings, mock: true });
    if (route === 'GET /api/diagnostics') return json(res, 200, { mock: true, checks: [], advice: 'Chạy standalone Windows exe để probe phần cứng.' });
    if (route === 'POST /api/diagnostics/capture') return json(res, 501, { error: 'hardware_probe_only_available_in_windows_exe' });
    if (route === 'PATCH /api/settings') {
      const patch = await bodyJson(req);
      const accepted = {};
      const invalid = [];
      for (const [key, value] of Object.entries(patch)) {
        if (!ALLOWED.includes(key)) continue;
        const valid = validSetting(key, value);
        if (valid) accepted[key] = value;
        else invalid.push(key);
      }
      if (invalid.length) return json(res, 422, { error: 'invalid_setting_value', fields: invalid });
      Object.assign(settings, accepted);
      persistSettings();
      return json(res, 200, { settings, updated: Object.keys(accepted), mock: true });
    }
    if (route === 'GET /api/sessions/current') return json(res, 200, { session: activeSession, mock: true });
    if (route === 'POST /api/sessions') {
      if (activeSession) return json(res, 409, { error: 'session_already_active', session: activeSession });
      const input = await bodyJson(req);
      if (input.mode !== undefined && !['hvnc','vnc'].includes(input.mode)) return json(res, 422, { error: 'invalid_session_mode' });
      if (input.windowId !== undefined && !WINDOWS.some(win => win.id === input.windowId)) return json(res, 422, { error: 'invalid_window_id' });
      const mode = input.mode === 'vnc' ? 'vnc' : 'hvnc';
      const windowId = input.windowId || 'desktop';
      activeSession = { id: randomUUID(), mode, windowId, status: 'connected', startedAt: new Date().toISOString(), audio: input.audio !== false, mock: true };
      return json(res, 201, { session: activeSession, mock: true });
    }
    const stopMatch = url.pathname.match(/^\/api\/sessions\/([0-9a-f-]+)$/i);
    if (req.method === 'DELETE' && stopMatch) {
      if (!activeSession || activeSession.id !== stopMatch[1]) return json(res, 404, { error: 'session_not_found' });
      const ended = activeSession;
      activeSession = null;
      return json(res, 200, { session: ended, stopped: true, mock: true });
    }
    if (url.pathname.startsWith('/api/')) return json(res, 404, { error: 'not_found' });
    if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'method_not_allowed' });
    return staticFile(url.pathname, res);
  } catch (error) {
    const code = error.message === 'invalid_json' ? 400 : error.message === 'body_too_large' ? 413 : 500;
    return json(res, code, { error: error.message === 'invalid_json' || error.message === 'body_too_large' ? error.message : 'internal_error' });
  }
});
server.listen(PORT, HOST, () => console.log(`Lantern mock listening at http://${HOST}:${PORT} (no real desktop access)`));
server.on('close', () => { activeSession = null; });
module.exports = { server, DEFAULTS, WINDOWS };
