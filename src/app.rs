//! `TaskoraApp`: trạng thái ứng dụng, vòng lặp update, phím tắt, hành động, lưu tự động.

use std::time::{Duration, Instant};

use chrono::{Local, NaiveDate};
use eframe::egui::{self, Align, Key, Layout, RichText};

use crate::models::{today, Priority, Repeat, SortMode, Store, SubTask, Task, TaskId, View};
use crate::parser;
use crate::storage;
use crate::ui::{icons, theme};

/// Bảng màu danh sách cho hộp thoại tạo/đổi tên danh sách.
pub const LIST_PALETTE: [[u8; 3]; 8] = [
    [99, 102, 241],
    [16, 185, 129],
    [245, 158, 11],
    [239, 68, 68],
    [14, 165, 233],
    [168, 85, 247],
    [236, 72, 153],
    [107, 114, 128],
];

/// Hộp thoại tạo / đổi tên danh sách.
#[derive(Debug, Clone)]
pub struct ListDialog {
    /// `Some(id)` = chế độ đổi tên.
    pub editing: Option<TaskId>,
    pub name: String,
    pub color_idx: usize,
}

/// Hành động gom lại trong lúc render rồi áp dụng sau (tránh mâu thuẫn mượn ngữ cảnh).
#[derive(Debug, Clone)]
pub enum Act {
    Select(TaskId),
    Toggle(TaskId),
    Star(TaskId),
    Delete(TaskId),
    Restore(TaskId),
    Purge(TaskId),
    Duplicate(TaskId),
    MoveUp(TaskId),
    MoveDown(TaskId),
    MoveToList(TaskId, Option<TaskId>),
    Drop {
        src: TaskId,
        dst: TaskId,
        before: bool,
    },
    AddSubtask(TaskId),
    ClearCompleted,
    FilterTag(String),
    SetDue(TaskId, Option<NaiveDate>),
    SetPriority(TaskId, Priority),
    PurgeAllTrash,
    DeferOverdue(NaiveDate),
}

/// Trạng thái phím tắt (tính trong một lần đọc input).
struct Sc {
    ctrl_n: bool,
    ctrl_f: bool,
    ctrl_k: bool,
    ctrl_d: bool,
    ctrl_z: bool,
    ctrl_y: bool,
    v1: bool,
    v2: bool,
    v3: bool,
    v4: bool,
    v5: bool,
    v6: bool,
    space: bool,
    del: bool,
    esc: bool,
    up: bool,
    down: bool,
    alt_up: bool,
    alt_down: bool,
}

pub struct TaskoraApp {
    pub store: Store,
    pub view: View,
    pub selected: Option<TaskId>,
    pub search: String,
    pub quick_add: String,
    pub tag_filter: Option<String>,
    pub prio_filter: Option<crate::models::Priority>,

    pub focus_quick: bool,
    pub focus_search: bool,

    // lịch chọn ngày
    pub show_cal: bool,
    pub cal_y: i32,
    pub cal_m: u32,

    // bộ đệm thẻ trong panel chi tiết
    pub tag_for: Option<TaskId>,
    pub tag_buf: String,

    // hộp thoại
    pub list_dialog: Option<ListDialog>,
    pub help_open: bool,
    pub import_open: bool,
    pub import_sel: usize,
    pub import_path: String,
    pub import_err: Option<String>,
    pub export_msg: Option<String>,
    pub backups: Vec<std::path::PathBuf>,

    // undo/redo
    pub undo_stack: Vec<Store>,
    pub redo_stack: Vec<Store>,

    // lưu tự động
    pub last_json: String,
    pub dirty: bool,
    pub last_save: Option<Instant>,
    pub saved_label: String,
    pub flash: Option<(String, Instant)>,
    /// Bộ đệm tiêu đề cửa sổ (tránh gửi ViewportCommand mỗi frame).
    pub title_cache: String,
    /// ID việc cần cuộn vào khung nhìn (set khi Select, dọn sau khi render).
    pub scroll_to: Option<crate::models::TaskId>,
    /// Thời điểm chuyển view gần nhất — hiệu ứng fade/slide khi vào trang.
    pub view_entered: Instant,
    /// Rect của row sidebar đang chọn (tọa độ nội dung) — để thanh accent trượt.
    pub sidebar_sel_rect: Option<egui::Rect>,
    /// Pulse xanh lá khi vừa đánh dấu xong: (id việc, thời điểm).
    pub done_pulse: Option<(TaskId, Instant)>,
    /// Thời điểm khởi động — làm mốc cho shimmer lặp.
    pub boot: Instant,
}

