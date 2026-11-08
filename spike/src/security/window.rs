//! §41.4 **T1 + D1** — lỗ hổng leo thang quyền thật: client chọn cửa sổ.
//!
//! Client **không bao giờ** gửi `hwnd`. Nó gửi `wid` — một id **do agent sinh**
//! — và chỉ được chấp nhận nếu id đó nằm trong danh sách agent **vừa trả**,
//! còn hạn (cache 3 s). Nếu không có luật này, một client (hoặc trang độc hại +
//! tab của bạn) có thể đưa `hwnd` của cửa sổ bất kỳ — kể cả cửa sổ riêng tư
//! mà người ngồi máy không cho xem.
//!
//! `wid` cũng **không** phải `hwnd`: nó là id ngẫu nhiên, nên đoán cũng
//! không ra, và đọc log cũng không suy ra được cửa sổ nào trên máy.

use std::collections::HashMap;

use super::crypto::{random_hex, Entropy};

/// Danh sách sống 3 s (§41.4 T1 "cache + TTL 3 s"). Ngắn vì danh sách cửa sổ
/// là dữ liệu nhạy cảm (T18) và cửa sổ đóng/mở liên tục — danh sách cũ là
/// danh sách **sai**.
pub const SNAPSHOT_TTL_MS: u64 = 3_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowEntry {
    /// Id agent sinh (hex 16) — **không** phải hwnd.
    pub wid: String,
    pub title: String,
    pub app: String,
    pub pid: u32,
    pub minimized: bool,
    pub elevated: bool,
    /// Cửa sổ chặn chụp (`WDA_EXCLUDEFROMCAPTURE`) ⇒ chỉ xem được ở VNC.
    pub capture_blocked: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WindowError {
    /// `wid` không có trong snapshot nào còn hạn. Đây là **403**, không phải 404:
    /// client đã gửi một id không tồn tại, nghĩa là nó đoán hoặc bịa.
    UnknownWindow,
    /// Snapshot quá 3 s ⇒ phải liệt kê lại. Client cũ không được "dùng lại
    /// danh sách cũ" để mở cửa sổ vừa xuất hiện.
    Stale,
    /// Client gửi `hwnd` (số) thay vì `wid` (chuỗi) ⇒ từ chối thẳng, đây là
    /// dấu hiệu của một client không phải của ta.
    HwndNotAccepted,
}
/// Đếm mọi lần từ chối, để `/diagnostics` thấy được tấn công thay vì chỉ thấy
/// "không mở được cửa sổ".

impl WindowError {
    pub fn status(self) -> u16 {
        match self {
            WindowError::UnknownWindow => 403,
            WindowError::Stale => 409,
            WindowError::HwndNotAccepted => 400,
        }
    }

    pub fn code(self) -> &'static str {
        match self {
            WindowError::UnknownWindow => "window.unknown",
            WindowError::Stale => "window.list_stale",
            WindowError::HwndNotAccepted => "window.hwnd_not_accepted",
        }
    }
}

#[derive(Debug, Clone)]
struct Snapshot {
    entries: Vec<WindowEntry>,
    issued_ms: u64,
}

#[derive(Debug, Default)]
pub struct WindowRegistry {
    snapshots: HashMap<String, Snapshot>,
    rejections: u64,
    next_snapshot: u64,
}

impl WindowRegistry {
    /// Agent gọi sau khi `EnumWindows` — trả về `snapshot_id` cho client, kèm
    /// danh sách. Client **chỉ** tham chiếu được các `wid` trong này.
    pub fn publish(
        &mut self,
        entries: Vec<WindowEntry>,
        now_ms: u64,
        entropy: &mut impl Entropy,
        keep_for_sub: &str,
    ) -> (String, Vec<WindowEntry>) {
        self.next_snapshot += 1;
        // Loại entry trùng wid: hai entry cùng wid = dữ liệu agent hỏng, phải
        // sửa ở agent chứ không để client chọn bừa.
        let mut seen = std::collections::HashSet::new();
        let entries: Vec<WindowEntry> = entries
            .into_iter()
            .filter(|e| seen.insert(e.wid.clone()))
            .collect();

        let id = format!(
            "ws{}{}",
            self.next_snapshot,
            random_hex(6, entropy)
        );
        // Dọn snapshot cũ hơn 1 phút để bộ nhớ không phình trong phiên dài.
        self.snapshots
            .retain(|_, s| now_ms.saturating_sub(s.issued_ms) < 60_000);
        self.snapshots.insert(
            id.clone(),
            Snapshot {
                entries: entries.clone(),
                issued_ms: now_ms,
            },
        );
        let _ = keep_for_sub; // giữ chỗ cho ACL per-user khi có nhiều người dùng
        (id, entries)
    }

    /// Kiểm `wid` trước khi chuyển/stream. Đây là **cổng duy nhất** — mọi
    /// endpoint nhận `wid` (tạo phiên, đổi cửa sổ) phải đi qua đây.
    pub fn authorize(
        &mut self,
        snapshot_id: &str,
        wid: &str,
        now_ms: u64,
    ) -> Result<WindowEntry, WindowError> {
        // Client gửi số (hwnd) hoặc hex dài như hwnd ⇒ sai định dạng.
        if wid.is_empty() || wid.len() > 32 || !wid.bytes().all(is_wid_byte) {
            self.rejections += 1;
            return Err(WindowError::HwndNotAccepted);
        }
        let Some(snapshot) = self.snapshots.get(snapshot_id) else {
            self.rejections += 1;
            return Err(WindowError::UnknownWindow);
        };
        if now_ms.saturating_sub(snapshot.issued_ms) > SNAPSHOT_TTL_MS {
            self.rejections += 1;
            return Err(WindowError::Stale);
        }
        match snapshot.entries.iter().find(|e| e.wid == wid) {
            Some(entry) => Ok(entry.clone()),
            None => {
                self.rejections += 1;
                Err(WindowError::UnknownWindow)
            }
        }
    }

