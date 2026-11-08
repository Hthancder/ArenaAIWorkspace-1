//! Tìm GStreamer — **không** bắt người dùng cài bằng tay.
//!
//! Bản v3.30 bắt bạn tải installer GStreamer rồi sửa `PATH`. Bản v3.31 bỏ hẳn
//! bước đó: CI nhúng sẵn GStreamer vào thư mục `gst\` cạnh `lantern-mock.exe`,
//! và app tự tìm theo thứ tự dưới đây.
//!
//! | # | Ở đâu | Khi nào dùng |
//! |---|---|---|
//! | 1 | `LANTERN_GST` (đường dẫn đầy đủ tới `gst-launch-1.0.exe`) | test, hoặc bạn tự trỏ |
//! | 2 | `.\gst\bin\` cạnh exe | **bản tải từ Actions** — không cần cài gì |
//! | 3 | `.\gst\msvc_x86_64\bin\` cạnh exe | nếu giải nén cả cây runtime vào `gst\` |
//! | 4 | `gst-launch-1.0` trong `PATH` | bản bạn tự cài (vẫn tôn trọng) |
//!
//! Thứ tự quan trọng: bản **đi kèm** phải thắng bản cài trong máy, vì bản đi kèm
//! là bản đã được kiểm cùng lúc với exe. Ngược lại thì một GStreamer cũ trong
//! `PATH` có thể làm thiếu plugin `d3d11` mà không ai hiểu tại sao.

use std::path::{Path, PathBuf};

/// Tên file thực thi, khác nhau giữa Windows và nơi khác. Tách ra để test trên
/// Linux vẫn kiểm được logic (chỉ đổi tên, không đổi thứ tự).
pub fn exe_name() -> &'static str {
    if cfg!(windows) { "gst-launch-1.0.exe" } else { "gst-launch-1.0" }
}

/// Tên `gst-inspect-1.0` tương ứng — dùng để kiểm plugin `d3d11`.
///
/// Chỉ `probe_live_status()` trên Windows gọi hàm này (Linux không capture
/// được nên không cần kiểm plugin), nhưng vẫn phải biên dịch ở mọi nền tảng để
/// nó nằm cùng chỗ với `exe_name()` — tách ra thì dễ lệch tên.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn inspect_name() -> &'static str {
    if cfg!(windows) { "gst-inspect-1.0.exe" } else { "gst-inspect-1.0" }
}

/// Ứng viên theo đúng thứ tự bảng ở trên (trừ `PATH`, do OS lo).
///
/// Hàm **thuần**: chỉ ghép đường dẫn, không kiểm tồn tại — nhờ vậy test được
/// trên Linux dù file `.exe` không tồn tại.
pub fn candidates(exe_dir: &Path, env_override: Option<&str>) -> Vec<PathBuf> {
    let mut found = Vec::new();
    if let Some(explicit) = env_override.filter(|value| !value.trim().is_empty()) {
        found.push(PathBuf::from(explicit));
    }
    // Bản đi kèm: hai kiểu giải nén khác nhau (§58.13 trong spec).
    found.push(exe_dir.join("gst").join("bin").join(exe_name()));
    found.push(exe_dir.join("gst").join("msvc_x86_64").join("bin").join(exe_name()));
    found
}

/// Ứng viên đầu tiên **thật sự tồn tại**, hoặc `None`.
pub fn resolve(exe_dir: &Path, env_override: Option<&str>) -> Option<PathBuf> {
    candidates(exe_dir, env_override)
        .into_iter()
        .find(|path| path.is_file())
}

/// Biến môi trường cần đặt để `gst-launch-1.0` tìm thấy **plugin của chính nó**
/// khi nằm trong thư mục riêng chứ không phải chỗ cài chuẩn.
///
/// Không có bước này, `gst-launch` chạy được nhưng `gst-inspect-1.0 d3d11...`
/// báo "No such element" — đúng lỗi im lặng khó nhất của loại này: mọi thứ
/// "có vẻ" ổn.
pub fn plugin_env(bin_dir: &Path) -> Vec<(String, String)> {
    // Thư mục plugin nằm cạnh `bin`: `<gst>\lib\gstreamer-1.0`.
    let root = bin_dir.parent().unwrap_or(bin_dir);
    let plugins = root.join("lib").join("gstreamer-1.0");
    vec![
        ("GST_PLUGIN_SYSTEM_PATH_1_0".to_string(), plugins.display().to_string()),
        // Rỗng (không unset) để GStreamer **không** trộn plugin của bản cài
        // trong máy với bản đi kèm — trộn hai phiên bản là cách chắc chắn nhất
        // để có crash khó hiểu.
        ("GST_PLUGIN_PATH_1_0".to_string(), String::new()),
    ]
}

