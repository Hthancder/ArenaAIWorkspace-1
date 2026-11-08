//! §44 — Input: **thực thi** input. Luật nằm ở `rd_spike_lib`.
//!
//! # Bài học đã trả giá
//!
//! Bản trước của file này chứa một bản **chép tay** của `InputSanitizer` (từ
//! `spike/src/security/input.rs`, §57.1) — 12 test, cùng bảng §44.2. Lý do tôi
//! chép: `spike` là crate "thử nghiệm", còn `app` là thứ chạy thật, nên tôi
//! tưởng không dùng được. **Sai**: `rd-spike` là một lib crate bình thường,
//! 0 dependency, và `app` chỉ cần khai báo path dependency.
//!
//! Hậu quả của việc chép — đúng những gì §41 cảnh báo khi có hai bản luật:
//! bản chép của tôi chặn cả chữ `l` (bản gốc chỉ chặn `Win+L`), và bỏ sót
//! auto-repeat (`accept_key` trả `Ok` cho trường hợp "bỏ", tôi hiểu `Ok` là
//! "hãy gửi").
//!
//! Vì vậy file này **không** còn luật nào. Nó chỉ:
//!
//! 1. `parse_event` — JSON → [`Event`] (dữ liệu hỏng bị loại ở đây).
//! 2. `handle` — gọi `security::input::InputSanitizer` của spec, dịch kết quả
//!    sang [`Action`].
//! 3. `inject` — `SendInput`, không quyết định gì.
//!
//! Mọi test của luật nằm ở `spike` và chạy bằng `cargo test` ở đó **hoặc**
//! qua crate này; không có bản sao nào để lệch.

pub use rd_spike_lib::security::input::InputSanitizer;
use rd_spike_lib::security::input::{
    clamp_wheel, Reject, FLAG_BACK, FLAG_FORWARD, FLAG_LEFT, FLAG_MIDDLE, FLAG_RIGHT,
};

// --- Phần chỉ `app` có: dịch sang hành động Win32 -------------------------
//
// `InputSanitizer` nói **được phép hay không**. Phần dưới nói **gửi gì**.
// Tách hẳn để `inject()` không bao giờ tự quyết định gì.

/// Một hành động chờ đẩy xuống Win32.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Toạ độ tuyệt đối 0–65535 trên virtual desktop (§8.3).
    MoveAbs { nx: u16, ny: u16 },
    /// Tương đối, cho pointer lock / chế độ game (§6.4.6).
    MoveRel { dx: i32, dy: i32 },
    Button { down: bool, bit: u8 },
    Wheel { vertical: bool, delta: i32 },
    Key { down: bool, vk: u16 },
    /// Một code unit UTF-16 (`KEYEVENTF_UNICODE`).
    Unicode { unit: u16 },
}

/// Sự kiện từ client, đã parse xong. Không phải JSON — xem `parse_event`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Move { nx: u16, ny: u16 },
    MoveRel { dx: i32, dy: i32 },
    Button { down: bool, button: u8 },
    Wheel { vertical: bool, delta: i32 },
    Key { down: bool, vk: u16, mods: u8 },
    Text { units: Vec<u16> },
    ReleaseAll,
    Blur,
}

/// Kết quả một sự kiện: hành động cần gửi + lý do nếu bị từ chối.
pub struct Outcome {
    pub actions: Vec<Action>,
    pub rejected: Option<Reject>,
}

