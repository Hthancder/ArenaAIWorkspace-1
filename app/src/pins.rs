//! §50.1 #2 — "lối tắt tới cửa sổ hay dùng".
//!
//! # Vì sao đây là P1 mà chỉ ~30 dòng
//!
//! Spec nói con số cụ thể: *"4 lần/ngày bạn mở đúng 1 cửa sổ. 3 bấm → **1
//! bấm**"*. Đó là toàn bộ mục đích — không phải "quản lý bookmark", chỉ là
//! một danh sách ngắn ai cũng biết dùng.
//!
//! # Ràng buộc từ spec, không phải tôi tự thêm
//!
//! * §41 (T1): không lưu **nội dung** cửa sổ, chỉ `wid` + nhãn người dùng tự
//!   đặt. Một cái nhãn là thứ người dùng gõ, không phải tiêu đề app đọc trộm.
//! * §50.1 #2: dùng `wid` của agent (danh sách §41.3 #3) — pin **không** làm
//!   cho `wid` lạ trở nên hợp lệ; `POST /api/sessions` vẫn kiểm lại.
//! * Tối đa 2 người dùng (§0.3.1 #4) nhưng pin là **một** danh sách: cả hai
//!   cùng quyền, cùng máy.
//!
//! # Vì sao lưu ra file mà không chỉ giữ trong RAM
//!
//! Ghim mà mất khi khởi động lại thì không ai dùng: mục đích là bấm 1 lần thay
//! 3 lần **trong nhiều ngày**. Cùng thư mục `data_dir` với `history.jsonl`
//! (§50.2) — một chỗ để backup, một chỗ để xoá.

use std::fs;
use std::path::{Path, PathBuf};

/// Số ghim tối đa. §50.1 #2 nói "1 cửa sổ, 4 lần/ngày"; 8 là mức mà danh sách
/// vẫn đọc được trong một lần nhìn, và đủ cho 2 người × 4.
pub const MAX_PINS: usize = 8;

/// Nhãn dài tối đa. Không phải giới hạn kỹ thuật mà là giới hạn **hiển thị**:
/// một nhãn 200 ký tự làm danh sách "bấm 1 lần" thành thứ phải đọc.
pub const MAX_LABEL_CHARS: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pin {
    /// `wid` do agent cấp (§41.3 #3) — client không bao giờ tự đặt.
    pub wid: String,
    /// Người dùng tự đặt, ví dụ "Chrome ở nhà".
    pub label: String,
    /// ms từ `UNIX_EPOCH` — để danh sách giữ thứ tự "ghim gần đây lên trước".
    pub created_ms: u64,
}

#[derive(Debug)]
pub struct Pins {
    path: PathBuf,
    items: Vec<Pin>,
}

/// Lỗi khi thêm/sửa ghim. Mã đi thẳng vào body JSON của §8.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PinError {
    /// `wid` rỗng hoặc không phải thứ agent cấp.
    BadWid,
    /// Nhãn rỗng, toàn khoảng trắng, hoặc quá [`MAX_LABEL_CHARS`].
    BadLabel,
    /// Đã có [`MAX_PINS`] ghim và đây là ghim mới.
    TooMany,
    /// `DELETE` một ghim không tồn tại.
    NotFound,
}

impl PinError {
    pub fn code(self) -> &'static str {
        match self {
            PinError::BadWid => "invalid_wid",
            PinError::BadLabel => "invalid_label",
            PinError::TooMany => "too_many_pins",
            PinError::NotFound => "pin_not_found",
        }
    }

    /// Mã HTTP cho từng lỗi.
    ///
    /// `409` cho "đã ghim" và "quá nhiều" là **cố ý**: cả hai là xung đột với
    /// trạng thái hiện tại, không phải dữ liệu sai. Trả `400` cho tất cả thì
    /// UI không phân biệt được "gõ sai nhãn" (sửa được) với "danh sách đầy"
    /// (phải xoá bớt).
    pub fn status(self) -> u16 {
        match self {
            PinError::BadWid | PinError::BadLabel => 422,
            PinError::TooMany => 409,
            PinError::NotFound => 404,
        }
    }
}

impl Pins {
    pub fn new(data_dir: &Path) -> Self {
        let path = data_dir.join("pins.json");
        let items = read_pins(&path);
        Self { path, items }
    }

