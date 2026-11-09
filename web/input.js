// §6.4 + §6.5 — client gửi sự kiện chuột/bàn phím. Đây là mảnh khiến điều
// khiển **thực sự chạy**: trước file này, server đã có `SendInput` sau
// `InputSanitizer` (12 test, xác minh bằng curl) nhưng **không một dòng JS nào
// gửi sự kiện**, nên nhìn từ trình duyệt chỉ xem được.
//
// # Vì sao là module riêng, không nhét vào `live_page`
//
// Mọi luật ở đây (throttle theo rAF latest-wins §6.4.3, KHÔNG debounce
// double-click §6.4.2, `setPointerCapture` §6.4.7 lớp 1, `sendBeacon` lớp 3)
// đều là **luật spec viết ra vì đã từng làm sai**. Nhét chúng vào một template
// HTML thì không test được, và cái sai chỉ lộ ra trên máy thật khi nút chuột
// kẹt. Ở đây `npm test` chạy được từng luật.
//
// Không dùng framework, không bundler: một `export` duy nhất, nhận `fetch`
// qua tham số để test thay được.

/** §6.4.1 — bit của `flags` trong message `move` (§8.3). */
export const FLAG_LEFT = 1 << 0;
export const FLAG_RIGHT = 1 << 1;
export const FLAG_MIDDLE = 1 << 2;
export const FLAG_BACK = 1 << 3;
export const FLAG_FORWARD = 1 << 4;
export const FLAG_CTRL = 1 << 5;
export const FLAG_SHIFT = 1 << 6;
export const FLAG_ALT = 1 << 7;

/**
 * `MouseEvent.button` (0=left,1=middle,2=right,3=back,4=forward) → bit của §8.3.
 * Trả `0` cho nút không biết — gửi **không có nút nào bấm** tốt hơn gửi một
 * nút sai (nút sai làm máy thật kẹt chuột, §6.4.7).
 */
export function buttonFlag(button) {
  switch (button) {
    case 0: return FLAG_LEFT;
    case 1: return FLAG_MIDDLE;
    case 2: return FLAG_RIGHT;
    case 3: return FLAG_BACK;
    case 4: return FLAG_FORWARD;
    default: return 0;
  }
}

/**
 * §6.4.4: KHÔNG gửi mỗi `pointermove`. Chuột gaming 1000 Hz gửi 1000 msg/s
 * trong khi §8.3 giới hạn `move` ≤120/s ở client và server drop >200/s.
 *
 * Gộp theo rAF, **latest-wins** (§6.4.3): vị trí cũ bị **bỏ**, không xếp hàng.
 * Xếp hàng thì con trỏ đi theo quỹ đạo người dùng đã vẽ 200 ms trước — cảm
 * giác "lag" cổ điển.
 */
export class MoveThrottle {
  constructor(send, { now = () => Date.now(), requestFrame = (cb) => setTimeout(cb, 16) } = {}) {
    this.send = send;
    this.now = now;
    this.requestFrame = requestFrame;
    this.pending = null;
    this.scheduled = false;
    this.sentCount = 0;
    this.droppedCount = 0;
  }

  /** Ghi nhận vị trí mới nhất; vị trí chưa gửi trước đó bị thay thế. */
  push(x, y, flags = 0, type = 1) {
    if (this.pending) this.droppedCount += 1;
    this.pending = { x, y, flags, type, ts: this.now() };
    if (this.scheduled) return;
    this.scheduled = true;
    this.requestFrame(() => {
      this.scheduled = false;
      const next = this.pending;
      this.pending = null;
      if (!next) return;
      this.sentCount += 1;
      this.send(next);
    });
  }

  /**
   * Gửi ngay, bỏ qua throttle. Dùng cho **down/up**: hai sự kiện đó quyết định
   * một cú click có xảy ra hay không, và gộp chúng vào một frame có thể làm
   * mất `up` (§6.4.7 — nút kẹt).
   */
  flush(x, y, flags = 0, type = 1, wheel = 0) {
    if (this.pending) this.droppedCount += 1;
    this.pending = null;
    this.sentCount += 1;
    // `wheel` phải đi cùng: bản trước của hàm này **bỏ** tham số wheel, nên
    // mọi sự kiện cuộn tới server với `wheel: 0` — cuộn không bao giờ chạy.
    // Test `a wheel event is clamped to the range §8.3 allows` bắt được.
    this.send({ x, y, flags, type, wheel, ts: this.now() });
  }
}