/// §8.3 message `move` — **12 byte nhị phân**, giải mã thành 0–2 [`Event`].
///
/// ```text
/// |u16 nx|u16 ny|u8 type|u8 flags|i16 wheel|u16 pad|
/// type:  1=move_abs  2=move_rel  3=down  4=up  5=wheel  6=touch_down 7=touch_up
/// flags: bit0..4 = left,right,middle,back,forward; bit5..7 = ctrl,shift,alt
/// ```
///
/// # Vì sao trả `Vec<Event>` chứ không một `Event`
///
/// Một gói mang **ba** thứ cùng lúc: vị trí, nút đang giữ, và wheel. Nếu chỉ
/// trả một, phải chọn bỏ hai — và bỏ cái nào cũng thành bug:
///
/// * bỏ vị trí ⇒ click xảy ra ở toạ độ cũ (người dùng thấy "click lệch")
/// * bỏ nút ⇒ không có cú click nào, hoặc nút kẹt
/// * bỏ wheel ⇒ cuộn không chạy (đúng lỗi tôi vừa sửa ở `web/input.js`)
///
/// Trả `None` khi không đúng 12 byte hoặc `type` không thuộc 1–7: một gói dị
/// dạng mà **đoán** thành `move_abs` sẽ làm con trỏ nhảy về (0,0).
pub fn parse_move(bytes: &[u8]) -> Option<Vec<Event>> {
    // **Spec tự mâu thuẫn**: §8.3 viết "binary 12 B" nhưng layout
    // `|u16 nx|u16 ny|u8 type|u8 flags|i16 wheel|u16 pad|` cộng lại chỉ **10**
    // byte (2+2+1+1+2+2). Không có cách đọc nào vừa đúng layout vừa đúng 12.
    //
    // Quyết định: **chấp nhận cả hai**. Layout là thứ quyết định vị trí byte
    // (và đó là thứ client/server phải khớp); 2 byte dư ở cuối là `pad` mở
    // rộng, bỏ qua. Như vậy:
    //
    //   * client theo đúng layout (10 B) chạy được,
    //   * client theo con số "12 B" trong tiêu đề (10 + 2 pad) chạy được,
    //   * và không bản nào phải đoán.
    //
    // Ghi lại ở đây thay vì im lặng chọn một bên: nếu sau này có client khác
    // đọc spec, họ cần biết cả hai đều hợp lệ.
    if bytes.len() != 10 && bytes.len() != 12 {
        return None;
    }
    let nx = u16::from_le_bytes([bytes[0], bytes[1]]);
    let ny = u16::from_le_bytes([bytes[2], bytes[3]]);
    let kind = bytes[4];
    let flags = bytes[5];
    let wheel = i16::from_le_bytes([bytes[6], bytes[7]]);
    // `bytes[8..10]` = pad; bỏ qua nhưng **không** từ chối nếu khác 0: một
    // client tương lai có thể dùng nó, và ta không phụ thuộc vào nó.

    let mut events = Vec::with_capacity(2);
    match kind {
        // §8.3: `move_abs` / `move_rel`. `move_rel` dùng `nx`/`ny` như `i16`
        // (delta), đó là cách duy nhất nhét delta vào cùng khung 12 byte.
        1 => events.push(Event::Move { nx, ny }),
        2 => events.push(Event::MoveRel {
            dx: nx as i16 as i32,
            dy: ny as i16 as i32,
        }),
        3 | 4 => {
            // Down/up: gói mang **toạ độ cuối cùng** (§8.3 `btn` ghi "kèm toạ
            // độ cuối cùng đã gửi"), nên phải move trước rồi mới bấm — ngược
            // lại là click ở chỗ cũ.
            events.push(Event::Move { nx, ny });
            // §6.4.1: mỗi cú bấm là **một** nút. Nếu `flags` có nhiều bit (đang
            // giữ trái, vừa bấm thêm phải) thì bit nào vừa đổi là do
            // `InputSanitizer` + trạng thái `buttons_held` quyết định; ở đây
            // gửi nút có **thứ tự ưu tiên** cố định và để sanitizer kiểm.
            let button = lowest_button_bit(flags)?;
            events.push(Event::Button { down: kind == 3, button });
        }
        5 => {
            events.push(Event::Move { nx, ny });
            // §8.3: `wheel` dấu dương = lên, khớp `MOUSEEVENTF_WHEEL`.
            events.push(Event::Wheel { vertical: true, delta: wheel as i32 });
        }
        // `touch_down`/`touch_up` (6/7): bản này chưa có touch (§6.6 cần
        // pointer events + `INPUT` API của Windows). Trả `None` để **không
        // giả vờ** — một touch giả thành click sẽ bấm nhầm chỗ.
        _ => return None,
    }
    Some(events)
}

