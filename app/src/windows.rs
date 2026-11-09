//! §5.4 window picker — `EnumWindows` **thật**, không phải danh sách bịa.
//!
//! # Vì sao file này là bước ngoặt của sản phẩm
//!
//! Trước file này, `GET /api/windows` trả **ba cửa sổ viết cứng** ("Trình duyệt",
//! "Ghi chú", "Toàn bộ màn hình"). Người dùng mở app trên máy mình thấy ba thứ
//! không tồn tại trên máy — đó là lý do cảm giác "vẫn là demo". Danh sách cửa sổ
//! là **thứ đầu tiên** người dùng chạm vào, trước cả khung hình.
//!
//! # Thuật toán là của spec, không phải của tôi
//!
//! §5.4 liệt kê **9 điều kiện loại** theo thứ tự và nói rõ vì sao từng cái:
//! `!IsWindowVisible`, `GW_OWNER != NULL`, `WS_EX_TOOLWINDOW|NOACTIVATE`,
//! class hệ thống, `DWMWA_CLOAKED`, `EXTENDED_FRAME_BOUNDS` rỗng, PID của
//! server, session khác. Mỗi điều kiện loại một loại "rác" mà nếu không loại
//! thì danh sách có 40 mục vô nghĩa (nút taskbar, tooltip, cửa sổ ẩn của UWP).
//!
//! Hai chi tiết spec nhấn mạnh vì đã từng sai:
//!
//! * **KHÔNG dùng `GetWindowRect`** — dính viền vô hình của DWM/UWP, lệch 7–8
//!   px mỗi cạnh ở Win10 ⇒ click sai mép. Dùng `DWMWA_EXTENDED_FRAME_BOUNDS`.
//! * Loại owned popup khỏi **danh sách** nhưng vẫn capture được chúng, vì
//!   capture theo *display* chứ không theo hwnd.
//!
//! # Trên Linux phần lọc "không được dùng" nhưng **không** được xoá
//!
//! `RawWindow`/`classify`/`Excluded` chỉ được tạo ra ở nhánh `#[cfg(windows)]`
//! (nơi `EnumWindows` chạy). Trên Linux chúng chỉ có trong test — và test đó là
//! thứ duy nhất kiểm 9 điều kiện loại của §5.4 mà không cần máy Windows. Xoá để
//! hết warning là xoá đúng phần được test tốt nhất của file.
//!
//! Phần quyết định "(title, rect, exe, pid) này có vào danh sách không" là
//! [`Filter`] — dữ liệu thuần, test được ở mọi nền tảng, và đó là phần dễ sai
//! (9 điều kiện có thứ tự). Phần gọi Win32 chỉ **thu** dữ liệu thô.

#![cfg_attr(
    not(any(windows, test)),
    allow(dead_code, reason = "§5.4: phần lọc chỉ được gọi từ nhánh Windows; trên Linux nó sống để test 9 điều kiện loại")
)]

/// Dữ liệu thô của một cửa sổ, do tầng Win32 thu.
///
/// Tách khỏi hwnd để [`Filter`] test được mà không cần Windows.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct RawWindow {
    /// `hwnd` dưới dạng `i64` — §5.4 ghi `wid(hwnd i64)`. Âm ở Windows 64-bit.
    pub wid: i64,
    pub title: String,
    /// Tên file exe, ví dụ `chrome.exe`.
    pub app: String,
    pub pid: u32,
    /// `(left, top, right, bottom)` từ `DWMWA_EXTENDED_FRAME_BOUNDS`.
    pub rect: (i32, i32, i32, i32),
    pub visible: bool,
    /// `GetWindow(hwnd, GW_OWNER) != NULL`.
    pub owned: bool,
    pub toolwindow: bool,
    pub noactivate: bool,
    pub cloaked: bool,
    /// Class name, ví dụ `Chrome_WidgetWin_1`, `Progman`.
    pub class: String,
    pub minimized: bool,
    pub elevated: bool,
    /// PID của chính server — §5.4: "loại nếu PID == server PID".
    pub is_self: bool,
    /// §5.4: "loại nếu `ProcessIdToSessionId(pid) != session của server`".
    pub other_session: bool,
}

