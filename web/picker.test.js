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

// §6.11.1 — resume sau reload. Phiên nằm ở **server**, tab chỉ giữ trạng thái.
// F5 làm mất trạng thái client trong khi server vẫn chạy phiên: người dùng thấy
// "Chưa kết nối", bấm Start, nhận `409 session_already_active`, và không có nút
// nào để lấy lại phiên cũ.
test('tải lại trang có hỏi tiếp tục phiên đang mở (§6.11.1)', () => {
  assert.ok(app.includes('/api/sessions/mine'), 'phải hỏi danh sách phiên còn sống');
  assert.ok(app.includes('Tiếp tục phiên đang mở'), 'phải hỏi bằng chữ, không tự chiếm');
  // Spec: **hỏi**, không tự động. Tự chiếm sẽ đá tab khác đang xem ra.
  assert.ok(!/currentSessionId\s*=\s*session\.id;\s*setConnected\(true\);/.test(code(app)),
    'không được tự nối lại mà không hỏi');
});

test('hộp resume không chạy trên màn hình khoá (§7.1)', () => {
  // Nếu chạy trước khi đăng nhập: request 401, và hộp hỏi hiện **trên** form
  // đăng nhập — người dùng không đăng nhập được.
  assert.ok(/lantern:unlocked/.test(app), 'phải chờ sự kiện mở khoá');
  assert.ok(/authOverlay.*hidden|hidden.*authOverlay/s.test(app),
    'phải kiểm màn hình khoá đã ẩn trước khi hỏi');
});

test('hộp resume không giẫm lên window picker (§6.11.1 + §5.4)', () => {
  // Hai tính năng dùng chung `#dialogOverlay`/`#dialogConfirm`. Thiếu `action`
  // thì bấm "Tiếp tục" chạy **cả** handler chọn cửa sổ; thiếu reset thì nút
  // "Chọn cửa sổ" sau đó im lặng không làm gì.
  assert.ok(/dataset\.action\s*=\s*'resume'/.test(app), 'phải đánh dấu overlay đang ở chế độ resume');
  assert.ok(/delete\s+confirm\.dataset\.action|delete\s+\$\('#dialogConfirm'\)\.dataset\.action/.test(app),
    'phải trả lại trạng thái sau khi dùng xong');
  assert.ok(app.includes("dataset.action === 'resume'"), 'handler chọn cửa sổ phải bỏ qua khi đang resume');
});