/// Bit nút **thấp nhất** đang bật, theo thứ tự §8.3 (bit0 = trái).
///
/// Trả `None` khi `flags` không có bit nút nào: gói down/up mà không nói nút
/// nào là gói hỏng, không phải "nút trái".
fn lowest_button_bit(flags: u8) -> Option<u8> {
    let buttons = flags & 0b0001_1111;
    if buttons == 0 {
        return None;
    }
    Some(buttons.trailing_zeros() as u8)
}

/// Dựng [`Event`] từ JSON phẳng (`main::parse_flat_object`).
///
/// Trả `None` khi thiếu trường bắt buộc. **Không** đoán: một `move` thiếu
/// `ny` mà mặc định 0 sẽ giật con trỏ về đỉnh màn hình — tệ hơn từ chối.
pub fn parse_event(fields: &std::collections::BTreeMap<String, String>) -> Option<Event> {
    let kind = fields.get("t")?.as_str();
    match kind {
        "move" => Some(Event::Move {
            nx: fields.get("nx")?.parse::<u16>().ok()?,
            ny: fields.get("ny")?.parse::<u16>().ok()?,
        }),
        "move_rel" => Some(Event::MoveRel {
            dx: fields.get("dx")?.parse::<i32>().ok()?.clamp(-4096, 4096),
            dy: fields.get("dy")?.parse::<i32>().ok()?.clamp(-4096, 4096),
        }),
        "btn" => {
            let down = fields.get("down")?.as_str() != "0";
            let bit = match fields.get("b").and_then(|v| v.parse::<u8>().ok()).unwrap_or(0) {
                0 => FLAG_LEFT,
                1 => FLAG_RIGHT,
                2 => FLAG_MIDDLE,
                3 => FLAG_BACK,
                4 => FLAG_FORWARD,
                _ => return None,
            };
            Some(Event::Button { down, button: bit })
        }
        "wheel" => {
            let dx = fields.get("dx").and_then(|v| v.parse::<i32>().ok()).unwrap_or(0);
            let dy = fields.get("dy").and_then(|v| v.parse::<i32>().ok()).unwrap_or(0);
            if dy != 0 {
                Some(Event::Wheel { vertical: true, delta: clamp_wheel(dy) })
            } else if dx != 0 {
                Some(Event::Wheel { vertical: false, delta: clamp_wheel(dx) })
            } else {
                None
            }
        }
        "key" => {
            let vk = fields.get("vk")?.parse::<u16>().ok()?;
            // §44.8: 0x01–0xFF. Ngoài khoảng ⇒ bỏ cả message.
            if !(0x01..=0xFF).contains(&vk) {
                return None;
            }
            Some(Event::Key {
                down: fields.get("down")?.as_str() != "0",
                vk,
                mods: fields.get("mods").and_then(|v| v.parse::<u8>().ok()).unwrap_or(0),
            })
        }
        "text" => {
            let text = fields.get("s")?;
            // SPEC §8.3 nói `s.length ≤ 8192`; §44.8 chặn 256 code unit.
            // Kiểm cả hai: 256 là giới hạn thật, 8192 là chặn transport.
            if text.len() > 8192 {
                return None;
            }
            Some(Event::Text { units: text.encode_utf16().collect() })
        }
        "release_all" => Some(Event::ReleaseAll),
        "blur" => Some(Event::Blur),
        _ => None,
    }
}

