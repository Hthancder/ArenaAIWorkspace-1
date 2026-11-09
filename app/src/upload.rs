//! §50.3 — gửi 1 file **một chiều** client → server.
//!
//! Spec (bảng §50.3):
//!
//! > ✅ dán ảnh/tài liệu sang máy ở nhà trong 1 cú kéo
//! > ⚠️ cần: giới hạn **50 MB**, đuôi file chặn (`exe/ps1/bat/scr/lnk`), ghi vào
//! > `%USERPROFILE%\Downloads\RD\`, **có** hộp xác nhận hiện tên + dung lượng,
//! > **không** tự mở
//! > ⚠️ **không** làm chiều server → client
//!
//! Và §8.1 ghi thêm: *"**chỉ khi bật**"*, trả `{path,size,sha256}`.
//!
//! # Bốn thứ dễ làm sai
//!
//! 1. **Đuôi file**: kiểm `exe/ps1/bat/scr/lnk` là **chưa đủ** nếu chỉ so chuỗi
//!    cuối. `report.pdf.exe` phải bị chặn (nó bị, vì ta so đuôi cuối). Nhưng
//!    `report.exe.txt` thì **không** nguy hiểm (Windows mở bằng Notepad), nên
//!    không được chặn — chặn quá tay làm người dùng tưởng app hỏng. Và phải so
//!    **không phân biệt hoa/thường**: Windows không phân biệt, `PAYLOAD.EXE`
//!    chạy được.
//! 2. **Tên file**: `..\..\Windows\System32\x.dll` là đường dẫn **ghép** vào
//!    thư mục đích. Không lọc thì upload ghi đè được file hệ thống. Cắt về
//!    `file_name()` và từ chối `.`/`..`.
//! 3. **50 MB** đo trên **phần file**, không phải trên cả multipart body (có
//!    boundary + header riêng). Đo sai chỗ thì file 49 MB bị từ chối oan.
//! 4. **Không tự mở** — và cũng **không** trả về đường dẫn mà client có thể
//!    dùng để mở. Đây là ghi một chiều.
//!
//! # Vì sao file này chạy được trên Linux
//!
//! Toàn bộ **luật** (đuôi, tên, cap, quyết định bật/tắt) là hàm thuần và có
//! test. Phần ghi đĩa dùng `std::fs` — chạy được cả hai nền. Chỉ *thư mục đích*
//! khác nhau (`%USERPROFILE%\Downloads\RD\` trên Windows).

use std::path::{Path, PathBuf};

/// §50.3: giới hạn 50 MB, đo trên **nội dung file**.
pub const MAX_FILE_BYTES: usize = 50 * 1024 * 1024;

/// §8.1/§50.3 — danh sách đuôi bị chặn, **nguyên văn từ spec**.
///
/// Đây là danh sách **chặn** (deny-list), không phải cho phép (allow-list). Spec
/// chọn cách này vì nó ít làm phiền người dùng hơn: một allow-list sẽ từ chối
/// `.psd`, `.sketch`, `.7z`… những thứ hoàn toàn vô hại.
///
/// Giới hạn của deny-list là **thật** và phải nói ra: `.lnk` bị chặn, nhưng
/// `.url`, `.hta`, `.js`, `.vbs`, `.wsf` cũng mở được bằng một cú double-click
/// trên Windows và **không** có trong spec. Bản này theo đúng spec (5 đuôi) và
/// ghi rõ khoảng trống đó trong [`UploadError::code`]… không, ghi ở đây:
/// **danh sách của spec chưa đủ**; thêm `.hta/.vbs/.js/.wsf/.url` là quyết định
/// của người dùng vì nó làm chặn nhiều hơn. Xem [`BLOCKED_EXTENSIONS`].
pub const BLOCKED_EXTENSIONS: &[&str] = &["exe", "ps1", "bat", "scr", "lnk"];