    /// Chỉ test dùng: `GET /api/pins` đi qua [`Pins::json`] để một chỗ duy nhất
    /// quyết định hình dạng JSON.
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn items(&self) -> &[Pin] {
        &self.items
    }

    /// `GET /api/pins` — mới ghim trước.
    pub fn json(&self) -> String {
        let body = self
            .items
            .iter()
            .map(|pin| {
                format!(
                    "{{\"wid\":{},\"label\":{},\"createdMs\":{}}}",
                    json_quote(&pin.wid),
                    json_quote(&pin.label),
                    pin.created_ms
                )
            })
            .collect::<Vec<_>>()
            .join(",");
        format!("{{\"pins\":[{}],\"max\":{}}}", body, MAX_PINS)
    }

    /// `POST /api/pins {wid,label}`.
    ///
    /// **Idempotent theo `wid`**: ghim lại cùng `wid` cập nhật nhãn thay vì tạo
    /// mục thứ hai. Người dùng bấm "ghim" hai lần (hoặc mở 2 tab) là chuyện
    /// bình thường; biến nó thành lỗi là bắt người dùng đi xoá một bản ghi họ
    /// không biết vì sao có.
    pub fn upsert(&mut self, wid: &str, label: &str, now_ms: u64) -> Result<&Pin, PinError> {
        let wid = wid.trim();
        if wid.is_empty() || wid.len() > 64 || wid.chars().any(|c| c.is_control()) {
            return Err(PinError::BadWid);
        }
        let label = label.trim();
        if label.is_empty() || label.chars().count() > MAX_LABEL_CHARS {
            return Err(PinError::BadLabel);
        }
        if let Some(existing) = self.items.iter().position(|pin| pin.wid == wid) {
            // Cập nhật nhãn, **giữ** `created_ms`: ghim cũ vẫn là ghim cũ, chỉ
            // đổi tên. Đặt lại `created_ms` sẽ làm nó nhảy lên đầu danh sách
            // mỗi lần sửa nhãn.
            self.items[existing].label = label.to_string();
            let _ = self.save();
            return Ok(&self.items[existing]);
        }
        if self.items.len() >= MAX_PINS {
            return Err(PinError::TooMany);
        }
        self.items.insert(0, Pin {
            wid: wid.to_string(),
            label: label.to_string(),
            created_ms: now_ms,
        });
        let _ = self.save();
        Ok(&self.items[0])
    }

    /// `DELETE /api/pins?wid=...`.
    pub fn remove(&mut self, wid: &str) -> Result<Pin, PinError> {
        let wid = wid.trim();
        let Some(index) = self.items.iter().position(|pin| pin.wid == wid) else {
            return Err(PinError::NotFound);
        };
        let removed = self.items.remove(index);
        let _ = self.save();
        Ok(removed)
    }

    /// `true` nếu `wid` đã được ghim.
    ///
    /// Route `GET /api/pins` trả **cả** danh sách (tối đa 8) nên UI tự biết
    /// cửa sổ nào đã ghim; hàm này chỉ test dùng để khẳng định ghim còn sau khi
    /// đọc lại từ đĩa.
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn contains(&self, wid: &str) -> bool {
        self.items.iter().any(|pin| pin.wid == wid)
    }

    /// Ghi ra file. Lỗi ghi **không** làm hỏng thao tác trong RAM: người dùng
    /// vừa ghim thì ghim phải có tác dụng ngay, kể cả khi đĩa đầy — mất ghim
    /// sau khi khởi động lại là chuyện nhỏ hơn mất thao tác vừa làm.
    fn save(&self) -> std::io::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let body = self.json();
        // Ghi qua file tạm rồi `rename`: cắt điện đúng lúc ghi sẽ để lại
        // `pins.json` dở dang và mọi ghim biến mất. `rename` trên cùng ổ đĩa
        // là thao tác nguyên tử.
        let temp = self.path.with_extension("json.tmp");
        fs::write(&temp, body.as_bytes())?;
        fs::rename(&temp, &self.path)
    }
}

