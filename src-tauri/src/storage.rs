//! Lưu / nạp dữ liệu JSON vào thư mục người dùng, xuất–nhập bản sao lưu.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::Local;

use crate::models::Store;

pub const APP_DIR_NAME: &str = "Taskora";

fn err(e: std::io::Error) -> String {
    e.to_string()
}

/// `%APPDATA%\Taskora` trên Windows, `~/.local/taskora` trên hệ thống khác.
pub fn data_dir() -> PathBuf {
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local").join("share"))
        })
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(APP_DIR_NAME)
}

pub fn data_file() -> PathBuf {
    data_dir().join("data.json")
}

pub fn backups_dir() -> PathBuf {
    data_dir().join("backups")
}

/// Ghi đè file dữ liệu chính (ghi tạm rồi đổi tên để tránh hỏng giữa chừng).
pub fn save(store: &Store) -> Result<(), String> {
    let dir = data_dir();
    fs::create_dir_all(&dir).map_err(err)?;
    let json = serde_json::to_string_pretty(store).map_err(|e| e.to_string())?;
    let tmp = dir.join("data.json.tmp");
    let dst = dir.join("data.json");
    fs::write(&tmp, json).map_err(err)?;
    let _ = fs::remove_file(&dst);
    fs::rename(&tmp, &dst).map_err(err)
}

/// Nạp dữ liệu; lỗi hoặc thiếu file → dữ liệu mẫu.
pub fn load() -> Store {
    match fs::read_to_string(data_file()) {
        Ok(s) => match serde_json::from_str::<Store>(&s) {
            Ok(mut st) => {
                st.sanitize();
                st
            }
            Err(_) => Store::seed(),
        },
        Err(_) => Store::seed(),
    }
}

/// Xuất một bản sao lưu có timestamp.
pub fn export_backup(store: &Store) -> Result<PathBuf, String> {
    let dir = backups_dir();
    fs::create_dir_all(&dir).map_err(err)?;
    let name = format!("taskora-{}.json", Local::now().format("%Y%m%d-%H%M%S"));
    let path = dir.join(name);
    let json = serde_json::to_string_pretty(store).map_err(|e| e.to_string())?;
    fs::write(&path, json).map_err(err)?;
    Ok(path)
}

/// Liệt kê bản sao lưu, mới nhất trước.
pub fn list_backups() -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir(backups_dir()) {
        for e in rd.flatten() {
            let p = e.path();
            if p.extension().map(|x| x == "json").unwrap_or(false) {
                out.push(p);
            }
        }
    }
    out.sort();
    out.reverse();
    out
}

/// Nhập một file sao lưu.
pub fn import_backup(path: &Path) -> Result<Store, String> {
    let s = fs::read_to_string(path).map_err(err)?;
    let mut st: Store = serde_json::from_str(&s).map_err(|e| e.to_string())?;
    st.sanitize();
    Ok(st)
}

/// Mở thư mục dữ liệu bằng trình quản lý tệp của hệ điều hành.
pub fn open_data_dir() {
    let dir = data_dir();
    let _ = fs::create_dir_all(&dir);
    #[cfg(windows)]
    let _ = std::process::Command::new("explorer").arg(&dir).spawn();
    #[cfg(not(windows))]
    let _ = std::process::Command::new("xdg-open").arg(&dir).spawn();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn export_import_roundtrip() {
        let store = Store::seed();
        let dir = backups_dir();
        fs::create_dir_all(&dir).unwrap();
        let path = export_backup(&store).unwrap();
        let back = import_backup(&path).unwrap();
        assert_eq!(store.tasks.len(), back.tasks.len());
        assert_eq!(store.lists, back.lists);
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn load_does_not_panic() {
        let _ = load();
    }
}