/**
 * §8.3: `|u16 nx|u16 ny|u8 type|u8 flags|i16 wheel|u16 pad|` — 12 byte.
 *
 * `nx`/`ny` là **0..65535** trên toàn khung hình, không phải pixel: đổi kích
 * thước cửa sổ không làm toạ độ cũ trỏ sai chỗ. Server vẫn clamp lại
 * (`InputSanitizer`) vì client không được tin (§41.3).
 */
export function encodeMove({ x, y, flags = 0, type = 1, wheel = 0 }) {
  // §8.3 ghi "12 B" nhưng layout cộng lại 10 (`2+2+1+1+2+2`). Gửi **12** theo
  // con số ở tiêu đề: 10 byte layout + 2 byte pad. Server chấp nhận cả 10 và
  // 12 (`input::parse_move`), nên cả hai cách đọc spec đều chạy.
  const buffer = new ArrayBuffer(12);
  const view = new DataView(buffer);
  const nx = Math.max(0, Math.min(65535, Math.round(x)));
  const ny = Math.max(0, Math.min(65535, Math.round(y)));
  const nw = Math.max(-32768, Math.min(32767, Math.round(wheel)));
  view.setUint16(0, nx, true);
  view.setUint16(2, ny, true);
  view.setUint8(4, type & 0xff);
  view.setUint8(5, flags & 0xff);
  view.setInt16(6, nw, true);
  view.setUint16(8, 0, true); // `pad` u16 theo layout
  view.setUint16(10, 0, true); // 2 byte dư để tròn 12 theo tiêu đề §8.3
  return buffer;
}

/**
 * Đổi toạ độ trong phần tử hiển thị → 0..65535 theo **khung hình thật**.
 *
 * §6.10.3: "Khi zoom local ≠ 1: toạ độ phải map qua transform — nếu không
 * click lệch. Đây là lỗi hay gặp." `object-fit: contain` để lại letterbox, nên
 * phải trừ nó đi trước khi chia — nếu không thì click ở mép dưới luôn lệch.
 */
export function toNormalised(clientX, clientY, rect, frame, mode = 'fit') {
  const frameW = frame.width || rect.width;
  const frameH = frame.height || rect.height;

  // # Ba chế độ hiển thị, ba phép đổi toạ độ khác nhau (§6.10.3)
  //
  // Đây là chỗ bug "click lệch" sinh ra lần thứ hai trong dự án: lần đầu là
  // crop cửa sổ ở server (§5.4), lần này là `object-fit` ở client. Dùng một
  // phép đổi cho cả ba chế độ thì **hai trong ba** chế độ bấm sai chỗ, và chế
  // độ đúng lại là chế độ mặc định — nên bug chỉ hiện khi người dùng đổi sang
  // Fill hoặc 1:1, tức là sau khi họ đã tin app chạy được.
  //
  // - `fit` (contain): letterbox hai bên. Trừ offset, chia cho cạnh hiển thị.
  // - `fill` (cover): ảnh phủ kín, **mép bị cắt**. Không có offset, nhưng phần
  //   tràn phải cộng vào — nếu không, click mép trái lại rơi vào giữa ảnh.
  // - `100` (1:1): một pixel ảnh là một pixel CSS, có thể cuộn. Toạ độ đi
  //   thẳng từ mép ảnh, phép chia là 1.
  let shownW;
  let shownH;
  let offsetX;
  let offsetY;
  if (mode === 'fill') {
    // `cover`: cạnh nào **vượt** thì cạnh đó quyết định tỉ lệ.
    const scale = Math.max(rect.width / frameW, rect.height / frameH);
    shownW = frameW * scale;
    shownH = frameH * scale;
    // Phần tràn bị cắt đều hai bên ⇒ offset **âm** (ảnh bắt đầu trước khung).
    offsetX = (rect.width - shownW) / 2;
    offsetY = (rect.height - shownH) / 2;
  } else if (mode === '100') {
    shownW = frameW;
    shownH = frameH;
    // 1:1 không căn giữa: ảnh bắt đầu ở góc khung và cuộn được. Thẻ `<img>` đã
    // nằm đúng gốc khi `object-fit:none`, nên offset bằng 0.
    offsetX = 0;
    offsetY = 0;
  } else {
    const scale = Math.min(rect.width / frameW, rect.height / frameH);
    shownW = frameW * scale;
    shownH = frameH * scale;
    offsetX = (rect.width - shownW) / 2;
    offsetY = (rect.height - shownH) / 2;
  }

  const x = (clientX - rect.left - offsetX) / shownW;
  const y = (clientY - rect.top - offsetY) / shownH;
  return {
    x: Math.max(0, Math.min(1, x)) * 65535,
    y: Math.max(0, Math.min(1, y)) * 65535,
  };
}

