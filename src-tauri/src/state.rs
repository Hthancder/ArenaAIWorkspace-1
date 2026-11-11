//! Trạng thái ứng dụng: store + undo/redo + lưu tự động.

use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

use serde::Serialize;

use crate::models::{today, Store};
use crate::storage;

/// Bảng màu danh sách (đồng bộ với UI chọn màu).
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

pub struct Inner {
    pub store: Store,
    pub undo_stack: Vec<Store>,
    pub redo_stack: Vec<Store>,
    pub last_saved: Instant,
    pub dirty: bool,
    pub flash: Option<String>,
    /// Id việc vừa thêm (frontend tự chọn khi nhận snapshot).
    pub last_added: Option<u64>,
}

pub struct AppState {
    inner: Mutex<Inner>,
}

fn flush_inner(i: &mut Inner) {
    if !i.dirty {
        return;
    }
    match storage::save(&i.store) {
        Ok(_) => {
            i.dirty = false;
            i.last_saved = Instant::now();
        }
        Err(e) => {
            eprintln!("[Taskora] Lưu dữ liệu thất bại: {e}");
        }
    }
}

/// Dữ liệu đẩy về frontend sau mỗi thay đổi.
#[derive(Serialize)]
pub struct Snapshot {
    pub tasks: Vec<crate::models::Task>,
    pub lists: Vec<crate::models::List>,
    pub settings: crate::models::Settings,
    pub counts: crate::models::Counts,
    pub today: String,
    pub undo_len: usize,
    pub redo_len: usize,
    pub flash: Option<String>,
    pub last_added: Option<u64>,
    pub step_presets: Vec<crate::models::StepPreset>,
}

impl AppState {
    pub fn new() -> Self {
        let store = storage::load();
        Self {
            inner: Mutex::new(Inner {
                store,
                undo_stack: Vec::new(),
                redo_stack: Vec::new(),
                last_saved: Instant::now(),
                dirty: false,
                flash: None,
                last_added: None,
            }),
        }
    }

    pub fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Đánh dấu "cần lưu"; lưu ngay nếu đã đủ 800ms từ lần lưu trước.
    pub fn commit(i: &mut Inner) {
        i.dirty = true;
        if i.last_saved.elapsed() >= Duration::from_millis(800) {
            flush_inner(i);
        }
    }

    /// Lưu ngay lập tức (lúc đóng app).
    pub fn flush(&self) {
        flush_inner(&mut self.lock());
    }

    pub fn push_undo(i: &mut Inner) {
        i.undo_stack.push(i.store.clone());
        if i.undo_stack.len() > 80 {
            i.undo_stack.remove(0);
        }
        i.redo_stack.clear();
    }
}

/// Snapshot từ inner (flash/last_added chỉ tiêu thụ một lần).
pub fn make_snapshot(i: &mut Inner) -> Snapshot {
    let counts = i.store.counts(today());
    Snapshot {
        tasks: i.store.tasks.clone(),
        lists: i.store.lists.clone(),
        settings: i.store.settings.clone(),
        counts,
        today: today().format("%Y-%m-%d").to_string(),
        undo_len: i.undo_stack.len(),
        redo_len: i.redo_stack.len(),
        flash: i.flash.take(),
        last_added: i.last_added.take(),
        step_presets: i.store.step_presets.clone(),
    }
}
