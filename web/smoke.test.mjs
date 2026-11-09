// # Smoke test cho `app.js`: chạy **toàn bộ** file trong một DOM giả.
//
// Lỗi đã có thật trong repo: `$('#liveInstall').addEventListener(…)` — id và hàm
// đều không tồn tại (GStreamer bị bỏ ở §58.15). Cú pháp hợp lệ, `node --check`
// im lặng, nhưng lúc chạy `$()` trả `null` ⇒ `TypeError` ⇒ **mọi handler sau
// dòng đó không được gắn**. Tính năng "đã viết xong" không có tác dụng, và không
// có thông báo nào.
//
// Test tĩnh (kiểm chéo id) bắt được trường hợp đó. Test **này** bắt được cả lớp
// lỗi rộng hơn: bất cứ thứ gì ném khi khởi tạo — sai tên hàm, đọc thuộc tính
// của `undefined`, gọi API trình duyệt theo cách sai. Không thay được trình
// duyệt thật, nhưng nó chạy trong 20 ms và bắt đúng loại lỗi đã làm hỏng app
// một lần rồi.
import { readFileSync } from 'node:fs';
const html = readFileSync('web/index.html', 'utf8');
const ids = new Set([...html.matchAll(/id="([^"]+)"/g)].map(m => m[1]));
const listeners = [];
function el(id) {
  const node = {
    id, dataset: {}, style: {}, classList: { add(){}, remove(){}, toggle(){}, contains(){ return true; } },
    children: [], textContent: '', innerHTML: '', value: '', title: '',
    addEventListener(type){ listeners.push(`${id}:${type}`); },
    removeEventListener(){}, setAttribute(){}, getAttribute(){ return null; },
    appendChild(){}, querySelector(){ return null; }, querySelectorAll(){ return []; },
    closest(){ return null; }, focus(){}, getBoundingClientRect(){ return {left:0,top:0,width:100,height:100}; },
  };
  return node;
}
const cache = new Map();
globalThis.document = {
  getElementById: (id) => { if (!cache.has(id)) cache.set(id, el(id)); return cache.get(id); },
  querySelector: (sel) => {
    if (sel.startsWith('#')) {
      const id = sel.slice(1);
      if (!ids.has(id)) return null;   // đúng hành vi thật
      return document.getElementById(id);
    }
    return el(sel);
  },
  querySelectorAll: () => [],
  addEventListener(){}, createElement: () => el('x'), body: el('body'),
  documentElement: el('html'), hidden: false, readyState: 'complete',
};
globalThis.window = { addEventListener(){}, matchMedia: () => ({ matches:false, addEventListener(){} }), location: { href: 'http://x/', search: '' }, dispatchEvent(){} };
globalThis.fetch = async () => ({ ok: false, status: 401, json: async () => ({}) });
globalThis.CustomEvent = class { constructor(t){ this.type = t; } };
globalThis.setTimeout = () => 0; globalThis.setInterval = () => 0; globalThis.clearInterval = () => {};
globalThis.clearTimeout = () => 0;
try {
  new Function(readFileSync('web/app.js', 'utf8'))();
  console.log(`ok — app.js chạy hết, gắn ${listeners.length} listener`);
} catch (error) {
  console.log(`LỖI: ${error.constructor.name}: ${error.message}`);
  process.exit(1);
}