/**
 * §6.5 bàn phím: `{t:"key",down:1,vk:65,mods:2,ts:…}` (§8.3).
 *
 * Dùng `event.keyCode` chứ không `event.code`: spec dùng **virtual-key code**
 * của Windows (§44), và `keyCode` là thứ gần nhất trình duyệt còn cung cấp.
 * `code` (vật lý) khác nhau giữa bàn phím US/DE, còn `vk` là thứ `SendInput`
 * cần. `keyCode` đã deprecated nhưng **vẫn hoạt động ở mọi trình duyệt** —
 * thay bằng gì cũng phải có bảng map riêng, và bảng đó là một bản luật nữa.
 */
export function keyEvent(event) {
  const mods =
    (event.ctrlKey ? FLAG_CTRL : 0) |
    (event.shiftKey ? FLAG_SHIFT : 0) |
    (event.altKey ? FLAG_ALT : 0);
  return { t: 'key', down: event.type === 'keydown' ? 1 : 0, vk: event.keyCode, mods, ts: Date.now() };
}

/**
 * Bộ điều khiển: cắm vào phần tử `<img>`/`<video>` đang hiển thị khung hình.
 *
 * Mọi thứ gửi đi đều qua `post(sid, body)` — một chỗ duy nhất, nên đổi sang
 * WebSocket (§8.2) sau này là đổi **một** hàm, không phải 10 chỗ `fetch`.
 */
export class InputController {
  constructor(element, { sid, post, frame = () => ({ width: 0, height: 0 }), mode = () => 'fit', now = () => Date.now(), threshold = 120 }) {
    this.element = element;
    this.sid = sid;
    this.post = post;
    this.frame = frame;
    // §6.10.3: chế độ hiển thị hiện tại (`fit`/`fill`/`100`). Đọc **mỗi lần
    // click** qua hàm, không chụp lại lúc tạo: người dùng đổi chế độ giữa phiên
    // là chuyện thường, và một giá trị chụp lại sẽ làm mọi click sau đó lệch.
    this.mode = mode;
    // §50.1 #6: `true` mặc định. `setPointerEnabled(false)` tắt **đường chuột**
    // (move/down/up/wheel) mà vẫn giữ bàn phím.
    this.pointerEnabled = true;
    this.now = now;
    this.threshold = threshold;
    this.held = 0;
    this.moveRate = { windowStart: now(), count: 0 };
    this.throttle = new MoveThrottle(
      (move) => this.postMove(move),
      { now, requestFrame: typeof requestAnimationFrame === 'function' ? requestAnimationFrame : (cb) => setTimeout(cb, 16) },
    );
  }

  /** §8.3: server drop `move` >200/s; ở đây tự chặn ở 120/s cho khớp client. */
  postMove({ x, y, flags, type, wheel = 0 }) {
    const ts = this.now();
    if (ts - this.moveRate.windowStart >= 1000) {
      this.moveRate = { windowStart: ts, count: 0 };
    }
    if (this.moveRate.count >= this.threshold) return;
    this.moveRate.count += 1;
    const bytes = encodeMove({ x, y, flags, type, wheel });
    // `Blob` giữ đúng 12 byte nhị phân của §8.3 — base64 sẽ phình 33% và
    // server phải decode lại, trong khi HTTP nhận body nhị phân trực tiếp.
    this.post(`/api/sessions/${this.sid}/move`, new Blob([bytes], { type: 'application/octet-stream' }));
  }

