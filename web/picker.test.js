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

// §6.4 — điều khiển phải có trên **trang chính**, không chỉ ở tab `/live`.
//
// Bug đã xảy ra thật: xem màn hình thật trên trang chính, bấm chuột → không có
// gì xảy ra. Với người dùng đó là "app hỏng", không phải "tính năng ở tab
// khác". Điều khiển chỉ tồn tại trong `live.js` (trang `/live`) suốt một thời
// gian dài, và không test nào bắt được vì cả hai phía đều "đúng".
test('trang chính cắm bộ điều khiển vào khung hình live (§6.4)', () => {
  assert.ok(/attachLiveInput/.test(app), 'phải có hàm cắm điều khiển');
  assert.ok(/import\('\/input\.js'\)|import\("\/input\.js"\)/.test(app),
    'phải nạp input.js (động, vì app.js là script cổ điển)');
  assert.ok(/inputModule\.attach\(/.test(app), 'phải gọi attach');
  // `frame` phải là kích thước **thật** của frame, không phải thẻ <img>.
  assert.ok(/frame:\s*\(\)\s*=>\s*liveFrame/.test(app), 'frame phải lấy từ liveFrame');
  assert.ok(/naturalWidth/.test(app), 'liveFrame phải lấy naturalWidth của ảnh');
});

test('gỡ điều khiển phải nhả mọi phím trước (§6.4.7)', () => {
  const detach = app.slice(app.indexOf('function detachLiveInput'), app.indexOf('function renderLive'));
  assert.ok(detach.includes('releaseAll'), 'phím đang giữ phải được nhả');
  // Thứ tự: nhả trước, gỡ sau. Gỡ trước thì không còn controller để nhả.
  assert.ok(detach.indexOf('releaseAll') < detach.indexOf('.detach()'),
    'releaseAll phải chạy **trước** detach');
});

test('dòng mô tả không nói sai là "không điều khiển được"', () => {
  // Nếu câu này quay lại trong **chuỗi hiển thị**, người dùng đọc rồi không thử
  // bấm — tệ hơn không ghi. Chỉ kiểm chuỗi trong template literal (bỏ comment,
  // vì comment có thể nhắc lại câu cũ để giải thích lịch sử).
  const visible = app.replace(/\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');
  assert.ok(!/không có tiếng\/điều khiển/.test(visible),
    'điều khiển đã có, đừng nói là không có trong UI');
});