    pub fn rejection_count(&self) -> u64 {
        self.rejections
    }

    /// Snapshot đang sống (để test TTL).
    pub fn live_snapshots(&self, now_ms: u64) -> usize {
        self.snapshots
            .values()
            .filter(|s| now_ms.saturating_sub(s.issued_ms) <= SNAPSHOT_TTL_MS)
            .count()
    }
}

fn is_wid_byte(b: u8) -> bool {
    b.is_ascii_hexdigit()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::crypto::FixedEntropy;

    fn entry(wid: &str, title: &str) -> WindowEntry {
        WindowEntry {
            wid: wid.into(),
            title: title.into(),
            app: "chrome.exe".into(),
            pid: 4242,
            minimized: false,
            elevated: false,
            capture_blocked: false,
        }
    }

    const T0: u64 = 1_700_000_000_000;

    #[test]
    fn a_wid_from_the_list_is_accepted() {
        let mut e = FixedEntropy::new(5);
        let mut r = WindowRegistry::default();
        let (snap, list) = r.publish(vec![entry("a1b2", "Notepad"), entry("c3d4", "Chrome")], T0, &mut e, "owner");
        assert_eq!(list.len(), 2);
        let found = r.authorize(&snap, "c3d4", T0 + 10).expect("phải cho qua");
        assert_eq!(found.title, "Chrome");
    }

    #[test]
    fn a_wid_that_was_never_listed_is_403() {
        // Đây chính là lỗ hổng T1: client tự đưa một cửa sổ không có trong danh sách.
        let mut e = FixedEntropy::new(5);
        let mut r = WindowRegistry::default();
        let (snap, _) = r.publish(vec![entry("a1b2", "Notepad")], T0, &mut e, "owner");
        let err = r.authorize(&snap, "dead", T0).unwrap_err();
        assert_eq!(err, WindowError::UnknownWindow);
        assert_eq!(err.status(), 403);
        assert_eq!(r.rejection_count(), 1);
    }

    #[test]
    fn a_raw_hwnd_is_refused_even_though_it_looks_like_a_number_string() {
        let mut e = FixedEntropy::new(5);
        let mut r = WindowRegistry::default();
        let (snap, _) = r.publish(vec![entry("a1b2", "Notepad")], T0, &mut e, "owner");
        // `0000000000012abc` là hwnd thật của Notepad, nhưng không phải wid.
        let err = r.authorize(&snap, "0000000000012abc", T0).unwrap_err();
        assert_eq!(err, WindowError::UnknownWindow);
        // Chuỗi không phải hex ⇒ client lạ.
        assert_eq!(
            r.authorize(&snap, "not a wid!", T0).unwrap_err(),
            WindowError::HwndNotAccepted
        );
        assert_eq!(
            r.authorize(&snap, &"0".repeat(40), T0).unwrap_err(),
            WindowError::HwndNotAccepted
        );
    }

    #[test]
    fn the_list_expires_after_three_seconds() {
        let mut e = FixedEntropy::new(5);
        let mut r = WindowRegistry::default();
        let (snap, _) = r.publish(vec![entry("a1b2", "Notepad")], T0, &mut e, "owner");
        assert!(r.authorize(&snap, "a1b2", T0 + SNAPSHOT_TTL_MS).is_ok());
        assert_eq!(
            r.authorize(&snap, "a1b2", T0 + SNAPSHOT_TTL_MS + 1).unwrap_err(),
            WindowError::Stale
        );
        assert_eq!(r.live_snapshots(T0 + SNAPSHOT_TTL_MS + 1), 0);
    }

    #[test]
    fn a_window_that_closed_and_came_back_needs_a_new_snapshot() {
        let mut e = FixedEntropy::new(5);
        let mut r = WindowRegistry::default();
        let (first, _) = r.publish(vec![entry("aa11", "Notepad")], T0, &mut e, "owner");
        let (second, _) = r.publish(vec![entry("bb22", "Notepad")], T0 + 100, &mut e, "owner");
        // Danh sách mới không còn `aa11`.
        assert_eq!(r.authorize(&second, "aa11", T0 + 101).unwrap_err(), WindowError::UnknownWindow);
        assert!(r.authorize(&second, "bb22", T0 + 101).is_ok());
        // Nhưng snapshot cũ vẫn còn sống ≤3 s ⇒ wid cũ vẫn dùng được tới lúc đó.
        // Đây là hành vi đúng: người dùng vừa bấm vào danh sách 1 giây trước.
        assert!(r.authorize(&first, "aa11", T0 + 101).is_ok());
    }

    #[test]
    fn duplicate_wids_are_collapsed() {
        let mut e = FixedEntropy::new(5);
        let mut r = WindowRegistry::default();
        let (_, list) = r.publish(
            vec![entry("a1b2", "Notepad"), entry("a1b2", "Notepad (copy)")],
            T0,
            &mut e,
            "owner",
        );
        assert_eq!(list.len(), 1);
    }
}