/// Dòng in lúc khởi động: app đang dùng GStreamer **nào**. Không có dòng này
/// thì khi hỏng, người dùng phải đoán giữa "bản đi kèm" và "bản trong PATH" —
/// hai thứ có thể khác phiên bản và khác bộ plugin.
pub fn describe(exe_dir: &Path) -> String {
    match resolve(exe_dir, None) {
        Some(path) => format!("GStreamer: {} (đi kèm exe)", path.display()),
        None => "GStreamer: không thấy bản đi kèm — sẽ dùng bản trong PATH nếu có.".to_string(),
    }
}

// ---------------------------------------------------------------------------
// Tự tải GStreamer khi máy chưa có.
//
// Vì sao cần: bản cài bằng tay thì *một lần*, nhưng vẫn là một lần bạn phải nhớ
// đường link, chọn đúng "Complete", đúng MSVC 64-bit, rồi sửa `PATH`. Ba bước
// đó là ba chỗ để sai. Máy đã có thì **không tải gì** — đây là fallback, không
// phải bắt buộc.
//
// An toàn: chỉ tải từ một URL **do ta viết cứng** trong binary (không nhận URL
// từ client), chỉ ghi vào thư mục `gst\` cạnh exe, không chạy installer nào.
// Nội dung tải về là file nén chứa sẵn thư mục `bin\` + `lib\`.
// ---------------------------------------------------------------------------

/// Kết quả một lần thử tải — dùng để app nói **đúng** chuyện gì đã xảy ra.
#[derive(Debug, PartialEq, Eq)]
pub enum FetchError {
    /// Nền tảng này không có bản tải sẵn (Linux/macOS: chỉ dùng `PATH`).
    Unsupported,
    /// Exe không nằm trên đĩa (chạy từ chỗ lạ) ⇒ không biết ghi vào đâu.
    NoExeDir,
    /// Mạng lỗi, DNS lỗi, 404… — giữ nguyên mô tả để người dùng đọc được.
    Download(String),
    /// Tải xong nhưng không giải nén được, hoặc thiếu `bin\` sau khi giải nén.
    Unpack(String),
    /// Ghi đè lên file đang bị khoá (GStreamer đang chạy).
    Busy,
}

impl FetchError {
    /// Câu tiếng Việt để hiện thẳng trong UI — không phải log kỹ thuật.
    pub fn message(&self) -> String {
        match self {
            FetchError::Unsupported => "Nền tảng này không có bản GStreamer tải sẵn; dùng bản cài trong PATH.".into(),
            FetchError::NoExeDir => "Không xác định được thư mục của exe nên không biết chỗ đặt GStreamer.".into(),
            FetchError::Download(detail) => format!("Tải GStreamer thất bại: {detail}"),
            FetchError::Unpack(detail) => format!("Giải nén GStreamer thất bại: {detail}"),
            FetchError::Busy => "Không ghi được vào thư mục gst: có thể GStreamer đang chạy. Dừng xem màn hình rồi thử lại.".into(),
        }
    }
}

/// URL tải **duy nhất** mà app được phép dùng. Viết cứng ở đây, không lấy từ
/// biến môi trường hay client (§41.4 — input từ ngoài không được thành lệnh).
///
/// `LANTERN_GST_URL` chỉ dành cho test/CI — nếu không có nó, không có cách nào
/// kiểm code tải về mà không thật sự tải 40 MB mỗi lần chạy test.
pub fn download_url() -> Option<String> {
    if let Ok(overridden) = std::env::var("LANTERN_GST_URL") {
        if !overridden.trim().is_empty() {
            return Some(overridden);
        }
    }
    if cfg!(windows) {
        Some("https://gstreamer.freedesktop.org/data/pkg/windows/1.24.10/msvc/gstreamer-1.0-msvc-x86_64-1.24.10.zip".to_string())
    } else {
        None
    }
}