  /** Chuyển một `PointerEvent` thành message `move` (§6.4.1). */
  pointer(event, type) {
    // §50.1 #6: chặn ở **một** chỗ, không ở từng handler. Nếu chặn rải rác thì
    // thêm một đường chuột mới (hoặc một handler mới) sẽ quên, và chế độ "chỉ
    // bàn phím" âm thầm gửi chuột — đúng thứ nó tồn tại để tránh.
    if (!this.pointerEnabled) return false;
    const { x, y } = toNormalised(event.clientX, event.clientY, this.element.getBoundingClientRect(), this.frame(), this.mode());
    // §6.4.1: giữ phím bổ trợ trong cùng `flags` byte.
    const mods =
      (event.ctrlKey ? FLAG_CTRL : 0) |
      (event.shiftKey ? FLAG_SHIFT : 0) |
      (event.altKey ? FLAG_ALT : 0);
    if (type === 1) {
      // Move thường: gộp. `held` vẫn phải đi kèm để server biết đang kéo.
      this.throttle.push(x, y, this.held | mods, 1);
      return;
    }
    const flag = buttonFlag(event.button);
    // §8.3: `flags` trong gói down/up là nút **của sự kiện đó**, không phải
    // toàn bộ nút đang giữ. Nếu gửi `held` *sau* khi nhả thì gói `up` có
    // `flags = 0` ⇒ server không biết nhả nút nào ⇒ từ chối gói `up` ⇒ **nút
    // trái kẹt** (đúng kịch bản §6.4.7, tự gây ra). Đây là lỗi tôi vừa mắc và
    // curl bắt được: `down` 200, `up` 422.
    if (type === 3) this.held |= flag;
    if (type === 4) this.held &= ~flag;
    // Down/up gửi **ngay**: gộp có thể làm mất `up` (§6.4.7).
    this.throttle.flush(x, y, flag | mods, type);
  }

  /**
   * §6.4.7 lớp 1: `setPointerCapture` để vẫn nhận `pointerup` khi con trỏ ra
   * ngoài phần tử — nếu không, kéo ra khỏi khung là nút trái kẹt trên máy thật.
   */
  captureOnDown(event) {
    if (typeof this.element.setPointerCapture === 'function' && event.pointerId !== undefined) {
      try {
        this.element.setPointerCapture(event.pointerId);
      } catch {
        // Trình duyệt không cho (đã nhả capture) — không phải lý do để bỏ click.
      }
    }
  }

  /**
   * §50.1 #6 — bật/tắt đường **chuột** mà không gỡ controller.
   *
   * # Vì sao tắt được chuột là một yêu cầu thật
   *
   * Ở chế độ "mạng rất yếu" (1 fps), hình cập nhật mỗi giây một lần. Bấm chuột
   * bằng **ảnh cũ** nghĩa là bấm vào chỗ nút đó nằm ở một giây trước — nguy
   * hiểm hơn không làm gì. Bàn phím không có vấn đề đó: gõ chữ không phụ thuộc
   * việc bạn thấy con trỏ ở đâu.
   *
   * # Vì sao không gỡ rồi gắn lại controller
   *
   * Hai controller cùng tồn tại là hai nguồn sự thật: `releaseAll` của cái này
   * không biết cái kia đang giữ phím nào. Một cờ ở đây rẻ hơn và đúng hơn.
   *
   * Tắt chuột thì phải **nhả** nút đang giữ trước: nếu người dùng đang kéo một
   * cửa sổ rồi bật chế độ yếu, nút chuột ở lại down trên máy thật.
   */
  setPointerEnabled(enabled) {
    this.pointerEnabled = enabled;
    if (!enabled) {
      try { this.releaseAll('pointer-disabled'); } catch { /* chưa có gì để nhả */ }
    }
  }

  /** §6.4.7 lớp 2 + §6.5: nhả mọi thứ đang giữ. */
  releaseAll(reason = 'blur') {
    if (this.held !== 0 || reason === 'blur') {
      this.held = 0;
      this.post(`/api/sessions/${this.sid}/input`, { t: 'release_all', reason });
      return true;
    }
    return false;
  }

  /** §6.5: `{t:"text",s:"ế"}` — UTF-16, surrogate pair OK (§8.3). */
  text(value) {
    if (!value) return false;
    this.post(`/api/sessions/${this.sid}/input`, { t: 'text', s: value });
    return true;
  }

