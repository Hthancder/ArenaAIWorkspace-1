mod auth_wire;
mod guard;
mod capture;
#[allow(dead_code)] // dùng trong nhánh #[cfg(windows)] của stream_live
mod history;
mod input;
mod jpeg;
mod pins;
mod session_state;
mod advice;
mod clipboard;
mod crop;
mod stream;
mod upload;
mod windows;

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

const INDEX: &str = include_str!("../../web/index.html");
/// §6.4/§6.5 — client gửi sự kiện. Tách file để test được (xem `web/input.test.js`).
const INPUT_JS: &str = include_str!("../../web/input.js");
/// §6.4/§6.5 — cắm `input.js` vào trang `/live`.
const LIVE_JS: &str = include_str!("../../web/live.js");
const CSS: &str = include_str!("../../web/styles.css");

/// §7.1 — màn hình khoá. Đăng ký như **mọi** asset khác: `include_str!` để file
/// nằm trong exe (không đọc đĩa lúc chạy), và route riêng vì CSP chặn inline.
const AUTH_JS: &str = include_str!("../../web/auth.js");
const JS: &str = include_str!("../../web/app.js");
const SETTINGS_DEFAULTS: &[(&str, &str)] = &[
    ("quality", "auto"), ("display", "real"), ("aspect", "fit"), ("touch", "scroll"),
    ("cursor-mode", "auto"), ("keyboard", "intent"), ("audio", "ask"), ("volume", "70"),
    ("hide-screen", "false"), ("hide-taskbar", "false"), ("language", "vi"), ("theme", "light"),
    ("max-bitrate", "10"), ("max-fps", "30"), ("keyframe", "2"), ("scaler", "balanced"),
    ("sharpen", "off"), ("jitter", "low"), ("cursor-echo", "on"), ("ripple", "on"),
    ("resolution", "auto"), ("dpi", "100"), ("monitor", "primary"), ("keyboard-layout", "system"),
    ("input-rate", "60"), ("block-win-lock", "on"), ("listen-port", "8443"), ("certificate", "self"),
    ("stun-turn", "auto"), ("latency-hud", "off"), ("log-level", "normal"), ("encoder", "auto"),
    // §50.3: mặc định **tắt** — §8.1 "chỉ khi bật", và spec để người dùng quyết.
    ("upload", "off"),
];

#[derive(Clone)]
/// Một phiên đang sống. Các trường **đổi được giữa phiên** là của §6.9:
/// `window_id` (`/{sid}/window`), `mode` (`/{sid}/mode`), `monitor`
/// (`/{sid}/monitor`), `preset` (`/{sid}/preset`, bảng §6.10.1),
/// `cursor_mode` và `view_only` (`/{sid}/cursor_mode`, `/{sid}/permission`).
struct Session {
    id: String,
    mode: String,
    window_id: String,
    started_at: u64,
    audio: bool,
    /// §6.9 đổi monitor **không** tạo phiên mới.
    monitor: u32,
    /// §6.10.1 — id của preset, xem `session_state::PRESETS`.
    preset: String,
    /// §8.1 `/{sid}/cursor_mode`.
    cursor_mode: session_state::CursorMode,
    /// §8.1 `/{sid}/permission {view_only}`. T2: xem được mà không điều khiển.
    view_only: bool,
    /// §6.9: `switching` trong lúc đổi nguồn, `active` khi xong.
    state: &'static str,
    /// §8.1 `/{sid}/share`: TTL của link xem tạm, `None` = không chia sẻ.
    share_ttl_min: Option<u32>,
}
/// Số đo **thật** của phiên stream đang chạy, để UI không phải bịa.
/// `None` = chưa từng stream. Mọi trường đều đo từ vòng lặp ở `stream_live`.
#[derive(Clone, Default)]
struct LiveMetrics {
    /// Số frame JPEG đã gửi thành công.
    frames: u64,
    /// Tổng byte JPEG đã gửi (không tính header multipart).
    jpeg_bytes: u64,
    /// Tổng thời gian encode, micro giây.
    encode_us: u64,
    /// Thời điểm frame đầu tiên (ms từ `UNIX_EPOCH`), 0 = chưa có.
    started_ms: u128,
    /// Độ phân giải thật của frame gần nhất.
    width: usize,
    height: usize,
}

impl LiveMetrics {
    /// `(fps, kbps)` suy ra từ số đo thật. Chưa stream lần nào ⇒ `(0.0, 0.0)`.
    ///
    /// Không lưu `fps`/`kbps` trực tiếp: hai đại lượng đó **phụ thuộc thời
    /// điểm đọc**, và lưu lại thì phải cập nhật ở mọi chỗ tăng `frames` — một
    /// trong số đó sẽ bị quên.
    fn summary(&self) -> (f64, f64) {
        let elapsed_ms = now_ms().saturating_sub(self.started_ms);
        if self.frames == 0 || elapsed_ms == 0 {
            return (0.0, 0.0);
        }
        let seconds = elapsed_ms as f64 / 1000.0;
        let fps = self.frames as f64 / seconds;
        let kbps = (self.jpeg_bytes as f64 * 8.0) / seconds / 1000.0;
        // Làm tròn 1 chữ số: hiển thị `58.3` thay vì `58.31489123` trong JSON.
        ((fps * 10.0).round() / 10.0, (kbps * 10.0).round() / 10.0)
    }
}

impl LiveMetrics {
    fn fps(&self, elapsed_ms: u128) -> f64 {
        if elapsed_ms == 0 { return 0.0; }
        self.frames as f64 * 1000.0 / elapsed_ms as f64
    }
    fn kb_per_frame(&self) -> f64 {
        if self.frames == 0 { return 0.0; }
        self.jpeg_bytes as f64 / self.frames as f64 / 1024.0
    }
    fn ms_per_frame(&self) -> f64 {
        if self.frames == 0 { return 0.0; }
        self.encode_us as f64 / self.frames as f64 / 1000.0
    }
    fn mbps(&self, elapsed_ms: u128) -> f64 {
        if elapsed_ms == 0 { return 0.0; }
        self.jpeg_bytes as f64 * 8.0 / (elapsed_ms as f64 / 1000.0) / 1_000_000.0
    }
}

fn now_ms() -> u128 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0)
}

struct State { settings: BTreeMap<String, String>, session: Option<Session>, next_id: u64, data_dir: PathBuf, live_status: Option<(bool, String)>, live_metrics: LiveMetrics, input: input::InputSanitizer, history: history::History, auth: auth_wire::AuthState, policy: guard::Policy, loopback_trusted: bool, keyframes: u64, pins: pins::Pins, windows: rd_spike_lib::security::window::WindowRegistry,
    /// §5.4 — gốc toạ độ của frame đang stream, tính theo pixel màn hình.
    /// `(0,0)` khi stream cả màn hình; `(left,top)` của cửa sổ khi crop.
    /// `inject` **phải** cộng giá trị này, nếu không click lệch đúng bằng vị
    /// trí cửa sổ.
    capture_offset: (i32, i32) }

fn json_quote(value: &str) -> String {
    let mut out = String::from("\"");
    for ch in value.chars() {
        match ch { '"' => out.push_str("\\\""), '\\' => out.push_str("\\\\"), '\n' => out.push_str("\\n"), '\r' => out.push_str("\\r"), '\t' => out.push_str("\\t"), c if c < ' ' => out.push(' '), c => out.push(c) }
    }
    out.push('"'); out
}

// The app sends a flat JSON object with string, boolean, and integer values only.
// This small parser is intentionally limited to that allowlisted mock-settings shape.
fn parse_flat_object(input: &str) -> Option<BTreeMap<String, String>> {
    let bytes = input.trim().as_bytes();
    if bytes.len() < 2 || bytes[0] != b'{' || *bytes.last()? != b'}' { return None; }
    let mut i = 1usize;
    let end = bytes.len() - 1;
    let mut map = BTreeMap::new();
    while i < end {
        while i < end && (bytes[i].is_ascii_whitespace() || bytes[i] == b',') { i += 1; }
        if i >= end { break; }
        if bytes[i] != b'"' { return None; }
        let (key, next) = parse_json_string(bytes, i)?; i = next;
        while i < end && bytes[i].is_ascii_whitespace() { i += 1; }
        if i >= end || bytes[i] != b':' { return None; } i += 1;
        while i < end && bytes[i].is_ascii_whitespace() { i += 1; }
        let value;
        if i < end && bytes[i] == b'"' {
            let (s, next) = parse_json_string(bytes, i)?; value = s; i = next;
        } else {
            let start = i;
            while i < end && bytes[i] != b',' { i += 1; }
            value = String::from_utf8(bytes[start..i].iter().copied().filter(|b| !b.is_ascii_whitespace()).collect()).ok()?;
        }
        map.insert(key, value);
        while i < end && bytes[i].is_ascii_whitespace() { i += 1; }
        if i < end && bytes[i] != b',' { return None; }
    }
    Some(map)
}
/// Đọc một chuỗi JSON từ `bytes[start] == b'"'`.
///
/// **UTF-8**: bản trước làm `out.push(b as char)` — biến mỗi *byte* thành một
/// ký tự Latin-1. Hậu quả: `"ế"` (3 byte UTF-8) thành 3 ký tự rác, và tầng
/// input gửi 3 code unit thay vì 1 ⇒ gõ tiếng Việt ra `Ã¡ÂºÂ¿`. Test HTTP
/// thật bắt được; unit test thì không, vì chúng dựng `Event` trực tiếp.
///
/// Cách sửa: gom các byte >= 0x80 thành một lát, rồi `from_utf8` **một lần**
/// cho cả lát — không giải mã từng byte.
fn parse_json_string(bytes: &[u8], start: usize) -> Option<(String, usize)> {
    let mut i = start + 1;
    let mut out = String::new();
    while i < bytes.len() {
        match bytes[i] {
            b'"' => return Some((out, i + 1)),
            b'\\' => {
                i += 1;
                if i >= bytes.len() { return None; }
                match bytes[i] {
                    b'"' => out.push('"'),
                    b'\\' => out.push('\\'),
                    b'n' => out.push('\n'),
                    // Hai escape JSON chuẩn còn thiếu — client có thể gửi
                    // `\b`/`\f` từ clipboard.
                    b'b' => out.push('\u{8}'),
                    b'f' => out.push('\u{c}'),
                    b'r' => out.push('\r'),
                    b't' => out.push('\t'),
                    b'u' => {
                        // \uXXXX (kể cả surrogate pair — ghép ở dưới).
                        if i + 4 >= bytes.len() { return None; }
                        let hex = std::str::from_utf8(&bytes[i + 1..i + 5]).ok()?;
                        let unit = u16::from_str_radix(hex, 16).ok()?;
                        if (0xD800..=0xDBFF).contains(&unit) {
                            // Chờ low surrogate ở escape kế tiếp dạng `\uXXXX`.
                            // Chỉ số: `i` đang ở 'u' của escape thứ nhất; hex1 =
                            // i+1..i+5. Escape thứ hai bắt đầu ở i+5 (`\\`),
                            // 'u' ở i+6, hex2 = i+7..i+11.
                            if bytes.get(i + 5) != Some(&b'\\') || bytes.get(i + 6) != Some(&b'u') {
                                return None;
                            }
                            let hex2 = std::str::from_utf8(bytes.get(i + 7..i + 11)?).ok()?;
                            let low = u16::from_str_radix(hex2, 16).ok()?;
                            if !(0xDC00..=0xDFFF).contains(&low) { return None; }
                            let scalar = 0x1_0000
                                + ((u32::from(unit) - 0xD800) << 10)
                                + (u32::from(low) - 0xDC00);
                            out.push(char::from_u32(scalar)?);
                            i += 11;
                            continue;
                        }
                        out.push(char::from_u32(u32::from(unit))?);
                        i += 5;
                        continue;
                    }
                    _ => return None,
                }
                i += 1;
            }
            b if b < 0x20 => return None,
            b if b < 0x80 => { out.push(b as char); i += 1; }
            _ => {
                // Lát byte UTF-8: gom tới ký tự ASCII tiếp theo (hoặc `"`).
                let begin = i;
                while i < bytes.len() && bytes[i] >= 0x80 { i += 1; }
                out.push_str(std::str::from_utf8(&bytes[begin..i]).ok()?);
            }
        }
    }
    None
}
fn allowed_value(key: &str, value: &str) -> bool {
    if key == "volume" { return value.parse::<u8>().is_ok_and(|volume| volume <= 100); }
    if key == "hide-screen" || key == "hide-taskbar" { return value == "true" || value == "false"; }
    let choices: &[&str] = match key {
        "quality" => &["auto","sharp","smooth"], "display" => &["real","comfortable","large-text","sharp"],
        "aspect" => &["fit","fill","100"], "touch" => &["scroll","mouse"], "cursor-mode" => &["auto","local","video"],
        "keyboard" => &["intent","raw"], "audio" => &["ask","on","off"], "language" => &["vi","en"],
        "theme" => &["light","dark","system"], "max-bitrate" => &["5","10","15"], "max-fps" => &["15","30","60"],
        "keyframe" => &["1","2","3"], "scaler" => &["balanced","sharp","fast"], "sharpen" => &["off","low"],
        "jitter" => &["low","smooth"], "cursor-echo" | "ripple" => &["on","off"], "resolution" => &["auto","1080","720"],
        "dpi" => &["100","125","150"], "monitor" => &["primary","2"], "keyboard-layout" => &["system","vi","en"],
        "input-rate" => &["60","100"], "block-win-lock" => &["on","off"], "listen-port" => &["8443","443"],
        "certificate" => &["self","custom"], "stun-turn" => &["auto","tailnet"], "latency-hud" => &["off","on"],
        "log-level" => &["normal","verbose"], "encoder" => &["auto","qsv","nvenc"],
        // §50.3 — mục **duy nhất** trong spec mà tác giả để người dùng quyết.
        // Mặc định `off` (§8.1 "chỉ khi bật"); bật thì `on`.
        "upload" => &["off","on"], _ => &[],
    };
    choices.contains(&value)
}
fn settings_json(settings: &BTreeMap<String, String>) -> String {
    let values = settings.iter().map(|(k,v)| {
        let encoded = if k == "volume" || k == "hide-screen" || k == "hide-taskbar" { v.clone() } else { json_quote(v) };
        format!("{}:{}", json_quote(k), encoded)
    }).collect::<Vec<_>>().join(","); format!("{{{values}}}")
}
fn session_json(s: &Session) -> String {
    // §8.1 `GET /api/sessions/{sid}` ghi `{state,stats,audio,view_only,warnings,
    // cursor_mode}`. `stats` đến từ `LiveMetrics` ở route, không phải ở đây —
    // hàm này chỉ mô tả phiên.
    format!(
        "{{\"id\":{},\"mode\":{},\"windowId\":{},\"startedAt\":{},\"audio\":{},\"status\":\"connected\",\"state\":\"{}\",\"monitor\":{},\"preset\":{},\"cursorMode\":\"{}\",\"viewOnly\":{},\"share\":{},\"mock\":true}}",
        json_quote(&s.id), json_quote(&s.mode), json_quote(&s.window_id), s.started_at, s.audio,
        s.state, s.monitor, json_quote(&s.preset), s.cursor_mode.as_str(), s.view_only,
        s.share_ttl_min.map(|m| m.to_string()).unwrap_or_else(|| "null".into())
    )
}
/// Header của **mọi** response. Tách khỏi socket để test được bằng giá trị trả
/// về, không phải bằng cách bắt chước chuỗi trong test.
///
/// §41.5 D4: thiếu hai header đầu thì một trang khác nhúng được app trong iframe
/// và bấm hộ nút "điều khiển" (clickjacking). Mock cũng phải giữ đúng, vì sản
/// phẩm thật sẽ bám theo mock.
fn response_head(status: u16, content_type: &str, content_length: usize) -> String {
    // Mã nào không có ở đây sẽ rơi vào "Internal Server Error" — và một `401`
    // in ra "Internal Server Error" là bug thật, không phải chuyện hình thức:
    // người đọc log tưởng server hỏng trong khi thực tế là token bị từ chối,
    // và client dựa vào dòng status để phân loại lỗi.
    let reason = match status {
        200 => "OK", 201 => "Created", 204 => "No Content",
        400 => "Bad Request", 401 => "Unauthorized", 403 => "Forbidden", 404 => "Not Found",
        405 => "Method Not Allowed", 409 => "Conflict", 412 => "Precondition Failed",
        413 => "Payload Too Large", 422 => "Unprocessable Entity", 423 => "Locked",
        429 => "Too Many Requests",
        _ => "Internal Server Error",
    };
    format!("HTTP/1.1 {status} {reason}\r\nContent-Type: {content_type}\r\nContent-Length: {content_length}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nContent-Security-Policy: default-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'none'\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n")
}
fn response(stream: &mut TcpStream, status: u16, content_type: &str, body: &[u8]) {
    let head = response_head(status, content_type, body.len());
    let _ = stream.write_all(head.as_bytes()); let _ = stream.write_all(body); let _ = stream.flush();
}
/// Như [`response`] nhưng thêm header — cần cho `Set-Cookie` (§41.6: refresh
/// token chỉ được đi bằng cookie `HttpOnly`, không vào body).
///
/// Dựng trên [`response_head`] thay vì tự ghép chuỗi: header bảo mật
/// (`nosniff`, `X-Frame-Options`, CSP) đã có ở đó, và một bản sao là một chỗ
/// nữa để quên cập nhật.
fn json_response_with_headers(
    stream: &mut TcpStream,
    status: u16,
    body: &str,
    extra: &[(&str, String)],
) {
    let head = response_head(status, "application/json; charset=utf-8", body.len());
    // Chèn trước dòng trống cuối cùng của head.
    let mut head = head.trim_end_matches("\r\n\r\n").to_string();
    for (name, value) in extra {
        head.push_str(&format!("\r\n{name}: {value}"));
    }
    head.push_str("\r\n\r\n");
    let _ = stream.write_all(head.as_bytes());
    let _ = stream.write_all(body.as_bytes());
    let _ = stream.flush();
}

