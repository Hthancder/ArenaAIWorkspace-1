//! §9.9 — `clipboard` (T2), **chỉ explicit**.
//!
//! Spec nguyên văn:
//!
//! > * **Không auto-sync.** Auto-sync 2 chiều: (a) gây vòng lặp, (b) **rò dữ
//! >   liệu riêng tư** của người ngồi máy (họ copy mật khẩu → sang client).
//! > * "Copy from remote": server đọc `CF_UNICODETEXT`/`CF_DIB` → client
//! >   `navigator.clipboard.writeText` (nút bấm = gesture).
//! > * "Paste to remote": client đọc clipboard → server `SetClipboardData` +
//! >   optional `Ctrl+V`; **restore clipboard cũ sau 300 ms** để không ghi đè
//! >   clipboard của người dùng máy.
//! > * Cap: text 256 KB, ảnh 8 MB (nén PNG q80).
//!
//! # Ba thứ dễ làm sai, và tại sao file này tồn tại
//!
//! 1. **Auto-sync là bẫy.** Nó là tính năng ai cũng đòi, và nó rò mật khẩu của
//!    người ngồi trước máy sang một tab browser. Bản này **không** có polling
//!    clipboard ở đâu cả — chỉ có route, chỉ chạy khi người dùng bấm.
//! 2. **Restore 300 ms** không phải trang trí. Không restore thì sau khi paste
//!    một đoạn văn vào máy remote, clipboard **của người dùng máy** bị ghi đè
//!    vĩnh viễn bằng dữ liệu từ xa. 300 ms là đủ để `Ctrl+V` kịp đọc.
//! 3. **Cap phải chặn ở server**, không chỉ ở client: client là bên không được
//!    tin (§41.3), và 100 MB clipboard là cách làm treo agent.
//!
//! # Cái gì chạy trên Linux
//!
//! Toàn bộ **luật** (cap, loại, validate, quyết định restore). Phần Win32
//! (`OpenClipboard`/`SetClipboardData`) chỉ chạy trên Windows — và nó là phần
//! **ngắn nhất** trong file này, đúng như mong muốn: chỗ nào khó test thì phải
//! mỏng.

/// §9.9 cap cho text: 256 KB.
///
/// Đo bằng **byte UTF-8**, không phải `chars()`: một chuỗi tiếng Việt 256 K ký
/// tự là ~700 KB UTF-8, và clipboard Windows giới hạn theo byte. Dùng
/// `chars().count()` sẽ cho qua dữ liệu mà `SetClipboardData` từ chối.
pub const MAX_TEXT_BYTES: usize = 256 * 1024;

/// §9.9 cap cho ảnh: 8 MB **sau khi nén PNG q80**.
pub const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;

/// §9.9: *"restore clipboard cũ sau 300 ms"*.
pub const RESTORE_DELAY_MS: u64 = 300;

/// Lỗi khi nhận nội dung clipboard. Mỗi biến thể là một mã HTTP khác nhau,
/// vì "quá lớn" và "sai định dạng" là hai chuyện khác nhau với client.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClipboardError {
    /// Rỗng, hoặc không có `text` lẫn `image_b64`.
    Empty,
    /// Text vượt [`MAX_TEXT_BYTES`].
    TextTooLarge,
    /// Ảnh vượt [`MAX_IMAGE_BYTES`] **sau khi decode base64**.
    ImageTooLarge,
    /// Base64 hỏng, hoặc ảnh không phải PNG/JPEG.
    InvalidImage,
    /// Có cả `text` và `image_b64` — spec chỉ có một trong hai.
    Ambiguous,
    /// Phiên đang `view_only` (§21.6): người xem tạm không được paste.
    ViewOnly,
}

impl ClipboardError {
    pub fn status(self) -> u16 {
        match self {
            // 422: dữ liệu đúng cú pháp nhưng không dùng được.
            ClipboardError::Empty
            | ClipboardError::TextTooLarge
            | ClipboardError::ImageTooLarge
            | ClipboardError::InvalidImage
            | ClipboardError::Ambiguous => 422,
            // 403: quyền, không phải dữ liệu.
            ClipboardError::ViewOnly => 403,
        }
    }