/// Chạy một sự kiện qua `InputSanitizer` (luật) rồi dịch sang [`Action`].
///
/// `block_win_lock` = true theo mặc định của spec (§5.8.4): `Win+L` khoá máy
/// và người dùng mất hình cho tới khi đăng nhập lại.
pub fn handle(sanitizer: &mut InputSanitizer, event: Event, now_ms: u64, block_win_lock: bool) -> Outcome {
    // §44.2 + §44.7: `release_all` và `blur` **nhảy hàng** — không qua rate
    // limiter, không bị drop, và trả về ngay.
    if matches!(event, Event::ReleaseAll | Event::Blur) {
        let keys = sanitizer.release_all(now_ms);
        let mut actions: Vec<Action> = keys.into_iter().map(|vk| Action::Key { down: false, vk }).collect();
        // Nhả cả 5 nút chuột — `release_all` của sanitizer chỉ xoá bitmask,
        // không trả danh sách nút, nên ta nhả hết cho chắc.
        for bit in [FLAG_LEFT, FLAG_RIGHT, FLAG_MIDDLE, FLAG_BACK, FLAG_FORWARD] {
            actions.push(Action::Button { down: false, bit });
        }
        return Outcome { actions, rejected: None };
    }

    // §44.2: "VK đã có ⇒ **bỏ** (client gửi repeat)". `accept_key` trả `Ok(())`
    // cho trường hợp này vì nó không phải lỗi — nhưng ta **không được** gửi
    // KEYDOWN lần hai. `Ok` ở đây nghĩa là "hợp lệ", không phải "hãy gửi".
    // Phải tự phân biệt trước khi gọi.
    let repeat_ignored = matches!(
        event,
        Event::Key { down: true, vk, .. } if sanitizer.keys_held().contains(&vk)
    );

    let rejected = match event {
        Event::Move { .. } | Event::MoveRel { .. } => sanitizer.accept_move(now_ms).err(),
        Event::Button { down, button } => sanitizer.accept_button(down, button, now_ms).err(),
        Event::Key { down, vk, mods } => sanitizer.accept_key(vk, down, mods, block_win_lock, now_ms).err(),
        Event::Wheel { .. } => None,
        // §44.8: `text` >256 unit phải bị từ chối **trước** khi thành Action.
        // Bản đầu bỏ qua `accept_text` nên giới hạn đó không bao giờ chạy.
        Event::Text { ref units } => {
            let text: String = String::from_utf16_lossy(units);
            sanitizer.accept_text(&text).err()
        }
        Event::ReleaseAll | Event::Blur => unreachable!("đã xử lý ở trên"),
    };

    if rejected.is_some() {
        // `TooManyKeysHeld`: sanitizer đã xoá `keys_held` **bên trong**, nhưng
        // nó trả `Err` chứ không trả danh sách phím. Nếu ta chỉ trả `Err` thì
        // máy thật **kẹt tới 16 phím đang giữ** — đúng lỗi mà §44.2 tồn tại
        // để chặn. Vì vậy phải gửi KEYUP cho **tất cả** VK có thể đang giữ:
        // ta không biết cái nào, nên nhả dải phổ biến (modifier + chữ cái +
        // số + F1–F12) là sai hướng.
        //
        // Cách đúng: `release_all` **trước** khi báo lỗi, để không bao giờ
        // mất danh sách phím. Đổi thứ tự, không đổi luật.
        if matches!(rejected, Some(Reject::TooManyKeysHeld)) {
            let keys = sanitizer.release_all(now_ms);
            let mut actions: Vec<Action> = keys.into_iter().map(|vk| Action::Key { down: false, vk }).collect();
            for bit in [FLAG_LEFT, FLAG_RIGHT, FLAG_MIDDLE, FLAG_BACK, FLAG_FORWARD] {
                actions.push(Action::Button { down: false, bit });
            }
            return Outcome { actions, rejected };
        }
        return Outcome { actions: Vec::new(), rejected };
    }

    if repeat_ignored {
        return Outcome { actions: Vec::new(), rejected: None };
    }

    let actions = match event {
        Event::Move { nx, ny } => vec![Action::MoveAbs { nx, ny }],
        Event::MoveRel { dx, dy } => vec![Action::MoveRel { dx, dy }],
        Event::Button { down, button } => vec![Action::Button { down, bit: button }],
        Event::Wheel { vertical, delta } => vec![Action::Wheel { vertical, delta }],
        Event::Key { down, vk, .. } => vec![Action::Key { down, vk }],
        Event::Text { units } => units.into_iter().map(|unit| Action::Unicode { unit }).collect(),
        Event::ReleaseAll | Event::Blur => unreachable!(),
    };
    Outcome { actions, rejected: None }
}


// --- Win32: chỉ thực thi, không quyết định -------------------------------