/// §6.9 — một lần "đổi thứ gì đó trong phiên đang sống".
///
/// # Vì sao đây là **một** hàm cho 7 route
///
/// Cả 7 route của §8.1 (`window`, `mode`, `monitor`, `preset`, `cursor_mode`,
/// `permission`, `share`) có cùng hình dạng: tìm phiên → kiểm quyền → kiểm
/// giá trị → áp → trả trạng thái mới. Viết rời thì có 7 bản của "kiểm quyền"
/// và 7 cơ hội quên một cái — đúng loại lỗi tôi vừa sửa ở `guard`.
///
/// Trả `None` = đã trả response (lỗi); `Some((status, body))` = để nơi gọi
/// ghi response.
enum Switch<'a> {
    Window(&'a str),
    Mode(&'a str),
    Monitor(&'a str),
    Preset(&'a str),
    CursorMode(&'a str),
    Permission(&'a str),
    Share(&'a str),
}

fn switch_session(
    stream: &mut TcpStream,
    state: &mut State,
    sid: &str,
    headers: &BTreeMap<String, String>,
    what: Switch<'_>,
) -> Option<(u16, String)> {
    let exists = state.session.as_ref().map(|session| session.id.as_str()) == Some(sid);
    if !exists {
        // Kiểm phiên **trước** quyền: trả 401 cho một `sid` không tồn tại thì
        // kẻ dò `sid` (§41.2 P2) biết được cái nào có thật.
        json_response(stream, 404, "{\"error\":\"session_not_found\"}".into());
        return None;
    }
    // `?` thay vì `if … { return None }`: cùng nghĩa, và clippy đúng khi nói
    // bản kia là ba dòng cho một phép kiểm.
    deny_if_unauthorised(stream, state, headers, Some("local"))?;
    let body = match what {
        Switch::Window(b) | Switch::Mode(b) | Switch::Monitor(b) | Switch::Preset(b)
        | Switch::CursorMode(b) | Switch::Permission(b) | Switch::Share(b) => b,
    };
    let fields = parse_flat_object(body).unwrap_or_default();

    // Giữ giá trị cũ để §6.9 biết **có đổi nguồn capture hay không** (chỉ lúc
    // đó mới cần release_all + keyframe; đổi preset thì không).
    let session = state.session.as_mut().expect("vừa kiểm ở trên bằng `exists`");
    let old_mode = session.mode.clone();

    match what {
        Switch::Window(_) => {
            let Some(wid) = fields.get("windowId") else {
                return Some((400, "{\"error\":\"invalid_json\"}".into()));
            };
            // §41.3 #3: `wid` phải nằm trong danh sách agent đã trả — kiểm qua
            // `WindowRegistry::authorize`, cùng cổng với tạo phiên.
            if wid != "desktop" {
                let snapshot = fields.get("snapshotId").map(String::as_str).unwrap_or("");
                if let Err(error) = state.windows.authorize(snapshot, wid, now_ms() as u64) {
                    // Cả `code()` và `status()` đều nhận `self` (move), nên
                    // phải lấy **cả hai** trước khi dùng cái nào — clippy/rustc
                    // đúng khi báo "use of moved value" ở bản trước.
                    let code = error.clone().code();
                    let status = error.status();
                    return Some((status, format!("{{\"error\":{}}}", json_quote(code))));
                }
            }
            session.window_id = wid.clone();
            session.state = "switching";
        }
        Switch::Mode(_) => {
            let Some(mode) = fields.get("mode") else {
                return Some((400, "{\"error\":\"invalid_json\"}".into()));
            };
            // §6.9: "Cho phép (v2.1 cấm) — chỉ là thay nguồn capture".
            if !["hvnc", "vnc"].contains(&mode.as_str()) {
                return Some((422, "{\"error\":\"invalid_session_mode\"}".into()));
            }
            let new_mode = mode.clone();
            session.mode = new_mode.clone();
            session.state = "switching";
        }
        Switch::Monitor(_) => {
            let index = fields.get("index").and_then(|v| v.parse::<u32>().ok());
            let Some(index) = index.and_then(|i| session_state::valid_monitor(i).ok()) else {
                return Some((422, "{\"error\":\"invalid_monitor\"}".into()));
            };
            session.monitor = index;
            // §6.9: đổi monitor cũng là đổi nguồn capture ⇒ keyframe mới.
            session.state = "switching";
        }
        Switch::Preset(_) => {
            let Some(id) = fields.get("preset") else {
                return Some((400, "{\"error\":\"invalid_json\"}".into()));
            };
            let Ok(preset) = session_state::resolve_preset(id) else {
                return Some((422, "{\"error\":\"invalid_preset\"}".into()));
            };
            session.preset = preset.id.to_string();
            // §6.10.1: "Đổi preset = đổi encoder config, **không** đổi màn hình
            // ảo (tránh move cửa sổ lần 2)" ⇒ cố ý **không** gọi
            // `apply_switch`: không release_all, không xin keyframe.
            return Some((200, format!(
                "{{\"preset\":{},\"fps\":{},\"mbps\":{},\"adaptive\":{}}}",
                json_quote(preset.id), preset.fps, preset.mbps, preset.adaptive)));
        }
        Switch::CursorMode(_) => {
            let Some(mode) = fields.get("mode") else {
                return Some((400, "{\"error\":\"invalid_json\"}".into()));
            };
            let Ok(parsed) = session_state::CursorMode::parse(mode) else {
                return Some((422, "{\"error\":\"invalid_cursor_mode\"}".into()));
            };
            session.cursor_mode = parsed;
            return Some((200, format!("{{\"cursorMode\":\"{}\"}}", parsed.as_str())));
        }
        Switch::Permission(_) => {
            let Some(raw) = fields.get("view_only") else {
                return Some((400, "{\"error\":\"invalid_json\"}".into()));
            };
            session.view_only = raw == "true";
            let now_view_only = session.view_only;
            // T2: bật view_only thì phím/chuột đang giữ phải được nhả **ngay**,
            // nếu không người dùng đổi quyền mà vẫn còn Ctrl đang giữ.
            //
            // `session` không được dùng lại sau đây, nên borrow kết thúc (NLL)
            // và `release_all_input(state)` mượn được `state`. Không cần
            // `drop(session)`: clippy đúng khi nói `drop` trên `&mut` là no-op
            // — bản trước của tôi có nó và CI bắt được.
            if now_view_only {
                release_all_input(state);
            }
            return Some((200, format!("{{\"viewOnly\":{}}}", now_view_only)));
        }
        Switch::Share(_) => {
            let minutes = fields.get("ttl_min").and_then(|v| v.parse::<u32>().ok());
            let Some(minutes) = minutes.and_then(|m| session_state::valid_share_ttl(m).ok()) else {
                return Some((422, "{\"error\":\"invalid_ttl\"}".into()));
            };
            session.share_ttl_min = Some(minutes);
            // §21.6: link chia sẻ là view-only. Chia sẻ chế độ điều khiển được
            // là trao toàn quyền máy cho người nhận link — spec không cho.
            session.view_only = true;
            let session_id = session.id.clone();
            // Cùng lý do: hết dùng `session` ⇒ borrow tự nhả.
            release_all_input(state);
            return Some((200, format!(
                "{{\"ttlMin\":{},\"viewOnly\":true,\"url\":{}}}",
                minutes, json_quote(&format!("/s/{}?t={}", session_id, minutes)))));
        }
    }

    // Ba route đổi nguồn capture (`window`/`mode`/`monitor`) đã set
    // `state = "switching"` ở trên. Bước (3)–(5) của §6.9 phải chạy **sau khi
    // nhả borrow** trên `state.session` (chúng cần `state.input`), nên tách ra
    // đây thay vì gọi trong match — borrow checker nói đúng chỗ này.
    let _ = session;
    let target_mode = state.session.as_ref().map(|s| s.mode.clone()).unwrap_or_default();
    apply_switch(&old_mode, &target_mode, state);
    let session = state.session.as_mut().expect("vừa kiểm");
    session.state = "active";
    // Trả **cả** trạng thái mới để client không phải gọi lại `GET /{sid}`.
    let snapshot = session_json(session);
    Some((200, format!("{{\"session\":{},\"state\":\"active\"}}", snapshot)))
}

/// §6.9 bước (1)–(5), theo đúng danh sách `session_state::switch_plan` đã
/// kiểm thứ tự. **Không** đụng peer/DTLS — với MJPEG thì "peer" là kết nối
/// HTTP của client, và nó sống ngoài hàm này.
fn apply_switch(old_mode: &str, new_mode: &str, state: &mut State) {
    for step in session_state::switch_plan(old_mode, new_mode) {
        match step {
            // Mock không có cửa sổ thật để restore/move; nhưng bước release và
            // keyframe là thật, và đó là hai bước **có tác dụng phụ**.
            session_state::SwitchStep::RestoreOldWindow
            | session_state::SwitchStep::MoveNewWindow
            | session_state::SwitchStep::KeepPeer => {}
            session_state::SwitchStep::ReleaseInput => { release_all_input(state); }
            session_state::SwitchStep::RequestKeyframe => { state.keyframes += 1; }
        }
    }
}

/// Nhả mọi phím/chuột đang giữ qua `SendInput`, **không** đụng máy nếu không
/// có gì để nhả. §6.4.7 lớp 3 + §6.9 bước (3).
fn release_all_input(state: &mut State) -> usize {
    let keys = state.input.release_all(now_ms() as u64);
    let actions: Vec<input::Action> = keys.into_iter().map(|vk| input::Action::Key { down: false, vk }).collect();
    let sent = input::inject(&actions);
    let _ = sent;
    actions.len()
}

/// Lấy một tham số từ query string: `?wid=desktop&x=1`.
///
/// Không decode `%20` — không route nào cần, và một bộ decode nửa vời là chỗ
/// để lỗi. Nếu sau này cần, viết nó **một** chỗ với test, đừng rải ra đây.
///
/// `route` được truyền vào là **path đầy đủ có query**; hàm này tự tách.
fn query_param(route: &str, name: &str) -> Option<String> {
    let query = route.split_once('?')?.1;
    for pair in query.split('&') {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        if key == name {
            return Some(value.to_string());
        }
    }
    None
}

/// Chạy cổng quyền cho một mutation. `None` = được đi tiếp; `Some(_)` = đã
/// trả response và route phải dừng.
///
/// Viết thành hàm để **mọi** route gọi cùng một câu, thay vì mỗi route tự
/// nhớ. `sid_owner` là `None` cho route không gắn phiên.
/// Policy **hiệu lực** tại thời điểm gọi.
///
/// # Vì sao không dùng `state.policy` trực tiếp
///
/// `Policy::Loopback` được tính **một lần lúc khởi động** từ địa chỉ bind. Nghĩa
/// là đặt mật khẩu sau đó không đổi được gì: máy đã có mật khẩu mà
/// `/api/windows`, `/api/live.mjpg`, `/move` vẫn mở cho **mọi** process trên máy.
/// Đã kiểm bằng curl: `setup` → 200, rồi `GET /api/windows` **không cookie** →
/// 200. Người dùng đặt mật khẩu, tưởng đã khoá, và thực ra không khoá gì.
///
/// Luật đúng: `Loopback` chỉ miễn token khi **chưa có gì để bảo vệ** — tức là
/// chưa có mật khẩu. Có mật khẩu ⇒ mọi request cần token, kể cả từ loopback.
///
/// Khi bind ra ngoài loopback (`policy` khác `Loopback`), giữ nguyên: đã cần
/// token từ trước.
fn effective_policy(state: &State) -> guard::Policy {
    if state.loopback_trusted && state.auth.auth.is_some() {
        // Đã có mật khẩu ⇒ đòi token dù bind loopback.
        guard::Policy::Lan
    } else {
        state.policy
    }
}

fn deny_if_unauthorised(
    stream: &mut TcpStream,
    state: &State,
    headers: &BTreeMap<String, String>,
    sid_owner: Option<&str>,
) -> Option<Option<String>> {
    match guard::require_token(
        effective_policy(state),
        headers,
        state.auth.auth.as_ref(),
        sid_owner,
        now_ms() as u64,
    ) {
        // Trả `sub` cho nơi gọi: §41.4 T3 cần biết **ai** đang gọi, không chỉ
        // "được phép". Bỏ `sub` đi là mở lại đúng lỗ hổng đó.
        guard::Verdict::Allowed(claims) => Some(claims.map(|c| c.sub)),
        guard::Verdict::Denied { status, code } => {
            json_response(stream, status, format!("{{\"error\":{}}}", json_quote(code)));
            None
        }
    }
}

fn json_response(stream: &mut TcpStream, status: u16, body: String) { response(stream, status, "application/json; charset=utf-8", body.as_bytes()); }
/// Đọc một request HTTP/1.1: `(method, path, headers, body)`.
///
/// # Vì sao trả `headers`
///
/// Bản trước chỉ trả `(method, path, body)` và **vứt** header sau khi dùng
/// `Content-Length`. Hệ quả: không route nào đọc được `Cookie`, nên refresh
/// token (§41.6 — nằm trong cookie `HttpOnly`, **không** trong body) không có
/// đường nào tới server. §8.1 `/api/refresh` không thể chạy nếu header bị vứt
/// ở tầng đọc.
///
/// Tên header được **hạ về chữ thường** để `cookie_value` không phải quan tâm
/// client viết `Cookie` hay `cookie`.
/// Request đã đọc: `(method, path, headers, body nhị phân)`.
///
/// `body` là `Vec<u8>` chứ không `String` vì §8.3 gửi message **nhị phân**
/// (bug #17). Route JSON tự decode, route `/move` đọc thẳng.
type Request = (String, String, BTreeMap<String, String>, Vec<u8>);

/// Giới hạn body theo route. Đủ lớn cho thứ spec cho phép, đủ nhỏ để một
/// request hỏng không ăn hết RAM.
///
/// # Vì sao `8192` không dùng được cho tất cả
///
/// §9.9 cho phép text 256 KB và ảnh 8 MB; §50.3 cho phép upload 50 MB. Một
/// giới hạn chung 8 KB làm **cả hai** tính năng đó không thể chạy, và triệu
/// chứng không phải "413" mà là "connection reset" — khó đoán hơn nhiều.
fn body_limit_for(path: &str) -> usize {
    let route = path.split('?').next().unwrap_or(path);
    if route.ends_with("/clipboard") {
        // Base64 của 8 MB là ~10.7 MB, cộng JSON overhead. `clipboard::validate`
        // vẫn kiểm lại cap thật sau khi decode — đây chỉ là chặn thô.
        12 * 1024 * 1024
    } else if route == "/api/upload" {
        // §50.3: multipart ≤ 50 MB. Multipart có boundary + header phần, nên
        // cho dư 1 MB.
        51 * 1024 * 1024
    } else {
        // Input, settings, session: JSON nhỏ. 256 KB đủ cho mọi route còn lại
        // (kể cả `preset` + `snapshotId` + payload lạ).
        256 * 1024
    }
}

fn read_request(stream: &mut TcpStream) -> Option<Request> {
    stream.set_read_timeout(Some(std::time::Duration::from_secs(3))).ok()?;
    let mut bytes = Vec::new(); let mut chunk = [0u8; 2048]; let header_end;
    loop {
        let n = stream.read(&mut chunk).ok()?; if n == 0 { return None; }
        bytes.extend_from_slice(&chunk[..n]);
        if bytes.len() > 20_000 { return None; }
        if let Some(pos) = bytes.windows(4).position(|w| w == b"\r\n\r\n") { header_end = pos + 4; break; }
    }
    let header = std::str::from_utf8(&bytes[..header_end]).ok()?;
    let mut lines = header.split("\r\n"); let mut request = lines.next()?.split_whitespace();
    let method = request.next()?.to_string(); let path = request.next()?.to_string();
    let mut length = 0usize;
    let mut headers = BTreeMap::new();
    for line in lines {
        let Some((name, value)) = line.split_once(':') else { continue };
        let name = name.trim().to_ascii_lowercase();
        let value = value.trim().to_string();
        if name == "content-length" { length = value.parse().ok()?; }
        // Header trùng tên: giữ cái đầu, đúng như HTTP cho phép gộp.
        headers.entry(name).or_insert(value);
    }
    // Giới hạn body **theo route**, không phải một con số cho tất cả.
    //
    // Bản trước chặn ở 8192 byte cho mọi request. Hệ quả thật:
    //
    // * §9.9 clipboard cho phép text **256 KB** ⇒ mọi lần dán một đoạn văn dài
    //   hơn 8 KB nhận "connection reset" (server trả 413 rồi đóng, nhưng client
    //   còn đang gửi body nên thấy reset chứ không thấy 413). Người dùng kết
    //   luận "paste không chạy" và không có thông báo nào.
    // * §50.3 `/api/upload` cho phép **50 MB** ⇒ route đó đơn giản không thể
    //   hoạt động, dù spec ghi nó là tính năng.
    //
    // Đọc trước `path` ở đây là chấp nhận được: nó nằm trong header đã parse.
    let limit = body_limit_for(&path);
    if length > limit { return Some((method, path, headers, b"__BODY_TOO_LARGE__".to_vec())); }
    while bytes.len() < header_end + length { let n = stream.read(&mut chunk).ok()?; if n == 0 { return None; } bytes.extend_from_slice(&chunk[..n]); }
    // §8.3 message `move` là **12 byte nhị phân** — không phải UTF-8. Bản
    // trước dùng `String::from_utf8(..).ok()?`, nên bất kỳ body nào có byte
    // không hợp lệ UTF-8 làm cả request biến mất (trả `None` ⇒ không response).
    // Đó là lý do §8.3 "không chạy" dù server có `SendInput`: frame `move` đầu
    // tiên có `nx=0..255` ở byte 0 và một toạ độ ngẫu nhiên ở byte 1 — xác
    // suất gặp byte >0x7F là rất cao.
    //
    // Giờ body nhị phân được giữ nguyên; nơi gọi tự quyết decode thành chuỗi
    // (route JSON) hay đọc thẳng (route `/move` của §8.3).
    Some((method, path, headers, bytes[header_end..header_end + length].to_vec()))
}
fn now_seconds() -> u64 { SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0) }
#[derive(Clone)]
struct ProbeCheck { id: String, title: String, status: String, output: String, advice: String }
fn clean_output(text: &str) -> String { text.chars().filter(|c| !c.is_control() || *c == '\n' || *c == '\t').take(1400).collect::<String>().trim().to_string() }
#[cfg(target_os = "windows")]
fn probe_check(id: &str, title: &str, command: &str, args: &[&str], advice: &str) -> ProbeCheck {
    match std::process::Command::new(command).args(args).output() {
        Ok(out) => { let text = clean_output(&format!("{}{}",String::from_utf8_lossy(&out.stdout),String::from_utf8_lossy(&out.stderr))); ProbeCheck { id:id.into(), title:title.into(), status:if out.status.success(){"pass"}else{"warn"}.into(), output:if text.is_empty(){format!("Exit code: {:?}",out.status.code())}else{text}, advice:if out.status.success(){String::new()}else{advice.into()} } },
        Err(error) => ProbeCheck { id:id.into(), title:title.into(), status:"warn".into(), output:format!("Không chạy được {command}: {error}"), advice:advice.into() },
    }
}
fn check_json(c: &ProbeCheck) -> String { format!("{{\"id\":{},\"title\":{},\"status\":{},\"output\":{},\"advice\":{}}}",json_quote(&c.id),json_quote(&c.title),json_quote(&c.status),json_quote(&c.output),json_quote(&c.advice)) }
fn run_diagnostics() -> String {
    let mut checks=Vec::new();
    #[cfg(target_os = "windows")]
    {
        let profile = "$os=Get-CimInstance Win32_OperatingSystem; $sys=Get-CimInstance Win32_ComputerSystem; $gpu=Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion; $wifi=Get-NetAdapter -Physical | Where-Object {$_.InterfaceDescription -match '8265|Wi-Fi|Wireless'} | Select-Object Name,InterfaceDescription,Status; $mon=Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue | Select-Object FriendlyName,Status; @{OS=$os.Caption;OSVersion=$os.Version;RAM_GB=[math]::Round($sys.TotalPhysicalMemory/1GB,1);GPU=$gpu;WiFi=$wifi;Monitors=$mon} | ConvertTo-Json -Depth 5 -Compress";
        checks.push(probe_check("host","Windows · RAM · GPU · Wi-Fi · màn hình","powershell.exe",&["-NoProfile","-NonInteractive","-Command",profile],"Mở PowerShell và kiểm tra WMI/PnP có hoạt động không."));
        checks.push(probe_check("nvidia","Driver / GTX 1050","nvidia-smi",&["--query-gpu=name,driver_version,memory.total","--format=csv,noheader"],"Cài/cập nhật NVIDIA driver. Phép kiểm tra này không đọc Win32_VideoController.AdapterRAM."));
        checks.push(probe_check("gstreamer-version","GStreamer runtime","gst-inspect-1.0",&["--version"],"Cài GStreamer MSVC runtime + good/bad/ugly/libav plugin trước khi thử capture."));
        for (plugin,title) in [("d3d11screencapturesrc","Desktop capture DXGI"),("d3d11download","Download DXGI frames"),("qsvh264enc","Intel QSV encoder"),("nvh264enc","NVIDIA NVENC encoder"),("webrtcbin","WebRTC transport"),("wasapi2src","WASAPI audio capture"),("mfh264enc","Media Foundation fallback")] {
            checks.push(probe_check(&format!("gst-{plugin}"),title,"gst-inspect-1.0",&[plugin],"Plugin chưa sẵn sàng. Xem đúng GStreamer runtime/plugin version; chưa capture thật."));
        }
        let vdd="$m=Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FriendlyName; $m | ConvertTo-Json -Compress";
        let mut c=probe_check("display-drivers","Display devices / VDD","powershell.exe",&["-NoProfile","-NonInteractive","-Command",vdd],"Cài VDD đã ký theo hướng dẫn §51.6 rồi chạy lại probe.");
        if c.status=="pass" && !c.output.to_lowercase().contains("virtual") { c.status="warn".into(); c.advice="Không thấy tên display ảo trong danh sách monitor. Cài/enable VDD đã ký rồi chạy lại.".into(); }
        checks.push(c);
    }
    #[cfg(not(target_os = "windows"))]
    { checks.push(ProbeCheck{id:"host".into(),title:"Windows hardware probe".into(),status:"warn".into(),output:"Probe này chỉ đọc được trên Windows; UI/server chạy ở chế độ kiểm thử.".into(),advice:"Chạy lantern-mock.exe trên laptop Windows.".into()}); }
    let body=checks.iter().map(check_json).collect::<Vec<_>>().join(",");
    format!("{{\"mock\":false,\"checkedAt\":{},\"checks\":[{}]}}",now_seconds(),body)
}
fn pipeline_args(monitor: u8, encoder: bool) -> Vec<String> {
    let mut args = vec!["-e".into(), "-q".into(), "d3d11screencapturesrc".into(),
        format!("monitor-index={monitor}"), "capture-api=dxgi".into(),
        if encoder { "num-buffers=300" } else { "num-buffers=150" }.into(), "!".into()];
    if encoder {
        args.extend(["d3d11convert".into(), "!".into(),
            "video/x-raw(memory:D3D11Memory),format=NV12,width=1920,height=1080,framerate=60/1".into(), "!".into(),
            "qsvh264enc".into(), "target-usage=7".into(), "bitrate=8000".into(), "rate-control=cbr".into(),
            "gop-size=120".into(), "b-frames=0".into(), "low-latency=true".into(), "!".into(),
            "h264parse".into(), "!".into(), "fakesink".into()]);
    } else {
        args.extend(["video/x-raw,framerate=30/1".into(), "!".into(), "d3d11download".into(),
            "!".into(), "videoconvert".into(), "!".into(), "autovideosink".into()]);
    }
    args
}

fn run_gst_pipeline(args: &[String]) -> (bool, String) {
    let mut child = match std::process::Command::new("gst-launch-1.0")
        .args(args).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::piped()).spawn() {
        Ok(child) => child,
        Err(error) => return (false, format!("Không chạy được gst-launch-1.0: {error}")),
    };
    let start = std::time::Instant::now();
    let mut timed_out = false;
    loop {
        match child.try_wait() { Ok(Some(_)) => break, Ok(None) => {}, Err(error) => {
            let _ = child.kill();
            return (false, format!("Không đọc được trạng thái pipeline: {error}"));
        } }
        if start.elapsed() > std::time::Duration::from_secs(12) {
            timed_out = true;
            let _ = child.kill();
            break;
        }
        thread::sleep(std::time::Duration::from_millis(100));
    }
    let output = child.wait_with_output().ok();
    let success = output.as_ref().map(|o| o.status.success()).unwrap_or(false) && !timed_out;
    let details = output.map(|o| clean_output(&String::from_utf8_lossy(&o.stderr))).unwrap_or_default();
    let shown = if timed_out { "Pipeline vượt quá giới hạn 12 giây.".to_string() }
        else if details.is_empty() && success { "Đã xử lý đủ số frame.".to_string() }
        else { details };
    (success, shown)
}

fn capture_probe(body: &str) -> (u16, String) {
    let Some(fields) = parse_flat_object(body) else { return (400, "{\"error\":\"invalid_json\"}".into()); };
    let monitor = fields.get("monitorIndex").and_then(|v| v.parse::<u8>().ok()).filter(|v| *v <= 8);
    let Some(monitor) = monitor else { return (422, "{\"error\":\"invalid_monitor_index\"}".into()); };

    // One user action follows the laptop P0 order: first prove visible DXGI
    // capture, then run the QSV path expected to keep capture+encode on the iGPU.
    let (capture_ok, capture_output) = run_gst_pipeline(&pipeline_args(monitor, false));
    if !capture_ok {
        let output = format!("DXGI visible capture: WARN\n{capture_output}\nQSV stage: skipped because capture did not pass.");
        return (200, format!("{{\"status\":\"warn\",\"output\":{},\"advice\":\"DXGI capture chưa đạt. Kiểm tra VDD, monitor-index và topology trước khi đánh giá encoder.\",\"monitorIndex\":{},\"mock\":false}}", json_quote(&output), monitor));
    }
    let (qsv_ok, qsv_output) = run_gst_pipeline(&pipeline_args(monitor, true));
    let status = if qsv_ok { "pass" } else { "warn" };
    let output = format!("DXGI visible capture: PASS — 150 frame ở 30 FPS, đã mở autovideosink.\nQSV capture→encode: {} — 300 frame ở 1080p60 vào fakesink.\n{}",
        if qsv_ok { "PASS" } else { "WARN" }, qsv_output);
    let advice = if qsv_ok { "DXGI preview và QSV đã chạy. Đây mới là kiểm tra pipeline cục bộ; chưa có WebRTC hoặc đo glass-to-glass." }
        else { "DXGI capture đạt nhưng QSV encode chưa đạt. Kiểm tra gst-inspect-1.0 qsvh264enc và topology/LUID; NVENC chưa tự động thay thế QSV trên laptop." };
    (200, format!("{{\"status\":{},\"output\":{},\"advice\":{},\"monitorIndex\":{},\"mock\":false}}", json_quote(status), json_quote(&output), json_quote(advice), monitor))
}

/// Kiểm tra **một lần** xem đường live có chạy được không: có `gst-launch-1.0`
/// trong PATH và có plugin `d3d11screencapturesrc`. Trả về `(available, detail)`
/// với `detail` là câu **người dùng đọc được**, không phải mã lỗi.
/// Có được bind ra ngoài loopback không?
///
/// Luật là của **spec**: `security::gate::Transport::for_bind` (§41.5 D4,
/// §54.5 #1 — "không có biến thể tắt"). Bản đầu của hàm này tự viết lại luật
/// đó với danh sách loopback riêng, và doc của nó nói "chưa có đăng nhập" —
/// câu vừa trở thành sai khi `/api/login` có thật.
///
/// Trả `(được_bind, lý_do)`.
fn allowed_bind_host(requested: &str) -> (String, Option<String>) {
    let loopback_only = ["127.0.0.1", "localhost", "::1"].contains(&requested);
    if loopback_only {
        // Bind `127.0.0.1` thay vì để OS quyết: "localhost" có thể ra ::1 rồi
        // trình duyệt lại gõ 127.0.0.1 và không vào được.
        return ("127.0.0.1".to_string(), None);
    }
    // Hỏi spec trước. `has_cert = false`: bản này chưa có TLS, nên spec sẽ từ
    // chối mọi địa chỉ không-loopback — đó là điều ta muốn.
    let spec_allows = auth_wire::bind_is_allowed(requested, false).is_ok();
    let forced = env::var("LANTERN_ALLOW_LAN").map(|value| value == "1").unwrap_or(false);
    if forced {
        // Cờ ghi đè phải **thật sự** ghi đè, nếu không nó chỉ là lời nói suông.
        if !spec_allows {
            eprintln!(
                "CẢNH BÁO: bind {requested} không có TLS — chỉ vì LANTERN_ALLOW_LAN=1. \
                 Nội dung màn hình và điều khiển chuột/bàn phím đi qua mạng dạng rõ (§41.4 T4)."
            );
        }
        return (requested.to_string(), None);
    }
    if spec_allows {
        return (requested.to_string(), None);
    }
    (
        "127.0.0.1".to_string(),
        Some(format!(
            "Từ chối bind {requested}: chưa có TLS (§54.5 #1). Đang bind 127.0.0.1 thay thế. \
             Muốn tự chịu rủi ro trên LAN: đặt LANTERN_ALLOW_LAN=1 (không khuyến khích)."
        )),
    )
}

/// Đường xem màn hình có dùng được không, và **nếu không thì vì sao**.
///
/// Trên Windows: kiểm DXGI thật bằng cách **mở một phiên capture rồi đóng ngay**.
/// Đó là câu trả lời đúng nhất có thể đưa ra mà không capture nội dung — nếu
/// `IDXGIOutputDuplication` mở được thì nút "Xem máy thật" sẽ chạy.
///
/// Trên Linux/macOS: trả `false` kèm lý do, **không** giả vờ sẵn sàng (§58.3).
fn probe_live_status() -> (bool, String) {
    #[cfg(windows)]
    {
        match capture::Capture::open(0) {
            Ok(session) => {
                let (width, height) = session.size();
                drop(session); // đóng ngay: không giữ phiên nào khi chỉ đang kiểm
                (true, format!("Sẵn sàng: DXGI {width}×{height}, JPEG trong exe, không cần cài gì."))
            }
            Err(error) => (false, error.message()),
        }
    }
    #[cfg(not(windows))]
    {
        (
            false,
            format!(
                "Capture màn hình chỉ chạy trên Windows. Đang chạy trên {} nên không có desktop để capture.",
                std::env::consts::OS
            ),
        )
    }
}

/// Client còn kết nối không? `peek` không lấy mất dữ liệu (client không gửi gì
/// trên đường này).
///
/// Bản đầu tiên chỉ coi `Ok(0)` là đóng, và **đóng tab của Chrome đi qua đường
/// khác** — nên pipeline sống mãi:
/// | `peek` trả | Nghĩa | Kết luận |
/// |---|---|---|
/// | `Ok(0)` | FIN: đóng bình thường | **đã đóng** |
/// | `Ok(_)` | có byte đến (không xảy ra trên đường này) | còn sống |
/// | `Err(...)` khác timeout | **RST**: đóng khi còn byte chưa đọc | **đã đóng** |
/// | `Err(WouldBlock/TimedOut)` | 200 ms không có gì | còn sống |
#[cfg_attr(not(windows), allow(dead_code))]
fn peer_closed(stream: &TcpStream) -> bool {
    use std::io::ErrorKind;
    let _ = stream.set_read_timeout(Some(std::time::Duration::from_millis(200)));
    let mut probe = [0u8; 1];
    match stream.peek(&mut probe) {
        Ok(0) => true,
        Ok(_) => false,
        Err(error) => !matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut),
    }
}

/// Bơm MJPEG từ `gst-launch-1.0` ra socket. Không qua shell, không qua file tạm:
/// `fdsink fd=1` ghi thẳng vào stdout của tiến trình con, ta chuyển tiếp.
///
/// Hai chỗ **không được block vô hạn**, vì đó là cách hỏng tệ nhất (im lặng):
/// Chất lượng JPEG cho đường xem màn hình: 70 là điểm "chữ còn đọc được" mà
/// vẫn nhẹ (một frame 720p khoảng 40–90 KB). Đổi số này là đổi băng thông —
/// xem §58.14.
#[cfg_attr(not(windows), allow(dead_code))]
const JPEG_QUALITY: u8 = 70;

/// Một phần của multipart: header + JPEG + CRLF.
#[cfg_attr(not(windows), allow(dead_code))]
fn frame_chunk(jpeg: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(jpeg.len() + 64);
    out.extend_from_slice(stream::frame_header().as_bytes());
    out.extend_from_slice(jpeg);
    out.extend_from_slice(b"\r\n");
    out
}

/// `GET /api/live.mjpg` — vòng lặp capture → nén → ghi, **không** GStreamer.
///
/// Ba thứ bản này làm mà bản GStreamer không làm được:
///
/// 1. **Chỉ gửi khi hình đổi.** Màn hình tĩnh ⇒ 0 byte, 0% CPU nén, pin không tụt.
///
/// 2. **Không có tiến trình con** ⇒ không có capture mồ côi, không có `ChildGuard`,
///    không có `stderr` treo (§58.7–§58.9 trở thành vô nghĩa vì không còn gì để dọn).
///
/// 3. **Không cài gì**: toàn bộ nằm trong exe ~500 KB.
fn stream_live(
    mut stream: TcpStream,
    monitor: u8,
    fps: u8,
    // §5.4: `None` = cả màn hình; `Some(hwnd)` = crop theo cửa sổ đã chọn.
    // Trên Linux không có nhánh nào dùng (không có DXGI), nên phải `allow`.
    #[cfg_attr(not(windows), allow(unused_variables, reason = "chỉ nhánh Windows crop"))]
    window: Option<i64>,
    state: &Arc<Mutex<State>>,
) {
    #[cfg(not(windows))]
    {
        let _ = (fps, state);
        response(
            &mut stream,
            503,
            "text/plain; charset=utf-8",
            format!(
                "Capture màn hình chỉ chạy trên Windows. Đang chạy trên {} nên không có desktop để capture (monitor={monitor}).",
                std::env::consts::OS
            )
            .as_bytes(),
        );
    }

    #[cfg(windows)]
    {
        use std::time::{Duration, Instant};

        /// Chờ frame **đầu tiên**. Ngắn hơn bản GStreamer (8 s) vì không có
        /// cold start của pipeline: chỉ là thời gian DXGI trả frame đầu.
        const FIRST_FRAME: Duration = Duration::from_secs(4);

        // §5.4/§5.5.1: cửa sổ đã chọn. Lấy rect **một lần** khi bắt đầu — cửa
        // sổ di chuyển giữa stream thì vùng cắt phải bám theo, nhưng làm vậy
        // mỗi frame tốn một `DwmGetWindowAttribute` (~50 µs) và ảnh sẽ "trượt"
        // dưới con trỏ. Bản này cố định vùng cắt và ghi rõ giới hạn đó.
        let window_rect = window.and_then(|hwnd| {
            let rect = windows::extended_frame_bounds(hwnd)?;
            if rect.is_empty() { None } else { Some(rect) }
        });
        // Nếu client đã chọn một cửa sổ mà không lấy được rect (cửa sổ vừa
        // đóng), nói thật thay vì lặng lẽ stream cả màn hình — người dùng sẽ
        // tưởng window picker không có tác dụng.
        if window.is_some() && window_rect.is_none() {
            return response(&mut stream, 409, "text/plain; charset=utf-8",
                "Cửa sổ đã chọn không còn tồn tại (có thể vừa đóng). Hãy chọn lại.".as_bytes());
        }
        // Ghi offset để `inject` cộng vào toạ độ: gốc frame là góc cửa sổ,
        // không phải góc màn hình. Không cộng thì bấm giữa cửa sổ sẽ bấm giữa
        // màn hình — lệch đúng bằng vị trí cửa sổ.
        {
            let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
            s.capture_offset = window_rect.map(|rect| (rect.left, rect.top)).unwrap_or((0, 0));
        }

        let mut capture = match capture::Capture::open(monitor) {
            Ok(capture) => capture,
            Err(error) => {
                return response(&mut stream, 503, "text/plain; charset=utf-8", error.message().as_bytes());
            }
        };

        let deadline = Instant::now() + FIRST_FRAME;
        let first = loop {
            match capture.next_frame(200) {
                Ok(frame) => break frame,
                Err(capture::CaptureError::Timeout) => {
                    if peer_closed(&stream) {
                        return;
                    }
                    if Instant::now() >= deadline {
                        let message = format!(
                            "Màn hình {} không trả frame nào trong {} giây. Thử monitor khác hoặc kiểm tra driver GPU.",
                            monitor,
                            FIRST_FRAME.as_secs()
                        );
                        return response(&mut stream, 504, "text/plain; charset=utf-8", message.as_bytes());
                    }
                }
                Err(error) => {
                    return response(&mut stream, 503, "text/plain; charset=utf-8", error.message().as_bytes());
                }
            }
        };

        // Header chỉ đi **sau** khi đã có frame thật (§58.3 #2).
        let encode_started = Instant::now();
        // §5.4: crop theo `EXTENDED_FRAME_BOUNDS` (đã kẹp vào frame). Không
        // crop được thì stream cả frame — và nói lý do ở stderr, không im lặng.
        let first = match window_rect {
            Some(rect) => match crop::plan(
                crop::Rect { left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom },
                first.width, first.height) {
                Some(plan) => {
                    let bgra = crop::extract(&first.bgra, first.width, plan);
                    capture::Frame { width: plan.width, height: plan.height, bgra }
                }
                None => {
                    return response(&mut stream, 409, "text/plain; charset=utf-8",
                        "Cửa sổ đã chọn nằm ngoài màn hình đang chia sẻ. Chọn cửa sổ khác hoặc chuyển sang chế độ toàn màn hình.".as_bytes());
                }
            },
            None => first,
        };
        let first_jpeg = jpeg::encode(&first.bgra, first.width, first.height, JPEG_QUALITY);
        let first_encode_us = encode_started.elapsed().as_micros() as u64;
        {
            let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
            s.live_metrics = LiveMetrics {
                frames: 1,
                jpeg_bytes: first_jpeg.len() as u64,
                encode_us: first_encode_us,
                started_ms: now_ms(),
                width: first.width,
                height: first.height,
            };
        }
        if stream.write_all(stream::stream_head().as_bytes()).is_err()
            || stream.write_all(&frame_chunk(&first_jpeg)).is_err()
            || stream.flush().is_err()
        {
            return;
        }

        let budget = Duration::from_micros(1_000_000 / u64::from(fps.max(1)));
        let mut previous = first.bgra;
        let mut next_due = Instant::now() + budget;
        // §6.4.7 lớp 4: watchdog 3 s. Client mất mạng khi đang giữ Ctrl ⇒
        // không bao giờ gửi `key up` ⇒ máy thật kẹt Ctrl tới khi reboot. Đây
        // là lưới **duy nhất** bắt được trường hợp đó, vì nó không phụ thuộc
        // client còn sống.
        let mut last_watchdog = Instant::now();
        loop {
            if peer_closed(&stream) {
                return;
            }
            match capture.next_frame(0) {
                Ok(frame) => {
                    // Crop **trước** khi so sánh: chuyển động ở phần màn hình
                    // ngoài cửa sổ không được làm ta nén lại frame.
                    let frame = match window_rect {
                        Some(rect) => match crop::plan(
                            crop::Rect { left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom },
                            frame.width, frame.height) {
                            Some(plan) => {
                                let bgra = crop::extract(&frame.bgra, frame.width, plan);
                                capture::Frame { width: plan.width, height: plan.height, bgra }
                            }
                            // Cửa sổ ra ngoài: giữ nguyên frame trước, đừng gửi
                            // ảnh rác.
                            None => continue,
                        },
                        None => frame,
                    };
                    if frame.bgra != previous {
                        let started = Instant::now();
                        let jpeg = jpeg::encode(&frame.bgra, frame.width, frame.height, JPEG_QUALITY);
                        let encode_us = started.elapsed().as_micros() as u64;
                        if stream.write_all(&frame_chunk(&jpeg)).is_err() {
                            return; // tab đóng
                        }
                        // Số đo thật cho UI — thay cho "24 ms / 2.4 Mbps" bịa.
                        {
                            let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
                            s.live_metrics.frames += 1;
                            s.live_metrics.jpeg_bytes += jpeg.len() as u64;
                            s.live_metrics.encode_us += encode_us;
                            s.live_metrics.width = frame.width;
                            s.live_metrics.height = frame.height;
                        }
                        previous = frame.bgra;
                    }
                }
                // Không có frame mới = màn hình không đổi, **không phải lỗi**.
                Err(capture::CaptureError::Timeout) => {}
                // Desktop đổi (UAC/khoá máy/đổi độ phân giải): dừng sạch. Trình
                // duyệt sẽ thấy stream kết thúc và `#liveImage` báo lỗi, UI dừng
                // chứ không hiện khung đen đứng.
                Err(capture::CaptureError::AccessLost) => return,
                Err(_) => return,
            }
            // Giới hạn tốc độ: DXGI có thể trả frame nhanh hơn `fps` khi có
            // chuyển động mạnh (con trỏ, video). Không giới hạn thì ta nén
            // nhiều hơn mức người xem nhận được.
            // 1 Hz là đủ (§44.2 nói watchdog 3 s).
            if last_watchdog.elapsed() >= Duration::from_secs(1) {
                last_watchdog = Instant::now();
                let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
                if let Some(actions) = input::watchdog(&mut s.input, now_ms() as u64) {
                    drop(s);
                    input::inject(&actions);
                }
            }
            let now = Instant::now();
            if next_due > now {
                std::thread::sleep(next_due - now);
            }
            next_due = Instant::now() + budget;
        }
    }
}

fn handle(mut stream: TcpStream, state: Arc<Mutex<State>>) {
    let Some((method, path, req_headers, body_bytes)) = read_request(&mut stream) else { return; };
    if body_bytes == b"__BODY_TOO_LARGE__" {
        return json_response(&mut stream, 413, "{\"error\":\"body_too_large\"}".into());
    }
    // Body JSON: đọc best-effort. Route nhị phân (`/move` của §8.3) dùng
    // `body_bytes` trực tiếp và **không** đụng `body`.
    let body = String::from_utf8(body_bytes.clone()).unwrap_or_default();
    let route = path.split('?').next().unwrap_or("/");
    if method == "GET" && route == "/" { return response(&mut stream, 200, "text/html; charset=utf-8", INDEX.as_bytes()); }
    if method == "GET" && route == "/styles.css" { return response(&mut stream, 200, "text/css; charset=utf-8", CSS.as_bytes()); }
    if method == "GET" && route == "/app.js" { return response(&mut stream, 200, "text/javascript; charset=utf-8", JS.as_bytes()); }
    // Thiếu route này thì `auth.js` 404 ⇒ màn hình khoá **không bao giờ mở**,
    // và app trông như treo ở màn hình đăng nhập. Đúng loại lỗi im lặng đã gặp
    // với `/live.js`: asset khai báo trong HTML mà không có route.
    if method == "GET" && route == "/auth.js" { return response(&mut stream, 200, "text/javascript; charset=utf-8", AUTH_JS.as_bytes()); }
    // §6.4/§6.5: bộ điều khiển chuột/bàn phím của client. Một file riêng (không
    // nhúng vào `live_page`) để `npm test` chạy được từng luật spec — throttle
    // latest-wins, down/up không gộp, `sendBeacon` lúc unload.
    if method == "GET" && route == "/input.js" { return response(&mut stream, 200, "text/javascript; charset=utf-8", INPUT_JS.as_bytes()); }
    // Trang `/live` cần script **file riêng**: CSP `default-src 'self'` chặn
    // inline script (§41.4 T5), nên nhúng JS vào HTML thì trang tải được mà
    // không có dòng nào chạy — lỗi im lặng.
    if method == "GET" && route == "/live.js" { return response(&mut stream, 200, "text/javascript; charset=utf-8", LIVE_JS.as_bytes()); }
    if method == "GET" && route == "/api/diagnostics" { return json_response(&mut stream, 200, run_diagnostics()); }
    // Nhìn thấy màn hình thật trong trình duyệt, không cần WebRTC (§58).
    // `GET /live` là trang tối giản cho điện thoại; `GET /api/live.mjpg` là stream.
    // `/api/live/status` trả lời được câu "nút Xem máy thật có dùng được không, và
    // nếu không thì vì sao" — thay vì để người dùng bấm vào rồi mới thấy lỗi.
    if method == "GET" && route == "/api/live/status" {
        // Cache bị **xoá** sau khi cài xong (`install_gstreamer`) để lần hỏi sau
        // phản ánh trạng thái mới — nếu không, UI vẫn hiện "chưa có GStreamer"
        // sau khi vừa cài thành công, và người dùng bấm lại vô ích.
        let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
        if s.live_status.is_none() { s.live_status = Some(probe_live_status()); }
        let (available, detail) = s.live_status.clone().unwrap_or((false, String::new()));
        // Không còn bước cài đặt nào: mọi thứ đã nằm trong exe. UI dùng trường
        // này để biết có nên hiện nút "Tự cài" hay không — giờ luôn là `false`.
        let can_install = false;
        // Số đo **thật** của phiên đang chạy. `frames: 0` nghĩa là chưa ai xem —
        // UI phải hiện "—", không được hiện số ước lượng.
        let m = s.live_metrics.clone();
        drop(s);
        let elapsed = now_ms().saturating_sub(m.started_ms);
        return json_response(&mut stream, 200, format!(
            "{{\"available\":{available},\"canInstall\":{can_install},\"detail\":{},\"contentType\":{},\"boundary\":{},\
\"metrics\":{{\"frames\":{},\"width\":{},\"height\":{},\"fps\":{:.1},\"kbPerFrame\":{:.1},\"msPerFrame\":{:.1},\"mbps\":{:.2}}}}}",
            json_quote(&detail), json_quote(&stream::mjpeg_content_type()), json_quote(stream::BOUNDARY),
            m.frames, m.width, m.height, m.fps(elapsed), m.kb_per_frame(), m.ms_per_frame(), m.mbps(elapsed)));
    }
    if method == "GET" && (route == "/live" || route == "/api/live.mjpg") {
        let query = path.split_once('?').map(|(_, q)| q).unwrap_or("");
        let (monitor, fps) = stream::parse_live_query(query);
        if route == "/live" {
            return response(&mut stream, 200, "text/html; charset=utf-8", stream::live_page(monitor, fps).as_bytes());
        }
        // §41.4 T1: **kiểm quyền trước khi làm gì khác.** Đặt sau bước probe
        // capture thì máy không capture được trả `503` cho cả người lạ **và**
        // người có token — nhìn như lỗi môi trường, thực ra là chưa đăng nhập.
        // Kiểm trước cũng tránh khởi tạo DXGI cho request không có quyền.
        // §41.4 T1: **kiểm quyền trước khi làm gì khác.** Đặt sau bước probe
        // capture thì máy không capture được trả `503` cho cả người lạ **và**
        // người có token — nhìn như lỗi môi trường, thực ra là chưa đăng nhập.
        //
        // # `<img src>` không gửi được `Authorization`
        //
        // Thẻ `<img>` tải stream và **không có cách nào** gắn header. Đòi bearer
        // token ở đây thì sau khi đăng nhập khung hình **đen vĩnh viễn** — lỗi
        // tệ hơn cả không có auth, vì nó chỉ xuất hiện sau khi người dùng làm
        // đúng mọi bước.
        //
        // Nên route này nhận thêm **cookie** `lantern_refresh` (HttpOnly, JS
        // không đọc được) làm bằng chứng: trình duyệt tự gửi nó cho request
        // cùng origin. `SameSite=Strict` của cookie chặn trang khác lợi dụng.
        //
        // Không hạ yêu cầu bảo mật: vẫn là token đã ký, vẫn qua
        // `authorize_maybe_scoped` (chữ ký + hạn + issuer + audience + revoke).
        // Chỉ **nguồn** token khác — cookie thay vì header — vì `<img>` không
        // cho chọn.
        {
            let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
            // Đổi cookie → access token **một lần**, ngay tại đây, rồi đi qua
            // đúng một hàm kiểm quyền như mọi route khác. Hai nhánh kiểm quyền
            // là hai cơ hội để sai.
            let from_cookie = match auth_wire::cookie_value(&req_headers, "lantern_refresh") {
                Some(refresh) => {
                    let now = now_ms() as u64;
                    match s.auth.auth.as_mut() {
                        Some(auth) => auth
                            .refresh_session(refresh, "local-device", now, &mut auth_wire::RealEntropy)
                            .map(|rotated| rotated.access),
                        None => None,
                    }
                }
                None => None,
            };
            let verdict = guard::require_token_with_refresh(
                effective_policy(&s),
                &req_headers,
                s.auth.auth.as_ref(),
                from_cookie.as_deref(),
                None,
                now_ms() as u64,
            );
            match verdict {
                guard::Verdict::Allowed(_) => {}
                guard::Verdict::Denied { status, code } => {
                    json_response(&mut stream, status, format!("{{\"error\":{}}}", json_quote(code)));
                    return;
                }
            }
        }
        // §5.4: cửa sổ của **phiên đang chạy** quyết định có crop hay không.
        // Trước bản này `window_id` được lưu, kiểm quyền, trả về UI — và
        // **không ảnh hưởng gì** tới hình. Người dùng chọn "Ghi chú" rồi vẫn
        // thấy cả màn hình: window picker không có tác dụng thật.
        //
        // `desktop` = cửa sổ đặc biệt "toàn màn hình" (§5.3 VNC), không phải
        // hwnd, nên không crop.
        let window = {
            let s = state.lock().unwrap_or_else(|e| e.into_inner());
            s.session.as_ref().and_then(|session| {
                if session.window_id == "desktop" {
                    None
                } else {
                    windows::hwnd_from_wid(&session.window_id)
                }
            })
        };
        return stream_live(stream, monitor, fps, window, &state);
    }
    if method == "POST" && route == "/api/diagnostics/capture" { let (status,body)=capture_probe(&body); return json_response(&mut stream,status,body); }
    let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
    match (method.as_str(), route) {
        ("GET", "/api/health") => json_response(&mut stream, 200, "{\"ok\":true,\"app\":\"lantern-mock\",\"mode\":\"mock\"}".into()),
        ("GET", "/api/device") => json_response(&mut stream, 200, "{\"id\":\"inspiron-7467\",\"name\":\"Inspiron 7467\",\"status\":\"ready\",\"platform\":\"Windows 11\",\"location\":\"Ở nhà\",\"mock\":true}".into()),
        // §6.10.2 câu 2: *"hoặc hiện ước lượng ~8 Mbps trước khi bấm Start"*.
        // Route này tồn tại để UI hiện con số **trước** khi tạo phiên — nếu
        // không, người dùng chỉ biết mình dùng bao nhiêu băng thông sau khi đã
        // dùng. Số đo là của phiên trước, nên nó có thể `null`.
        ("GET", "/api/advice") => {
            let elapsed = now_ms().saturating_sub(s.live_metrics.started_ms);
            let measured = if s.live_metrics.frames >= 10 && elapsed >= advice::MIN_SAMPLE_MS {
                let mbps = s.live_metrics.mbps(elapsed);
                (mbps.is_finite() && mbps > 0.0).then_some(mbps)
            } else {
                None
            };
            let recommended = advice::recommend(measured);
            let (estimate_mbps, estimate_label) = advice::estimate_before_start();
            json_response(&mut stream, 200, format!(
                "{{\"recommendation\":{},\"estimate\":{{\"mbps\":{},\"preset\":\"{}\"}}}}",
                advice::advice_json(&recommended), estimate_mbps, estimate_label))
        }
        // §5.4 — `EnumWindows` **thật**. Trước đây route này trả ba cửa sổ viết
        // cứng ("Trình duyệt", "Ghi chú"), nên trên máy người dùng danh sách
        // hiện ba thứ không tồn tại. Đó là lý do cảm giác "vẫn là demo": danh
        // sách cửa sổ là thứ **đầu tiên** người dùng chạm vào.
        ("GET", "/api/windows") => {
            // §41.3 #3: danh sách cửa sổ là **thông tin về máy đang chạy** —
            // tên app và tiêu đề tài liệu người dùng đang mở. Đã đặt mật khẩu
            // thì nó cần token như mọi thứ khác; trước bản này route không gọi
            // `deny_if_unauthorised`, nên đặt mật khẩu xong vẫn đọc được danh
            // sách **không cần đăng nhập** (đã kiểm bằng curl: 200).
            if deny_if_unauthorised(&mut stream, &s, &req_headers, None).is_none() {
                return;
            }
            // §41.3 #3 / §41.4 T1: **publish** danh sách vào `WindowRegistry`
            // của spec, rồi trả `snapshotId` cho client. Từ đây client chỉ
            // tham chiếu được `wid` trong snapshot này (TTL 3 s) — nó không
            // bao giờ cầm hwnd, nên không mở được cửa sổ mà agent cố ý không
            // trả về. Đây chính là "lỗ hổng leo thang quyền thật" mà §41.3
            // gọi tên.
            let (entries, excluded) = windows::enumerate_with_summary();
            let registry_entries = windows::to_registry_entries(&entries);
            let mut entropy = auth_wire::RealEntropy;
            let (snapshot_id, published) = s.windows.publish(
                registry_entries,
                now_ms() as u64,
                &mut entropy,
                "local",
            );
            // Ghép `wid` của registry (id hex) với dữ liệu hiển thị, theo
            // **đúng thứ tự** registry trả (nó đã loại `wid` trùng).
            let by_wid: BTreeMap<String, usize> = entries
                .iter()
                .enumerate()
                .map(|(index, entry)| (format!("{:016x}", entry.hwnd as u64), index))
                .collect();
            let paired: Vec<(String, windows::WindowEntry)> = published
                .iter()
                .filter_map(|entry| {
                    let index = *by_wid.get(&entry.wid)?;
                    Some((entry.wid.clone(), entries[index].clone()))
                })
                .collect();
            let body = windows::windows_json(&paired);
            let note = windows::platform_note()
                .map(|reason| format!(",\"note\":{}", json_quote(reason)))
                .unwrap_or_default();
            // Vì sao danh sách có thể ngắn hơn số cửa sổ đang mở (§5.4 loại 7
            // kiểu). Chỉ **số đếm** theo lý do, không tiêu đề: cửa sổ bị loại
            // có thể là popup của trình quản lý mật khẩu.
            let excluded_json = excluded
                .iter()
                .map(|(code, count)| format!("{{\"code\":{},\"count\":{count}}}", json_quote(code)))
                .collect::<Vec<_>>()
                .join(",");
            json_response(&mut stream, 200, format!(
                "{{\"windows\":{},\"count\":{},\"snapshotId\":{},\"excluded\":[{excluded_json}]{note}}}",
                body, paired.len(), json_quote(&snapshot_id)))
        }
        ("GET", "/api/settings") => json_response(&mut stream, 200, format!("{{\"settings\":{},\"mock\":true}}", settings_json(&s.settings))),
        ("PATCH", "/api/settings") => {
            let Some(patch) = parse_flat_object(&body) else { return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into()); };
            let mut changed = Vec::new();
            // Bản trước chỉ nhận key **đã có** trong map: `if s.settings.contains_key(&key)`.
            // Hệ quả thật: thêm một setting mới (như §50.3 `upload`) thì nó
            // **không bật được** — `PATCH` trả 200, `updated:[]`, và UI trông
            // như đã lưu. Người dùng bật "gửi file" rồi upload vẫn 403.
            //
            // Giờ: bất kỳ key nào `allowed_value` chấp nhận đều ghi được. Key
            // lạ (không có trong bảng) vẫn bị bỏ qua — đó là hành vi đúng, vì
            // chấp nhận key tuỳ ý là mở đường cho client ghi rác vào cài đặt.
            for (key, value) in patch {
                if !allowed_value(&key, &value) { continue; }
                s.settings.insert(key.clone(), value);
                changed.push(json_quote(&key));
            }
            let _ = fs::create_dir_all(&s.data_dir);
            let _ = fs::write(s.data_dir.join("settings.json"), settings_json(&s.settings));
            json_response(&mut stream, 200, format!("{{\"settings\":{},\"updated\":[{}],\"mock\":true}}",settings_json(&s.settings),changed.join(",")))
        }
        ("GET", "/api/sessions/current") => json_response(&mut stream, 200, format!("{{\"session\":{},\"mock\":true}}",s.session.as_ref().map(session_json).unwrap_or_else(||"null".into()))),
        // §6.11.1 / §8.1 `GET /api/sessions/mine` — "phiên còn sống trong grace
        // (resume)". Mục đích: reload trang (§50.1 #3) không phải tạo phiên
        // mới. Đặt **trước** nhánh `/{sid}` bên dưới, nếu không `mine` bị đọc
        // thành một `sid` và trả 404 — đúng lỗi thứ tự route đã có tiền lệ.
        ("GET", "/api/sessions/mine") => {
            let live = s.session.as_ref().map(session_json).unwrap_or_else(|| "null".into());
            json_response(&mut stream, 200, format!("{{\"sessions\":{}}}", if live == "null" { "[]".to_string() } else { format!("[{live}]") }))
        }
        // §8.1 `GET /api/sessions/{sid}` → `{state,stats,audio,view_only,warnings,cursor_mode}`.
        // `stats` là số đo **thật** của `LiveMetrics`, không phải số bịa.
        // `GET /api/sessions/{sid}` — **chỉ** đúng một segment.
        //
        // Bản trước dùng `p.starts_with("/api/sessions/") && !p.contains("/input")`,
        // nên nó nuốt **mọi** GET con: `/api/sessions/x/clipboard`,
        // `/api/sessions/x/events`, `/api/sessions/x/mine`… Tất cả trả 404
        // `session_not_found` vì `sid` hoá ra là `"x/clipboard"`. Đó là lý do
        // route clipboard thêm vào vẫn không chạy, dù nó khai báo "trước" trong
        // `match` — guard của route này **rộng hơn** và đứng trước.
        //
        // Đếm số `/` là cách kiểm rẻ và không phải bảo trì danh sách loại trừ:
        // thêm một route con nữa sẽ tự động không bị nuốt.
        ("GET", p) if p.starts_with("/api/sessions/") && p.matches('/').count() == 3 => {
            let sid = p.trim_start_matches("/api/sessions/");
            let Some(session) = s.session.as_ref().filter(|session| session.id == sid) else {
                return json_response(&mut stream, 404, "{\"error\":\"session_not_found\"}".into());
            };
            let metrics = &s.live_metrics;
            let (fps, kbps) = metrics.summary();
            json_response(&mut stream, 200, format!(
                "{{\"session\":{},\"state\":\"{}\",\"stats\":{{\"fps\":{},\"kbps\":{},\"frames\":{},\"width\":{},\"height\":{}}},\"audio\":{{\"enabled\":{},\"available\":false}},\"viewOnly\":{},\"warnings\":[],\"cursorMode\":\"{}\",\"keyframes\":{}}}",
                session_json(session), session.state, fps, kbps, metrics.frames, metrics.width, metrics.height,
                session.audio, session.view_only, session.cursor_mode.as_str(), s.keyframes
            ))
        }
        ("POST", "/api/sessions") => {
            // §41.4 T3: tạo phiên là mutation nguy hiểm nhất — nó sinh ra
            // quyền xem màn hình + điều khiển chuột/bàn phím.
            if deny_if_unauthorised(&mut stream, &s, &req_headers, None).is_none() { return; }
            let Some(input) = parse_flat_object(&body) else { return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into()); };
            // **Thứ tự có nghĩa**: kiểm `wid` (§41.3 #3) và tham số **trước**
            // khi kiểm "đã có phiên". Bản trước kiểm "đã có phiên" trước, nên
            // trên server đang có phiên thì **mọi** `wid` bịa đều trả 409
            // `session_already_active` — cổng `wid` trông như có mà không kiểm
            // gì, và test cũng không thấy. Một client độc gửi `wid` của cửa sổ
            // nhạy cảm sẽ nhận 409 thay vì 403, tức là nó **không biết** mình
            // đã bị chặn ở đâu. Kiểm rẻ (parse) trước, kiểm nặng (registry)
            // sau, kiểm trạng thái (đã có phiên) **cuối**.
            let mode = input.get("mode").map(String::as_str).unwrap_or("hvnc");
            // §5.4 + §41.3 #3: client gửi `wid` lấy từ snapshot, **không** phải
            // hwnd. `snapshotId` phải đi kèm; thiếu thì không kiểm được `wid`
            // có thuộc danh sách agent vừa trả hay không.
            let win = input.get("windowId").map(String::as_str).unwrap_or("desktop");
            let snapshot = input.get("snapshotId").map(String::as_str).unwrap_or("");
            if !["hvnc","vnc"].contains(&mode) { return json_response(&mut stream, 422, "{\"error\":\"invalid_session_mode\"}".into()); }
            // §5.4: cửa sổ phải **crop được** ngay bây giờ. Kiểm trước khi tạo
            // phiên, để người dùng nhận lỗi rõ ràng thay vì tạo phiên rồi thấy
            // stream cả màn hình (hoặc 409 giữa chừng).
            if win != "desktop" {
                let hwnd = windows::hwnd_from_wid(win);
                let rect = hwnd.and_then(windows::extended_frame_bounds);
                if hwnd.is_none() || rect.is_none() {
                    // Nói **vì sao**: cửa sổ vừa đóng, hoặc DWM không trả
                    // bounds. Không nói thì người dùng chỉ thấy "lỗi".
                    return json_response(&mut stream, 409,
                        "{\"error\":\"window.unavailable\",\"detail\":\"Cửa sổ vừa đóng hoặc không lấy được khung hình. Hãy liệt kê lại.\"}"
                            .to_string());
                }
            }
            // Cổng **duy nhất** nhận `wid` (spec: `WindowRegistry::authorize`).
            // `desktop` là cửa sổ đặc biệt (stream cả màn hình, §5.3 VNC), không
            // cần snapshot vì nó không phải một hwnd nào.
            if win != "desktop" {
                match s.windows.authorize(snapshot, win, now_ms() as u64) {
                    Ok(_) => {}
                    Err(error) => {
                        // 403 `window.unknown` khi client bịa `wid`;
                        // 409 `window.list_stale` khi snapshot quá 3 s.
                        let code = error.clone().code();
                        let status = error.status();
                        return json_response(&mut stream, status,
                            format!("{{\"error\":{}}}", json_quote(code)));
                    }
                }
            }
            s.next_id += 1;
            // §6.10.1: preset mặc định là "Cân bằng"; `POST /api/sessions`
            // (§8.1) cho chọn ngay từ đầu. Giá trị lạ ⇒ 422, không đoán.
            let preset = input.get("preset").map(String::as_str).unwrap_or(session_state::DEFAULT_PRESET);
            let Ok(preset) = session_state::resolve_preset(preset) else {
                return json_response(&mut stream, 422, "{\"error\":\"invalid_preset\"}".into());
            };
            let monitor = match input.get("monitor") {
                Some(raw) => match raw.parse::<u32>().ok().and_then(|index| session_state::valid_monitor(index).ok()) {
                    Some(index) => index,
                    None => return json_response(&mut stream, 422, "{\"error\":\"invalid_monitor\"}".into()),
                },
                None => 0,
            };
            // Kiểm trạng thái **cuối cùng** — sau khi mọi tham số đã hợp lệ.
            if let Some(active) = &s.session {
                return json_response(&mut stream, 409, format!(
                    "{{\"error\":\"session_already_active\",\"session\":{}}}", session_json(active)));
            }
            // §6.10.2: **trước khi bắt đầu** — đề nghị preset từ số đo phiên
            // trước (5 s gần nhất, hoặc cả phiên nếu ngắn hơn), để người dùng
            // không phải đoán. Người dùng đã chọn `preset` rõ ràng thì đề nghị
            // chỉ để tham khảo: `preset` của họ thắng.
            let measured = {
                let (_, _) = s.live_metrics.summary();
                let elapsed = now_ms().saturating_sub(s.live_metrics.started_ms);
                if s.live_metrics.frames >= 10 && elapsed >= advice::MIN_SAMPLE_MS {
                    let mbps = s.live_metrics.mbps(now_ms().saturating_sub(s.live_metrics.started_ms));
                    (mbps.is_finite() && mbps > 0.0).then_some(mbps)
                } else {
                    None
                }
            };
            let recommended = advice::recommend(measured);
            let session = Session {
                id: format!("mock-{}",s.next_id), mode: mode.into(), window_id: win.into(),
                started_at: now_seconds(),
                audio: input.get("audio").map(|v|v!="false").unwrap_or(true),
                monitor,
                preset: preset.id.to_string(),
                cursor_mode: session_state::CursorMode::Local,
                view_only: input.get("view_only").map(|v| v=="true").unwrap_or(false),
                state: "active",
                share_ttl_min: None,
            };
            let result = session_json(&session);
            // Luật §6.10.1: người dùng **chọn tay** thì preset của họ thắng —
            // đề nghị là để tham khảo, và phải nói được là nó khác lựa chọn.
            let taken_from_user = input.contains_key("preset");
            let advice_json = advice::advice_json(&recommended);
            let hint = if taken_from_user && recommended.recommended.id != session.preset {
                ",\"advice_conflict\":true".to_string()
            } else {
                String::new()
            };
            s.session = Some(session);
            json_response(&mut stream, 201, format!(
                "{{\"session\":{},\"advice\":{}{},\"mock\":true}}", result, advice_json, hint))
        }
        // §8.3 + §44: input. Ba tầng, mỗi tầng một việc:
        //   1. parse JSON → `input::Event`  (dữ liệu hỏng bị loại)
        //   2. `InputSanitizer` của spec quyết định được phép hay không (§57.1)
        //   3. `inject()` chỉ thực thi — không tự quyết gì
        // Tầng 1+2 chạy trên Linux và có test; chỉ tầng 3 cần Windows.
        ("POST", p) if p.starts_with("/api/sessions/") && p.ends_with("/input") => {
            let sid = p.trim_start_matches("/api/sessions/").trim_end_matches("/input");
            if s.session.as_ref().map(|session| session.id.as_str()) != Some(sid) {
                return json_response(&mut stream, 404, "{\"error\":\"session_not_found\"}".into());
            }
            // §41.4 T2/T3: kiểm **sau** khi biết phiên có thật (để route không
            // lộ "phiên có tồn tại hay không" qua mã 401), **trước** khi chạm
            // vào `SendInput`. Ở loopback cổng này mở; bind LAN thì đóng.
            if deny_if_unauthorised(&mut stream, &s, &req_headers, Some("local")).is_none() { return; }
            let Some(fields) = parse_flat_object(&body) else {
                return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into());
            };
            let Some(event) = input::parse_event(&fields) else {
                return json_response(&mut stream, 422, "{\"error\":\"invalid_input\"}".into());
            };
            let outcome = input::handle(&mut s.input, event, now_ms() as u64, true);
            let sent = input::inject(&outcome.actions);
            // `dropped_moves`/`flood_warnings` là số đo của spec (§57.1), giữ tên.
            let refused = outcome.rejected.map(|r| json_quote(r.code())).unwrap_or_else(|| "null".into());
            let sankeys = s.input.keys_held().len();
            let sanbuttons = s.input.buttons_held();
            let dropped = s.input.dropped_moves;
            let floods = s.input.flood_warnings;
            let releases = s.input.release_all_count;
            let odd = s.input.odd_keyups;
            json_response(&mut stream, 200, format!(
                "{{\"ok\":true,\"actions\":{},\"sent\":{},\"refused\":{},\"stats\":{{\"keysHeld\":{},\"buttonsHeld\":{},\"droppedMoves\":{},\"floodWarnings\":{},\"releaseAllCount\":{},\"oddKeyups\":{}}}}}",
                outcome.actions.len(), sent, refused, sankeys, sanbuttons, dropped, floods, releases, odd))
        }
        // ══════════════════════════════════════════════════════════════════
        // ══════════════════════════════════════════════════════════════════
        // §8.3 **message `move` nhị phân 12 byte** — đường đi chuột thật của
        // Tier 1. `|u16 nx|u16 ny|u8 type|u8 flags|i16 wheel|u16 pad|`
        //
        // Đây là route duy nhất nhận body **không** phải JSON, và đó là lý do
        // `read_request` phải giữ `body_bytes` (bug #17: bản trước decode cả
        // body thành `String`, body nhị phân làm request biến mất).
        //
        // Luật vẫn là của spec: `InputSanitizer` clamp `nx,ny ∈ [0,65535]`,
        // `wheel ∈ [-2400,2400]`, và từ chối khi vượt 120/s (§8.3).
        ("POST", p) if p.starts_with("/api/sessions/") && p.ends_with("/move") => {
            let sid = p.trim_start_matches("/api/sessions/").trim_end_matches("/move");
            if s.session.as_ref().map(|session| session.id.as_str()) != Some(sid) {
                return json_response(&mut stream, 404, "{\"error\":\"session_not_found\"}".into());
            }
            if deny_if_unauthorised(&mut stream, &s, &req_headers, Some("local")).is_none() { return; }
            match input::parse_move(&body_bytes) {
                Some(events) => {
                    // Một gói `move` mang vị trí + nút + wheel (§8.3). Áp **lần
                    // lượt** qua cùng `handle` để mọi luật (clamp, rate limit,
                    // `MAX_KEYS_HELD`) chạy cho từng phần — không có đường tắt
                    // nào cho gói nhị phân.
                    let now = now_ms() as u64;
                    let mut sent = 0usize;
                    let mut refused = "null".to_string();
                    for event in events {
                        let outcome = input::handle(&mut s.input, event, now, true);
                        // §5.4 + §8.3: khi stream đang crop một cửa sổ, toạ độ
                        // client gửi là theo **ảnh** (một phần màn hình). Đổi
                        // về toạ độ virtual desktop trước khi inject — không
                        // đổi thì bấm giữa cửa sổ lại bấm giữa màn hình.
                        let actions = crop::remap_actions(
                            outcome.actions,
                            s.capture_offset,
                            s.live_metrics.width,
                            s.live_metrics.height,
                        );
                        sent += input::inject(&actions) as usize;
                        if let Some(reject) = outcome.rejected {
                            refused = json_quote(reject.code());
                        }
                    }
                    // 12 byte mỗi frame ⇒ body response phải **nhỏ**. Trả đủ
                    // số đo cho UI nhưng không thêm gì thừa.
                    json_response(&mut stream, 200, format!(
                        "{{\"ok\":true,\"sent\":{},\"refused\":{}}}", sent, refused))
                }
                None => json_response(&mut stream, 422, "{\"error\":\"invalid_move\"}".into()),
            }
        }
        // ══════════════════════════════════════════════════════════════════
        // §6.9 — đổi nguồn capture **giữa phiên**. Điểm của cả mục này: KHÔNG
        // đóng phiên, KHÔNG mất peer/DTLS. v2.1 làm ngược lại (5–8 s màn hình
        // đen), nên các route dưới đây là thứ khiến §6.9 có nghĩa.
        //
        // Một nhánh cho cả 7 route của §8.1 (`window`, `mode`, `monitor`,
        // `preset`, `cursor_mode`, `permission`, `share`): chúng khác nhau ở
        // **giá trị được phép**, không khác ở luồng xử lý. Viết 7 nhánh giống
        // nhau là 7 chỗ để quên một bước (clippy cũng chỉ ra: 14 `return`
        // thừa) — và bản đầu của tôi đúng là viết như vậy.
        // ══════════════════════════════════════════════════════════════════
        ("POST", p)
            if p.starts_with("/api/sessions/")
                && ["/window", "/mode", "/monitor", "/preset", "/cursor_mode", "/permission", "/share"]
                    .iter()
                    .any(|suffix| p.ends_with(suffix)) =>
        {
            let tail = p.trim_start_matches("/api/sessions/");
            let (sid, action) = tail.rsplit_once('/').expect("có `/` vì khớp ở trên");
            let what = match action {
                "window" => Switch::Window(&body),
                "mode" => Switch::Mode(&body),
                "monitor" => Switch::Monitor(&body),
                "preset" => Switch::Preset(&body),
                "cursor_mode" => Switch::CursorMode(&body),
                "permission" => Switch::Permission(&body),
                "share" => Switch::Share(&body),
                other => unreachable!("đã lọc ở điều kiện route: {other}"),
            };
            if let Some((status, response)) =
                switch_session(&mut stream, &mut s, sid, &req_headers, what)
            {
                json_response(&mut stream, status, response);
            }
        }

        // §8.1 `{sid}/keyframe` — 204, xin IDR mới. Với MJPEG mỗi frame đã
        // độc lập nên không có gì để làm; route vẫn phải tồn tại vì client
        // (§6.9 bước 5) gọi nó và không được nhận 404.
        ("POST", p) if p.starts_with("/api/sessions/") && p.ends_with("/keyframe") && !p.ends_with("/keyframes") => {
            let sid = p.trim_start_matches("/api/sessions/").trim_end_matches("/keyframe");
            if s.session.as_ref().map(|session| session.id.as_str()) != Some(sid) {
                return response(&mut stream, 404, "application/json", b"{\"error\":\"session_not_found\"}");
            }
            // Đếm để `GET /{sid}` báo được "đã xin keyframe lúc nào" — nếu
            // không, route này là 204 rỗng và không ai biết nó có chạy không.
            s.keyframes += 1;
            response(&mut stream, 204, "application/json", b"")
        }
        // §8.1 `POST /api/sessions/{sid}/takeover` — §6.11.4 / §42.2: thiết bị
        // khác tiếp quản. Bản một-thiết-bị: luôn 409, và nói **vì sao**.
        ("POST", p) if p.starts_with("/api/sessions/") && p.ends_with("/takeover") => {
            json_response(&mut stream, 409,
                "{\"error\":\"takeover_not_supported\",\"detail\":\"bản một-người-dùng chỉ có một thiết bị; 6.11.4 cần nhiều thiết bị cùng user\"}".into());
        }
        // §8.1 `{sid}/audio {enabled}` — §3 "Opus 48k per-app". Bản này chỉ
        // MJPEG nên `enabled` được ghi lại và báo trung thực là chưa có tiếng
        // (§58.3: không giả vờ).
        ("POST", p) if p.starts_with("/api/sessions/") && p.ends_with("/audio") => {
            let sid = p.trim_start_matches("/api/sessions/").trim_end_matches("/audio");
            let Some(fields) = parse_flat_object(&body) else {
                return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into());
            };
            let enabled = fields.get("enabled").map(|v| v == "true").unwrap_or(false);
            let mut applied = false;
            if let Some(session) = s.session.as_mut() {
                if session.id == sid { session.audio = enabled; applied = true; }
            }
            if !applied {
                return json_response(&mut stream, 404, "{\"error\":\"session_not_found\"}".into());
            }
            json_response(&mut stream, 200, format!(
                "{{\"enabled\":{},\"available\":false,\"reason\":\"audio_not_implemented\"}}", enabled))
        }
        // §9.9 — `clipboard` (T2), **chỉ explicit**.
        //
        // Không có route nào ở đây chạy theo lịch. Đó là điểm chính của §9.9:
        // auto-sync hai chiều (a) gây vòng lặp và (b) rò dữ liệu riêng tư của
        // người ngồi máy — họ copy mật khẩu, và nó sang tab browser. Muốn có
        // nội dung thì phải bấm nút, và mỗi lần bấm là một request.
        ("POST", p) if p.starts_with("/api/sessions/") && p.ends_with("/clipboard") => {
            let sid = p.trim_start_matches("/api/sessions/").trim_end_matches("/clipboard");
            let Some(session) = s.session.as_ref().filter(|session| session.id == sid) else {
                return json_response(&mut stream, 404, "{\"error\":\"session_not_found\"}".into());
            };
            let view_only = session.view_only;
            let Some(input) = parse_flat_object(&body) else {
                return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into());
            };
            let text = input.get("text").map(String::as_str);
            let image = input.get("image_b64").map(String::as_str);
            match clipboard::validate(text, image, view_only) {
                Ok(content) => {
                    // `paste_to_remote = true`: ta **mượn** clipboard của máy
                    // người dùng để chuyển dữ liệu vào phiên, nên phải trả lại
                    // sau 300 ms (§9.9) — nếu không, clipboard của họ bị ghi đè
                    // vĩnh viễn bằng nội dung từ xa.
                    let policy = clipboard::restore_policy(true);
                    let restore_ms = match policy {
                        clipboard::RestorePolicy::RestoreAfter(ms) => ms,
                        clipboard::RestorePolicy::Keep => 0,
                    };
                    // Chạy trọn "Paste to remote": lưu clipboard cũ → ghi mới
                    // → `Ctrl+V` → trả lại sau 300 ms. Ba bước phải đi cùng
                    // nhau; gửi `Ctrl+V` một mình là paste **nội dung cũ** của
                    // máy remote vào tài liệu người dùng.
                    let injected = clipboard::paste_to_remote(&content);
                    // `injected == 0` trên Linux (stub) **hoặc** khi không ghi
                    // được clipboard. Hai nguyên nhân khác nhau nhưng cùng hệ
                    // quả với người dùng: chưa có gì được paste. Nói thật.
                    let applied = injected > 0;
                    json_response(&mut stream, 200, format!(
                        "{{\"ok\":true,\"restore_after_ms\":{},\"applied\":{},\"keys\":{}}}",
                        restore_ms, applied, injected))
                }
                Err(error) => {
                    // `ClipboardError` là `Copy`, nên không cần clone.
                    let code = error.code();
                    let status = error.status();
                    json_response(&mut stream, status, format!("{{\"error\":{}}}", json_quote(code)))
                }
            }
        }
        // "Copy from remote" — client đọc clipboard của agent rồi tự
        // `navigator.clipboard.writeText` (nút bấm = gesture, §9.9).
        ("GET", p) if p.starts_with("/api/sessions/") && p.ends_with("/clipboard") => {
            let sid = p.trim_start_matches("/api/sessions/").trim_end_matches("/clipboard");
            if s.session.as_ref().map(|session| session.id.as_str()) != Some(sid) {
                return json_response(&mut stream, 404, "{\"error\":\"session_not_found\"}".into());
            }
            let content = clipboard::read();
            json_response(&mut stream, 200, clipboard::content_json(content.as_ref()))
        }
        // §50.3 — gửi **1 file, một chiều** client → server. §8.1: "chỉ khi bật".
        //
        // Đây là mục **duy nhất** trong spec mà tác giả khuyên "tuỳ bạn", và
        // người dùng đã chọn bật (xem `settings`). Tắt thì route trả 403
        // `upload.disabled`, không phải 404 — route tồn tại, tính năng đang tắt.
        ("POST", "/api/upload") => {
            if deny_if_unauthorised(&mut stream, &s, &req_headers, None).is_none() { return; }
            // §8.1: "**chỉ khi bật**" ⇒ mặc định tắt. Đọc đúng key trong bảng
            // `allowed_value`: bản trước tự đặt `upload-enabled`, key đó không
            // được bảng cho phép nên `PATCH /api/settings` **lặng lẽ bỏ qua**
            // và route luôn 403 — người dùng bật trong UI mà không có gì xảy ra.
            let enabled = s.settings.get("upload").map(|value| value == "on").unwrap_or(false);
            if !enabled {
                return json_response(&mut stream, 403, "{\"error\":\"upload.disabled\"}".into());
            }
            let Some(content_type) = req_headers.get("content-type") else {
                return json_response(&mut stream, 422, "{\"error\":\"upload.malformed\"}".into());
            };
            let Some(boundary) = upload::boundary_of(content_type) else {
                return json_response(&mut stream, 422, "{\"error\":\"upload.malformed\"}".into());
            };
            let parts = match upload::parse_multipart(&body_bytes, &boundary) {
                Ok(parts) => parts,
                Err(error) => {
                    let code = error.code();
                    return json_response(&mut stream, error.status(),
                        format!("{{\"error\":{}}}", json_quote(code)));
                }
            };
            // Phần có `filename` là file; phần khác là field phụ (bỏ qua, đúng
            // như form HTML gửi kèm).
            let Some(part) = parts.into_iter().find(|part| part.filename.is_some()) else {
                return json_response(&mut stream, 422, "{\"error\":\"upload.malformed\"}".into());
            };
            let filename = part.filename.unwrap_or_default();
            match upload::validate(true, &filename, part.body) {
                Ok(file) => {
                    let home = std::env::var_os("USERPROFILE")
                        .or_else(|| std::env::var_os("HOME"))
                        .map(std::path::PathBuf::from)
                        .unwrap_or_else(|| std::path::PathBuf::from("."));
                    let dir = upload::upload_dir(&home);
                    match upload::write(&file, &dir) {
                        Ok((path, size, sha256)) => {
                            // §50.3: **không** tự mở file. Trả đường dẫn để UI
                            // **hiện** cho người dùng xác nhận, không để mở.
                            json_response(&mut stream, 201, upload::upload_json(&path, size, &sha256))
                        }
                        Err(error) => {
                            // Lỗi ghi đĩa là lỗi server, không phải lỗi client —
                            // nhưng vẫn phải nói **lý do**, không chỉ "500".
                            json_response(&mut stream, 500, format!(
                                "{{\"error\":\"upload.write_failed\",\"detail\":{}}}",
                                json_quote(&error.to_string())))
                        }
                    }
                }
                Err(error) => {
                    // Lý do cụ thể cho `blocked_extension`: người dùng cần biết
                    // **đuôi nào** bị chặn, không chỉ "không được". Lấy trước
                    // khi `code`/`status` move `error`.
                    let detail = match &error {
                        upload::UploadError::BlockedExtension(extension) => format!(
                            ",\"extension\":{}", json_quote(extension)),
                        _ => String::new(),
                    };
                    let code = error.code();
                    let status = error.status();
                    json_response(&mut stream, status, format!(
                        "{{\"error\":{}{}}}", json_quote(code), detail))
                }
            }
        }
        // §6.4.7 lớp 3: `sendBeacon` khi đóng tab — không phụ thuộc WS còn sống.
        ("POST", p) if p.starts_with("/api/sessions/") && p.ends_with("/release") => {
            let sid = p.trim_start_matches("/api/sessions/").trim_end_matches("/release");
            if s.session.as_ref().map(|session| session.id.as_str()) != Some(sid) {
                return json_response(&mut stream, 404, "{\"error\":\"session_not_found\"}".into());
            }
            let keys = s.input.release_all(now_ms() as u64);
            let actions: Vec<input::Action> = keys.into_iter().map(|vk| input::Action::Key { down: false, vk }).collect();
            input::inject(&actions);
            json_response(&mut stream, 200, format!("{{\"released\":{}}}", actions.len()))
        }
        ("DELETE", _) if route.starts_with("/api/sessions/") => {
            let id = route.trim_start_matches("/api/sessions/");
            if s.session.as_ref().map(|session| session.id.as_str()) != Some(id) { return json_response(&mut stream, 404, "{\"error\":\"session_not_found\"}".into()); }
            let ended_session = s.session.take();
            let ended = ended_session.as_ref().map(session_json).unwrap_or_else(||"null".into());
            // §50.2: một dòng / phiên. Ghi **sau** khi phiên đã đóng, và
            // không để lỗi ghi đĩa làm hỏng response — lịch sử là phụ.
            if let Some(session) = &ended_session {
                // `session.started_at` là **giây** (`now_seconds`), còn
                // `History` so mốc bằng **mili** (`now_ms`). Lệch 1000× ⇒
                // mọi dòng bị coi là quá 7 ngày và bị `rotate` xoá ngay sau
                // khi ghi: lịch sử **luôn rỗng** mà không báo lỗi gì.
                let record = history::Record {
                    ts: session.started_at.saturating_mul(1_000),
                    sid: session.id.clone(),
                    user: "local".into(),
                    app: session.window_id.clone(),
                    title_hash: history::title_hash(&session.window_id),
                    mode: session.mode.clone(),
                    duration_s: now_seconds().saturating_sub(session.started_at),
                    end_reason: "closed".into(),
                    bytes_out: s.live_metrics.jpeg_bytes,
                };
                if let Err(error) = s.history.append(&record, now_ms() as u64) {
                    eprintln!("history: không ghi được ({error}) — phiên vẫn đóng bình thường");
                }
            }
            json_response(&mut stream, 200, format!("{{\"session\":{},\"stopped\":true,\"mock\":true}}",ended))
        }
        // §8.1 + §50.2: lịch sử, **mới nhất trước**, tối đa 500 dòng, không
        // phân trang. Không có route ghi: client không được tạo lịch sử.
        // §50.1 #2: ghim cửa sổ hay dùng. `GET /api/pins`, `POST`, `DELETE`
        // (§8.1 gộp cả ba vào một dòng).
        ("GET", "/api/pins") => json_response(&mut stream, 200, s.pins.json()),
        ("POST", "/api/pins") => {
            if deny_if_unauthorised(&mut stream, &s, &req_headers, None).is_none() { return; }
            let Some(fields) = parse_flat_object(&body) else {
                return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into());
            };
            let (Some(wid), label) = (fields.get("wid"), fields.get("label")) else {
                return json_response(&mut stream, 422, "{\"error\":\"invalid_wid\"}".into());
            };
            // `label` không bắt buộc: không có thì dùng chính `wid` làm nhãn
            // — bấm "ghim" mà phải gõ tên trước là thêm một bước cản.
            let label = label.cloned().unwrap_or_else(|| wid.clone());
            let wid = wid.clone();
            match s.pins.upsert(&wid, &label, now_ms() as u64) {
                Ok(pin) => json_response(&mut stream, 200, format!(
                    "{{\"wid\":{},\"label\":{}}}", json_quote(&pin.wid), json_quote(&pin.label))),
                Err(error) => json_response(&mut stream, error.status(), format!(
                    "{{\"error\":{}}}", json_quote(error.code()))),
            }
        }
        ("DELETE", "/api/pins") => {
            if deny_if_unauthorised(&mut stream, &s, &req_headers, None).is_none() { return; }
            // `wid` đi trong query string (§8.1 không ghi rõ, nhưng `DELETE`
            // không có body trong HTTP/1.1 là chuyện thường).
            //
            // Phải đọc từ `path`, **không** từ `route`: `route` đã bị tách
            // query ở dòng `let route = path.split('?')...`, nên
            // `query_param(&route, ..)` luôn trả `None` — DELETE nào cũng
            // thành 404 dù ghim có thật. Bug này chỉ lộ ra khi gọi bằng curl;
            // unit test của `Pins` không đi qua HTTP nên không thấy.
            let wid = query_param(&path, "wid").unwrap_or_default();
            match s.pins.remove(&wid) {
                Ok(removed) => json_response(&mut stream, 200, format!(
                    "{{\"removed\":{}}}", json_quote(&removed.wid))),
                Err(error) => json_response(&mut stream, error.status(), format!(
                    "{{\"error\":{}}}", json_quote(error.code()))),
            }
        }
        ("GET", "/api/history") => {
            // §8.1 ghi `?from=&to=`; §50.2 "danh sách + lọc theo ngày".
            // **Không** phân trang ảo hoá: tối đa 500 dòng (§50.2).
            let records: Vec<history::Record> = s
                .history
                .read()
                .into_iter()
                .filter(|record| {
                    let Some(from) = query_param(&path, "from").and_then(|v| v.parse::<u64>().ok()) else {
                        return true;
                    };
                    let to = query_param(&path, "to")
                        .and_then(|v| v.parse::<u64>().ok())
                        .unwrap_or(u64::MAX);
                    record.ts >= from && record.ts <= to
                })
                .collect();
            let items: Vec<String> = records.iter().map(history::Record::to_json).collect();
            json_response(&mut stream, 200, format!(
                "{{\"history\":[{}],\"count\":{}}}", items.join(","), records.len()))
        }
        // §7.1: `/auth.js` cần biết **một** điều trước khi vẽ form: máy này đã
        // có mật khẩu chưa? Route công khai (không có bí mật nào trong câu trả
        // lời — chỉ một boolean), vì form đăng nhập phải hiện được **trước** khi
        // đăng nhập.
        //
        // Không dò bằng cách gọi `/api/login` với mật khẩu giả: mỗi lần tải
        // trang sẽ tính là một lần sai và tự khoá mình sau 5 lần (§41.2 P4).
        ("GET", "/api/auth/state") => {
            let configured = s.auth.auth.is_some();
            json_response(&mut stream, 200, format!(
                "{{\"configured\":{configured},\"user\":{}}}",
                json_quote(if configured { "local" } else { "" })))
        }
        // §7.1 `SETUP ──lưu config──► IDLE`: lần đầu chưa có mật khẩu thì phải
        // đặt được, nếu không server vĩnh viễn không có đường vào.
        ("POST", "/api/setup") => {
            let Some(fields) = parse_flat_object(&body) else {
                return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into());
            };
            let (Some(user), Some(password)) = (fields.get("u"), fields.get("p")) else {
                return json_response(&mut stream, 400, "{\"error\":\"invalid_credentials_shape\"}".into());
            };
            let user = user.clone();
            let password = password.clone();
            match s.auth.setup(&user, &password, now_ms() as u64) {
                auth_wire::SetupOutcome::Created => {
                    json_response(&mut stream, 200, "{\"ok\":true}".into())
                }
                auth_wire::SetupOutcome::AlreadyConfigured => {
                    // 409 chứ không 403: không phải "bạn không có quyền" mà
                    // "trạng thái đã khác" — UI cần hiện màn hình đăng nhập.
                    json_response(&mut stream, 409, "{\"error\":\"already_configured\"}".into())
                }
                auth_wire::SetupOutcome::WeakPassword => json_response(
                    &mut stream,
                    422,
                    // 12 là độ dài tối thiểu của §4373. Không export hằng từ
                    // `spike` chỉ để in ra đây; nếu spec đổi, test
                    // `a_short_password_is_rejected_by_the_spec_policy` bắt.
                    "{\"error\":\"weak_password\",\"minLen\":12}".to_string(),
                ),
            }
        }
        // §8.1 + §57: đăng nhập. Đây là chỗ `security::gate::Auth` (100 test
        // trong `spike`) lần đầu có tác dụng thật.
        ("POST", "/api/login") => {
            let Some(fields) = parse_flat_object(&body) else {
                return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into());
            };
            let (Some(user), Some(password)) = (fields.get("u"), fields.get("p")) else {
                return json_response(&mut stream, 400, "{\"error\":\"invalid_credentials_shape\"}".into());
            };
            match &mut s.auth.auth {
                Some(_) => {}
                None => {
                    // §41.6: chưa đặt mật khẩu ⇒ không có đường đăng nhập nào.
                    // Trả 412 để UI biết cần chạy bước đặt mật khẩu, không
                    // phải hiện "sai mật khẩu" gây hoang mang.
                    return json_response(&mut stream, 412, "{\"error\":\"no_password_set\"}".into());
                }
            }
            let auth = s.auth.auth.as_mut().expect("vừa kiểm ở trên");
            // Mật khẩu để trong `BTreeMap<String,String>` chỉ vì đây là client
            // tối giản; nó không bao giờ được ghi ra đĩa hay log.
            let password = password.clone();
            let user = user.clone();
            let mut entropy = auth_wire::RealEntropy;
            match auth.login("127.0.0.1", &user, &password, "local-device", now_ms() as u64, &mut entropy) {
                Ok(session) => {
                    // Refresh token đi bằng cookie HttpOnly, KHÔNG vào body.
                    let body_out = auth_wire::login_body(&session, 900);
                    let cookie = rd_spike_lib::security::gate::session_cookie(
                        "lantern_refresh", &session.refresh, 7 * 24 * 3600);
                    let headers = [("Set-Cookie", cookie)];
                    json_response_with_headers(&mut stream, 200, &body_out, &headers)
                }
                Err(error) => {
                    let (status, code) = auth_wire::login_error_response(&error);
                    json_response(&mut stream, status, format!("{{\"error\":{}}}", json_quote(code)))
                }
            }
        }
        // §8.1 `/api/refresh`: rotate refresh token, phát access mới.
        //
        // §41.6 "reuse detection": dùng lại refresh cũ ⇒ **cả family** bị thu
        // hồi. Đó là lý do route này không thể chỉ là "phát access mới" — nó
        // là nơi phát hiện bị đánh cắp.
        ("POST", "/api/refresh") => {
            let Some(auth) = s.auth.auth.as_mut() else {
                return json_response(&mut stream, 412, "{\"error\":\"no_password_set\"}".into());
            };
            let Some(refresh_token) = auth_wire::cookie_value(&req_headers, "lantern_refresh") else {
                return json_response(&mut stream, 401, "{\"error\":\"no_refresh_cookie\"}".into());
            };
            let refresh_token = refresh_token.to_string();
            let mut entropy = auth_wire::RealEntropy;
            match auth.refresh_session(&refresh_token, "local-device", now_ms() as u64, &mut entropy) {
                Some(rotated) => {
                    // Cookie được **thay** ở mỗi lần rotate: nếu không, token
                    // cũ vẫn nằm trong trình duyệt và reuse-detection vô nghĩa.
                    let cookie = rd_spike_lib::security::gate::session_cookie(
                        "lantern_refresh", &rotated.refresh, 7 * 24 * 3600);
                    let body_out = format!(
                        "{{\"access\":{},\"expiresIn\":900}}",
                        json_quote(&rotated.access)
                    );
                    let mut extra = vec![("Set-Cookie", cookie)];
                    if rotated.device_mismatch {
                        // §41.6: lệch thiết bị ⇒ **cảnh báo, không chặn**.
                        extra.push(("X-Lantern-Device-Mismatch", "1".to_string()));
                    }
                    json_response_with_headers(&mut stream, 200, &body_out, &extra)
                }
                // `None` = token đã dùng/không tồn tại/hết hạn/hết chuỗi. Tất
                // cả đều 401 và cookie bị xoá: đây là lúc chuỗi đã chết.
                None => {
                    let cleared = rd_spike_lib::security::gate::session_cookie(
                        "lantern_refresh", "", 0);
                    json_response_with_headers(
                        &mut stream, 401,
                        "{\"error\":\"refresh_rejected\"}",
                        &[("Set-Cookie", cleared)],
                    )
                }
            }
        }
        // §8.1: 204, **kill mọi phiên của user** — không chỉ xoá cookie của
        // trình duyệt này. `revoke_all` của spec đặt watermark `revoked_before`
        // nên access token 15 phút cũng chết ngay, không phải chờ hết hạn.
        ("POST", "/api/logout") => {
            // Không có `sub` trong request (204 không trả body, access token có
            // thể đã hết hạn) ⇒ thu hồi theo user **thật** mà server được cấu
            // hình, không phải chuỗi `"local"` viết cứng: nếu ai đặt tài khoản
            // tên khác thì `revoke_all("local")` không thu hồi gì, và nút
            // "đăng xuất mọi nơi" im lặng không làm gì.
            // §0.3.1 #4: tối đa 2 tài khoản, cả hai cùng quyền ⇒ đúng một tên.
            if let Some(auth) = s.auth.auth.as_mut() {
                let user = auth.passwords.user().to_string();
                auth.refresh.revoke_all(&user, now_ms() as u64);
            }
            let cleared = rd_spike_lib::security::gate::session_cookie("lantern_refresh", "", 0);
            json_response_with_headers(
                &mut stream, 204, "",
                &[("Set-Cookie", cleared)],
            )
        }
        ("GET", p) if p.starts_with("/api/") => json_response(&mut stream, 404, "{\"error\":\"not_found\"}".into()),
        _ => json_response(&mut stream, 405, "{\"error\":\"method_not_allowed\"}".into()),
    }
}
fn main() {
    if env::args().any(|arg| arg == "--check") {
        assert!(INDEX.contains("/api/sessions") || JS.contains("/api/sessions"));
        assert!(JS.contains("/api/settings"));
        // Đường "xem máy thật" phải tồn tại trong bản build này, không chỉ trong docs.
        assert!(stream::mjpeg_content_type().contains(stream::BOUNDARY));
        // Không còn GStreamer: đường capture phải nằm **trong** binary này.
        //
        // Gọi **đúng một lần**: mỗi lần gọi là một phiên DXGI thật, và lần thứ
        // hai trong cùng process thường bị `E_ACCESSDENIED` (duplication chỉ cho
        // một phiên) ⇒ `--check` báo đỏ trên máy có GPU, trong khi capture tốt.
        let (available, detail) = probe_live_status();
        println!("capture: available={available} — {detail}");

        // Kiểm encoder **thật** khi khởi động, không chỉ trong `#[cfg(test)]`.
        //
        // Vì sao ở đây: `jpeg::encode` chỉ được gọi từ nhánh `#[cfg(windows)]`
        // của `stream_live`, nên trên Linux nó là dead-code và mọi bảng lượng
        // tử/Huffman bị cảnh báo "never used" — 25 warning che mất cảnh báo
        // thật. Gọi một lần ở `--check` vừa chứng minh encoder chạy được trên
        // mọi nền tảng (không cần GPU), vừa giữ cảnh báo có ích.
        let probe_pixels = vec![0x7Fu8; 16 * 16 * 4];
        let probe_jpeg = jpeg::encode(&probe_pixels, 16, 16, 70);
        assert!(probe_jpeg.starts_with(&[0xFF, 0xD8]), "JPEG phải bắt đầu bằng SOI");
        assert!(probe_jpeg.ends_with(&[0xFF, 0xD9]), "JPEG phải kết thúc bằng EOI");
        println!("jpeg: encoder chạy được, {} byte cho 16×16", probe_jpeg.len());
        // §58.8: in rõ vì sao nút "Xem máy thật" có thể bị xám — nếu không,
        // trên Linux/CI người đọc chỉ thấy "live route ready" và tưởng capture
        // hỏng, trong khi thực tế không có desktop để capture.
        println!(
            "Lantern mock assets embedded; API routes ready; live MJPEG route ready (capture available: {available} — {detail})."
        );
        return;
    }
    let requested_host = env::var("HOST").unwrap_or_else(|_| "127.0.0.1".into());
    let (host, refusal) = allowed_bind_host(&requested_host);
    if let Some(reason) = refusal {
        eprintln!("{reason}");
    }
    let port = env::var("PORT").unwrap_or_else(|_| "0".into());
    let listener = TcpListener::bind(format!("{host}:{port}")).unwrap_or_else(|e| { eprintln!("Cannot listen on {host}:{port}: {e}"); std::process::exit(1); });
    let actual = listener.local_addr().map(|a|a.port()).unwrap_or(0);
    let data_dir = env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(env::temp_dir).join("LanternMock");
    let mut settings = SETTINGS_DEFAULTS.iter().map(|(k,v)|(k.to_string(),v.to_string())).collect::<BTreeMap<_,_>>();
    if let Ok(text) = fs::read_to_string(data_dir.join("settings.json")) { if let Some(saved)=parse_flat_object(&text) { for (k,v) in saved { if settings.contains_key(&k) && allowed_value(&k,&v) { settings.insert(k,v); } } } }
    // Dựng trước khi `data_dir` bị move vào `State` — cùng lý do với `history`.
    let history_log = history::History::new(&data_dir);
    let pins_store = pins::Pins::new(&data_dir);
    let state=Arc::new(Mutex::new(State{settings,session:None,next_id:0,data_dir,live_status:None,live_metrics:LiveMetrics::default(),input:input::InputSanitizer::default(),history:history_log,pins:pins_store,auth:auth_wire::AuthState::default(),policy:guard::Policy::for_bind(&host),loopback_trusted:matches!(guard::Policy::for_bind(&host), guard::Policy::Loopback),keyframes:0,windows:rd_spike_lib::security::window::WindowRegistry::default(),capture_offset:(0,0)}));
    let url = format!("http://127.0.0.1:{actual}");
    println!("Lantern mock is ready. Open {url} in your browser.");
    println!("Xem màn hình thật: {url}/live  — hoặc bấm nút \"Xem máy thật\" (không cần cài gì).");
    println!("Capture + JPEG nằm trong chính exe này; không cần GStreamer, không cần DLL.");
    #[cfg(target_os = "windows")]
    { let _ = std::process::Command::new("cmd").arg("/C").arg("start").arg("").arg(&url).spawn(); }
    for incoming in listener.incoming() { match incoming { Ok(stream)=>{ let shared=Arc::clone(&state); let _=thread::Builder::new().name("lantern-mock-request".into()).spawn(move||handle(stream,shared)); }, Err(e)=>eprintln!("Request error: {e}") } }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// §58.21: UI từng hiện "24 ms" và "2.4 Mbps" như **số đo thật** — nhưng
    /// chúng là hằng số viết cứng trong `app.js`. Người dùng nhìn vào và tin.
    /// Test này khoá lại: không được xuất hiện lại như một con số hiển thị.
    #[test] fn the_ui_never_shows_a_number_it_did_not_measure() {
        // Chỉ xét dòng **code**, bỏ qua comment (nơi nhắc lại lỗi là hợp lệ).
        let code: Vec<&str> = JS
            .lines()
            .filter(|line| !line.trim_start().starts_with("//"))
            .collect();
        let code = code.join("\n");
        for lie in ["24 ms", "2.4 Mbps", "1080p · 30 FPS"] {
            assert!(!code.contains(lie), "UI lại hiện số bịa: {lie}");
        }
        // Và phải có đường lấy số thật.
        assert!(code.contains("/api/live/status"), "UI phải đọc số đo từ server");
        assert!(code.contains("msPerFrame"), "UI phải dùng ms đo được");
        assert!(INDEX.contains("liveMetrics"), "phải có chỗ hiện số đo");
    }

    #[test] fn serves_embedded_frontend_sources() { assert!(INDEX.contains("Lantern")); assert!(CSS.contains(".app-shell")); assert!(JS.contains("/api/sessions")); }
    #[test] fn capture_probe_rejects_untrusted_monitor_index() { assert_eq!(capture_probe(r#"{"monitorIndex":99}"#).0,422); }
    #[test] fn p0_capture_pipeline_shows_real_dxgi_frames() {
        let args = pipeline_args(1, false);
        let command = args.join(" ");
        assert!(command.contains("monitor-index=1 capture-api=dxgi num-buffers=150"));
        assert!(command.contains("d3d11download ! videoconvert ! autovideosink"));
        assert!(!command.contains("fakesink"));
    }
    #[test] fn laptop_p0_encoder_pipeline_uses_qsv_and_bounded_frames() {
        let args = pipeline_args(1, true);
        let command = args.join(" ");
        assert!(command.contains("num-buffers=300"));
        assert!(command.contains("qsvh264enc target-usage=7 bitrate=8000 rate-control=cbr"));
        assert!(command.contains("width=1920,height=1080,framerate=60/1"));
        assert!(command.contains("b-frames=0 low-latency=true"));
        assert!(command.ends_with("fakesink"));
    }
    /// Dựng một server thật trên cổng ngẫu nhiên, trả `(địa chỉ, JoinHandle)`.
    ///
    /// Vì sao phải là HTTP thật chứ không gọi `handle()` trực tiếp: lỗi UTF-8
    /// dưới đây nằm ở **chỗ nối** giữa socket, `read_request` và
    /// `parse_flat_object` — gọi hàm trực tiếp sẽ bỏ qua đúng chỗ hỏng.
    fn spawn_server() -> (std::net::SocketAddr, std::thread::JoinHandle<()>) {
        spawn_server_with(guard::Policy::Loopback)
    }

    /// Như [`spawn_server`] nhưng chọn chính sách — cần để chứng minh cổng
    /// **thật sự đóng** khi bind LAN, không chỉ đóng trong unit test của
    /// `guard`.
    fn spawn_server_with(policy: guard::Policy) -> (std::net::SocketAddr, std::thread::JoinHandle<()>) {
        use std::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");
        let handle = std::thread::spawn(move || {
            // Thư mục riêng cho mỗi lần `spawn_server`: dùng chung
            // `temp_dir()` thì các test thấy `history.jsonl` của nhau và
            // `count` không bao giờ đúng. Lỗi của test, không phải của code —
            // nhưng nếu không sửa thì test này test nhầm thứ.
            let data_dir = std::env::temp_dir().join(format!(
                "lantern-test-{}-{:?}",
                std::process::id(),
                std::thread::current().id()
            ));
            let _ = std::fs::remove_dir_all(&data_dir);
            let state = Arc::new(Mutex::new(State {
                settings: BTreeMap::new(),
                session: None,
                next_id: 0,
                data_dir: data_dir.clone(),
                live_status: None,
                live_metrics: LiveMetrics::default(),
                input: input::InputSanitizer::default(),
                auth: auth_wire::AuthState::default(),
                policy,
                loopback_trusted: matches!(policy, guard::Policy::Loopback),
                keyframes: 0,
                history: history::History::new(&data_dir),
                pins: pins::Pins::new(&data_dir),
                windows: rd_spike_lib::security::window::WindowRegistry::default(),
                capture_offset: (0, 0),
            }));
            // `take(32)`: luồng đăng nhập đầy đủ (§8.1) cần 8 request **chỉ
            // riêng** cho setup/login/refresh/logout; `take(8)` khiến test
            // chết ở `ConnectionRefused` chứ không phải ở logic — một kiểu
            // hỏng rất dễ đọc sai.
            for stream in listener.incoming().take(32).flatten() {
                handle(stream, Arc::clone(&state));
            }
        });
        (addr, handle)
    }

    /// Gửi một request HTTP thô, trả toàn bộ response (header + body).
    fn http(addr: std::net::SocketAddr, method: &str, path: &str, body: &str) -> String {
        http_with(addr, method, path, body, &[])
    }

    /// Như [`http`] nhưng gửi **body nhị phân** — cần cho §8.3.
    fn http_bytes(addr: std::net::SocketAddr, method: &str, path: &str, body: &[u8]) -> String {
        http_bytes_typed(addr, method, path, body, "application/octet-stream")
    }

    /// Như [`http_bytes`] nhưng đặt `Content-Type` — bắt buộc cho multipart
    /// (§50.3), vì boundary nằm **trong** header đó; thiếu nó thì server không
    /// thể tách phần file và mọi upload sẽ là `upload.malformed`.
    fn http_bytes_typed(
        addr: std::net::SocketAddr,
        method: &str,
        path: &str,
        body: &[u8],
        content_type: &str,
    ) -> String {
        use std::io::Write;
        let mut stream = TcpStream::connect(addr).expect("connect");
        let head = format!(
            "{method} {path} HTTP/1.1\r\nHost: test\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            body.len()
        );
        stream.write_all(head.as_bytes()).expect("write head");
        stream.write_all(body).expect("write body");
        let mut out = String::new();
        let _ = stream.read_to_string(&mut out);
        out
    }

    // # Lỗ hổng thật: đặt mật khẩu xong app vẫn mở
    //
    // Phát hiện bằng curl, không phải bằng đọc code: `setup` → 200, rồi
    // `GET /api/windows` **không cookie** → 200. Người dùng đặt mật khẩu, tưởng
    // đã khoá máy, và bất kỳ process nào trên máy cũng đọc được danh sách cửa
    // sổ + tiêu đề tài liệu đang mở. Tệ hơn: `/api/live.mjpg` cho xem **màn
    // hình** mà không cần đăng nhập.
    //
    // Ba nguyên nhân độc lập, mỗi cái đủ để mở toang:
    //  1. `Policy::Loopback` miễn token **vĩnh viễn** (tính một lần lúc khởi
    //     động, không biết về việc đặt mật khẩu sau đó).
    //  2. `/api/windows` và `/api/live.mjpg` **không gọi** `deny_if_unauthorised`.
    //  3. Route không gắn phiên truyền `sid_owner = "*"` ⇒ mọi token bị
    //     `wrong_subject` ⇒ bật mật khẩu lên là app khoá cứng.
    //
    // Test này khoá cả ba: trước khi đặt mật khẩu thì mở (đường dùng bình
    // thường), sau khi đặt thì **đóng**, và token hợp lệ thì **mở lại được**
    // (nếu thiếu vế cuối, "bảo mật" chỉ là app hỏng).
    #[test]
    fn setting_a_password_actually_locks_the_app_and_a_token_unlocks_it() {
        let (addr, handle) = spawn_server_with(guard::Policy::Loopback);
        let password = "mat-khau-rat-dai-2026";

        // Trước khi có mật khẩu: loopback được dùng bình thường. Đây là đường
        // của người dùng lần đầu mở app — nếu nó đòi token thì không ai vào được.
        let before = http(addr, "GET", "/api/windows", "");
        assert!(before.starts_with("HTTP/1.1 200"), "lần đầu phải mở: {before}");

        let setup = http(addr, "POST", "/api/setup",
            &format!(r#"{{"u":"local","p":"{password}"}}"#));
        assert!(setup.starts_with("HTTP/1.1 200"), "setup: {setup}");

        // Vế 1: danh sách cửa sổ phải **đóng**.
        let locked = http(addr, "GET", "/api/windows", "");
        assert!(
            locked.starts_with("HTTP/1.1 401"),
            "đã có mật khẩu mà vẫn đọc được danh sách cửa sổ: {locked}"
        );
        // Vế 2: xem màn hình phải **đóng**. Đây là vế quan trọng nhất — nó là
        // toàn bộ mục đích của app.
        let hidden = http(addr, "GET", "/api/live.mjpg", "");
        assert!(
            hidden.starts_with("HTTP/1.1 401"),
            "đã có mật khẩu mà vẫn xem được màn hình: {hidden}"
        );

        // Vế 3: token hợp lệ phải mở lại được. Không có vế này thì "bảo mật"
        // chỉ là app hỏng — đúng trạng thái trước khi sửa `sid_owner`.
        let login = http(addr, "POST", "/api/login",
            &format!(r#"{{"u":"local","p":"{password}"}}"#));
        assert!(login.starts_with("HTTP/1.1 200"), "login: {login}");
        let body = login.split_once("\r\n\r\n").map(|(_, b)| b).unwrap_or("");
        let access = body
            .split_once("\"access\":\"")
            .and_then(|(_, rest)| rest.split_once('"'))
            .map(|(token, _)| token.to_string())
            .unwrap_or_else(|| panic!("không thấy access trong: {body}"));
        let bearer = format!("Bearer {access}");
        let opened = http_with(addr, "GET", "/api/windows", "",
            &[("authorization", bearer.as_str())]);
        assert!(
            opened.starts_with("HTTP/1.1 200"),
            "token hợp lệ phải mở được danh sách cửa sổ (nếu 401 wrong_subject thì \
             route không gắn phiên đang bị kiểm sub sai): {opened}"
        );
        drop(handle);
    }

    /// Như [`http`] nhưng gửi thêm header — cần cho `Cookie`, vì refresh token
    /// (§41.6) chỉ đi bằng cookie chứ không nằm trong body.
    fn http_with(
        addr: std::net::SocketAddr,
        method: &str,
        path: &str,
        body: &str,
        extra: &[(&str, &str)],
    ) -> String {
        use std::io::Write;
        let mut stream = TcpStream::connect(addr).expect("connect");
        let mut head = format!(
            "{method} {path} HTTP/1.1\r\nHost: test\r\nContent-Length: {}\r\nConnection: close\r\n",
            body.len()
        );
        for (name, value) in extra {
            head.push_str(&format!("{name}: {value}\r\n"));
        }
        head.push_str("\r\n");
        let request = format!("{head}{body}");
        stream.write_all(request.as_bytes()).expect("write");
        let mut out = String::new();
        stream.read_to_string(&mut out).expect("read");
        out
    }

    /// Lấy giá trị cookie từ response (dòng `Set-Cookie:`).
    fn set_cookie(response: &str, name: &str) -> Option<String> {
        for line in response.lines() {
            let line = line.trim();
            if let Some(rest) = line.strip_prefix("Set-Cookie: ") {
                if let Some(value) = rest.strip_prefix(&format!("{name}=")) {
                    return Some(value.split(';').next()?.to_string());
                }
            }
        }
        None
    }

    /// §8.1 + §7.1 + §41.6, chạy qua **socket thật**.
    ///
    /// # Vì sao test này đi qua HTTP chứ không gọi `AuthState` trực tiếp
    ///
    /// `auth_wire` đã có 9 unit test cho `Auth`, và `spike` có 100 test cho
    /// luật. Nhưng cả hai đều **không** chứng minh nối được: bản trước
    /// `read_request` vứt toàn bộ header, nên refresh token không có đường nào
    /// tới server — và không unit test nào thấy, vì không có unit test nào đi
    /// qua `read_request`.
    ///
    /// Bài học đã trả giá ở `history` (ts tính bằng giây, rotate so bằng ms):
    /// **unit test xanh không có nghĩa là tính năng chạy.** Test này là bằng
    /// chứng cho chuỗi setup → login → refresh → logout.
    #[test] fn the_whole_login_chain_works_over_real_http() {
        let (addr, server) = spawn_server();

        // §7.1: chưa SETUP thì chưa có đường vào.
        let early = http(addr, "POST", "/api/login", r#"{"u":"local","p":"mat-khau-rat-dai-2026"}"#);
        assert!(early.starts_with("HTTP/1.1 412"), "chưa đặt mật khẩu ⇒ 412: {early}");

        // §4373: 12 ký tự tối thiểu, danh sách phổ biến bị chặn.
        let weak = http(addr, "POST", "/api/setup", r#"{"u":"local","p":"abc"}"#);
        assert!(weak.starts_with("HTTP/1.1 422"), "mật khẩu yếu ⇒ 422: {weak}");

        let setup = http(addr, "POST", "/api/setup", r#"{"u":"local","p":"mat-khau-rat-dai-2026"}"#);
        assert!(setup.contains("\"ok\":true"), "setup: {setup}");

        // Không cho đặt lại: nếu cho, ai mở được URL cũng chiếm máy được.
        let again = http(addr, "POST", "/api/setup", r#"{"u":"local","p":"mat-khau-khac-2026"}"#);
        assert!(again.starts_with("HTTP/1.1 409"), "setup lần 2 ⇒ 409: {again}");

        let bad = http(addr, "POST", "/api/login", r#"{"u":"local","p":"sai-mat-khau"}"#);
        assert!(bad.starts_with("HTTP/1.1 401"), "sai mật khẩu ⇒ 401: {bad}");

        let login = http_with(addr, "POST", "/api/login",
            r#"{"u":"local","p":"mat-khau-rat-dai-2026"}"#, &[]);
        assert!(login.starts_with("HTTP/1.1 200"), "login: {login}");
        // §41.6: refresh **chỉ** trong cookie, không trong body.
        assert!(!login.lines().last().unwrap_or("").contains("rt."), "body không được có refresh token");
        let first = set_cookie(&login, "lantern_refresh").expect("phải có Set-Cookie");
        assert!(login.contains("HttpOnly"), "cookie phải HttpOnly: {login}");

        // §8.1 `/api/refresh`: rotate ⇒ cookie mới khác cookie cũ.
        let refreshed = http_with(addr, "POST", "/api/refresh", "",
            &[("Cookie", &format!("lantern_refresh={first}"))]);
        assert!(refreshed.starts_with("HTTP/1.1 200"), "refresh: {refreshed}");
        let second = set_cookie(&refreshed, "lantern_refresh").expect("refresh phải phát cookie mới");
        assert_ne!(first, second, "rotate phải đổi token, không phát lại cái cũ");

        // §41.6 reuse detection: dùng lại cái **cũ** ⇒ chết cả family.
        let reused = http_with(addr, "POST", "/api/refresh", "",
            &[("Cookie", &format!("lantern_refresh={first}"))]);
        assert!(reused.starts_with("HTTP/1.1 401"), "dùng lại refresh cũ phải bị từ chối: {reused}");
        assert!(!reused.contains("Internal Server Error"), "401 phải có tên đúng: {reused}");

        // Mã 401 không được in thành "Internal Server Error" (bug #15).
        let after = http_with(addr, "POST", "/api/refresh", "",
            &[("Cookie", &format!("lantern_refresh={second}"))]);
        assert!(after.starts_with("HTTP/1.1 401"), "family đã bị thu hồi: {after}");

        drop(server);
    }

    /// §8.3 **message `move` 12 byte nhị phân**, qua socket thật.
    ///
    /// # Bug #17 mà test này tồn tại để bắt
    ///
    /// `read_request` từng làm `String::from_utf8(body).ok()?` — body nhị phân
    /// **không** hợp lệ UTF-8 (gần như chắc chắn: byte 0 là nửa thấp của `nx`,
    /// byte 1 là nửa cao) làm cả request biến mất, không response nào. Đó là lý
    /// do §8.3 "không chạy" dù server đã có `SendInput`.
    ///
    /// `sent` là **0** trên Linux (stub của `inject`); trên Windows nó là số
    /// sự kiện `SendInput` thật. Test này khoá phần **giải mã + quyền**, không
    /// khoá phần Windows.
    #[test] fn a_binary_move_packet_survives_the_http_layer() {
        let (addr, server) = spawn_server();
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        let sid = created.split("\"id\":\"").nth(1).and_then(|r| r.split('"').next())
            .expect("sid").to_string();

        // §8.3: 10 byte layout + 2 pad (xem `input::parse_move` về mâu thuẫn
        // "12 B" vs layout 10 B trong spec).
        let packet = |nx: u16, ny: u16, kind: u8, flags: u8, wheel: i16| {
            let mut bytes = Vec::new();
            bytes.extend_from_slice(&nx.to_le_bytes());
            bytes.extend_from_slice(&ny.to_le_bytes());
            bytes.push(kind);
            bytes.push(flags);
            bytes.extend_from_slice(&wheel.to_le_bytes());
            bytes.extend_from_slice(&[0, 0, 0, 0]);
            bytes
        };

        let path = format!("/api/sessions/{sid}/move");
        // Byte 0xFF ở đây là byte **không hợp lệ UTF-8** đứng một mình — đúng
        // thứ làm body hỏng nếu server decode cả body thành `String`.
        let moved = http_bytes(addr, "POST", &path, &packet(0xFF, 0x00FF, 1, 0, 0));
        assert!(moved.starts_with("HTTP/1.1 200"), "move nhị phân phải qua được: {moved}");
        assert!(moved.contains(r#""ok":true"#), "{moved}");

        // Cả chuỗi click: down rồi up, mỗi gói nêu **nút của nó** (§8.3).
        for kind in [3u8, 4u8] {
            let out = http_bytes(addr, "POST", &path, &packet(1000, 1000, kind, 1, 0));
            assert!(out.starts_with("HTTP/1.1 200"), "kind {kind}: {out}");
        }

        // Gói hỏng phải là 422 cụ thể, không im lặng bỏ qua và không 500.
        assert!(http_bytes(addr, "POST", &path, &packet(1, 1, 6, 1, 0)).starts_with("HTTP/1.1 422"),
            "touch chưa có ⇒ 422");
        assert!(http_bytes(addr, "POST", &path, &[0u8; 11]).starts_with("HTTP/1.1 422"),
            "11 byte ⇒ 422");
        assert!(http_bytes(addr, "POST", &path, &packet(1, 1, 3, 0, 0)).starts_with("HTTP/1.1 422"),
            "down không nêu nút ⇒ 422");
        drop(server);
    }

    /// §50.1 #2 + §8.1: `GET/POST/DELETE /api/pins` chạy qua HTTP.
    ///
    /// # Bug thật mà test này tồn tại để bắt
    ///
    /// `/api/pins?wid=browser` — `route` **đã** bị tách query ở
    /// `let route = path.split('?')...`, nên `query_param(&route, ..)` luôn
    /// trả `None` và **mọi** `DELETE` thành 404 dù ghim có thật. Unit test của
    /// `Pins` không thấy vì nó không đi qua HTTP. Chỉ `curl` thấy.
    #[test] fn pin_routes_work_over_http_including_delete_with_a_query_string() {
        let (addr, server) = spawn_server();
        assert!(http(addr, "GET", "/api/pins", "").contains(r#""pins":[]"#), "ban đầu phải rỗng");

        let added = http(addr, "POST", "/api/pins", r#"{"wid":"browser","label":"Chrome ở nhà"}"#);
        assert!(added.contains(r#""label":"Chrome ở nhà""#), "thêm ghim: {added}");

        // Không có nhãn ⇒ lấy `wid` làm nhãn (không bắt người dùng gõ thêm).
        let bare = http(addr, "POST", "/api/pins", r#"{"wid":"desktop"}"#);
        assert!(bare.contains(r#""label":"desktop""#), "nhãn mặc định: {bare}");

        let list = http(addr, "GET", "/api/pins", "");
        assert_eq!(list.matches(r#""wid":"#).count(), 2, "phải có 2 ghim: {list}");
        // Mới ghim lên trước (§50.1 #2: "3 bấm → 1 bấm", danh sách phải ngắn
        // và mới nhất ở đầu).
        assert!(list.find("desktop").unwrap() < list.find("browser").unwrap(),
            "mới ghim phải đứng trước: {list}");

        // §50.1 #2: nhãn là của người dùng, có dấu tiếng Việt — phải giữ nguyên.
        let removed = http(addr, "DELETE", "/api/pins?wid=browser", "");
        assert!(removed.contains(r#""removed":"browser""#),
            "DELETE kèm query string phải tìm được ghim: {removed}");
        let again = http(addr, "DELETE", "/api/pins?wid=browser", "");
        assert!(again.contains("pin_not_found"), "xoá lần 2 ⇒ 404: {again}");
        drop(server);
    }

    /// §8.1 `/api/logout` phải thu hồi theo **tên tài khoản thật**.
    ///
    /// Bản trước dùng `for user in ["local"]` — chạy đúng với mật khẩu mặc
    /// định, và **im lặng không làm gì** nếu ai đặt tài khoản tên khác. Clippy
    /// chỉ bắt được "for loop over a single element" (chuyện hình thức); test
    /// này bắt được chuyện thật.
    #[test] fn logout_revokes_the_configured_user_not_a_hardcoded_name() {
        let (addr, server) = spawn_server();
        // Tài khoản tên KHÁC "local".
        let setup = http(addr, "POST", "/api/setup", r#"{"u":"ba-toi","p":"mat-khau-rat-dai-2026"}"#);
        assert!(setup.contains(r#""ok":true"#), "setup với tên khác: {setup}");
        let login = http(addr, "POST", "/api/login", r#"{"u":"ba-toi","p":"mat-khau-rat-dai-2026"}"#);
        assert!(login.starts_with("HTTP/1.1 200"), "login: {login}");
        let token = set_cookie(&login, "lantern_refresh").expect("cookie");
        let cookie = format!("lantern_refresh={token}");

        let out = http_with(addr, "POST", "/api/logout", "", &[("Cookie", &cookie)]);
        assert!(out.starts_with("HTTP/1.1 204"), "logout: {out}");

        let after = http_with(addr, "POST", "/api/refresh", "", &[("Cookie", &cookie)]);
        assert!(after.starts_with("HTTP/1.1 401"),
            "logout phải giết refresh của user thật, không chỉ của \"local\": {after}");
        drop(server);
    }

    /// §6.9 + §6.10.1 + §8.1: 9 route "đổi thứ gì đó trong phiên" chạy được.
    ///
    /// Đi qua socket vì lý do quen thuộc: `session_state` đã có 9 unit test cho
    /// **luật** (bảng preset, thứ tự switch), nhưng luật đúng mà route không
    /// gọi thì tính năng vẫn chết. Chưa có test nào từng gọi các route này —
    /// chúng vừa mới tồn tại.
    #[test] fn every_in_session_switch_route_of_the_spec_works() {
        let (addr, server) = spawn_server();
        let created = http(addr, "POST", "/api/sessions",
            r#"{"mode":"vnc","windowId":"desktop"}"#);
        let sid = created.split("\"id\":\"").nth(1).and_then(|r| r.split('"').next())
            .expect("sid").to_string();
        let at = |route: &str| format!("/api/sessions/{sid}/{route}");

        // §6.9 window / mode / monitor. Đổi nguồn capture ⇒ keyframe mới.
        // `desktop` là cửa sổ đặc biệt (§5.3 VNC — stream cả màn hình), không
        // cần snapshot vì nó không phải hwnd nào. Một `wid` cụ thể phải có
        // snapshot hợp lệ — và trên Linux `EnumWindows` trả rỗng (§58.3),
        // nên test này dùng `desktop` thay vì bịa `"notes"` như bản trước
        // (bản trước qua được chỉ vì code cũng bịa danh sách).
        let window = http(addr, "POST", &at("window"), r#"{"windowId":"desktop"}"#);
        assert!(window.starts_with("HTTP/1.1 200"), "window: {window}");
        assert!(window.contains(r#""windowId":"desktop""#), "phải áp dụng: {window}");

        let mode = http(addr, "POST", &at("mode"), r#"{"mode":"hvnc"}"#);
        assert!(mode.starts_with("HTTP/1.1 200"), "mode: {mode}");
        assert!(mode.contains(r#""mode":"hvnc""#), "mode phải đổi: {mode}");

        let monitor = http(addr, "POST", &at("monitor"), r#"{"index":2}"#);
        assert!(monitor.starts_with("HTTP/1.1 200"), "monitor: {monitor}");
        assert!(monitor.contains(r#""monitor":2"#), "monitor phải đổi: {monitor}");

        // §6.10.1: đổi preset trả đúng số của bảng, và **không** xin keyframe.
        let before = http(addr, "GET", &format!("/api/sessions/{sid}"), "");
        let kf_before = before.split(r#""keyframes":"#).nth(1)
            .and_then(|r| r.trim_start_matches(' ').split(|c: char| !c.is_ascii_digit()).next())
            .and_then(|n| n.parse::<u64>().ok()).unwrap_or(0);
        let preset = http(addr, "POST", &at("preset"), r#"{"preset":"low"}"#);
        assert!(preset.contains(r#""fps":30"#), "low = 30 fps: {preset}");
        assert!(preset.contains(r#""mbps":1.5"#), "low = 1.5 Mbps: {preset}");
        let after = http(addr, "GET", &format!("/api/sessions/{sid}"), "");
        let kf_after = after.split(r#""keyframes":"#).nth(1)
            .and_then(|r| r.trim_start_matches(' ').split(|c: char| !c.is_ascii_digit()).next())
            .and_then(|n| n.parse::<u64>().ok()).unwrap_or(0);
        assert_eq!(kf_before, kf_after,
            "§6.10.1: đổi preset KHÔNG đổi nguồn capture ⇒ không xin keyframe ({kf_before}→{kf_after})");

        // §8.1 cursor_mode / permission / share / keyframe / takeover / audio.
        let cursor = http(addr, "POST", &at("cursor_mode"), r#"{"mode":"remote"}"#);
        assert!(cursor.contains(r#""cursorMode":"remote""#), "cursor_mode: {cursor}");

        let permission = http(addr, "POST", &at("permission"), r#"{"view_only":true}"#);
        assert!(permission.contains(r#""viewOnly":true"#), "permission: {permission}");

        let share = http(addr, "POST", &at("share"), r#"{"ttl_min":30}"#);
        assert!(share.contains(r#""ttlMin":30"#), "share: {share}");
        assert!(share.contains(r#""viewOnly":true"#), "§21.6: link chia sẻ là view-only: {share}");

        let keyframe = http(addr, "POST", &at("keyframe"), "");
        assert!(keyframe.starts_with("HTTP/1.1 204"), "keyframe ⇒ 204: {keyframe}");

        let takeover = http(addr, "POST", &at("takeover"), "");
        assert!(takeover.starts_with("HTTP/1.1 409"), "takeover chưa hỗ trợ ⇒ 409: {takeover}");

        let audio = http(addr, "POST", &at("audio"), r#"{"enabled":false}"#);
        assert!(audio.contains(r#""enabled":false"#), "audio: {audio}");
        // §58.3: không giả vờ có tiếng khi chưa có.
        assert!(audio.contains(r#""available":false"#), "phải nói thật là chưa có tiếng: {audio}");
        drop(server);
    }

    /// §6.9 ghi rõ: "**Cho phép** (v2.1 cấm)" đổi HVNC↔VNC giữa phiên.
    /// v2.1 phải đóng rồi mở phiên mới (5–8 s màn hình đen); §6.9 giữ nguyên
    /// `sid`. Test này khoá rằng `sid` **không** đổi — nếu đổi thì toàn bộ điểm
    /// của §6.9 mất.
    #[test] fn switching_mode_keeps_the_same_session_id() {
        let (addr, server) = spawn_server();
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        let sid = created.split("\"id\":\"").nth(1).and_then(|r| r.split('"').next())
            .expect("sid").to_string();
        let switched = http(addr, "POST", &format!("/api/sessions/{sid}/mode"), r#"{"mode":"hvnc"}"#);
        assert!(switched.contains(&format!(r#""id":"{sid}""#)),
            "§6.9: cùng một phiên, không tạo phiên mới: {switched}");
        // Và phiên cũ vẫn là phiên duy nhất.
        let mine = http(addr, "GET", "/api/sessions/mine", "");
        assert_eq!(mine.matches(r#""id":"#).count(), 1, "chỉ được có 1 phiên: {mine}");
        drop(server);
    }

    /// §41.3 #3: `wid` phải nằm trong danh sách agent đã trả — client không
    /// bao giờ quyết định hwnd. Đây là lỗ hổng leo thang quyền **thật** mà
    /// spec gọi tên, nên nó cần test ở tầng route, không chỉ ở `guard`.
    #[test] fn a_client_cannot_pick_an_arbitrary_window_id() {
        // §41.3 #3: client **không bao giờ** cầm hwnd. Hai kiểu tấn công khác
        // nhau, và spec cho hai mã khác nhau:
        //
        // * gửi hwnd thô (`"0x000A0B0C"`, số) ⇒ 400 `window.hwnd_not_accepted`
        //   — "dấu hiệu của một client không phải của ta", từ chối thẳng.
        // * gửi `wid` mà không có/không đúng snapshot ⇒ 403 `window.unknown`.
        let (addr, server) = spawn_server();
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        let sid = created.split("\"id\":\"").nth(1).and_then(|r| r.split('"').next())
            .expect("sid").to_string();
        // `HwndNotAccepted` = **định dạng** sai (`0x…` có chữ `x`, dấu `-`,
        // hoặc >32 ký tự). `"123456"` **không** thuộc nhóm này: nó là chuỗi
        // hex hợp lệ, nên rơi vào `window.unknown` (403) — đó mới là phân biệt
        // đúng của spec, và test này từng viết sai chỗ đó.
        for malformed in [
            r#"{"windowId":"0x000A0B0C"}"#,
            r#"{"windowId":"-140000"}"#,
            r#"{"windowId":"   "}"#,
            r#"{"windowId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#,
        ] {
            let out = http(addr, "POST", &format!("/api/sessions/{sid}/window"), malformed);
            assert!(out.starts_with("HTTP/1.1 400"), "định dạng hwnd ⇒ 400 ({malformed}): {out}");
            assert!(out.contains("hwnd_not_accepted"), "phải nói rõ vì sao: {out}");
        }
        // Chuỗi hex hợp lệ nhưng không thuộc snapshot nào ⇒ 403.
        let hex_but_unknown = http(addr, "POST", &format!("/api/sessions/{sid}/window"),
            r#"{"windowId":"123456","snapshotId":"ws1x"}"#);
        assert!(hex_but_unknown.starts_with("HTTP/1.1 403"),
            "hex hợp lệ nhưng lạ ⇒ 403: {hex_but_unknown}");
        // `wid` giống id hex nhưng không có trong snapshot nào.
        let guessed = http(addr, "POST", &format!("/api/sessions/{sid}/window"),
            r#"{"windowId":"00000000deadbeef","snapshotId":"ws1abc"}"#);
        assert!(guessed.starts_with("HTTP/1.1 403"), "wid bịa ⇒ 403: {guessed}");
        assert!(guessed.contains("window.unknown"), "{guessed}");
        drop(server);
    }

    /// §41.3 #3 / §41.4 T1 — **lỗ hổng leo thang quyền thật** mà spec gọi tên.
    ///
    /// Kịch bản: người dùng mở app, `GET /api/windows` trả 5 cửa sổ. Client bịa
    /// ra một `wid` khác (cửa sổ ngân hàng họ không cho xem) ⇒ nếu agent không
    /// kiểm, nó stream cửa sổ đó. Đây không phải tấn công lý thuyết: client
    /// **không được tin** (§41.3), và một extension độc (§41.2 P5) sửa được
    /// request.
    /// §6.10.2 — *"Kiểm tra băng thông trước khi bắt đầu"*.
    ///
    /// Spec cho hai cách: `POST /api/sessions` trả `recommended_preset`, **hoặc**
    /// hiện ước lượng "~8 Mbps" trước khi bấm Start. Bản này làm cả hai; test
    /// này khoá cả hai đường, vì một route tồn tại mà không ai gọi thì cũng như
    /// không có.
    /// §9.9 — clipboard **chỉ explicit**, và cap phải chặn ở **server**.
    ///
    /// Client là bên không được tin (§41.3): cap ở `web/app.js` chỉ là tiện cho
    /// người dùng, không phải hàng rào. 100 MB clipboard là cách làm treo agent.
    /// §50.3 — gửi 1 file, **một chiều**, "chỉ khi bật".
    ///
    /// Test này dựng multipart **thật** (không gọi hàm nội bộ), vì bug đã gặp
    /// là route trả 403 dù PATCH cài đặt trả 200 — chỉ HTTP mới thấy.
    #[test] fn upload_is_off_by_default_then_writes_one_file_and_refuses_exe() {
        let (addr, server) = spawn_server();
        let boundary = "BNDtestbnd";
        let multipart = |filename: &str, content: &[u8]| {
            let mut body = Vec::new();
            body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
            body.extend_from_slice(format!(
                "Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n").as_bytes());
            body.extend_from_slice(b"Content-Type: application/octet-stream\r\n\r\n");
            body.extend_from_slice(content);
            body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
            body
        };

        // §8.1: "**chỉ khi bật**" ⇒ mặc định 403, không phải 404 (route có thật).
        let off = http_bytes_typed(addr, "POST", "/api/upload", &multipart("a.txt", b"hello"),
            &format!("multipart/form-data; boundary={boundary}"));
        assert!(off.starts_with("HTTP/1.1 403"), "{off}");
        assert!(off.contains("upload.disabled"), "{off}");

        // Bật qua PATCH — và **kiểm** là nó thật sự bật. Bug đã gặp: PATCH trả
        // 200 nhưng chỉ nhận key đã có trong map, nên setting mới không bao giờ
        // có tác dụng.
        let patched = http(addr, "PATCH", "/api/settings", r#"{"upload":"on"}"#);
        assert!(patched.contains(r#""upload":"on""#), "PATCH phải áp dụng: {patched}");

        let on = http_bytes_typed(addr, "POST", "/api/upload", &multipart("a.txt", b"hello"),
            &format!("multipart/form-data; boundary={boundary}"));
        assert!(on.starts_with("HTTP/1.1 201"), "{on}");
        assert!(on.contains(r#""sha256":"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824""#), "{on}");
        // giá trị người dùng không kiểm được, tệ hơn không trả gì.
        assert!(on.contains(r#""sha256":"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824""#), "{on}");
        assert!(on.contains(r#""size":5"#), "{on}");
        assert!(on.contains("Downloads/RD"), "§50.3 ghi `Downloads\\RD\\`: {on}");
        // §50.3: **không** tự mở.
        assert!(!on.contains("launch"), "{on}");

        // §50.3 chặn `exe/ps1/bat/scr/lnk` — và nói **đuôi nào**.
        let blocked = http_bytes_typed(addr, "POST", "/api/upload", &multipart("payload.exe", b"MZ"),
            &format!("multipart/form-data; boundary={boundary}"));
        assert!(blocked.starts_with("HTTP/1.1 422"), "{blocked}");
        assert!(blocked.contains("upload.blocked_extension"), "{blocked}");
        assert!(blocked.contains(r#""extension":"exe""#), "{blocked}");

        // Tên chứa đường dẫn không được ghi ra ngoài thư mục đích.
        let traversal = http_bytes_typed(addr, "POST", "/api/upload",
            &multipart(r"..\..\thoat.txt", b"x"),
            &format!("multipart/form-data; boundary={boundary}"));
        assert!(traversal.starts_with("HTTP/1.1 201"), "{traversal}");
        assert!(!traversal.contains(".."), "không được có `..` trong đường dẫn: {traversal}");
        drop(server);
    }

    #[test] fn clipboard_is_explicit_checked_at_the_server_and_capped() {
        let (addr, server) = spawn_server();
        // Tạo phiên **trước**, rồi mới có `sid` để gọi route. Bản trước đọc
        // `current` trước khi tạo, nên `sid` là phiên cũ (hoặc không có) và
        // route trả 404 — đúng hành vi, sai thứ tự test.
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        let current = http(addr, "GET", "/api/sessions/current", "");
        let sid = created
            .split("\"id\":\"").nth(1)
            .or_else(|| current.split("\"id\":\"").nth(1))
            .and_then(|r| r.split('"').next())
            .expect("phải có phiên để test clipboard")
            .to_string();
        let route = format!("/api/sessions/{sid}/clipboard");

        // Text hợp lệ ⇒ 200, và **phải nói** là chưa inject được trên Linux.
        let ok = http(addr, "POST", &route, r#"{"text":"xin chào"}"#);
        assert!(ok.starts_with("HTTP/1.1 200"), "{ok}");
        assert!(ok.contains(r#""restore_after_ms":300"#), "§9.9 ghi 300 ms: {ok}");
        assert!(ok.contains(r#""applied":false"#), "Linux không có clipboard Windows — nói thật: {ok}");

        // Rỗng và mập mờ: hai lỗi khác nhau, hai mã khác nhau.
        assert!(http(addr, "POST", &route, r#"{"text":"   "}"#).contains("clipboard.empty"));
        assert!(http(addr, "POST", &route, r#"{"text":"a","image_b64":"aGk="}"#)
            .contains("clipboard.ambiguous"));

        // Vượt cap 256 KB ⇒ 422 **tại server**, không phải chỉ ở client.
        let big = "a".repeat(256 * 1024 + 1);
        let refused = http(addr, "POST", &route, &format!(r#"{{"text":"{big}"}}"#));
        assert!(refused.starts_with("HTTP/1.1 422"), "{refused}");
        assert!(refused.contains("clipboard.text_too_large"), "{refused}");

        // GET = "copy from remote"; trên Linux clipboard trống ⇒ null, không lỗi.
        let read = http(addr, "GET", &route, "");
        assert!(read.starts_with("HTTP/1.1 200"), "{read}");
        assert!(read.contains(r#""text":null"#), "{read}");

        // Phiên lạ ⇒ 404, không phải 200 rỗng (nếu không client tưởng đã copy).
        let unknown = http(addr, "POST", "/api/sessions/khong-co/clipboard", r#"{"text":"a"}"#);
        assert!(unknown.starts_with("HTTP/1.1 404"), "{unknown}");
        drop(server);
    }

    #[test] fn bandwidth_advice_is_available_before_and_at_session_start() {
        let (addr, server) = spawn_server();
        let before = http(addr, "GET", "/api/advice", "");
        assert!(before.starts_with("HTTP/1.1 200"), "{before}");
        assert!(before.contains(r#""recommended_preset":"auto""#), "{before}");
        assert!(before.contains(r#""measured_mbps":null"#), "chưa stream ⇒ null, không phải 0: {before}");
        assert!(before.contains(r#""mbps":8"#), "§6.10.2 ghi ~8 Mbps: {before}");

        // `DELETE` nhận **id thật** (không có route `/current`). Lấy id từ
        // `GET /api/sessions/current`, hoặc bỏ qua nếu chưa có phiên nào.
        let sid_of = |response: &str| {
            response.split("\"id\":\"").nth(1).and_then(|rest| rest.split('"').next()).map(str::to_string)
        };
        let end_current = |addr: std::net::SocketAddr| {
            let current = http(addr, "GET", "/api/sessions/current", "");
            if let Some(id) = sid_of(&current) { http(addr, "DELETE", &format!("/api/sessions/{id}"), ""); }
        };
        end_current(addr);
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        assert!(created.starts_with("HTTP/1.1 201"), "{created}");
        assert!(created.contains(r#""recommended_preset""#), "thiếu đề nghị: {created}");

        // Người dùng chọn tay ⇒ lựa chọn của họ thắng, và phải biết là nó
        // **khác** đề nghị (nếu không UI im lặng làm theo một preset tệ).
        end_current(addr);
        let forced = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop","preset":"sharp"}"#);
        assert!(forced.contains(r#""preset":"sharp""#), "lựa chọn tay phải thắng: {forced}");
        assert!(forced.contains(r#""advice_conflict":true"#), "phải báo lệch: {forced}");
        drop(server);
    }

    #[test] fn a_wid_outside_the_published_snapshot_is_refused() {
        let (addr, server) = spawn_server();
        // Liệt kê trên Linux trả rỗng (§58.3: không bịa), nên snapshot có 0
        // mục — đó cũng là trường hợp đúng để kiểm: `wid` nào cũng ngoài.
        let listed = http(addr, "GET", "/api/windows", "");
        assert!(listed.starts_with("HTTP/1.1 200"), "{listed}");
        // Phải có `snapshotId` để client tham chiếu — thiếu nó thì `wid` không
        // kiểm được, và một danh sách không kiểm được là danh sách vô dụng.
        assert!(listed.contains("snapshotId"), "phải trả snapshotId: {listed}");

        let sid_of = |response: &str| {
            response.split("\"id\":\"").nth(1).and_then(|r| r.split('"').next())
                .map(str::to_string)
        };
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        let _sid = sid_of(&created).or_else(|| {
            // Phiên có thể đã tồn tại từ test khác trong cùng server.
            let current = http(addr, "GET", "/api/sessions/current", "");
            sid_of(&current)
        });

        // Kiểm **thứ tự**: `wid` phải bị từ chối **trước** khi kiểm "đã có
        // phiên". Nếu ngược lại thì trên một server đã có phiên, mọi `wid` bịa
        // đều trả 409 `session_already_active` và **không ai biết** có cổng
        // `wid` hay không — cổng trông như có mà không kiểm gì.
        // Thứ tự kiểm là **có nghĩa**, và test này khoá nó:
        //
        // 1. `wid` có trỏ tới cửa sổ **thật, crop được** không (`409
        //    window.unavailable`)? Một cửa sổ không tồn tại thì không có gì để
        //    cấp quyền — kiểm quyền trước là kiểm một thứ trừu tượng.
        // 2. `wid` có nằm trong snapshot agent vừa trả không (`403
        //    window.unknown`)?
        // 3. Đã có phiên chưa (`409 session_already_active`)?
        //
        // Trên Linux `extended_frame_bounds` luôn `None` ⇒ mọi `wid` dừng ở (1).
        // Đó **không** phải là cổng bị vô hiệu hoá: trên Windows cùng đoạn code
        // này đi tiếp tới (2), và test `a_client_cannot_pick_an_arbitrary_window_id`
        // kiểm (2) ở tầng `authorize` trực tiếp.
        let stolen = http(addr, "POST", "/api/sessions",
            r#"{"mode":"vnc","windowId":"00000000000a0b0c","snapshotId":"ws1aaaaaaaaaaaa"}"#);
        assert!(
            stolen.starts_with("HTTP/1.1 409"),
            "cửa sổ không tồn tại ⇒ 409 window.unavailable: {stolen}"
        );
        assert!(
            stolen.contains("window.unavailable"),
            "phải nói rõ lý do, không phải \"đã có phiên\": {stolen}"
        );
        // Và **không** được tạo phiên.
        assert!(!stolen.contains("\"session\""), "{stolen}");
        drop(server);
    }

    /// §41.3 #3 / §41.4 T3: bind ra LAN thì **không ai** tạo được phiên mà
    /// không có token.
    ///
    /// Đây là test quan trọng nhất của `guard`. Unit test trong `guard` chỉ
    /// chứng minh hàm trả `Denied`; nó **không** chứng minh route gọi hàm đó.
    /// Bản đầu của `/api/sessions` không gọi, và không unit test nào thấy.
    #[test] fn on_lan_nobody_can_create_a_session_without_a_token() {
        let (addr, server) = spawn_server_with(guard::Policy::Lan);
        let denied = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        assert!(denied.starts_with("HTTP/1.1 401"), "LAN không token ⇒ 401: {denied}");
        assert!(denied.contains("missing_token"), "phải nói rõ thiếu gì: {denied}");

        // Có token nhưng server **chưa** setup ⇒ 401 `auth_not_configured`.
        // Đây là nhánh dễ viết sai nhất: `Option<Auth>::is_some()` gộp nó với
        // "không gửi token", và gộp nhầm thì thành cho qua.
        let no_auth = http_with(addr, "POST", "/api/sessions",
            r#"{"mode":"vnc","windowId":"desktop"}"#,
            &[("Authorization", "Bearer khong.phai.token")]);
        assert!(no_auth.starts_with("HTTP/1.1 401"), "chưa setup ⇒ 401: {no_auth}");
        assert!(no_auth.contains("auth_not_configured"), "phải nói rõ: {no_auth}");

        // Đã setup xong thì token rác bị phân loại cụ thể, không thành 500.
        let _ = http(addr, "POST", "/api/setup", r#"{"u":"local","p":"mat-khau-rat-dai-2026"}"#);
        let garbage = http_with(addr, "POST", "/api/sessions",
            r#"{"mode":"vnc","windowId":"desktop"}"#,
            &[("Authorization", "Bearer khong.phai.token")]);
        assert!(garbage.starts_with("HTTP/1.1 401"), "token rác ⇒ 401: {garbage}");
        assert!(garbage.contains("malformed_token"), "phải phân loại được: {garbage}");
        drop(server);
    }

    #[test] fn on_loopback_the_gate_stays_open_for_the_single_local_user() {
        // Cùng route, cùng request: khác **chính sách** thì khác kết quả. Nếu
        // test này đỏ thì hoặc ta chặn chính mình, hoặc `Policy` không được
        // truyền vào thật.
        let (addr, server) = spawn_server_with(guard::Policy::Loopback);
        let ok = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        assert!(ok.contains("\"id\""), "loopback phải tạo được phiên: {ok}");
        drop(server);
    }

    #[test] fn logout_kills_every_session_of_the_user_not_just_the_cookie() {
        // §8.1 ghi "204, kill mọi phiên của user". Nếu chỉ xoá cookie trình
        // duyệt thì một kẻ đã copy refresh token vẫn dùng được sau khi bạn
        // bấm "đăng xuất mọi nơi" — đúng thứ §41.3 P3 cảnh báo.
        let (addr, server) = spawn_server();
        let _ = http(addr, "POST", "/api/setup", r#"{"u":"local","p":"mat-khau-rat-dai-2026"}"#);
        let login = http(addr, "POST", "/api/login", r#"{"u":"local","p":"mat-khau-rat-dai-2026"}"#);
        let token = set_cookie(&login, "lantern_refresh").expect("cookie");
        let cookie = format!("lantern_refresh={token}");

        let out = http_with(addr, "POST", "/api/logout", "", &[("Cookie", &cookie)]);
        assert!(out.starts_with("HTTP/1.1 204"), "logout ⇒ 204: {out}");
        assert!(!out.contains("Internal Server Error"), "204 phải có tên đúng");

        // Cookie cũ giờ vô dụng.
        let after = http_with(addr, "POST", "/api/refresh", "", &[("Cookie", &cookie)]);
        assert!(after.starts_with("HTTP/1.1 401"), "logout phải giết refresh: {after}");
        drop(server);
    }

    /// **Lỗi thật**: `parse_json_string` cũ làm `out.push(b as char)` — mỗi
    /// *byte* thành một ký tự Latin-1. `"ế"` (3 byte UTF-8) thành 3 ký tự
    /// rác, tầng input gửi 3 code unit ⇒ gõ tiếng Việt ra `Ã¡ÂºÂ¿`.
    ///
    /// Unit test không bắt được vì chúng dựng `Event` trực tiếp, bỏ qua JSON.
    /// Test này đi qua socket thật, nên bắt được — và đã bắt được.
    #[test] fn vietnamese_text_survives_the_http_layer_as_one_code_unit() {
        let (addr, server) = spawn_server();
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        assert!(created.contains("\"id\""), "tạo phiên: {created}");
        let sid = created.split("\"id\":\"").nth(1).and_then(|r| r.split('"').next()).expect("sid").to_string();

        // UTF-8 thô trong body (đúng thứ trình duyệt gửi).
        let response = http(
            addr,
            "POST",
            &format!("/api/sessions/{sid}/input"),
            "{\"t\":\"text\",\"s\":\"ế\"}",
        );
        assert!(response.contains("\"ok\":true"), "response: {response}");
        // **1** code unit, không phải 3 byte.
        assert!(
            response.contains("\"actions\":1"),
            "`ế` phải là 1 code unit, không phải 3 byte: {response}"
        );
        drop(server);
    }

    #[test] fn a_surrogate_pair_arrives_as_two_units_over_http() {
        let (addr, server) = spawn_server();
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        let sid = created.split("\"id\":\"").nth(1).and_then(|r| r.split('"').next()).expect("sid").to_string();
        // `\\ud83d\\ude00` = 😀 dạng escape JSON (một số client gửi kiểu này).
        let response = http(
            addr,
            "POST",
            &format!("/api/sessions/{sid}/input"),
            r#"{"t":"text","s":"\ud83d\ude00"}"#,
        );
        assert!(response.contains("\"actions\":2"), "emoji phải là 2 code unit: {response}");
        drop(server);
    }

    /// §50.2 + §8.1: kết thúc phiên ⇒ **một** dòng lịch sử, đọc lại được.
    #[test] fn closing_a_session_writes_exactly_one_history_line() {
        let (addr, server) = spawn_server();
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        let sid = created.split("\"id\":\"").nth(1).and_then(|r| r.split('"').next()).expect("sid").to_string();
        let closed = http(addr, "DELETE", &format!("/api/sessions/{sid}"), "");
        assert!(closed.contains("\"stopped\":true"), "{closed}");

        let history = http(addr, "GET", "/api/history", "");
        assert!(history.contains("\"count\":1"), "phải có đúng 1 dòng: {history}");
        assert!(history.contains("\"mode\":\"vnc\""), "{history}");
        assert!(history.contains("\"end_reason\":\"closed\""), "{history}");
        // §41: không lưu tiêu đề, chỉ hash.
        assert!(!history.contains("Trình duyệt"), "không lưu tiêu đề: {history}");
        drop(server);
    }

    #[test] fn input_to_an_unknown_session_is_404_not_a_crash() {
        let (addr, server) = spawn_server();
        let response = http(addr, "POST", "/api/sessions/khong-co/input", r#"{"t":"move","nx":1,"ny":1}"#);
        assert!(response.contains("404"), "{response}");
        assert!(response.contains("session_not_found"), "{response}");
        drop(server);
    }

    #[test] fn a_forbidden_key_is_refused_over_http() {
        let (addr, server) = spawn_server();
        let created = http(addr, "POST", "/api/sessions", r#"{"mode":"vnc","windowId":"desktop"}"#);
        let sid = created.split("\"id\":\"").nth(1).and_then(|r| r.split('"').next()).expect("sid").to_string();
        // `L` **một mình** phải đi qua: người dùng gõ chữ "l" là chuyện bình
        // thường. Spec §5.8.4 chỉ chặn `Win+L` (khi Win **đang giữ**).
        let alone = http(
            addr,
            "POST",
            &format!("/api/sessions/{sid}/input"),
            r#"{"t":"key","down":1,"vk":76}"#,
        );
        assert!(alone.contains("\"actions\":1"), "chữ 'l' phải gõ được: {alone}");

        // §44.2: auto-repeat (giữ phím) **không** được gửi KEYDOWN lần hai.
        // Sanitizer không coi đây là lỗi (nó trả Ok), nên tầng trên phải tự
        // nhận ra — bản đầu bỏ sót và gửi 2 lần xuống Windows.
        let repeat = http(
            addr,
            "POST",
            &format!("/api/sessions/{sid}/input"),
            r#"{"t":"key","down":1,"vk":76}"#,
        );
        assert!(
            repeat.contains("\"actions\":0"),
            "auto-repeat không được gửi lần hai: {repeat}"
        );

        // Giữ Win trước (0x5B), rồi L ⇒ bị chặn.
        let win = http(
            addr,
            "POST",
            &format!("/api/sessions/{sid}/input"),
            r#"{"t":"key","down":1,"vk":91,"mods":0}"#,
        );
        assert!(win.contains("\"actions\":1"), "Win phải nhận được: {win}");
        let combo = http(
            addr,
            "POST",
            &format!("/api/sessions/{sid}/input"),
            r#"{"t":"key","down":1,"vk":76,"mods":0}"#,
        );
        assert!(combo.contains("forbidden_key"), "Win+L phải bị chặn: {combo}");
        assert!(combo.contains("\"actions\":0"), "{combo}");
        drop(server);
    }

    #[test] fn peer_closed_sees_a_hangup_and_not_just_a_slow_client() {
        use std::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");
        let client = TcpStream::connect(addr).expect("connect");
        let (server, _) = listener.accept().expect("accept");

        assert!(!peer_closed(&server), "client còn mở thì không được coi là đã đóng");

        drop(client);

        let start = std::time::Instant::now();
        while start.elapsed() < std::time::Duration::from_secs(2) {
            if peer_closed(&server) { return; }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        panic!("đã đóng socket mà peer_closed vẫn báo còn sống");
    }

    #[test] fn peer_closed_also_catches_an_rst_from_a_closed_tab() {
        // Đóng tab khi còn byte chưa đọc ⇒ OS gửi **RST**, không phải FIN;
        // `peek` trả `Err(ConnectionReset)` và bản đầu bỏ sót ⇒ capture chạy mãi.
        // Test viết lại đúng lần chạy thật đã phát hiện lỗi này.
        use std::io::Write;
        let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");
        let client = TcpStream::connect(addr).expect("connect");
        let (server, _) = listener.accept().expect("accept");

        // Server gửi dữ liệu client **không đọc**, rồi client đóng ⇒ RST.
        (&server).write_all(&[7u8; 4096]).ok();
        drop(client);
        (&server).write_all(&[7u8; 4096]).ok();

        let start = std::time::Instant::now();
        while start.elapsed() < std::time::Duration::from_secs(2) {
            if peer_closed(&server) { return; }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        panic!("RST từ client phải được coi là đã đóng");
    }
    #[cfg(unix)]
    
        
    #[test] fn live_status_is_honest_about_the_sandbox() {
        // Trên Linux (CI/sandbox) phải nói rõ "chỉ Windows" và `available=false`,
        // không được giả vờ sẵn sàng rồi để UI vẽ khung đen.
        #[cfg(not(target_os = "windows"))]
        {
            let (available, detail) = probe_live_status();
            assert!(!available);
            assert!(detail.contains("Windows"), "{detail}");
        }
    }
    #[test] fn diagnostics_api_is_marked_as_hardware_not_ui_mock() { assert!(run_diagnostics().contains("\"mock\":false")); }
    #[test] fn responses_carry_clickjacking_headers() {
        // §41.5 D4 — test trên giá trị thật mà socket sẽ ghi, không phải chuỗi chép tay.
        let head = response_head(200, "text/html; charset=utf-8", 42);
        assert!(head.contains("X-Frame-Options: DENY"), "{head}");
        assert!(head.contains("Content-Security-Policy: default-src 'self'; frame-ancestors 'none'"), "{head}");
        assert!(head.contains("Referrer-Policy: no-referrer"), "{head}");
        assert!(head.contains("Content-Length: 42"), "{head}");
        // Cùng bộ header cho response JSON và lỗi — không có đường nào thiếu.
        for status in [200u16, 201, 400, 404, 409, 413, 422, 500] {
            let head = response_head(status, "application/json", 2);
            assert!(head.contains("X-Frame-Options: DENY"), "status {status}: {head}");
        }
    }
}