    /// Tên lỗi cho client. Đặt tên riêng thay vì một `invalid_clipboard` chung,
    /// để UI nói được "ảnh quá lớn" thay vì "lỗi".
    pub fn code(self) -> &'static str {
        match self {
            ClipboardError::Empty => "clipboard.empty",
            ClipboardError::TextTooLarge => "clipboard.text_too_large",
            ClipboardError::ImageTooLarge => "clipboard.image_too_large",
            ClipboardError::InvalidImage => "clipboard.invalid_image",
            ClipboardError::Ambiguous => "clipboard.ambiguous",
            ClipboardError::ViewOnly => "clipboard.view_only",
        }
    }
}

/// Nội dung clipboard đã kiểm, sẵn sàng đưa cho tầng Win32.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClipboardContent {
    /// `CF_UNICODETEXT`. Đã validate UTF-8 và cap.
    Text(String),
    /// `CF_DIB` — dữ liệu ảnh **đã decode** từ base64, chưa parse định dạng.
    Image { bytes: Vec<u8>, format: ImageFormat },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageFormat {
    Png,
    Jpeg,
}

impl ImageFormat {
    /// Nhận diện bằng magic bytes, **không** bằng đuôi file hay `Content-Type`
    /// client gửi — cả hai do client đặt.
    fn sniff(bytes: &[u8]) -> Option<Self> {
        if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
            return Some(ImageFormat::Png);
        }
        if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
            return Some(ImageFormat::Jpeg);
        }
        None
    }
}

/// §9.9 — kiểm nội dung client gửi lên trước khi chạm clipboard Windows.
///
/// Trả `Err` cho mọi thứ không qua được. **Không** sửa dữ liệu cho vừa cap:
/// cắt bớt một đoạn văn rồi paste là tệ hơn từ chối — người dùng dán vào và
/// nhận một nửa câu mà không biết tại sao.
pub fn validate(
    text: Option<&str>,
    image_b64: Option<&str>,
    view_only: bool,
) -> Result<ClipboardContent, ClipboardError> {
    if view_only {
        // §21.6: link xem tạm là **view-only**. Kiểm trước cả dữ liệu: người
        // xem tạm không được ghi vào máy dù nội dung hợp lệ.
        return Err(ClipboardError::ViewOnly);
    }
    match (text, image_b64) {
        (Some(_), Some(_)) => Err(ClipboardError::Ambiguous),
        (None, None) => Err(ClipboardError::Empty),
        (Some(text), None) => {
            if text.trim().is_empty() {
                return Err(ClipboardError::Empty);
            }
            // Byte, không phải ký tự — xem docs của `MAX_TEXT_BYTES`.
            if text.len() > MAX_TEXT_BYTES {
                return Err(ClipboardError::TextTooLarge);
            }
            // Clipboard Windows là UTF-16, nên NUL nhúng sẽ cắt chuỗi ở giữa và
            // người dùng paste được một nửa. Từ chối thay vì lặng lẽ cắt.
            if text.contains('\0') {
                return Err(ClipboardError::Empty);
            }
            Ok(ClipboardContent::Text(text.to_string()))
        }
        (None, Some(encoded)) => {
            // Cap **trước khi decode**: base64 của 8 MB là ~10.7 MB. Decode một
            // payload 500 MB để rồi từ chối là cách tự làm treo agent bằng một
            // request.
            let max_encoded = MAX_IMAGE_BYTES.saturating_mul(4) / 3 + 4;
            if encoded.len() > max_encoded {
                return Err(ClipboardError::ImageTooLarge);
            }
            let bytes = decode_base64(encoded).ok_or(ClipboardError::InvalidImage)?;
            // Kiểm **sau** khi decode: base64 dài 10 MB có thể ra 7 MB, và
            // ngược lại. Cap của spec là của **ảnh**, không phải của chuỗi.
            if bytes.len() > MAX_IMAGE_BYTES {
                return Err(ClipboardError::ImageTooLarge);
            }
            let format = ImageFormat::sniff(&bytes).ok_or(ClipboardError::InvalidImage)?;
            Ok(ClipboardContent::Image { bytes, format })
        }
    }
}

