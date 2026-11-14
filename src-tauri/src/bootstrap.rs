//! Xác định nơi lưu dữ liệu: portable (cạnh exe) / tùy chỉnh / %APPDATA%.
//! - `portable.txt` cạnh file thực thi  → mọi dữ liệu nằm cạnh exe.
//! - `custom_dir` trong bootstrap.json  → thư mục người dùng tự chọn.
//! - Không có gì → mặc định `%APPDATA%\Taskora`.
//! bootstrap.json luôn nằm ở mặc định (nhỏ, chỉ giữ con trỏ + cờ đã hỏi).

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{OnceLock, RwLock};

use serde::Serialize;

use crate::models::Store;

pub const APP_DIR_NAME: &str = "Taskora";
pub const PORTABLE_MARKER: &str = "portable.txt";
const BOOTSTRAP_FILE: &str = "bootstrap.json";
const DATA_FILE: &str = "data.json";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Mode {
    Default,
    Portable,
    Custom,
}

#[derive(Debug, Clone, Default, serde::Deserialize, Serialize)]
struct Bootstrap {
    #[serde(default)]
    custom_dir: Option<String>,
    #[serde(default)]
    last_exe: Option<String>,
    #[serde(default)]
    last_portable_dir: Option<String>,
    /// Các lời nhắc đã bỏ qua vĩnh viễn ("merge|dir|mtime" / "move|dir|mtime").
    #[serde(default)]
    dismissed: Vec<String>,
}

#[derive(Debug, Clone)]
struct Resolved {
    mode: Mode,
    dir: PathBuf,
}

static STARTUP: OnceLock<StartupReport> = OnceLock::new();
static ACTIVE: OnceLock<RwLock<Resolved>> = OnceLock::new();

#[derive(Debug, Clone, Serialize)]
pub struct LegacyRef {
    pub dir: String,
    pub tasks: usize,
    pub lists: usize,
}

/// Báo cáo một lần lúc khởi động (dùng cho lời nhắc gộp/chuyển dữ liệu).
#[derive(Debug, Clone, Serialize)]
pub struct StartupReport {
    pub mode: Mode,
    pub dir: String,
    pub default_dir: String,
    pub exe_path: Option<String>,
    /// exe đã đổi vị trí so với lần chạy trước (portable).
    pub moved: bool,
    /// Thư mục portable cũ vẫn còn data.json còn thư mục hiện tại trống
    /// (người dùng copy lẻ Taskora.exe ra chỗ khác) → hỏi chuyển.
    pub orphan_portable: Option<String>,
    /// Đang chạy ở nơi khác (custom/portable) nhưng %APPDATA% còn dữ liệu cũ → hỏi gộp.
    pub legacy: Option<LegacyRef>,
}

fn exe_path() -> Option<PathBuf> {
    std::env::current_exe().ok()
}

fn exe_dir() -> Option<PathBuf> {
    exe_path().and_then(|p| p.parent().map(|d| d.to_path_buf()))
}

pub fn default_dir() -> PathBuf {
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local").join("share")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(APP_DIR_NAME)
}

fn bootstrap_path() -> PathBuf {
    default_dir().join(BOOTSTRAP_FILE)
}