/// Một cửa sổ đã qua [`Filter`], sẵn sàng trả cho client.
#[derive(Debug, Clone, PartialEq)]
pub struct WindowEntry {
    /// **hwnd thô** — chỉ dùng nội bộ để capture/di chuyển.
    ///
    /// §41.3 #3: client **không bao giờ** thấy giá trị này. Cái client thấy là
    /// `wid` (id hex do agent sinh trong snapshot §41.4 T1). Hai thứ khác nhau
    /// vì nếu client cầm hwnd thì nó gọi được cửa sổ **bất kỳ** — kể cả cửa sổ
    /// mà agent đã cố ý không trả về.
    pub hwnd: i64,
    pub title: String,
    pub app: String,
    pub pid: u32,
    pub rect: (i32, i32, i32, i32),
    pub minimized: bool,
    pub elevated: bool,
    /// §5.4 `display=physical|virtual`. Bản này chưa cài VDD nên luôn
    /// `physical`; khi có VDD thì đây là chỗ phân biệt (§5.2).
    pub display: &'static str,
}

/// Class thuộc shell, không phải app — §5.4 liệt kê đúng bốn cái.
///
/// Thiếu một cái là danh sách có "Program Manager" / "Taskbar" — người dùng
/// thấy ngay là danh sách rác.
const SHELL_CLASSES: &[&str] = &[
    "Progman",
    "WorkerW",
    "Shell_TrayWnd",
    "Windows.UI.Core.CoreWindow",
];

/// Lý do một cửa sổ bị loại. Có tên để log đọc được và test khẳng định được
/// **vì sao** — "bị loại" chung chung không chẩn đoán được khi người dùng báo
/// "app của tôi không hiện trong danh sách".
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Excluded {
    NotVisible,
    OwnedPopup,
    ToolWindow,
    NoActivate,
    ShellClass,
    Cloaked,
    EmptyFrame,
    ServerItself,
    OtherSession,
    NoTitle,
}

impl Excluded {
    /// Mã cho `detail` của response — để người dùng gửi được "app X bị loại vì Y".
    pub fn code(self) -> &'static str {
        match self {
            Excluded::NotVisible => "not_visible",
            Excluded::OwnedPopup => "owned_popup",
            Excluded::ToolWindow => "tool_window",
            Excluded::NoActivate => "no_activate",
            Excluded::ShellClass => "shell_class",
            Excluded::Cloaked => "cloaked",
            Excluded::EmptyFrame => "empty_frame",
            Excluded::ServerItself => "server_itself",
            Excluded::OtherSession => "other_session",
            Excluded::NoTitle => "no_title",
        }
    }
}

/// §5.4 — quyết định một cửa sổ có vào danh sách hay không.
///
/// Thứ tự **có ý nghĩa**: kiểm rẻ trước (visible, owned) rồi mới tới phần cần
/// gọi API (cloaked nằm ở tầng thu, `RawWindow` đã có). Và `NoTitle` ở **cuối**
/// — một cửa sổ có title rỗng nhưng hiển thị vẫn là ứng dụng thật (một số app
/// đặt title rỗng); nó bị loại vì không chọn được trong UI, không phải vì
/// không tồn tại.
pub fn classify(raw: &RawWindow) -> Result<(), Excluded> {
    if !raw.visible {
        return Err(Excluded::NotVisible);
    }
    // §5.4: owned popup bị loại **khỏi danh sách** nhưng vẫn được capture.
    if raw.owned {
        return Err(Excluded::OwnedPopup);
    }
    if raw.toolwindow {
        return Err(Excluded::ToolWindow);
    }
    if raw.noactivate {
        return Err(Excluded::NoActivate);
    }
    // So khớp **chính xác**: `WorkerW` phải là `WorkerW`, không phải app nào
    // có "WorkerW" trong tên class. `contains` ở đây là lỗi: một app tên
    // `MyWorkerWidget` sẽ bị loại oan.
    if SHELL_CLASSES.contains(&raw.class.as_str()) {
        return Err(Excluded::ShellClass);
    }
    // §5.4: `DWMWA_CLOAKED != 0` ⇒ UWP suspended hoặc cửa sổ ở desktop ảo
    // khác. Không loại thì danh sách có hàng chục cửa sổ "Settings" ảo.
    if raw.cloaked {
        return Err(Excluded::Cloaked);
    }
    let (left, top, right, bottom) = raw.rect;
    if right <= left || bottom <= top {
        return Err(Excluded::EmptyFrame);
    }
    if raw.is_self {
        return Err(Excluded::ServerItself);
    }
    if raw.other_session {
        return Err(Excluded::OtherSession);
    }
    if raw.title.trim().is_empty() {
        return Err(Excluded::NoTitle);
    }
    Ok(())
}

