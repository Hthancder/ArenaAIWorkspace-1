//! Mô hình dữ liệu cốt lõi: Task, List, Store, View và các tiện ích ngày tháng.

use chrono::{DateTime, Datelike, Local, Months, NaiveDate, TimeDelta, Utc};
use std::collections::HashMap;
use serde::{Deserialize, Serialize};

pub type TaskId = u64;

/// Hôm nay (giờ local của hệ thống).
pub fn today() -> NaiveDate {
    Local::now().date_naive()
}

pub const VN_WEEKDAYS: [&str; 7] = [
    "Thứ Hai",
    "Thứ Ba",
    "Thứ Tư",
    "Thứ Năm",
    "Thứ Sáu",
    "Thứ Bảy",
    "Chủ Nhật",
];

/// Tên thứ trong tuần (Thứ Hai..Chủ Nhật).
pub fn weekday_name(d: NaiveDate) -> &'static str {
    VN_WEEKDAYS[d.weekday().num_days_from_monday() as usize]
}

/// Ưu tiên: P1 cao nhất, P4 = không ưu tiên (thứ tự Ord: P1 < P2 < P3 < P4).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, Default)]
pub enum Priority {
    P1,
    P2,
    P3,
    #[default]
    P4,
}

impl Priority {
    pub fn color_rgb(self) -> (u8, u8, u8) {
        match self {
            Priority::P1 => (239, 68, 68),
            Priority::P2 => (245, 158, 11),
            Priority::P3 => (59, 130, 246),
            Priority::P4 => (120, 130, 150),
        }
    }

    pub fn short(self) -> &'static str {
        match self {
            Priority::P1 => "P1",
            Priority::P2 => "P2",
            Priority::P3 => "P3",
            Priority::P4 => "P4",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Priority::P1 => "Ưu tiên 1 (Cao)",
            Priority::P2 => "Ưu tiên 2 (Trung bình)",
            Priority::P3 => "Ưu tiên 3 (Thấp)",
            Priority::P4 => "Không ưu tiên",
        }
    }

    pub fn all() -> [Priority; 4] {
        [Priority::P1, Priority::P2, Priority::P3, Priority::P4]
    }
}

/// Nhịp lặp lại của việc.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum Repeat {
    #[default]
    None,
    Daily,
    Weekdays,
    Weekly,
    Monthly,
}

impl Repeat {
    pub fn label(self) -> &'static str {
        match self {
            Repeat::None => "Không lặp lại",
            Repeat::Daily => "Hàng ngày",
            Repeat::Weekdays => "Các ngày trong tuần (T2–T6)",
            Repeat::Weekly => "Hàng tuần",
            Repeat::Monthly => "Hàng tháng",
        }
    }

    pub fn short(self) -> &'static str {
        match self {
            Repeat::None => "",
            Repeat::Daily => "hàng ngày",
            Repeat::Weekdays => "ngày tuần",
            Repeat::Weekly => "hàng tuần",
            Repeat::Monthly => "hàng tháng",
        }
    }

    /// Ngày kế tiếp của lần lặp, tính từ `from`.
    pub fn next_after(self, from: NaiveDate) -> Option<NaiveDate> {
        match self {
            Repeat::None => None,
            Repeat::Daily => from.checked_add_signed(TimeDelta::days(1)),
            Repeat::Weekly => from.checked_add_signed(TimeDelta::days(7)),
            Repeat::Monthly => from.checked_add_months(Months::new(1)),
            Repeat::Weekdays => {
                let mut d = from.checked_add_signed(TimeDelta::days(1))?;
                for _ in 0..10 {
                    if d.weekday().num_days_from_monday() < 5 {
                        return Some(d);
                    }
                    d = d.checked_add_signed(TimeDelta::days(1))?;
                }
                None
            }
        }
    }

    pub fn all() -> [Repeat; 5] {
        [
            Repeat::None,
            Repeat::Daily,
            Repeat::Weekdays,
            Repeat::Weekly,
            Repeat::Monthly,
        ]
    }
}

// ------------------------------------------------------------------ lặp lại hạng nhất (v2.9.0)

/// Tần suất lặp.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Freq {
    Day,
    Week,
    Month,
    Year,
}

/// Cách kết thúc chuỗi lặp.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum EndSpec {
    Never,
    /// NGÀY CUỐI CÙNG việc có thể xuất hiện (due == until vẫn hợp lệ).
    Until { date: NaiveDate },
    /// total = số lần Hoàn thành cần có (sau khi đặt rule); done = số lần đã bấm.
    After { total: u32, done: u32 },
}

impl Default for EndSpec {
    fn default() -> Self {
        EndSpec::Never
    }
}

const WD_BITS_WEEKDAYS: u8 = 0b001_1111; // T2..T6 (bit0 = Thứ Hai … bit6 = Chủ Nhật)

/// Quy tắc lặp hạng nhất. `Repeat` cũ chỉ còn vai trò shadow (downgrade an toàn).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecurrenceRule {
    pub freq: Freq,
    #[serde(default = "one")]
    pub interval: u32, // 1..=99 (kẹp)
    /// Week: bitmask T2..CN. None = trùng thứ với hạn chót của việc.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub by_day: Option<u8>,
    /// Month/Year: ngày trong tháng 1..=31, -1 = ngày cuối cùng của tháng.
    /// Luôn được đóng băng (anchor) ngay khi tạo/nạp — xem `freeze_anchor`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub month_day: Option<i8>,
    #[serde(default)]
    pub ends: EndSpec,
}

fn one() -> u32 {
    1
}

impl RecurrenceRule {
    pub fn new(freq: Freq) -> Self {
        Self { freq, interval: 1, by_day: None, month_day: None, ends: EndSpec::Never }
    }

    /// Kẹp + chuẩn hoá (không bao giờ để rule hỏng vào file).
    pub fn clamped(mut self) -> Self {
        self.interval = self.interval.clamp(1, 99);
        match self.freq {
            Freq::Week => {
                self.month_day = None;
                // mask giữ nguyên (mask rỗng = không có ngày nào → validate() sẽ chặn khi lưu;
                // next_date_only gặp mask 0 → None → sanitize gỡ thành việc thường, an toàn).
                self.by_day = self.by_day.map(|m| m & 0b111_1111);
            }
            Freq::Month | Freq::Year => {
                self.by_day = None;
                if let Some(d) = self.month_day {
                    self.month_day = Some(if d == -1 { -1 } else { d.clamp(1, 31) });
                }
            }
            Freq::Day => {
                // Day + mask = kiểu “các ngày trong tuần” (Weekdays legacy) — mask giữ nguyên;
                // interval vô nghĩa khi có mask → ép 1.
                self.month_day = None;
                self.by_day = self.by_day.map(|m| m & 0b111_1111);
                if self.by_day.is_some() {
                    self.interval = 1;
                }
            }
        }
        if let EndSpec::After { total, done } = &mut self.ends {
            *total = (*total).clamp(1, 999);
            *done = (*done).min(*total);
        }
        self
    }