/// Đọc `pins.json`; file hỏng thì **bắt đầu rỗng**, không panic.
///
/// Một file JSON hỏng (ghi dở, sửa tay sai) không được làm app không khởi động
/// được — ghim là tiện ích, không phải dữ liệu phải sống chết.
fn read_pins(path: &Path) -> Vec<Pin> {
    let Ok(text) = fs::read_to_string(path) else {
        return Vec::new();
    };
    parse_pins(&text).unwrap_or_default()
}

/// Đọc đúng định dạng do [`Pins::json`] ghi ra. Không có thư viện JSON (§56.1:
/// 0 dependency) nên đây là bộ đọc tối thiểu, và nó chỉ cần đọc thứ **mình**
/// vừa ghi — một bộ đọc tổng quát hơn là bề mặt lỗi không cần thiết.
fn parse_pins(text: &str) -> Option<Vec<Pin>> {
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(start) = rest.find("{\"wid\":") {
        rest = &rest[start + 7..];
        let (wid, after) = read_json_string(rest)?;
        let after = after.trim_start().strip_prefix(',')?;
        let after = after.trim_start().strip_prefix("\"label\":")?;
        let (label, after) = read_json_string(after)?;
        let after = after.trim_start().strip_prefix(',')?;
        let after = after.trim_start().strip_prefix("\"createdMs\":")?;
        let digits: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
        let created_ms = digits.parse().ok()?;
        out.push(Pin { wid, label, created_ms });
        rest = after;
        if out.len() >= MAX_PINS { break; }
    }
    Some(out)
}

/// Đọc một chuỗi JSON có dấu nháy, xử lý `\"` và `\\`. Trả `(giá_trị, phần_còn_lại)`.
fn read_json_string(input: &str) -> Option<(String, &str)> {
    let mut chars = input.char_indices();
    let (_, first) = chars.next()?;
    if first != '"' {
        return None;
    }
    let mut out = String::new();
    while let Some((index, ch)) = chars.next() {
        match ch {
            '"' => return Some((out, &input[index + 1..])),
            '\\' => {
                let (_, escaped) = chars.next()?;
                out.push(match escaped {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '"' => '"',
                    '\\' => '\\',
                    other => other,
                });
            }
            other => out.push(other),
        }
    }
    None
}