// §50.1 #3 (P1) — mất kết nối: giữ ảnh cuối + đồng hồ "đã mất N giây".
// Bản trước tắt `live.active` ngay khi `<img>` báo lỗi: một nhịp mạng 2 giây
// xoá toàn bộ khung hình và hiện "Chưa bật xem máy thật" — người dùng tưởng app
// chết, bấm Start lại, tự tạo phiên thứ hai hoặc nhận 409.
test('mất hình thì giữ ảnh cuối và đếm giây, không xoá trắng (§50.1 #3)', () => {
  assert.ok(html.includes('liveReconnect'), 'phải có banner trạng thái mất hình');
  assert.ok(/Mất hình \$\{seconds\} giây/.test(app), 'banner phải đếm giây thật');
  const start = app.indexOf("$('#liveImage').addEventListener('error'");
  const errorHandler = app.slice(start, app.indexOf('§50.1 #3: ảnh cuối hiện lại', start));
  assert.ok(errorHandler.length > 400, 'phải tìm thấy handler');
  // Có **hai** nhánh: lỗi ngay lần đầu (báo lý do) và đứt giữa chừng (đếm
  // ngược + thử lại). Kiểm cái quan trọng: nhánh đứt giữa chừng **không** tắt
  // stream — tắt là xoá ảnh cuối, đúng cái spec cấm.
  const afterRetry = errorHandler.slice(errorHandler.indexOf('showReconnecting();'));
  assert.ok(!/live\.active = false;\s*renderLive\(\);\s*toast\('Không xem/.test(afterRetry),
    'đứt giữa chừng không được tắt stream');
  assert.ok(errorHandler.includes('firstFrameSeen'), 'phải phân biệt "lỗi ngay" với "đứt giữa chừng"');
  assert.ok(/img\.src = .*Date\.now\(\)/.test(app), 'phải nạp lại có cache-bust');
});

test('không còn câu nào nói "chưa điều khiển được" (§6.4 đã xong)', () => {
  // Câu sai ở đúng chỗ người dùng đọc trước khi bấm là lý do họ không bấm —
  // và là lý do họ tin app yếu hơn thực tế.
  // Bỏ **comment HTML** trước khi kiểm: comment giải thích "đã sửa câu chưa
  // điều khiển được" chứa đúng chuỗi đó — bẫy đã gặp ba lần với test grep.
  const visibleHtml = html.replace(/<!--[\s\S]*?-->/g, '');
  const stale = /chưa điều khiển được|không điều khiển được/i.exec(visibleHtml);
  assert.equal(stale, null, `index.html còn câu sai: ${stale && stale[0]}`);
});

// §50.1 #4 (P1) + §6.11.2 — chuyển sang app khác trên điện thoại.
// Spec: *"phải **không** mất phiên và **không** kẹt phím"*.
test('tab ẩn thì nhả phím ngay và hạ fps sau 10 giây (§50.1 #4)', () => {
  // `blur` không bắt được trường hợp điện thoại chuyển app: trang chỉ chuyển
  // sang hidden. Thiếu `visibilitychange` thì phím đang giữ ở lại down trên máy
  // thật, và quay lại gõ một chữ nhận Ctrl+chữ.
  assert.ok(app.includes("addEventListener('visibilitychange'"), 'phải nghe visibilitychange');
  assert.ok(/releaseAll\('hidden'\)/.test(app), 'phải nhả phím ngay khi tab ẩn');
  assert.ok(app.includes('HIDDEN_DELAY_MS'), 'phải có độ trễ 10 s theo spec');
  assert.ok(/HIDDEN_DELAY_MS\s*=\s*10_000/.test(app), 'độ trễ phải là 10 giây, không phải giá trị khác');
  assert.ok(/live\.hiddenFps\s*=\s*5/.test(app), 'phải hạ về 5 fps như §6.11.2');
});

test('hạ fps khi ẩn tab không đổi lựa chọn của người dùng (§50.1 #4)', () => {
  // Nếu ghi vào `live.fps` thì slider nhảy về 5 và người dùng quay lại thấy lựa
  // chọn của mình bị đổi mà không hiểu vì sao. Dùng trường riêng.
  assert.ok(app.includes('live.hiddenFps'), 'phải có trường fps riêng cho trạng thái ẩn');
  const hiddenAssign = app.match(/live\.fps\s*=\s*5/);
  assert.equal(hiddenAssign, null, 'không được gán live.fps = 5 (đó là lựa chọn của người dùng)');
});

// §50.1 #5 (P2) — báo khi phiên bắt đầu & kết thúc. Người dùng bật phiên rồi
// **rời màn hình**; đó là toàn bộ mục đích của remote desktop. Khi phiên đứt họ
// không biết cho tới lần sau nhìn vào.
test('phiên bắt đầu/kết thúc thì báo được (§50.1 #5)', () => {
  assert.ok(app.includes("import('/alert.js')"), 'phải nạp module báo hiệu');
  assert.ok(html.includes('/alert.js') || app.includes("import('/alert.js')"),
    'alert.js phải được tham chiếu');
  // Ba đường báo: bấm Start/Dừng, mất hình quá 60 s, và dừng có chủ ý.
  // Đếm **lời gọi** theo dòng, không bằng regex một dòng: lời gọi quan trọng
  // nhất (`toggleLive`) là ternary, nên một regex `announce('end')` bỏ sót nó.
  // Bẫy grep đã gặp nhiều lần — test phải khớp hình dạng code thật.
  const callLines = app
    .split('\n')
    .filter(line => /\bannounce\(/.test(line) && !/function announce/.test(line));
  assert.ok(callLines.length >= 3, `phải báo ở ≥3 chỗ, thấy ${callLines.length}: ${callLines.map(l => l.trim()).join(' | ')}`);
  assert.ok(app.includes("announce(live.active ? 'start' : 'end')"), 'bấm Start/Dừng phải báo');
});

test('chuông không bịa: im lặng phải nói ra (§50.1 #5)', () => {
  const alert = fs.readFileSync(require('node:path').join(__dirname, 'alert.js'), 'utf8');
  // `notify` trả `boolean` để nơi gọi biết đã báo được hay chưa — nếu nó luôn
  // trả `true` thì app nói "đã báo" trong khi không có gì kêu.
  assert.ok(/export function notify/.test(alert), 'phải export notify');
  assert.ok(/return false/.test(alert), 'phải có đường trả false khi không báo được');
  assert.ok(alert.includes('vibrate'), 'phải có rung làm dự phòng (rung không bị chặn autoplay)');
  // Autoplay bị chặn tới khi có tương tác: phải mở khoá ở tương tác đầu tiên.
  assert.ok(app.includes('pointerdown'), 'phải mở khoá AudioContext ở tương tác đầu');
});

// §50.1 #6 (P2) — chế độ "mạng rất yếu": 1 fps + **chỉ bàn phím**.
// Ở 1 fps, bấm chuột bằng ảnh cũ là bấm vào chỗ nút đó nằm ở một giây trước —
// nguy hiểm hơn không làm gì. Bàn phím không có vấn đề đó.
test('chế độ mạng yếu là 1 fps và tắt chuột, không chỉ hạ fps (§50.1 #6)', () => {
  assert.ok(html.includes('liveWeakNet'), 'phải có nút bật chế độ');
  assert.ok(/live\.weakNet \? 1 :/.test(app), 'fps phải là 1 ở chế độ yếu');
  assert.ok(app.includes('setPointerEnabled'), 'phải tắt đường chuột');
  // Chặn ở **một** chỗ trong controller, không rải rác từng handler.
  const input = fs.readFileSync(require('node:path').join(__dirname, 'input.js'), 'utf8');
  // Kiểm **thứ tự trong hàm `pointer`**, không khớp nguyên văn: bản đầu của test
  // này giả định đúng một dòng comment và đỏ khi comment dài hai dòng. Test khớp
  // hình dạng quá cụ thể sẽ đỏ mỗi lần sửa lời văn — và người ta sẽ nới nó thay
  // vì hiểu nó.
  const pointerBody = input.slice(
    input.indexOf('pointer(event, type) {'),
    input.indexOf('pointer(event, type) {') + 1200
  );
  const guardAt = pointerBody.indexOf('if (!this.pointerEnabled) return false;');
  const computeAt = pointerBody.indexOf('toNormalised(');
  assert.ok(guardAt >= 0, 'pointer() phải có cờ chặn');
  assert.ok(guardAt < computeAt, 'cờ chặn phải **trước** khi tính toạ độ và gửi');
  assert.ok(input.includes("releaseAll('pointer-disabled')"),
    'tắt chuột phải nhả nút đang giữ (nếu không nút ở lại down trên máy thật)');
});

test('chế độ mạng yếu không đổi FPS người dùng đã chọn (§50.1 #6)', () => {
  // Như tab ẩn: ghi vào `live.fps` thì slider nhảy, và tắt chế độ yếu xong FPS
  // của người dùng đã bị đổi mà không biết.
  assert.ok(!/live\.fps\s*=\s*1\b/.test(code(app)), 'không được gán live.fps = 1');
  assert.ok(/live\.weakNet\s*=\s*enabled/.test(app), 'phải dùng cờ riêng');
});

// # Mọi `$('#id')` phải trỏ tới một id **có thật** trong HTML
//
// Lỗi đã xảy ra và đã nằm trong repo: `$('#liveInstall').addEventListener(...,
// installGstreamer)` — cả id lẫn hàm **không tồn tại** (GStreamer bị bỏ ở
// §58.15 nhưng dòng này ở lại). `$()` trả `null`, `.addEventListener` ném
// `TypeError` **ngay lúc chạy**, và toàn bộ code sau dòng đó không bao giờ thực
// thi. Đó là lý do nhiều tính năng "đã viết" không có tác dụng trong trình duyệt.
//
// Không công cụ nào bắt được: `node --check` chỉ kiểm cú pháp, còn
// `$('#liveInstall')` là biểu thức hợp lệ. Chỉ có kiểm chéo HTML ↔ JS mới thấy.
test('không có handler nào gắn vào id không tồn tại (§58.15 hậu quả)', () => {
  const htmlIds = new Set([...html.matchAll(/id="([^"]+)"/g)].map(m => m[1]));
  // Bỏ comment rồi lấy mọi `$('#...')` không chứa dấu cách (chuỗi có dấu cách là
  // selector lồng, không phải id).
  const codeApp = code(app);
  const refs = [...codeApp.matchAll(/\$\('#([^'\s]+)'\)/g)].map(m => m[1]);
  const missing = [...new Set(refs)].filter(id => !htmlIds.has(id));
  assert.deepEqual(missing, [],
    `app.js gắn handler vào id không có trong index.html: ${missing.join(', ')}. ` +
    'Đây là TypeError lúc chạy, và nó giết mọi handler phía sau.');
});

// §6.13 — giới hạn trung thực: phải nói **trước**, không để người dùng tự phát hiện.
test('Ctrl+Alt+Del không giả vờ gửi được (§6.13)', () => {
  // Windows chặn SAS từ Vista. "Giả vờ gửi" là nói dối đúng chỗ nguy hiểm:
  // người dùng bấm rồi chờ một màn hình khoá không bao giờ hiện.
  const codeApp = code(app);
  assert.ok(!/Phím tắt đang được mô phỏng/.test(codeApp), 'còn toast giả vờ gửi');
  assert.ok(/SA?S\b|Secure Attention/.test(codeApp), 'phải giải thích lý do thật');
  assert.ok(/Win\+L/.test(codeApp), 'phải gợi ý đường thay thế hoạt động được');
});

test('cảnh báo cửa sổ admin **trước** khi tạo phiên (§6.13)', () => {
  const start = app.indexOf("apiRequest('/api/sessions', { method: 'POST'");
  assert.ok(start > 0, 'phải tìm thấy chỗ tạo phiên');
  const before = app.slice(Math.max(0, start - 1400), start);
  // UIPI: xem được nhưng không điều khiển được. Phát hiện **sau** khi đã bắt
  // đầu là trải nghiệm tệ nhất — người dùng tưởng app hỏng.
  assert.ok(/elevated/.test(before), 'phải kiểm cửa sổ elevated trước khi tạo phiên');
  assert.ok(/UIPI|không điều\s*\n?'?\s*khiển/.test(before) || before.includes('UIPI'),
    'cảnh báo phải nói rõ hệ quả');
});
