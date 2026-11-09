// §30.7 — hàng chip **sticky modifier** cho điện thoại.
//
// # Vì sao chip chứ không phải bàn phím tự vẽ
//
// Bàn phím ảo chiếm ~50 % màn hình điện thoại. Tự vẽ bàn phím đầy đủ nghĩa là:
// sai ngôn ngữ, sai IME (không gõ được tiếng Việt có dấu), và chiếm gấp đôi chỗ.
// Spec nói rõ: *"Chỉ 1 hàng chip (36 px) … Các phím khác dùng bàn phím ảo của HĐH
// (đúng ngôn ngữ, đúng IME, không phải tự vẽ)"*.
//
// Chip chỉ cấp thứ bàn phím HĐH **không** có: `Ctrl`, `Alt`, `Shift`, `Esc`,
// `Tab`, `⌫`, và bốn phím mũi tên.
//
// # Sticky nghĩa là gì (và vì sao nó là chi tiết quan trọng nhất)
//
// Chạm `Ctrl` → sáng → chạm `C` → gửi **Ctrl+C** → `Ctrl` tự tắt. Không có cơ chế
// này thì để bấm Ctrl+C người dùng phải giữ Ctrl bằng một ngón và bấm C bằng ngón
// khác — trên bàn phím HĐH không làm được (không có phím Ctrl thật).
// Chạm **hai lần** = khoá (dùng cho Ctrl+Shift+Esc hay nhiều phím liên tiếp).

/** VK của các phím chỉ tồn tại trên chip, không có trên bàn phím điện thoại. */
export const VK = {
  escape: 0x1b,
  tab: 0x09,
  backspace: 0x08,
  up: 0x26,
  down: 0x28,
  left: 0x25,
  right: 0x27,
};

/** Modifier bit của §8.3 — khớp `FLAG_CTRL/FLAG_SHIFT/FLAG_ALT` trong `input.js`. */
export const MOD = { ctrl: 1, shift: 2, alt: 4 };

/**
 * Trạng thái chip: cái nào đang bật, cái nào đã **khoá**.
 *
 * Tách khỏi DOM để kiểm được bằng test mà không cần trình duyệt — logic sticky
 * (bật → dùng một lần → tự nhả) là chỗ dễ sai nhất của tính năng này.
 */
export class ChipState {
  constructor() {
    /** Modifier đang bật cho phím kế tiếp. */
    this.active = 0;
    /** Modifier đã khoá (chạm hai lần) — không tự nhả sau phím kế tiếp. */
    this.locked = 0;
  }

  /**
   * Chạm một modifier. Trả `'on'`, `'locked'` hoặc `'off'` để UI đổi `aria-pressed`
   * — dùng `aria-pressed` chứ không chỉ đổi class: trạng thái chỉ bằng **màu** là
   * không đọc được bằng trình đọc màn hình và không phân biệt được khi mù màu.
   */
  toggle(name) {
    const bit = MOD[name];
    if (!bit) return 'off';
    if (this.locked & bit) {
      // Đang khoá ⇒ chạm lần nữa là tắt hẳn.
      this.locked &= ~bit;
      this.active &= ~bit;
      return 'off';
    }
    if (this.active & bit) {
      // Đang bật (chưa khoá) ⇒ chạm lần hai = khoá.
      this.locked |= bit;
      return 'locked';
    }
    this.active |= bit;
    return 'on';
  }

  /** Bitmask để gửi kèm phím. */
  mask() {
    return this.active | this.locked;
  }

  /**
   * Gọi **sau khi** đã gửi một phím: modifier chưa khoá tự nhả.
   *
   * Đây chính là "sticky": một lần dùng. Modifier đã khoá thì ở lại.
   */
  consumed() {
    this.active = this.locked;
  }

  /** Nhả hết — khi ẩn bàn phím, khi mất focus, khi `release_all`. */
  reset() {
    this.active = 0;
    this.locked = 0;
  }
}

/**
 * Cắm hàng chip vào DOM.
 *
 * `send(vk, down, mods)` do nơi gọi cấp — nó biết gửi đi đâu (`InputController`).
 * Ở đây chỉ quyết định **gửi gì**, không quyết định **gửi thế nào**: cùng một
 * chia tách đã dùng ở `input.js` và nó giúp test được mà không cần mạng.
 */
export function attachChips(root, { send, state = new ChipState() } = {}) {
  if (!root) return null;

  const paint = () => {
    root.querySelectorAll('.chip[data-mod]').forEach((button) => {
      const bit = MOD[button.dataset.mod];
      let pressed = 'false';
      if (state.locked & bit) pressed = 'locked';
      else if (state.active & bit) pressed = 'true';
      button.setAttribute('aria-pressed', pressed);
    });
  };

  /**
   * Gửi một phím "một lần bấm": down rồi up.
   *
   * Gửi **cả up**: nếu chỉ gửi down thì trên máy đích phím ở lại trạng thái giữ
   * và tự lặp (auto-repeat) — gõ `Tab` một lần sẽ chuyển focus mãi không dừng.
   */
  const tap = (vk) => {
    const mods = state.mask();
    send(vk, 1, mods);
    send(vk, 0, mods);
    state.consumed();
    paint();
  };

  const onClick = (event) => {
    const button = event.target.closest('.chip');
    if (!button) return;
    // Giữ focus ở phần tử nhận phím: nếu chip chiếm focus, bàn phím HĐH **đóng**
    // và người dùng phải chạm lại vào khung hình — đúng sự ức chế §30.7 cấm.
    event.preventDefault();

    if (button.dataset.mod) {
      state.toggle(button.dataset.mod);
      paint();
      return;
    }
    if (button.dataset.key) {
      tap(VK[button.dataset.key]);
      return;
    }
    if (button.dataset.arrow) {
      tap(VK[button.dataset.arrow]);
    }
  };

  root.addEventListener('click', onClick);
  paint();
  return {
    state,
    paint,
    /** Gọi khi ẩn bàn phím: trạng thái chip không được sống qua lần mở sau. */
    reset() {
      state.reset();
      paint();
    },
    detach() {
      root.removeEventListener('click', onClick);
    },
  };
}

/**
 * §30.7 — *"Video KHÔNG bị che — nó co lại"*.
 *
 * `visualViewport.height` là chiều cao **thật** còn nhìn được; khi bàn phím HĐH
 * mở, nó nhỏ hơn `window.innerHeight` đúng bằng chiều cao bàn phím. Chênh lệch
 * đó chính là `padding-bottom` cần đặt cho khung hình để video co lại thay vì bị
 * che.
 *
 * Dùng `visualViewport` chứ không `resize`: trên iOS, mở bàn phím **không** làm
 * `window.innerHeight` đổi trong vài trình duyệt, nên cách cũ không thấy gì.
 */
export function watchKeyboard(viewport, apply) {
  if (!viewport) return () => {};
  const update = () => {
    // `Math.max(0, …)`: khi bàn phím tắt, hai số bằng nhau; làm tròn có thể cho
    // −1 và `padding-bottom:-1px` không hợp lệ.
    const inset = Math.max(0, Math.round((window.innerHeight - viewport.height) - (viewport.offsetTop || 0)));
    apply(inset);
  };
  update();
  viewport.addEventListener('resize', update);
  viewport.addEventListener('scroll', update);
  return () => {
    viewport.removeEventListener('resize', update);
    viewport.removeEventListener('scroll', update);
  };
}