/// Tải bằng **PowerShell có sẵn của Windows** — không thêm dependency Rust nào
/// (§0.3: zero-dependency, CI không được đỏ vì thư viện ngoài).
///
/// `curl.exe` cũng có trên Windows 10 1809+, nhưng PowerShell chắc chắn hơn với
/// máy đã tắt Windows Update lâu ngày.
pub fn download_zip(url: &str, target: &Path) -> Result<(), FetchError> {
    if !cfg!(windows) {
        return Err(FetchError::Unsupported);
    }
    let script = format!(
        "$ProgressPreference='SilentlyContinue';          try {{ Invoke-WebRequest -Uri '{}' -OutFile '{}' -UseBasicParsing }}          catch {{ Write-Output $_.Exception.Message; exit 1 }}",
        url.replace('\'', "''"),
        target.display().to_string().replace('\'', "''")
    );
    let output = std::process::Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", &script])
        .output()
        .map_err(|error| FetchError::Download(format!("không chạy được powershell: {error}")))?;
    if output.status.success() && target.is_file() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Err(FetchError::Download(if stderr.is_empty() { stdout } else { stderr }))
}

/// Giải nén bằng `tar.exe` (có sẵn từ Windows 10 1803) — cùng lý do: 0 dependency.
///
/// `tar -xf` đọc được **cả** `.zip` và `.tar.gz` trên Windows 10 mới, nên một
/// lệnh dùng được cho cả hai loại file nhà phát hành đưa ra.
pub fn unpack(zip: &Path, into: &Path) -> Result<(), FetchError> {
    if !cfg!(windows) {
        return Err(FetchError::Unsupported);
    }
    std::fs::create_dir_all(into).map_err(|error| FetchError::Unpack(error.to_string()))?;
    let output = std::process::Command::new("tar")
        .args(["-xf"])
        .arg(zip)
        .arg("-C")
        .arg(into)
        .output()
        .map_err(|error| FetchError::Unpack(format!("không chạy được tar: {error}")))?;
    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(FetchError::Unpack(if detail.is_empty() { "tar trả mã lỗi".into() } else { detail }));
    }
    // Sau khi giải nén phải có `bin\gst-launch-1.0.exe`, nếu không thì gói tải
    // về không đúng thứ ta nghĩ — báo ngay chứ không để lỗi hiện ở chỗ khác.
    if !into.join("bin").join(exe_name()).is_file() {
        return Err(FetchError::Unpack(format!(
            "gói tải về không có bin/{}",
            exe_name()
        )));
    }
    Ok(())
}

