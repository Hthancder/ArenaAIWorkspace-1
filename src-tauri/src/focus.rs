//! Focus engine — nguồn sự thật duy nhất cho phiên tập trung.
//!
//! Thời gian tính theo **wall-clock** (`ends_at_ms`), không đếm lùi bằng bộ đếm —
//! nhờ vậy overlay trong app chính và cửa sổ Đồng hồ (mini window) luôn khớp nhau,
//! kể cả khi cửa sổ bị minimize hoặc máy ngủ (sleep) giữa chừng.
//!
//! State nằm ở `state::Inner` dưới dạng runtime (KHÔNG serialize vào data.json):
//! đóng app là phiên tắt — đây là hành vi mong muốn.

use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;

use crate::models::{today, TaskId};
use crate::state::Inner;

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FocusMode {
    Focus,
    BreakShort,
    BreakLong,
}

impl FocusMode {
    pub fn is_break(self) -> bool {
        !matches!(self, FocusMode::Focus)
    }
}

#[derive(Debug, Clone)]
pub struct FocusState {
    pub active: bool,
    pub mode: FocusMode,
    pub task_id: Option<TaskId>,
    pub task_title: String,
    pub total_secs: u64,
    pub remaining_secs: u64,
    /// `Some(ends_at)` khi đồng hồ đang chạy; `None` khi tạm dừng / đã xong.
    pub ends_at_ms: Option<i64>,
    pub paused: bool,
    pub phase_done: bool,
    /// Số phiên focus đã hoàn thành trong lần mở app này (chu kỳ nghỉ dài).
    pub cycle_count: u32,
    pub started_at_ms: i64,
    /// Runtime: cửa sổ Đồng hồ đang được ghim "luôn nổi".
    pub timer_pinned: bool,
}

impl Default for FocusState {
    fn default() -> Self {
        Self {
            active: false,
            mode: FocusMode::Focus,
            task_id: None,
            task_title: String::new(),
            total_secs: 25 * 60,
            remaining_secs: 25 * 60,
            ends_at_ms: None,
            paused: false,
            phase_done: false,
            cycle_count: 0,
            started_at_ms: 0,
            timer_pinned: true,
        }
    }
}

/// Payload chung cho event `focus:change` và trả về trực tiếp từ commands.
/// `transitioned` = lệnh này vừa gây chuyển phase (chỉ cửa sổ gọi lệnh thấy `true`) —
/// dùng để tránh chuông/log đúp khi cả hai cửa sổ cùng thấy 0.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FocusPayload {
    pub active: bool,
    pub mode: FocusMode,
    pub task_id: Option<TaskId>,
    pub task_title: String,
    pub total_secs: u64,
    pub ends_at_ms: Option<i64>,
    pub remaining_secs: u64,
    pub paused: bool,
    pub phase_done: bool,
    pub cycle_count: u32,
    /// Phiên nghỉ kế tiếp là nghỉ dài (sau mỗi `long_break_every` phiên focus).
    pub next_break_long: bool,
    /// `true` chỉ với lệnh vừa gây chuyển phase.
    pub transitioned: bool,
    /// `true` khi lần chuyển phase này vừa GHI nhận một phiên focus vào thống kê.
    pub completed_focus: bool,
    pub sound_on: bool,
    pub chime: String,
    pub focus_min: u32,
    pub break_min: u32,
    pub long_break_min: u32,
}

pub fn next_break_long(cycle_count: u32, long_break_every: u32) -> bool {
    long_break_every > 0 && cycle_count > 0 && cycle_count % long_break_every == 0
}

fn current_remaining(f: &FocusState, now: i64) -> u64 {
    match f.ends_at_ms {
        Some(ends) => {
            let ms = ends.saturating_sub(now).max(0) as u64;
            // ceil để 1500ms hiển thị "2" (không cắt sớm thành 0/1)
            ms.div_ceil(1000)
        }
        None => f.remaining_secs,
    }
}

pub fn payload(i: &Inner, transitioned: bool, completed_focus: bool) -> FocusPayload {
    let now = now_ms();
    let f = &i.focus;
    let s = &i.store.settings;
    FocusPayload {
        active: f.active,
        mode: f.mode,
        task_id: f.task_id,
        task_title: f.task_title.clone(),
        total_secs: f.total_secs,
        ends_at_ms: f.ends_at_ms,
        remaining_secs: current_remaining(f, now),
        paused: f.paused,
        phase_done: f.phase_done,
        cycle_count: f.cycle_count,
        next_break_long: next_break_long(f.cycle_count, s.long_break_every),
        transitioned,
        completed_focus,
        sound_on: s.sound_on,
        chime: s.chime.clone(),
        focus_min: s.focus_min,
        break_min: s.break_min,
        long_break_min: s.long_break_min,
    }
}