    /// Kiểm hợp lệ cho rule NGƯỜI DÙNG TẠO (không dùng cho rule legacy nạp từ file).
    pub fn validate(&self) -> Result<(), String> {
        if self.freq == Freq::Week && self.by_day.unwrap_or(0) == 0 {
            return Err("Chọn ít nhất 1 thứ trong tuần".to_string());
        }
        if let EndSpec::Until { date } = &self.ends {
            if *date < today() {
                return Err("Ngày kết thúc phải ở tương lai".to_string());
            }
        }
        Ok(())
    }

    /// Shadow về `Repeat` cũ — rule custom (interval>1, mask, until/after) → `None`
    /// để build cũ mở file thấy "Không lặp" nhưng tuyệt đối không nhân bản loạn.
    pub fn shadow(&self) -> Repeat {
        if !matches!(self.ends, EndSpec::Never) {
            return Repeat::None;
        }
        match self.freq {
            Freq::Day => match self.by_day {
                None if self.interval == 1 => Repeat::Daily,
                Some(m) if self.interval == 1 && m == WD_BITS_WEEKDAYS => Repeat::Weekdays,
                _ => Repeat::None,
            },
            Freq::Week => match self.by_day {
                None if self.interval == 1 => Repeat::Weekly,
                _ => Repeat::None,
            },
            Freq::Month if self.interval == 1 => Repeat::Monthly,
            _ => Repeat::None,
        }
    }

    /// Đóng băng anchor (month_day) cho Month/Year khi còn thiếu.
    pub fn freeze_anchor(&mut self, due: Option<NaiveDate>) {
        if matches!(self.freq, Freq::Month | Freq::Year) && self.month_day.is_none() {
            let d = due.map(|d| d.day() as i8).unwrap_or_else(|| today().day() as i8);
            self.month_day = Some(d);
        }
    }
}

/// Nâng `Repeat` legacy lên rule hạng nhất (dùng khi nạp file cũ trong sanitize).
pub fn rule_from_repeat(r: Repeat, due: Option<NaiveDate>) -> Option<RecurrenceRule> {
    let day = due.map(|d| d.day() as i8).unwrap_or_else(|| today().day() as i8);
    Some(match r {
        Repeat::None => return None,
        Repeat::Daily => RecurrenceRule { freq: Freq::Day, interval: 1, by_day: None, month_day: None, ends: EndSpec::Never },
        Repeat::Weekdays => RecurrenceRule { freq: Freq::Day, interval: 1, by_day: Some(WD_BITS_WEEKDAYS), month_day: None, ends: EndSpec::Never },
        Repeat::Weekly => RecurrenceRule { freq: Freq::Week, interval: 1, by_day: None, month_day: None, ends: EndSpec::Never },
        Repeat::Monthly => RecurrenceRule { freq: Freq::Month, interval: 1, by_day: None, month_day: Some(day), ends: EndSpec::Never },
    })
}

fn last_day_of_month(y: i32, m: u32) -> u32 {
    let (ny, nm) = if m == 12 { (y + 1, 1) } else { (y, m + 1) };
    NaiveDate::from_ymd_opt(ny, nm, 1).unwrap().pred_opt().unwrap().day()
}

/// Cộng tháng trên **field tháng** (không trôi ngày): (y*12 + m - 1) + delta.
fn add_months_fields(y: i32, m: u32, delta: u32) -> (i32, u32) {
    let total = y as i64 * 12 + (m as i64 - 1) + delta as i64;
    ((total.div_euclid(12)) as i32, (total.rem_euclid(12) + 1) as u32)
}

/// Đầu tuần (Thứ Hai) chứa `d`.
pub fn week_start(d: NaiveDate) -> NaiveDate {
    d - TimeDelta::days(d.weekday().num_days_from_monday() as i64)
}

/// Ngày lặp kế tiếp SAU `from` — thuần ngày tháng + `Until`; KHÔNG xét bộ đếm `After`.
/// Dùng chung cho mọi thứ; bộ đếm After được cộng thêm ở `next_after` / `occurrences_after`.
pub fn next_date_only(rule: &RecurrenceRule, from: NaiveDate) -> Option<NaiveDate> {
    let rule = rule.clone().clamped();
    let interval = rule.interval;
    let base = match rule.freq {
        Freq::Day => match rule.by_day {
            // Day + mask = “các ngày trong tuần” (nâng cấp Weekdays legacy)
            Some(mask) => {
                if mask == 0 {
                    return None;
                }
                let mut d = from;
                for _ in 0..8 {
                    d = d.checked_add_signed(TimeDelta::days(1))?;
                    if mask & (1u8 << d.weekday().num_days_from_monday()) != 0 {
                        break;
                    }
                }
                Some(d)
            }
            None => from.checked_add_signed(TimeDelta::days(interval as i64)),
        }
        Freq::Week => match rule.by_day {
            Some(mask) => {
                if mask == 0 {
                    return None;
                }
                let aw = week_start(from);
                let mut d = from;
                for _ in 0..(interval as i64 * 7 + 14) {
                    d = d.checked_add_signed(TimeDelta::days(1))?;
                    let bit = 1u8 << d.weekday().num_days_from_monday();
                    if mask & bit != 0 && ((week_start(d) - aw).num_days() / 7) % interval as i64 == 0 {
                        return Some(d).filter(|x| match &rule.ends {
                            EndSpec::Until { date } => *x <= *date,
                            _ => true,
                        });
                    }
                }
                None
            }
            None => from.checked_add_signed(TimeDelta::days(7 * interval as i64)),
        },
        Freq::Month => {
            let (ty, tm) = add_months_fields(from.year(), from.month(), interval);
            let dim = last_day_of_month(ty, tm);
            let anchor = rule.month_day.unwrap_or(from.day() as i8);
            let day = if anchor == -1 {
                dim
            } else {
                (anchor.max(1) as u32).min(dim)
            };
            NaiveDate::from_ymd_opt(ty, tm, day)
        }
        Freq::Year => {
            let ty = from.year().checked_add(interval as i32)?;
            let dim = last_day_of_month(ty, from.month());
            let anchor = rule.month_day.unwrap_or(from.day() as i8);
            let day = if anchor == -1 {
                dim
            } else {
                (anchor.max(1) as u32).min(dim)
            };
            NaiveDate::from_ymd_opt(ty, from.month(), day)
        }
    };
    base.filter(|b| match &rule.ends {
        EndSpec::Until { date } => *b <= *date,
        _ => true,
    })
}

/// Ngày lặp kế tiếp SAU `from` — đầy đủ (kể cả trần After).
pub fn next_after(rule: &RecurrenceRule, from: NaiveDate) -> Option<NaiveDate> {
    if let EndSpec::After { total, done } = &rule.ends {
        if done >= total {
            return None;
        }
    }
    next_date_only(rule, from)
}

