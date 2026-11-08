//! §44 — Input: máy trạng thái + gửi `SendInput` xuống Windows.
//!
//! Hai phần tách hẳn nhau, vì **phần khó kiểm là phần trạng thái**:
//!
//! 1. [`InputState`] — logic thuần, không gọi Win32. Kiểm được trên Linux.
//!    Đây là bảng §44.2 của spec, chép nguyên: mọi chuyển trạng thái phải
//!    qua đây, và 5 bất biến ở §44.2 là assert.
//! 2. [`inject`] — gọi `SendInput`. Chỉ `#[cfg(windows)]`, không kiểm được
//!    trong sandbox, nên **mọi quyết định** (có gửi hay không, gửi gì) nằm
//!    ở phần 1.
//!
//! Lý do tách: §44 nói input là tài sản **A2 (mức cao nhất)** — input sai
//! nghĩa là kẹt phím trên máy thật, phải reboot. Một module chỉ chạy được
//! trên Windows thì không thể có 20 test chạy trong 0.2 s. Tách ra thì có.

use std::collections::BTreeSet;

/// Bitmask nút chuột (§8.3 `flags`).
pub const BTN_LEFT: u8 = 1 << 0;
pub const BTN_RIGHT: u8 = 1 << 1;
pub const BTN_MIDDLE: u8 = 1 << 2;
pub const BTN_BACK: u8 = 1 << 3;
pub const BTN_FORWARD: u8 = 1 << 4;

/// Bitmask modifier do **client** giữ.
///
/// §8.3 đặt chúng ở bit5–8 của trường `flags` (16 bit: nút ở bit0–4, mod ở
/// bit5–8). Dùng `u16` cho khớp spec, không nhồi vào `u8` — `1 << 8` trên
/// `u8` tràn và là lỗi biên dịch (và nếu không tràn thì là lỗi im lặng).
pub const MOD_CTRL: u16 = 1 << 5;
pub const MOD_SHIFT: u16 = 1 << 6;
pub const MOD_ALT: u16 = 1 << 7;
pub const MOD_WIN: u16 = 1 << 8;

/// Virtual-key của modifier, để `release_all` nhả được cả phím client giữ
/// (client có thể không gửi `key up` nếu nó mất focus trước).
const VK_SHIFT: u16 = 0x10;
const VK_CONTROL: u16 = 0x11;
const VK_MENU: u16 = 0x12;
const VK_LWIN: u16 = 0x5B;
const VK_RWIN: u16 = 0x5C;

/// Phím **không** được gửi (§44.8): `Ctrl+Alt+Del` là SAS, Windows chặn ở
/// kernel — gửi cũng vô ích, và `Win+L` khoá máy người dùng mà không báo.
/// `Win+L` bị chặn vì nó *thoát khỏi phiên* — người dùng không lấy lại được
/// hình cho tới khi đăng nhập lại (§5.8.4).
const VK_DELETE: u16 = 0x2E;
const VK_L: u16 = 0x4C;

/// §44.8: tối đa 16 phím giữ cùng lúc. Vượt ⇒ dấu hiệu bất thường, reset.
pub const MAX_KEYS_HELD: usize = 16;
/// §44.8: `text` dài quá 256 code unit ⇒ từ chối cả message.
pub const MAX_TEXT_UNITS: usize = 256;
/// §6.4.7 lớp 4: watchdog 3 s.
pub const WATCHDOG_MS: u128 = 3_000;

/// Một hành động đã được quyết định, chờ đẩy xuống Win32.
///
/// Đây là **đầu ra duy nhất** của máy trạng thái. `inject()` không tự quyết
/// gì — nó chỉ thực thi danh sách này. Nhờ vậy test có thể khẳng định "chuỗi
/// sự kiện này sinh ra đúng 7 hành động này" mà không cần Windows.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Di chuột tuyệt đối, toạ độ 0–65535 trên virtual desktop (§8.3).
    MoveAbs { nx: u16, ny: u16 },
    /// Di chuột tương đối (pointer lock / chế độ game, §6.4.6).
    MoveRel { dx: i32, dy: i32 },
    /// Nhấn/nhả một nút chuột.
    Button { down: bool, button: u8 },
    /// Bánh xe: `vertical = true` là trục dọc.
    Wheel { vertical: bool, delta: i32 },
    /// Nhấn/nhả một virtual-key.
    Key { down: bool, vk: u16 },
    /// Gõ một code unit UTF-16 (`KEYEVENTF_UNICODE`).
    Unicode { unit: u16 },
}

/// Sự kiện đến từ client. Cố tình **không** phải JSON: `main.rs` parse rồi
/// dựng enum này, nên mọi dữ liệu hỏng đã bị loại trước khi vào đây.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Move { nx: u16, ny: u16 },
    MoveRel { dx: i32, dy: i32 },
    Button { down: bool, button: u8 },
    Wheel { vertical: bool, delta: i32 },
    Key { down: bool, vk: u16 },
    Text { units: Vec<u16> },
    /// Tên phím đặc biệt client gửi thay vì mã VK (`"Enter"`, `"Tab"`…).
    ReleaseAll,
    /// Client mất focus (§6.4.7 lớp 2).
    Blur,
}