impl TaskoraApp {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let store = storage::load();
        let dark = store.settings.dark;
        theme::install(&cc.egui_ctx, dark);
        let last_json = serde_json::to_string(&store).unwrap_or_default();
        Self {
            store,
            view: View::Inbox,
            selected: None,
            search: String::new(),
            quick_add: String::new(),
            tag_filter: None,
            prio_filter: None,
            focus_quick: false,
            focus_search: false,
            show_cal: false,
            cal_y: 0,
            cal_m: 1,
            tag_for: None,
            tag_buf: String::new(),
            list_dialog: None,
            help_open: false,
            import_open: false,
            import_sel: 0,
            import_path: String::new(),
            import_err: None,
            export_msg: None,
            backups: Vec::new(),
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            last_json,
            dirty: false,
            last_save: None,
            saved_label: "—".to_string(),
            flash: None,
            title_cache: String::new(),
            scroll_to: None,
            view_entered: Instant::now(),
            sidebar_sel_rect: None,
            done_pulse: None,
            boot: Instant::now(),
        }
    }

    // ------------------------------------------------------------------ chung

    pub fn flash(&mut self, msg: impl Into<String>) {
        self.flash = Some((msg.into(), Instant::now()));
    }

    pub fn push_undo(&mut self) {
        self.undo_stack.push(self.store.clone());
        if self.undo_stack.len() > 80 {
            self.undo_stack.remove(0);
        }
        self.redo_stack.clear();
    }

    pub fn undo(&mut self) {
        if let Some(prev) = self.undo_stack.pop() {
            self.redo_stack.push(self.store.clone());
            self.store = prev;
            self.keep_selection_valid();
            self.flash("Đã hoàn tác");
        }
    }

    pub fn redo(&mut self) {
        if let Some(next) = self.redo_stack.pop() {
            self.undo_stack.push(self.store.clone());
            self.store = next;
            self.keep_selection_valid();
            self.flash("Đã làm lại");
        }
    }

    pub fn keep_selection_valid(&mut self) {
        if let Some(id) = self.selected {
            if !self.store.tasks.iter().any(|t| t.id == id) {
                self.selected = None;
            }
        }
        if let View::List(id) = self.view {
            if !self.store.lists.iter().any(|l| l.id == id) {
                self.view = View::Inbox;
                self.view_entered = Instant::now();
            }
        }
    }

    // ------------------------------------------------------------------ actions

    pub fn apply(&mut self, act: Act) {
        match act {
            Act::Select(id) => {
                self.selected = Some(id);
                self.scroll_to = Some(id);
            }
            Act::Toggle(id) => self.toggle_done(id),
            Act::Star(id) => {
                if let Some(t) = self.store.tasks.iter_mut().find(|t| t.id == id) {
                    t.starred = !t.starred;
                }
            }
            Act::Delete(id) => self.delete_task(id),
            Act::Restore(id) => {
                self.push_undo();
                if let Some(t) = self.store.tasks.iter_mut().find(|t| t.id == id) {
                    t.deleted_at = None;
                    t.completed_at = None;
                }
                self.flash("Đã khôi phục việc");
            }
            Act::Purge(id) => {
                self.push_undo();
                self.store.tasks.retain(|t| t.id != id);
                if self.selected == Some(id) {
                    self.selected = None;
                }
                self.flash("Đã xóa vĩnh viễn");
            }
            Act::Duplicate(id) => self.duplicate_task(id),
            Act::MoveUp(id) => self.shift_task(id, true),
            Act::MoveDown(id) => self.shift_task(id, false),
            Act::MoveToList(id, list) => {
                self.push_undo();
                if let Some(t) = self.store.tasks.iter_mut().find(|t| t.id == id) {
                    t.list_id = list;
                }
                self.flash("Đã chuyển việc");
            }
            Act::Drop { src, dst, before } => self.drop_task(src, dst, before),
            Act::AddSubtask(id) => {
                self.push_undo();
                let sid = self.store.new_id();
                if let Some(t) = self.store.tasks.iter_mut().find(|t| t.id == id) {
                    t.subtasks.push(SubTask {
                        id: sid,
                        title: String::new(),
                        done: false,
                    });
                }
            }
            Act::FilterTag(tag) => {
                let already = self.tag_filter.as_deref() == Some(tag.as_str());
                self.tag_filter = if already { None } else { Some(tag.clone()) };
                self.flash(match &self.tag_filter {
                    Some(_) => format!("Đang lọc thẻ #{tag}"),
                    None => "Đã bỏ lọc thẻ".to_string(),
                });
            }
            Act::ClearCompleted => {
                self.push_undo();
                let before = self.store.tasks.len();
                self.store
                    .tasks
                    .retain(|t| !(t.is_completed() && !t.is_deleted()));
                let n = before - self.store.tasks.len();
                self.keep_selection_valid();
                self.flash(format!("Đã xóa {n} việc hoàn thành"));
            }
            Act::SetDue(id, due) => {
                self.push_undo();
                if let Some(t) = self.store.tasks.iter_mut().find(|t| t.id == id) {
                    t.due = due;
                }
                self.flash(match due {
                    Some(d) => format!("Hạn chót: {}", d.format("%d/%m/%Y")),
                    None => "Đã bỏ hạn chót".to_string(),
                });
            }
            Act::SetPriority(id, p) => {
                self.push_undo();
                if let Some(t) = self.store.tasks.iter_mut().find(|t| t.id == id) {
                    t.priority = p;
                }
                self.flash(format!("Ưu tiên: {}", p.label()));
            }
            Act::PurgeAllTrash => {
                let n = self.store.tasks.iter().filter(|t| t.is_deleted()).count();
                if n == 0 {
                    self.flash("Thùng rác đã trống");
                    return;
                }
                self.push_undo();
                self.store.tasks.retain(|t| !t.is_deleted());
                self.keep_selection_valid();
                self.flash(format!("Đã xóa vĩnh viễn {n} việc trong thùng rác"));
            }
            Act::DeferOverdue(target) => {
                let t = today();
                let n = self
                    .store
                    .tasks
                    .iter()
                    .filter(|x| x.is_active() && x.due.map(|d| d < t).unwrap_or(false))
                    .count();
                if n == 0 {
                    self.flash("Không có việc quá hạn nào");
                    return;
                }
                self.push_undo();
                for task in self
                    .store
                    .tasks
                    .iter_mut()
                    .filter(|x| x.is_active() && x.due.map(|d| d < t).unwrap_or(false))
                {
                    task.due = Some(target);
                }
                self.flash(format!(
                    "Đã đổi hạn {} việc quá hạn → {}",
                    n,
                    target.format("%d/%m/%Y")
                ));
            }
        }
    }

    /// Bật/tắt hoàn thành; việc lặp lại sẽ tạo lần kế tiếp.
    pub fn toggle_done(&mut self, id: TaskId) {
        self.push_undo();
        let Some(idx) = self.store.tasks.iter().position(|t| t.id == id) else {
            return;
        };
        let was_done = self.store.tasks[idx].completed_at.is_some();
        self.done_pulse = Some((id, Instant::now()));
        if was_done {
            self.store.tasks[idx].completed_at = None;
            return;
        }
        let snap = self.store.tasks[idx].clone();
        self.store.tasks[idx].completed_at = Some(chrono::Utc::now());
        if snap.repeat != Repeat::None {
            let base = snap.due.unwrap_or_else(today);
            if let Some(next) = snap.repeat.next_after(base) {
                let mut nt = snap;
                nt.id = self.store.new_id();
                nt.due = Some(next);
                nt.completed_at = None;
                nt.deleted_at = None;
                nt.created_at = chrono::Utc::now();
                nt.starred = false;
                for s in &mut nt.subtasks {
                    s.done = false;
                }
                nt.order = self.store.tasks[idx].order.saturating_add(1);
                self.store.tasks.push(nt);
                self.flash(format!("Lặp lại: hẹn gặp {}", next.format("%d/%m/%Y")));
            }
        }
    }

    pub fn delete_task(&mut self, id: TaskId) {
        if self.view == View::Trash {
            self.apply(Act::Purge(id));
            return;
        }
        self.push_undo();
        if let Some(t) = self.store.tasks.iter_mut().find(|t| t.id == id) {
            t.deleted_at = Some(chrono::Utc::now());
        }
        if self.selected == Some(id) {
            self.selected = None;
        }
        self.flash("Đã chuyển vào thùng rác (Ctrl+Z hoàn tác)");
    }

    pub fn duplicate_task(&mut self, id: TaskId) {
        self.push_undo();
        let Some(idx) = self.store.tasks.iter().position(|t| t.id == id) else {
            return;
        };
        let mut nt = self.store.tasks[idx].clone();
        nt.id = self.store.new_id();
        nt.title = format!("{} (bản sao)", nt.title);
        nt.completed_at = None;
        nt.deleted_at = None;
        nt.created_at = chrono::Utc::now();
        for s in &mut nt.subtasks {
            s.id = self.store.new_id();
            s.done = false;
        }
        nt.order = self.store.tasks[idx].order;
        let insert_at = idx + 1;
        self.store.tasks.insert(insert_at, nt);
        self.flash("Đã nhân bản việc");
    }

    /// Sắp xếp: lấy thứ tự hiện tại của view, đổi vị trí, ghi lại `order`.
    fn reorder_with(&mut self, f: impl FnOnce(&mut Vec<TaskId>)) {
        let view = self.view;
        let search = self.search.clone();
        let sort = self.store.settings.sort;
        let hide = self.store.settings.hide_completed;
        let tag = self.tag_filter.clone();
        let mut vis = self.store.visible(&view, &search, sort, hide, tag.as_deref(), self.prio_filter);
        f(&mut vis);
        for (i, id) in vis.iter().enumerate() {
            if let Some(t) = self.store.tasks.iter_mut().find(|t| t.id == *id) {
                t.order = i as u32;
            }
        }
    }

    fn shift_task(&mut self, id: TaskId, up: bool) {
        if self.store.settings.sort != SortMode::Manual {
            self.flash("Chỉ sắp xếp được khi chọn thứ tự Thủ công");
            return;
        }
        self.push_undo();
        self.reorder_with(|vis| {
            if let Some(i) = vis.iter().position(|&x| x == id) {
                if up && i > 0 {
                    vis.swap(i, i - 1);
                } else if !up && i + 1 < vis.len() {
                    vis.swap(i, i + 1);
                }
            }
        });
    }

    fn drop_task(&mut self, src: TaskId, dst: TaskId, before: bool) {
        if self.store.settings.sort != SortMode::Manual || src == dst {
            return;
        }
        self.push_undo();
        self.reorder_with(|vis| {
            if let Some(si) = vis.iter().position(|&x| x == src) {
                let item = vis.remove(si);
                if let Some(di) = vis.iter().position(|&x| x == dst) {
                    let at = if before { di } else { di + 1 };
                    vis.insert(at, item);
                } else {
                    vis.insert(si, item);
                }
            }
        });
        self.flash("Đã đổi thứ tự");
    }

    /// Thêm việc từ ô nhanh (đã phân tích xong).
    pub fn submit_quick(&mut self) {
        let input = self.quick_add.clone();
        if input.trim().is_empty() {
            return;
        }
        let p = parser::parse(&input, today());
        if p.title.trim().is_empty() {
            self.flash("Không nhận diện được nội dung việc cần làm");
            return;
        }
        self.push_undo();
        let mut due = p.due;
        let mut list_id = None;
        let mut starred = false;
        match self.view {
            View::Today => {
                due.get_or_insert_with(today);
            }
            View::Upcoming => {
                let t = today();
                due.get_or_insert_with(|| t.succ_opt().unwrap_or(t));
            }
            View::Starred => starred = true,
            View::List(id) => list_id = Some(id),
            _ => {}
        }
        let order = self
            .store
            .tasks
            .iter()
            .filter(|t| t.list_id == list_id)
            .map(|t| t.order)
            .min()
            .unwrap_or(0);
        let id = self.store.new_id();
        self.store.tasks.insert(
            0,
            Task {
                id,
                title: p.title,
                notes: String::new(),
                list_id,
                priority: p.priority.unwrap_or_default(),
                due,
                repeat: p.repeat.unwrap_or(Repeat::None),
                tags: p.tags,
                subtasks: Vec::new(),
                starred,
                order: order.saturating_sub(0),
                created_at: chrono::Utc::now(),
                completed_at: None,
                deleted_at: None,
            },
        );
        self.quick_add.clear();
        self.selected = Some(id);
        self.flash("Đã thêm việc ✓");
    }

    pub fn clear_completed(&mut self) {
        self.apply(Act::ClearCompleted);
    }

    pub fn toggle_theme(&mut self, ctx: &egui::Context) {
        self.store.settings.dark = !self.store.settings.dark;
        theme::set_active_theme(ctx, self.store.settings.dark);
        self.flash(if self.store.settings.dark {
            "Đã bật giao diện tối"
        } else {
            "Đã bật giao diện sáng"
        });
    }

    pub fn set_view(&mut self, v: View) {
        if self.view != v {
            self.view = v;
            self.view_entered = Instant::now();
        }
        self.selected = None;
        self.tag_filter = None;
        self.prio_filter = None;
        self.show_cal = false;
    }

    /// Đầu frame chuyển trang: trả progress 0..1 (1 = xong), thêm lề trượt nhẹ.
    pub(crate) fn view_enter_head(&self, ui: &mut egui::Ui) -> (f32, egui::Rect) {
        let vr = ui.available_rect_before_wrap();
        let p = (self.view_entered.elapsed().as_secs_f32() / 0.20).clamp(0.0, 1.0);
        if p < 1.0 {
            ui.add_space((14.0 * (1.0 - p)).round());
        }
        (p, vr)
    }

    /// Cuối frame chuyển trang: lớp phủ cùng màu nền đang dần trong suốt (fade-in).
    pub(crate) fn view_enter_fade(&self, ui: &egui::Ui, p: f32, vr: egui::Rect) {
        if p < 1.0 {
            let [r, g, b, _] = ui.visuals().panel_fill.to_array();
            let a = ((1.0 - p) * 215.0).round() as u8;
            ui.painter().rect_filled(
                vr,
                egui::CornerRadius::ZERO,
                egui::Color32::from_rgba_unmultiplied(r, g, b, a),
            );
        }
    }

    // ------------------------------------------------------------------ phím tắt

    fn handle_shortcuts(&mut self, ctx: &egui::Context) {
        let typing = ctx.wants_keyboard_input();
        let sc = ctx.input(|i| Sc {
            ctrl_n: i.key_pressed(Key::N) && i.modifiers.command,
            ctrl_f: i.key_pressed(Key::F) && i.modifiers.command,
            ctrl_k: i.key_pressed(Key::K) && i.modifiers.command,
            ctrl_d: i.key_pressed(Key::D) && i.modifiers.command,
            ctrl_z: i.key_pressed(Key::Z) && i.modifiers.command,
            ctrl_y: i.key_pressed(Key::Y) && i.modifiers.command,
            v1: i.key_pressed(Key::Num1) && i.modifiers.command,
            v2: i.key_pressed(Key::Num2) && i.modifiers.command,
            v3: i.key_pressed(Key::Num3) && i.modifiers.command,
            v4: i.key_pressed(Key::Num4) && i.modifiers.command,
            v5: i.key_pressed(Key::Num5) && i.modifiers.command,
            v6: i.key_pressed(Key::Num6) && i.modifiers.command,
            space: i.key_pressed(Key::Space) && !typing,
            del: i.key_pressed(Key::Delete) && !typing,
            esc: i.key_pressed(Key::Escape),
            up: i.key_pressed(Key::ArrowUp) && !typing,
            down: i.key_pressed(Key::ArrowDown) && !typing,
            alt_up: i.key_pressed(Key::ArrowUp) && i.modifiers.alt && !typing,
            alt_down: i.key_pressed(Key::ArrowDown) && i.modifiers.alt && !typing,
        });

        if sc.ctrl_n {
            if !self.view.allows_quick_add() {
                self.set_view(View::Inbox);
            }
            self.focus_quick = true;
        }
        if sc.ctrl_f || sc.ctrl_k {
            self.focus_search = true;
        }
        if sc.ctrl_d {
            self.toggle_theme(ctx);
        }
        if !typing && (sc.ctrl_z || sc.ctrl_y) {
            let shift = ctx.input(|i| i.modifiers.shift);
            if sc.ctrl_y || shift {
                self.redo();
            } else {
                self.undo();
            }
        }
        if sc.v1 {
            self.set_view(View::Inbox);
        }
        if sc.v2 {
            self.set_view(View::Today);
        }
        if sc.v3 {
            self.set_view(View::Upcoming);
        }
        if sc.v4 {
            self.set_view(View::Starred);
        }
        if sc.v5 {
            self.set_view(View::Completed);
        }
        if sc.v6 {
            self.set_view(View::Trash);
        }

        if sc.esc {
            if self.show_cal {
                self.show_cal = false;
            } else if self.list_dialog.is_some() {
                self.list_dialog = None;
            } else if self.help_open || self.import_open || self.export_msg.is_some() {
                self.help_open = false;
                self.import_open = false;
                self.export_msg = None;
            } else if !typing {
                if self.tag_filter.is_some() || self.prio_filter.is_some() {
                    self.tag_filter = None;
                    self.prio_filter = None;
                    self.flash("Đã bỏ bộ lọc");
                } else if self.selected.is_some() {
                    self.selected = None;
                }
            }
        }

        // Di chuyển lựa chọn / chuyển việc
        if sc.up || sc.down || sc.alt_up || sc.alt_down {
            if let Some(sel) = self.selected {
                let view = self.view;
                let search = self.search.clone();
                let sort = self.store.settings.sort;
                let hide = self.store.settings.hide_completed;
                let tag = self.tag_filter.clone();
                let vis = self.store.visible(&view, &search, sort, hide, tag.as_deref(), self.prio_filter);
                if let Some(i) = vis.iter().position(|&x| x == sel) {
                    if sc.alt_up || sc.alt_down {
                        self.shift_task(sel, sc.alt_up);
                    } else if sc.up && i > 0 {
                        self.selected = Some(vis[i - 1]);
                    } else if sc.down && i + 1 < vis.len() {
                        self.selected = Some(vis[i + 1]);
                    }
                }
            }
        }

        if sc.space {
            if let Some(id) = self.selected {
                self.toggle_done(id);
            }
        }
        if sc.del {
            if let Some(id) = self.selected {
                self.delete_task(id);
            }
        }
    }

    // ------------------------------------------------------------------ vòng lặp

    fn update_ui(&mut self, ctx: &egui::Context) {
        // ----- giữ frame chạy trong lúc animation entrance/pulse còn sống -----
        if self.view_entered.elapsed().as_secs_f32() < 0.35 {
            ctx.request_repaint();
        }
        match self.done_pulse {
            Some((_, at)) if at.elapsed().as_secs_f32() > 0.5 => self.done_pulse = None,
            Some(_) => ctx.request_repaint(),
            None => {}
        }

        self.handle_shortcuts(ctx);

        // ----- tiêu đề cửa sổ động: "Taskora · 7 việc · 2 quá hạn" -----
        let c_now = self.store.counts(today());
        let title = if c_now.overdue > 0 {
            format!(
                "Taskora · {} việc · {} quá hạn",
                c_now.active, c_now.overdue
            )
        } else if c_now.active > 0 {
            format!("Taskora · {} việc", c_now.active)
        } else {
            "Taskora".to_string()
        };
        if title != self.title_cache {
            self.title_cache = title.clone();
            ctx.send_viewport_cmd(egui::ViewportCommand::Title(title));
        }

        // ----- nền aurora (layer Background — panel kính mờ nằm đè lên) -----
        let dark = ctx.style().visuals.dark_mode;
        theme::paint_wallpaper(ctx, ctx.screen_rect());

        egui::TopBottomPanel::top("topbar")
            .frame(theme::glass_frame(dark, false))
            .show(ctx, |ui| {
                theme::paint_glass(ui.painter(), ui.max_rect(), egui::CornerRadius::ZERO, dark);
                self.top_bar(ui);
            });
        egui::TopBottomPanel::bottom("statusbar")
            .frame(theme::glass_frame(dark, false))
            .show(ctx, |ui| {
                theme::paint_glass(ui.painter(), ui.max_rect(), egui::CornerRadius::ZERO, dark);
                self.status_bar(ui);
            });
        egui::SidePanel::left("sidebar")
            .resizable(true)
            .default_width(224.0)
            .min_width(180.0)
            .max_width(320.0)
            .frame(theme::glass_frame(dark, false))
            .show(ctx, |ui| {
                theme::paint_glass(ui.painter(), ui.max_rect(), egui::CornerRadius::ZERO, dark);
                self.render_sidebar(ui);
            });

        if self.selected.is_some() && self.view != View::Stats {
            egui::SidePanel::right("detail")
                .resizable(true)
                .default_width(330.0)
                .min_width(260.0)
                .max_width(460.0)
                .frame(theme::glass_frame(dark, true))
                .show(ctx, |ui| {
                    theme::paint_glass(ui.painter(), ui.max_rect(), egui::CornerRadius::ZERO, dark);
                    self.render_detail(ui);
                });
        }

        egui::CentralPanel::default()
            .frame(egui::Frame::new().fill(egui::Color32::TRANSPARENT))
            .show(ctx, |ui| match self.view {
                View::Stats => self.render_stats(ui),
                _ => self.render_task_view(ui),
            });

        self.render_dialogs(ctx);

        // ----- lưu tự động (so sánh JSON từng frame) -----
        if let Ok(j) = serde_json::to_string(&self.store) {
            if j != self.last_json {
                self.last_json = j;
                self.dirty = true;
            }
        }
        if self.dirty
            && self
                .last_save
                .map_or(true, |t| t.elapsed() >= Duration::from_millis(400))
        {
            match storage::save(&self.store) {
                Ok(()) => {
                    self.dirty = false;
                    self.last_save = Some(Instant::now());
                    self.saved_label = Local::now().format("%H:%M:%S").to_string();
                }
                Err(e) => {
                    self.dirty = false;
                    self.flash(format!("Lỗi lưu: {e}"));
                }
            }
        }
        if self.dirty {
            ctx.request_repaint_after(Duration::from_millis(300));
        }
        let flash_left: Option<f32> = self
            .flash
            .as_ref()
            .map(|(_, at)| 3.0 - at.elapsed().as_secs_f32());
        match flash_left {
            Some(left) if left <= 0.0 => self.flash = None,
            Some(left) => {
                ctx.request_repaint_after(Duration::from_secs_f32(left.min(0.5)));
            }
            None => {}
        }
    }

    // ------------------------------------------------------------------ top bar

    fn top_bar(&mut self, ui: &mut egui::Ui) {
        let today_c = today();
        let c = self.store.counts(today_c);
        ui.add_space(2.0);
        ui.horizontal(|ui| {
            // ----- logo + tên + view -----
            let (r, _) = ui.allocate_exact_size(egui::vec2(28.0, 28.0), egui::Sense::hover());
            theme::paint_logo(ui, r);
            ui.add_space(6.0);
            ui.label(theme::bold_text("Taskora", 17.0, ui.visuals().text_color()));
            ui.add_space(10.0);
            // ngăn cách mảnh
            let sep_x = ui.cursor().left();
            let y0 = ui.cursor().top();
            let h = ui.spacing().interact_size.y;
            ui.painter().line_segment(
                [
                    egui::pos2(sep_x, y0 + 2.0),
                    egui::pos2(sep_x, y0 + h - 2.0),
                ],
                egui::Stroke::new(1.0f32, ui.visuals().widgets.noninteractive.bg_stroke.color),
            );
            ui.add_space(10.0);
            ui.weak(format!("· {} việc đang làm", c.active));
            if c.overdue > 0 {
                ui.colored_label(theme::DANGER, format!("· {} quá hạn", c.overdue));
            }

            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                // menu ⋯
                ui.menu_button(theme::ic(icons::DOTS_THREE_VERTICAL).size(15.0), |ui| {
                    if ui.button("Xuất bản sao lưu…").clicked() {
                        match storage::export_backup(&self.store) {
                            Ok(p) => {
                                self.export_msg = Some(p.display().to_string());
                            }
                            Err(e) => self.flash(format!("Lỗi xuất: {e}")),
                        }
                        ui.close_menu();
                    }
                    if ui.button("Nhập dữ liệu…").clicked() {
                        self.backups = storage::list_backups();
                        self.import_sel = 0;
                        self.import_err = None;
                        self.import_open = true;
                        ui.close_menu();
                    }
                    if ui.button("Mở thư mục dữ liệu").clicked() {
                        storage::open_data_dir();
                        ui.close_menu();
                    }
                    ui.separator();
                    if ui.button("Xóa toàn bộ việc đã hoàn thành").clicked() {
                        self.clear_completed();
                        ui.close_menu();
                    }
                    if ui.button("Xem thùng rác").clicked() {
                        self.set_view(View::Trash);
                        ui.close_menu();
                    }
                    ui.separator();
                    if ui.button("Phím tắt & Trợ giúp").clicked() {
                        self.help_open = true;
                        ui.close_menu();
                    }
                });

                // undo / redo
                let can_undo = !self.undo_stack.is_empty();
                let can_redo = !self.redo_stack.is_empty();
                if ui
                    .add_enabled(
                        can_undo,
                        egui::Button::new(theme::ic(icons::ARROW_COUNTER_CLOCKWISE).size(15.0)),
                    )
                    .on_hover_text("Hoàn tác (Ctrl+Z)")
                    .clicked()
                {
                    self.undo();
                }
                if ui
                    .add_enabled(
                        can_redo,
                        egui::Button::new(theme::ic(icons::ARROW_CLOCKWISE).size(15.0)),
                    )
                    .on_hover_text("Làm lại (Ctrl+Y)")
                    .clicked()
                {
                    self.redo();
                }

                // theme (icon mặt trời / mặt trăng)
                let (glyph, tip) = if self.store.settings.dark {
                    (icons::SUN, "Chuyển giao diện Sáng (Ctrl+D)")
                } else {
                    (icons::MOON, "Chuyển giao diện Tối (Ctrl+D)")
                };
                if ui
                    .small_button(theme::ic(glyph).size(14.0))
                    .on_hover_text(tip)
                    .clicked()
                {
                    self.toggle_theme(ui.ctx());
                }

                // thêm việc nhanh (nút chủ đạo, có icon)
                if ui
                    .add(theme::primary_button_icon(icons::PLUS, "Thêm việc"))
                    .on_hover_text("Thêm việc nhanh (Ctrl+N)")
                    .clicked()
                {
                    if !self.view.allows_quick_add() {
                        self.set_view(View::Inbox);
                    }
                    self.focus_quick = true;
                }

                // tìm kiếm (icon kính lú + vòng sáng khi đang nhập)
                let w = 240.0;
                let weak_c = ui.visuals().weak_text_color();
                ui.label(
                    theme::ic(icons::MAGNIFYING_GLASS)
                        .size(13.0)
                        .color(weak_c),
                );
                let resp = ui.add(
                    egui::TextEdit::singleline(&mut self.search)
                        .hint_text("Tìm việc… (Ctrl+F / Ctrl+K)")
                        .desired_width(w),
                );
                if resp.has_focus() {
                    ui.painter().rect_stroke(
                        resp.rect.expand(3.0),
                        egui::CornerRadius::same(9),
                        egui::Stroke::new(1.4f32, theme::ACCENT.gamma_multiply(0.55)),
                        egui::StrokeKind::Outside,
                    );
                }
                if resp.has_focus() && ui.input(|i| i.key_pressed(Key::Escape)) {
                    self.search.clear();
                    resp.surrender_focus();
                }
                if std::mem::take(&mut self.focus_search) {
                    resp.request_focus();
                }
                ui.add_space(2.0);
            });
        });
        ui.add_space(2.0);
    }

    // ------------------------------------------------------------------ status bar

    fn status_bar(&mut self, ui: &mut egui::Ui) {
        let t = today();
        let c = self.store.counts(t);
        ui.horizontal(|ui| {
            let weak_c = ui.visuals().weak_text_color();
            ui.scope(|ui| {
                ui.spacing_mut().item_spacing.x = 4.0;
                ui.label(theme::ic(icons::LIGHTNING).size(12.0).color(weak_c));
                ui.weak(format!("{} đang làm", c.active));
            });
            ui.scope(|ui| {
                ui.spacing_mut().item_spacing.x = 4.0;
                ui.label(theme::ic(icons::WARNING).size(12.0).color(theme::DANGER));
                if c.overdue > 0 {
                    ui.colored_label(theme::DANGER, format!("{} quá hạn", c.overdue));
                } else {
                    ui.weak("0 quá hạn");
                }
            });
            if c.done_today > 0 {
                ui.scope(|ui| {
                    ui.spacing_mut().item_spacing.x = 4.0;
                    ui.label(theme::ic(icons::CHECK_CIRCLE).size(12.0).color(theme::OK));
                    ui.colored_label(theme::OK, format!("{} xong hôm nay", c.done_today));
                });
            }
            // tiến độ hôm nay (thanh mini)
            let today_total = c.done_today + c.today;
            if today_total > 0 {
                let frac = c.done_today as f32 / today_total as f32;
                ui.add(
                    egui::ProgressBar::new(frac)
                        .desired_height(7.0)
                        .desired_width(90.0)
                        .fill(theme::OK)
                        .corner_radius(egui::CornerRadius::same(4))
                        .animate(true),
                );
                ui.weak(format!("{}/{} hôm nay", c.done_today, today_total));
            }
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                ui.weak("Ctrl+N thêm · Ctrl+K tìm · Space đánh dấu · Ctrl+Z hoàn tác");
                let f = self
                    .flash
                    .as_ref()
                    .filter(|(_, at)| at.elapsed() < Duration::from_secs(3))
                    .map(|(m, _)| m.clone());
                if let Some(m) = f {
                    ui.colored_label(theme::ACCENT_SOFT, m);
                } else {
                    ui.scope(|ui| {
                        ui.spacing_mut().item_spacing.x = 4.0;
                        ui.label(theme::ic(icons::CHECK).size(12.0).color(theme::OK));
                        ui.weak(format!("Đã lưu {}", self.saved_label));
                    });
                }
            });
        });
    }

    // ------------------------------------------------------------------ dialogs

    fn render_dialogs(&mut self, ctx: &egui::Context) {
        // ---- tạo / đổi tên danh sách ----
        if let Some(dlg) = self.list_dialog.clone() {
            let mut open = true;
            let mut accepted = false;
            let mut cancelled = false;
            egui::Window::new(if dlg.editing.is_some() {
                "Đổi tên danh sách"
            } else {
                "Danh sách mới"
            })
            .id(egui::Id::new("list_dialog"))
            .open(&mut open)
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, -40.0])
            .default_width(320.0)
            .show(ctx, |ui| {
                ui.label("Tên danh sách:");
                let resp = ui.add(
                    egui::TextEdit::singleline(&mut self.list_dialog.as_mut().unwrap().name)
                        .desired_width(f32::INFINITY)
                        .hint_text("VD: Công việc…"),
                );
                if resp.lost_focus() && ui.input(|i| i.key_pressed(Key::Enter)) {
                    accepted = true;
                }
                ui.add_space(6.0);
                ui.label("Màu:");
                ui.horizontal_wrapped(|ui| {
                    for (i, rgb) in LIST_PALETTE.iter().enumerate() {
                        let selected =
                            self.list_dialog.as_ref().map(|d| d.color_idx) == Some(i);
                        let color = egui::Color32::from_rgb(rgb[0], rgb[1], rgb[2]);
                        let (r, rr) =
                            ui.allocate_exact_size(egui::vec2(26.0, 26.0), egui::Sense::click());
                        ui.painter().rect_filled(
                            r,
                            egui::CornerRadius::same(6),
                            if selected { color } else { color.gamma_multiply(0.55) },
                        );
                        if selected {
                            ui.painter().rect_stroke(
                                r.shrink(2.0),
                                egui::CornerRadius::same(4),
                                egui::Stroke::new(2.0f32, ui.visuals().text_color()),
                                egui::StrokeKind::Outside,
                            );
                        }
                        if rr.clicked() {
                            if let Some(d) = self.list_dialog.as_mut() {
                                d.color_idx = i;
                            }
                        }
                    }
                });
                ui.add_space(10.0);
                ui.horizontal(|ui| {
                    let can_create = self
                        .list_dialog
                        .as_ref()
                        .map(|d| !d.name.trim().is_empty())
                        .unwrap_or(false);
                    if ui
                        .add_enabled(can_create, theme::primary_button("Lưu"))
                        .clicked()
                    {
                        accepted = true;
                    }
                    if ui.button("Hủy").clicked() {
                        cancelled = true;
                    }
                });
            });
            if !open {
                cancelled = true;
            }
            if cancelled {
                self.list_dialog = None;
            } else if accepted {
                let name = dlg
                    .name
                    .trim()
                    .to_string();
                if !name.is_empty() {
                    if let Some(id) = dlg.editing {
                        self.push_undo();
                        if let Some(l) = self.store.lists.iter_mut().find(|l| l.id == id) {
                            l.name = name;
                            l.color = LIST_PALETTE[dlg.color_idx];
                        }
                        self.flash("Đã đổi tên danh sách");
                    } else {
                        self.push_undo();
                        let id = self.store.new_id();
                        self.store.lists.push(crate::models::List {
                            id,
                            name,
                            color: LIST_PALETTE[dlg.color_idx],
                        });
                        self.set_view(View::List(id));
                        self.flash("Đã tạo danh sách");
                    }
                }
                self.list_dialog = None;
            }
        }

        // ---- xuất thành công ----
        if let Some(path) = self.export_msg.clone() {
            let mut open = true;
            let mut close = false;
            egui::Window::new("Xuất bản sao lưu thành công ✓")
                .id(egui::Id::new("export_done"))
                .open(&mut open)
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, -40.0])
                .default_width(380.0)
                .show(ctx, |ui| {
                    ui.label("Bản sao lưu đã được ghi tới:");
                    ui.label(RichText::new(&path).monospace());
                    ui.add_space(8.0);
                    ui.horizontal(|ui| {
                        if ui.button("Mở thư mục").clicked() {
                            storage::open_data_dir();
                        }
                        if ui.button("Đóng").clicked() {
                            close = true;
                        }
                    });
                });
            if close {
                open = false;
            }
            if !open {
                self.export_msg = None;
            }
        }

        // ---- nhập dữ liệu ----
        if self.import_open {
            let mut open = true;
            let mut close = false;
            let mut do_import = false;
            egui::Window::new("Nhập dữ liệu từ bản sao lưu")
                .id(egui::Id::new("import_dialog"))
                .open(&mut open)
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, -40.0])
                .default_width(420.0)
                .show(ctx, |ui| {
                    ui.weak("Chọn một bản sao lưu đã xuất:");
                    egui::ScrollArea::vertical()
                        .id_salt("import_list")
                        .max_height(180.0)
                        .auto_shrink([false, false])
                        .show(ui, |ui| {
                            if self.backups.is_empty() {
                                ui.weak("Chưa có bản sao lưu nào.");
                            }
                            for (i, p) in self.backups.iter().enumerate() {
                                let name = p
                                    .file_name()
                                    .map(|s| s.to_string_lossy().to_string())
                                    .unwrap_or_default();
                                ui.selectable_value(&mut self.import_sel, i, name);
                            }
                        });
                    if let Some(e) = self.import_err.clone() {
                        ui.colored_label(theme::DANGER, e);
                    }
                    ui.add_space(6.0);
                    ui.separator();
                    ui.weak("Hoặc dán đường dẫn tệp .json:");
                    let cp = ui.add(
                        egui::TextEdit::singleline(&mut self.import_path)
                            .hint_text("C:\\Users\\…\\Taskora\\backups\\….json")
                            .desired_width(f32::INFINITY),
                    );
                    let mut custom_go = false;
                    if cp.lost_focus() && ui.input(|i| i.key_pressed(Key::Enter)) {
                        custom_go = true;
                    }
                    ui.add_space(8.0);
                    ui.horizontal(|ui| {
                        let can = !self.backups.is_empty();
                        if ui
                            .add_enabled(can, egui::Button::new("Nhập bản đã chọn"))
                            .clicked()
                        {
                            do_import = true;
                        }
                        if ui.button("Nhập đường dẫn").clicked() {
                            custom_go = true;
                        }
                        if ui.button("Làm mới").clicked() {
                            self.backups = storage::list_backups();
                        }
                        if ui.button("Hủy").clicked() {
                            close = true;
                        }
                    });
                    if custom_go {
                        let path = self.import_path.trim().to_string();
                        if path.is_empty() {
                            self.import_err = Some("Chưa nhập đường dẫn.".into());
                        } else {
                            match storage::import_backup(std::path::Path::new(&path)) {
                                Ok(st) => {
                                    self.push_undo();
                                    self.store = st;
                                    self.keep_selection_valid();
                                    theme::set_active_theme(ui.ctx(), self.store.settings.dark);
                                    self.flash("Đã nhập dữ liệu thành công ✓");
                                    close = true;
                                }
                                Err(e) => {
                                    self.import_err = Some(format!("Không đọc được tệp: {e}"));
                                }
                            }
                        }
                    }
                });
            if close {
                open = false;
            }
            if do_import {
                if let Some(p) = self.backups.get(self.import_sel).cloned() {
                    match storage::import_backup(&p) {
                        Ok(st) => {
                            self.push_undo();
                            self.store = st;
                            self.keep_selection_valid();
                            theme::set_active_theme(ctx, self.store.settings.dark);
                            self.flash("Đã nhập dữ liệu thành công ✓");
                            self.import_open = false;
                        }
                        Err(e) => {
                            self.import_err = Some(format!("Không đọc được tệp: {e}"));
                        }
                    }
                }
            }
            if !open {
                self.import_open = false;
            }
        }

        // ---- help ----
        if self.help_open {
            let mut open = true;
            egui::Window::new("Phím tắt & Trợ giúp")
                .id(egui::Id::new("help_dialog"))
                .open(&mut open)
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
                .default_width(430.0)
                .show(ctx, |ui| {
                    ui.heading("Thao tác nhanh");
                    egui::Grid::new("help_grid")
                        .num_columns(2)
                        .spacing([18.0, 5.0])
                        .show(ui, |ui| {
                            let rows: &[(&str, &str)] = &[
                                ("Ctrl + N", "Thêm việc nhanh"),
                                ("Ctrl + F / Ctrl + K", "Tìm kiếm nhanh"),
                                ("Chuột phải", "Menu ngữ cảnh: hạn chót, ưu tiên…"),
                                ("Ctrl + D", "Đổi giao diện Tối/Sáng"),
                                ("Ctrl + Z / Ctrl + Y", "Hoàn tác / Làm lại"),
                                ("Ctrl + 1…6", "Chuyển view nhanh"),
                                ("Space", "Đánh dấu hoàn thành việc đang chọn"),
                                ("Delete", "Xóa (vào thùng rác)"),
                                ("↑ / ↓", "Chọn việc kế trước / kế sau"),
                                ("Alt + ↑ / ↓", "Đổi thứ tự (khi sắp Thủ công)"),
                                ("Esc", "Đóng panel / hộp thoại / bỏ bộ lọc"),
                                ("Enter", "Xác nhận trong ô nhập"),
                            ];
                            for (k, v) in rows {
                                let tc = ui.visuals().text_color();
                                ui.label(theme::bold_text(*k, 12.5, tc));
                                ui.label(*v);
                                ui.end_row();
                            }
                        });
                    ui.separator();
                    ui.heading("Mẹo thêm việc nhanh");
                    ui.label("Viết tự nhiên, ví dụ:");
                    ui.label(
                        RichText::new("  Trả báo cáo ngày mai #công-việc !p1 *weekly")
                            .monospace(),
                    );
                    ui.weak("#the · !p1–!p4 · ngày mai/hôm nay/thứ 6/15/11/next monday · *daily/*weekly/*monthly · hàng ngày");
                    ui.add_space(6.0);
                    ui.separator();
                    ui.weak(format!(
                        "Taskora v{} · dữ liệu: {}",
                        env!("CARGO_PKG_VERSION"),
                        storage::data_dir().display()
                    ));
                });
            if !open {
                self.help_open = false;
            }
        }
    }
}

impl eframe::App for TaskoraApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.update_ui(ctx);
    }

    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) {
        let _ = storage::save(&self.store);
    }
}
