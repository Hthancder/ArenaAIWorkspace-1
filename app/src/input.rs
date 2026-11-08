// §44 — Input: **an toàn** (kiểm tra) và **thực thi** (`SendInput`).
//
// # Vì sao file này tồn tại hai lần ở hai chỗ
//
// `spike/src/security/input.rs` là bản **của spec** (§57.1): 12 test, đúng
// bảng §44.2, và là nơi §41 tin cậy. Nhưng `spike` là crate **thử nghiệm**
// — nó không phải thứ người dùng chạy. Người dùng chạy `lantern-mock.exe`.
//
// Bản đầu của file này là một `InputState` **viết lại từ đầu**, trùng chức
// năng với `InputSanitizer` của spec nhưng khác chi tiết (tôi dùng
// `BTreeSet` + `u16 mods`, spec dùng `Vec<u16>` + `u8 mods` có `FLAG_*`).
// Hai bản luật cho cùng một thứ là chắc chắn lệch nhau — đúng loại lỗi mà
// §41 cảnh báo.
//
// Cách sửa: **chép nguyên `InputSanitizer` của spec** vào đây (không viết
// lại), và thêm đúng phần mà `spike` không có: dịch `Event` → `Action` →
// `SendInput`. Nhờ vậy:
//
// - Luật an toàn chỉ có **một** bản, và nó là bản đã có 12 test.
// - 12 test đó giờ chạy trên Linux trong `app` nữa (không chỉ `spike`).
// - Phần mới (`inject`) không chứa quyết định nào — nó chỉ thực thi.


/// Bộ đếm theo cửa sổ thời gian — bản rút gọn của `security/gate.rs`, đủ cho
/// hai khoá `"move"` và `"ctrl"`. Không dùng `HashMap<String,…>` vì mỗi lần
/// đếm lại cấp phát một `String`, và đường này chạy 125 lần/giây.
#[derive(Debug, Default)]
#[derive(Clone)]
struct RateLimiter {
    move_times: Vec<u64>,
    ctrl_times: Vec<u64>,
}

impl RateLimiter {
    fn check(&mut self, key: &'static str, max: u32, window_ms: u64, now_ms: u64) -> bool {
        let times = if key == "move" { &mut self.move_times } else { &mut self.ctrl_times };
        times.retain(|t| now_ms.saturating_sub(*t) < window_ms);
        if times.len() as u32 >= max {
            return false;
        }
        times.push(now_ms);
        true
    }
}

// §44.2 / §44.8 / §6.5.4 — an toàn input: chỗ duy nhất được phép nói "không".
//
// Nguyên tắc từ §41.3: client **không được tin**. Mọi thứ dưới đây là kiểm
// tra lại ở phía server, kể cả khi client đã kiểm — vì "client đã kiểm" chỉ
// đúng khi client là code của ta, mà giả định nền là nó **không** phải.
//
// Bốn thứ `[CỨNG]`:
// 1. Toạ độ luôn `u16` ⇒ không thể vượt biên (kiểu dữ liệu, không phải clamp).
// 2. `Win+L` và `Ctrl+Alt+Del` (SAS) **không bao giờ** đi qua.
// 3. `release_all` idempotent + **nhảy hàng** (xử lý trước mọi thứ đang chờ).
// 4. Im 3 s mà còn phím/nút đang giữ ⇒ tự `release_all` (watchdog).



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
#[allow(dead_code)] // §8.3 / §44.2 — API đầy đủ, chưa dùng hết
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
#[allow(dead_code)] // §8.3 / §44.2 — API đầy đủ, chưa dùng hết
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
    /// Chưa nối: `accept_text` hiện dùng `from_utf16_lossy` nên hiếm khi
    /// tạo ra; giữ lại vì spec §44.2 bất biến #5 cần mã lỗi này.
    #[allow(dead_code)]
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
/// §44.7 — thứ tự hàng đợi. Chưa nối: đường HTTP hiện đồng bộ từng
/// request, nên "nhảy hàng" đã đúng theo tự nhiên. Giữ vì §44.7 yêu cầu và
/// `drain_order` có test.
#[allow(dead_code)]
pub enum Priority {
    /// Số càng nhỏ càng sớm.
    ReleaseAll = 0,
    ButtonOrKey = 1,
    Wheel = 2,
    Move = 3,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)] // §8.3 — bitmask client; chưa dùng vì HTTP gửi từng event
pub struct Held {
    pub left: bool,
    pub right: bool,
    pub middle: bool,
    pub ctrl: bool,
    pub shift: bool,
    pub alt: bool,
}

#[allow(dead_code)]
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
        let mut ups: Vec<u16> = std::mem::take(&mut self.keys_held);
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
    #[allow(dead_code)] // gọi qua `watchdog()` tự do bên dưới
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
#[allow(dead_code)] // §44.7, có test riêng
pub fn drain_order(events: &[Priority]) -> Vec<usize> {
    let mut order: Vec<usize> = (0..events.len()).collect();
    order.sort_by_key(|i| (events[*i], *i)); // ổn định: cùng mức thì giữ thứ tự đến
    order
}


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
