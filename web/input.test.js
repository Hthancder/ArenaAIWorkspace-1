// Test cho `web/input.js` — §6.4 (chuột), §6.5 (bàn phím), §6.4.7 (kẹt nút).
//
// # Vì sao test này quan trọng hơn vẻ ngoài của nó
//
// Mỗi luật ở đây là một luật spec viết ra **vì đã từng làm sai**, và cái sai
// chỉ lộ ra trên máy thật:
//
// * throttle latest-wins → nếu queue, con trỏ đi chậm 200 ms (§6.4.3)
// * down/up phải gửi **ngay** → nếu gộp, mất `up`, nút trái kẹt vĩnh viễn
//   cho tới khi watchdog 3 s của server cứu (§6.4.7 lớp 4)
// * không debounce double-click → nếu debounce 300 ms, double-click **không
//   bao giờ** hoạt động (§6.4.2)
// * letterbox của `object-fit: contain` phải trừ → nếu không, click lệch ở
//   mép (§6.10.3)
// * `sendBeacon` lúc unload → nếu dựa vào WS, đóng tab là kẹt phím
//
// Không có DOM thật trong `node --test`, nên `InputController` được cấp
// `post` và `frame` giả — đó **chính là** lý do module này tách khỏi HTML.

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  FLAG_ALT,
  FLAG_CTRL,
  FLAG_LEFT,
  FLAG_MIDDLE,
  FLAG_RIGHT,
  FLAG_SHIFT,
  InputController,
  MoveThrottle,
  attach,
  buttonFlag,
  encodeMove,
  installUnloadRelease,
  keyEvent,
  toNormalised,
} from '../web/input.js';

/** Phần tử giả: chỉ đủ cho `getBoundingClientRect` + capture. */
function fakeElement(rect = { left: 0, top: 0, width: 1600, height: 900 }) {
  const handlers = new Map();
  return {
    rect,
    captured: [],
    getBoundingClientRect: () => rect,
    setPointerCapture(id) { this.captured.push(id); },
    addEventListener(name, fn) { handlers.set(name, fn); },
    removeEventListener(name) { handlers.delete(name); },
    fire(name, event) { handlers.get(name)?.(event); },
    handlers,
  };
}

/** `post` giả: ghi lại mọi lời gọi. */
function recorder() {
  const calls = [];
  const post = (path, body) => { calls.push({ path, body }); };
  return { calls, post };
}

test('buttonFlag maps every pointer button the spec lists', () => {
  // §6.4.1: trái/phải/giữa + nút 4/5 (back/forward).
  assert.equal(buttonFlag(0), FLAG_LEFT);
  assert.equal(buttonFlag(1), FLAG_MIDDLE);
  assert.equal(buttonFlag(2), FLAG_RIGHT);
  assert.equal(buttonFlag(3), 1 << 3);
  assert.equal(buttonFlag(4), 1 << 4);
  // Nút lạ ⇒ 0, **không** đoán. Gửi một nút sai làm máy thật kẹt chuột.
  assert.equal(buttonFlag(9), 0);
  assert.equal(buttonFlag(undefined), 0);
});

test('encodeMove writes exactly the 12 bytes of §8.3', () => {
  const buffer = encodeMove({ x: 0, y: 65535, flags: FLAG_LEFT | FLAG_CTRL, type: 3, wheel: -120 });
  assert.equal(buffer.byteLength, 12, '§8.3 ghi 12 byte, không phải 13');

  const view = new DataView(buffer);
  assert.equal(view.getUint16(0, true), 0, 'nx');
  assert.equal(view.getUint16(2, true), 65535, 'ny');
  assert.equal(view.getUint8(4), 3, 'type=down');
  assert.equal(view.getUint8(5), FLAG_LEFT | FLAG_CTRL, 'flags');
  assert.equal(view.getInt16(6, true), -120, 'wheel có dấu');
  assert.equal(view.getUint16(8, true), 0, 'pad');
});

