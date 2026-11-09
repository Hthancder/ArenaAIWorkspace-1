// §58 — mọi hàm `app.js` **gọi** phải tồn tại.
//
// # Vì sao cần test riêng cho việc này
//
// Đã có thật trong repo: `offerResume()` gọi `startLive()`, và `startLive`
// **không được định nghĩa ở đâu cả**. Cú pháp hợp lệ, `node --check` im lặng,
// `smoke.test.mjs` cũng im lặng — vì smoke test chỉ chạy phần khởi tạo, còn
// `offerResume` chỉ chạy khi có phiên cũ. Hệ quả: bấm "Tiếp tục" ở hộp thoại nối
// lại phiên thì `ReferenceError` bị `try { } catch { }` rỗng nuốt, `live.active`
// vẫn `false`, và trang vẫn hiện desktop giả trong khi một phiên **đang chạy
// thật** trên máy. Không có thông báo nào, nên không ai lần ra.
//
// Test này đọc mã nguồn và đối chiếu, nên nó bắt được cả lớp lỗi đó — kể cả
// nhánh chưa từng được chạy trong test nào khác.
import test from 'node:test';
import assert from 'node:assert';
import { readFileSync } from 'node:fs';

/**
 * Bóc comment và literal chuỗi.
 *
 * Không bóc thì test báo sai liên tục: comment trong repo là tiếng Việt có dấu
 * ngoặc đơn, và `Pha 0 (đã xong)` trông y hệt một lời gọi hàm.
 */
