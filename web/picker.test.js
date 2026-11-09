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

// §7.1 — màn hình khoá. Không có nó thì "dùng thật" không bắt đầu được: server
// từ chối mọi thao tác (đã có mật khẩu) mà UI không có chỗ nào để đăng nhập.
const auth = fs.readFileSync(require('node:path').join(__dirname, 'auth.js'), 'utf8');

test('màn hình khoá nạp được và có cả hai chế độ (§7.1)', () => {
  assert.ok(html.includes('auth.js'), 'index.html phải nạp auth.js');
  assert.ok(/id="authOverlay"/.test(html), 'phải có overlay khoá');
  assert.ok(/id="authForm"/.test(html), 'phải có form');
  // Chế độ "đặt mật khẩu" là đường vào lần đầu; thiếu nó thì lần chạy đầu
  // không có cách nào tạo mật khẩu ⇒ app vĩnh viễn không dùng được.
  assert.ok(auth.includes("'/api/setup'"), 'phải gọi /api/setup khi chưa có mật khẩu');
  assert.ok(auth.includes("'/api/login'"), 'phải gọi /api/login');
});

test('mật khẩu không được lưu ở đâu (§41.6)', () => {
  // Refresh token nằm trong cookie HttpOnly — JS không đọc được, cũng không
  // được ghi. Access token ở trong biến closure, không `localStorage`: XSS đọc
  // được `localStorage` còn closure thì không.
  assert.ok(!/localStorage|sessionStorage/.test(code(auth)),
    'auth.js không được dùng localStorage/sessionStorage cho token');
  assert.ok(!/document\.cookie/.test(code(auth)),
    'auth.js không được đọc/ghi document.cookie');
});

test('mọi request cần quyền đều đi qua authFetch (§7.1)', () => {
  // Bug sẽ xảy ra nếu quên: app chạy được ở lần chạy đầu (chưa có mật khẩu) và
  // **hỏng sau khi người dùng đặt mật khẩu** — đúng lúc họ tưởng đã xong.
  assert.ok(app.includes('authorisedFetch'),
    'app.js phải có lớp gắn Authorization');
  const bare = code(app).match(/await fetch\('\/api\/(windows|sessions|settings|live)/g) || [];
  assert.deepEqual(bare, [],
    `còn fetch trần tới route cần quyền: ${bare.join(', ')}`);
  assert.ok(jsLiveIncludesAuthorisedFetch(), 'live.js phải gắn Authorization khi gửi input');
});

/**
 * Bỏ comment trước khi kiểm.
 *
 * Đây là bẫy đã gặp **hai lần**: test grep chuỗi trong source sẽ khớp cả câu
 * giải thích. Lần đầu là "bấm để điều khiển" nằm trong comment; lần này là
 * `localStorage` được nhắc trong chính comment nói *không* dùng nó. Sửa test
 * cho đúng, đừng xoá test.
 */
function code(file) {
  return file.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}

function jsLiveIncludesAuthorisedFetch() {
  const live = fs.readFileSync(require('node:path').join(__dirname, 'live.js'), 'utf8');
  return live.includes('authorisedFetch');
}

test('auth.js tự refresh một lần, không lặp vô hạn (§41.6)', () => {
  // Refresh lặp khi token mới vẫn bị từ chối sẽ đốt lockout và tạo vòng vô hạn.
  const refreshed = auth.match(/refreshAccess\(\)/g) || [];
  assert.ok(refreshed.length >= 2, 'phải có hàm refresh và chỗ gọi');
  assert.ok(/refreshing/.test(auth), 'phải gộp các lần refresh đồng thời');
});
