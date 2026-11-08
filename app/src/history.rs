//! §50.2 — Lịch sử phiên: **nhật ký của tôi**, không phải audit trail.
//!
//! Spec cắt bảng `audit` 7 bảng (§26.1) nhưng giữ lịch sử, vì nó trả lời câu
//! khác: *"sáng nay mình đã mở gì trên máy đó"* và *"hôm qua nó giật — phiên
//! nào, mode nào, bao lâu"*.
//!
//! Ba ràng buộc của spec, mỗi cái là một lựa chọn thiết kế ở đây:
//!
//! 1. **Không lưu nội dung, không lưu ảnh.** Chỉ 9 trường vô hại. Một file
//!    lịch sử bị đọc trộm không được tiết lộ bạn đã *thấy* gì, chỉ là đã *mở*
//!    phiên trong bao lâu.
//! 2. **`titleHash`, không phải tiêu đề.** §41 nói không lưu tiêu đề cửa sổ
//!    (tiêu đề là nội dung: tên file đang mở, đoạn chat, tên bệnh nhân…).
//!    Hash 4 byte đủ để phân biệt "cùng cửa sổ" với "cửa sổ khác", không đủ
//!    để đọc ra gì.
//! 3. **Xoay 7 ngày hoặc 500 dòng, cái nào tới trước** — và xoay xảy ra khi
//!    *ghi*, không phải khi đọc: đọc không được làm chậm UI.

use std::fs;
use std::path::{Path, PathBuf};

/// Số dòng tối đa (§50.2).
pub const MAX_LINES: usize = 500;
/// Số ngày giữ (§50.2).
pub const MAX_AGE_DAYS: u64 = 7;

/// Một phiên đã kết thúc. Đúng 9 trường của §50.2 — không thêm trường nào,
/// vì mỗi trường thêm vào là một thứ có thể bị đọc trộm.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Record {
    /// Unix ms lúc **bắt đầu** phiên.
    pub ts: u64,
    /// `sid` — để đối chiếu với log nếu có sự cố.
    pub sid: String,
    /// `user` — 1 trong 2 (§0.3.1: ≤2 tài khoản). Hiện luôn `"local"`.
    pub user: String,
    /// Tên app đã xem (`"desktop"`, `"chrome"`…) — **không** phải tiêu đề.
    pub app: String,
    /// Hash 4 byte của tiêu đề, dạng hex 8 ký tự. Xem ghi chú đầu file.
    pub title_hash: String,
    /// `hvnc` hoặc `vnc`.
    pub mode: String,
    /// Độ dài phiên, giây.
    pub duration_s: u64,
    /// `closed` | `app_closed` | `timeout` | `error` | `switch`.
    pub end_reason: String,
    /// Byte JPEG đã gửi trong phiên — số **đo được**, không phải ước lượng.
    pub bytes_out: u64,
}

impl Record {
    /// Một dòng JSON. Tự viết escape thay vì kéo `serde` vào (0 dependency).
    pub fn to_json(&self) -> String {
        format!(
            "{{\"ts\":{},\"sid\":{},\"user\":{},\"app\":{},\"title_hash\":{},\"mode\":{},\"duration_s\":{},\"end_reason\":{},\"bytes_out\":{}}}",
            self.ts,
            quote(&self.sid),
            quote(&self.user),
            quote(&self.app),
            quote(&self.title_hash),
            quote(&self.mode),
            self.duration_s,
            quote(&self.end_reason),
            self.bytes_out
        )
    }
}