/// Mọi occurrence sau `from` (tối đa `limit`, ≤200).
/// After: budget = `total - done - 1` (số bản sao còn sinh sau lần hiện tại) —
/// UI tự ghép thêm lần hiện tại (task.due) để ra "≈ N lần nữa" = `total - done`.
pub fn occurrences_after(rule: &RecurrenceRule, from: NaiveDate, limit: u32) -> Vec<NaiveDate> {
    let limit = limit.clamp(1, 200) as usize;
    let mut out = Vec::new();
    let mut cur = from;
    let mut remaining: Option<u32> = match &rule.ends {
        EndSpec::After { total, done } => Some(total.saturating_sub(*done).saturating_sub(1)),
        _ => None,
    };
    while out.len() < limit {
        if let Some(r) = remaining {
            if r == 0 {
                break;
            }
        }
        match next_date_only(rule, cur) {
            Some(d) => {
                out.push(d);
                cur = d;
                if let Some(r) = &mut remaining {
                    *r -= 1;
                }
            }
            None => break,
        }
    }
    out
}

/// Việc nhỏ (subtask).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubTask {
    pub id: TaskId,
    pub title: String,
    pub done: bool,
}

/// Một công việc.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Task {
    pub id: TaskId,
    pub title: String,
    #[serde(default)]
    pub notes: String,
    /// `None` = Hộp thư (Inbox).
    #[serde(default)]
    pub list_id: Option<TaskId>,
    #[serde(default)]
    pub priority: Priority,
    #[serde(default)]
    pub due: Option<NaiveDate>,
    #[serde(default)]
    pub repeat: Repeat,
    /// v2.9.0 — rule lặp hạng nhất (khi có, ưu tiên hơn `repeat`). `repeat` là shadow cho build cũ.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recurrence: Option<RecurrenceRule>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub subtasks: Vec<SubTask>,
    #[serde(default)]
    pub starred: bool,
    #[serde(default)]
    pub order: u32,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub completed_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub deleted_at: Option<DateTime<Utc>>,
}

impl Task {
    pub fn is_completed(&self) -> bool {
        self.completed_at.is_some()
    }

    pub fn is_deleted(&self) -> bool {
        self.deleted_at.is_some()
    }

    /// Còn "đang làm": chưa xóa, chưa hoàn thành.
    pub fn is_active(&self) -> bool {
        !self.is_deleted() && !self.is_completed()
    }

    /// Tiến độ việc nhỏ 0.0 – 1.0 (nếu không có việc nhỏ trả 1.0).
    pub fn progress(&self) -> f32 {
        if self.subtasks.is_empty() {
            1.0
        } else {
            let done = self.subtasks.iter().filter(|s| s.done).count() as f32;
            done / self.subtasks.len() as f32
        }
    }

    /// Khớp từ khóa tìm kiếm (tiêu đề, ghi chú, thẻ).
    pub fn matches_query(&self, q: &str) -> bool {
        if q.is_empty() {
            return true;
        }
        self.title.to_lowercase().contains(q)
            || self.notes.to_lowercase().contains(q)
            || self.tags.iter().any(|t| t.to_lowercase().contains(q))
    }
}

/// Danh sách tùy chỉnh.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct List {
    pub id: TaskId,
    pub name: String,
    /// Màu RGB.
    pub color: [u8; 3],
}

/// Cách sắp xếp danh sách việc.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum SortMode {
    #[default]
    Manual,
    Due,
    Priority,
    Title,
    Created,
}

impl SortMode {
    pub fn label(self) -> &'static str {
        match self {
            SortMode::Manual => "Thủ công",
            SortMode::Due => "Hạn chót",
            SortMode::Priority => "Ưu tiên",
            SortMode::Title => "Tên A → Ẩ",
            SortMode::Created => "Mới nhất",
        }
    }

    pub fn all() -> [SortMode; 5] {
        [
            SortMode::Manual,
            SortMode::Due,
            SortMode::Priority,
            SortMode::Title,
            SortMode::Created,
        ]
    }
}

/// Thiết đặt được lưu cùng dữ liệu.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default = "default_dark")]
    pub dark: bool,
    #[serde(default)]
    pub sort: SortMode,
    #[serde(default = "default_true")]
    pub hide_completed: bool,
    // ----- v2.1: tùy chỉnh giao diện -----
    /// Trong suốt Acrylic — thấy màn hình desktop phía sau cửa sổ.
    #[serde(default = "default_true")]
    pub transparent: bool,
    /// Độ phủ màu của lớp Acrylic (40–170; thấp = trong hơn).
    #[serde(default = "default_alpha")]
    pub acrylic_alpha: u8,
    /// Màu nhấn tùy chỉnh (hex, vd "#6366f1").
    #[serde(default = "default_accent")]
    pub accent: String,
    /// Giảm hiệu ứng chuyển động (trợ năng).
    #[serde(default)]
    pub reduce_motion: bool,
    // ----- v2.1: hành vi -----
    /// Hiện gợi ý phân tích khi gõ ở ô thêm nhanh.
    #[serde(default = "default_true")]
    pub qa_preview: bool,
    /// Toast nhắc số việc hôm nay mỗi lần mở app.
    #[serde(default = "default_true")]
    pub remind_today: bool,
    /// Tự tạo bản sao lưu khi thoát.
    #[serde(default)]
    pub backup_on_exit: bool,
    /// Chế độ hiệu năng: tắt blur/backdrop-filter/animation (máy yếu).
    #[serde(default)]
    pub perf_mode: bool,
    /// Chế độ ADHD: một việc tại một thời điểm, thưởng tức thì, không phán xét.
    #[serde(default)]
    pub adhd_mode: bool,
    /// Chime nhẹ khi kết thúc phiên tập trung / giờ nghỉ.
    #[serde(default = "default_true")]
    pub sound_on: bool,
    /// View đang mở lần cuối ("inbox"…"list:3") — khôi phục khi mở app.
    #[serde(default)]
    pub last_view: String,
}

fn default_dark() -> bool {
    true
}

fn default_true() -> bool {
    true
}

fn default_alpha() -> u8 {
    110
}

fn default_accent() -> String {
    "#6366f1".to_string()
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            dark: true,
            sort: SortMode::default(),
            hide_completed: true,
            transparent: true,
            acrylic_alpha: default_alpha(),
            accent: default_accent(),
            reduce_motion: false,
            qa_preview: true,
            remind_today: true,
            backup_on_exit: false,
            perf_mode: false,
            adhd_mode: false,
            sound_on: true,
            last_view: String::new(),
        }
    }
}

/// Giao diện đang xem.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum View {
    Inbox,
    Today,
    Upcoming,
    Starred,
    Completed,
    Trash,
    Stats,
    List(TaskId),
}

impl View {
    pub fn title(self, lists: &[List]) -> String {
        match self {
            View::Inbox => "Hộp thư".to_string(),
            View::Today => "Hôm nay".to_string(),
            View::Upcoming => "Sắp tới".to_string(),
            View::Starred => "Đã ghim".to_string(),
            View::Completed => "Đã hoàn thành".to_string(),
            View::Trash => "Thùng rác".to_string(),
            View::Stats => "Thống kê".to_string(),
            View::List(id) => lists
                .iter()
                .find(|l| l.id == id)
                .map(|l| l.name.clone())
                .unwrap_or_else(|| "Danh sách".to_string()),
        }
    }