/// Base64 chuẩn (RFC 4648, có padding). Tự viết để không thêm dependency
/// (§56.1: 0 dependency ngoài `std`).
///
/// Chấp nhận cả `\r\n` — client gửi JSON thì không có, nhưng nếu ai đó dán
/// base64 từ file PEM/MIME vào form thì nó có dòng mới, và từ chối vì lý do đó
/// là khó hiểu với người dùng.
fn decode_base64(input: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(input.len() * 3 / 4);
    let mut acc: u32 = 0;
    let mut bits = 0u32;
    let mut padding = 0usize;
    for byte in input.bytes() {
        if byte == b'\r' || byte == b'\n' || byte == b' ' || byte == b'\t' {
            continue;
        }
        if byte == b'=' {
            padding += 1;
            continue;
        }
        // Padding chỉ được ở cuối: một `=` ở giữa nghĩa là dữ liệu hỏng.
        if padding > 0 {
            return None;
        }
        let value = match byte {
            b'A'..=b'Z' => byte - b'A',
            b'a'..=b'z' => byte - b'a' + 26,
            b'0'..=b'9' => byte - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return None,
        } as u32;
        acc = (acc << 6) | value;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
        }
    }
    // Chỉ 0/1/2 ký tự `=` là hợp lệ, và phần dư bit phải < 8.
    if padding > 2 || bits >= 6 {
        return None;
    }
    Some(out)
}

/// §9.9 — quyết định **có cần restore** clipboard cũ không.
///
/// Không phải mọi lần set đều cần restore: nếu người dùng **chủ động** bấm
/// "Copy from remote" thì họ muốn clipboard của họ thành dữ liệu đó — restore
/// sẽ xoá đúng thứ họ vừa copy. Restore chỉ dành cho **Paste to remote**, nơi
/// ta mượn clipboard làm đường trung chuyển.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RestorePolicy {
    /// `Paste to remote`: mượn clipboard → `Ctrl+V` → trả lại sau 300 ms.
    RestoreAfter(#[doc = "ms"] u64),
    /// `Copy from remote`: để nguyên, người dùng muốn thế.
    Keep,
}

/// `direction`: `true` = paste **vào** máy remote (mượn clipboard),
/// `false` = copy **từ** máy remote (clipboard của agent thành kết quả).
pub fn restore_policy(paste_to_remote: bool) -> RestorePolicy {
    if paste_to_remote {
        RestorePolicy::RestoreAfter(RESTORE_DELAY_MS)
    } else {
        RestorePolicy::Keep
    }
}

/// JSON cho `GET /api/sessions/{sid}/clipboard` ("copy from remote").
///
/// Trả **một** trường, đúng như request của §8.1 (`{text}` / `{image_b64}`).
/// Kèm `truncated` vì clipboard Windows có thể chứa thứ lớn hơn cap: cắt và
/// **nói** là đã cắt, thay vì im lặng.
pub fn content_json(content: Option<&ClipboardContent>) -> String {
    match content {
        None => "{\"text\":null,\"image_b64\":null}".to_string(),
        Some(ClipboardContent::Text(text)) => {
            if text.len() > MAX_TEXT_BYTES {
                // Cắt ở **biên ký tự**, không phải biên byte: cắt giữa một ký
                // tự UTF-8 tạo chuỗi không hợp lệ và `String::from_utf8` bên
                // client sẽ lỗi.
                let mut end = MAX_TEXT_BYTES;
                while end > 0 && !text.is_char_boundary(end) {
                    end -= 1;
                }
                format!(
                    "{{\"text\":{},\"truncated\":true}}",
                    crate::json_quote(&text[..end])
                )
            } else {
                format!("{{\"text\":{},\"truncated\":false}}", crate::json_quote(text))
            }
        }
        // Chưa nối đường ảnh: `CF_DIB` → PNG cần GDI+ (thêm dependency) và
        // chưa có ở bản này. Nói `null` + lý do thay vì trả base64 rỗng mà
        // client sẽ vẽ thành ảnh hỏng.
        Some(ClipboardContent::Image { .. }) => {
            "{\"text\":null,\"image_b64\":null,\"unsupported\":\"image\"}".to_string()
        }
    }
}