fn quote(value: &str) -> String {
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

/// Hash 4 byte của tiêu đề — §41: **không lưu tiêu đề**, chỉ dấu vân tay.
///
/// FNV-1a 32 bit: không phải hash mật mã, và **không cần** phải là. Mục đích
/// duy nhất là "hai lần mở cùng một cửa sổ có cùng số không". Một hash mật mã
/// ở đây sẽ tạo cảm giác an toàn hơn thực tế: kẻ đọc được file vẫn có thể
/// thử *đoán* tiêu đề. Điều duy nhất thật sự bảo vệ là **không lưu tiêu đề**.
pub fn title_hash(title: &str) -> String {
    let mut hash: u32 = 0x811c_9dc5;
    for byte in title.as_bytes() {
        hash ^= u32::from(*byte);
        hash = hash.wrapping_mul(0x0100_0193);
    }
    format!("{hash:08x}")
}

/// Kho lịch sử trên đĩa. Không có `Drop`, không có thread — ghi đồng bộ,
/// vì mỗi lần ghi là một dòng khi kết thúc phiên (1 lần / phiên, không phải
/// 1 lần / frame).
pub struct History {
    path: PathBuf,
}

impl History {
    pub fn new(dir: &Path) -> Self {
        Self { path: dir.join("history.jsonl") }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Ghi một dòng rồi xoay nếu cần. Không trả lỗi ra ngoài: lịch sử hỏng
    /// **không được** làm hỏng phiên. Nhưng cũng không nuốt im lặng — trả
    /// `Result` để nơi gọi quyết định ghi log.
    pub fn append(&self, record: &Record, now_ms: u64) -> std::io::Result<()> {
        use std::io::Write;
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut file = fs::OpenOptions::new().create(true).append(true).open(&self.path)?;
        writeln!(file, "{}", record.to_json())?;
        drop(file);
        self.rotate(now_ms)?;
        Ok(())
    }

    /// §50.2: giữ tối đa 500 dòng, tối đa 7 ngày.
    ///
    /// Xoay khi **ghi**, không khi đọc — đọc phải nhanh và không được sửa file.
    pub fn rotate(&self, now_ms: u64) -> std::io::Result<()> {
        let Ok(text) = fs::read_to_string(&self.path) else { return Ok(()) };
        let cutoff_ms = now_ms.saturating_sub(MAX_AGE_DAYS * 24 * 60 * 60 * 1000);
        let mut kept: Vec<&str> = text
            .lines()
            .filter(|line| !line.trim().is_empty())
            .filter(|line| match line_ts(line) {
                Some(ts) => ts >= cutoff_ms,
                // Dòng không đọc được `ts` thì bỏ: nó không chứng minh được
                // là còn trong hạn, và lịch sử không phải nơi giữ dữ liệu lạ.
                None => false,
            })
            .collect();
        if kept.len() > MAX_LINES {
            kept = kept.split_off(kept.len() - MAX_LINES);
        }
        let rebuilt = format!("{}\n", kept.join("\n"));
        if rebuilt != text {
            fs::write(&self.path, rebuilt)?;
        }
        Ok(())
    }

    /// Đọc lịch sử, **mới nhất trước**. `None` = file chưa có (lần đầu chạy).
    ///
    /// Chỉ đọc tối đa [`MAX_LINES`] dòng — spec cấm phân trang ảo hoá.
    pub fn read(&self) -> Vec<Record> {
        let Ok(text) = fs::read_to_string(&self.path) else { return Vec::new() };
        let mut records: Vec<Record> = text
            .lines()
            .filter_map(parse_line)
            .collect();
        records.reverse();
        records.truncate(MAX_LINES);
        records
    }
}

/// Lấy `ts` từ dòng JSON mà không viết cả parser: dòng do `to_json` sinh ra
/// luôn bắt đầu bằng `{"ts":`.
fn line_ts(line: &str) -> Option<u64> {
    let rest = line.strip_prefix("{\"ts\":")?;
    let end = rest.find(|c: char| !c.is_ascii_digit())?;
    rest[..end].parse().ok()
}

/// Đọc lại một dòng. **Cố tình không** dùng parser JSON chung: lịch sử là
/// dữ liệu *ta* ghi ra, và nếu nó hỏng thì bỏ dòng đó chứ không làm hỏng UI.
fn parse_line(line: &str) -> Option<Record> {
    let field = |name: &str| -> Option<String> {
        let needle = format!("\"{name}\":");
        let start = line.find(&needle)? + needle.len();
        let rest = &line[start..];
        if let Some(stripped) = rest.strip_prefix('"') {
            let end = stripped.find('"')?;
            Some(stripped[..end].to_string())
        } else {
            let end = rest.find([',', '}'])?;
            Some(rest[..end].to_string())
        }
    };
    Some(Record {
        ts: field("ts")?.parse().ok()?,
        sid: field("sid")?,
        user: field("user")?,
        app: field("app")?,
        title_hash: field("title_hash")?,
        mode: field("mode")?,
        duration_s: field("duration_s")?.parse().ok()?,
        end_reason: field("end_reason")?,
        bytes_out: field("bytes_out")?.parse().ok()?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("lantern-history-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn record(ts: u64, sid: &str) -> Record {
        Record {
            ts,
            sid: sid.into(),
            user: "local".into(),
            app: "desktop".into(),
            title_hash: title_hash("Màn hình nền"),
            mode: "vnc".into(),
            duration_s: 65,
            end_reason: "closed".into(),
            bytes_out: 1_234_567,
        }
    }

    #[test] fn a_record_survives_a_round_trip() {
        let dir = tmp_dir("roundtrip");
        let history = History::new(&dir);
        let original = record(1_700_000_000_000, "mock-1");
        history.append(&original, 1_700_000_000_000).unwrap();
        let read = history.read();
        assert_eq!(read.len(), 1);
        assert_eq!(read[0], original);
    }

    #[test] fn the_newest_record_comes_first() {
        let dir = tmp_dir("order");
        let history = History::new(&dir);
        history.append(&record(1, "a"), 1_000).unwrap();
        history.append(&record(2, "b"), 2_000).unwrap();
        history.append(&record(3, "c"), 3_000).unwrap();
        let read = history.read();
        assert_eq!(read.iter().map(|r| r.sid.as_str()).collect::<Vec<_>>(), ["c", "b", "a"]);
    }

    #[test] fn only_the_last_500_lines_are_kept() {
        let dir = tmp_dir("cap");
        let history = History::new(&dir);
        // Ghi 510 dòng, tất cả trong hạn.
        for i in 0..510u64 {
            history.append(&record(1_700_000_000_000 + i, &format!("s{i}")), 1_700_000_000_000 + i).unwrap();
        }
        let read = history.read();
        assert_eq!(read.len(), MAX_LINES, "phải cắt còn {MAX_LINES} dòng");
        // Dòng mới nhất phải còn, dòng cũ nhất phải mất.
        assert_eq!(read[0].sid, "s509");
        assert!(!read.iter().any(|r| r.sid == "s0"), "dòng cũ nhất phải bị cắt");
    }

    #[test] fn records_older_than_seven_days_are_dropped() {
        let dir = tmp_dir("age");
        let history = History::new(&dir);
        let now = 1_700_000_000_000u64;
        let day = 24 * 60 * 60 * 1000u64;
        history.append(&record(now - 8 * day, "cũ"), now - 8 * day).unwrap();
        history.append(&record(now - day, "mới"), now - day).unwrap();
        // Xoay theo `now`, không theo lúc ghi.
        history.rotate(now).unwrap();
        let read = history.read();
        assert_eq!(read.len(), 1, "quá 7 ngày phải bị xoá");
        assert_eq!(read[0].sid, "mới");
    }

    #[test] fn the_title_is_never_stored_only_its_hash() {
        let dir = tmp_dir("hash");
        let history = History::new(&dir);
        let secret_title = "hóa đơn bệnh nhân Nguyễn Văn A";
        let mut r = record(1, "s");
        r.title_hash = title_hash(secret_title);
        history.append(&r, 1).unwrap();
        let raw = fs::read_to_string(history.path()).unwrap();
        assert!(!raw.contains("Nguyễn"), "tiêu đề không được nằm trong file");
        assert!(!raw.contains("bệnh nhân"));
        assert!(raw.contains(&title_hash(secret_title)));
        // Cùng tiêu đề ⇒ cùng hash; khác một ký tự ⇒ khác hash.
        assert_eq!(title_hash(secret_title), title_hash(secret_title));
        assert_ne!(title_hash("a"), title_hash("b"));
    }

    #[test] fn a_corrupt_line_does_not_break_the_whole_history() {
        let dir = tmp_dir("corrupt");
        let history = History::new(&dir);
        history.append(&record(1, "tốt"), 1).unwrap();
        // Ai đó sửa file hoặc đĩa hỏng giữa chừng.
        let mut text = fs::read_to_string(history.path()).unwrap();
        text.push_str("{\"ts\": rác không phải số}\n");
        text.push_str("dòng này không phải json\n");
        fs::write(history.path(), text).unwrap();
        let read = history.read();
        assert_eq!(read.len(), 1, "dòng hỏng bị bỏ, dòng tốt vẫn còn");
        assert_eq!(read[0].sid, "tốt");
    }

    /// **Lỗi thật**: `ts` ghi bằng giây, `now_ms` so bằng mili ⇒ lệch 1000×,
    /// mọi dòng bị coi là quá 7 ngày và bị xoá ngay khi vừa ghi. Lịch sử
    /// luôn rỗng mà **không** báo lỗi — kiểu lỗi tệ nhất.
    ///
    /// Test này khoá **đơn vị**: một `ts` tính bằng giây phải bị coi là dữ
    /// liệu sai (bỏ), chứ không được âm thầm xoá cả file.
    #[test] fn a_seconds_timestamp_is_recognised_as_the_wrong_unit() {
        let dir = tmp_dir("units");
        let history = History::new(&dir);
        let now_ms = 1_700_000_000_000u64;
        // Ghi đúng đơn vị (mili) ⇒ còn.
        history.append(&record(now_ms - 1_000, "mili"), now_ms).unwrap();
        // Ghi sai đơn vị (giây) ⇒ bị coi là quá cũ (1970), phải bị xoá — và
        // đó là hành vi **đúng**: dữ liệu sai đơn vị thì không dùng được.
        history.append(&record((now_ms / 1_000) - 1, "giây"), now_ms).unwrap();
        let read = history.read();
        assert_eq!(read.len(), 1, "chỉ dòng đúng đơn vị còn lại");
        assert_eq!(read[0].sid, "mili");
    }

    #[test] fn reading_a_missing_file_is_empty_not_an_error() {
        let dir = tmp_dir("missing");
        let history = History::new(&dir);
        assert!(history.read().is_empty());
    }

    #[test] fn no_field_can_inject_a_newline_into_the_log() {
        // Nếu một trường chứa `\n` mà ta không escape, một phiên sẽ thành hai
        // dòng — và `bytes_out` của dòng thứ hai sẽ là rác.
        let dir = tmp_dir("inject");
        let history = History::new(&dir);
        let mut r = record(1, "s");
        r.app = "desktop\n{\"ts\":9999,\"sid\":\"giả\"}".into();
        history.append(&r, 1).unwrap();
        let raw = fs::read_to_string(history.path()).unwrap();
        assert_eq!(raw.lines().count(), 1, "không được thành 2 dòng");
    }
}