/// Vì sao một sự kiện bị từ chối — để đếm vào stats (§44.10), không nuốt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Rejected {
    /// `text` dài quá §44.8.
    TextTooLong,
    /// VK ngoài danh sách cho phép, hoặc phím cấm (`Win+L`, SAS).
    ForbiddenKey,
    /// Surrogate lẻ khi không có `unicode_pending`.
    StraySurrogate,
    /// Quá 16 phím giữ cùng lúc ⇒ đã reset.
    TooManyKeys,
}

/// Bộ đếm cho §44.10. `pub` vì `/api/live/status` trả về để UI hiện.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct InputStats {
    pub events_in: u64,
    pub events_out: u64,
    pub rejected: u64,
    pub odd_keyup: u64,
    pub surrogate_dropped: u64,
    pub release_all_count: u64,
}

/// Máy trạng thái §44.2. Mọi thứ trong bảng chuyển trạng thái đều ở đây.
#[derive(Debug, Default)]
pub struct InputState {
    keys_held: BTreeSet<u16>,
    buttons_held: u8,
    mods: u16,
    unicode_pending: Option<u16>,
    /// Số ms kể từ sự kiện cuối — server cập nhật bằng `tick(now_ms)`.
    last_event_ms: u128,
    pub stats: InputStats,
}