  /** §6.4.1 wheel: dọc và ngang. */
  wheel(event) {
    const dx = event.deltaX || 0;
    const dy = event.deltaY || 0;
    if (dx === 0 && dy === 0) return;
    const { x, y } = toNormalised(event.clientX, event.clientY, this.element.getBoundingClientRect(), this.frame(), this.mode());
    // §8.3 clamp `wheel ∈ [-2400,2400]`; dấu dy của trình duyệt cùng chiều với
    // `MOUSEEVENTF_WHEEL` (dương = lên), nên không đảo.
    this.throttle.flush(x, y, this.held, 5, Math.max(-2400, Math.min(2400, -dy)));
  }
}

/**
 * §6.4.7 lớp 3: `sendBeacon` khi đóng tab. **Không** phụ thuộc WS còn sống —
 * đó chính là lý do spec dùng `sendBeacon` chứ không `fetch`.
 *
 * `beacon` được truyền vào để test thay được (`navigator.sendBeacon` trong
 * trình duyệt).
 */
export function installUnloadRelease(controller, { beacon, addEventListener }) {
  let fired = false;
  const release = () => {
    if (fired) return;
    fired = true;
    // `release_all` đi qua `/input` (JSON) — server có sẵn; `/release` là
    // `sendBeacon` không cần body (§8.1, §6.4.7 lớp 3).
    beacon(`/api/sessions/${controller.sid}/release`, '');
  };
  // §6.4.7 lớp 2: mất focus / tab ẩn / huỷ con trỏ đều phải nhả.
  addEventListener('blur', () => controller.releaseAll('blur'));
  addEventListener('pagehide', release);
  addEventListener('beforeunload', release);
  return release;
}

/**
 * Cắm toàn bộ sự kiện vào một phần tử. Trả hàm tháo gỡ để test sạch.
 */
export function attach(element, options) {
  const controller = new InputController(element, options);
  const onMove = (event) => controller.pointer(event, 1);
  const onDown = (event) => {
    controller.captureOnDown(event);
    controller.pointer(event, 3);
  };
  const onUp = (event) => controller.pointer(event, 4);
  const onWheel = (event) => {
    event.preventDefault();
    controller.wheel(event);
  };
  const onKeyDown = (event) => {
    // §6.5: phím do ô nhập khác xử lý thì không cướp.
    if (event.target && event.target.dataset && event.target.dataset.remoteInput === 'off') return;
    controller.post(`/api/sessions/${controller.sid}/input`, keyEvent(event));
    // §6.5: `F5`/`F12`/`Ctrl+W` phải để **trình duyệt** xử lý? Không — trong
    // chế độ điều khiển, người dùng muốn gửi tới máy thật, nhưng chặn
    // `Ctrl+W` là chặn đường thoát khi app treo. Chỉ chặn những phím chắc
    // chắn thuộc về phiên.
    if (['Tab', 'Backspace', 'F5'].includes(event.key)) event.preventDefault();
  };
  const onKeyUp = (event) => controller.post(`/api/sessions/${controller.sid}/input`, keyEvent(event));

  // §6.4.3: `pointermove` **kể cả khi không bấm** — nếu không, tooltip/menu
  // hover không bao giờ mở và người dùng thấy "app không phản hồi".
  element.addEventListener('pointermove', onMove);
  element.addEventListener('pointerdown', onDown);
  element.addEventListener('pointerup', onUp);
  // Giữ tham chiếu để `detach` gỡ được. Bản trước dùng arrow inline nên
  // `removeEventListener` không bao giờ gỡ được hai cái này — rò rỉ cho tới
  // khi trang đóng, và trên trang điều khiển thì đó là rò **hành vi**:
  // một phiên đã tách vẫn nhả phím của phiên mới.
  const onCancel = () => controller.releaseAll('pointercancel');
  const onLostCapture = () => controller.releaseAll('lostcapture');
  element.addEventListener('pointercancel', onCancel);
  element.addEventListener('lostpointercapture', onLostCapture);
  element.addEventListener('wheel', onWheel, { passive: false });
  element.addEventListener('keydown', onKeyDown);
  element.addEventListener('keyup', onKeyUp);
  return {
    controller,
    detach() {
      element.removeEventListener('pointermove', onMove);
      element.removeEventListener('pointerdown', onDown);
      element.removeEventListener('pointerup', onUp);
      element.removeEventListener('pointercancel', onCancel);
      element.removeEventListener('lostpointercapture', onLostCapture);
      element.removeEventListener('wheel', onWheel);
      element.removeEventListener('keydown', onKeyDown);
      element.removeEventListener('keyup', onKeyUp);
    },
  };
}