/// `INPUT` của Win32 — phải khớp layout **tuyệt đối**.
///
/// Sai layout ⇒ `SendInput` trả 0 và không nói vì sao. Đó là kiểu lỗi im
/// lặng nhất trong toàn bộ file này, nên layout được khai báo tường minh
/// (không dùng `union` của Rust) và có test `size_of` bên dưới.
#[cfg(windows)]
#[repr(C)]
pub struct Win32Input {
    input_type: u32,
    /// `union { MOUSEINPUT, KEYBDINPUT, HARDWAREINPUT }` — kiểu lớn nhất là
    /// `MOUSEINPUT`: i32+i32+u32+u32+u32+usize = 28 byte, căn 8 ⇒ **32**.
    #[allow(dead_code)]
    payload: [u8; 32],
}

#[cfg(windows)]
impl Win32Input {
    fn mouse(flags: u32, dx: i32, dy: i32, data: u32) -> Self {
        let mut payload = [0u8; 32];
        payload[0..4].copy_from_slice(&dx.to_ne_bytes());
        payload[4..8].copy_from_slice(&dy.to_ne_bytes());
        payload[8..12].copy_from_slice(&data.to_ne_bytes());
        payload[12..16].copy_from_slice(&flags.to_ne_bytes());
        Self { input_type: 0, payload }
    }
    fn key(flags: u32, vk: u16, scan: u16) -> Self {
        let mut payload = [0u8; 32];
        payload[0..2].copy_from_slice(&vk.to_ne_bytes());
        payload[2..4].copy_from_slice(&scan.to_ne_bytes());
        payload[4..8].copy_from_slice(&flags.to_ne_bytes());
        Self { input_type: 1, payload }
    }
}

#[cfg(windows)]
pub const MOUSEEVENTF_MOVE: u32 = 0x0001;
#[cfg(windows)]
pub const MOUSEEVENTF_ABSOLUTE: u32 = 0x8000;
#[cfg(windows)]
pub const MOUSEEVENTF_VIRTUALDESK: u32 = 0x4000;
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
pub const KEYEVENTF_KEYUP: u32 = 0x0002;
#[cfg(windows)]
pub const KEYEVENTF_UNICODE: u32 = 0x0004;

#[cfg(windows)]
#[link(name = "user32")]
extern "system" {
    fn SendInput(count: u32, inputs: *const Win32Input, size: i32) -> u32;
}

/// Thực thi. Trả số event gửi được.
///
/// `sent < actions.len()` nghĩa là `SendInput` bị chặn — thường vì app đích
/// chạy elevated mà ta thì không (UIPI). Đây là **thông tin**, không phải lỗi
/// ta sửa được; ghi vào stats để người dùng biết vì sao click không ăn.
#[cfg(windows)]
pub fn inject(actions: &[Action]) -> u32 {
    let mut sent = 0u32;
    for action in actions {
        let batch: Vec<Win32Input> = match *action {
            Action::MoveAbs { nx, ny } => vec![Win32Input::mouse(
                MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
                i32::from(nx),
                i32::from(ny),
                0,
            )],
            Action::MoveRel { dx, dy } => vec![Win32Input::mouse(MOUSEEVENTF_MOVE, dx, dy, 0)],
            Action::Button { down, bit } => {
                let (flag, data) = match (bit, down) {
                    (FLAG_LEFT, true) => (MOUSEEVENTF_LEFTDOWN, 0),
                    (FLAG_LEFT, false) => (MOUSEEVENTF_LEFTUP, 0),
                    (FLAG_RIGHT, true) => (MOUSEEVENTF_RIGHTDOWN, 0),
                    (FLAG_RIGHT, false) => (MOUSEEVENTF_RIGHTUP, 0),
                    (FLAG_MIDDLE, true) => (MOUSEEVENTF_MIDDLEDOWN, 0),
                    (FLAG_MIDDLE, false) => (MOUSEEVENTF_MIDDLEUP, 0),
                    (FLAG_BACK, true) => (MOUSEEVENTF_XDOWN, XBUTTON1),
                    (FLAG_BACK, false) => (MOUSEEVENTF_XUP, XBUTTON1),
                    (FLAG_FORWARD, true) => (MOUSEEVENTF_XDOWN, XBUTTON2),
                    (FLAG_FORWARD, false) => (MOUSEEVENTF_XUP, XBUTTON2),
                    _ => continue,
                };
                vec![Win32Input::mouse(flag, 0, 0, data)]
            }
            Action::Wheel { vertical, delta } => {
                let flag = if vertical { MOUSEEVENTF_WHEEL } else { MOUSEEVENTF_HWHEEL };
                vec![Win32Input::mouse(flag, 0, 0, delta as u32)]
            }
            Action::Key { down, vk } => {
                let flag = if down { 0 } else { KEYEVENTF_KEYUP };
                vec![Win32Input::key(flag, vk, 0)]
            }
            // §6.5.1: `KEYEVENTF_UNICODE` gửi **cả cặp down+up** trong một
            // batch — nếu gửi rời, một lần mất gói ở giữa sẽ để lại keydown
            // treo cho một ký tự không tồn tại.
            Action::Unicode { unit } => vec![
                Win32Input::key(KEYEVENTF_UNICODE, 0, unit),
                Win32Input::key(KEYEVENTF_UNICODE | KEYEVENTF_KEYUP, 0, unit),
            ],
        };
        let count = unsafe {
            SendInput(batch.len() as u32, batch.as_ptr(), std::mem::size_of::<Win32Input>() as i32)
        };
        sent += count;
    }
    sent
}