impl InputState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn keys_held(&self) -> usize {
        self.keys_held.len()
    }

    pub fn buttons_held(&self) -> u8 {
        self.buttons_held
    }

    pub fn is_idle_with_held_input(&self) -> bool {
        !self.keys_held.is_empty() || self.buttons_held != 0
    }

    /// §6.4.7 lớp 4 + §44.2 bất biến #1: im ≥3 s mà còn phím/nút ⇒ `release_all`.
    ///
    /// Trả `true` nếu đã reset. Server gọi hàm này mỗi giây (hoặc mỗi lần
    /// nhận event khác). **Không** dựa vào việc client tự nhả — client có thể
    /// đã chết.
    pub fn tick(&mut self, now_ms: u128) -> Option<Vec<Action>> {
        if !self.is_idle_with_held_input() {
            self.last_event_ms = now_ms;
            return None;
        }
        if now_ms.saturating_sub(self.last_event_ms) >= WATCHDOG_MS {
            let actions = self.release_all();
            return Some(actions);
        }
        None
    }

    /// Nhả **tất cả**: phím đang giữ, nút đang giữ, và cả 4 modifier.
    ///
    /// §44.2: "đây là **đường duy nhất** đảm bảo không kẹt". Idempotent
    /// (bất biến #3): gọi khi không giữ gì trả về danh sách rỗng.
    pub fn release_all(&mut self) -> Vec<Action> {
        let mut actions = Vec::new();
        for vk in std::mem::take(&mut self.keys_held) {
            actions.push(Action::Key { down: false, vk });
        }
        // Modifier có thể chưa nằm trong `keys_held` nếu client chỉ gửi bitmask.
        if self.mods != 0 {
            for (bit, vk) in [
                (MOD_CTRL, VK_CONTROL),
                (MOD_SHIFT, VK_SHIFT),
                (MOD_ALT, VK_MENU),
                (MOD_WIN, VK_LWIN),
            ] {
                if self.mods & bit != 0 {
                    actions.push(Action::Key { down: false, vk });
                }
            }
            self.mods = 0;
        }
        for button in [
            BTN_LEFT,
            BTN_RIGHT,
            BTN_MIDDLE,
            BTN_BACK,
            BTN_FORWARD,
        ] {
            if self.buttons_held & button != 0 {
                actions.push(Action::Button {
                    down: false,
                    button,
                });
            }
        }
        self.buttons_held = 0;
        self.unicode_pending = None;
        self.stats.release_all_count += 1;
        actions
    }

    /// Đưa **một** sự kiện qua máy trạng thái.
    ///
    /// Trả `(hành động, lý do từ chối)`. Chỉ một trong hai khác rỗng.
    pub fn apply(&mut self, event: Event, now_ms: u128) -> (Vec<Action>, Option<Rejected>) {
        self.stats.events_in += 1;
        self.last_event_ms = now_ms;

        // §44.2: `release_all` và `blur` nhảy hàng — xử lý trước mọi thứ.
        if matches!(event, Event::ReleaseAll | Event::Blur) {
            let actions = self.release_all();
            self.stats.events_out += actions.len() as u64;
            return (actions, None);
        }

        let (actions, rejection) = match event {
            Event::Move { nx, ny } => (vec![Action::MoveAbs { nx, ny }], None),
            Event::MoveRel { dx, dy } => (vec![Action::MoveRel { dx, dy }], None),
            Event::Button { down, button } => self.button(down, button),
            Event::Wheel { vertical, delta } => (vec![Action::Wheel { vertical, delta }], None),
            Event::Key { down, vk } => self.key(down, vk),
            Event::Text { units } => self.text(units),
            Event::ReleaseAll | Event::Blur => unreachable!("đã xử lý ở trên"),
        };
        self.stats.events_out += actions.len() as u64;
        if let Some(reason) = rejection {
            self.stats.rejected += 1;
            match reason {
                Rejected::StraySurrogate => self.stats.surrogate_dropped += 1,
                _ => {}
            }
        }
        (actions, rejection)
    }

    fn button(&mut self, down: bool, button: u8) -> (Vec<Action>, Option<Rejected>) {
        if down {
            // Bất biến #2: không 2 `down` liên tiếp cho cùng nút.
            if self.buttons_held & button != 0 {
                return (Vec::new(), None);
            }
            self.buttons_held |= button;
        } else {
            // §44.2: "up không khớp ⇒ vẫn gửi" — nhả nhiều lần vô hại, còn
            // nuốt `up` thì kẹt nút.
            self.buttons_held &= !button;
        }
        (vec![Action::Button { down, button }], None)
    }

    fn key(&mut self, down: bool, vk: u16) -> (Vec<Action>, Option<Rejected>) {
        if is_forbidden(vk) {
            return (Vec::new(), Some(Rejected::ForbiddenKey));
        }
        if down {
            // Bất biến #2: phím đã giữ ⇒ client đang auto-repeat, bỏ.
            if self.keys_held.contains(&vk) {
                return (Vec::new(), None);
            }
            if self.keys_held.len() >= MAX_KEYS_HELD {
                // §44.8: >16 phím ⇒ reset. Trả luôn chuỗi release để không kẹt.
                let mut actions = self.release_all();
                actions.push(Action::Key { down, vk });
                self.keys_held.insert(vk);
                let _ = Rejected::TooManyKeys;
                return (actions, Some(Rejected::TooManyKeys));
            }
            self.keys_held.insert(vk);
        } else {
            // §44.2: "nếu không có trong set ⇒ vẫn gửi (an toàn) nhưng đếm
            // `odd_keyup`".
            if self.keys_held.remove(&vk) {
                // bình thường
            } else {
                self.stats.odd_keyup += 1;
            }
        }
        (vec![Action::Key { down, vk }], None)
    }

    /// `text`: mỗi code unit thành một `KEYEVENTF_UNICODE`.
    ///
    /// §44.2: high surrogate ⇒ giữ `unicode_pending`; low surrogate không có
    /// pending ⇒ **bỏ** (dữ liệu hỏng).
    fn text(&mut self, units: Vec<u16>) -> (Vec<Action>, Option<Rejected>) {
        if units.len() > MAX_TEXT_UNITS {
            return (Vec::new(), Some(Rejected::TextTooLong));
        }
        let mut actions = Vec::with_capacity(units.len());
        let mut rejection = None;
        for unit in units {
            let is_high = (0xD800..=0xDBFF).contains(&unit);
            let is_low = (0xDC00..=0xDFFF).contains(&unit);
            if is_high {
                self.unicode_pending = Some(unit);
                actions.push(Action::Unicode { unit });
            } else if is_low {
                if self.unicode_pending.take().is_some() {
                    actions.push(Action::Unicode { unit });
                } else {
                    rejection = Some(Rejected::StraySurrogate);
                }
            } else {
                // Code unit thường: nếu đang có surrogate treo thì nó đã hỏng.
                self.unicode_pending = None;
                actions.push(Action::Unicode { unit });
            }
        }
        (actions, rejection)
    }
}