fn json_quote(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push(' '),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("lantern-pins-{}-{tag}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test] fn a_pin_survives_a_restart() {
        let dir = temp_dir("restart");
        {
            let mut pins = Pins::new(&dir);
            pins.upsert("desktop", "Màn hình chính", 1_000).unwrap();
            pins.upsert("browser", "Chrome ở nhà", 2_000).unwrap();
        }
        // "Khởi động lại": đọc lại từ đĩa.
        let pins = Pins::new(&dir);
        assert_eq!(pins.items().len(), 2, "ghim phải còn sau khi đọc lại");
        assert!(pins.contains("browser"));
        assert_eq!(pins.items()[0].label, "Chrome ở nhà", "mới ghim lên trước");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test] fn pinning_the_same_window_twice_updates_instead_of_duplicating() {
        // Người dùng bấm "ghim" hai lần là chuyện bình thường. Nếu tạo mục thứ
        // hai thì danh sách "1 bấm" thành 2 bấm giống nhau.
        let dir = temp_dir("twice");
        let mut pins = Pins::new(&dir);
        pins.upsert("desktop", "Lần đầu", 1_000).unwrap();
        pins.upsert("desktop", "Đổi tên", 5_000).unwrap();
        assert_eq!(pins.items().len(), 1, "không được nhân đôi");
        assert_eq!(pins.items()[0].label, "Đổi tên");
        // `created_ms` **giữ** nguyên: sửa nhãn không làm ghim nhảy lên đầu.
        assert_eq!(pins.items()[0].created_ms, 1_000);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test] fn the_list_is_capped_and_says_so() {
        let dir = temp_dir("cap");
        let mut pins = Pins::new(&dir);
        for index in 0..MAX_PINS {
            pins.upsert(&format!("wid-{index}"), &format!("Cửa sổ {index}"), index as u64).unwrap();
        }
        let error = pins.upsert("mot-cua-so-nua", "Quá", 9_999).unwrap_err();
        assert_eq!(error, PinError::TooMany);
        assert_eq!(error.status(), 409, "đầy là xung đột, không phải dữ liệu sai");
        assert_eq!(pins.items().len(), MAX_PINS);
        // Sửa nhãn của ghim **đã có** vẫn được dù danh sách đầy.
        assert!(pins.upsert("wid-0", "Nhãn mới", 9_999).is_ok());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test] fn removing_a_pin_that_is_not_there_is_a_404_not_a_silent_success() {
        let dir = temp_dir("remove");
        let mut pins = Pins::new(&dir);
        pins.upsert("desktop", "Chính", 1).unwrap();
        assert_eq!(pins.remove("khong-co"), Err(PinError::NotFound));
        assert_eq!(PinError::NotFound.status(), 404);
        assert_eq!(pins.remove("desktop").unwrap().label, "Chính");
        assert!(pins.items().is_empty());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test] fn labels_are_trimmed_and_bounded() {
        let dir = temp_dir("label");
        let mut pins = Pins::new(&dir);
        // Nhãn có khoảng trắng hai đầu: cắt, không từ chối.
        assert_eq!(pins.upsert("desktop", "  Chính  ", 1).unwrap().label, "Chính");
        // Nhãn rỗng / toàn khoảng trắng: từ chối.
        assert_eq!(pins.upsert("a", "   ", 2).unwrap_err(), PinError::BadLabel);
        assert_eq!(pins.upsert("b", "", 2).unwrap_err(), PinError::BadLabel);
        // Dài quá `MAX_LABEL_CHARS` **ký tự** (không phải byte): tiếng Việt
        // nhiều dấu không được bị đếm oan.
        let long = "ế".repeat(MAX_LABEL_CHARS + 1);
        assert_eq!(pins.upsert("c", &long, 3).unwrap_err(), PinError::BadLabel);
        let exact = "ế".repeat(MAX_LABEL_CHARS);
        assert!(pins.upsert("d", &exact, 4).is_ok(), "đúng giới hạn phải được chấp nhận");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test] fn a_control_character_in_a_wid_is_refused() {
        // `wid` đi vào `SendInput`/capture sau này; ký tự điều khiển trong một
        // định danh là dấu hiệu dữ liệu hỏng, không phải một cửa sổ.
        let dir = temp_dir("wid");
        let mut pins = Pins::new(&dir);
        assert_eq!(pins.upsert("", "x", 1).unwrap_err(), PinError::BadWid);
        assert_eq!(pins.upsert("a\u{0}b", "x", 1).unwrap_err(), PinError::BadWid);
        assert_eq!(pins.upsert("a\nb", "x", 1).unwrap_err(), PinError::BadWid);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test] fn a_corrupt_file_means_start_empty_not_refuse_to_start() {
        // Ghi dở / sửa tay sai không được làm app không mở được.
        let dir = temp_dir("corrupt");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("pins.json"), "{\"pins\":[{\"wid\":\"desk").unwrap();
        let pins = Pins::new(&dir);
        assert!(pins.items().is_empty(), "file hỏng ⇒ rỗng, không panic");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test] fn a_label_with_quotes_and_newlines_round_trips() {
        // Nhãn do người dùng gõ, nên nó **sẽ** có dấu nháy và có thể có xuống
        // dòng dán vào. Nếu không escape đúng, một nhãn có `"` làm hỏng cả
        // file và mọi ghim biến mất sau khi khởi động lại.
        let dir = temp_dir("quotes");
        {
            let mut pins = Pins::new(&dir);
            pins.upsert("desktop", "Chrome \"ở nhà\"", 1).unwrap();
            pins.upsert("browser", "dòng 1\ndòng 2", 2).unwrap();
        }
        let pins = Pins::new(&dir);
        assert_eq!(pins.items().len(), 2);
        assert_eq!(pins.items()[0].label, "dòng 1\ndòng 2");
        assert_eq!(pins.items()[1].label, "Chrome \"ở nhà\"");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test] fn the_json_matches_what_the_route_promises() {
        let dir = temp_dir("json");
        let mut pins = Pins::new(&dir);
        pins.upsert("desktop", "Chính", 12).unwrap();
        let json = pins.json();
        assert!(json.contains("\"wid\":\"desktop\""), "{json}");
        assert!(json.contains("\"label\":\"Chính\""), "{json}");
        assert!(json.contains("\"createdMs\":12"), "{json}");
        assert!(json.contains(&format!("\"max\":{MAX_PINS}")), "{json}");
        let _ = fs::remove_dir_all(&dir);
    }
}