test('encodeMove clamps instead of trusting the client', () => {
  // §41.3: client không được tin. Server vẫn clamp lại, nhưng gửi số vô lý
  // làm body dài ra vô ích và làm log khó đọc.
  const view = new DataView(encodeMove({ x: -50, y: 999999, flags: 999, type: 300, wheel: 99999 }));
  assert.equal(view.getUint16(0, true), 0);
  assert.equal(view.getUint16(2, true), 65535);
  assert.equal(view.getUint8(4), 300 & 0xff);
  assert.equal(view.getInt16(6, true), 32767);
});

test('toNormalised removes the letterbox of object-fit: contain', () => {
  // §6.10.3: khung 4:3 nằm trong hộp 16:9 ⇒ có viền hai bên. Bấm đúng tâm
  // phải ra 0.5/0.5; bấm ở mép **khung hình** phải ra 0 hoặc 1.
  const rect = { left: 0, top: 0, width: 1600, height: 900 };
  const frame = { width: 1024, height: 768 }; // 4:3
  const centre = toNormalised(800, 450, rect, frame);
  assert.equal(Math.round(centre.x), 32768, 'tâm ngang');
  assert.equal(Math.round(centre.y), 32768, 'tâm dọc');
  // Cạnh trái của **khung** (không phải của hộp): hộp rộng 1600, khung 1200.
  const leftEdge = toNormalised(200, 450, rect, frame);
  assert.equal(Math.round(leftEdge.x), 0, 'mép trái khung ⇒ 0');
  const outside = toNormalised(0, 0, rect, frame);
  assert.equal(Math.round(outside.x), 0, 'viền trái bị kẹp về 0');
});

test('the move throttle keeps only the newest position (§6.4.3)', () => {
  // §6.4.4: chuột gaming 1000 Hz không được thành 1000 msg/s. Gộp theo frame,
  // **latest-wins** — vị trí cũ bị *bỏ*, không xếp hàng.
  const sent = [];
  const frames = [];
  const throttle = new MoveThrottle((move) => sent.push(move), {
    now: () => 1000,
    requestFrame: (cb) => frames.push(cb),
  });
  throttle.push(10, 10);
  throttle.push(20, 20);
  throttle.push(30, 30);
  assert.equal(sent.length, 0, 'chưa tới frame thì chưa gửi');
  assert.equal(frames.length, 1, 'chỉ hẹn **một** frame, không hẹn 3');
  frames[0]();
  assert.equal(sent.length, 1);
  assert.deepEqual([sent[0].x, sent[0].y], [30, 30], 'phải là vị trí **mới nhất**');
  assert.equal(throttle.droppedCount, 2, 'hai vị trí bị bỏ — đếm được để chẩn đoán');
});

test('pointer down and up are never coalesced away (§6.4.7)', () => {
  // Đây là bug tệ nhất có thể có trong file này: gộp `up` vào frame ⇒ server
  // không bao giờ nhận `up` ⇒ **nút trái kẹt** trên máy thật, người ngồi máy
  // không click được gì cho tới khi watchdog 3 s của server cứu.
  const { calls, post } = recorder();
  const element = fakeElement();
  const controller = new InputController(element, { sid: 's1', post, frame: () => ({ width: 1600, height: 900 }) });
  const down = { clientX: 800, clientY: 450, button: 0, ctrlKey: false, shiftKey: false, altKey: false };
  controller.pointer(down, 3);
  controller.pointer(down, 4);
  const moves = calls.filter((call) => call.path === '/api/sessions/s1/move');
  assert.equal(moves.length, 2, 'down và up phải gửi **ngay**, không chờ frame');
});