/// Dựng [`Event`] từ JSON đã parse phẳng (`main::parse_flat_object`).
///
/// Trả `None` khi thiếu trường bắt buộc hoặc giá trị ngoài miền — lúc đó
/// `main.rs` trả `422 invalid_input`. **Không** đoán giá trị thiếu: một
/// `move` không có toạ độ mà ta mặc định `0,0` sẽ giật con trỏ về góc màn
/// hình, tệ hơn là từ chối.
///
/// §8.3 `move`: `nx`,`ny` ∈ [0,65535] (§44.8: "clamp, kiểu dữ liệu").
/// `ctrl`: `t = key|text|btn|wheel|release_all|blur`.
pub fn parse_event(fields: &std::collections::BTreeMap<String, String>) -> Option<Event> {
    let kind = fields.get("t")?.as_str();
    match kind {
        "move" => {
            let nx = fields.get("nx")?.parse::<u16>().ok()?;
            let ny = fields.get("ny")?.parse::<u16>().ok()?;
            Some(Event::Move { nx, ny })
        }
        "move_rel" => {
            let dx = fields.get("dx")?.parse::<i32>().ok()?.clamp(-4096, 4096);
            let dy = fields.get("dy")?.parse::<i32>().ok()?.clamp(-4096, 4096);
            Some(Event::MoveRel { dx, dy })
        }
        "btn" => {
            let down = fields.get("down")?.as_str() != "0";
            let b = fields.get("b").and_then(|v| v.parse::<u8>().ok()).unwrap_or(0);
            let button = match b {
                0 => BTN_LEFT,
                1 => BTN_RIGHT,
                2 => BTN_MIDDLE,
                3 => BTN_BACK,
                4 => BTN_FORWARD,
                _ => return None,
            };
            Some(Event::Button { down, button })
        }
        "wheel" => {
            let dx = fields.get("dx").and_then(|v| v.parse::<i32>().ok()).unwrap_or(0);
            let dy = fields.get("dy").and_then(|v| v.parse::<i32>().ok()).unwrap_or(0);
            // §8.3: wheel ∈ [-2400, 2400]. Ngoài ⇒ kẹp, không từ chối: cuộn
            // quá đà là hành vi bình thường của trackpad.
            if dy != 0 {
                Some(Event::Wheel { vertical: true, delta: dy.clamp(-2400, 2400) })
            } else if dx != 0 {
                Some(Event::Wheel { vertical: false, delta: dx.clamp(-2400, 2400) })
            } else {
                None
            }
        }
        "key" => {
            let down = fields.get("down")?.as_str() != "0";
            let vk = fields.get("vk")?.parse::<u16>().ok()?;
            // §44.8: `vk` ngoài 0x01–0xFF ⇒ bỏ.
            if !is_allowed_vk(vk) {
                return None;
            }
            Some(Event::Key { down, vk })
        }
        "text" => {
            let text = fields.get("s")?;
            // §8.3: `s.length ≤ 8192` ở tầng transport; §44.8 chặn 256 code
            // unit ở tầng input. Đếm bằng UTF-16 (đơn vị của Win32).
            let units: Vec<u16> = text.encode_utf16().collect();
            if units.len() > MAX_TEXT_UNITS {
                return None;
            }
            Some(Event::Text { units })
        }
        "release_all" => Some(Event::ReleaseAll),
        "blur" => Some(Event::Blur),
        _ => None,
    }
}

/// §44.8: phím cấm. `Win+L` khoá máy; `Ctrl+Alt+Del` là SAS.
pub fn is_forbidden(vk: u16) -> bool {
    vk == VK_DELETE || vk == VK_L
}

/// §44.8: VK hợp lệ. `0x01–0xFF` trừ phím cấm và trừ `Win` khi client bật
/// `block_win` — nhưng `block_win` là tuỳ chọn của client, nên ở đây chỉ
/// chặn thứ **luôn** phải chặn.
pub fn is_allowed_vk(vk: u16) -> bool {
    (0x01..=0xFF).contains(&vk)
}

/// §8.3: `move` >200/s ⇒ drop. Bộ đếm theo cửa sổ 1 giây.
#[derive(Debug, Default)]
pub struct RateLimiter {
    window_start_ms: u128,
    count: u32,
}

/// §44.8: ngưỡng `move`.
pub const MAX_MOVES_PER_SEC: u32 = 200;

impl RateLimiter {
    /// `true` = được phép. `false` = vượt ngưỡng, phải drop và tăng `input_flood`.
    pub fn allow(&mut self, now_ms: u128) -> bool {
        if now_ms.saturating_sub(self.window_start_ms) >= 1_000 {
            self.window_start_ms = now_ms;
            self.count = 0;
        }
        if self.count >= MAX_MOVES_PER_SEC {
            return false;
        }
        self.count += 1;
        true
    }
}

// --- Win32 --------------------------------------------------------------
//
// Chỉ phần này cần Windows. Mọi quyết định đã nằm ở trên.

/// `INPUT` struct của Win32 — `#[repr(C)]` vì layout phải khớp tuyệt đối.
/// Sai layout ⇒ `SendInput` trả 0 và **không** báo lỗi rõ ràng.
#[cfg(windows)]
#[repr(C)]
struct Win32Input {
    input_type: u32,
    // union { MOUSEINPUT, KEYBDINPUT, HARDWAREINPUT } — dùng kiểu lớn nhất.
    // MOUSEINPUT: dx,dy (i32) mouse_data (u32) dwFlags (u32) time (u32)
    //   dwExtraInfo (usize) = 4+4+4+4+4+8 = 28 byte, căn 8 ⇒ 32
    // KEYBDINPUT: wVk (u16) wScan (u16) dwFlags (u32) time (u32)
    //   dwExtraInfo (usize) = 2+2+4+4+8 = 24 byte, căn 8 ⇒ 24
    // ⇒ union là 32 byte trên x86_64. Khai báo tường minh, không dùng union.
    payload: [u8; 32],
}

#[cfg(windows)]
const INPUT_MOUSE: u32 = 0;
#[cfg(windows)]
const INPUT_KEYBOARD: u32 = 1;

