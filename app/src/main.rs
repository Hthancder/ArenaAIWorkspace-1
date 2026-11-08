mod capture;
#[allow(dead_code)] // dùng trong nhánh #[cfg(windows)] của stream_live
mod history;
mod input;
mod jpeg;
mod stream;

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
const CSS: &str = include_str!("../../web/styles.css");
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
];

#[derive(Clone)]
struct Session { id: String, mode: String, window_id: String, started_at: u64, audio: bool }
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

struct State { settings: BTreeMap<String, String>, session: Option<Session>, next_id: u64, data_dir: PathBuf, live_status: Option<(bool, String)>, live_metrics: LiveMetrics, input: input::InputSanitizer, history: history::History }

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
        "log-level" => &["normal","verbose"], "encoder" => &["auto","qsv","nvenc"], _ => &[],
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
    format!("{{\"id\":{},\"mode\":{},\"windowId\":{},\"startedAt\":{},\"audio\":{},\"status\":\"connected\",\"mock\":true}}", json_quote(&s.id), json_quote(&s.mode), json_quote(&s.window_id), s.started_at, s.audio)
}
/// Header của **mọi** response. Tách khỏi socket để test được bằng giá trị trả
/// về, không phải bằng cách bắt chước chuỗi trong test.
///
/// §41.5 D4: thiếu hai header đầu thì một trang khác nhúng được app trong iframe
/// và bấm hộ nút "điều khiển" (clickjacking). Mock cũng phải giữ đúng, vì sản
/// phẩm thật sẽ bám theo mock.
fn response_head(status: u16, content_type: &str, content_length: usize) -> String {
    let reason = match status { 200 => "OK", 201 => "Created", 400 => "Bad Request", 404 => "Not Found", 405 => "Method Not Allowed", 409 => "Conflict", 413 => "Payload Too Large", 422 => "Unprocessable Entity", _ => "Internal Server Error" };
    format!("HTTP/1.1 {status} {reason}\r\nContent-Type: {content_type}\r\nContent-Length: {content_length}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nContent-Security-Policy: default-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'none'\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n")
}
fn response(stream: &mut TcpStream, status: u16, content_type: &str, body: &[u8]) {
    let head = response_head(status, content_type, body.len());
    let _ = stream.write_all(head.as_bytes()); let _ = stream.write_all(body); let _ = stream.flush();
}
fn json_response(stream: &mut TcpStream, status: u16, body: String) { response(stream, status, "application/json; charset=utf-8", body.as_bytes()); }
fn read_request(stream: &mut TcpStream) -> Option<(String, String, String)> {
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
    for line in lines { if let Some((name,value)) = line.split_once(':') { if name.eq_ignore_ascii_case("content-length") { length = value.trim().parse().ok()?; } } }
    if length > 8192 { return Some((method, path, "__BODY_TOO_LARGE__".into())); }
    while bytes.len() < header_end + length { let n = stream.read(&mut chunk).ok()?; if n == 0 { return None; } bytes.extend_from_slice(&chunk[..n]); }
    let body = String::from_utf8(bytes[header_end..header_end+length].to_vec()).ok()?;
    Some((method, path, body))
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
/// Có được bind ra ngoài loopback không? **Chưa** — binary này không có TLS và
/// chưa có đăng nhập, nên bind LAN nghĩa là ai trong cùng Wi-Fi cũng xem được
/// màn hình của bạn (§54.5 #1, §41.5 D4).
///
/// Hàm này tồn tại vì tài liệu **từng nói** app "từ chối" `HOST=0.0.0.0` trong
/// khi code không kiểm tra gì — đó là kiểu sai tệ nhất: tuyên bố an toàn mà
/// không có gì bảo vệ. Giờ lời hứa và code là một.
///
/// Trả `(được_bind, lý_do)`.
fn allowed_bind_host(requested: &str) -> (String, Option<String>) {
    // `LANTERN_ALLOW_LAN=1` chỉ để tự kiểm trên máy mình, có cảnh báo rõ ràng.
    let forced = env::var("LANTERN_ALLOW_LAN").map(|value| value == "1").unwrap_or(false);
    let loopback_only = ["127.0.0.1", "localhost", "::1"].contains(&requested);
    if loopback_only {
        // Bind `127.0.0.1` thay vì để OS quyết: "localhost" có thể ra ::1 rồi
        // trình duyệt lại gõ 127.0.0.1 và không vào được.
        return ("127.0.0.1".to_string(), None);
    }
    if forced {
        // Cờ ghi đè phải **thật sự** ghi đè, nếu không nó chỉ là lời nói suông.
        return (requested.to_string(), None);
    }
    (
        "127.0.0.1".to_string(),
        Some(format!(
            "Từ chối bind {requested}: bản này chưa có TLS và chưa có đăng nhập. Đang bind 127.0.0.1 thay thế. Muốn tự chịu rủi ro trên LAN: đặt LANTERN_ALLOW_LAN=1 (không khuyến khích)."
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
    let Some((method,path,body)) = read_request(&mut stream) else { return; };
    if body == "__BODY_TOO_LARGE__" { return json_response(&mut stream, 413, "{\"error\":\"body_too_large\"}".into()); }
    let route = path.split('?').next().unwrap_or("/");
    if method == "GET" && route == "/" { return response(&mut stream, 200, "text/html; charset=utf-8", INDEX.as_bytes()); }
    if method == "GET" && route == "/styles.css" { return response(&mut stream, 200, "text/css; charset=utf-8", CSS.as_bytes()); }
    if method == "GET" && route == "/app.js" { return response(&mut stream, 200, "text/javascript; charset=utf-8", JS.as_bytes()); }
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
        return stream_live(stream, monitor, fps, &state);
    }
    if method == "POST" && route == "/api/diagnostics/capture" { let (status,body)=capture_probe(&body); return json_response(&mut stream,status,body); }
    let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
    match (method.as_str(), route) {
        ("GET", "/api/health") => json_response(&mut stream, 200, "{\"ok\":true,\"app\":\"lantern-mock\",\"mode\":\"mock\"}".into()),
        ("GET", "/api/device") => json_response(&mut stream, 200, "{\"id\":\"inspiron-7467\",\"name\":\"Inspiron 7467\",\"status\":\"ready\",\"platform\":\"Windows 11\",\"location\":\"Ở nhà\",\"mock\":true}".into()),
        ("GET", "/api/windows") => json_response(&mut stream, 200, "{\"windows\":[{\"id\":\"desktop\",\"title\":\"Toàn bộ màn hình\",\"detail\":\"Desktop · 1920 × 1080\",\"mode\":\"screen\"},{\"id\":\"browser\",\"title\":\"Trình duyệt\",\"detail\":\"Chrome · Cửa sổ đang mở\",\"mode\":\"window\"},{\"id\":\"notes\",\"title\":\"Ghi chú\",\"detail\":\"Notepad · Cửa sổ đang mở\",\"mode\":\"window\"}],\"mock\":true}".into()),
        ("GET", "/api/settings") => json_response(&mut stream, 200, format!("{{\"settings\":{},\"mock\":true}}", settings_json(&s.settings))),
        ("PATCH", "/api/settings") => {
            let Some(patch) = parse_flat_object(&body) else { return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into()); };
            let mut changed = Vec::new();
            for (key,value) in patch { if s.settings.contains_key(&key) { if !allowed_value(&key,&value) { return json_response(&mut stream, 422, format!("{{\"error\":\"invalid_setting_value\",\"field\":{}}}",json_quote(&key))); } s.settings.insert(key.clone(),value); changed.push(json_quote(&key)); } }
            let _ = fs::create_dir_all(&s.data_dir);
            let _ = fs::write(s.data_dir.join("settings.json"), settings_json(&s.settings));
            json_response(&mut stream, 200, format!("{{\"settings\":{},\"updated\":[{}],\"mock\":true}}",settings_json(&s.settings),changed.join(",")))
        }
        ("GET", "/api/sessions/current") => json_response(&mut stream, 200, format!("{{\"session\":{},\"mock\":true}}",s.session.as_ref().map(session_json).unwrap_or_else(||"null".into()))),
        ("POST", "/api/sessions") => {
            if let Some(active) = &s.session { return json_response(&mut stream, 409, format!("{{\"error\":\"session_already_active\",\"session\":{}}}",session_json(active))); }
            let Some(input) = parse_flat_object(&body) else { return json_response(&mut stream, 400, "{\"error\":\"invalid_json\"}".into()); };
            let mode = input.get("mode").map(String::as_str).unwrap_or("hvnc");
            let win = input.get("windowId").map(String::as_str).unwrap_or("desktop");
            if !["hvnc","vnc"].contains(&mode) { return json_response(&mut stream, 422, "{\"error\":\"invalid_session_mode\"}".into()); }
            if !["desktop","browser","notes"].contains(&win) { return json_response(&mut stream, 422, "{\"error\":\"invalid_window_id\"}".into()); }
            s.next_id += 1; let session = Session { id: format!("mock-{}",s.next_id), mode: mode.into(), window_id: win.into(), started_at: now_seconds(), audio: input.get("audio").map(|v|v!="false").unwrap_or(true) };
            let result = session_json(&session); s.session = Some(session); json_response(&mut stream, 201, format!("{{\"session\":{},\"mock\":true}}",result))
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
        ("GET", "/api/history") => {
            let records = s.history.read();
            let items: Vec<String> = records.iter().map(history::Record::to_json).collect();
            json_response(&mut stream, 200, format!(
                "{{\"history\":[{}],\"count\":{}}}", items.join(","), records.len()))
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
    let history_log = history::History::new(&data_dir);
    let state=Arc::new(Mutex::new(State{settings,session:None,next_id:0,data_dir,live_status:None,live_metrics:LiveMetrics::default(),input:input::InputSanitizer::default(),history:history_log}));
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
                history: history::History::new(&data_dir),
            }));
            for stream in listener.incoming().take(8).flatten() {
                handle(stream, Arc::clone(&state));
            }
        });
        (addr, handle)
    }

    /// Gửi một request HTTP thô, trả toàn bộ response (header + body).
    fn http(addr: std::net::SocketAddr, method: &str, path: &str, body: &str) -> String {
        use std::io::Write;
        let mut stream = TcpStream::connect(addr).expect("connect");
        let request = format!(
            "{method} {path} HTTP/1.1\r\nHost: test\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        stream.write_all(request.as_bytes()).expect("write");
        let mut out = String::new();
        stream.read_to_string(&mut out).expect("read");
        out
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