test('an up packet names the button it releases (§8.3)', () => {
  // Bug thật: client gửi `flags = held` **sau** khi nhả ⇒ gói `up` có
  // `flags = 0` ⇒ server trả 422 (`a_button_packet_with_no_button_bit_is_refused`)
  // ⇒ nút người dùng vừa nhả **không được nhả** trên máy thật. curl bắt được:
  // `down` 200, `up` 422.
  const { calls, post } = recorder();
  const controller = new InputController(fakeElement(), {
    sid: 's1',
    post,
    frame: () => ({ width: 1600, height: 900 }),
    now: () => 0,
  });
  const event = { clientX: 10, clientY: 10, button: 0, ctrlKey: false, shiftKey: false, altKey: false };
  controller.pointer(event, 3); // down
  controller.pointer(event, 4); // up
  const moves = calls.filter((call) => call.path === '/api/sessions/s1/move');
  return Promise.all(moves.map((call) => call.body.arrayBuffer())).then((buffers) => {
    const downFlags = new DataView(buffers[0]).getUint8(5);
    const upFlags = new DataView(buffers[1]).getUint8(5);
    assert.equal(downFlags & FLAG_LEFT, FLAG_LEFT, 'down phải nói nút trái');
    assert.equal(upFlags & FLAG_LEFT, FLAG_LEFT, 'up cũng phải nói nút trái, không được là 0');
    assert.equal(controller.held, 0, 'nội bộ vẫn phải sạch sau khi nhả');
  });
});

test('a drag keeps the held button in the move flags', () => {
  const { calls, post } = recorder();
  const element = fakeElement();
  const frames = [];
  const controller = new InputController(element, {
    sid: 's1',
    post,
    frame: () => ({ width: 1600, height: 900 }),
    now: () => 1000,
  });
  controller.throttle.requestFrame = (cb) => frames.push(cb);
  const base = { clientX: 400, clientY: 300, button: 0, ctrlKey: false, shiftKey: false, altKey: false };
  controller.pointer(base, 3); // down
  controller.pointer(base, 1); // move (kéo)
  frames.forEach((cb) => cb());
  const moves = calls.filter((call) => call.path === '/api/sessions/s1/move');
  const last = moves[moves.length - 1];
  // `Blob` không đọc được đồng bộ trong Node, nên đọc qua `arrayBuffer()`.
  return last.body.arrayBuffer().then((buffer) => {
    assert.equal(buffer.byteLength, 12);
    assert.equal(new DataView(buffer).getUint8(5) & FLAG_LEFT, FLAG_LEFT, 'đang kéo ⇒ bit trái phải bật');
  });
});

test('the move rate is capped at 120/s, matching §8.3', () => {
  // Client gửi ≤120/s; server drop >200/s. Vượt ở client chỉ làm tốn băng
  // thông rồi bị drop — không có ích gì.
  const { calls, post } = recorder();
  let clock = 0;
  const controller = new InputController(fakeElement(), {
    sid: 's1',
    post,
    frame: () => ({ width: 1600, height: 900 }),
    now: () => clock,
  });
  for (let index = 0; index < 200; index += 1) {
    controller.postMove({ x: index, y: index, flags: 0, type: 1 });
  }
  assert.equal(calls.length, 120, 'phải chặn ở 120/s');
  clock = 1001; // sang giây mới
  controller.postMove({ x: 1, y: 1, flags: 0, type: 1 });
  assert.equal(calls.length, 121, 'cửa sổ trượt phải mở lại sau 1 s');
});

test('keyEvent carries the Windows virtual-key code and modifiers (§6.5)', () => {
  const down = keyEvent({ type: 'keydown', keyCode: 65, ctrlKey: true, shiftKey: false, altKey: false });
  assert.deepEqual(
    { t: down.t, down: down.down, vk: down.vk, mods: down.mods },
    { t: 'key', down: 1, vk: 65, mods: FLAG_CTRL },
  );
  const up = keyEvent({ type: 'keyup', keyCode: 65, ctrlKey: false, shiftKey: true, altKey: true });
  assert.equal(up.down, 0);
  assert.equal(up.mods, FLAG_SHIFT | FLAG_ALT);
  assert.ok(up.ts > 0, 'phải có timestamp thật (§6.4.2: OS tự nhận double-click theo timing)');
});

test('text events keep Vietnamese as one string (§8.3)', () => {
  const { calls, post } = recorder();
  const controller = new InputController(fakeElement(), { sid: 's1', post, frame: () => ({ width: 1, height: 1 }) });
  assert.equal(controller.text('ế'), true);
  assert.equal(calls[0].path, '/api/sessions/s1/input');
  assert.deepEqual(calls[0].body, { t: 'text', s: 'ế' });
  // Rỗng thì không gửi — một message rỗng chỉ tốn một lượt round-trip.
  assert.equal(controller.text(''), false);
  assert.equal(calls.length, 1);
});