/// Bắt đầu phiên focus mới (thay thế phiên đang chạy nếu có). Giữ `cycle_count`.
pub fn start(i: &mut Inner, task_id: Option<TaskId>, task_title: String) {
    let total = i.store.settings.focus_min.max(5) as u64 * 60;
    let now = now_ms();
    let cycle = i.focus.cycle_count;
    let pinned = i.focus.timer_pinned;
    i.focus = FocusState {
        active: true,
        mode: FocusMode::Focus,
        task_id,
        task_title,
        total_secs: total,
        remaining_secs: total,
        ends_at_ms: Some(now + total as i64 * 1000),
        paused: false,
        phase_done: false,
        cycle_count: cycle,
        started_at_ms: now,
        timer_pinned: pinned,
    };
}

pub fn pause_toggle(i: &mut Inner) -> FocusPayload {
    let now = now_ms();
    {
        let f = &mut i.focus;
        if f.active && !f.phase_done {
            if f.paused {
                f.ends_at_ms = Some(now + f.remaining_secs as i64 * 1000);
                f.paused = false;
            } else {
                f.remaining_secs = current_remaining(f, now);
                f.ends_at_ms = None;
                f.paused = true;
            }
        }
    }
    payload(i, false, false)
}

/// "Bắt đầu lại" — về đầy đồng hồ, giữ việc + chế độ + chu kỳ + trạng thái tạm dừng.
/// Không ghi nhận phiên nào. Bấm ở màn "xong" = chạy lại phiên mới ngay.
pub fn reset(i: &mut Inner) -> FocusPayload {
    let now = now_ms();
    {
        let f = &mut i.focus;
        if f.active {
            f.remaining_secs = f.total_secs;
            f.phase_done = false;
            f.ends_at_ms = if f.paused {
                None
            } else {
                Some(now + f.total_secs as i64 * 1000)
            };
        }
    }
    payload(i, false, false)
}

/// Dừng hẳn phiên (overlay đóng ở mọi cửa sổ qua event).
pub fn stop(i: &mut Inner) {
    let cycle = i.focus.cycle_count;
    let pinned = i.focus.timer_pinned;
    i.focus = FocusState::default();
    i.focus.cycle_count = cycle;
    i.focus.timer_pinned = pinned;
}

/// Đồng hồ về 0 → chuyển phase. Idempotent: chỉ lời gọi đầu tiên (đúng giờ) mới chuyển;
/// các cửa sổ khác thấy trạng thái đã chuyển và trả về `transitioned: false`.
pub fn complete(i: &mut Inner) -> FocusPayload {
    let now = now_ms();
    let is_due = {
        let f = &i.focus;
        f.active && !f.phase_done && f.ends_at_ms.map(|e| now >= e).unwrap_or(false)
    };
    if !is_due {
        return payload(i, false, false);
    }
    let was_focus = i.focus.mode == FocusMode::Focus;
    let mut auto_start_break = false;
    let mut auto_start_focus = false;
    if was_focus {
        let key = today().format("%Y-%m-%d").to_string();
        *i.store.focus_days.entry(key).or_insert(0) += 1;
        i.focus.cycle_count += 1;
        auto_start_break = i.store.settings.auto_start_break;
    } else {
        // Nghỉ xong → tự bắt đầu lại cùng việc (chỉ khi việc vẫn còn tồn tại)
        let task_ok = i
            .focus
            .task_id
            .and_then(|id| i.store.tasks.iter().find(|t| t.id == id))
            .map(|t| !t.is_deleted() && !t.is_completed())
            .unwrap_or(false);
        auto_start_focus = i.store.settings.auto_start_focus && task_ok;
    }

    if was_focus && auto_start_break {
        let settings = &i.store.settings;
        let long = next_break_long(i.focus.cycle_count, settings.long_break_every);
        let (mode, mins) = if long {
            (FocusMode::BreakLong, settings.long_break_min)
        } else {
            (FocusMode::BreakShort, settings.break_min)
        };
        let total = mins.max(1) as u64 * 60;
        let f = &mut i.focus;
        f.mode = mode;
        f.total_secs = total;
        f.remaining_secs = total;
        f.ends_at_ms = Some(now + total as i64 * 1000);
        f.paused = false;
        f.phase_done = false;
        return payload(i, true, true);
    }
    if !was_focus && auto_start_focus {
        let total = i.store.settings.focus_min.max(5) as u64 * 60;
        let f = &mut i.focus;
        f.mode = FocusMode::Focus;
        f.total_secs = total;
        f.remaining_secs = total;
        f.ends_at_ms = Some(now + total as i64 * 1000);
        f.paused = false;
        f.phase_done = false;
        return payload(i, true, false);
    }
    {
        let f = &mut i.focus;
        f.phase_done = true;
        f.ends_at_ms = None;
        f.remaining_secs = 0;
        f.paused = true;
    }
    payload(i, true, was_focus)
}

/// Người dùng bấm "Nghỉ…" ở màn hoàn thành phiên focus.
pub fn break_start(i: &mut Inner) -> FocusPayload {
    let now = now_ms();
    let valid = {
        let f = &i.focus;
        f.active && f.phase_done && f.mode == FocusMode::Focus
    };
    if valid {
        let settings = &i.store.settings;
        let long = next_break_long(i.focus.cycle_count, settings.long_break_every);
        let (mode, mins) = if long {
            (FocusMode::BreakLong, settings.long_break_min)
        } else {
            (FocusMode::BreakShort, settings.break_min)
        };
        let total = mins.max(1) as u64 * 60;
        let f = &mut i.focus;
        f.mode = mode;
        f.total_secs = total;
        f.remaining_secs = total;
        f.ends_at_ms = Some(now + total as i64 * 1000);
        f.paused = false;
        f.phase_done = false;
    }
    payload(i, false, false)
}