    /// Có cho phép thêm việc nhanh không.
    pub fn allows_quick_add(self) -> bool {
        matches!(
            self,
            View::Inbox | View::Today | View::Upcoming | View::Starred | View::List(_)
        )
    }
}

/// Mẫu chia nhỏ do người dùng tự tạo (đặt trên Store).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StepPreset {
    #[serde(default)]
    pub id: u64,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub steps: Vec<String>,
}

/// Bộ đếm cho thanh bên / thanh trạng thái.
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Counts {
    pub inbox: usize,
    pub today: usize,
    pub upcoming: usize,
    pub starred: usize,
    pub completed: usize,
    pub trash: usize,
    pub active: usize,
    pub overdue: usize,
    pub done_today: usize,
    pub focus_today: usize,
    pub focus_week: usize,
    pub by_list: Vec<(TaskId, usize)>,
}

/// Toàn bộ dữ liệu người dùng – lưu thành JSON.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Store {
    #[serde(default = "current_version")]
    pub version: u32,
    #[serde(default = "seed_next_id")]
    pub next_id: TaskId,
    #[serde(default)]
    pub tasks: Vec<Task>,
    #[serde(default)]
    pub lists: Vec<List>,
    #[serde(default)]
    pub settings: Settings,
    /// Số phiên tập trung 25′ hoàn thành mỗi ngày (khóa ISO "yyyy-mm-dd").
    #[serde(default)]
    pub focus_days: HashMap<String, u64>,
    /// Mẫu chia nhỏ do người dùng tự tạo.
    #[serde(default)]
    pub step_presets: Vec<StepPreset>,
    /// In-memory only (không serialize): việc vừa bị sanitize gỡ rule lặp hết hạn — để flash 1 lần lúc mở app.
    #[serde(skip)]
    pub sanitize_notes: Vec<String>,
}

fn current_version() -> u32 {
    1
}

fn seed_next_id() -> TaskId {
    1
}

impl Default for Store {
    fn default() -> Self {
        Self {
            version: current_version(),
            next_id: seed_next_id(),
            tasks: Vec::new(),
            lists: Vec::new(),
            settings: Settings::default(),
            focus_days: HashMap::new(),
            step_presets: Vec::new(),
            sanitize_notes: Vec::new(),
        }
    }
}