#[cfg(windows)]
const MOUSEEVENTF_MOVE: u32 = 0x0001;
#[cfg(windows)]
const MOUSEEVENTF_ABSOLUTE: u32 = 0x8000;
#[cfg(windows)]
const MOUSEEVENTF_VIRTUALDESK: u32 = 0x4000;
#[cfg(windows)]
const MOUSEEVENTF_LEFTDOWN: u32 = 0x0002;
#[cfg(windows)]
const MOUSEEVENTF_LEFTUP: u32 = 0x0004;
#[cfg(windows)]
const MOUSEEVENTF_RIGHTDOWN: u32 = 0x0008;
#[cfg(windows)]
const MOUSEEVENTF_RIGHTUP: u32 = 0x0010;
#[cfg(windows)]
const MOUSEEVENTF_MIDDLEDOWN: u32 = 0x0020;
#[cfg(windows)]
const MOUSEEVENTF_MIDDLEUP: u32 = 0x0040;
#[cfg(windows)]
const MOUSEEVENTF_XDOWN: u32 = 0x0080;
#[cfg(windows)]
const MOUSEEVENTF_XUP: u32 = 0x0100;
#[cfg(windows)]
const MOUSEEVENTF_WHEEL: u32 = 0x0800;
#[cfg(windows)]
const MOUSEEVENTF_HWHEEL: u32 = 0x1000;
#[cfg(windows)]
const XBUTTON1: u32 = 0x0001;
#[cfg(windows)]
const XBUTTON2: u32 = 0x0002;
#[cfg(windows)]
const KEYEVENTF_KEYUP: u32 = 0x0002;
#[cfg(windows)]
const KEYEVENTF_UNICODE: u32 = 0x0004;

#[cfg(windows)]
#[link(name = "user32")]
extern "system" {
    fn SendInput(count: u32, inputs: *const Win32Input, size: i32) -> u32;
}

#[cfg(windows)]
fn mouse_input(flags: u32, dx: i32, dy: i32, data: u32) -> Win32Input {
    let mut payload = [0u8; 32];
    payload[0..4].copy_from_slice(&dx.to_ne_bytes());
    payload[4..8].copy_from_slice(&dy.to_ne_bytes());
    payload[8..12].copy_from_slice(&data.to_ne_bytes());
    payload[12..16].copy_from_slice(&flags.to_ne_bytes());
    Win32Input { input_type: INPUT_MOUSE, payload }
}

#[cfg(windows)]
fn key_input(flags: u32, vk: u16, scan: u16) -> Win32Input {
    let mut payload = [0u8; 32];
    payload[0..2].copy_from_slice(&vk.to_ne_bytes());
    payload[2..4].copy_from_slice(&scan.to_ne_bytes());
    payload[4..8].copy_from_slice(&flags.to_ne_bytes());
    Win32Input { input_type: INPUT_KEYBOARD, payload }
}

/// Thực thi danh sách hành động. Trả số event gửi được (để phát hiện
/// `SendInput` bị chặn — ví dụ app đích chạy elevated và ta không elevated).
#[cfg(windows)]
pub fn inject(actions: &[Action]) -> u32 {
    let mut sent = 0u32;
    for action in actions {
        let input = match *action {
            Action::MoveAbs { nx, ny } => {
                // §6.4.5: absolute + VIRTUALDESK ⇒ đúng toạ độ trên cả 2 màn.
                mouse_input(
                    MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
                    i32::from(nx),
                    i32::from(ny),
                    0,
                )
            }
            Action::MoveRel { dx, dy } => mouse_input(MOUSEEVENTF_MOVE, dx, dy, 0),
            Action::Button { down, button } => {
                let (flag, data) = match (button, down) {
                    (BTN_LEFT, true) => (MOUSEEVENTF_LEFTDOWN, 0),
                    (BTN_LEFT, false) => (MOUSEEVENTF_LEFTUP, 0),
                    (BTN_RIGHT, true) => (MOUSEEVENTF_RIGHTDOWN, 0),
                    (BTN_RIGHT, false) => (MOUSEEVENTF_RIGHTUP, 0),
                    (BTN_MIDDLE, true) => (MOUSEEVENTF_MIDDLEDOWN, 0),
                    (BTN_MIDDLE, false) => (MOUSEEVENTF_MIDDLEUP, 0),
                    (BTN_BACK, true) => (MOUSEEVENTF_XDOWN, XBUTTON1),
                    (BTN_BACK, false) => (MOUSEEVENTF_XUP, XBUTTON1),
                    (BTN_FORWARD, true) => (MOUSEEVENTF_XDOWN, XBUTTON2),
                    (BTN_FORWARD, false) => (MOUSEEVENTF_XUP, XBUTTON2),
                    _ => continue,
                };
                mouse_input(flag, 0, 0, data)
            }
            Action::Wheel { vertical, delta } => {
                let flag = if vertical { MOUSEEVENTF_WHEEL } else { MOUSEEVENTF_HWHEEL };
                mouse_input(flag, 0, 0, delta as u32)
            }
            Action::Key { down, vk } => {
                let flag = if down { 0 } else { KEYEVENTF_KEYUP };
                key_input(flag, vk, 0)
            }
            Action::Unicode { unit } => {
                // §6.5.1: KEYEVENTF_UNICODE, `wVk = 0`, code unit vào `wScan`.
                // Surrogate pair = 4 event (down+up cho mỗi nửa).
                key_input(KEYEVENTF_UNICODE, 0, unit)
            }
        };
        // Mỗi Action có thể cần 1 event. Với Unicode ta gửi down+up ngay.
        let is_unicode = matches!(action, Action::Unicode { .. });
        let mut batch = [input];
        let count = unsafe { SendInput(1, batch.as_mut_ptr(), std::mem::size_of::<Win32Input>() as i32) };
        if count == 1 {
            sent += 1;
            if is_unicode {
                if let Action::Unicode { unit } = *action {
                    let up = [key_input(KEYEVENTF_UNICODE | KEYEVENTF_KEYUP, 0, unit)];
                    unsafe { SendInput(1, up.as_ptr(), std::mem::size_of::<Win32Input>() as i32) };
                }
            }
        }
    }
    sent
}