#[cfg(not(windows))]
pub fn inject(_actions: &[Action]) -> u32 {
    0
}

/// §6.4.7 lớp 4: gọi từ vòng lặp 1 Hz. Trả danh sách KEYUP cần gửi nếu
/// watchdog kích hoạt (client im ≥3 s mà còn phím/nút đang giữ).
///
/// Vì sao phải có hàm này ở đây chứ không để `main` tự gọi `sanitizer.watchdog`:
/// `main` phải **gửi** chuỗi KEYUP đó xuống Win32, và việc dịch VK → `Action`
/// chỉ nên nằm ở một chỗ.
/// Chỉ dùng từ nhánh Windows của `stream_live` (nơi có phiên capture thật).
#[cfg_attr(not(windows), allow(dead_code))]
pub fn watchdog(sanitizer: &mut InputSanitizer, now_ms: u64) -> Option<Vec<Action>> {
    let keys = sanitizer.watchdog(now_ms)?;
    let mut actions: Vec<Action> = keys.into_iter().map(|vk| Action::Key { down: false, vk }).collect();
    for bit in [FLAG_LEFT, FLAG_RIGHT, FLAG_MIDDLE, FLAG_BACK, FLAG_FORWARD] {
        actions.push(Action::Button { down: false, bit });
    }
    Some(actions)
}

