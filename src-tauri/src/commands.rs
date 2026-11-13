//! Toàn bộ lệnh IPC từ frontend — port nguyên logic từ bản egui (app.rs).

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State};

use crate::models::{
    occurrences_after, next_after, today, EndSpec, Priority, RecurrenceRule, Repeat,
    SortMode, StepPreset, Store, SubTask, Task, View,
};
use crate::parser;
use crate::state::{make_snapshot, AppState, Inner, Snapshot, LIST_PALETTE};

/// Chèn một task đã parse vào store (dùng chung cho quick-add và brain-dump).
/// Trả về id việc mới. Không push undo (bên gọi quyết định).
fn insert_parsed_task(i: &mut Inner, p: parser::Parsed, view: &View) -> u64 {
    let mut due = p.due;
    let mut list_id = None;
    let mut starred = false;
    match view {
        View::Today => { due.get_or_insert_with(today); }
        View::Upcoming => { let t = today(); due.get_or_insert_with(|| t.succ_opt().unwrap_or(t)); }
        View::Starred => starred = true,
        View::List(id) => list_id = Some(*id),
        _ => {}
    }
    let order = i.store.tasks.iter()
        .filter(|t| t.list_id == list_id)
        .map(|t| t.order)
        .min()
        .unwrap_or(0);
    let id = i.store.new_id();
    i.store.tasks.insert(
        0,
        Task {
            id,
            title: p.title,
            notes: String::new(),
            list_id,
            priority: p.priority.unwrap_or_default(),
            due,
            repeat: p
                .recurrence
                .as_ref()
                .map(|r| r.shadow())
                .unwrap_or_else(|| p.repeat.unwrap_or(Repeat::None)),
            recurrence: p.recurrence.as_ref().map(|r| {
                let mut r = r.clone().clamped();
                r.freeze_anchor(due);
                r
            }),
            tags: p.tags,
            subtasks: Vec::new(),
            starred,
            order: order.saturating_sub(1),
            created_at: Utc::now(),
            completed_at: None,
            deleted_at: None,
        },
    );
    id
}
use crate::stats::{self, StatsPayload};
use crate::storage;

// ------------------------------------------------------------------ helpers

fn set_flash(i: &mut Inner, msg: impl Into<String>) {
    i.flash = Some(msg.into());
}

fn parse_date(s: &str) -> Result<NaiveDate, String> {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").map_err(|_| "Ngày không hợp lệ (cần yyyy-mm-dd)".to_string())
}

#[derive(Deserialize, Clone)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ViewWire {
    Inbox,
    Today,
    Upcoming,
    Starred,
    Completed,
    Trash,
    Stats,
    List { id: u64 },
    /// Mọi view lạ (vd "settings") → hành xử như Hộp thư (an toàn).
    #[serde(other)]
    Unknown,
}

impl From<ViewWire> for View {
    fn from(v: ViewWire) -> Self {
        match v {
            ViewWire::Inbox => View::Inbox,
            ViewWire::Today => View::Today,
            ViewWire::Upcoming => View::Upcoming,
            ViewWire::Starred => View::Starred,
            ViewWire::Completed => View::Completed,
            ViewWire::Trash => View::Trash,
            ViewWire::Stats => View::Stats,
            ViewWire::List { id } => View::List(id),
            ViewWire::Unknown => View::Inbox,
        }
    }
}

/// Áp dụng mutation + tạo snapshot, đồng thời cập nhật tiêu đề cửa sổ.
fn finish(app: &AppHandle, i: &mut Inner) -> Snapshot {
    let snap = make_snapshot(i);
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.set_title(&format!("Taskora — {} việc đang làm", snap.counts.active));
    }
    snap
}

/// Hoàn thành / bỏ hoàn thành; việc lặp lại tự sinh lần kế tiếp.
fn toggle_done(i: &mut Inner, id: u64) {
    AppState::push_undo(i);
    let Some(idx) = i.store.tasks.iter().position(|t| t.id == id) else {
        return;
    };
    if i.store.tasks[idx].completed_at.is_some() {
        i.store.tasks[idx].completed_at = None;
        return;
    }
    let snap_task = i.store.tasks[idx].clone();
    i.store.tasks[idx].completed_at = Some(Utc::now());
    match snap_task.recurrence.clone() {
        Some(rule) => {
            let base = snap_task.due.unwrap_or_else(today);
            // Hết chuỗi ở thời điểm hoàn thành:
            //  - After với done+1 >= total → dừng (đúng N lần bấm)
            //  - không còn occurrence nào từ hôm nay trở đi (until đã trôi qua) → dừng + flash
            let after_exhausted = matches!(&rule.ends, EndSpec::After { total, done } if done + 1 >= *total);
            let future_exhausted = next_after(&rule, base.max(today())).is_none();
            let next = if after_exhausted || future_exhausted {
                None
            } else {
                next_after(&rule, base) // ngày sinh = theo due (giữ thứ tự chuỗi catch-up quá hạn)
            };
            match next {
                Some(next) => {
                    let mut rule2 = rule.clone();
                    if let EndSpec::After { done, .. } = &mut rule2.ends {
                        *done += 1; // đếm trên CLONE; instance vừa xong giữ `done` cũ (lịch sử nhất quán, undo free)
                    }
                    let mut nt = snap_task;
                    nt.id = i.store.new_id();
                    nt.due = Some(next);
                    nt.recurrence = Some(rule2.clone());
                    nt.repeat = rule2.shadow();
                    nt.completed_at = None;
                    nt.deleted_at = None;
                    nt.created_at = Utc::now();
                    nt.starred = false;
                    for s in &mut nt.subtasks {
                        s.done = false;
                    }
                    nt.order = i.store.tasks[idx].order.saturating_add(1);
                    i.store.tasks.push(nt);
                    set_flash(i, format!("✓ Xong — lần tiếp theo: {}, {}", crate::models::weekday_name(next), next.format("%d/%m/%Y")));
                }
                None => match &rule.ends {
                    EndSpec::After { total, .. } => {
                        set_flash(i, format!("✓ Xong — đủ {total} lần như đã hẹn"))
                    }
                    _ => set_flash(i, "✓ Xong — chuỗi lặp đã kết thúc".to_string()),
                },
            }
        }
        None => {
            // Lưới an toàn: file chưa sanitize có repeat mà thiếu recurrence → nâng cấp tại chỗ.
            if snap_task.repeat != Repeat::None {
                let base = snap_task.due.unwrap_or_else(today);
                if let Some(rule) = crate::models::rule_from_repeat(snap_task.repeat, Some(base)) {
                    if let Some(next) = next_after(&rule, base) {
                        let mut nt = snap_task;
                        nt.id = i.store.new_id();
                        nt.due = Some(next);
                        nt.recurrence = Some(rule.clone());
                        nt.repeat = rule.shadow();
                        nt.completed_at = None;
                        nt.deleted_at = None;
                        nt.created_at = Utc::now();
                        nt.starred = false;
                        for s in &mut nt.subtasks {
                            s.done = false;
                        }
                        nt.order = i.store.tasks[idx].order.saturating_add(1);
                        i.store.tasks.push(nt);
                        set_flash(i, format!("✓ Xong — lần tiếp theo: {}, {}", crate::models::weekday_name(next), next.format("%d/%m/%Y")));
                    }
                }
            }
        }
    }
}

fn delete_task(i: &mut Inner, id: u64, in_trash: bool) {
    if in_trash {
        // xóa vĩnh viễn
        AppState::push_undo(i);
        i.store.tasks.retain(|t| t.id != id);
        set_flash(i, "Đã xóa vĩnh viễn");
        return;
    }
    AppState::push_undo(i);
    if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
        t.deleted_at = Some(Utc::now());
    }
    set_flash(i, "Đã chuyển vào thùng rác (Ctrl+Z hoàn tác)");
}

fn duplicate_task(i: &mut Inner, id: u64) {
    AppState::push_undo(i);
    let Some(idx) = i.store.tasks.iter().position(|t| t.id == id) else {
        return;
    };
    let mut nt = i.store.tasks[idx].clone();
    nt.id = i.store.new_id();
    nt.title = format!("{} (bản sao)", nt.title);
    nt.completed_at = None;
    nt.deleted_at = None;
    nt.created_at = Utc::now();
    for s in &mut nt.subtasks {
        s.id = i.store.new_id();
        s.done = false;
    }
    nt.order = i.store.tasks[idx].order;
    i.store.tasks.insert(idx + 1, nt);
    set_flash(i, "Đã nhân bản việc");
}