fn read_bootstrap() -> Bootstrap {
    fs::read_to_string(bootstrap_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn write_bootstrap(b: &Bootstrap) {
    let _ = fs::create_dir_all(default_dir());
    if let Ok(js) = serde_json::to_string_pretty(b) {
        let _ = fs::write(bootstrap_path(), js);
    }
}

fn update_bootstrap(f: impl FnOnce(&mut Bootstrap)) {
    let mut b = read_bootstrap();
    f(&mut b);
    if b.dismissed.len() > 32 {
        let keep = b.dismissed.split_off(b.dismissed.len() - 32);
        b.dismissed = keep;
    }
    write_bootstrap(&b);
}

pub fn probe_writable(dir: &Path) -> bool {
    if fs::create_dir_all(dir).is_err() {
        return false;
    }
    let probe = dir.join(format!(".taskora-probe-{}", std::process::id()));
    match fs::write(&probe, b"ok") {
        Ok(_) => {
            let _ = fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

fn resolve(boot: &Bootstrap) -> Resolved {
    if let Some(exe) = exe_dir() {
        if exe.join(PORTABLE_MARKER).exists() {
            return Resolved { mode: Mode::Portable, dir: exe };
        }
    }
    if let Some(c) = boot.custom_dir.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        let p = PathBuf::from(c);
        if probe_writable(&p) {
            return Resolved { mode: Mode::Custom, dir: p };
        }
    }
    Resolved { mode: Mode::Default, dir: default_dir() }
}

fn fingerprint(kind: &str, src: &Path) -> String {
    let mtime = fs::metadata(src.join(DATA_FILE))
        .ok()
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{kind}|{}|{mtime}", src.to_string_lossy())
}

fn peek_store(path: &Path) -> Option<(usize, usize)> {
    let s = fs::read_to_string(path.join(DATA_FILE)).ok()?;
    let st: Store = serde_json::from_str(&s).ok()?;
    Some((st.tasks.len(), st.lists.len()))
}

fn is_dismissed(boot: &Bootstrap, kind: &str, src: &Path) -> bool {
    boot.dismissed.iter().any(|d| d == &fingerprint(kind, src))
}

/// Gọi MỘT lần lúc khởi động trước khi nạp dữ liệu.
pub fn init() {
    let boot = read_bootstrap();
    let res = resolve(&boot);
    let default = default_dir();
    let exe = exe_path().map(|p| p.to_string_lossy().to_string());

    let mut report = StartupReport {
        mode: res.mode,
        dir: res.dir.to_string_lossy().to_string(),
        default_dir: default.to_string_lossy().to_string(),
        exe_path: exe.clone(),
        moved: false,
        orphan_portable: None,
        legacy: None,
    };

    // 1) portable: exe đã đổi vị trí so với lần chạy trước
    if res.mode == Mode::Portable {
        if let Some(e) = &exe {
            if boot.last_exe.as_deref() != Some(e.as_str()) {
                report.moved = true;
            }
        }
    }

    // 2) exe portable bị copy lẻ ra chỗ trống: hiện tại không có data.json,
    //    thư mục portable cũ còn nguyên → hỏi chuyển.
    if !res.dir.join(DATA_FILE).exists() {
        if let Some(src) = boot.last_portable_dir.as_deref().map(str::trim) {
            if !src.is_empty() {
                let p = PathBuf::from(src);
                if p != res.dir
                    && p.join(DATA_FILE).exists()
                    && !is_dismissed(&boot, "move", &p)
                {
                    report.orphan_portable = Some(src.to_string());
                }
            }
        }
    }

    // 3) đang chạy ở custom/portable mà %APPDATA% còn dữ liệu cũ → hỏi gộp.
    if res.dir != default && default.join(DATA_FILE).exists() && !is_dismissed(&boot, "merge", &default) {
        if let Some((tasks, lists)) = peek_store(&default) {
            if tasks > 0 || lists > 0 {
                report.legacy = Some(LegacyRef {
                    dir: default.to_string_lossy().to_string(),
                    tasks,
                    lists,
                });
            }
        }
    }

    // ghi nhớ vị trí hiện tại (luôn, kể cả khi không portable)
    update_bootstrap(|b| {
        b.last_exe = exe;
        if res.mode == Mode::Portable {
            b.last_portable_dir = Some(res.dir.to_string_lossy().to_string());
        }
    });

    let _ = STARTUP.set(report);
    let _ = ACTIVE.set(RwLock::new(res));
}

pub fn startup() -> StartupReport {
    STARTUP
        .get()
        .cloned()
        .unwrap_or_else(|| StartupReport {
            mode: Mode::Default,
            dir: default_dir().to_string_lossy().to_string(),
            default_dir: default_dir().to_string_lossy().to_string(),
            exe_path: exe_path().map(|p| p.to_string_lossy().to_string()),
            moved: false,
            orphan_portable: None,
            legacy: None,
        })
}

pub fn data_dir() -> PathBuf {
    ACTIVE
        .get_or_init(|| RwLock::new(resolve(&read_bootstrap())))
        .read()
        .unwrap()
        .dir
        .clone()
}

pub fn current_mode() -> Mode {
    ACTIVE
        .get()
        .map(|r| r.read().unwrap().mode)
        .unwrap_or(Mode::Default)
}

pub fn data_file() -> PathBuf {
    data_dir().join(DATA_FILE)
}

pub fn backups_dir() -> PathBuf {
    data_dir().join("backups")
}

/// Gộp `src` vào `dst` theo id (không tạo bản trùng khi id khớp nhau).
pub fn merge_into(dst: &mut Store, src: &Store) {
    let mut ids: HashSet<u64> = dst.tasks.iter().map(|t| t.id).collect();
    for t in &src.tasks {
        if !ids.contains(&t.id) {
            dst.tasks.push(t.clone());
            ids.insert(t.id);
        }
    }
    let mut list_ids: HashSet<u64> = dst.lists.iter().map(|l| l.id).collect();
    for l in &src.lists {
        if !list_ids.contains(&l.id) {
            dst.lists.push(l.clone());
            list_ids.insert(l.id);
        }
    }
    dst.next_id = dst.next_id.max(src.next_id);
    dst.sanitize();
}

fn copy_backups(from: &Path, to: &Path) -> Result<u64, String> {
    if !from.exists() {
        return Ok(0);
    }
    fs::create_dir_all(to).map_err(|e| e.to_string())?;
    let mut n = 0u64;
    for e in fs::read_dir(from).map_err(|e| e.to_string())?.flatten() {
        let p = e.path();
        if p.extension().map(|x| x == "json").unwrap_or(false) {
            let dst = to.join(e.file_name());
            if !dst.exists() {
                fs::copy(&p, &dst).map_err(|e| e.to_string())?;
                n += 1;
            }
        }
    }
    Ok(n)
}

fn copy_data_file(from_dir: &Path, to_dir: &Path) -> Result<(), String> {
    let src = from_dir.join(DATA_FILE);
    if src.exists() {
        fs::create_dir_all(to_dir).map_err(|e| e.to_string())?;
        fs::copy(&src, to_dir.join(DATA_FILE)).map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Chuyển toàn bộ dữ liệu hiện tại sang `to_dir` (data.json + backups).
pub fn move_data_into(to_dir: &Path) -> Result<(), String> {
    let from = data_dir();
    if from == to_dir {
        return Ok(());
    }
    if to_dir.join(DATA_FILE).exists() {
        return Err("Thư mục đích đã có data.json. Hãy dùng chức năng Gộp để hợp nhất.".to_string());
    }
    copy_data_file(&from, to_dir)?;
    copy_backups(&from.join("backups"), &to_dir.join("backups"))?;
    Ok(())
}

/// Đổi nơi lưu. Trả về chế độ + thư mục thực tế sau khi đổi.
/// `portable`: ghi portable.txt cạnh exe; `custom`: lưu con trỏ trong bootstrap.
pub fn set_location(portable: bool, custom: Option<&str>) -> Result<(Mode, PathBuf), String> {
    let exe_dir = exe_dir().ok_or_else(|| "Không xác định được vị trí file thực thi.".to_string())?;
    let (mode, target) = if portable {
        (Mode::Portable, exe_dir.clone())
    } else if let Some(c) = custom.map(str::trim).filter(|s| !s.is_empty()) {
        (Mode::Custom, PathBuf::from(c))
    } else {
        (Mode::Default, default_dir())
    };
    if !probe_writable(&target) {
        return Err(format!(
            "Không ghi được vào “{}”. Hãy chọn thư mục khác (cần quyền ghi).",
            target.to_string_lossy()
        ));
    }
    // portable marker
    let marker = exe_dir.join(PORTABLE_MARKER);
    if portable {
        fs::write(
            &marker,
            "Taskora portable — xóa file này để trở về %APPDATA%\\Taskora\n",
        )
        .map_err(|e| e.to_string())?;
    } else {
        let _ = fs::remove_file(&marker);
    }
    update_bootstrap(|b| {
        b.custom_dir = if portable { None } else { custom.map(|s| s.to_string()) };
        b.last_portable_dir = if portable { Some(target.to_string_lossy().to_string()) } else { b.last_portable_dir.clone() };
    });
    if let Some(lock) = ACTIVE.get() {
        if let Ok(mut g) = lock.write() {
            *g = Resolved { mode, dir: target.clone() };
        }
    }
    Ok((mode, target))
}

/// Nạp dữ liệu từ một thư mục cụ thể (dùng khi đổi nơi lưu).
pub fn load_from(dir: &Path) -> Result<Store, String> {
    let p = dir.join(DATA_FILE);
    match fs::read_to_string(&p) {
        Ok(s) => {
            let mut st: Store = serde_json::from_str(&s).map_err(|e| e.to_string())?;
            st.sanitize();
            Ok(st)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Store::default()),
        Err(e) => Err(e.to_string()),
    }
}

/// Sao chép data.json + backups từ một thư mục khác vào thư mục hiện tại.
pub fn import_from(src_dir: &Path) -> Result<(), String> {
    let dst = data_dir();
    if src_dir == dst {
        return Ok(());
    }
    if dst.join(DATA_FILE).exists() {
        return Err("Thư mục hiện tại đã có dữ liệu — hãy dùng chức năng Gộp thay vì Chuyển.".to_string());
    }
    copy_data_file(src_dir, &dst)?;
    copy_backups(&src_dir.join("backups"), &dst.join("backups"))?;
    Ok(())
}

pub fn dismiss(kind: &str, src_dir: &str) {
    let p = PathBuf::from(src_dir);
    let fp = fingerprint(kind, &p);
    update_bootstrap(|b| {
        if !b.dismissed.contains(&fp) {
            b.dismissed.push(fp);
        }
    });
}