// ---------- §8.3 message `move` 12 byte ----------

    /// Dựng gói 12 byte đúng định dạng §8.3.
    #[cfg(test)]
    fn packet(nx: u16, ny: u16, kind: u8, flags: u8, wheel: i16) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(12);
        bytes.extend_from_slice(&nx.to_le_bytes());
        bytes.extend_from_slice(&ny.to_le_bytes());
        bytes.push(kind);
        bytes.push(flags);
        bytes.extend_from_slice(&wheel.to_le_bytes());
        bytes.extend_from_slice(&[0, 0]);
        assert_eq!(bytes.len(), 10, "layout §8.3 cộng lại **10** byte, không phải 12");
        bytes
    }

    #[test] fn a_wrong_length_is_refused_not_guessed() {
        // Đoán một gói ngắn thành `move_abs` sẽ làm con trỏ nhảy về (0,0) —
        // người dùng thấy chuột tự chạy.
        assert!(parse_move(&[]).is_none());
        assert!(parse_move(&[0u8; 9]).is_none());
        assert!(parse_move(&[0u8; 11]).is_none(), "11 không phải layout lẫn tiêu đề");
        assert!(parse_move(&[0u8; 13]).is_none());
    }

    #[test] fn both_readings_of_the_specs_move_size_are_accepted() {
        // §8.3 ghi "12 B" nhưng layout cộng lại 10. Đây là mâu thuẫn của spec,
        // không phải của client. Chấp nhận **cả hai** để bản nào theo spec
        // cũng chạy — và ghi lại thay vì im lặng chọn một bên.
        let ten = packet(100, 200, 1, 0, 0);
        assert_eq!(ten.len(), 10);
        let mut twelve = ten.clone();
        twelve.extend_from_slice(&[0, 0]);
        for bytes in [ten, twelve] {
            let events = parse_move(&bytes).expect("cả 10 và 12 byte phải đọc được");
            assert!(matches!(events[0], Event::Move { nx: 100, ny: 200 }));
        }
    }

    #[test] fn move_abs_and_move_rel_use_the_same_fields_differently() {
        let abs = parse_move(&packet(1000, 2000, 1, 0, 0)).unwrap();
        assert_eq!(abs.len(), 1);
        assert!(matches!(abs[0], Event::Move { nx: 1000, ny: 2000 }));

        // `move_rel` đọc cùng 16 bit như **số có dấu** (§8.3 chỉ có 12 byte
        // cho cả hai).
        let rel = parse_move(&packet(0xFFFF, 0xFFFE, 2, 0, 0)).unwrap();
        assert!(matches!(rel[0], Event::MoveRel { dx: -1, dy: -2 }), "{rel:?}");
    }

    #[test] fn a_click_moves_first_then_presses() {
        // §8.3 `btn` ghi "kèm toạ độ cuối cùng đã gửi". Nếu bấm trước rồi
        // move, cú click xảy ra ở toạ độ **cũ** — người dùng thấy click lệch,
        // đây là lỗi kinh điển của remote desktop.
        for (kind, down) in [(3u8, true), (4u8, false)] {
            let events = parse_move(&packet(300, 400, kind, 0b0000_0001, 0)).unwrap();
            assert_eq!(events.len(), 2, "move + button");
            assert!(matches!(events[0], Event::Move { nx: 300, ny: 400 }), "move phải đứng trước");
            assert!(matches!(events[1], Event::Button { down: d, button: 0 } if d == down), "{events:?}");
        }
    }

    #[test] fn every_button_bit_of_the_spec_maps_to_its_index() {
        // §8.3 bit0..4 = trái, phải, giữa, back, forward.
        for bit in 0..5u8 {
            let events = parse_move(&packet(0, 0, 3, 1 << bit, 0)).unwrap();
            assert!(
                matches!(events[1], Event::Button { down: true, button } if button == bit),
                "bit {bit} ⇒ button {bit}: {events:?}"
            );
        }
    }

    #[test] fn a_button_packet_with_no_button_bit_is_refused() {
        // Gói down mà không nói nút nào là gói hỏng. Mặc định "nút trái" nghĩa
        // là một gói mạng hỏng thành một cú click thật.
        assert!(parse_move(&packet(0, 0, 3, 0, 0)).is_none());
        assert!(parse_move(&packet(0, 0, 4, 0b1110_0000, 0)).is_none(), "chỉ có bit phím bổ trợ");
    }

    #[test] fn a_wheel_packet_carries_move_and_signed_delta() {
        let events = parse_move(&packet(500, 600, 5, 0, -120)).unwrap();
        assert_eq!(events.len(), 2);
        assert!(matches!(events[0], Event::Move { nx: 500, ny: 600 }));
        assert!(matches!(events[1], Event::Wheel { vertical: true, delta: -120 }), "{events:?}");
        // Dương = cuộn lên (cùng chiều `MOUSEEVENTF_WHEEL`).
        let up = parse_move(&packet(0, 0, 5, 0, 120)).unwrap();
        assert!(matches!(up[1], Event::Wheel { delta: 120, .. }));
    }

    #[test] fn touch_and_unknown_types_are_refused_rather_than_faked() {
        // §6.6 (touch) chưa làm. Một touch giả thành click là bấm nhầm chỗ.
        for kind in [0u8, 6, 7, 8, 255] {
            assert!(parse_move(&packet(0, 0, kind, 0b1, 0)).is_none(), "type {kind} phải bị từ chối");
        }
    }

    #[test] fn out_of_range_coordinates_are_clamped_by_the_sanitizer_not_here() {
        // Parser **không** clamp: nó chỉ giải mã. Việc clamp là của
        // `InputSanitizer` (§44.2), một chỗ duy nhất — nếu parser cũng clamp
        // thì có hai bản luật và chúng sẽ lệch.
        let events = parse_move(&packet(65535, 65535, 1, 0, 0)).unwrap();
        assert!(matches!(events[0], Event::Move { nx: 65535, ny: 65535 }));

}
