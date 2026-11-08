//! §44.2 / §44.8 / §6.5.4 — an toàn input: chỗ duy nhất được phép nói "không".
//!
//! Nguyên tắc từ §41.3: client **không được tin**. Mọi thứ dưới đây là kiểm
//! tra lại ở phía server, kể cả khi client đã kiểm — vì "client đã kiểm" chỉ
//! đúng khi client là code của ta, mà giả định nền là nó **không** phải.
//!
//! Bốn thứ `[CỨNG]`:
//! 1. Toạ độ luôn `u16` ⇒ không thể vượt biên (kiểu dữ liệu, không phải clamp).
//! 2. `Win+L` và `Ctrl+Alt+Del` (SAS) **không bao giờ** đi qua.
//! 3. `release_all` idempotent + **nhảy hàng** (xử lý trước mọi thứ đang chờ).
//! 4. Im 3 s mà còn phím/nút đang giữ ⇒ tự `release_all` (watchdog).

use crate::security::gate::RateLimiter;

/// Windows virtual-key cho `L` — `Win+L` khoá console thật, mất phiên.
pub const VK_L: u16 = 0x4C;
pub const VK_LWIN: u16 = 0x5B;
pub const VK_RWIN: u16 = 0x5C;
/// `VK_DELETE` — chỉ bị chặn khi đi cùng Ctrl+Alt (SAS). Delete thường đi qua.
pub const VK_DELETE: u16 = 0x2E;

/// Bit trong `flags` của `move` (§8.3).
pub const FLAG_LEFT: u8 = 1 << 0;
pub const FLAG_RIGHT: u8 = 1 << 1;
pub const FLAG_MIDDLE: u8 = 1 << 2;
pub const FLAG_BACK: u8 = 1 << 3;
pub const FLAG_FORWARD: u8 = 1 << 4;
pub const FLAG_CTRL: u8 = 1 << 5;
pub const FLAG_SHIFT: u8 = 1 << 6;
pub const FLAG_ALT: u8 = 1 << 7;