/// Sắp xếp lại `order` theo thứ tự hiển thị của view (chỉ chế độ Thủ công).
fn reorder_with(i: &mut Inner, view: &View, f: impl FnOnce(&mut Vec<u64>)) {
    let mut vis = i
        .store
        .visible(view, "", i.store.settings.sort, false, None, None);
    f(&mut vis);
    for (idx, id) in vis.iter().enumerate() {
        if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == *id) {
            t.order = idx as u32;
        }
    }
}

fn shift_task(i: &mut Inner, view: &View, id: u64, up: bool) {
    if i.store.settings.sort != SortMode::Manual {
        set_flash(i, "Chỉ sắp xếp được khi chọn thứ tự Thủ công");
        return;
    }
    AppState::push_undo(i);
    reorder_with(i, view, |vis| {
        if let Some(pos) = vis.iter().position(|&x| x == id) {
            if up && pos > 0 {
                vis.swap(pos, pos - 1);
            } else if !up && pos + 1 < vis.len() {
                vis.swap(pos, pos + 1);
            }
        }
    });
}

fn drop_task(i: &mut Inner, view: &View, src: u64, dst: u64, before: bool) {
    if i.store.settings.sort != SortMode::Manual || src == dst {
        return;
    }
    AppState::push_undo(i);
    reorder_with(i, view, |vis| {
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
    set_flash(i, "Đã đổi thứ tự");
}

// ------------------------------------------------------------------ act enum

/// Wire format cho hành động (frontend gửi `{ "type": "toggle", "id": 3 }`).
#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Act {
    Toggle { id: u64 },
    Star { id: u64 },
    Delete { id: u64 },
    Restore { id: u64 },
    Purge { id: u64 },
    Duplicate { id: u64 },
    MoveUp { id: u64 },
    MoveDown { id: u64 },
    MoveToList { id: u64, list: Option<u64> },
    Drop { src: u64, dst: u64, before: bool },
    AddSubtask { id: u64 },
    AddSubtasks { id: u64, titles: Vec<String> },
    ClearCompleted,
    SetDue { id: u64, due: Option<String> },
    SetPriority { id: u64, priority: Priority },
    PurgeTrash,
    DeferOverdue { target: String },
    BulkComplete { ids: Vec<u64> },
    BulkStar { ids: Vec<u64> },
    BulkDelete { ids: Vec<u64> },
}

// ------------------------------------------------------------------ lệnh snapshot

#[tauri::command]
pub fn snapshot(app: AppHandle, state: State<'_, AppState>) -> Snapshot {
    let mut i = state.lock();
    finish(&app, &mut i)
}

// ------------------------------------------------------------------ lệnh act

#[tauri::command]
pub fn act(
    app: AppHandle,
    state: State<'_, AppState>,
    action: Act,
    view: ViewWire,
) -> Result<Snapshot, String> {
    let view = View::from(view);
    let in_trash = matches!(view, View::Trash);
    let mut i = state.lock();
    match action {
        Act::Toggle { id } => toggle_done(&mut i, id),
        Act::Star { id } => {
            if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
                t.starred = !t.starred;
            }
        }
        Act::Delete { id } => delete_task(&mut i, id, in_trash),
        Act::Restore { id } => {
            AppState::push_undo(&mut i);
            if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
                t.deleted_at = None;
                t.completed_at = None;
            }
            set_flash(&mut i, "Đã khôi phục việc");
        }
        Act::Purge { id } => {
            AppState::push_undo(&mut i);
            i.store.tasks.retain(|t| t.id != id);
            set_flash(&mut i, "Đã xóa vĩnh viễn");
        }
        Act::Duplicate { id } => duplicate_task(&mut i, id),
        Act::MoveUp { id } => shift_task(&mut i, &view, id, true),
        Act::MoveDown { id } => shift_task(&mut i, &view, id, false),
        Act::MoveToList { id, list } => {
            AppState::push_undo(&mut i);
            if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
                t.list_id = list;
            }
            set_flash(&mut i, "Đã chuyển việc");
        }
        Act::Drop { src, dst, before } => drop_task(&mut i, &view, src, dst, before),
        Act::AddSubtask { id } => {
            AppState::push_undo(&mut i);
            let sid = i.store.new_id();
            if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
                t.subtasks.push(SubTask {
                    id: sid,
                    title: String::new(),
                    done: false,
                });
            }
        }
        Act::AddSubtasks { id, titles } => {
            AppState::push_undo(&mut i);
            let cleaned: Vec<String> = titles
                .iter()
                .map(|t| t.trim().chars().take(140).collect::<String>().trim().to_string())
                .filter(|t| !t.is_empty())
                .take(12)
                .collect();
            let mut added = 0usize;
            let sids: Vec<u64> = (0..cleaned.len()).map(|_| i.store.new_id()).collect();
            if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
                for (title, sid) in cleaned.into_iter().zip(sids) {
                    t.subtasks.push(SubTask { id: sid, title, done: false });
                    added += 1;
                }
            }
            set_flash(&mut i, format!("Đã thêm {added} bước nhỏ ✓"));
        }
        Act::ClearCompleted => {
            AppState::push_undo(&mut i);
            let before = i.store.tasks.len();
            i.store
                .tasks
                .retain(|t| !(t.is_completed() && !t.is_deleted()));
            let n = before - i.store.tasks.len();
            set_flash(&mut i, format!("Đã xóa {n} việc hoàn thành"));
        }
        Act::SetDue { id, due } => {
            let due = due.as_deref().map(parse_date).transpose()?;
            AppState::push_undo(&mut i);
            if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
                t.due = due;
            }
            set_flash(
                &mut i,
                match due {
                    Some(d) => format!("Hạn chót: {}", d.format("%d/%m/%Y")),
                    None => "Đã bỏ hạn chót".to_string(),
                },
            );
        }
        Act::SetPriority { id, priority } => {
            AppState::push_undo(&mut i);
            if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
                t.priority = priority;
            }
            set_flash(&mut i, format!("Ưu tiên: {}", priority.label()));
        }
        Act::PurgeTrash => {
            let n = i.store.tasks.iter().filter(|t| t.is_deleted()).count();
            if n == 0 {
                set_flash(&mut i, "Thùng rác đã trống");
                return Ok(finish(&app, &mut i));
            }
            AppState::push_undo(&mut i);
            i.store.tasks.retain(|t| !t.is_deleted());
            set_flash(&mut i, format!("Đã xóa vĩnh viễn {n} việc trong thùng rác"));
        }
        Act::BulkComplete { ids } => {
            if ids.is_empty() {
                // không có gì để làm
            } else {
                AppState::push_undo(&mut i);
                let mut n = 0usize;
                for t in i.store.tasks.iter_mut() {
                    if ids.contains(&t.id) && t.completed_at.is_none() && t.deleted_at.is_none() {
                        t.completed_at = Some(Utc::now());
                        n += 1;
                    }
                }
                set_flash(&mut i, format!("Đã hoàn thành {n} việc"));
            }
        }
        Act::BulkStar { ids } => {
            let mut n = 0usize;
            for t in i.store.tasks.iter_mut() {
                if ids.contains(&t.id) && !t.starred {
                    t.starred = true;
                    n += 1;
                }
            }
            set_flash(&mut i, format!("Đã ghim {n} việc"));
        }
        Act::BulkDelete { ids } => {
            if ids.is_empty() {
                // không có gì để làm
            } else if in_trash {
                AppState::push_undo(&mut i);
                i.store.tasks.retain(|t| !ids.contains(&t.id));
                set_flash(&mut i, format!("Đã xóa vĩnh viễn {} việc", ids.len()));
            } else {
                AppState::push_undo(&mut i);
                let mut n = 0usize;
                let now = Utc::now();
                for t in i.store.tasks.iter_mut() {
                    if ids.contains(&t.id) && t.deleted_at.is_none() {
                        t.deleted_at = Some(now);
                        n += 1;
                    }
                }
                set_flash(&mut i, format!("Đã chuyển {n} việc vào thùng rác"));
            }
        }
        Act::DeferOverdue { target } => {
            let target = parse_date(&target)?;
            let t = today();
            let n = i
                .store
                .tasks
                .iter()
                .filter(|x| x.is_active() && x.due.map(|d| d < t).unwrap_or(false))
                .count();
            if n == 0 {
                set_flash(&mut i, "Không có việc quá hạn nào");
                return Ok(finish(&app, &mut i));
            }
            AppState::push_undo(&mut i);
            for task in i
                .store
                .tasks
                .iter_mut()
                .filter(|x| x.is_active() && x.due.map(|d| d < t).unwrap_or(false))
            {
                task.due = Some(target);
            }
            set_flash(
                &mut i,
                format!("Đã đổi hạn {n} việc quá hạn → {}", target.format("%d/%m/%Y")),
            );
        }
    }
    AppState::commit(&mut i);
    Ok(finish(&app, &mut i))
}