pub fn timer_pin_toggle(i: &mut Inner) -> bool {
    i.focus.timer_pinned = !i.focus.timer_pinned;
    i.focus.timer_pinned
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::Store;
    use crate::state::Inner;
    use std::time::Instant;

    fn test_inner() -> Inner {
        Inner {
            store: Store::default(),
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            last_saved: Instant::now(),
            dirty: false,
            flash: None,
            last_added: None,
            focus: FocusState::default(),
        }
    }

    #[test]
    fn focus_start_uses_settings_duration() {
        let mut i = test_inner();
        i.store.settings.focus_min = 45;
        start(&mut i, Some(7), "Viết báo cáo".to_string());
        assert!(i.focus.active);
        assert_eq!(i.focus.total_secs, 45 * 60);
        assert_eq!(i.focus.remaining_secs, 45 * 60);
        assert!(i.focus.ends_at_ms.is_some());
        assert!(!i.focus.paused);
    }

    #[test]
    fn pause_resume_math_roundtrip() {
        let mut i = test_inner();
        start(&mut i, None, "x".to_string());
        let p1 = pause_toggle(&mut i);
        assert!(p1.paused);
        assert!(p1.ends_at_ms.is_none());
        let remaining = p1.remaining_secs;
        let p2 = pause_toggle(&mut i);
        assert!(!p2.paused);
        assert_eq!(p2.remaining_secs, remaining);
    }

    #[test]
    fn reset_restores_full_and_keeps_pause() {
        let mut i = test_inner();
        i.store.settings.focus_min = 20;
        start(&mut i, None, "x".to_string());
        pause_toggle(&mut i);
        let p = reset(&mut i);
        assert_eq!(p.remaining_secs, 20 * 60);
        assert!(p.paused);
        assert!(p.ends_at_ms.is_none());
        assert!(!p.phase_done);
        // Không ghi nhận phiên nào
        assert!(i.store.focus_days.is_empty());
    }

    #[test]
    fn complete_is_idempotent_and_logs_once() {
        let mut i = test_inner();
        start(&mut i, None, "x".to_string());
        // Giả lập hết giờ
        i.focus.ends_at_ms = Some(now_ms() - 1000);
        let p1 = complete(&mut i);
        assert!(p1.transitioned);
        assert!(p1.completed_focus);
        assert!(p1.phase_done);
        assert_eq!(i.store.focus_days.values().sum::<u64>(), 1);
        assert_eq!(i.focus.cycle_count, 1);
        let p2 = complete(&mut i);
        assert!(!p2.transitioned);
        assert_eq!(i.store.focus_days.values().sum::<u64>(), 1);
    }

    #[test]
    fn every_fourth_session_is_long_break() {
        let mut i = test_inner();
        i.store.settings.long_break_every = 4;
        i.focus.cycle_count = 3; // đã xong 3 phiên
        start(&mut i, None, "x".to_string());
        i.focus.ends_at_ms = Some(now_ms() - 1);
        let p = complete(&mut i);
        assert_eq!(p.cycle_count, 4);
        assert!(p.next_break_long);
        let p2 = break_start(&mut i);
        assert_eq!(p2.mode, FocusMode::BreakLong);
        assert_eq!(p2.total_secs, i.store.settings.long_break_min as u64 * 60);
    }

    #[test]
    fn long_break_every_zero_disables_long_breaks() {
        let mut i = test_inner();
        i.store.settings.long_break_every = 0;
        i.focus.cycle_count = 7;
        assert!(!next_break_long(i.focus.cycle_count, 0));
        start(&mut i, None, "x".to_string());
        i.focus.ends_at_ms = Some(now_ms() - 1);
        complete(&mut i);
        let p = break_start(&mut i);
        assert_eq!(p.mode, FocusMode::BreakShort);
    }

    #[test]
    fn auto_start_break_transitions_immediately() {
        let mut i = test_inner();
        i.store.settings.auto_start_break = true;
        i.store.settings.long_break_every = 2;
        i.focus.cycle_count = 1;
        start(&mut i, None, "x".to_string());
        i.focus.ends_at_ms = Some(now_ms() - 1);
        let p = complete(&mut i);
        assert!(p.transitioned);
        // cycle 1 → 2; 2 % 2 == 0 → phiên nghỉ kế là nghỉ dài
        assert_eq!(p.mode, FocusMode::BreakLong);
        assert!(p.next_break_long);
    }

    #[test]
    fn stop_keeps_cycle_but_clears_session() {
        let mut i = test_inner();
        i.focus.cycle_count = 5;
        start(&mut i, None, "x".to_string());
        stop(&mut i);
        assert!(!i.focus.active);
        assert_eq!(i.focus.cycle_count, 5);
    }
}