impl Store {
    pub fn new_id(&mut self) -> TaskId {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    /// Gỡ rule lặp hết hạn còn trên **việc chưa xong** → việc thường.
    /// Trả về tiêu đề các việc bị gỡ (để flash 1 lần). Một predicate duy nhất — dùng chung
    /// cho nạp file (sanitize) và lưu rule (set_task_recurrence).
    pub fn strip_exhausted_recurrences(&mut self) -> Vec<String> {
        let tdy = today();
        let mut stripped = Vec::new();
        for t in &mut self.tasks {
            if t.completed_at.is_some() || t.deleted_at.is_some() {
                continue; // instance lịch sử giữ rule làm lịch sử
            }
            let Some(rule) = &t.recurrence else { continue };
            // "Còn occurrence nào từ hôm nay trở đi không?" — chuỗi until đã trôi qua hết
            // sẽ không sinh thêm việc ma quá khứ nữa, dù due gốc còn nằm trước until.
            let from = t.due.unwrap_or(tdy).max(tdy);
            if next_after(rule, from).is_none() {
                t.recurrence = None;
                t.repeat = Repeat::None;
                stripped.push(t.title.clone());
            }
        }
        stripped
    }

    /// Nâng cấp legacy Repeat → recurrence; đóng băng anchor; ghi shadow; gỡ rule hết hạn.
    /// Ghi chú các việc bị gỡ rule vào `sanitize_notes` (in-memory) cho flash lúc mở app.
    fn migrate_recurrences(&mut self) {
        for t in &mut self.tasks {
            // 1) upgrade: recurrence == None && repeat != None
            if t.recurrence.is_none() && t.repeat != Repeat::None {
                t.recurrence = rule_from_repeat(t.repeat, t.due);
            }
            // 2) đóng băng anchor (Month/Year)
            if let Some(r) = &mut t.recurrence {
                r.freeze_anchor(t.due);
                *r = r.clone().clamped();
            }
            // 3) shadow cho build cũ
            t.repeat = match &t.recurrence {
                Some(r) => r.shadow(),
                None => Repeat::None,
            };
        }
        // 4) gỡ rule hết hạn trên việc chưa xong + ghi chú
        self.sanitize_notes = self.strip_exhausted_recurrences();
    }

    /// Sửa dữ liệu sau khi nạp từ đĩa (hợp lệ hóa id, danh sách mồ côi...).
    pub fn sanitize(&mut self) {
        self.migrate_recurrences();
        let mut max_id = 0u64;
        for t in &self.tasks {
            max_id = max_id.max(t.id);
            if let Some(sid) = t.list_id {
                max_id = max_id.max(sid);
            }
            for s in &t.subtasks {
                max_id = max_id.max(s.id);
            }
        }
        for l in &self.lists {
            max_id = max_id.max(l.id);
        }
        for p in &mut self.step_presets {
            max_id = max_id.max(p.id);
            p.name = p.name.trim().to_string();
            p.steps = p
                .steps
                .iter()
                .map(|x| x.trim().chars().take(140).collect::<String>().trim().to_string())
                .filter(|x| !x.is_empty())
                .take(12)
                .collect();
        }
        self.step_presets.retain(|p| !p.name.is_empty() && !p.steps.is_empty());
        self.next_id = self.next_id.max(max_id + 1);
        let list_ids: Vec<TaskId> = self.lists.iter().map(|l| l.id).collect();
        for t in &mut self.tasks {
            if let Some(lid) = t.list_id {
                if !list_ids.contains(&lid) {
                    t.list_id = None;
                }
            }
            t.tags.retain(|tag| !tag.trim().is_empty());
            t.tags.dedup();
        }
    }

    /// Dữ liệu mẫu dùng khi mở lần đầu.
    pub fn seed() -> Store {
        let mut store = Store {
            version: current_version(),
            next_id: 1,
            tasks: Vec::new(),
            lists: Vec::new(),
            settings: Settings::default(),
            focus_days: HashMap::new(),
            step_presets: Vec::new(),
        };
        let lists = [
            ("Công việc", [99, 102, 241]),
            ("Cá nhân", [16, 185, 129]),
            ("Học tập", [245, 158, 11]),
        ];
        let mut list_ids = Vec::new();
        for (name, color) in lists {
            let id = store.new_id();
            store.lists.push(List {
                id,
                name: name.to_string(),
                color,
            });
            list_ids.push(id);
        }
        let t = today();
        let now = Utc::now();
        let mk = |store: &mut Store,
                  title: &str,
                  notes: &str,
                  list_id: Option<TaskId>,
                  priority: Priority,
                  due: Option<NaiveDate>,
                  repeat: Repeat,
                  tags: &[&str],
                  starred: bool,
                  subtasks: &[(&str, bool)],
                  completed: bool| {
            let id = store.new_id();
            let order = 1000 + store.tasks.len() as u32;
            let subtasks = subtasks
                .iter()
                .map(|(title, done)| SubTask {
                    id: store.new_id(),
                    title: title.to_string(),
                    done: *done,
                })
                .collect::<Vec<_>>();
            store.tasks.push(Task {
                id,
                title: title.to_string(),
                notes: notes.to_string(),
                list_id,
                priority,
                due,
                repeat,
                tags: tags.iter().map(|s| s.to_string()).collect(),
                subtasks,
                starred,
                order,
                created_at: now,
                completed_at: if completed { Some(now) } else { None },
                deleted_at: None,
                recurrence: None,
            });
        };
        mk(
            &mut store,
            "Chào mừng bạn đến với Taskora 👋",
            "Đây là ứng dụng quản lý công việc được viết bằng Rust.\n\n• Bấm vòng tròn để hoàn thành việc\n• Chuột phải để mở menu nhanh\n• Ctrl+N thêm việc · Ctrl+F tìm kiếm · Ctrl+D đổi giao diện\n• Việc lặp lại: gõ \'Tập gym *hàng ngày\' (hoặc \'*mỗi 3 ngày\', \'*mỗi 2 tuần\'…). Việc lặp chỉ hiện 1 lần; hoàn thành sẽ tự tạo lần tiếp theo. Mở Chi tiết → \'Chỉnh…\' để đặt thứ trong tuần, ngày kết thúc — có lịch xem trước. Muốn dừng: Chi tiết → \'Dừng lặp lại\'.\n• Việc của bạn tự động lưu vào thư mục dữ liệu",
            None,
            Priority::P2,
            Some(t),
            Repeat::None,
            &["hướng-dẫn"],
            true,
            &[],
            false,
        );
        mk(
            &mut store,
            "Thử thêm việc nhanh: 'Mua cà phê ngày mai #cá- nhân !p1'",
            "Ô nhập ở trên cùng hiểu ngôn ngữ tự nhiên: ngày tháng, thẻ #, ưu tiên !p1–!p4. Lặp lại: gõ \'*hàng ngày\', \'*mỗi 3 ngày\', \'*mỗi 2 tuần\' (cũng hiểu *daily / *weekly / *mỗi 6 tháng / *mỗi 2 năm).",
            None,
            Priority::P4,
            Some(t),
            Repeat::None,
            &["thử"],
            false,
            &[],
            false,
        );
        mk(
            &mut store,
            "Lập kế hoạch tuần này",
            "Tổng hợp việc chưa xong rồi phân ưu tiên.",
            Some(list_ids[0]),
            Priority::P1,
            Some(t),
            Repeat::None,
            &["quan-trọng"],
            false,
            &[("Tổng hợp việc chưa xong", false), ("Phân ưu tiên P1–P4", false)],
            false,
        );
        mk(
            &mut store,
            "Tập thể dục 30 phút",
            "",
            Some(list_ids[1]),
            Priority::P3,
            Some(t),
            Repeat::None,
            &["sức-khỏe"],
            false,
            &[],
            false,
        );
        mk(
            &mut store,
            "Đọc 20 trang sách",
            "",
            Some(list_ids[2]),
            Priority::P4,
            Some(t),
            Repeat::None,
            &[],
            false,
            &[],
            false,
        );
        mk(
            &mut store,
            "Trả lời email quan trọng",
            "",
            Some(list_ids[0]),
            Priority::P2,
            Some(t),
            Repeat::None,
            &[],
            false,
            &[],
            true,
        );
        store
    }

    /// Thống kê nhanh.
    pub fn counts(&self, today: NaiveDate) -> Counts {
        let mut c = Counts::default();
        let today_key = today.format("%Y-%m-%d").to_string();
        let week_start = (today - TimeDelta::days(6)).format("%Y-%m-%d").to_string();
        for (day, n) in &self.focus_days {
            if *day == today_key {
                c.focus_today = *n as usize;
            }
            if day.as_str() >= week_start.as_str() && day.as_str() <= today_key.as_str() {
                c.focus_week += *n as usize;
            }
        }
        for t in &self.tasks {
            if t.is_deleted() {
                c.trash += 1;
                continue;
            }
            if t.is_completed() {
                c.completed += 1;
                if t.completed_at.map(|d| d.with_timezone(&Local).date_naive()) == Some(today) {
                    c.done_today += 1;
                }
                continue;
            }
            c.active += 1;
            match t.due {
                Some(d) if d < today => c.overdue += 1,
                _ => {}
            }
            if t.list_id.is_none() {
                c.inbox += 1;
            }
            if let Some(d) = t.due {
                if d <= today {
                    c.today += 1;
                } else {
                    c.upcoming += 1;
                }
            }
            if t.starred {
                c.starred += 1;
            }
        }
        for l in &self.lists {
            let n = self
                .tasks
                .iter()
                .filter(|t| t.is_active() && t.list_id == Some(l.id))
                .count();
            c.by_list.push((l.id, n));
        }
        c
    }

    /// Danh sách id việc hiển thị theo bộ lọc hiện tại (đã sắp xếp).
    pub fn visible(
        &self,
        view: &View,
        search: &str,
        sort: SortMode,
        hide_completed: bool,
        tag: Option<&str>,
        prio: Option<Priority>,
    ) -> Vec<TaskId> {
        let t = today();
        let q = search.trim().to_lowercase();
        let mut list: Vec<&Task> = self
            .tasks
            .iter()
            .filter(|task| match view {
                View::Inbox => task.is_active() && task.list_id.is_none(),
                View::Today => task.is_active() && task.due.map(|d| d <= t).unwrap_or(false),
                View::Upcoming => task.is_active() && task.due.map(|d| d > t).unwrap_or(false),
                View::Starred => task.is_active() && task.starred,
                View::Completed => !task.is_deleted() && task.is_completed(),
                View::Trash => task.is_deleted(),
                View::Stats => false,
                View::List(id) => task.is_active() && task.list_id == Some(*id),
            })
            .filter(|task| {
                if hide_completed && matches!(view, View::Inbox | View::Today | View::Upcoming | View::Starred | View::List(_)) {
                    !task.is_completed()
                } else {
                    true
                }
            })
            .filter(|task| task.matches_query(&q))
            .filter(|task| match tag {
                Some(tg) => task.tags.iter().any(|x| x == tg),
                None => true,
            })
            .filter(|task| match prio {
                Some(p) => task.priority == p,
                None => true,
            })
            .collect();
        list.sort_by(|a, b| cmp_tasks(a, b, sort).then(a.id.cmp(&b.id)));
        list.iter().map(|t| t.id).collect()
    }
}

fn cmp_tasks(a: &Task, b: &Task, sort: SortMode) -> std::cmp::Ordering {
    use std::cmp::Ordering;
    match sort {
        SortMode::Manual => a.order.cmp(&b.order),
        SortMode::Due => (a.due.is_none(), a.due, a.priority)
            .cmp(&(b.due.is_none(), b.due, b.priority))
            .then(a.order.cmp(&b.order)),
        SortMode::Priority => (a.priority, a.due, a.order).cmp(&(b.priority, b.due, b.order)),
        SortMode::Title => a
            .title
            .to_lowercase()
            .cmp(&b.title.to_lowercase())
            .then(a.order.cmp(&b.order)),
        SortMode::Created => b.created_at.cmp(&a.created_at),
    }
    .then(Ordering::Equal)
}

/// Trạng thái hạn chót để tô màu badge.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DueState {
    Overdue,
    Today,
    Tomorrow,
    Later,
    None,
}