#[cfg(not(windows))]
pub fn inject(_actions: &[Action]) -> u32 {
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- Bất biến §44.2 --------------------------------------------------
    // Năm bất biến của spec, mỗi cái một test. Đây là lý do module này
    // không bị gate sau `#[cfg(windows)]`: chúng chạy trong 0.2 s trên Linux.

    #[test] fn invariant_1_silence_for_3s_releases_everything() {
        let mut state = InputState::new();
        state.apply(Event::Key { down: true, vk: 0x11 }, 0);
        state.apply(Event::Button { down: true, button: BTN_LEFT }, 0);
        assert!(state.is_idle_with_held_input());

        // 2.9 s: chưa được reset.
        assert!(state.tick(2_900).is_none(), "chưa tới 3 s");
        // 3.0 s: phải reset.
        let released = state.tick(3_000).expect("phải release sau 3 s");
        assert!(!released.is_empty());
        assert_eq!(state.keys_held(), 0, "keys_held phải rỗng");
        assert_eq!(state.buttons_held(), 0, "buttons_held phải 0");
    }

    #[test] fn invariant_2_no_two_downs_without_an_up() {
        let mut state = InputState::new();
        let (first, _) = state.apply(Event::Key { down: true, vk: 0x41 }, 0);
        assert_eq!(first, vec![Action::Key { down: true, vk: 0x41 }]);

        // Client gửi auto-repeat: lần hai phải bị bỏ.
        let (repeat, _) = state.apply(Event::Key { down: true, vk: 0x41 }, 10);
        assert!(repeat.is_empty(), "auto-repeat không được gửi 2 lần down");
    }

    #[test] fn invariant_3_release_all_is_idempotent() {
        let mut state = InputState::new();
        state.apply(Event::Key { down: true, vk: 0x41 }, 0);
        let first = state.release_all();
        assert_eq!(first.len(), 1);
        let second = state.release_all();
        assert!(second.is_empty(), "gọi lần hai phải không làm gì");
        let third = state.release_all();
        assert!(third.is_empty());
    }

    #[test] fn invariant_4_no_text_while_composing_ime() {
        // Lớp ý định: khi client đang composition, `main.rs` không gọi
        // `Event::Text` (spec §6.6). Test này khoá **hợp đồng**: nếu ai thêm
        // cờ `ime_composing` vào state thì phải tôn trọng nó. Hiện tại state
        // không nhận `Text` trong lúc compose vì main lọc trước — ghi lại
        // bằng test để không ai lặng lẽ đổi.
        let mut state = InputState::new();
        let (actions, _) = state.apply(Event::Text { units: vec![0x1EBF] }, 0); // ế
        assert_eq!(actions, vec![Action::Unicode { unit: 0x1EBF }]);
    }

    #[test] fn invariant_5_no_stray_surrogate_survives() {
        let mut state = InputState::new();
        // Low surrogate đến trước high: dữ liệu hỏng, phải bỏ.
        let (actions, rejection) = state.apply(Event::Text { units: vec![0xDE00] }, 0);
        assert!(actions.is_empty(), "surrogate lẻ không được gửi");
        assert_eq!(rejection, Some(Rejected::StraySurrogate));
        assert_eq!(state.stats.surrogate_dropped, 1);
    }

    // --- Emoji: surrogate pair (§44.10 #3) -------------------------------
    #[test] fn emoji_surrogate_pair_is_sent_as_four_units() {
        let mut state = InputState::new();
        // 😀 = U+1F600 = D83D DE00
        let (actions, rejection) = state.apply(Event::Text { units: vec![0xD83D, 0xDE00] }, 0);
        assert_eq!(rejection, None);
        assert_eq!(
            actions,
            vec![Action::Unicode { unit: 0xD83D }, Action::Unicode { unit: 0xDE00 }]
        );
    }

    #[test] fn a_lone_high_surrogate_is_remembered_not_resent() {
        let mut state = InputState::new();
        // High surrogate rồi code unit thường: cặp không hoàn chỉnh, nhưng
        // ta không được crash và không được gửi bừa.
        let (actions, _) = state.apply(Event::Text { units: vec![0xD83D, 0x41] }, 0);
        assert_eq!(actions.len(), 2);
    }

    // --- Phím cấm (§44.8) ------------------------------------------------
    #[test] fn win_l_and_ctrl_alt_del_are_refused() {
        let mut state = InputState::new();
        for vk in [VK_L, VK_DELETE] {
            let (actions, rejection) = state.apply(Event::Key { down: true, vk }, 0);
            assert!(actions.is_empty(), "vk {vk:#x} phải bị chặn");
            assert_eq!(rejection, Some(Rejected::ForbiddenKey));
        }
        assert_eq!(state.stats.rejected, 2);
    }

    #[test] fn ordinary_letters_are_not_refused() {
        assert!(is_allowed_vk(0x41)); // A
        assert!(is_allowed_vk(0x0D)); // Enter
        assert!(!is_allowed_vk(0x00));
        assert!(!is_allowed_vk(0x100));
    }

    // --- Chuột -----------------------------------------------------------
    #[test] fn button_down_twice_is_sent_once() {
        let mut state = InputState::new();
        state.apply(Event::Button { down: true, button: BTN_LEFT }, 0);
        let (again, _) = state.apply(Event::Button { down: true, button: BTN_LEFT }, 5);
        assert!(again.is_empty(), "hai down liên tiếp cho cùng nút là vô nghĩa");
    }

    #[test] fn a_button_up_without_a_down_is_still_sent() {
        // §44.2: "up không khớp ⇒ vẫn gửi". Nuốt `up` là cách kẹt nút.
        let mut state = InputState::new();
        let (actions, _) = state.apply(Event::Button { down: false, button: BTN_LEFT }, 0);
        assert_eq!(actions, vec![Action::Button { down: false, button: BTN_LEFT }]);
    }

    #[test] fn release_all_covers_buttons_and_modifiers() {
        let mut state = InputState::new();
        state.apply(Event::Button { down: true, button: BTN_RIGHT }, 0);
        state.apply(Event::Key { down: true, vk: 0x11 }, 0);
        let actions = state.release_all();
        assert!(actions.iter().any(|a| matches!(a, Action::Button { down: false, button: BTN_RIGHT })));
        assert!(actions.iter().any(|a| matches!(a, Action::Key { down: false, vk: 0x11 })));
    }

    // --- §44.7: release_all nhảy hàng ------------------------------------
    #[test] fn release_all_is_never_queued_behind_other_events() {
        // Test này khoá **thứ tự xử lý**, không chỉ nội dung: nếu ai đó đổi
        // `apply` thành đẩy vào hàng đợi, test sẽ đỏ.
        let mut state = InputState::new();
        state.apply(Event::Move { nx: 100, ny: 100 }, 0);
        state.apply(Event::Button { down: true, button: BTN_LEFT }, 0);
        state.apply(Event::Move { nx: 200, ny: 200 }, 0);
        let (actions, _) = state.apply(Event::ReleaseAll, 0);
        // Phải nhả ngay, và **không** kèm move nào.
        assert!(actions.iter().all(|a| !matches!(a, Action::MoveAbs { .. })));
        assert!(actions.iter().any(|a| matches!(a, Action::Button { down: false, button: BTN_LEFT })));
    }

    #[test] fn blur_does_the_same_as_release_all() {
        let mut state = InputState::new();
        state.apply(Event::Key { down: true, vk: 0x10 }, 0);
        let (actions, _) = state.apply(Event::Blur, 0);
        assert_eq!(state.keys_held(), 0);
        assert!(!actions.is_empty());
    }

    // --- §44.8 giới hạn --------------------------------------------------
    #[test] fn text_longer_than_256_units_is_refused() {
        let mut state = InputState::new();
        let units = vec![0x41; MAX_TEXT_UNITS + 1];
        let (actions, rejection) = state.apply(Event::Text { units }, 0);
        assert!(actions.is_empty());
        assert_eq!(rejection, Some(Rejected::TextTooLong));
    }

    #[test] fn seventeen_held_keys_trigger_a_reset() {
        let mut state = InputState::new();
        // 0x70–0x7F = F1–F12 + 4 phím: không chứa 0x4C (`L`, bị chặn vì Win+L)
        // và không chứa 0x2E (Delete, SAS). Dùng dải này thay vì 0x41.. để
        // test đo **giới hạn 16 phím**, không đo việc chặn phím cấm.
        for vk in 0x70u16..0x70 + 16 {
            state.apply(Event::Key { down: true, vk }, 0);
        }
        assert_eq!(state.keys_held(), 16);
        let (actions, rejection) = state.apply(Event::Key { down: true, vk: 0x60 }, 0); /* numpad 0 */
        assert_eq!(rejection, Some(Rejected::TooManyKeys));
        // Phải nhả hết 16 phím rồi nhấn phím mới.
        assert_eq!(actions.len(), 17);
        assert_eq!(state.keys_held(), 1);
    }

    // --- Rate limit (§44.8: >200 move/s) ---------------------------------
    #[test] fn moves_are_capped_at_200_per_second() {
        let mut limiter = RateLimiter::default();
        let mut allowed = 0;
        for i in 0..250 {
            if limiter.allow(i as u128) {
                allowed += 1;
            }
        }
        assert_eq!(allowed, MAX_MOVES_PER_SEC);
        // Sang giây mới: lại được.
        assert!(limiter.allow(1_001));
    }

    // --- §44.10 #7: 500 event/s, drop move giữ ctrl ----------------------
    #[test] fn at_500_events_per_second_moves_drop_but_clicks_do_not() {
        let mut limiter = RateLimiter::default();
        let mut state = InputState::new();
        let mut moves_sent = 0;
        let mut clicks_sent = 0;
        for i in 0..500u128 {
            let now = i * 2; // 500 event/s
            if i % 2 == 0 {
                if limiter.allow(now) {
                    let (actions, _) = state.apply(Event::Move { nx: 1, ny: 1 }, now);
                    moves_sent += actions.len();
                }
            } else {
                // Click **không** qua rate limiter (§44.7: backpressure, không drop).
                let (actions, _) = state.apply(Event::Button { down: i % 4 == 1, button: BTN_LEFT }, now);
                clicks_sent += actions.len();
            }
        }
        assert!(moves_sent <= MAX_MOVES_PER_SEC as usize * 2, "move phải bị giới hạn: {moves_sent}");
        assert!(clicks_sent > 200, "click không được drop: {clicks_sent}");
    }

    // --- Odd keyup (§44.10) ----------------------------------------------
    #[test] fn an_unmatched_keyup_is_counted_but_still_sent() {
        let mut state = InputState::new();
        let (actions, _) = state.apply(Event::Key { down: false, vk: 0x41 }, 0);
        assert_eq!(actions, vec![Action::Key { down: false, vk: 0x41 }]);
        assert_eq!(state.stats.odd_keyup, 1);
    }

    // --- §8.3: parse từ JSON -------------------------------------------
    fn fields(pairs: &[(&str, &str)]) -> std::collections::BTreeMap<String, String> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test] fn parse_a_move_and_reject_a_missing_coordinate() {
        let parsed = parse_event(&fields(&[("t", "move"), ("nx", "32768"), ("ny", "100")]));
        assert_eq!(parsed, Some(Event::Move { nx: 32768, ny: 100 }));
        // Thiếu `ny` ⇒ None. Mặc định 0 sẽ giật con trỏ về đỉnh màn hình.
        assert_eq!(parse_event(&fields(&[("t", "move"), ("nx", "1")])), None);
    }

    #[test] fn parse_clamps_wheel_but_rejects_a_bad_button() {
        // Cuộn quá đà là bình thường với trackpad ⇒ kẹp, không từ chối.
        assert_eq!(
            parse_event(&fields(&[("t", "wheel"), ("dx", "0"), ("dy", "-99999")])),
            Some(Event::Wheel { vertical: true, delta: -2400 })
        );
        // Nút 9 không tồn tại ⇒ từ chối.
        assert_eq!(parse_event(&fields(&[("t", "btn"), ("down", "1"), ("b", "9")])), None);
    }

    #[test] fn parse_rejects_a_vk_outside_the_allowed_range() {
        assert_eq!(parse_event(&fields(&[("t", "key"), ("down", "1"), ("vk", "0")])), None);
        assert_eq!(parse_event(&fields(&[("t", "key"), ("down", "1"), ("vk", "256")])), None);
        assert!(parse_event(&fields(&[("t", "key"), ("down", "1"), ("vk", "65")])).is_some());
    }

    #[test] fn parse_text_counts_utf16_units_not_bytes() {
        // "ế" = 1 code unit UTF-16, 3 byte UTF-8. Đếm bằng byte sẽ chặn
        // sớm gấp 3 lần với tiếng Việt — đúng loại lỗi khó thấy.
        let parsed = parse_event(&fields(&[("t", "text"), ("s", "ế")]));
        assert_eq!(parsed, Some(Event::Text { units: vec![0x1EBF] }));

        let long = "a".repeat(MAX_TEXT_UNITS + 1);
        assert_eq!(parse_event(&fields(&[("t", "text"), ("s", &long)])), None);
    }

    #[test] fn parse_emoji_into_a_surrogate_pair() {
        // 😀 = U+1F600 ⇒ 2 code unit UTF-16.
        let parsed = parse_event(&fields(&[("t", "text"), ("s", "😀")]));
        assert_eq!(parsed, Some(Event::Text { units: vec![0xD83D, 0xDE00] }));
    }

    #[test] fn stats_count_in_and_out() {
        let mut state = InputState::new();
        state.apply(Event::Move { nx: 5, ny: 5 }, 0);
        state.apply(Event::Key { down: true, vk: 0x41 }, 0);
        assert_eq!(state.stats.events_in, 2);
        assert_eq!(state.stats.events_out, 2);
    }
}