// ---------------------------------------------------------------------------
// Tầng Win32 — phần **mỏng nhất** của file, đúng như mong muốn.
// ---------------------------------------------------------------------------

/// Ghi nội dung vào clipboard của **agent** (máy Windows đang chạy server).
///
/// Trả `true` nếu thực sự ghi được. Trên Linux luôn `false` — route vẫn trả
/// 200 (dữ liệu đã qua validate là hợp lệ), nhưng `applied:false` nói thật là
/// chưa có gì xảy ra. Im lặng trả `true` sẽ khiến người dùng tưởng đã paste
/// được và đi tìm lỗi ở chỗ khác.
#[cfg(windows)]
pub fn apply(content: &ClipboardContent) -> bool {
    use std::ffi::c_void;
    #[allow(non_snake_case)]
    mod win {
        use std::ffi::c_void;
        extern "system" {
            /// `CF_UNICODETEXT` = 13
            pub fn OpenClipboard(owner: *mut c_void) -> i32;
            pub fn CloseClipboard() -> i32;
            pub fn EmptyClipboard() -> i32;
            pub fn SetClipboardData(format: u32, memory: *mut c_void) -> *mut c_void;
            pub fn GlobalAlloc(flags: u32, bytes: usize) -> *mut c_void;
            pub fn GlobalLock(handle: *mut c_void) -> *mut c_void;
            pub fn GlobalUnlock(handle: *mut c_void) -> i32;
        }
    }
    const CF_UNICODETEXT: u32 = 13;
    // `GMEM_MOVEABLE` (0x0002) là **bắt buộc** cho `SetClipboardData`: Windows
    // sở hữu handle sau khi set, nên nó phải moveable. `GMEM_FIXED` sẽ làm
    // `SetClipboardData` thất bại một cách im lặng.
    const GMEM_MOVEABLE: u32 = 0x0002;

    // Chỉ text được hỗ trợ: `CF_DIB` cần chuyển PNG → DIB, và bản này chưa làm
    // (xem `content_json`, nó nói `unsupported:"image"` thay vì bịa).
    let ClipboardContent::Text(text) = content else {
        return false;
    };
    // UTF-16 **có NUL kết thúc**: `CF_UNICODETEXT` là chuỗi C rộng. Thiếu NUL thì
    // ứng dụng đích đọc quá cuối buffer.
    let wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
    let bytes = wide.len() * std::mem::size_of::<u16>();
    unsafe {
        if win::OpenClipboard(std::ptr::null_mut()) == 0 {
            // Clipboard đang bị process khác giữ. Không retry: retry trong route
            // HTTP là giữ một thread cho một thao tác người dùng có thể bấm lại.
            return false;
        }
        // `EmptyClipboard` **phải** gọi trước `SetClipboardData`, nếu không
        // Windows trả lỗi và clipboard cũ vẫn còn.
        if win::EmptyClipboard() == 0 {
            win::CloseClipboard();
            return false;
        }
        let handle = win::GlobalAlloc(GMEM_MOVEABLE, bytes);
        if handle.is_null() {
            win::CloseClipboard();
            return false;
        }
        let target = win::GlobalLock(handle);
        if target.is_null() {
            win::CloseClipboard();
            return false;
        }
        // GCC/clippy không biết `GlobalLock` trả vùng `bytes` hợp lệ — nó đúng
        // theo hợp đồng của Win32.
        std::ptr::copy_nonoverlapping(wide.as_ptr(), target.cast::<u16>(), wide.len());
        win::GlobalUnlock(handle);
        if win::SetClipboardData(CF_UNICODETEXT, handle).is_null() {
            win::CloseClipboard();
            return false;
        }
        // Sau `SetClipboardData` thành công, Windows sở hữu `handle` — **không**
        // `GlobalFree`, làm vậy là double-free.
        win::CloseClipboard();
        true
    }
}