pub fn due_state(due: Option<NaiveDate>, today: NaiveDate) -> DueState {
    match due {
        None => DueState::None,
        Some(d) if d < today => DueState::Overdue,
        Some(d) if d == today => DueState::Today,
        Some(d) if Some(d) == today.succ_opt() => DueState::Tomorrow,
        Some(_) => DueState::Later,
    }
}

/// Thứ tự weekday: 0 = Thứ Hai … 6 = Chủ Nhật → lấy ngày kế tiếp (hoặc hôm nay nếu trùng).
pub fn next_weekday(target_mon0: u32, from: NaiveDate, allow_today: bool) -> NaiveDate {
    let cur = from.weekday().num_days_from_monday();
    let mut delta = (target_mon0 as i64 - cur as i64).rem_euclid(7) as u32;
    if delta == 0 && !allow_today {
        delta = 7;
    }
    from.checked_add_signed(TimeDelta::days(delta as i64)).unwrap_or(from)
}

/// Chuyển tên thứ (EN/VN) → 0=Thứ Hai … 6=Chủ Nhật.
pub fn weekday_from_name(s: &str) -> Option<u32> {
    Some(match s {
        "monday" | "mon" | "thứ2" | "thứ 2" | "thứ hai" | "hai" => 0,
        "tuesday" | "tue" | "tues" | "thứ3" | "thứ 3" | "thứ ba" | "ba" => 1,
        "wednesday" | "wed" | "weds" | "thứ4" | "thứ 4" | "thứ tư" | "thứ tu" | "tư" | "tu" => 2,
        "thursday" | "thu" | "thur" | "thứ5" | "thứ 5" | "thứ năm" | "năm" => 3,
        "friday" | "fri" | "thứ6" | "thứ 6" | "thứ sáu" | "thứ sau" | "sáu" | "sau" => 4,
        "saturday" | "sat" | "thứ7" | "thứ 7" | "thứ bảy" | "thứ bay" | "bảy" | "bay" => 5,
        "sunday" | "sun" | "chủ nhật" | "chu nhat" | "cn" => 6,
        _ => return None,
    })
}