/// §50.3 — thư mục đích **tương đối** với home của người dùng.
///
/// Spec ghi `%USERPROFILE%\Downloads\RD\`. Trên Linux dùng cùng cấu trúc để
/// đường dẫn trong report/test giống nhau.
pub const UPLOAD_SUBDIR: &str = "Downloads/RD";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UploadError {
    /// §8.1: route **chỉ khi bật**. Tắt ⇒ 403, không phải 404: route tồn tại,
    /// tính năng đang tắt, và người dùng cần biết để bật.
    Disabled,
    /// File rỗng — không phải file.
    Empty,
    /// > 50 MB.
    TooLarge,
    /// Đuôi trong [`BLOCKED_EXTENSIONS`].
    BlockedExtension(String),
    /// Tên file không dùng được: rỗng, `.`/`..`, hoặc chứa ký tự điều khiển.
    InvalidName,
    /// Multipart hỏng: không có boundary, không có phần `file`.
    MalformedMultipart,
}

impl UploadError {
    pub fn status(self) -> u16 {
        match self {
            // Tính năng tắt/không có quyền.
            UploadError::Disabled => 403,
            // Vượt cap: 413 là mã đúng của HTTP cho việc này.
            UploadError::TooLarge => 413,
            // Dữ liệu hỏng/không dùng được.
            UploadError::Empty
            | UploadError::BlockedExtension(_)
            | UploadError::InvalidName
            | UploadError::MalformedMultipart => 422,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            UploadError::Disabled => "upload.disabled",
            UploadError::Empty => "upload.empty",
            UploadError::TooLarge => "upload.too_large",
            UploadError::BlockedExtension(_) => "upload.blocked_extension",
            UploadError::InvalidName => "upload.invalid_name",
            UploadError::MalformedMultipart => "upload.malformed",
        }
    }
}

/// Tên file đã kiểm, sẵn sàng dùng làm tên trên đĩa.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SafeName {
    /// Chỉ tên, **không** đường dẫn.
    pub name: String,
}

/// Kiểm tên file client gửi trong `Content-Disposition`.
///
/// # Vì sao không dùng thẳng tên client gửi
///
/// `filename="..\..\Windows\System32\kernel32.dll"` ghép vào
/// `Downloads/RD/` sẽ ghi **ngoài** thư mục đích. Windows chấp nhận cả `\` và
/// `/` làm dấu phân cách, nên phải cắt cả hai.
pub fn safe_name(raw: &str) -> Result<SafeName, UploadError> {
    // Bỏ mọi đường dẫn: lấy thành phần **cuối** sau cả `/` và `\`. Không dùng
    // `Path::file_name()` một mình vì trên Linux nó không coi `\` là dấu phân
    // cách, nên `..\..\x.dll` sẽ lọt nguyên.
    // **Không** `.trim()` ở đây: `"name "` (có dấu cách cuối) là tên Windows sẽ
    // tự cắt khi tạo file. Trim trước rồi kiểm `ends_with(' ')` thì kiểm không
    // bao giờ chạy — đó là bug thật của bản đầu, và nó làm file trên đĩa khác
    // tên đã báo cho người dùng.
    let name = raw.rsplit(['/', '\\']).next().unwrap_or(raw);

    if name.is_empty() || name == "." || name == ".." {
        return Err(UploadError::InvalidName);
    }
    // Ký tự điều khiển (NUL, xuống dòng) làm hỏng tên trên Windows và có thể
    // cắt chuỗi ở tầng NT. Từ chối thay vì lọc, vì tên hợp lệ không có chúng.
    if name.chars().any(|c| c.is_control()) {
        return Err(UploadError::InvalidName);
    }
    // Windows cấm 9 ký tự này trong tên file. Cho qua thì ghi sẽ thất bại với
    // lỗi khó hiểu; từ chối sớm thì nói được lý do.
    if name.chars().any(|c| "<>:\"|?*".contains(c)) {
        return Err(UploadError::InvalidName);
    }
    // Tên kết thúc bằng dấu chấm hoặc khoảng trắng: Windows tự cắt khi tạo file,
    // nên file trên đĩa sẽ khác tên đã báo cho người dùng.
    if name.ends_with('.') || name.ends_with(' ') {
        return Err(UploadError::InvalidName);
    }
    // Tên bắt đầu bằng khoảng trắng cũng bị Windows cắt — cùng lý do.
    if name.starts_with(' ') {
        return Err(UploadError::InvalidName);
    }

    // Đuôi file: **không phân biệt hoa/thường**, và lấy đuôi **cuối cùng**.
    // `payload.EXE` chạy được trên Windows; `report.pdf.exe` cũng vậy.
    if let Some(extension) = name.rsplit_once('.').map(|(_, ext)| ext) {
        let lowered = extension.to_ascii_lowercase();
        if BLOCKED_EXTENSIONS.contains(&lowered.as_str()) {
            return Err(UploadError::BlockedExtension(lowered));
        }
        // Đuôi rỗng (`file.`) đã bị chặn ở trên.
    }

    Ok(SafeName { name: name.to_string() })
}

