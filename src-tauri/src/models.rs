//! Mô hình dữ liệu cốt lõi: Task, List, Store, View và các tiện ích ngày tháng.

use chrono::{DateTime, Datelike, Local, Months, NaiveDate, TimeDelta, Utc};
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
        }
    }
}

impl Store {
    pub fn new_id(&mut self) -> TaskId {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    /// Sửa dữ liệu sau khi nạp từ đĩa (hợp lệ hóa id, danh sách mồ côi...).
    pub fn sanitize(&mut self) {
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
            });
        };
        mk(
            &mut store,
            "Chào mừng bạn đến với Taskora 👋",
            "Đây là ứng dụng quản lý công việc được viết bằng Rust.\n\n• Bấm vòng tròn để hoàn thành việc\n• Chuột phải để mở menu nhanh\n• Ctrl+N thêm việc · Ctrl+F tìm kiếm · Ctrl+D đổi giao diện\n• Việc của bạn tự động lưu vào thư mục dữ liệu",
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
            "Ô nhập ở trên cùng hiểu ngôn ngữ tự nhiên: ngày tháng, thẻ #, ưu tiên !p1–!p4 và lặp lại *daily/*weekly.",
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
            Repeat::Daily,
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