/// Lọc cả danh sách, giữ **thứ tự** Win32 trả (z-order: trên cùng trước).
///
/// Giữ z-order vì người dùng nhận ra cửa sổ mình vừa dùng ở **đầu** danh sách
/// — sắp theo tên sẽ làm họ phải đọc.
pub fn pick(windows: &[RawWindow]) -> Vec<WindowEntry> {
    windows
        .iter()
        .filter(|raw| classify(raw).is_ok())
        .map(|raw| WindowEntry {
            hwnd: raw.wid,
            title: raw.title.clone(),
            app: raw.app.clone(),
            pid: raw.pid,
            rect: raw.rect,
            minimized: raw.minimized,
            elevated: raw.elevated,
            display: "physical",
        })
        .collect()
}

/// Đếm số cửa sổ bị loại theo lý do, để UI/người dùng biết **vì sao** danh sách
/// ngắn hơn số cửa sổ họ đang mở.
///
/// # Vì sao cần
///
/// §5.4 loại cửa sổ theo 7 lý do (tool window, cloaked, không có tiêu đề…). Nếu
/// danh sách chỉ ngắn hơn mà không nói gì, người dùng kết luận "picker hỏng" —
/// cùng loại nhầm lẫn như "stream không có hình" khi thật ra là chưa đăng nhập.
/// Trả số đếm chứ **không** trả danh sách: tiêu đề cửa sổ bị loại có thể chứa
/// thông tin nhạy cảm (ví dụ popup của trình quản lý mật khẩu).
#[cfg_attr(not(windows), allow(dead_code, reason = "chỉ nhánh Windows có RawWindow"))]
pub fn exclusion_summary(windows: &[RawWindow]) -> Vec<(&'static str, usize)> {
    let mut counts: Vec<(&'static str, usize)> = Vec::new();
    for raw in windows {
        if let Err(reason) = classify(raw) {
            let code = reason.code();
            match counts.iter_mut().find(|(existing, _)| *existing == code) {
                Some((_, count)) => *count += 1,
                None => counts.push((code, 1)),
            }
        }
    }
    counts
}

/// Chuyển sang `security::window::WindowEntry` của spec để **publish** vào
/// `WindowRegistry` (§41.3 #3). Từ đây `hwnd` không đi ra ngoài nữa; `wid` là
/// id hex do registry sinh.
pub fn to_registry_entries(entries: &[WindowEntry]) -> Vec<rd_spike_lib::security::window::WindowEntry> {
    entries
        .iter()
        .map(|entry| rd_spike_lib::security::window::WindowEntry {
            // `wid` tạm: registry sẽ thay bằng id thật của nó? Không — registry
            // giữ nguyên `wid` client thấy, nên ta truyền **hwnd dạng hex** và
            // nó trở thành định danh mà client dùng. hwnd có thể âm (bit cao),
            // nên dùng hex của `u64` để không có dấu.
            wid: format!("{:016x}", entry.hwnd as u64),
            title: entry.title.clone(),
            app: entry.app.clone(),
            pid: entry.pid,
            minimized: entry.minimized,
            elevated: entry.elevated,
            // §5.4 `blocked_capture` (WDA_EXCLUDEFROMCAPTURE) — bản này chưa
            // kiểm (cần `SetWindowDisplayAffinity` trả về); để `false` và ghi
            // lý do thay vì đoán.
            capture_blocked: false,
        })
        .collect()
}

/// `EXTENDED_FRAME_BOUNDS` của một cửa sổ, theo pixel màn hình.
///
/// §5.4: **KHÔNG** `GetWindowRect` — dính viền vô hình DWM/UWP, lệch 7–8 px mỗi
/// cạnh ở Win10 ⇒ click sai mép và crop cắt mất viền.
///
/// `None` = cửa sổ không còn (vừa đóng) hoặc DWM không trả bounds. Trả `None`
/// thay vì rect 0×0 để người gọi **nói** được lý do với người dùng; một rect
/// rỗng lặng lẽ biến thành "stream cả màn hình" và người dùng tưởng window
/// picker không có tác dụng.
#[cfg(windows)]
pub fn extended_frame_bounds(hwnd: i64) -> Option<crate::crop::Rect> {
    use std::ffi::c_void;
    #[allow(non_snake_case)]
    mod dwm {
        use std::ffi::c_void;
        extern "system" {
            pub fn DwmGetWindowAttribute(
                hwnd: *mut c_void,
                attribute: u32,
                out: *mut c_void,
                size: u32,
            ) -> i32;
        }
    }
    const DWMWA_EXTENDED_FRAME_BOUNDS: u32 = 9;
    #[repr(C)]
    #[derive(Default)]
    struct WinRect {
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    }
    let mut rect = WinRect::default();
    let ok = unsafe {
        dwm::DwmGetWindowAttribute(
            hwnd as *mut c_void,
            DWMWA_EXTENDED_FRAME_BOUNDS,
            &mut rect as *mut WinRect as *mut c_void,
            std::mem::size_of::<WinRect>() as u32,
        )
    } == 0;
    if !ok {
        return None;
    }
    Some(crate::crop::Rect {
        left: rect.left,
        top: rect.top,
        right: rect.right,
        bottom: rect.bottom,
    })
}

/// Linux/macOS: không có cửa sổ Win32 để hỏi.
///
/// `None` để người gọi trả `409` kèm lý do, thay vì crop một vùng bịa.
#[cfg(not(windows))]
pub fn extended_frame_bounds(_hwnd: i64) -> Option<crate::crop::Rect> {
    None
}

/// Tra ngược `wid` (hex) → `hwnd`. Cần khi đã có snapshot hợp lệ và phải
/// capture/đổi cửa sổ thật.
///
/// Chưa nối ở đây vì `app` mới stream **theo display** (`/api/live.mjpg`), chưa
/// stream theo `hwnd`. Hàm này là mảnh của §5.5.1 (WGC window item cho T3) —
/// giữ vì nó là nửa còn lại của `to_registry_entries`, và test khoá tính đối
/// xứng của hai chiều hex.
#[cfg_attr(not(test), allow(dead_code, reason = "§5.5.1: cần khi stream theo hwnd; hiện chỉ test dùng"))]
pub fn hwnd_from_wid(wid: &str) -> Option<i64> {
    u64::from_str_radix(wid, 16).ok().map(|value| value as i64)
}

/// JSON cho `GET /api/windows` (§8.1).
///
/// `elevated_warn` chỉ có khi cửa sổ chạy elevated mà server không — §9.9b:
/// stream được nhưng **click/gõ bị UIPI chặn**, nên phải cảnh báo *trước* khi
/// bắt đầu, không phải để người dùng phát hiện ra khi bấm không ăn.
pub fn windows_json(entries: &[(String, WindowEntry)]) -> String {
    let items: Vec<String> = entries
        .iter()
        .map(|(wid, entry)| {
            let (left, top, right, bottom) = entry.rect;
            let warn = if entry.elevated {
                r#","elevated_warn":"Cửa sổ chạy quyền admin — xem được nhưng không điều khiển được (UIPI, §9.9b)""#
            } else {
                ""
            };
            format!(
                "{{\"wid\":{},\"title\":{},\"app\":{},\"pid\":{},\"rect\":{{\"left\":{},\"top\":{},\"right\":{},\"bottom\":{}}},\"min\":{},\"display\":{},\"elevated\":{},{} }}",
                json_quote(wid),
                json_quote(&entry.title),
                json_quote(&entry.app),
                entry.pid,
                left,
                top,
                right,
                bottom,
                entry.minimized,
                json_quote(entry.display),
                entry.elevated,
                warn
            )
            // `format!` trên để lại `, }` khi không cảnh báo — dọn cho JSON hợp lệ.
            .replace(", }", "}")
        })
        .collect();
    format!("[{}]", items.join(","))
}

fn json_quote(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push(' '),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

// ══════════════════════════════════════════════════════════════════════════
// Tầng Win32 — chỉ **thu** dữ liệu, không quyết định gì.
// ══════════════════════════════════════════════════════════════════════════

/// Như `enumerate`, nhưng kèm **lý do loại** (`§5.4` có 7 lý do).
///
/// Một lần `EnumWindows` cho cả hai thứ: quét hai lần vừa đắt vừa có thể cho
/// hai kết quả khác nhau (cửa sổ đóng giữa hai lần quét ⇒ danh sách và số đếm
/// không khớp, người dùng thấy "1 cửa sổ bị loại" mà không cửa sổ nào biến mất).
#[cfg(windows)]
pub fn enumerate_with_summary() -> (Vec<WindowEntry>, Vec<(&'static str, usize)>) {
    let raw = unsafe { enumerate_raw() };
    (pick(&raw), exclusion_summary(&raw))
}

#[cfg(not(windows))]
pub fn enumerate_with_summary() -> (Vec<WindowEntry>, Vec<(&'static str, usize)>) {
    (Vec::new(), Vec::new())
}

/// UTF-16 → `String`, không cần `std::os::windows::ffi::OsStringExt`.
///
/// # Vì sao không dùng `OsStringExt::from_wide`
///
/// Nó chỉ tồn tại trên Windows, nên `scripts/check-windows-shape.py` — script
/// biên dịch **nhánh Windows trên Linux** để bắt `dead_code`/`unused_mut`
/// trước CI — không thể dựng được. Tự decode là 6 dòng và làm nhánh Windows
/// **test được** trên Linux, đúng mục đích của script đó.
#[cfg_attr(not(windows), allow(dead_code, reason = "chỉ nhánh Windows gọi; giữ để script hình dạng kiểm được trên Linux"))]
fn wide_to_string(wide: &[u16]) -> String {
    String::from_utf16_lossy(wide).trim_end_matches('\0').to_string()
}

/// Trên hệ khác Windows, nói rõ **vì sao** danh sách rỗng thay vì giả vờ.
pub fn platform_note() -> Option<&'static str> {
    if cfg!(windows) {
        None
    } else {
        Some("Danh sách cửa sổ dùng EnumWindows — chỉ chạy trên Windows. Bản này chạy trên Linux/macOS nên trả danh sách rỗng thay vì bịa.")
    }
}

#[cfg(windows)]
unsafe fn enumerate_raw() -> Vec<RawWindow> {
    use std::ffi::c_void;

    // ---- khai báo API ----
    //
    // Không dùng crate `windows`: §56.1 là **0 dependency**, và cả binary này
    // đã đi theo đường `extern "system"` (xem `capture.rs`, `auth_wire.rs`).
    // Mọi hàm dưới đây đều tra trong tài liệu Win32, không phải đoán.

    #[link(name = "user32")]
    extern "system" {
        fn EnumWindows(callback: EnumWindowsProc, lparam: isize) -> i32;
        fn IsWindowVisible(hwnd: *mut c_void) -> i32;
        fn IsIconic(hwnd: *mut c_void) -> i32;
        fn GetWindow(hwnd: *mut c_void, cmd: u32) -> *mut c_void;
        fn GetWindowLongPtrW(hwnd: *mut c_void, index: i32) -> isize;
        fn GetClassNameW(hwnd: *mut c_void, buffer: *mut u16, max: i32) -> i32;
        fn GetWindowTextW(hwnd: *mut c_void, buffer: *mut u16, max: i32) -> i32;
        fn GetWindowThreadProcessId(hwnd: *mut c_void, pid: *mut u32) -> u32;
    }
    #[link(name = "dwmapi")]
    extern "system" {
        fn DwmGetWindowAttribute(
            hwnd: *mut c_void,
            attribute: u32,
            out: *mut c_void,
            size: u32,
        ) -> i32;
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn OpenProcess(access: u32, inherit: i32, pid: u32) -> *mut c_void;
        fn CloseHandle(handle: *mut c_void) -> i32;
        fn ProcessIdToSessionId(pid: u32, session: *mut u32) -> i32;
        fn QueryFullProcessImageNameW(
            process: *mut c_void,
            flags: u32,
            buffer: *mut u16,
            size: *mut u32,
        ) -> i32;
        fn GetCurrentProcessId() -> u32;
    }

    // Hằng số Win32 (đều có trong tài liệu, không phải số đoán).
    const GW_OWNER: u32 = 4;
    const GWL_EXSTYLE: i32 = -20;
    const WS_EX_TOOLWINDOW: isize = 0x0000_0080;
    const WS_EX_NOACTIVATE: isize = 0x0800_0000;
    const DWMWA_CLOAKED: u32 = 14;
    const DWMWA_EXTENDED_FRAME_BOUNDS: u32 = 9;
    const PROCESS_QUERY_LIMITED_INFORMATION: u32 = 0x1000;

    type EnumWindowsProc = unsafe extern "system" fn(*mut c_void, isize) -> i32;

    /// `RECT` — bốn `LONG`, đúng thứ tự của Win32.
    #[repr(C)]
    #[derive(Default)]
    struct Rect {
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    }

    struct Collect {
        items: Vec<RawWindow>,
        self_pid: u32,
        self_session: u32,
    }

    unsafe extern "system" fn callback(hwnd: *mut c_void, lparam: isize) -> i32 {
        let collect = &mut *(lparam as *mut Collect);

        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, &mut pid);

        // Session của process này (§5.4 loại cửa sổ ở session khác — ví dụ
        // app của user khác, hoặc service).
        let mut session = 0u32;
        let other_session = ProcessIdToSessionId(pid, &mut session) != 0
            && session != collect.self_session;

        let ex_style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);

        let mut class_buffer = [0u16; 256];
        let class_len = GetClassNameW(hwnd, class_buffer.as_mut_ptr(), class_buffer.len() as i32);
        let class = wide_to_string(&class_buffer[..class_len.max(0) as usize]);

        let mut title_buffer = [0u16; 512];
        let title_len = GetWindowTextW(hwnd, title_buffer.as_mut_ptr(), title_buffer.len() as i32);
        let title = wide_to_string(&title_buffer[..title_len.max(0) as usize]);

        // §5.4: **KHÔNG** `GetWindowRect` — dính viền vô hình DWM/UWP, lệch 7–8
        // px mỗi cạnh ở Win10 ⇒ click sai mép.
        let mut frame = Rect::default();
        let bounds_ok = DwmGetWindowAttribute(
            hwnd,
            DWMWA_EXTENDED_FRAME_BOUNDS,
            &mut frame as *mut Rect as *mut c_void,
            std::mem::size_of::<Rect>() as u32,
        ) == 0;

        let mut cloaked = 0u32;
        DwmGetWindowAttribute(
            hwnd,
            DWMWA_CLOAKED,
            &mut cloaked as *mut u32 as *mut c_void,
            std::mem::size_of::<u32>() as u32,
        );

        // Tên exe: `QueryFullProcessImageNameW` không cần quyền cao.
        let mut app = String::new();
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if !process.is_null() {
            let mut path_buffer = [0u16; 512];
            let mut size = path_buffer.len() as u32;
            if QueryFullProcessImageNameW(process, 0, path_buffer.as_mut_ptr(), &mut size) != 0 {
                let path = wide_to_string(&path_buffer[..size as usize]);
                app = path
                    .rsplit(['\\', '/'])
                    .next()
                    .unwrap_or(&path)
                    .to_string();
            }
            CloseHandle(process);
        }

        collect.items.push(RawWindow {
            wid: hwnd as i64,
            title,
            app,
            pid,
            // `bounds_ok == false` ⇒ để rect rỗng; `classify` loại nó bằng
            // `EmptyFrame` thay vì dùng toạ độ sai.
            rect: if bounds_ok {
                (frame.left, frame.top, frame.right, frame.bottom)
            } else {
                (0, 0, 0, 0)
            },
            visible: IsWindowVisible(hwnd) != 0,
            owned: !GetWindow(hwnd, GW_OWNER).is_null(),
            toolwindow: ex_style & WS_EX_TOOLWINDOW != 0,
            noactivate: ex_style & WS_EX_NOACTIVATE != 0,
            cloaked: cloaked != 0,
            class,
            minimized: IsIconic(hwnd) != 0,
            // §5.4: `elevated` cần biết token của process kia có elevated
            // không. Bản này để `false` và ghi lý do — **không** đoán bằng
            // cách so tên exe: đoán sai làm cảnh báo UIPI (§9.9b) hiện nhầm
            // hoặc không hiện.
            elevated: false,
            is_self: pid == collect.self_pid,
            other_session,
        });
        1 // tiếp tục liệt kê
    }

    let mut collect = Collect {
        items: Vec::with_capacity(64),
        self_pid: GetCurrentProcessId(),
        self_session: {
            let mut session = 0u32;
            let _ = ProcessIdToSessionId(GetCurrentProcessId(), &mut session);
            session
        },
    };
    EnumWindows(callback, &mut collect as *mut Collect as isize);
    collect.items
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `pick` + sinh `wid` cho mỗi entry, đúng như route làm.
    fn pick_with_wids(raw: &[RawWindow]) -> Vec<(String, WindowEntry)> {
        pick(raw)
            .into_iter()
            .map(|entry| (format!("{:016x}", entry.hwnd as u64), entry))
            .collect()
    }

    /// Một cửa sổ "bình thường" — dùng làm mốc, rồi mỗi test phá **một** điều
    /// kiện. Nếu làm ngược lại (dựng từ `default()`) thì mọi test đều bị loại
    /// bởi điều kiện đầu tiên và không test được điều kiện nào khác.
    fn normal() -> RawWindow {
        RawWindow {
            wid: 0x1234,
            title: "Tài liệu — Word".into(),
            app: "WINWORD.EXE".into(),
            pid: 4242,
            rect: (100, 100, 900, 700),
            visible: true,
            owned: false,
            toolwindow: false,
            noactivate: false,
            cloaked: false,
            class: "OpusApp".into(),
            minimized: false,
            elevated: false,
            is_self: false,
            other_session: false,
        }
    }

    #[test] fn a_normal_window_is_kept() {
        assert_eq!(classify(&normal()), Ok(()));
        let picked = pick(&[normal()]);
        assert_eq!(picked.len(), 1);
        assert_eq!(picked[0].title, "Tài liệu — Word");
        assert_eq!(picked[0].hwnd, 0x1234);
    }

    #[test] fn every_exclusion_of_the_spec_actually_excludes() {
        // §5.4 liệt kê 9 điều kiện. Test này khẳng định **từng cái** đều có
        // tác dụng — không có cái nào là code chết. Mỗi lần chỉ phá một cái.
        let cases: Vec<(RawWindow, Excluded)> = vec![
            ({ let mut w = normal(); w.visible = false; w }, Excluded::NotVisible),
            ({ let mut w = normal(); w.owned = true; w }, Excluded::OwnedPopup),
            ({ let mut w = normal(); w.toolwindow = true; w }, Excluded::ToolWindow),
            ({ let mut w = normal(); w.noactivate = true; w }, Excluded::NoActivate),
            ({ let mut w = normal(); w.class = "Progman".into(); w }, Excluded::ShellClass),
            ({ let mut w = normal(); w.class = "Shell_TrayWnd".into(); w }, Excluded::ShellClass),
            ({ let mut w = normal(); w.cloaked = true; w }, Excluded::Cloaked),
            ({ let mut w = normal(); w.rect = (0, 0, 0, 0); w }, Excluded::EmptyFrame),
            ({ let mut w = normal(); w.is_self = true; w }, Excluded::ServerItself),
            ({ let mut w = normal(); w.other_session = true; w }, Excluded::OtherSession),
            ({ let mut w = normal(); w.title = "  ".into(); w }, Excluded::NoTitle),
        ];
        for (window, expected) in cases {
            assert_eq!(classify(&window), Err(expected), "phải loại vì {expected:?}");
            assert!(pick(std::slice::from_ref(&window)).is_empty(), "{expected:?} lọt qua");
        }
    }

    #[test]
    fn the_shell_class_list_is_exact_not_substring() {
        // §5.4 so **class**, không so chuỗi con. Một app tên
        // `MyWorkerWidgetClass` không được bị loại oan vì có "WorkerW".
        for class in ["MyWorkerWidgetClass", "ProgmanHelper", "Shell_TrayWndX"] {
            let mut window = normal();
            window.class = class.into();
            assert_eq!(classify(&window), Ok(()), "{class} bị loại oan");
        }
        // Còn bốn class của shell thì phải loại.
        for class in SHELL_CLASSES {
            let mut window = normal();
            window.class = (*class).into();
            assert_eq!(classify(&window), Err(Excluded::ShellClass), "{class} phải bị loại");
        }
    }

    #[test]
    fn an_empty_frame_is_refused_so_we_never_click_with_bad_coordinates() {
        // §5.4: `DWMWA_EXTENDED_FRAME_BOUNDS` rỗng ⇒ loại. Đây là đường mà
        // việc gọi DWM thất bại đi vào — dùng `GetWindowRect` thay thế sẽ cho
        // toạ độ **sai** thay vì rỗng, và click lệch mép.
        for rect in [(0, 0, 0, 0), (100, 100, 100, 200), (100, 100, 200, 100), (500, 500, 100, 100)] {
            let mut window = normal();
            window.rect = rect;
            assert_eq!(classify(&window), Err(Excluded::EmptyFrame), "{rect:?} phải bị loại");
        }
    }

    #[test]
    fn z_order_is_preserved_because_users_recognise_the_top_window_first() {
        let mut top = normal();
        top.wid = 1;
        top.title = "Vừa dùng".into();
        let mut bottom = normal();
        bottom.wid = 2;
        bottom.title = "Cũ".into();
        let picked = pick(&[top, bottom]);
        assert_eq!(picked[0].hwnd, 1, "cửa sổ trên cùng phải đứng trước");
    }

    #[test]
    fn a_minimized_window_is_listed_and_flagged() {
        // §5.4: `minimized=IsIconic`. Cửa sổ thu nhỏ **vẫn** phải chọn được —
        // đó thường chính là cửa sổ người dùng muốn mở.
        let mut window = normal();
        window.minimized = true;
        let picked = pick(&[window]);
        assert_eq!(picked.len(), 1);
        assert!(picked[0].minimized, "phải báo là thu nhỏ, không loại");
    }

    #[test]
    fn an_elevated_window_gets_the_uipi_warning() {
        // §9.9b: stream được nhưng click bị UIPI chặn ⇒ cảnh báo **trước**.
        let mut elevated = normal();
        elevated.elevated = true;
        let json = windows_json(&pick_with_wids(&[elevated]));
        assert!(json.contains(r#""elevated":true"#), "{json}");
        assert!(json.contains("elevated_warn"), "phải cảnh báo trước khi bắt đầu: {json}");

        // Cửa sổ thường không có cảnh báo, và JSON vẫn hợp lệ (không `, }`).
        let plain = windows_json(&pick_with_wids(&[normal()]));
        assert!(!plain.contains("elevated_warn"), "{plain}");
        assert!(!plain.contains(", }"), "JSON hỏng: {plain}");
    }

    #[test]
    fn a_title_with_quotes_or_newlines_does_not_break_the_json() {
        // Title do **app bên thứ ba** đặt (§41.4 T5) — sẽ có dấu nháy, xuống
        // dòng, emoji. Không escape đúng là JSON hỏng và cả danh sách không
        // hiện.
        let mut window = normal();
        window.title = "Chrome \"tin tức\"\ndòng 2\\".into();
        let json = windows_json(&pick_with_wids(&[window]));
        assert!(!json.contains('\n'), "không được để xuống dòng thô: {json}");
        assert!(json.contains(r#"\"tin tức\""#), "{json}");
        assert!(json.contains(r"dòng 2\\"), "{json}");
    }

    #[test]
    fn an_empty_list_is_an_empty_array_not_a_broken_string() {
        assert_eq!(windows_json(&[]), "[]");
        assert_eq!(pick(&[]).len(), 0);
    }

    #[test]
    fn the_platform_note_explains_an_empty_list_off_windows() {
        // §58.3: không giả vờ. Danh sách rỗng trên Linux phải **nói vì sao**,
        // nếu không người dùng tưởng máy không có app nào đang mở.
        if cfg!(windows) {
            assert!(platform_note().is_none());
        } else {
            let note = platform_note().expect("phải có lời giải thích");
            assert!(note.contains("Windows"), "{note}");
        }
    }

    #[test]
    fn wid_and_hwnd_round_trip_including_high_bit_handles() {
        // hwnd là `*mut c_void`; trên Windows 64-bit giá trị thật thường có bit
        // cao bật ⇒ **âm** khi đọc như `i64`. Nếu mã hoá bằng `i64::to_string`
        // thì có dấu `-` và `WindowRegistry::authorize` từ chối (chỉ nhận hex),
        // nên client không bao giờ mở được cửa sổ. Dùng hex của `u64`.
        for hwnd in [0i64, 0x1234, -1, i64::MIN, 0x0000_0000_000A_0B0C] {
            let wid = format!("{:016x}", hwnd as u64);
            assert_eq!(hwnd_from_wid(&wid), Some(hwnd), "wid {wid}");
            assert!(wid.bytes().all(|b| b.is_ascii_hexdigit()), "wid phải là hex");
            assert!(!wid.contains('-'), "không được có dấu âm: {wid}");
        }
        assert_eq!(hwnd_from_wid(""), None);
        assert_eq!(hwnd_from_wid("zz"), None);
    }

    #[test]
    fn every_exclusion_has_a_distinct_code() {
        // Mã trùng nhau làm log/UI không phân biệt được "bị loại vì ẩn" với
        // "bị loại vì session khác".
        let all = [
            Excluded::NotVisible, Excluded::OwnedPopup, Excluded::ToolWindow,
            Excluded::NoActivate, Excluded::ShellClass, Excluded::Cloaked,
            Excluded::EmptyFrame, Excluded::ServerItself, Excluded::OtherSession,
            Excluded::NoTitle,
        ];
        let codes: std::collections::BTreeSet<&str> = all.iter().map(|e| e.code()).collect();
        assert_eq!(codes.len(), all.len(), "mỗi lý do một mã: {codes:?}");
    }
}