/// File upload đã kiểm, sẵn sàng ghi.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Upload {
    pub name: String,
    pub bytes: Vec<u8>,
}

/// §50.3 — kiểm **toàn bộ** một lần upload trước khi chạm đĩa.
///
/// `enabled` đến từ cài đặt (§8.1 "chỉ khi bật"); kiểm nó **trước** dữ liệu để
/// một tính năng đang tắt không tốn CPU parse 50 MB multipart.
pub fn validate(enabled: bool, name: &str, bytes: Vec<u8>) -> Result<Upload, UploadError> {
    if !enabled {
        return Err(UploadError::Disabled);
    }
    if bytes.is_empty() {
        return Err(UploadError::Empty);
    }
    // Cap đo trên **nội dung file**, không phải cả multipart body — xem docs
    // `MAX_FILE_BYTES`.
    if bytes.len() > MAX_FILE_BYTES {
        return Err(UploadError::TooLarge);
    }
    let safe = safe_name(name)?;
    Ok(Upload { name: safe.name, bytes })
}

/// Tách `boundary` từ `Content-Type: multipart/form-data; boundary=...`.
///
/// Không dùng crate: §56.1 yêu cầu 0 dependency, và định dạng này đủ nhỏ để
/// parse đúng. Giá trị có thể có `"` bao quanh (RFC 2046 cho phép).
pub fn boundary_of(content_type: &str) -> Option<String> {
    let lowered = content_type.to_ascii_lowercase();
    if !lowered.starts_with("multipart/form-data") {
        return None;
    }
    let index = lowered.find("boundary=")?;
    let rest = &content_type[index + "boundary=".len()..];
    let value = rest.split(';').next()?.trim();
    let value = value.trim_matches('"');
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

/// Một phần của multipart sau khi tách.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Part {
    /// `filename` trong `Content-Disposition`, nếu có.
    pub filename: Option<String>,
    /// `name` trong `Content-Disposition`.
    pub field: Option<String>,
    pub body: Vec<u8>,
}