// ------------------------------------------------------------------ quick add

#[tauri::command]
pub fn quick_add(
    app: AppHandle,
    state: State<'_, AppState>,
    input: String,
    view: ViewWire,
) -> Result<Snapshot, String> {
    let input = input.trim().to_string();
    if input.is_empty() {
        return Err("Nội dung trống".to_string());
    }
    let p = parser::parse(&input, today());
    if p.title.trim().is_empty() {
        return Err("Không nhận diện được nội dung việc cần làm".to_string());
    }
    let view = View::from(view);
    let mut i = state.lock();
    AppState::push_undo(&mut i);
    let id = insert_parsed_task(&mut i, p, &view);
    set_flash(&mut i, "Đã thêm việc ✓");
    i.last_added = Some(id);
    AppState::commit(&mut i);
    Ok(finish(&app, &mut i))
}

/// Lưu mẫu chia nhỏ do người dùng tự tạo (trùng tên → ghi đè).
#[tauri::command]
pub fn save_step_preset(
    app: AppHandle,
    state: State<'_, AppState>,
    name: String,
    steps: Vec<String>,
) -> Result<Snapshot, String> {
    let name = name.trim().to_string();
    if name.is_empty() {
        return Err("Đặt tên cho mẫu đã".to_string());
    }
    if name.chars().count() > 40 {
        return Err("Tên mẫu tối đa 40 ký tự".to_string());
    }
    let steps: Vec<String> = steps
        .iter()
        .map(|s| s.trim().chars().take(140).collect::<String>().trim().to_string())
        .filter(|s| !s.is_empty())
        .take(12)
        .collect();
    if steps.is_empty() {
        return Err("Mẫu phải có ít nhất 1 bước".to_string());
    }
    let mut i = state.lock();
    if let Some(p) = i
        .store
        .step_presets
        .iter_mut()
        .find(|p| p.name.to_lowercase() == name.to_lowercase())
    {
        p.steps = steps;
        set_flash(&mut i, "Đã cập nhật mẫu ✓");
    } else {
        let id = i.store.new_id();
        i.store.step_presets.push(StepPreset { id, name, steps });
        set_flash(&mut i, "Đã lưu mẫu ✓");
    }
    AppState::commit(&mut i);
    Ok(finish(&app, &mut i))
}