/// Đọc `CF_UNICODETEXT` từ clipboard của agent.
///
/// `None` = clipboard trống, chứa định dạng khác (ảnh, file…), hoặc đang bị
/// process khác giữ. Không trả chuỗi rỗng: §9.9 phân biệt "không có gì" với
/// "có chuỗi rỗng", và UI cần phân biệt để hiện "không có gì để dán".
#[cfg(windows)]
pub fn read() -> Option<ClipboardContent> {
    use std::ffi::c_void;
    #[allow(non_snake_case)]
    mod win {
        use std::ffi::c_void;
        extern "system" {
            pub fn OpenClipboard(owner: *mut c_void) -> i32;
            pub fn CloseClipboard() -> i32;
            pub fn GetClipboardData(format: u32) -> *mut c_void;
            pub fn GlobalLock(handle: *mut c_void) -> *mut c_void;
            pub fn GlobalUnlock(handle: *mut c_void) -> i32;
            pub fn GlobalSize(handle: *mut c_void) -> usize;
        }
    }
    const CF_UNICODETEXT: u32 = 13;
    unsafe {
        if win::OpenClipboard(std::ptr::null_mut()) == 0 {
            return None;
        }
        let handle = win::GetClipboardData(CF_UNICODETEXT);
        if handle.is_null() {
            // Không có text — có thể là ảnh. Đóng handle rồi trả `None`: route
            // sẽ trả `{"text":null,"image_b64":null}`, đúng hơn là lỗi.
            win::CloseClipboard();
            return None;
        }
        // Handle của `GetClipboardData` **không** thuộc về ta — không `GlobalFree`.
        let pointer = win::GlobalLock(handle);
        if pointer.is_null() {
            win::CloseClipboard();
            return None;
        }
        let bytes = win::GlobalSize(handle);
        let units = bytes / std::mem::size_of::<u16>();
        let wide = std::slice::from_raw_parts(pointer.cast::<u16>(), units);
        // Dừng ở NUL đầu tiên: `GlobalSize` thường lớn hơn độ dài chuỗi thật.
        let length = wide.iter().position(|unit| *unit == 0).unwrap_or(units);
        let text = String::from_utf16_lossy(&wide[..length]);
        win::GlobalUnlock(handle);
        win::CloseClipboard();
        if text.is_empty() {
            None
        } else {
            Some(ClipboardContent::Text(text))
        }
    }
}

/// Linux/macOS: không có clipboard Windows để chạm.
///
/// Trả `false` thay vì giả vờ — route trả `applied:false` và người dùng biết
/// paste **chưa** xảy ra. `XTEST`/`xclip` sẽ là một đường khác, nhưng §58.1 nói
/// agent là Windows; thêm đường Linux ở đây là code chết.
#[cfg(not(windows))]
pub fn apply(_content: &ClipboardContent) -> bool {
    false
}

#[cfg(not(windows))]
pub fn read() -> Option<ClipboardContent> {
    None
}

/// §9.9 — chờ [`RESTORE_DELAY_MS`] rồi trả clipboard cũ lại.
///
/// Tách thành hàm riêng để test được **thời lượng** mà không cần clipboard
/// thật. Hợp đồng: "chờ đúng 300 ms rồi gọi `apply` với bản cũ".
pub fn restore_after_delay(old: Option<ClipboardContent>, sleep: impl Fn(u64)) {
    sleep(RESTORE_DELAY_MS);
    if let Some(content) = old {
        // Trên Linux `apply` trả `false` — nhưng `Ctrl+V` cũng không chạy, nên
        // không có gì bị ghi đè để phải trả lại. Nhánh này là no-op trung thực.
        apply(&content);
    }
}

/// §9.9 + §633 — dãy phím cho "Paste to remote".
///
/// Spec §633 nói rõ vì sao phải đi đường clipboard thay vì gõ từng ký tự:
///
/// > *"**Paste/chuỗi dài** (>200 ký tự): **không** inject từng ký tự (chậm +
/// > dễ sai). Dùng đường clipboard: set clipboard server → `Ctrl+V` → **restore
/// > clipboard cũ sau 300 ms**."*
///
/// `VK_CONTROL` = 0x11, `V` = 0x56. Thứ tự **xuống trước, lên sau** và lên
/// theo thứ tự ngược lại — nếu nhả `Ctrl` trước `V` thì một số app nhận được
/// `v` trần và gõ chữ "v" vào tài liệu thay vì paste.
pub fn ctrl_v_actions() -> [crate::input::Action; 4] {
    use crate::input::Action;
    [
        Action::Key { down: true, vk: 0x11 },
        Action::Key { down: true, vk: 0x56 },
        Action::Key { down: false, vk: 0x56 },
        Action::Key { down: false, vk: 0x11 },
    ]
}