/// 1-based số thứ (2..7 → Thứ Hai..Chủ Nhật theo cách viết "thứ 2").
pub fn weekday_from_number(n: u32) -> Option<u32> {
    match n {
        2 => Some(0),
        3 => Some(1),
        4 => Some(2),
        5 => Some(3),
        6 => Some(4),
        7 => Some(5),
        1 | 8 => Some(6), // "thứ 1"/"thứ 8" ≈ Chủ Nhật (một số nơi dùng)
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seed_has_data() {
        let s = Store::seed();
        assert!(s.tasks.len() >= 5);
        assert_eq!(s.lists.len(), 3);
        assert!(s.next_id > s.tasks.len() as u64);
    }

    fn rule(freq: Freq, interval: u32, by_day: Option<u8>, month_day: Option<i8>, ends: EndSpec) -> RecurrenceRule {
        RecurrenceRule { freq, interval, by_day, month_day, ends }
    }

    fn d(y: i32, m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    // ---------- occurrence math: Day ----------
    #[test]
    fn rec_day_interval() {
        let r = rule(Freq::Day, 3, None, None, EndSpec::Never);
        assert_eq!(next_after(&r, d(2026, 11, 9)), Some(d(2026, 11, 12)));
        let r1 = rule(Freq::Day, 1, None, None, EndSpec::Never);
        assert_eq!(next_after(&r1, d(2026, 12, 31)), Some(d(2027, 1, 1)));
    }

    // ---------- Week không mask (trùng thứ) & interval ----------
    #[test]
    fn rec_week_no_mask() {
        let r = rule(Freq::Week, 2, None, None, EndSpec::Never);
        assert_eq!(next_after(&r, d(2026, 11, 9)), Some(d(2026, 11, 23)));
    }

    // ---------- Week mask {T2,T5}, interval 1 ----------
    #[test]
    fn rec_week_mask() {
        // bit0=T2 … bit6=CN; mask T2+T5 (bit0 + bit3) = 0b0001001
        let r = rule(Freq::Week, 1, Some(0b000_1001), None, EndSpec::Never);
        let mut cur = d(2026, 11, 9); // Thứ Hai
        let mut got = Vec::new();
        for _ in 0..4 {
            cur = next_after(&r, cur).unwrap();
            got.push(cur);
        }
        assert_eq!(got, vec![d(2026, 11, 12), d(2026, 11, 16), d(2026, 11, 19), d(2026, 11, 23)]);
    }

    // ---------- Week mask interval 2 (anchor vào tuần của due) ----------
    #[test]
    fn rec_week_mask_interval2() {
        // mask T2; due Thứ Hai 09/11/2026 (tuần chẵn anchor)
        let r = rule(Freq::Week, 2, Some(0b000_0001), None, EndSpec::Never);
        assert_eq!(next_after(&r, d(2026, 11, 9)), Some(d(2026, 11, 23)));
        assert_eq!(next_after(&r, d(2026, 11, 23)), Some(d(2026, 12, 7)));
        // mask T5 cùng anchor — trong tuần của due vẫn ra T5 (0 % 2 == 0)
        let r5 = rule(Freq::Week, 2, Some(0b000_1000), None, EndSpec::Never);
        assert_eq!(next_after(&r5, d(2026, 11, 9)), Some(d(2026, 11, 12)));
        assert_eq!(next_after(&r5, d(2026, 11, 12)), Some(d(2026, 11, 26)));
    }

    // ---------- Week mask 0 → không occurrence ----------
    #[test]
    fn rec_week_empty_mask_none() {
        let r = rule(Freq::Week, 1, Some(0), None, EndSpec::Never);
        assert_eq!(next_after(&r, d(2026, 11, 9)), None);
    }

    // ---------- Month anchor 31 (chống trôi 31/1→28/2→28/3) ----------
    #[test]
    fn rec_month_anchor31_no_drift() {
        let r = rule(Freq::Month, 1, None, Some(31), EndSpec::Never);
        let a = next_after(&r, d(2026, 1, 31)).unwrap();
        assert_eq!(a, d(2026, 2, 28));
        let b = next_after(&r, a).unwrap();
        assert_eq!(b, d(2026, 3, 31)); // KHÔNG trôi về 28/3
        let c = next_after(&r, b).unwrap();
        assert_eq!(c, d(2026, 4, 30));
    }

    // ---------- Month anchor -1 (ngày cuối) ----------
    #[test]
    fn rec_month_anchor_last_day() {
        let r = rule(Freq::Month, 1, None, Some(-1), EndSpec::Never);
        assert_eq!(next_after(&r, d(2026, 1, 31)), Some(d(2026, 2, 28)));
        assert_eq!(next_after(&r, d(2026, 2, 28)), Some(d(2026, 3, 31)));
        assert_eq!(next_after(&r, d(2026, 3, 31)), Some(d(2026, 4, 30)));
    }

    // ---------- Month anchor 30 trong tháng 2 ----------
    #[test]
    fn rec_month_anchor30_february() {
        let r = rule(Freq::Month, 1, None, Some(30), EndSpec::Never);
        assert_eq!(next_after(&r, d(2026, 1, 30)), Some(d(2026, 2, 28)));
        assert_eq!(next_after(&r, d(2026, 2, 28)), Some(d(2026, 3, 30)));
    }

    // ---------- Month interval 3 ----------
    #[test]
    fn rec_month_interval3() {
        let r = rule(Freq::Month, 3, None, Some(15), EndSpec::Never);
        assert_eq!(next_after(&r, d(2026, 11, 15)), Some(d(2027, 2, 15)));
        assert_eq!(next_after(&r, d(2026, 12, 15)), Some(d(2027, 3, 15)));
    }

    // ---------- Year: 29/2 → 28/2 năm thường → 29/2 năm nhuận ----------
    #[test]
    fn rec_year_leap() {
        let r = rule(Freq::Year, 1, None, Some(29), EndSpec::Never);
        let from = d(2028, 2, 29);
        assert_eq!(next_after(&r, from), Some(d(2029, 2, 28)));
        assert_eq!(next_after(&r, d(2029, 2, 28)), Some(d(2030, 2, 28)));
        assert_eq!(next_after(&r, d(2031, 2, 28)), Some(d(2032, 2, 29)));
        // anchor = ngày thường
        let r2 = rule(Freq::Year, 2, None, Some(15), EndSpec::Never);
        assert_eq!(next_after(&r2, d(2026, 8, 15)), Some(d(2028, 8, 15)));
    }

    // ---------- Until: đúng ngày OK, sau 1 ngày hết ----------
    #[test]
    fn rec_until_boundary() {
        let r = rule(Freq::Day, 1, None, None, EndSpec::Until { date: d(2026, 11, 12) });
        assert_eq!(next_after(&r, d(2026, 11, 11)), Some(d(2026, 11, 12)));
        assert_eq!(next_after(&r, d(2026, 11, 12)), None);
    }

    // ---------- After: trần total/done ----------
    #[test]
    fn rec_after_cap() {
        let r = rule(Freq::Day, 1, None, None, EndSpec::After { total: 3, done: 3 });
        assert_eq!(next_after(&r, d(2026, 11, 9)), None);
        let r2 = rule(Freq::Day, 1, None, None, EndSpec::After { total: 3, done: 2 });
        assert_eq!(next_after(&r2, d(2026, 11, 9)), Some(d(2026, 11, 10)));
        // occurrences_after chỉ sinh (total - done - 1) bản sao sau lần hiện tại
        let occ = occurrences_after(&r2, d(2026, 11, 9), 200);
        assert_eq!(occ.len(), 0);
        let r3 = rule(Freq::Day, 1, None, None, EndSpec::After { total: 5, done: 1 });
        let occ3 = occurrences_after(&r3, d(2026, 11, 9), 200);
        assert_eq!(occ3.len(), 3); // 11, 12, 13 — lần hiện tại (9) không tính
    }

    // ---------- validate ----------
    #[test]
    fn rec_validate_week_needs_mask() {
        let bad = rule(Freq::Week, 1, None, None, EndSpec::Never);
        // Week không mask = hợp lệ (trùng thứ); Week mask rỗng = lỗi
        assert!(bad.validate().is_ok());
        let bad2 = rule(Freq::Week, 1, Some(0), None, EndSpec::Never);
        assert!(bad2.validate().is_err());
        let bad3 = rule(Freq::Month, 1, None, None, EndSpec::Until { date: d(2020, 1, 1) });
        assert!(bad3.validate().is_err());
    }

    // ---------- shadow ----------
    #[test]
    fn rec_shadow_mapping() {
        assert_eq!(rule(Freq::Day, 1, None, None, EndSpec::Never).shadow(), Repeat::Daily);
        assert_eq!(rule(Freq::Day, 1, Some(0b001_1111), None, EndSpec::Never).shadow(), Repeat::Weekdays);
        assert_eq!(rule(Freq::Week, 1, None, None, EndSpec::Never).shadow(), Repeat::Weekly);
        assert_eq!(rule(Freq::Month, 1, None, Some(15), EndSpec::Never).shadow(), Repeat::Monthly);
        assert_eq!(rule(Freq::Day, 3, None, None, EndSpec::Never).shadow(), Repeat::None);
        assert_eq!(rule(Freq::Day, 1, None, None, EndSpec::Until { date: d(2030, 1, 1) }).shadow(), Repeat::None);
        assert_eq!(rule(Freq::Year, 1, None, Some(1), EndSpec::Never).shadow(), Repeat::None);
    }

    // ---------- sanitize: upgrade legacy + freeze + shadow ----------
    #[test]
    fn rec_sanitize_upgrades_legacy() {
        let mut s = Store::default();
        let t = today();
        let task = Task {
            id: 1,
            title: "Tập gym".into(),
            notes: String::new(),
            list_id: None,
            priority: Priority::P4,
            due: Some(d(2026, 1, 31)),
            repeat: Repeat::Monthly,
            recurrence: None,
            tags: vec![],
            subtasks: vec![],
            starred: false,
            order: 1,
            created_at: Utc::now(),
            completed_at: None,
            deleted_at: None,
        };
        s.tasks.push(task);
        s.next_id = 2;
        s.sanitize();
        let got = &s.tasks[0].recurrence.clone().unwrap();
        assert_eq!(got.freq, Freq::Month);
        assert_eq!(got.month_day, Some(31)); // anchor đóng băng từ due
        assert_eq!(s.tasks[0].repeat, Repeat::Monthly); // shadow giữ nguyên (đơn)
        let _ = t;
    }

    #[test]
    fn rec_sanitize_custom_shadow_none() {
        let mut s = Store::default();
        let task = Task {
            id: 1,
            title: "X".into(),
            notes: String::new(),
            list_id: None,
            priority: Priority::P4,
            due: Some(d(2026, 11, 9)),
            repeat: Repeat::None,
            recurrence: Some(rule(Freq::Day, 3, None, None, EndSpec::Never)),
            tags: vec![],
            subtasks: vec![],
            starred: false,
            order: 1,
            created_at: Utc::now(),
            completed_at: None,
            deleted_at: None,
        };
        s.tasks.push(task);
        s.next_id = 2;
        s.sanitize();
        assert_eq!(s.tasks[0].repeat, Repeat::None); // downgrade an toàn
    }

    // ---------- sanitize: rule hết hạn trên việc CHƯA xong → việc thường + note ----------
    #[test]
    fn rec_sanitize_strips_exhausted() {
        let mut s = Store::default();
        let task = Task {
            id: 1,
            title: "Sắp hết hạn".into(),
            notes: String::new(),
            list_id: None,
            priority: Priority::P4,
            due: Some(d(2026, 11, 1)),
            repeat: Repeat::None,
            recurrence: Some(rule(Freq::Day, 1, None, None, EndSpec::Until { date: d(2026, 11, 5) })),
            tags: vec![],
            subtasks: vec![],
            starred: false,
            order: 1,
            created_at: Utc::now(),
            completed_at: None,
            deleted_at: None,
        };
        s.tasks.push(task);
        s.next_id = 2;
        s.sanitize();
        assert!(s.tasks[0].recurrence.is_none());
        assert_eq!(s.tasks[0].repeat, Repeat::None);
        assert_eq!(s.sanitize_notes, vec!["Sắp hết hạn".to_string()]);
    }

    // ---------- until = đúng hôm nay vẫn giữ (việc hôm nay) ----------
    #[test]
    fn rec_sanitize_until_today_strips_to_plain() {
        let mut s = Store::default();
        let tdy = today();
        let task = Task {
            id: 1,
            title: "Hôm nay còn".into(),
            notes: String::new(),
            list_id: None,
            priority: Priority::P4,
            due: Some(tdy),
            repeat: Repeat::None,
            recurrence: Some(rule(Freq::Day, 1, None, None, EndSpec::Until { date: tdy })),
            tags: vec![],
            subtasks: vec![],
            starred: false,
            order: 1,
            created_at: Utc::now(),
            completed_at: None,
            deleted_at: None,
        };
        s.tasks.push(task);
        s.next_id = 2;
        s.sanitize();
        // from == until == today: occurrence kế tiếp (> from) đã vượt until → gỡ rule.
        // Bản thân việc (due = hôm nay) vẫn hiện trong Hôm nay như việc thường — đúng luật.
        assert!(s.tasks[0].recurrence.is_none());
    }

        #[test]
    fn repeat_daily_next() {
        let d = NaiveDate::from_ymd_opt(2026, 11, 9).unwrap();
        assert_eq!(
            Repeat::Daily.next_after(d),
            NaiveDate::from_ymd_opt(2026, 11, 10)
        );
        assert_eq!(
            Repeat::Weekly.next_after(d),
            NaiveDate::from_ymd_opt(2026, 11, 16)
        );
        // 31/1 + 1 tháng = 28/2 (năm 2026 không nhuận)
        let d2 = NaiveDate::from_ymd_opt(2026, 1, 31).unwrap();
        assert_eq!(
            Repeat::Monthly.next_after(d2),
            NaiveDate::from_ymd_opt(2026, 2, 28)
        );
    }

    #[test]
    fn weekdays_skip_weekend() {
        // 2026-11-06 là Thứ Sáu → lần kế tiếp trong tuần = Thứ Hai 09
        let fri = NaiveDate::from_ymd_opt(2026, 11, 6).unwrap();
        assert_eq!(fri.weekday().num_days_from_monday(), 4);
        assert_eq!(
            Repeat::Weekdays.next_after(fri),
            NaiveDate::from_ymd_opt(2026, 11, 9)
        );
        // Thứ Hai → Thứ Ba
        let mon = NaiveDate::from_ymd_opt(2026, 11, 9).unwrap();
        assert_eq!(
            Repeat::Weekdays.next_after(mon),
            NaiveDate::from_ymd_opt(2026, 11, 10)
        );
        // Thứ Bảy → Thứ Hai
        let sat = NaiveDate::from_ymd_opt(2026, 11, 7).unwrap();
        assert_eq!(sat.weekday().num_days_from_monday(), 5);
        assert_eq!(
            Repeat::Weekdays.next_after(sat),
            NaiveDate::from_ymd_opt(2026, 11, 9)
        );
    }

    #[test]
    fn visible_filters_and_sorts() {
        let mut s = Store::seed();
        let t = today();
        let ids = s.visible(&View::Today, "", SortMode::Due, true, None, None);
        assert!(!ids.is_empty());
        // tìm kiếm
        let hit = s.visible(&View::Inbox, "chào", SortMode::Title, true, None, None);
        assert_eq!(hit.len(), 1);
        // ẩn đã hoàn thành
        s.tasks[0].completed_at = Some(Utc::now());
        let inbox = s.visible(&View::Inbox, "", SortMode::Manual, true, None, None);
        assert!(!inbox.contains(&s.tasks[0].id));
        // tag
        let tagged = s.visible(&View::Inbox, "", SortMode::Manual, false, Some("hướng-dẫn"), None);
        assert!(tagged.iter().all(|id| {
            s.tasks
                .iter()
                .find(|x| x.id == *id)
                .unwrap()
                .tags
                .contains(&"hướng-dẫn".to_string())
        }));
        let _ = t;
    }

    #[test]
    fn due_state_colors() {
        let t = NaiveDate::from_ymd_opt(2026, 11, 9).unwrap();
        assert_eq!(
            due_state(Some(NaiveDate::from_ymd_opt(2026, 11, 8).unwrap()), t),
            DueState::Overdue
        );
        assert_eq!(due_state(Some(t), t), DueState::Today);
        assert_eq!(
            due_state(Some(t.succ_opt().unwrap()), t),
            DueState::Tomorrow
        );
        assert_eq!(due_state(None, t), DueState::None);
    }

    #[test]
    fn serde_roundtrip() {
        let s = Store::seed();
        let json = serde_json::to_string(&s).unwrap();
        let back: Store = serde_json::from_str(&json).unwrap();
        assert_eq!(s, back);
    }

    #[test]
    fn weekday_helpers() {
        assert_eq!(weekday_from_name("monday"), Some(0));
        assert_eq!(weekday_from_name("chủ nhật"), Some(6));
        assert_eq!(weekday_from_number(2), Some(0));
        let mon = NaiveDate::from_ymd_opt(2026, 11, 9).unwrap();
        // "thứ 6" từ Thứ Hai → Thứ Sáu (+4)
        assert_eq!(
            next_weekday(4, mon, true),
            NaiveDate::from_ymd_opt(2026, 11, 13).unwrap()
        );
        // "monday" khi đang là Monday, không cho hôm nay → tuần sau
        assert_eq!(
            next_weekday(0, mon, false),
            NaiveDate::from_ymd_opt(2026, 11, 16).unwrap()
        );
    }

    #[test]
    fn weekday_name_vn() {
        let mon = NaiveDate::from_ymd_opt(2026, 11, 9).unwrap();
        assert_eq!(weekday_name(mon), "Thứ Hai");
        assert_eq!(weekday_name(mon.succ_opt().unwrap()), "Thứ Ba");
    }
}