function stripNoise(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ')
    .replace(/'(?:\\.|[^'\\])*'/g, "''")
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/`(?:\\.|[^`\\])*`/g, '``');
}

/** Tên được **định nghĩa** trong file: khai báo hàm, biến, tham số. */
function declaredNames(code) {
  const names = new Set();
  for (const m of code.matchAll(/function\s+([A-Za-z_$][\w$]*)/g)) names.add(m[1]);
  for (const m of code.matchAll(/class\s+([A-Za-z_$][\w$]*)/g)) names.add(m[1]);
  for (const m of code.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g)) names.add(m[1]);
  for (const m of code.matchAll(/\(([^)]*)\)\s*(?:=>|\{)/g)) {
    for (const part of m[1].split(',')) {
      const name = part.trim().split(/[=:]/)[0].trim();
      if (/^[A-Za-z_$][\w$]*$/.test(name)) names.add(name);
    }
  }
  // `catch (error)` và `for (const x of …)`.
  for (const m of code.matchAll(/catch\s*\(\s*([A-Za-z_$][\w$]*)/g)) names.add(m[1]);
  for (const m of code.matchAll(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)/g)) names.add(m[1]);
  return names;
}

/** Tên được **gọi** dưới dạng `name(` mà không phải `obj.name(`. */
function calledNames(code) {
  return new Set(
    [...code.matchAll(/(?<![.\w$])([A-Za-z_$][\w$]*)\s*\(/g)].map(m => m[1])
  );
}

const KEYWORDS = new Set([
  'if', 'for', 'while', 'switch', 'catch', 'return', 'typeof', 'function', 'await',
  'new', 'else', 'do', 'try', 'in', 'of', 'delete', 'void', 'yield', 'instanceof',
  // Từ khoá phụ khi bóc chuỗi: `import('/x.js')` và `async () =>`.
  'import', 'async',
]);

/**
 * Tên **dựng sẵn** của JS và của môi trường chạy.
 *
 * Bóc chuỗi làm mất ngữ cảnh, nên `new Blob(…)` trông như gọi một hàm `Blob`
 * chưa khai báo. Danh sách dưới đây là các constructor/hàm toàn cục **thật sự**
 * tồn tại trong trình duyệt; thêm tên vào đây là một lời khẳng định rằng nó có
 * trong môi trường đích, không phải cách để làm test xanh.
 */
const GLOBALS = new Set([
  'Error', 'TypeError', 'RangeError', 'String', 'Number', 'Boolean', 'Object',
  'Array', 'Set', 'Map', 'WeakMap', 'Promise', 'Blob', 'File', 'FormData',
  'DataView', 'ArrayBuffer', 'Uint8Array', 'Uint16Array', 'Int16Array', 'Float32Array',
  'setTimeout', 'clearTimeout', 'setInterval', 'clearInterval',
  'requestAnimationFrame', 'cancelAnimationFrame', 'queueMicrotask',
  'parseInt', 'parseFloat', 'isNaN', 'isFinite', 'encodeURIComponent',
  'decodeURIComponent', 'fetch', 'alert', 'confirm', 'URL', 'Date', 'Math',
  'JSON', 'RegExp', 'Symbol', 'structuredClone', 'super', 'constructor',
]);

test('app.js không gọi hàm nào không tồn tại (§58)', () => {
  const code = stripNoise(readFileSync('web/app.js', 'utf8'));
  const declared = declaredNames(code);
  const missing = [...calledNames(code)].filter(
    name => !declared.has(name) && !KEYWORDS.has(name) && !GLOBALS.has(name)
  );
  assert.deepEqual(
    missing, [],
    `app.js gọi những tên không được định nghĩa ở đâu: ${missing.join(', ')}. `
    + 'Đây đúng là lỗi `startLive` — ReferenceError bị catch rỗng nuốt, tính năng '
    + 'im lặng không chạy.'
  );
});

test('mọi hàm mà app.js gọi tới đều tồn tại (§58)', () => {
  // Đây là test đã tìm ra `startLive`. Giữ nó **chỉ** cho `app.js` — nơi mọi thứ
  // gọi trực tiếp trong closure. Ở `input.js`/`chip.js`, phần lớn lời gọi là
  // method của `this` hoặc callback do người gọi truyền vào (`options.onMove`),
  // nên phân tích tĩnh ở đó chỉ sinh báo sai: đã thử, và nó liệt kê 15 "hàm
  // không tồn tại" mà tất cả đều là `this.releaseAll` / `array.push`.
  const code = stripNoise(readFileSync('web/app.js', 'utf8'));
  const declared = declaredNames(code);
  const missing = [...calledNames(code)].filter(
    name => !declared.has(name) && !KEYWORDS.has(name) && !GLOBALS.has(name)
  );
  assert.deepEqual(missing, [], `app.js gọi tên không tồn tại: ${missing.join(', ')}`);
});

test('mọi id mà app.js tra cứu đều có trong index.html (§58)', () => {
  // `$('#liveInstall')` từng trỏ tới một id **không tồn tại** sau khi GStreamer bị
  // bỏ (§58.15): `$()` trả `null`, và mọi handler gắn **sau** dòng đó không bao
  // giờ chạy. smoke.test.mjs đã bắt được lần đó; test này bắt cùng lớp lỗi nhưng
  // đọc thẳng từ danh sách id nên không phụ thuộc thứ tự khởi tạo.
  // **Bỏ comment trước.** `#liveInstall` chỉ còn trong đoạn ghi chú giải thích
  // vì sao dòng đó đã bị xoá; quét cả comment sẽ báo lỗi cho một dòng không còn
  // tồn tại — và cách "sửa" duy nhất là xoá ghi chú, tức là xoá đúng thứ đang
  // ngăn người sau thêm lại nó.
  const js = stripNoise(readFileSync('web/app.js', 'utf8'));
  const html = readFileSync('web/index.html', 'utf8');
  const ids = new Set([...html.matchAll(/id="([^"]+)"/g)].map(m => m[1]));
  // Chỉ những id được dùng làm selector, không phải chuỗi bất kỳ.
  const referenced = new Set(
    [...js.matchAll(/[$(]\s*['"]#([A-Za-z0-9_-]+)['"]/g)].map(m => m[1])
  );
  const missing = [...referenced].filter(id => !ids.has(id));
  assert.deepEqual(missing, [], `app.js tra cứu id không có trong HTML: ${missing.join(', ')}`);
});
