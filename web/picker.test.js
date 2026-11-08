// §5.4 — cửa sổ là **dữ liệu**, không phải ba nút viết trong HTML.
//
// Bug đã xảy ra thật: `index.html` có sẵn ba `<button data-window="browser">`
// và `app.js` đọc `windows.windows.map(win => win.id)` trong khi server trả
// `wid`. Hai lỗi cộng lại ⇒ window picker **không bao giờ** hiện cửa sổ thật,
// mà trông vẫn bình thường vì có ba nút bịa. Test này khoá cả hai đầu.
const fs = require('node:fs');
const test = require('node:test');
const assert = require('node:assert');

const html = fs.readFileSync(require('node:path').join(__dirname, 'index.html'), 'utf8');
const app = fs.readFileSync(require('node:path').join(__dirname, 'app.js'), 'utf8');

test('danh sách cửa sổ không còn viết cứng trong HTML (§5.4)', () => {
  const invented = /data-window="(browser|notes)"/.exec(html);
  assert.equal(invented, null,
    `index.html còn cửa sổ bịa: ${invented && invented[0]}. ` +
    'Danh sách phải do renderWindowOptions() dựng từ GET /api/windows.');
});

test('app.js đọc đúng schema wid của §8.1', () => {
  assert.ok(app.includes('win.wid'), 'phải đọc `wid`, không phải `id`');
  assert.ok(!/windows\.windows\.map\(\s*win\s*=>\s*win\.id\s*\)/.test(app),
    'schema cũ `win.id` đã bị bỏ — server không bao giờ trả trường đó');
});

test('mọi chuỗi từ server vào DOM qua textContent', () => {
  // Title cửa sổ do app bên thứ ba đặt ⇒ có thể chứa `<script>`.
  const render = app.slice(app.indexOf('function renderWindowOptions'), app.indexOf('function updateMockWindow'));
  assert.ok(render.includes('textContent'), 'phải dùng textContent');
  const inner = render.match(/\.innerHTML\s*=/);
  assert.equal(inner, null, 'không được innerHTML với dữ liệu server (§41.4 T5)');
});

test('tạo phiên gửi kèm snapshotId (§41.3 #3)', () => {
  const post = app.slice(app.indexOf("apiRequest('/api/sessions', { method: 'POST'"));
  assert.ok(post.slice(0, 300).includes('snapshotId'),
    'thiếu snapshotId ⇒ server trả 403 window.unknown');
});