/// Tách multipart thành các phần. Không cần crate.
///
/// # Vì sao tự viết thay vì crate `multipart`
///
/// §56.1: bản này **0 dependency** ngoài `std`. Định dạng đủ đơn giản, và tự
/// viết cho phép kiểm chính xác chỗ dễ sai: `\r\n` **trước** boundary thuộc về
/// dấu phân cách, **không** thuộc nội dung file. Lấy sai một byte là file PNG
/// hỏng mà không báo lỗi.
pub fn parse_multipart(body: &[u8], boundary: &str) -> Result<Vec<Part>, UploadError> {
    // Boundary trong body có tiền tố `--`.
    let mut delimiter = Vec::with_capacity(boundary.len() + 2);
    delimiter.extend_from_slice(b"--");
    delimiter.extend_from_slice(boundary.as_bytes());

    let mut parts = Vec::new();
    let mut cursor = 0usize;
    loop {
        // Tìm phần mở đầu.
        let Some(start) = find(&body[cursor..], &delimiter) else {
            break;
        };
        let after = cursor + start + delimiter.len();
        // `--` ngay sau boundary = phần kết thúc.
        if body.get(after..after + 2) == Some(b"--") {
            return Ok(parts);
        }
        // Bỏ `\r\n` sau boundary.
        let headers_start = if body.get(after..after + 2) == Some(b"\r\n") {
            after + 2
        } else {
            after
        };
        // Phần này kết thúc ở boundary tiếp theo; `\r\n` **trước** nó thuộc dấu
        // phân cách nên bị cắt khỏi nội dung.
        let Some(next) = find(&body[headers_start..], &delimiter) else {
            // Không có boundary kết thúc: dữ liệu bị cắt giữa đường.
            return Err(UploadError::MalformedMultipart);
        };
        let mut section = &body[headers_start..headers_start + next];
        if section.ends_with(b"\r\n") {
            section = &section[..section.len() - 2];
        }
        parts.push(parse_part(section)?);
        cursor = headers_start + next;
    }
    if parts.is_empty() {
        Err(UploadError::MalformedMultipart)
    } else {
        Ok(parts)
    }
}

fn parse_part(section: &[u8]) -> Result<Part, UploadError> {
    // Header và body cách nhau bởi dòng trống.
    let (header_bytes, body) = match find(section, b"\r\n\r\n") {
        Some(index) => (&section[..index], section[index + 4..].to_vec()),
        // Không có header: cả phần là body (boundary-only part).
        None => (&section[..0], section.to_vec()),
    };
    let headers = String::from_utf8_lossy(header_bytes);
    let mut filename = None;
    let mut field = None;
    for line in headers.lines() {
        let Some((name, value)) = line.split_once(':') else { continue };
        if !name.trim().eq_ignore_ascii_case("content-disposition") {
            continue;
        }
        for piece in value.split(';').map(str::trim) {
            if let Some(rest) = piece.strip_prefix("filename=") {
                filename = Some(rest.trim_matches('"').to_string());
            } else if let Some(rest) = piece.strip_prefix("name=") {
                field = Some(rest.trim_matches('"').to_string());
            }
        }
    }
    Ok(Part { filename, field, body })
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return None;
    }
    haystack.windows(needle.len()).position(|window| window == needle)
}

