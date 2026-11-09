// Trang `/live` — §6.4 + §6.5: cắm bộ điều khiển vào khung hình.
//
// # Vì sao là file riêng, không `<script>` nhúng trong HTML
//
// `response_head` (main.rs) đặt `Content-Security-Policy: default-src 'self'`
// — theo §41.4 T5, để tên cửa sổ do app bên thứ ba đặt không chèn được markup
// hay script. CSP đó **chặn** inline script. Nhúng JS vào `live_page` nghĩa là
// trang tải được nhưng **không có script nào chạy** — lỗi im lặng: khung hình
// hiện, bấm không có gì xảy ra. Test `the_live_page_never_renders_untrusted_input`
// bắt được vì nó grep `<script`.
//
// Cũng đúng ý đồ thiết kế: JS trong file riêng thì `npm test` chạy được.

// §6.4 + §6.5: cắm bộ điều khiển. Ở chế độ xem (chưa có phiên) thì
// `sessionId` rỗng ⇒ `attach` không chạy, và trang vẫn là chỉ-xem — không
// giả vờ điều khiển được khi không có gì để điều khiển.
import { attach, installUnloadRelease } from '/input.js';
const screen = document.getElementById('screen');
const hint = document.getElementById('hint');
let sessionId = '';

// §41.3: server là nơi quyết định `sid` — client chỉ hỏi. Không đoán, không
// tự sinh.
// §7.1: đã có mật khẩu thì route đòi token. Nạp `authFetch` một lần; nếu
// `auth.js` không tải được (server cũ) thì rơi về `fetch` trần — chế độ chưa
// đặt mật khẩu vẫn chạy.
let authorisedFetchPromise = null;
function authorisedFetch(path, options) {
  if (!authorisedFetchPromise) {
    authorisedFetchPromise = import('./auth.js').then((m) => m.authFetch).catch(() => fetch);
  }
  return authorisedFetchPromise.then((send) => send(path, options));
}

async function currentSession() {
  try {
    const response = await authorisedFetch('/api/sessions/current', { cache: 'no-store' });
    const data = await response.json();
    return data.session ? data.session.id : '';
  } catch { return ''; }
}

async function post(path, body) {
  // `Blob` (message `move` 12 byte của §8.3) đi thẳng không qua JSON.
  const isBinary = body instanceof Blob;
  await authorisedFetch(path, {
    method: 'POST',
    headers: isBinary ? { 'content-type': 'application/octet-stream' } : { 'content-type': 'application/json' },
    body: isBinary ? body : JSON.stringify(body),
    cache: 'no-store',
  });
}

let controller = null;
let frame = { width: 0, height: 0 };

async function enable() {
  sessionId = sessionId || await currentSession();
  if (!sessionId) {
    hint.textContent = 'chưa có phiên — mở một phiên rồi quay lại';
    return;
  }
  if (controller) return;
  const attached = attach(screen, {
    sid: sessionId,
    post,
    // §6.10.3: toạ độ chuẩn hoá theo **khung hình**, nên phải biết kích thước
    // thật. `naturalWidth/Height` là của frame MJPEG vừa vẽ.
    frame: () => frame,
  });
  controller = attached.controller;
  installUnloadRelease(controller, {
    beacon: (path, body) => navigator.sendBeacon(path, body),
    addEventListener: (name, fn) => window.addEventListener(name, fn),
  });
  screen.focus();
  hint.textContent = 'đang điều khiển · Esc để nhả phím';
}

screen.addEventListener('load', () => {
  frame = { width: screen.naturalWidth, height: screen.naturalHeight };
});
screen.addEventListener('pointerdown', enable, { once: false });
// §6.5: `Esc` nhả pointer lock (§6.4.6) ⇒ phải nhả **mọi** phím/chuột.
window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && controller) controller.releaseAll('escape');
});
