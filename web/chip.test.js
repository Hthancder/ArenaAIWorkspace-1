// §30.7 — hàng chip sticky modifier. Logic "bật → dùng một lần → tự nhả" là chỗ
// dễ sai nhất, và sai nó thì **mọi** phím gõ sau đó đều bị chèn modifier: người
// dùng gõ "a" và nhận Ctrl+A (chọn tất cả) — một lỗi trông như app hỏng.
import test from 'node:test';
import assert from 'node:assert';
import { ChipState, MOD, VK, attachChips } from './chip.js';

test('chạm một lần: bật, áp cho phím kế tiếp, rồi tự nhả (§30.7)', () => {
  const state = new ChipState();
  assert.equal(state.toggle('ctrl'), 'on', 'chạm đầu = bật');
  assert.equal(state.mask(), MOD.ctrl, 'phải áp cho phím tới');
  state.consumed();
  assert.equal(state.mask(), 0, 'sticky = dùng **một** lần, rồi nhả');
});

test('chạm hai lần: khoá, không tự nhả (§30.7)', () => {
  const state = new ChipState();
  state.toggle('ctrl');
  assert.equal(state.toggle('ctrl'), 'locked', 'chạm hai = khoá');
  state.consumed();
  assert.equal(state.mask(), MOD.ctrl, 'khoá thì ở lại sau phím kế tiếp');
  // Chạm lần ba = tắt hẳn.
  assert.equal(state.toggle('ctrl'), 'off');
  assert.equal(state.mask(), 0);
});

test('Ctrl+Shift cùng lúc: hai bit, không ghi đè nhau (§30.7)', () => {
  const state = new ChipState();
  state.toggle('ctrl');
  state.toggle('shift');
  assert.equal(state.mask(), MOD.ctrl | MOD.shift);
  // Một lần dùng nhả **cả hai** — đúng "áp dụng cho phím kế tiếp".
  state.consumed();
  assert.equal(state.mask(), 0);
});

test('khoá Ctrl rồi bật Shift: hai bit, chỉ Shift tự nhả (§30.7)', () => {
  // Kịch bản thật: Ctrl+Shift+Esc. Khoá Ctrl (chạm hai lần), bật Shift (chạm
  // một), bấm Esc ⇒ cả hai áp. Sau đó Ctrl ở lại (đã khoá), Shift nhả.
  const state = new ChipState();
  state.toggle('ctrl');
  state.toggle('ctrl');     // khoá Ctrl
  state.toggle('shift');    // bật Shift (chưa khoá)
  assert.equal(state.mask(), MOD.ctrl | MOD.shift);
  state.consumed();
  assert.equal(state.mask(), MOD.ctrl, 'Ctrl ở lại vì đã khoá, Shift nhả');
});

test('reset nhả cả khoá, không chỉ active (§30.7)', () => {
  // Nếu `reset` chỉ xoá `active` thì một chip đã khoá sống qua lần ẩn bàn phím
  // sau, và người dùng gõ chữ đầu tiên nhận Ctrl+chữ mà không hiểu vì sao.
  const state = new ChipState();
  state.toggle('ctrl');
  state.toggle('ctrl'); // khoá
  state.reset();
  assert.equal(state.mask(), 0);
  assert.equal(state.locked, 0);
  assert.equal(state.active, 0);
});

test('VK của chip khớp giá trị Windows (§44)', () => {
  // Tra theo Win32 `Virtual-Key Codes`, không đoán: Esc 0x1B, Tab 0x09,
  // Backspace 0x08, mũi tên 0x25–0x28.
  assert.equal(VK.escape, 0x1b);
  assert.equal(VK.tab, 0x09);
  assert.equal(VK.backspace, 0x08);
  assert.equal(VK.up, 0x26);
  assert.equal(VK.down, 0x28);
  assert.equal(VK.left, 0x25);
  assert.equal(VK.right, 0x27);
});

test('mỗi phím chip gửi **cả down và up** (§30.7)', () => {
  // Chỉ gửi down thì phím ở lại trạng thái giữ trên máy đích và tự lặp
  // (auto-repeat): gõ Tab một lần sẽ chuyển focus mãi không dừng.
  const sent = [];
  const root = fakeChipRoot();
  attachChips(root, { send: (vk, down, mods) => sent.push({ vk, down, mods }) });
  root.click({ key: 'tab' });
  assert.deepEqual(sent.map(s => s.down), [1, 0], 'phải có down rồi up');
  assert.equal(sent[0].vk, VK.tab);
});

test('phím chip mang modifier đang bật, rồi tự nhả (§30.7)', () => {
  const sent = [];
  const root = fakeChipRoot();
  const controller = attachChips(root, { send: (vk, down, mods) => sent.push({ vk, down, mods }) });
  root.click({ mod: 'ctrl' });
  root.click({ key: 'tab' });
  assert.equal(sent[0].mods, MOD.ctrl, 'phím đầu mang Ctrl');
  // Phím thứ hai **không** mang Ctrl — sticky đã nhả.
  root.click({ key: 'tab' });
  assert.equal(sent[2].mods, 0, 'sticky phải nhả sau một lần dùng');
  assert.equal(controller.state.mask(), 0);
});

/** DOM giả tối thiểu cho hàng chip: đủ `querySelectorAll` + `click`. */
function fakeChipRoot() {
  const buttons = [];
  const handlers = new Map();
  const makeButton = (dataset) => {
    const button = {
      dataset,
      attrs: {},
      setAttribute(name, value) { this.attrs[name] = value; },
      getAttribute(name) { return this.attrs[name]; },
    };
    buttons.push(button);
    return button;
  };
  // Chip modifier cần có mặt trong `querySelectorAll` để `paint` đổi trạng thái.
  ['ctrl', 'alt', 'shift'].forEach(mod => buttons.push({
    dataset: { mod }, attrs: {},
    setAttribute(name, value) { this.attrs[name] = value; },
    getAttribute(name) { return this.attrs[name]; },
  }));
  return {
    querySelectorAll: () => buttons.filter(b => b.dataset.mod),
    addEventListener: (type, fn) => handlers.set(type, fn),
    removeEventListener: () => handlers.delete('click'),
    /**
     * Giả lập một cú chạm vào chip có `data-*` cho trước.
     *
     * `closest('.chip')` phải trả về **chính** phím: trong DOM thật một cú chạm
     * vào chữ bên trong `<button>` có `event.target` là node con, và `closest`
     * mới leo lên được `button`. `preventDefault` nằm trên **event**, không phải
     * `target` — bản đầu của test đặt nhầm và báo "không gửi gì" trong khi code
     * đúng.
     */
    click(dataset) {
      const handler = handlers.get('click');
      const target = { dataset };
      target.closest = () => target;
      handler({ target, preventDefault() {} });
    },
  };
}