/// SHA-256 của nội dung, hex thường.
///
/// §8.1 trả `{path,size,sha256}` — hash để người dùng **kiểm** file nhận được
/// đúng là file đã gửi. Tự cài đặt (không crate) là ~60 dòng và có test vector
/// chuẩn từ FIPS 180-4; dùng một dependency cho việc này là đổi §56.1 lấy 60
/// dòng.
pub fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    // Padding: 0x80, rồi 0x00 tới 56 mod 64, rồi độ dài **bit** (u64 big-endian).
    let mut message = data.to_vec();
    message.push(0x80);
    while message.len() % 64 != 56 {
        message.push(0);
    }
    message.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());

    for chunk in message.chunks(64) {
        let mut w = [0u32; 64];
        for (index, word) in chunk.chunks(4).enumerate() {
            w[index] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for index in 16..64 {
            let s0 = w[index - 15].rotate_right(7)
                ^ w[index - 15].rotate_right(18)
                ^ (w[index - 15] >> 3);
            let s1 = w[index - 2].rotate_right(17)
                ^ w[index - 2].rotate_right(19)
                ^ (w[index - 2] >> 10);
            w[index] = w[index - 16]
                .wrapping_add(s0)
                .wrapping_add(w[index - 7])
                .wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for index in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[index])
                .wrapping_add(w[index]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = String::with_capacity(64);
    for word in h {
        out.push_str(&format!("{word:08x}"));
    }
    out
}

/// Thư mục đích: `$HOME/Downloads/RD`. Tạo nếu chưa có.
///
/// Trên Windows `$USERPROFILE` là `HOME` của tiến trình, nên cùng một biểu thức
/// cho ra `%USERPROFILE%\Downloads\RD` đúng như spec.
pub fn upload_dir(home: &Path) -> PathBuf {
    home.join(UPLOAD_SUBDIR)
}

/// Ghi file đã kiểm vào `dir`. Trả `(path, size, sha256)`.
///
/// # Chống ghi đè
///
/// Nếu tên đã tồn tại, thêm hậu tố ` (2)`, ` (3)`… **không** ghi đè. Ghi đè
/// file cùng tên là mất dữ liệu của người dùng — họ gửi `photo.jpg` lần thứ
/// hai và mất ảnh cũ mà không biết.
pub fn write(upload: &Upload, dir: &Path) -> std::io::Result<(PathBuf, usize, String)> {
    std::fs::create_dir_all(dir)?;
    let stem = upload
        .name
        .rsplit_once('.')
        .map(|(stem, extension)| (stem.to_string(), Some(extension.to_string())))
        .unwrap_or_else(|| (upload.name.clone(), None));
    let mut candidate = dir.join(&upload.name);
    let mut counter = 2u32;
    while candidate.exists() {
        let name = match &stem.1 {
            Some(extension) => format!("{} ({counter}).{extension}", stem.0),
            None => format!("{} ({counter})", stem.0),
        };
        candidate = dir.join(name);
        counter += 1;
        if counter > 9_999 {
            // Dừng sau 10 000 thử: một vòng lặp không có trần là cách treo
            // thread xử lý request.
            break;
        }
    }
    std::fs::write(&candidate, &upload.bytes)?;
    Ok((
        candidate,
        upload.bytes.len(),
        sha256_hex(&upload.bytes),
    ))
}

/// JSON §8.1: `{path,size,sha256}`.
pub fn upload_json(path: &Path, size: usize, sha256: &str) -> String {
    format!(
        "{{\"path\":{},\"size\":{},\"sha256\":{}}}",
        crate::json_quote(&path.to_string_lossy()),
        size,
        crate::json_quote(sha256)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn multipart(field: &str, filename: &str, content: &[u8]) -> Vec<u8> {
        let mut body = Vec::new();
        body.extend_from_slice(b"--BND\r\n");
        body.extend_from_slice(
            format!("Content-Disposition: form-data; name=\"{field}\"; filename=\"{filename}\"\r\n")
                .as_bytes(),
        );
        body.extend_from_slice(b"Content-Type: application/octet-stream\r\n\r\n");
        body.extend_from_slice(content);
        body.extend_from_slice(b"\r\n--BND--\r\n");
        body
    }

    #[test]
    fn the_spec_extension_list_is_blocked_case_insensitively() {
        // §50.3 nguyên văn: exe/ps1/bat/scr/lnk. Windows **không** phân biệt
        // hoa/thường, nên `PAYLOAD.EXE` chạy được y như `payload.exe`.
        for name in ["a.exe", "a.PS1", "a.Bat", "a.sCr", "a.LNK"] {
            match safe_name(name) {
                Err(UploadError::BlockedExtension(ext)) => {
                    assert_eq!(ext, name.rsplit('.').next().unwrap().to_ascii_lowercase())
                }
                other => panic!("{name} phải bị chặn: {other:?}"),
            }
        }
    }

    #[test]
    fn a_blocked_extension_is_caught_even_if_it_is_the_last_of_many() {
        // `report.pdf.exe` — đuôi **cuối** quyết định cách Windows mở file.
        assert!(matches!(
            safe_name("report.pdf.exe"),
            Err(UploadError::BlockedExtension(_))
        ));
        // Ngược lại: `report.exe.txt` mở bằng Notepad, **không** nguy hiểm.
        // Chặn nó là chặn oan và làm người dùng tưởng app hỏng.
        assert!(safe_name("report.exe.txt").is_ok());
    }

    #[test]
    fn a_path_in_the_filename_cannot_escape_the_upload_folder() {
        // Đây là leo thang đặc quyền thật, không phải lý thuyết: ghép
        // `Downloads/RD/` với `..\..\Windows\System32\x.dll` ghi đè file hệ
        // thống. Windows chấp nhận cả `\` và `/`, nên phải cắt cả hai.
        // `.dll`/`.txt`/`.sh` **không** nằm trong 5 đuôi §50.3 chặn, nên phần
        // cuối hợp lệ — thứ cần kiểm ở đây là **đường dẫn bị cắt**, không phải
        // đuôi.
        for raw in [
            r"..\..\Windows\System32\kernel32.dll",
            "../../etc/passwd.txt",
            "/tmp/evil.sh",
            r"C:\Users\me\tai-lieu.pdf",
        ] {
            let safe = safe_name(raw).expect("phần cuối vẫn là tên hợp lệ");
            assert!(!safe.name.contains('/'), "{raw} ⇒ {}", safe.name);
            assert!(!safe.name.contains('\\'), "{raw} ⇒ {}", safe.name);
            assert_eq!(safe.name, raw.rsplit(['/', '\\']).next().unwrap());
        }
        // Nhưng nếu phần cuối **chính nó** bị chặn thì vẫn phải chặn — cắt
        // đường dẫn không được vô hiệu hoá kiểm đuôi.
        assert!(matches!(
            safe_name(r"..\..\payload.exe"),
            Err(UploadError::BlockedExtension(_))
        ));
        assert!(matches!(
            safe_name(r"C:\Windows\System32\cmd.EXE"),
            Err(UploadError::BlockedExtension(_))
        ));
    }

    #[test]
    fn names_windows_would_silently_change_are_refused() {
        // Windows tự cắt dấu chấm/khoảng trắng cuối khi tạo file ⇒ file trên đĩa
        // khác tên đã báo cho người dùng, và họ tìm không thấy.
        for bad in ["", "  ", ".", "..", "name.", "name ", "a<b", "a>b", "a:b", "a|b", "a?b", "a*b"] {
            assert_eq!(
                safe_name(bad).map(|s| s.name).map_err(|_| ()),
                Err(()),
                "{bad:?} phải bị từ chối"
            );
        }
        assert!(safe_name("báo cáo (cuối).pdf").is_ok(), "tiếng Việt + ngoặc phải qua");
    }

    #[test]
    fn the_cap_is_fifty_megabytes_of_file_not_of_multipart_envelope() {
        // §50.3: 50 MB. Đo trên **nội dung file**: multipart có boundary +
        // header riêng, nên đo cả body sẽ từ chối oan file 49.9 MB.
        let exact = vec![0u8; MAX_FILE_BYTES];
        assert!(validate(true, "a.bin", exact).is_ok(), "đúng 50 MB phải qua");
        let over = vec![0u8; MAX_FILE_BYTES + 1];
        assert_eq!(validate(true, "a.bin", over), Err(UploadError::TooLarge));
    }

    #[test]
    fn a_disabled_feature_refuses_before_parsing_anything() {
        // §8.1: "chỉ khi bật". 403 chứ không 404 — route tồn tại, tính năng tắt,
        // người dùng cần biết để bật.
        assert_eq!(validate(false, "a.txt", b"x".to_vec()), Err(UploadError::Disabled));
        assert_eq!(UploadError::Disabled.status(), 403);
        // Kiểm `enabled` **trước** dữ liệu: tính năng tắt không tốn CPU parse
        // 50 MB multipart.
        assert_eq!(
            validate(false, "payload.exe", vec![0; MAX_FILE_BYTES + 1]),
            Err(UploadError::Disabled)
        );
    }

    #[test]
    fn the_sha256_matches_the_fips_vectors() {
        // Vector chuẩn FIPS 180-4. Nếu hash sai, §8.1 trả một giá trị người
        // dùng không kiểm được — tệ hơn không trả gì.
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            sha256_hex(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
        // Độ dài qua ranh giới block (55/56/64 byte) — chỗ padding dễ sai nhất.
        assert_eq!(sha256_hex(&[b'a'; 55]).len(), 64);
        assert_ne!(sha256_hex(&[b'a'; 55]), sha256_hex(&[b'a'; 56]));
        assert_eq!(
            sha256_hex(&[b'a'; 64]),
            "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"
        );
    }

    #[test]
    fn multipart_parsing_keeps_file_bytes_exactly() {
        // Sai một byte ở đây là file PNG hỏng mà **không** có lỗi nào: `\r\n`
        // trước boundary thuộc dấu phân cách, không thuộc nội dung.
        let png = [0x89u8, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF];
        let body = multipart("file", "anh.png", &png);
        let parts = parse_multipart(&body, "BND").unwrap();
        assert_eq!(parts.len(), 1);
        assert_eq!(parts[0].filename.as_deref(), Some("anh.png"));
        assert_eq!(parts[0].field.as_deref(), Some("file"));
        assert_eq!(parts[0].body, png, "byte phải **nguyên vẹn**, kể cả \\r\\n");
    }

    #[test]
    fn a_truncated_multipart_is_an_error_not_a_partial_file() {
        // Ghi một nửa file rồi báo thành công là mất dữ liệu im lặng.
        let mut body = multipart("file", "a.bin", b"0123456789");
        body.truncate(body.len() / 2);
        assert_eq!(
            parse_multipart(&body, "BND"),
            Err(UploadError::MalformedMultipart)
        );
        // Boundary không có trong body ⇒ không phải multipart của ta.
        assert_eq!(
            parse_multipart(b"raw bytes", "BND"),
            Err(UploadError::MalformedMultipart)
        );
    }

    #[test]
    fn the_boundary_is_read_from_the_content_type() {
        assert_eq!(
            boundary_of("multipart/form-data; boundary=abc123"),
            Some("abc123".into())
        );
        // RFC 2046 cho phép `"`.
        assert_eq!(
            boundary_of("multipart/form-data; boundary=\"a b\""),
            Some("a b".into())
        );
        assert_eq!(boundary_of("multipart/form-data"), None);
        assert_eq!(boundary_of("application/json"), None);
        assert_eq!(boundary_of("multipart/form-data; boundary="), None);
    }

    #[test]
    fn writing_twice_never_overwrites_the_first_file() {
        let dir = std::env::temp_dir().join(format!("rd-upload-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let first = Upload { name: "photo.jpg".into(), bytes: b"first".to_vec() };
        let second = Upload { name: "photo.jpg".into(), bytes: b"second".to_vec() };
        let (path1, size1, hash1) = write(&first, &dir).unwrap();
        let (path2, _, _) = write(&second, &dir).unwrap();
        assert_ne!(path1, path2, "không được ghi đè");
        assert_eq!(std::fs::read(&path1).unwrap(), b"first", "ảnh cũ phải còn");
        assert_eq!(std::fs::read(&path2).unwrap(), b"second");
        assert_eq!(size1, 5);
        assert_eq!(hash1, sha256_hex(b"first"));
        // Tên thứ hai phải giữ đuôi file — nếu không, Windows không mở được.
        assert!(path2.to_string_lossy().ends_with(".jpg"), "{}", path2.display());
        assert!(path2.to_string_lossy().contains("(2)"), "{}", path2.display());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_response_has_exactly_the_three_fields_the_spec_names() {
        let json = upload_json(Path::new("/tmp/x/y.pdf"), 12, "ab12");
        assert!(json.contains(r#""path":"/tmp/x/y.pdf""#), "{json}");
        assert!(json.contains(r#""size":12"#), "{json}");
        assert!(json.contains(r#""sha256":"ab12""#), "{json}");
    }

    #[test]
    fn the_upload_folder_matches_the_spec_path() {
        // §50.3: `%USERPROFILE%\Downloads\RD\`.
        let dir = upload_dir(Path::new("/home/nguoi-dung"));
        assert!(dir.ends_with("Downloads/RD"), "{}", dir.display());
    }
}