/// Xóa một mẫu chia nhỏ tự tạo.
#[tauri::command]
pub fn delete_step_preset(app: AppHandle, state: State<'_, AppState>, id: u64) -> Snapshot {
    let mut i = state.lock();
    i.store.step_presets.retain(|p| p.id != id);
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

/// Brain-dump — đổ hàng loạt suy nghĩ vào Hộp thư, mỗi dòng một việc.
#[tauri::command]
pub fn brain_dump(
    app: AppHandle,
    state: State<'_, AppState>,
    input: String,
    view: ViewWire,
) -> Result<Snapshot, String> {
    let lines: Vec<&str> = input
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .take(100)
        .collect();
    if lines.is_empty() {
        return Err("Chưa có gì để đổ ra — viết mỗi dòng một việc".to_string());
    }
    let view = View::from(view);
    // Parse trước khi push undo — dòng rác không để lại undo trống
    let parsed: Vec<parser::Parsed> = lines
        .iter()
        .map(|l| parser::parse(l, today()))
        .filter(|p| !p.title.trim().is_empty())
        .collect();
    if parsed.is_empty() {
        return Err("Không dòng nào nhận diện được việc".to_string());
    }
    let skipped = lines.len() - parsed.len();
    let mut i = state.lock();
    AppState::push_undo(&mut i);
    let added = parsed.len();
    for p in parsed {
        insert_parsed_task(&mut i, p, &view);
    }
    let msg = if skipped > 0 {
        format!("Đã đổ {added} việc vào Hộp thư ✓ (bỏ qua {skipped} dòng)")
    } else {
        format!("Đã đổ {added} việc vào Hộp thư ✓")
    };
    set_flash(&mut i, msg);
    AppState::commit(&mut i);
    Ok(finish(&app, &mut i))
}

/// Ghi nhận một phiên tập trung 25′ đã hoàn thành (không undo-able).
#[tauri::command]
pub fn log_focus_session(app: AppHandle, state: State<'_, AppState>) -> Snapshot {
    let mut i = state.lock();
    let key = today().format("%Y-%m-%d").to_string();
    *i.store.focus_days.entry(key).or_insert(0) += 1;
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

/* ─── FOCUS ENGINE (v2.10.0) — thời gian nằm ở Rust, wall-clock ─── */

#[tauri::command]
pub fn focus_start(app: AppHandle, state: State<'_, AppState>, task_id: Option<u64>) -> Snapshot {
    let mut i = state.lock();
    let title = task_id
        .and_then(|id| i.store.tasks.iter().find(|t| t.id == id))
        .map(|t| t.title.clone())
        .unwrap_or_else(|| "Phiên tập trung".to_string());
    crate::focus::start(&mut i, task_id, title);
    let payload = crate::focus::payload(&i, false, false);
    let _ = app.emit("focus:change", payload);
    finish(&app, &mut i)
}

#[tauri::command]
pub fn focus_stop(app: AppHandle, state: State<'_, AppState>) -> Snapshot {
    let mut i = state.lock();
    crate::focus::stop(&mut i);
    let payload = crate::focus::payload(&i, false, false);
    let _ = app.emit("focus:change", payload);
    // Dừng đồng hồ ⇒ cửa sổ Đồng hồ đóng theo (đóng ở CẢ khi bấm Dừng trong cửa sổ nhỏ lẫn ở overlay)
    if let Some(w) = app.get_webview_window("timer") {
        let _ = w.close();
    }
    finish(&app, &mut i)
}

#[tauri::command]
pub fn focus_pause_toggle(app: AppHandle, state: State<'_, AppState>) -> crate::focus::FocusPayload {
    let mut i = state.lock();
    let p = crate::focus::pause_toggle(&mut i);
    let _ = app.emit("focus:change", p.clone());
    p
}

#[tauri::command]
pub fn focus_reset(app: AppHandle, state: State<'_, AppState>) -> crate::focus::FocusPayload {
    let mut i = state.lock();
    let p = crate::focus::reset(&mut i);
    let _ = app.emit("focus:change", p.clone());
    p
}

#[tauri::command]
pub fn focus_break_start(app: AppHandle, state: State<'_, AppState>) -> crate::focus::FocusPayload {
    let mut i = state.lock();
    let p = crate::focus::break_start(&mut i);
    let _ = app.emit("focus:change", p.clone());
    p
}

#[tauri::command]
pub fn focus_complete(app: AppHandle, state: State<'_, AppState>) -> crate::focus::FocusPayload {
    let mut i = state.lock();
    let p = crate::focus::complete(&mut i);
    if p.transitioned && p.completed_focus {
        AppState::commit(&mut i);
    }
    let _ = app.emit("focus:change", p.clone());
    p
}

#[tauri::command]
pub fn focus_state(state: State<'_, AppState>) -> crate::focus::FocusPayload {
    let i = state.lock();
    crate::focus::payload(&i, false, false)
}

/// Mở (hoặc focus) cửa sổ Đồng hồ — mini window luôn nổi.
/// QUAN TRỌNG (Windows): phải là `async` — trên Windows, tạo webview mới bên trong
/// command đồng bộ gây deadlock vòng lặp WebView2 ⇒ cửa sổ trắng, ứng dụng treo.
#[tauri::command]
pub async fn focus_open_timer(app: AppHandle) -> Result<(), String> {
    if let Some(w) = app.get_webview_window("timer") {
        let _ = w.set_focus();
        return Ok(());
    }
    tauri::WebviewWindowBuilder::new(&app, "timer", tauri::WebviewUrl::App("timer.html".into()))
        .title("Taskora — Đồng hồ")
        .inner_size(340.0, 430.0)
        .min_inner_size(300.0, 400.0)
        .decorations(true)
        .transparent(false)
        .always_on_top(true)
        .resizable(true)
        .center()
        .build()
        .map(|_| ())
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn focus_timer_close(app: AppHandle) -> Result<(), String> {
    if let Some(w) = app.get_webview_window("timer") {
        w.close().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn focus_timer_pin(app: AppHandle, state: State<'_, AppState>) -> Result<bool, String> {
    let pinned = {
        let mut i = state.lock();
        crate::focus::timer_pin_toggle(&mut i)
    };
    if let Some(w) = app.get_webview_window("timer") {
        w.set_always_on_top(pinned).map_err(|e| e.to_string())?;
    }
    Ok(pinned)
}

// ─────────────────────────────────────────────────────────────
// Cửa sổ THÔNG BÁO riêng — tách khỏi cửa sổ app chính (frameless,
// trong suốt, luôn nổi, kích thước tự co theo số thẻ).
// Luồng: main window invoke("notify_push") → Rust đảm bảo cửa sổ tồn tại →
//   - chưa sẵn sàng: xếp vào pending (tối đa 10, FIFO)
//   - sẵn sàng: emit "notify:arrival" (cửa sổ Thông báo đang nghe)
// Cửa sổ Thông báo: đọc prefs mới nhất qua notify_prefs, vẽ thẻ, tự đo chiều
// cao → notify_layout (thu/phóng/ẩn cửa sổ). Bấm nút hành động → notify_action
// → Rust emit "notify:action" → main window chạy closure (undo…).
// ─────────────────────────────────────────────────────────────

#[derive(Clone, serde::Serialize, serde::Deserialize)]
pub struct NotifyAction {
    pub id: u64,
    pub label: String,
}

#[derive(Clone, serde::Serialize)]
pub struct NotifyItem {
    pub kind: String,
    pub title: String,
    pub body: String,
    pub actions: Vec<NotifyAction>,
    /// true = thẻ yên lặng (caller truyền sound: "none") — vẫn hiện, không kêu
    #[serde(default)]
    pub silent: bool,
}

#[derive(serde::Serialize)]
pub struct NotifyPrefsPayload {
    pub dark: bool,
    pub accent: String,
    pub perf_mode: bool,
    pub reduce_motion: bool,
    pub acrylic_alpha: u8,
    pub notify_enabled: bool,
    pub notify_autohide: bool,
    pub notify_hide_secs: u8,
    pub notify_sound_on: bool,
    pub chime: String,
    pub notify_prefs: std::collections::BTreeMap<String, crate::models::NotifyPref>,
    pub notify_custom_sounds: std::collections::BTreeMap<String, String>,
}

/// Trạng thái vòng đời cửa sổ Thông báo (không thuộc store — chỉ là plumbing).
#[derive(Default)]
pub struct NotifyState {
    ready: std::sync::atomic::AtomicBool,
    pending: std::sync::Mutex<Vec<NotifyItem>>,
}

const NOTIFY_PUSH_KINDS: [&str; 8] = ["focus_done", "break_done", "due_today", "overdue", "storage_error", "import_merged", "info", "error"];

fn truncate_chars(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

/// Tạo cửa sổ Thông báo nếu chưa có (frameless · trong suốt · always-on-top ·
/// không taskbar · không focus). Gọi từ async command — tạo webview trong
/// command đồng bộ trên Windows gây deadlock WebView2 (xem focus_open_timer).
pub async fn ensure_notify_window(app: &AppHandle) -> Result<(), String> {
    if app.get_webview_window("notify").is_some() {
        return Ok(());
    }
    tauri::WebviewWindowBuilder::new(app, "notify", tauri::WebviewUrl::App("notify.html".into()))
        .title("Taskora — Thông báo")
        .inner_size(376.0, 96.0)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .resizable(false)
        .skip_taskbar(true)
        .focused(false)
        .visible(false)
        .shadow(false)
        .build()
        .map(|_| ())
        .or_else(|e| {
            // race hai push cùng lúc — cửa sổ có thể vừa được tạo bởi lần gọi kia
            if app.get_webview_window("notify").is_some() { Ok(()) } else { Err(e.to_string()) }
        })
}

#[tauri::command]
pub async fn notify_push(
    app: AppHandle,
    state: State<'_, NotifyState>,
    kind: String,
    title: String,
    body: String,
    actions: Option<Vec<NotifyAction>>,
    sound: Option<String>,
) -> Result<(), String> {
    let silent = matches!(sound.as_deref(), Some("none"));
    let kind = if NOTIFY_PUSH_KINDS.contains(&kind.trim().to_lowercase().as_str()) {
        kind.trim().to_lowercase()
    } else {
        "info".to_string()
    };
    let actions = actions
        .unwrap_or_default()
        .into_iter()
        .take(4)
        .map(|a| NotifyAction { id: a.id, label: truncate_chars(a.label.trim(), 48) })
        .filter(|a| !a.label.is_empty())
        .collect();
    let item = NotifyItem { kind, title: truncate_chars(title.trim(), 140), body: truncate_chars(body.trim(), 320), actions, silent };
    // Nhiều push bất ngờ: mọi mục đều cũng được đẩy vào pending khi cửa sổ chưa sẵn sàng
    let fresh = app.get_webview_window("notify").is_some();
    if !fresh {
        // cửa sổ bị đóng/recreate → đánh dấu chưa sẵn sàng để instance mới drain pending
        state.ready.store(false, std::sync::atomic::Ordering::SeqCst);
        ensure_notify_window(&app).await?;
    }
    if state.ready.load(std::sync::atomic::Ordering::SeqCst) {
        let _ = app.emit("notify:arrival", item);
    } else {
        let mut pending = state.pending.lock().map_err(|e| e.to_string())?;
        if pending.len() >= 10 { pending.remove(0); }
        pending.push(item);
    }
    Ok(())
}

/// Cửa sổ Thông báo gọi sau khi đã gắn listener — xả pending (nếu có) và sẵn sàng nhận trực tiếp.
#[tauri::command]
pub fn notify_ready(app: AppHandle, state: State<'_, NotifyState>) -> Result<usize, String> {
    state.ready.store(true, std::sync::atomic::Ordering::SeqCst);
    let drained = std::mem::take(&mut *state.pending.lock().map_err(|e| e.to_string())?);
    let n = drained.len();
    for item in drained {
        let _ = app.emit("notify:arrival", item);
    }
    Ok(n)
}

/// Cửa sổ Thông báo báo chiều cao mới của chồng thẻ — Rust tự thu/phóng/ẩn cửa sổ,
/// neo đáy phải vùng làm việc (workArea) của màn hình chứa cửa sổ chính.
#[tauri::command]
pub fn notify_layout(app: AppHandle, height: f64) -> Result<(), String> {
    let Some(w) = app.get_webview_window("notify") else { return Ok(()) };
    let h = height.clamp(0.0, 480.0);
    if h < 24.0 {
        let _ = w.hide();
        return Ok(());
    }
    let main = app.get_webview_window("main");
    let monitor = main
        .as_ref()
        .and_then(|m| m.current_monitor().ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    let Some(m) = monitor else {
        // không lấy được màn hình — chỉ hiện, giữ vị trí cũ
        w.show().map_err(|e| e.to_string())?;
        return Ok(());
    };
    let scale = m.scale_factor();
    let wa = m.work_area();
    let wp = &wa.position; let ws = &wa.size;
    let w_phys = (376.0 * scale).round() as u32;
    let h_phys = (h * scale).round() as u32;
    let off = (14.0 * scale).round() as i32;
    let x = wp.x + ws.width as i32 - w_phys as i32 - off;
    let y = wp.y + ws.height as i32 - h_phys as i32 - off;
    w.set_size(tauri::Size::Physical(tauri::PhysicalSize::new(w_phys, h_phys))).map_err(|e| e.to_string())?;
    w.set_position(tauri::PhysicalPosition::new(x, y)).map_err(|e| e.to_string())?;
    w.show().map_err(|e| e.to_string())
}

/// Prefs + trạng thái theme mới nhất cho cửa sổ Thông báo (đọc tươi từ store mỗi lần).
#[tauri::command]
pub fn notify_prefs(state: State<'_, AppState>) -> NotifyPrefsPayload {
    let i = state.lock();
    let s = &i.store.settings;
    NotifyPrefsPayload {
        dark: s.dark,
        accent: s.accent.clone(),
        perf_mode: s.perf_mode,
        reduce_motion: s.reduce_motion,
        acrylic_alpha: s.acrylic_alpha,
        notify_enabled: s.notify_enabled,
        notify_autohide: s.notify_autohide,
        notify_hide_secs: s.notify_hide_secs,
        notify_sound_on: s.notify_sound_on,
        chime: s.chime.clone(),
        notify_prefs: s.notify_prefs.clone(),
        notify_custom_sounds: s.notify_custom_sounds.clone(),
    }
}

/// Nút hành động trong thẻ → main window nhận "notify:action" và chạy closure tương ứng (undo…).
#[tauri::command]
pub fn notify_action(app: AppHandle, id: u64) {
    let _ = app.emit("notify:action", serde_json::json!({ "id": id }));
}

/// Xóa mọi thẻ đang hiện (main window gọi khi reset cài đặt…).
#[tauri::command]
pub fn notify_clear(app: AppHandle) {
    let _ = app.emit("notify:clear", ());
}

#[tauri::command]
pub fn focus_open_main(app: AppHandle) -> Result<(), String> {
    if let Some(w) = app.get_webview_window("main") {
        w.set_focus().map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Phân tích xem trước (hiển thị chip gợi ý khi đang gõ).
#[derive(Serialize)]
pub struct Preview {
    pub title: String,
    pub due: Option<String>,
    pub tags: Vec<String>,
    pub priority: Option<String>,
    pub repeat: Option<String>,
    pub recurrence: Option<RecurrenceRule>,
}

#[tauri::command]
pub fn preview_parse(input: String) -> Preview {
    let p = parser::parse(input.trim(), today());
    Preview {
        title: p.title,
        due: p.due.map(|d| d.format("%d/%m/%Y").to_string()),
        tags: p.tags,
        priority: p.priority.map(|x| x.short().to_string()),
        repeat: p.repeat.map(|x| x.label().to_string()),
        recurrence: p.recurrence,
    }
}

// ------------------------------------------------------------------ lọc / xóa

#[tauri::command]
pub fn visible_ids(
    state: State<'_, AppState>,
    view: ViewWire,
    search: String,
    tag: Option<String>,
    prio: Option<Priority>,
    sort: SortMode,
    hide_completed: bool,
) -> Vec<u64> {
    let i = state.lock();
    i.store.visible(
        &View::from(view),
        &search,
        sort,
        hide_completed,
        tag.as_deref(),
        prio,
    )
}

// ------------------------------------------------------------------ chi tiết việc

#[tauri::command]
pub fn set_task_title(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    title: String,
) -> Snapshot {
    let title = title.trim().to_string();
    let mut i = state.lock();
    if !title.is_empty() {
        if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
            t.title = title;
        }
        AppState::commit(&mut i);
    }
    finish(&app, &mut i)
}

#[tauri::command]
pub fn set_task_notes(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    notes: String,
) -> Snapshot {
    let mut i = state.lock();
    if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
        t.notes = notes;
    }
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

/// Áp dụng rule mới (hoặc gỡ) cho một việc: clamp + validate + ghi shadow + gỡ rule hết hạn.
/// Dùng chung cho set_task_recurrence / set_task_repeat. Một đường duy nhất.
fn apply_recurrence(
    i: &mut Inner,
    id: u64,
    rule: Option<RecurrenceRule>,
) -> Result<Option<String>, String> {
    // validate TRƯỚC khi đụng undo stack / dữ liệu
    let rule = match rule {
        Some(r) => {
            let r = r.clamped();
            r.validate()?;
            Some(r)
        }
        None => None,
    };
    AppState::push_undo(i);
    if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
        match rule {
            Some(mut r) => {
                r.freeze_anchor(t.due);
                t.repeat = r.shadow();
                t.recurrence = Some(r);
            }
            None => {
                t.repeat = Repeat::None;
                t.recurrence = None;
            }
        }
    }
    let stripped = i.store.strip_exhausted_recurrences();
    Ok(stripped.into_iter().next())
}

#[tauri::command]
pub fn set_task_recurrence(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    rule: Option<RecurrenceRule>,
) -> Result<Snapshot, String> {
    let mut i = state.lock();
    let stripped = apply_recurrence(&mut i, id, rule)?;
    if let Some(title) = stripped {
        set_flash(&mut i, format!("Đã chuyển “{title}” thành việc thường (lặp đã hết hạn)"));
    } else {
        set_flash(&mut i, "Đã cập nhật lặp lại".to_string());
    }
    AppState::commit(&mut i);
    Ok(finish(&app, &mut i))
}

#[tauri::command]
pub fn skip_occurrence(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
) -> Result<Snapshot, String> {
    let mut i = state.lock();
    // validate trước khi push undo
    let (due, rule) = {
        let Some(t) = i.store.tasks.iter().find(|t| t.id == id) else {
            return Ok(finish(&app, &mut i));
        };
        let Some(rule) = t.recurrence.clone() else {
            return Err("Việc này không lặp lại".to_string());
        };
        (t.due, rule)
    };
    let base = due.unwrap_or_else(today).max(today());
    let Some(next) = next_after(&rule, base) else {
        return Err("Sắp hết lặp — không còn lần nào để bỏ qua".to_string());
    };
    AppState::push_undo(&mut i);
    if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
        t.due = Some(next);
    }
    set_flash(&mut i, format!("Đã bỏ qua — chuyển sang {}, {}", crate::models::weekday_name(next), next.format("%d/%m/%Y")));
    AppState::commit(&mut i);
    Ok(finish(&app, &mut i))
}

/// Lịch các occurrence sau `from` (ISO yyyy-mm-dd). Nguồn thuật toán DUY NHẤT (Rust) —
/// ghost calendar và hint đều dùng lệnh này, không mô phỏng bằng JS.
#[tauri::command]
pub fn preview_occurrences(
    rule: RecurrenceRule,
    from: Option<String>,
    max: Option<u32>,
) -> Result<Vec<String>, String> {
    let rule = rule.clamped();
    rule.validate()?;
    let from = from
        .as_deref()
        .and_then(|s| NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
        .unwrap_or_else(|| today().pred_opt().unwrap_or_else(today));
    let limit = max.unwrap_or(200).clamp(1, 200);
    Ok(occurrences_after(&rule, from, limit)
        .into_iter()
        .map(|d| d.format("%Y-%m-%d").to_string())
        .collect())
}

/// Occurrence kế tiếp (cho hint "lần tiếp theo: …").
#[tauri::command]
pub fn next_occurrence(rule: RecurrenceRule, from: Option<String>) -> Result<Option<String>, String> {
    let rule = rule.clamped();
    rule.validate()?;
    let from = from
        .as_deref()
        .and_then(|s| NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
        .unwrap_or_else(today);
    Ok(next_after(&rule, from).map(|d| d.format("%Y-%m-%d").to_string()))
}

#[tauri::command]
pub fn set_task_repeat(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    repeat: Repeat,
) -> Snapshot {
    let mut i = state.lock();
    // Đi qua đường recurrence (một đường duy nhất): legacy enum → rule tương đương.
    let due = i.store.tasks.iter().find(|t| t.id == id).and_then(|t| t.due);
    let rule = crate::models::rule_from_repeat(repeat, due);
    match apply_recurrence(&mut i, id, rule) {
        Ok(_) => {}
        Err(e) => set_flash(&mut i, e),
    }
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

#[tauri::command]
pub fn toggle_subtask(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    sid: u64,
) -> Snapshot {
    let mut i = state.lock();
    if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
        if let Some(s) = t.subtasks.iter_mut().find(|s| s.id == sid) {
            s.done = !s.done;
        }
    }
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

#[tauri::command]
pub fn set_subtask_title(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    sid: u64,
    title: String,
) -> Snapshot {
    let mut i = state.lock();
    if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
        if let Some(s) = t.subtasks.iter_mut().find(|s| s.id == sid) {
            s.title = title;
        }
    }
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

#[tauri::command]
pub fn remove_subtask(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    sid: u64,
) -> Snapshot {
    let mut i = state.lock();
    if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
        t.subtasks.retain(|s| s.id != sid);
    }
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

#[tauri::command]
pub fn add_task_tag(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    tag: String,
) -> Snapshot {
    let tag = tag.trim().trim_start_matches('#').to_lowercase();
    if tag.is_empty() {
        let mut i = state.lock();
        return finish(&app, &mut i);
    }
    let mut i = state.lock();
    AppState::push_undo(&mut i);
    if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
        if !t.tags.iter().any(|x| x == &tag) {
            t.tags.push(tag);
        }
    }
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

#[tauri::command]
pub fn remove_task_tag(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    tag: String,
) -> Snapshot {
    let mut i = state.lock();
    AppState::push_undo(&mut i);
    if let Some(t) = i.store.tasks.iter_mut().find(|t| t.id == id) {
        t.tags.retain(|x| x != &tag);
    }
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

// ------------------------------------------------------------------ undo/redo

#[tauri::command]
pub fn undo(app: AppHandle, state: State<'_, AppState>) -> Snapshot {
    let mut i = state.lock();
    if let Some(prev) = i.undo_stack.pop() {
        let cur = i.store.clone();
        i.redo_stack.push(cur);
        i.store = prev;
        set_flash(&mut i, "Đã hoàn tác");
        AppState::commit(&mut i);
    }
    finish(&app, &mut i)
}

#[tauri::command]
pub fn redo(app: AppHandle, state: State<'_, AppState>) -> Snapshot {
    let mut i = state.lock();
    if let Some(next) = i.redo_stack.pop() {
        let cur = i.store.clone();
        i.undo_stack.push(cur);
        i.store = next;
        set_flash(&mut i, "Đã làm lại");
        AppState::commit(&mut i);
    }
    finish(&app, &mut i)
}

// ------------------------------------------------------------------ cài đặt

#[tauri::command]
pub fn set_sort(
    app: AppHandle,
    state: State<'_, AppState>,
    mode: SortMode,
) -> Snapshot {
    let mut i = state.lock();
    i.store.settings.sort = mode;
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

#[tauri::command]
pub fn set_hide_completed(
    app: AppHandle,
    state: State<'_, AppState>,
    hide: bool,
) -> Snapshot {
    let mut i = state.lock();
    i.store.settings.hide_completed = hide;
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

#[tauri::command]
pub fn toggle_dark(app: AppHandle, state: State<'_, AppState>) -> Snapshot {
    let mut i = state.lock();
    i.store.settings.dark = !i.store.settings.dark;
    let msg = if i.store.settings.dark {
        "Đã bật giao diện tối"
    } else {
        "Đã bật giao diện sáng"
    };
    set_flash(&mut i, msg);
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

// ------------------------------------------------------------------ danh sách

#[tauri::command]
pub fn create_list(
    app: AppHandle,
    state: State<'_, AppState>,
    name: String,
    color_idx: usize,
) -> Snapshot {
    let name = name.trim().to_string();
    let mut i = state.lock();
    if name.is_empty() {
        return finish(&app, &mut i);
    }
    AppState::push_undo(&mut i);
    let id = i.store.new_id();
    let color = LIST_PALETTE[color_idx.min(LIST_PALETTE.len() - 1)];
    i.store.lists.push(crate::models::List { id, name, color });
    set_flash(&mut i, "Đã tạo danh sách");
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

#[tauri::command]
pub fn rename_list(
    app: AppHandle,
    state: State<'_, AppState>,
    id: u64,
    name: String,
    color_idx: usize,
) -> Snapshot {
    let name = name.trim().to_string();
    let mut i = state.lock();
    if name.is_empty() {
        return finish(&app, &mut i);
    }
    AppState::push_undo(&mut i);
    let color = LIST_PALETTE[color_idx.min(LIST_PALETTE.len() - 1)];
    if let Some(l) = i.store.lists.iter_mut().find(|l| l.id == id) {
        l.name = name;
        l.color = color;
    }
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

/// Xóa danh sách — việc trong danh sách trở về Hộp thư.
#[tauri::command]
pub fn delete_list(app: AppHandle, state: State<'_, AppState>, id: u64) -> Snapshot {
    let mut i = state.lock();
    AppState::push_undo(&mut i);
    for t in i.store.tasks.iter_mut() {
        if t.list_id == Some(id) {
            t.list_id = None;
        }
    }
    i.store.lists.retain(|l| l.id != id);
    set_flash(&mut i, "Đã xóa danh sách (việc về Hộp thư)");
    AppState::commit(&mut i);
    finish(&app, &mut i)
}

// ------------------------------------------------------------------ thống kê

#[tauri::command]
pub fn stats(state: State<'_, AppState>) -> StatsPayload {
    let i = state.lock();
    stats::compute(&i.store)
}

// ------------------------------------------------------------------ sao lưu

#[derive(Serialize)]
pub struct BackupInfo {
    pub name: String,
    pub size: u64,
    /// Ngày sửa đổi (yyyy-mm-dd HH:MM).
    pub modified: String,
}

#[tauri::command]
pub fn export_backup(state: State<'_, AppState>) -> Result<String, String> {
    let i = state.lock();
    let path = storage::export_backup(&i.store)?;
    Ok(path
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "taskora-backup.json".to_string()))
}

#[tauri::command]
pub fn list_backups() -> Vec<BackupInfo> {
    storage::list_backups()
        .into_iter()
        .map(|p| {
            let meta = std::fs::metadata(&p);
            let size = meta.as_ref().map(|m| m.len()).unwrap_or(0);
            let modified = meta
                .and_then(|m| m.modified())
                .map(|t| {
                    let dt: DateTime<Utc> = t.into();
                    dt.format("%Y-%m-%d %H:%M").to_string()
                })
                .unwrap_or_else(|_| "—".to_string());
            BackupInfo {
                name: p
                    .file_name()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_default(),
                size,
                modified,
            }
        })
        .collect()
}

#[tauri::command]
pub fn import_backup(
    app: AppHandle,
    state: State<'_, AppState>,
    name: String,
) -> Result<Snapshot, String> {
    if name.contains(['/', '\\']) || name.is_empty() {
        return Err("Tên bản sao lưu không hợp lệ".to_string());
    }
    let path = storage::backups_dir().join(&name);
    let mut i = state.lock();
    AppState::push_undo(&mut i);
    let mut st = storage::import_backup(&path)?;
    st.sanitize();
    i.store = st;
    set_flash(&mut i, "Đã khôi phục bản sao lưu");
    AppState::commit(&mut i);
    Ok(finish(&app, &mut i))
}

#[tauri::command]
pub fn open_data_dir() {
    storage::open_data_dir();
}

/// Lưu ngay lập tức (Ctrl+S).
#[tauri::command]
pub fn save_now(app: AppHandle, state: State<'_, AppState>) -> Snapshot {
    let i = state.lock();
    drop(i);
    state.flush();
    let mut i = state.lock();
    set_flash(&mut i, "Đã lưu ✓");
    finish(&app, &mut i)
}

// ------------------------------------------------------------------ cài đặt v2.1

/// Gói cập nhật cài đặt — mọi trường đều tùy chọn, thiếu = giữ nguyên.
#[derive(Deserialize, Default)]
#[serde(default)]
pub struct SettingsPatch {
    pub dark: Option<bool>,
    pub sort: Option<SortMode>,
    pub hide_completed: Option<bool>,
    pub transparent: Option<bool>,
    pub acrylic_alpha: Option<u8>,
    pub accent: Option<String>,
    pub reduce_motion: Option<bool>,
    pub qa_preview: Option<bool>,
    pub remind_today: Option<bool>,
    pub backup_on_exit: Option<bool>,
    pub perf_mode: Option<bool>,
    pub adhd_mode: Option<bool>,
    pub sound_on: Option<bool>,
    pub focus_min: Option<u32>,
    pub break_min: Option<u32>,
    pub long_break_min: Option<u32>,
    pub long_break_every: Option<u32>,
    pub auto_start_break: Option<bool>,
    pub auto_start_focus: Option<bool>,
    pub eye_reminder: Option<bool>,
    pub chime: Option<String>,
    pub focus_clock_display: Option<String>,
    pub notify_enabled: Option<bool>,
    pub notify_autohide: Option<bool>,
    pub notify_hide_secs: Option<u8>,
    pub notify_sound_on: Option<bool>,
    pub notify_prefs: Option<std::collections::BTreeMap<String, crate::models::NotifyPref>>,
    pub notify_custom_sounds: Option<std::collections::BTreeMap<String, String>>,
}

fn valid_accent(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 7 && b[0] == b'#' && b[1..].iter().all(|c| c.is_ascii_hexdigit())
}

#[tauri::command]
pub fn update_settings(
    app: AppHandle,
    state: State<'_, AppState>,
    patch: SettingsPatch,
) -> Snapshot {
    let mut i = state.lock();
    let new_transparent = patch.transparent.unwrap_or(i.store.settings.transparent);
    let new_alpha = patch.acrylic_alpha.unwrap_or(i.store.settings.acrylic_alpha);
    let effect_changed = new_transparent != i.store.settings.transparent
        || new_alpha != i.store.settings.acrylic_alpha;
    {
        let s = &mut i.store.settings;
        if let Some(v) = patch.dark { s.dark = v; }
        if let Some(v) = patch.sort { s.sort = v; }
        if let Some(v) = patch.hide_completed { s.hide_completed = v; }
        if let Some(v) = patch.transparent { s.transparent = v; }
        if let Some(v) = patch.acrylic_alpha { s.acrylic_alpha = v.clamp(40, 170); }
        if let Some(v) = patch.accent {
            let v = v.trim().to_lowercase();
            if valid_accent(&v) { s.accent = v; }
        }
        if let Some(v) = patch.reduce_motion { s.reduce_motion = v; }
        if let Some(v) = patch.qa_preview { s.qa_preview = v; }
        if let Some(v) = patch.remind_today { s.remind_today = v; }
        if let Some(v) = patch.backup_on_exit { s.backup_on_exit = v; }
        if let Some(v) = patch.perf_mode { s.perf_mode = v; }
        if let Some(v) = patch.adhd_mode { s.adhd_mode = v; }
        if let Some(v) = patch.sound_on { s.sound_on = v; }
        if let Some(v) = patch.focus_min { s.focus_min = v.clamp(5, 180); }
        if let Some(v) = patch.break_min { s.break_min = v.clamp(1, 60); }
        if let Some(v) = patch.long_break_min { s.long_break_min = v.clamp(5, 60); }
        if let Some(v) = patch.long_break_every { s.long_break_every = v.min(12); }
        if let Some(v) = patch.auto_start_break { s.auto_start_break = v; }
        if let Some(v) = patch.auto_start_focus { s.auto_start_focus = v; }
        if let Some(v) = patch.eye_reminder { s.eye_reminder = v; }
        if let Some(v) = patch.chime {
            let v = v.trim().to_lowercase();
            if matches!(v.as_str(), "soft" | "wind" | "none") { s.chime = v; }
        }
        if let Some(v) = patch.focus_clock_display {
            let v = v.trim().to_lowercase();
            if matches!(v.as_str(), "window" | "overlay" | "both") { s.focus_clock_display = Some(v); }
        }
        if let Some(v) = patch.notify_enabled { s.notify_enabled = v; }
        if let Some(v) = patch.notify_autohide { s.notify_autohide = v; }
        if let Some(v) = patch.notify_hide_secs {
            // chỉ nhận 3|5|8|10 — nắn về mốc gần nhất, ngoài mọi biên → 5
            let n = [3u8, 5, 8, 10];
            s.notify_hide_secs = *n.iter().min_by_key(|m| (**m as i32 - v as i32).abs()).unwrap_or(&5);
        }
        if let Some(v) = patch.notify_sound_on { s.notify_sound_on = v; }
        if let Some(v) = patch.notify_prefs {
            // chỉ nhận kind đã biết + sound hợp lệ — chống rác vào data.json
            const KINDS: [&str; 8] = ["focus_done", "break_done", "due_today", "overdue", "storage_error", "import_merged", "info", "error"];
            const SOUNDS: [&str; 5] = ["default", "soft", "wind", "none", "custom"];
            s.notify_prefs = v
                .into_iter()
                .filter(|(k, _)| KINDS.contains(&k.as_str()))
                .map(|(k, mut p)| {
                    let snd = p.sound.trim().to_lowercase();
                    p.sound = if SOUNDS.contains(&snd.as_str()) { snd } else { "default".into() };
                    (k, p)
                })
                .collect();
        }
        if let Some(v) = patch.notify_custom_sounds {
            // tối đa 4 âm tùy chỉnh, mỗi cái là data URI audio ≤ ~360k ký tự (≈ 256 KB)
            const KINDS: [&str; 8] = ["focus_done", "break_done", "due_today", "overdue", "storage_error", "import_merged", "info", "error"];
            let ok = v
                .into_iter()
                .filter(|(k, uri)| KINDS.contains(&k.as_str()) && uri.starts_with("data:audio/") && uri.len() <= 360_000)
                .take(4)
                .collect();
            s.notify_custom_sounds = ok;
        }
    }
    AppState::commit(&mut i);
    if effect_changed {
        if let Some(w) = app.get_webview_window("main") {
            let (t, a) = {
                let s = &i.store.settings;
                (s.transparent, s.acrylic_alpha)
            };
            if let Err(e) = crate::fx::apply_effect(&w, t, a) {
                eprintln!("[Taskora] Không đổi được hiệu ứng: {e}");
            }
        }
    }
    finish(&app, &mut i)
}

/// Đặt lại toàn bộ cài đặt về mặc định (giữ nguyên dữ liệu).
#[tauri::command]
pub fn reset_settings(app: AppHandle, state: State<'_, AppState>) -> Snapshot {
    let mut i = state.lock();
    i.store.settings = crate::models::Settings::default();
    AppState::commit(&mut i);
    if let Some(w) = app.get_webview_window("main") {
        if let Err(e) = crate::fx::apply_effect(&w, true, 110) {
            eprintln!("[Taskora] Không bật lại Acrylic: {e}");
        }
    }
    set_flash(&mut i, "Đã đặt lại cài đặt gốc");
    finish(&app, &mut i)
}

// ------------------------------------------------------------------ nơi lưu dữ liệu v2.2

#[derive(Serialize)]
pub struct StorageInfoView {
    /// "default" | "portable" | "custom"
    pub mode: String,
    pub dir: String,
    pub default_dir: String,
    pub exe_path: Option<String>,
    pub exe_dir_writable: bool,
    pub portable: bool,
    pub moved: bool,
    pub orphan_portable: Option<String>,
    pub legacy_dir: Option<String>,
    pub legacy_tasks: usize,
    pub legacy_lists: usize,
}

fn storage_info_view() -> StorageInfoView {
    let rep = crate::bootstrap::startup();
    let exe_dir_writable = rep
        .exe_path
        .as_deref()
        .and_then(|e| std::path::Path::new(e).parent().map(|d| d.to_path_buf()))
        .map(|d| crate::bootstrap::probe_writable(&d))
        .unwrap_or(false);
    let mode = match rep.mode {
        crate::bootstrap::Mode::Default => "default",
        crate::bootstrap::Mode::Portable => "portable",
        crate::bootstrap::Mode::Custom => "custom",
    }
    .to_string();
    let (legacy_dir, legacy_tasks, legacy_lists) = rep
        .legacy
        .clone()
        .map(|l| (Some(l.dir), l.tasks, l.lists))
        .unwrap_or((None, 0, 0));
    StorageInfoView {
        mode: mode.clone(),
        dir: rep.dir,
        default_dir: rep.default_dir,
        exe_path: rep.exe_path,
        exe_dir_writable,
        portable: mode == "portable",
        moved: rep.moved,
        orphan_portable: rep.orphan_portable,
        legacy_dir,
        legacy_tasks,
        legacy_lists,
    }
}

#[tauri::command]
pub fn storage_info() -> StorageInfoView {
    storage_info_view()
}

#[tauri::command]
pub fn storage_startup() -> StorageInfoView {
    storage_info_view()
}

#[derive(Serialize)]
pub struct StorageChangePayload {
    pub snapshot: Snapshot,
    pub info: StorageInfoView,
}

#[derive(Deserialize, Default)]
#[serde(default)]
pub struct StorageSwitchReq {
    /// "default" | "portable" | "custom"
    pub choice: String,
    pub custom_path: Option<String>,
    /// true = chuyển dữ liệu hiện tại sang; false = bắt đầu mới (trống)
    pub migrate: bool,
}

#[tauri::command]
pub fn storage_switch(
    app: AppHandle,
    state: State<'_, AppState>,
    req: StorageSwitchReq,
) -> Result<StorageChangePayload, String> {
    let mut i = state.lock();
    let old_dir = storage::data_dir();
    let portable = req.choice == "portable";
    let custom: Option<String> = if req.choice == "custom" {
        Some(req.custom_path.clone().unwrap_or_default())
    } else {
        None
    };
    let target = if portable {
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.to_path_buf()))
            .ok_or_else(|| "Không xác định được đường dẫn exe".to_string())?
    } else if let Some(c) = &custom {
        std::path::PathBuf::from(c)
    } else {
        crate::bootstrap::default_dir()
    };
    if target == old_dir {
        let snapshot = finish(&app, &mut i);
        return Ok(StorageChangePayload { snapshot, info: storage_info_view() });
    }
    if req.migrate {
        crate::bootstrap::move_data_into(&target)?;
    }
    crate::bootstrap::set_location(portable, custom.as_deref())?;
    i.store = if req.migrate {
        storage::load()
    } else {
        Store::default()
    };
    i.undo_stack.clear();
    i.redo_stack.clear();
    if req.migrate {
        set_flash(&mut i, "Đã chuyển dữ liệu sang thư mục mới");
    } else {
        set_flash(&mut i, "Đã bắt đầu với thư mục mới (trống)");
    }
    AppState::commit(&mut i);
    let snapshot = finish(&app, &mut i);
    Ok(StorageChangePayload { snapshot, info: storage_info_view() })
}

/// Gộp dữ liệu cũ ở %APPDATA% vào dữ liệu hiện tại (nơi đang dùng).
#[tauri::command]
pub fn storage_merge_legacy(
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<StorageChangePayload, String> {
    let mut i = state.lock();
    let default = crate::bootstrap::default_dir();
    if storage::data_dir() == default {
        return Err("Đang dùng thư mục mặc định — không có dữ liệu cũ để gộp.".to_string());
    }
    let raw = std::fs::read_to_string(default.join("data.json"))
        .map_err(|e| format!("Không đọc được dữ liệu cũ: {e}"))?;
    let legacy: Store =
        serde_json::from_str(&raw).map_err(|e| format!("Dữ liệu cũ không hợp lệ: {e}"))?;
    // sao lưu an toàn hai phía trước khi gộp
    let _ = storage::export_backup(&i.store);
    let bdir = storage::backups_dir();
    let _ = std::fs::create_dir_all(&bdir);
    let stash = bdir.join(format!(
        "legacy-{}.json",
        chrono::Local::now().format("%Y%m%d-%H%M%S")
    ));
    let _ = std::fs::copy(default.join("data.json"), &stash);
    let before = i.store.tasks.len();
    crate::bootstrap::merge_into(&mut i.store, &legacy);
    let added = i.store.tasks.len().saturating_sub(before);
    crate::bootstrap::dismiss("merge", &default.to_string_lossy());
    set_flash(&mut i, format!("Đã gộp {added} việc từ dữ liệu cũ"));
    AppState::commit(&mut i);
    let snapshot = finish(&app, &mut i);
    Ok(StorageChangePayload { snapshot, info: storage_info_view() })
}

/// Chuyển dữ liệu từ thư mục portable cũ (exe bị copy lẻ) vào nơi hiện tại.
#[tauri::command]
pub fn storage_import_orphan(
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<StorageChangePayload, String> {
    let mut i = state.lock();
    let rep = crate::bootstrap::startup();
    let src = rep
        .orphan_portable
        .clone()
        .ok_or_else(|| "Không tìm thấy thư mục portable cũ.".to_string())?;
    let src_path = std::path::PathBuf::from(&src);
    if storage::data_dir() == src_path {
        return Err("Đang dùng chính thư mục portable cũ.".to_string());
    }
    // đang trống ở nơi mới → sao chép nguyên vẹn (không cần gộp)
    crate::bootstrap::import_from(&src_path)?;
    i.store = storage::load();
    i.undo_stack.clear();
    i.redo_stack.clear();
    crate::bootstrap::dismiss("move", &src);
    set_flash(&mut i, "Đã chuyển dữ liệu portable sang vị trí mới");
    AppState::commit(&mut i);
    let snapshot = finish(&app, &mut i);
    Ok(StorageChangePayload { snapshot, info: storage_info_view() })
}

/// Bỏ qua lời nhắc (gộp / chuyển) vĩnh viễn.
#[tauri::command]
pub fn storage_dismiss(kind: String, src_dir: String) {
    crate::bootstrap::dismiss(&kind, &src_dir);
}

/// Ghi nhớ view đang mở (khôi phục lần sau).
#[tauri::command]
pub fn set_last_view(state: State<'_, AppState>, view: String) {
    let ok = matches!(
        view.as_str(),
        "inbox" | "today" | "upcoming" | "starred" | "completed" | "trash" | "stats" | "settings"
    ) || view.starts_with("list:");
    if !ok {
        return;
    }
    let mut i = state.lock();
    i.store.settings.last_view = view;
    AppState::commit(&mut i);
}


/// Trạng thái hiệu ứng cửa sổ gần nhất (chuỗi hiển thị trong Cài đặt).
#[tauri::command]
pub fn fx_status() -> String {
    let mut s = crate::fx::status();
    match crate::transparency::read() {
        Some(true) => s.push_str(" · Transparency effects: BẬT"),
        Some(false) => s.push_str(" · Transparency effects: TẮT"),
        None => s.push_str(" · Transparency effects: không đọc được"),
    }
    s
}

/// Báo cáo trạng thái công tắc Transparency effects của Windows.
#[derive(Serialize)]
pub struct TransparencyReport {
    /// Windows hay không (nơi công tắc này có ý nghĩa)
    pub supported: bool,
    /// true = BẬT · false = TẮT · null = không đọc được
    pub enabled: Option<bool>,
    /// App hiện có đang áp dụng trong suốt không
    pub acrylic: bool,
}

/// Đọc trạng thái Transparency effects (chỉ Windows có ý nghĩa).
#[tauri::command]
pub fn transparency_status(state: State<'_, AppState>) -> TransparencyReport {
    let enabled = crate::transparency::read();
    let acrylic = state.lock().store.settings.transparent;
    TransparencyReport {
        supported: cfg!(windows),
        enabled,
        acrylic,
    }
}

/// Bật/tắt công tắc Transparency effects của Windows (toàn tài khoản hiện tại).
///
/// Hành vi khi TẮT (đúng yêu cầu sản phẩm): app bắt buộc rời chế độ Trong suốt —
/// không được giữ "trong suốt" khi điều kiện hệ thống không còn được đảm bảo.
/// Khi BẬT lại: nếu cài đặt Trong suốt đang bật thì áp lại acrylic ngay.
#[tauri::command]
pub fn set_transparency(
    app: AppHandle,
    state: State<'_, AppState>,
    on: bool,
) -> Result<Snapshot, String> {
    #[cfg(windows)]
    {
        crate::transparency::set(on)?;
    }
    #[cfg(not(windows))]
    {
        let _ = on;
        return Err("Chỉ hỗ trợ trên Windows".to_string());
    }
    let mut i = state.lock();
    if !on && i.store.settings.transparent {
        i.store.settings.transparent = false;
        AppState::commit(&mut i);
        if let Some(w) = app.get_webview_window("main") {
            let _ = crate::fx::apply_effect(&w, false, i.store.settings.acrylic_alpha);
        }
        set_flash(&mut i, "Đã tắt Transparency effects — Taskora chuyển nền đặc");
    } else if on && i.store.settings.transparent {
        let a = i.store.settings.acrylic_alpha;
        if let Some(w) = app.get_webview_window("main") {
            let _ = crate::fx::apply_effect(&w, true, a);
        }
    }
    Ok(finish(&app, &mut i))
}