test('releaseAll always fires so a stuck button cannot survive focus loss (§6.4.7 lớp 2)', () => {
  const { calls, post } = recorder();
  const controller = new InputController(fakeElement(), { sid: 's1', post, frame: () => ({ width: 1, height: 1 }) });
  const base = { clientX: 1, clientY: 1, button: 0, ctrlKey: false, shiftKey: false, altKey: false };
  controller.pointer(base, 3); // đang giữ chuột trái
  const sent = controller.releaseAll('blur');
  assert.equal(sent, true);
  const release = calls.find((call) => call.body && call.body.t === 'release_all');
  assert.ok(release, 'phải gửi release_all');
  assert.equal(controller.held, 0, 'trạng thái nội bộ phải sạch');
});

test('a wheel event is clamped to the range §8.3 allows', () => {
  const { calls, post } = recorder();
  const controller = new InputController(fakeElement(), {
    sid: 's1',
    post,
    frame: () => ({ width: 1600, height: 900 }),
    now: () => 0,
  });
  controller.wheel({ clientX: 800, clientY: 450, deltaX: 0, deltaY: -99999 });
  const move = calls.find((call) => call.path === '/api/sessions/s1/move');
  return move.body.arrayBuffer().then((buffer) => {
    const wheel = new DataView(buffer).getInt16(6, true);
    assert.equal(wheel, 2400, 'clamp [-2400, 2400]');
    assert.equal(new DataView(buffer).getUint8(4), 5, 'type=5 là wheel (§8.3)');
  });
});

test('unload sends a beacon exactly once (§6.4.7 lớp 3)', () => {
  // Nếu dựa vào WebSocket, đóng tab là mất `release` và phím kẹt. `sendBeacon`
  // không phụ thuộc kết nối nào còn sống — đó là toàn bộ lý do spec chọn nó.
  const beacons = [];
  const listeners = new Map();
  const controller = { sid: 'abc', releaseAll: () => {} };
  const release = installUnloadRelease(controller, {
    beacon: (path, body) => { beacons.push({ path, body }); return true; },
    addEventListener: (name, fn) => listeners.set(name, fn),
  });
  listeners.get('pagehide')();
  listeners.get('beforeunload')(); // cả hai cùng bắn là chuyện bình thường
  release(); // gọi lại lần nữa cũng không được bắn thêm
  assert.equal(beacons.length, 1, 'chỉ một beacon, không spam server');
  assert.equal(beacons[0].path, '/api/sessions/abc/release');
});

test('attach wires the events the spec requires and can be detached', () => {
  const { calls, post } = recorder();
  const element = fakeElement();
  const { controller, detach } = attach(element, { sid: 's1', post, frame: () => ({ width: 1600, height: 900 }) });
  // §6.4.3: hover phải gửi move **kể cả khi không bấm** — thiếu nó thì
  // tooltip/menu hover không mở và người dùng thấy "app không phản hồi".
  assert.ok(element.handlers.has('pointermove'));
  assert.ok(element.handlers.has('pointerdown'));
  assert.ok(element.handlers.has('pointerup'));
  assert.ok(element.handlers.has('wheel'));
  assert.ok(element.handlers.has('pointercancel'));
  assert.ok(element.handlers.has('lostpointercapture'));
  assert.ok(element.handlers.has('keydown'));
  assert.ok(element.handlers.has('keyup'));

  // §6.4.7 lớp 1: `pointerdown` phải `setPointerCapture` để `pointerup` vẫn
  // tới khi con trỏ ra ngoài phần tử.
  element.fire('pointerdown', {
    clientX: 10, clientY: 10, button: 0, pointerId: 7,
    ctrlKey: false, shiftKey: false, altKey: false,
  });
  assert.deepEqual(element.captured, [7], 'phải giữ con trỏ');

  detach();
  assert.equal(element.handlers.size, 0, 'detach phải gỡ hết');
  assert.equal(controller.held, FLAG_LEFT);
});