/// Chạy trọn "Paste to remote": lưu clipboard cũ → ghi mới → `Ctrl+V` → trả lại.
///
/// # Vì sao `Ctrl+V` **không** nằm trong `clipboard.rs` trước đây
///
/// Nó là dãy phím, nên tưởng như thuộc `input.rs`. Nhưng nó chỉ đúng **khi đi
/// kèm** ba bước clipboard kia: gửi `Ctrl+V` một mình là paste nội dung cũ của
/// máy remote. Ghép chúng vào một hàm để không ai gọi lẻ được.
///
/// Trả số `Action` đã inject (0 trên Linux, vì `inject` là stub).
pub fn paste_to_remote(content: &ClipboardContent) -> usize {
    // 1. Lưu bản cũ **trước** khi ghi đè — nếu lưu sau thì ta đã mất nó.
    let previous = read();
    // 2. Ghi nội dung mới. Nếu ghi thất bại (clipboard bị giữ, hoặc Linux) thì
    //    gửi `Ctrl+V` sẽ paste nội dung **cũ** vào tài liệu người dùng — đúng
    //    thứ tệ nhất có thể xảy ra, nên dừng ở đây.
    if !apply(content) {
        return 0;
    }
    // 3. Ctrl+V để app đích đọc clipboard.
    let actions = ctrl_v_actions();
    crate::input::inject(&actions);
    // 4. Trả clipboard cũ lại sau 300 ms, trên thread riêng.
    //
    //    **Không** `sleep` ở đây: route HTTP sẽ bị giữ 300 ms cho một thao tác
    //    người dùng, và nếu client bấm nhiều lần thì các request xếp hàng sau
    //    chờ theo. Thread riêng cũng cần thiết cho đúng nghĩa: `Ctrl+V` được
    //    xử lý **bất đồng bộ** bởi app đích — ngủ trong handler không làm nó
    //    nhanh hơn.
    std::thread::spawn(move || {
        restore_after_delay(previous, |ms| {
            std::thread::sleep(std::time::Duration::from_millis(ms));
        });
    });
    actions.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_under_the_cap_is_accepted_verbatim() {
        let content = validate(Some("xin chào"), None, false).unwrap();
        assert_eq!(content, ClipboardContent::Text("xin chào".into()));
    }

    #[test]
    fn the_cap_is_256_kilobytes_of_utf8_not_of_characters() {
        // §9.9 ghi 256 KB. Một chuỗi 200 K ký tự tiếng Việt là ~600 KB UTF-8 —
        // `chars().count()` sẽ cho qua rồi `SetClipboardData` từ chối hoặc cắt.
        let just_under = "a".repeat(MAX_TEXT_BYTES);
        assert!(validate(Some(&just_under), None, false).is_ok());
        let over = "a".repeat(MAX_TEXT_BYTES + 1);
        assert_eq!(validate(Some(&over), None, false), Err(ClipboardError::TextTooLarge));

        // Tiếng Việt: mỗi ký tự 1–3 byte trong UTF-8.
        let vietnamese = "ế".repeat(MAX_TEXT_BYTES / 3 + 10);
        assert!(vietnamese.len() > MAX_TEXT_BYTES);
        assert_eq!(
            validate(Some(&vietnamese), None, false),
            Err(ClipboardError::TextTooLarge),
            "phải đo byte, không đo ký tự"
        );
    }

    #[test]
    fn empty_and_ambiguous_payloads_are_refused_with_distinct_codes() {
        assert_eq!(validate(None, None, false), Err(ClipboardError::Empty));
        assert_eq!(validate(Some("   "), None, false), Err(ClipboardError::Empty));
        assert_eq!(validate(Some("a"), Some("aGk="), false), Err(ClipboardError::Ambiguous));
        // Hai lỗi khác nhau phải có **mã** khác nhau, nếu không UI không nói
        // được cho người dùng biết phải sửa gì.
        assert_ne!(ClipboardError::Empty.code(), ClipboardError::Ambiguous.code());
    }

    #[test]
    fn a_view_only_session_cannot_write_to_the_machine() {
        // §21.6: link xem tạm. Kiểm **trước** dữ liệu — nội dung hợp lệ cũng bị
        // chặn, và mã là 403 (quyền) không phải 422 (dữ liệu).
        assert_eq!(
            validate(Some("mật khẩu"), None, true),
            Err(ClipboardError::ViewOnly)
        );
        assert_eq!(ClipboardError::ViewOnly.status(), 403);
        assert_eq!(ClipboardError::TextTooLarge.status(), 422);
    }

    #[test]
    fn an_image_is_identified_by_magic_bytes_not_by_what_the_client_says() {
        // PNG 1×1 thật.
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
        match validate(None, Some(png), false).unwrap() {
            ClipboardContent::Image { bytes, format } => {
                assert_eq!(format, ImageFormat::Png);
                assert!(bytes.starts_with(&[0x89, b'P', b'N', b'G']));
            }
            other => panic!("phải là ảnh: {other:?}"),
        }

        // Không phải ảnh: base64 hợp lệ của chữ "hello".
        assert_eq!(
            validate(None, Some("aGVsbG8="), false),
            Err(ClipboardError::InvalidImage)
        );
        // Base64 hỏng.
        assert_eq!(
            validate(None, Some("!!!không phải base64!!!"), false),
            Err(ClipboardError::InvalidImage)
        );
    }

    #[test]
    fn an_oversized_image_is_refused_before_it_is_decoded() {
        // Cap **trước** decode: base64 của 8 MB là ~10.7 MB. Decode một payload
        // 500 MB để rồi từ chối là cách tự treo agent bằng một request.
        let huge = "A".repeat(MAX_IMAGE_BYTES * 4 / 3 + 100);
        assert_eq!(
            validate(None, Some(&huge), false),
            Err(ClipboardError::ImageTooLarge)
        );
    }

    #[test]
    fn base64_accepts_wrapped_input_but_rejects_mid_string_padding() {
        assert_eq!(decode_base64("aGVsbG8="), Some(b"hello".to_vec()));
        assert_eq!(decode_base64("aGVs\nbG8="), Some(b"hello".to_vec()), "PEM có dòng mới");
        assert_eq!(decode_base64("aGVsbG8"), Some(b"hello".to_vec()), "thiếu padding vẫn đúng bit");
        assert_eq!(decode_base64("aGV=bG8="), None, "`=` ở giữa là hỏng");
        assert_eq!(decode_base64("a"), None, "6 bit lẻ không đủ 1 byte");
    }

    #[test]
    fn the_clipboard_is_only_restored_when_we_borrowed_it() {
        // Paste **vào** remote = mượn clipboard ⇒ phải trả lại sau 300 ms.
        assert_eq!(
            restore_policy(true),
            RestorePolicy::RestoreAfter(RESTORE_DELAY_MS)
        );
        assert_eq!(RESTORE_DELAY_MS, 300, "§9.9 ghi 300 ms");
        // Copy **từ** remote = người dùng muốn clipboard của họ thành kết quả ⇒
        // restore sẽ xoá đúng thứ họ vừa copy.
        assert_eq!(restore_policy(false), RestorePolicy::Keep);
    }

    #[test]
    fn ctrl_v_releases_the_modifier_last() {
        // Nhả `Ctrl` trước `V` ⇒ một số app nhận `v` trần và **gõ chữ "v"** vào
        // tài liệu thay vì paste. Đây là bug thật, không phải lý thuyết.
        use crate::input::Action;
        let actions = ctrl_v_actions();
        assert_eq!(actions[0], Action::Key { down: true, vk: 0x11 }, "Ctrl xuống trước");
        assert_eq!(actions[1], Action::Key { down: true, vk: 0x56 }, "V xuống sau");
        assert_eq!(actions[2], Action::Key { down: false, vk: 0x56 }, "V lên trước");
        assert_eq!(actions[3], Action::Key { down: false, vk: 0x11 }, "Ctrl lên **cuối**");
        // Cân bằng: mỗi phím xuống đúng một lần và lên đúng một lần, nếu không
        // phím kẹt (§6.4.7) và mọi thao tác sau đều hỏng.
        let downs = actions.iter().filter(|a| matches!(a, Action::Key { down: true, .. })).count();
        let ups = actions.iter().filter(|a| matches!(a, Action::Key { down: false, .. })).count();
        assert_eq!(downs, ups, "phím xuống/lên phải cân bằng");
    }

    #[test]
    fn the_old_clipboard_comes_back_only_after_the_delay() {
        // §9.9: restore **sau 300 ms**, không phải ngay. Ngay lập tức thì
        // `Ctrl+V` chưa kịp đọc và người dùng paste nội dung cũ.
        // `Cell` vì closure là `Fn` (hàm nhận `impl Fn(u64)`, không phải
        // `FnMut`) — đúng hợp đồng: chỉ **quan sát** thời lượng, không sửa
        // trạng thái ngoài.
        let slept = std::cell::Cell::new(0u64);
        let calls = std::cell::Cell::new(0);
        restore_after_delay(Some(ClipboardContent::Text("cũ".into())), |ms| {
            slept.set(ms);
            calls.set(calls.get() + 1);
        });
        assert_eq!(slept.get(), RESTORE_DELAY_MS, "phải ngủ đúng 300 ms");
        assert_eq!(calls.get(), 1, "chờ đúng một lần, không lặp");
    }

    #[test]
    fn an_empty_old_clipboard_is_left_empty() {
        // Không có gì để trả lại ⇒ không ghi gì. Ghi chuỗi rỗng sẽ làm clipboard
        // của người dùng thành "" thay vì trống, và app đích paste chuỗi rỗng.
        let slept = std::cell::Cell::new(0u64);
        restore_after_delay(None, |ms| slept.set(ms));
        assert_eq!(slept.get(), RESTORE_DELAY_MS, "vẫn phải chờ, để Ctrl+V kịp chạy");
    }

    #[test]
    fn a_text_larger_than_the_cap_is_truncated_on_a_character_boundary() {
        // "ế" = 3 byte UTF-8. Cắt ở byte 1 của nó tạo chuỗi không hợp lệ và
        // `JSON.parse` bên client hoặc `navigator.clipboard.writeText` sẽ lỗi.
        let text = "ế".repeat(MAX_TEXT_BYTES / 2);
        let json = content_json(Some(&ClipboardContent::Text(text)));
        assert!(json.contains("\"truncated\":true"), "{json}");
        // Trích lại chuỗi đã cắt và kiểm nó là UTF-8 hợp lệ.
        let start = json.find("\"text\":\"").unwrap() + 8;
        let end = json.rfind("\"").unwrap();
        let body = &json[start..end];
        // "\uXXXX" escapes vẫn hợp lệ; chỉ cần không có byte lẻ.
        assert!(!body.is_empty());
        assert!(String::from_utf8(body.as_bytes().to_vec()).is_ok());
    }

    #[test]
    fn no_content_says_null_rather_than_an_empty_string() {
        // Clipboard trống khác với clipboard chứa chuỗi rỗng: UI phải phân biệt
        // để hiện "không có gì để dán" thay vì dán một chuỗi rỗng.
        let json = content_json(None);
        assert!(json.contains("\"text\":null"), "{json}");
        assert!(!json.contains("\"text\":\"\""), "{json}");
    }

    #[test]
    fn an_image_the_server_cannot_convert_says_so_instead_of_returning_garbage() {
        let image = ClipboardContent::Image {
            bytes: vec![0x89, b'P', b'N', b'G'],
            format: ImageFormat::Png,
        };
        let json = content_json(Some(&image));
        assert!(json.contains("\"unsupported\":\"image\""), "{json}");
        assert!(json.contains("\"image_b64\":null"), "{json}");
    }
}