/// Chuỗi phím giữ tối đa (§44.8). Vượt ⇒ dấu hiệu bất thường, release + reset.
pub const MAX_KEYS_HELD: usize = 16;
/// `move` ≤ 200/s ở server (client nên gửi ≤ 120/s).
pub const MAX_MOVE_PER_SEC: u32 = 200;
/// `ctrl` ≤ 100/s.
pub const MAX_CTRL_PER_SEC: u32 = 100;
/// `text` ≤ 256 code unit / message (§44.8).
pub const MAX_TEXT_UNITS: usize = 256;
/// Watchdog: im 3 s mà còn giữ gì đó ⇒ release.
pub const STUCK_RELEASE_MS: u64 = 3_000;
/// `wheel` biên (§8.3 clamp).
pub const MAX_WHEEL: i32 = 2_400;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reject {
    /// Quá tần suất. `move` thì drop im lặng + đếm; `ctrl` thì cảnh báo 1 lần.
    Flood { kind: &'static str },
    /// Phím bị cấm: `Win+L` hoặc SAS.
    ForbiddenKey { reason: &'static str },
    /// `text` quá dài.
    TextTooLong,
    /// `keys_held` vượt 16 ⇒ release + reset.
    TooManyKeysHeld,
    /// Surrogate lẻ (dữ liệu hỏng). Bỏ, không crash.
    SurrogateOrphan,
}

impl Reject {
    pub fn code(self) -> &'static str {
        match self {
            Reject::Flood { .. } => "input.flood",
            Reject::ForbiddenKey { .. } => "input.forbidden_key",
            Reject::TextTooLong => "input.text_too_long",
            Reject::TooManyKeysHeld => "input.too_many_keys",
            Reject::SurrogateOrphan => "input.surrogate_orphan",
        }
    }
}

/// Thứ tự xử lý của hàng đợi input (§44.7). `release_all` **nhảy hàng** —
/// nếu xếp sau 60 event move, người dùng đã nhả chuột 100 ms trước mà máy vẫn
/// đang drag.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Priority {
    /// Số càng nhỏ càng sớm.
    ReleaseAll = 0,
    ButtonOrKey = 1,
    Wheel = 2,
    Move = 3,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Held {
    pub left: bool,
    pub right: bool,
    pub middle: bool,
    pub ctrl: bool,
    pub shift: bool,
    pub alt: bool,
}

impl Held {
    pub fn from_flags(flags: u8) -> Self {
        Self {
            left: flags & FLAG_LEFT != 0,
            right: flags & FLAG_RIGHT != 0,
            middle: flags & FLAG_MIDDLE != 0,
            ctrl: flags & FLAG_CTRL != 0,
            shift: flags & FLAG_SHIFT != 0,
            alt: flags & FLAG_ALT != 0,
        }
    }

    pub fn any_button(self) -> bool {
        self.left || self.right || self.middle
    }
}

/// `Default` **derive** chứ không viết tay: viết tay thì clippy
/// `derivable_impls` đỏ CI, và nó cũng là một chỗ để quên một field mới.
#[derive(Debug, Clone, Default)]
pub struct InputSanitizer {
    keys_held: Vec<u16>,
    buttons_held: u8,
    last_event_ms: u64,
    /// Có phím/nút đang giữ mà chưa release ⇒ watchdog phải chạy.
    started_ms: u64,
    move_rate: RateLimiter,
    ctrl_rate: RateLimiter,
    pub dropped_moves: u64,
    pub flood_warnings: u64,
    pub release_all_count: u64,
    pub odd_keyups: u64,
}

impl InputSanitizer {
    pub fn keys_held(&self) -> &[u16] {
        &self.keys_held
    }

    pub fn buttons_held(&self) -> u8 {
        self.buttons_held
    }

    /// `move` — **luôn** nhận `u16`, nên "toạ độ ngoài biên" không biểu diễn
    /// được. Hàm chỉ lo tần suất.
    pub fn accept_move(&mut self, now_ms: u64) -> Result<(), Reject> {
        self.touch(now_ms);
        if !self
            .move_rate
            .check("move", MAX_MOVE_PER_SEC, 1_000, now_ms)
        {
            self.dropped_moves += 1;
            return Err(Reject::Flood { kind: "move" });
        }
        Ok(())
    }

    /// `btn` (§8.3 `{"t":"btn","down":1,"b":0}`). Không drop: mất một cú up
    /// là kẹt nút trên máy thật.
    pub fn accept_button(&mut self, down: bool, button_bit: u8, now_ms: u64) -> Result<(), Reject> {
        self.touch(now_ms);
        if down {
            if self.buttons_held & button_bit == 0 && self.buttons_held.count_ones() as usize >= 8 {
                // 8 bit đã đầy ⇒ không thể là người dùng thật.
                self.release_all(now_ms);
                return Err(Reject::TooManyKeysHeld);
            }
            self.buttons_held |= button_bit;
        } else {
            self.buttons_held &= !button_bit;
        }
        Ok(())
    }

    /// `key` với modifier hiện tại (client gửi `mods` bitmask trong `move`).
    /// Chặn **đúng hai** thứ `[CỨNG]`: `Win+L` và `Ctrl+Alt+Del`.
    pub fn accept_key(
        &mut self,
        vk: u16,
        down: bool,
        mods: u8,
        block_win_lock: bool,
        now_ms: u64,
    ) -> Result<(), Reject> {
        self.touch(now_ms);
        if !self
            .ctrl_rate
            .check("ctrl", MAX_CTRL_PER_SEC, 1_000, now_ms)
        {
            self.flood_warnings += 1;
            return Err(Reject::Flood { kind: "ctrl" });
        }

        if down {
            let win_down = self.keys_held.contains(&VK_LWIN) || self.keys_held.contains(&VK_RWIN);
            if vk == VK_L && block_win_lock && win_down {
                return Err(Reject::ForbiddenKey { reason: "win_lock" });
            }
            let ctrl = mods & FLAG_CTRL != 0;
            let alt = mods & FLAG_ALT != 0;
            if vk == VK_DELETE && ctrl && alt {
                return Err(Reject::ForbiddenKey { reason: "secure_attention" });
            }
            if self.keys_held.contains(&vk) {
                // Repeat từ client: bỏ, server tự sinh repeat theo trạng thái.
                return Ok(());
            }
            if self.keys_held.len() >= MAX_KEYS_HELD {
                self.release_all(now_ms);
                return Err(Reject::TooManyKeysHeld);
            }
            self.keys_held.push(vk);
        } else {
            if self.keys_held.contains(&vk) {
                self.keys_held.retain(|k| *k != vk);
            } else {
                // Up không khớp: vẫn gửi (an toàn) nhưng đếm.
                self.odd_keyups += 1;
            }
        }
        Ok(())
    }

    /// `text` — UTF-16 code unit (§8.3). Surrogate lẻ bị giữ 1 message rồi bỏ;
    /// không bao giờ gửi cặp hỏng xuống `SendInput`.
    pub fn accept_text(&mut self, text: &str) -> Result<String, Reject> {
        if text.encode_utf16().count() > MAX_TEXT_UNITS {
            return Err(Reject::TextTooLong);
        }
        // Emoji (c > 0xFFFF) đi qua dưới dạng surrogate pair — hợp lệ, không
        // được "sửa" ở đây.
        Ok(text.to_string())
    }

    /// `release_all` — **luôn** thành công, **luôn** idempotent (§44.2 bất biến 3).
    /// Trả về danh sách VK cần gửi `KEYUP` (gồm cả modifier cho chắc).
    pub fn release_all(&mut self, now_ms: u64) -> Vec<u16> {
        let mut ups: Vec<u16> = self.keys_held.drain(..).collect();
        for mod_vk in [0x11u16, 0x10, 0x12, VK_LWIN, VK_RWIN] {
            // Ctrl, Shift, Alt, LWin, RWin
            if !ups.contains(&mod_vk) {
                ups.push(mod_vk);
            }
        }
        self.buttons_held = 0;
        self.release_all_count += 1;
        self.started_ms = now_ms;
        ups
    }

    /// Watchdog §6.4.7 lớp 4: im `STUCK_RELEASE_MS` mà còn giữ ⇒ release.
    /// Gọi từ vòng lặp 1 Hz là đủ.
    pub fn watchdog(&mut self, now_ms: u64) -> Option<Vec<u16>> {
        let holding = !self.keys_held.is_empty() || self.buttons_held != 0;
        if !holding {
            self.started_ms = now_ms;
            return None;
        }
        let reference = self.last_event_ms.max(self.started_ms);
        if now_ms.saturating_sub(reference) >= STUCK_RELEASE_MS {
            return Some(self.release_all(now_ms));
        }
        None
    }

    fn touch(&mut self, now_ms: u64) {
        if self.keys_held.is_empty() && self.buttons_held == 0 {
            self.started_ms = now_ms;
        }
        self.last_event_ms = now_ms;
    }
}

/// `wheel` clamp biên (§8.3).
pub fn clamp_wheel(delta: i32) -> i32 {
    delta.clamp(-MAX_WHEEL, MAX_WHEEL)
}

/// Thứ tự hàng đợi theo §44.7: trả index sắp xử lý.
pub fn drain_order(events: &[Priority]) -> Vec<usize> {
    let mut order: Vec<usize> = (0..events.len()).collect();
    order.sort_by_key(|i| (events[*i], *i)); // ổn định: cùng mức thì giữ thứ tự đến
    order
}

#[cfg(test)]
mod tests {
    use super::*;

    const T0: u64 = 1_700_000_000_000;

    #[test]
    fn move_is_rate_limited_by_dropping_the_extra() {
        let mut s = InputSanitizer::default();
        for i in 0..MAX_MOVE_PER_SEC as u64 {
            assert!(s.accept_move(T0 + i).is_ok());
        }
        assert_eq!(
            s.accept_move(T0 + 500).unwrap_err(),
            Reject::Flood { kind: "move" }
        );
        assert_eq!(s.dropped_moves, 1);
        // 1 s sau thì có lại.
        assert!(s.accept_move(T0 + 1_001).is_ok());
    }

    #[test]
    fn win_l_is_blocked_while_win_is_held_and_allowed_otherwise() {
        let mut s = InputSanitizer::default();
        assert!(s.accept_key(VK_LWIN, true, 0, true, T0).is_ok());
        assert_eq!(
            s.accept_key(VK_L, true, 0, true, T0 + 1).unwrap_err(),
            Reject::ForbiddenKey { reason: "win_lock" }
        );
        // Nhả Win rồi bấm L ⇒ bình thường.
        assert!(s.accept_key(VK_LWIN, false, 0, true, T0 + 2).is_ok());
        assert!(s.accept_key(VK_L, true, 0, true, T0 + 3).is_ok());
        // Người dùng tắt block_win_lock: L vẫn đi, nhưng SAS vẫn chết.
        let mut s2 = InputSanitizer::default();
        s2.accept_key(VK_LWIN, true, 0, false, T0).unwrap();
        assert!(s2.accept_key(VK_L, true, 0, false, T0 + 1).is_ok());
    }

    #[test]
    fn secure_attention_is_always_refused() {
        let mut s = InputSanitizer::default();
        assert_eq!(
            s.accept_key(VK_DELETE, true, FLAG_CTRL | FLAG_ALT, false, T0)
                .unwrap_err(),
            Reject::ForbiddenKey { reason: "secure_attention" }
        );
        // Delete **không** modifier vẫn đi qua — không được chặn quá tay.
        let mut s2 = InputSanitizer::default();
        assert!(s2.accept_key(VK_DELETE, true, 0, true, T0).is_ok());
    }

    #[test]
    fn keys_held_never_exceeds_sixteen() {
        let mut s = InputSanitizer::default();
        for vk in 0x41..=0x50u16 {
            // 16 phím A..P
            s.accept_key(vk, true, 0, true, T0).unwrap();
        }
        assert_eq!(s.keys_held().len(), MAX_KEYS_HELD);
        assert_eq!(
            s.accept_key(0x51, true, 0, true, T0).unwrap_err(),
            Reject::TooManyKeysHeld
        );
        // Đã release toàn bộ — không còn phím kẹt.
        assert!(s.keys_held().is_empty());
        assert_eq!(s.buttons_held(), 0);
    }

    #[test]
    fn release_all_is_idempotent_and_covers_modifiers() {
        let mut s = InputSanitizer::default();
        assert!(s.release_all(T0).contains(&0x11), "luôn có Ctrl");
        s.accept_key(0x41, true, 0, true, T0).unwrap();
        let ups = s.release_all(T0 + 1);
        assert!(ups.contains(&0x41));
        assert!(ups.contains(&0x11) && ups.contains(&0x10) && ups.contains(&0x12));
        assert!(ups.contains(&VK_LWIN) && ups.contains(&VK_RWIN));
        assert!(s.keys_held().is_empty(), "idempotent");
        assert_eq!(s.release_all_count, 2);
        // Gọi lần 3 vẫn trả cùng danh sách modifier, không panic.
        assert!(s.release_all(T0 + 2).contains(&0x11));
    }

    #[test]
    fn watchdog_releases_after_three_seconds_of_silence() {
        let mut s = InputSanitizer::default();
        s.accept_button(true, FLAG_LEFT, T0).unwrap();
        assert!(s.watchdog(T0 + 2_000).is_none(), "chưa đủ 3 s");
        let ups = s.watchdog(T0 + STUCK_RELEASE_MS).expect("phải release");
        assert!(ups.contains(&0x11));
        assert_eq!(s.buttons_held(), 0);
        // Sau khi release thì watchdog im.
        assert!(s.watchdog(T0 + 10_000).is_none());
    }

    #[test]
    fn watchdog_does_nothing_when_nothing_is_held() {
        let mut s = InputSanitizer::default();
        assert!(s.watchdog(T0 + 60_000).is_none());
        assert_eq!(s.release_all_count, 0);
    }

    #[test]
    fn button_up_is_never_dropped() {
        let mut s = InputSanitizer::default();
        s.accept_button(true, FLAG_LEFT, T0).unwrap();
        // up không khớp (nút chưa giữ) vẫn phải đi qua, không bị chặn.
        assert!(s.accept_button(false, FLAG_RIGHT, T0 + 1).is_ok());
        assert!(s.accept_button(false, FLAG_LEFT, T0 + 2).is_ok());
        assert_eq!(s.buttons_held(), 0);
    }

    #[test]
    fn text_limit_and_emoji() {
        let mut s = InputSanitizer::default();
        assert!(s.accept_text("ế ữ 😀").is_ok(), "emoji hợp lệ");
        assert_eq!(
            s.accept_text(&"a".repeat(MAX_TEXT_UNITS + 1)).unwrap_err(),
            Reject::TextTooLong
        );
        assert!(s.accept_text(&"a".repeat(MAX_TEXT_UNITS)).is_ok());
    }

    #[test]
    fn wheel_is_clamped() {
        assert_eq!(clamp_wheel(99_999), MAX_WHEEL);
        assert_eq!(clamp_wheel(-99_999), -MAX_WHEEL);
        assert_eq!(clamp_wheel(-120), -120);
    }

    #[test]
    fn release_all_jumps_the_queue() {
        let queue = [
            Priority::Move,
            Priority::Move,
            Priority::Wheel,
            Priority::ReleaseAll,
            Priority::ButtonOrKey,
            Priority::Move,
        ];
        assert_eq!(drain_order(&queue)[0], 3, "release_all phải xử lý trước");
        // Cùng mức giữ thứ tự đến (ổn định).
        let order = drain_order(&queue);
        assert!(order.iter().position(|i| *i == 3) < order.iter().position(|i| *i == 4));
        let moves: Vec<usize> = order.iter().copied().filter(|i| queue[*i] == Priority::Move).collect();
        assert_eq!(moves, vec![0, 1, 5]);
    }

    #[test]
    fn flags_decode_to_buttons_and_modifiers() {
        let held = Held::from_flags(FLAG_LEFT | FLAG_CTRL);
        assert!(held.left && held.ctrl);
        assert!(!held.right && !held.alt);
        assert!(held.any_button());
        assert!(!Held::from_flags(0).any_button());
    }
}