/// Toàn bộ quy trình: tải → giải nén vào `gst\` cạnh exe. Trả về thư mục `bin`.
///
/// Gọi hàm này **chỉ** khi `resolve()` đã trả `None` — không tải lại thứ đã có.
pub fn fetch_into(exe_dir: &Path) -> Result<PathBuf, FetchError> {
    let url = download_url().ok_or(FetchError::Unsupported)?;
    let target = exe_dir.join("gst");
    std::fs::create_dir_all(&target).map_err(|error| {
        if error.kind() == std::io::ErrorKind::PermissionDenied { FetchError::Busy } else { FetchError::Unpack(error.to_string()) }
    })?;
    let zip = target.join("gstreamer.zip");
    download_zip(&url, &zip)?;
    let result = unpack(&zip, &target);
    // Dọn file tải về dù thành công hay không: 40 MB rác trong thư mục app.
    let _ = std::fs::remove_file(&zip);
    result?;
    Ok(target.join("bin"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!("lantern-gst-{tag}-{stamp}"));
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    #[test] fn vendored_gst_beats_the_one_installed_on_the_pc() {
        // Đây là lý do hàm này tồn tại: GStreamer cũ trong `PATH` không được
        // thắng bản đã kiểm cùng exe.
        let dir = temp_dir("order");
        let vendored = dir.join("gst").join("bin");
        std::fs::create_dir_all(&vendored).expect("gst dir");
        std::fs::write(vendored.join(exe_name()), b"x").expect("fake exe");

        let found = resolve(&dir, None).expect("phải tìm thấy bản đi kèm");
        assert_eq!(found, vendored.join(exe_name()));
        assert_ne!(found, PathBuf::from(exe_name()), "không được trả tên trần trong PATH");
    }

    #[test] fn both_unpack_layouts_are_supported() {
        let dir = temp_dir("layouts");
        let nested = dir.join("gst").join("msvc_x86_64").join("bin");
        std::fs::create_dir_all(&nested).expect("nested");
        std::fs::write(nested.join(exe_name()), b"x").expect("fake exe");
        assert_eq!(resolve(&dir, None), Some(nested.join(exe_name())));
    }

    #[test] fn an_explicit_override_wins_even_if_vendored_exists() {
        let dir = temp_dir("override");
        let vendored = dir.join("gst").join("bin");
        std::fs::create_dir_all(&vendored).expect("gst dir");
        std::fs::write(vendored.join(exe_name()), b"x").expect("fake exe");
        let mine = dir.join("my-gst");
        std::fs::write(&mine, b"x").expect("override file");

        assert_eq!(resolve(&dir, Some(&mine.display().to_string())), Some(mine));
    }

    #[test] fn nothing_found_is_none_not_a_panic() {
        let dir = temp_dir("empty");
        assert_eq!(resolve(&dir, None), None);
        assert!(describe(&dir).contains("không thấy bản đi kèm"));
    }

    #[test] fn plugin_env_points_at_the_sibling_lib_dir_and_hides_foreign_plugins() {
        let bin = PathBuf::from("C:\\lantern\\gst\\bin");
        let env = plugin_env(&bin);
        let map = env.into_iter().collect::<std::collections::BTreeMap<_, _>>();
        let system = map.get("GST_PLUGIN_SYSTEM_PATH_1_0").expect("phải set");
        assert!(system.ends_with("lib\\gstreamer-1.0") || system.ends_with("lib/gstreamer-1.0"), "{system}");
        assert_eq!(map.get("GST_PLUGIN_PATH_1_0").map(String::as_str), Some(""));
    }

    #[test] fn the_download_url_is_not_configurable_by_a_client() {
        // URL phải là hằng trong binary; `LANTERN_GST_URL` là cửa cho test, và
        // nó chỉ đọc từ **biến môi trường của tiến trình**, không từ HTTP.
        // Nếu ai đó sau này đổi sang đọc query string thì test này vẫn xanh —
        // nên nó không thay thế việc đọc code, nó chỉ ghim hành vi hiện tại.
        let _guard = ENV_LOCK.lock().unwrap_or_else(|error| error.into_inner());
        std::env::remove_var("LANTERN_GST_URL");
        let url = download_url();
        if cfg!(windows) {
            let url = url.expect("Windows phải có URL mặc định");
            assert!(url.starts_with("https://"), "chỉ https: {url}");
            assert!(url.contains("gstreamer.freedesktop.org"), "đúng nhà phát hành: {url}");
            assert!(url.ends_with(".zip") || url.ends_with(".tar.gz"), "định dạng tar đọc được: {url}");
        } else {
            assert_eq!(url, None, "Linux không tải sẵn");
        }
    }

    #[test] fn a_download_failure_keeps_the_reason_the_user_needs() {
        // Thông báo lỗi là thứ người dùng đọc; đừng trả "lỗi không xác định".
        let message = FetchError::Download("getaddrinfo failed".into()).message();
        assert!(message.contains("getaddrinfo failed"), "{message}");
        assert!(message.contains("Tải GStreamer thất bại"), "{message}");
        assert!(FetchError::Busy.message().contains("đang chạy"));
    }

    #[test] fn fetching_is_a_no_op_error_on_platforms_without_a_bundle() {
        // Trên Linux, `fetch_into` phải trả lỗi rõ ràng **trước khi** chạm đĩa.
        let dir = temp_dir("fetch-noop");
        if !cfg!(windows) {
            assert_eq!(fetch_into(&dir), Err(FetchError::Unsupported));
            assert!(!dir.join("gst").exists(), "không được tạo thư mục khi không hỗ trợ");
        }
    }

    static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test] fn an_empty_override_is_ignored_not_treated_as_a_path() {
        // `LANTERN_GST=` (rỗng) rất dễ xảy ra khi người dùng sửa file .cmd;
        // nếu coi nó là đường dẫn thì app báo "không chạy được" vô cớ.
        let dir = temp_dir("empty-override");
        let vendored = dir.join("gst").join("bin");
        std::fs::create_dir_all(&vendored).expect("gst dir");
        std::fs::write(vendored.join(exe_name()), b"x").expect("fake exe");
        assert_eq!(resolve(&dir, Some("  ")), Some(vendored.join(exe_name())));
    }
}
