mod capture;
#[allow(dead_code)] // dùng trong nhánh #[cfg(windows)] của stream_live
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
struct State { settings: BTreeMap<String, String>, session: Option<Session>, next_id: u64, data_dir: PathBuf, live_status: Option<(bool, String)> }

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
fn parse_json_string(bytes: &[u8], start: usize) -> Option<(String, usize)> {
    let mut i = start + 1; let mut out = String::new();
    while i < bytes.len() {
        match bytes[i] {
            b'"' => return Some((out, i + 1)),
            b'\\' => { i += 1; if i >= bytes.len() { return None; } match bytes[i] { b'"' => out.push('"'), b'\\' => out.push('\\'), b'n' => out.push('\n'), b'r' => out.push('\r'), b't' => out.push('\t'), _ => return None } },
            b if b < 0x20 => return None,
            b => out.push(b as char),
        }
        i += 1;
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
/// 3. **Không cài gì**: toàn bộ nằm trong exe ~2 MB.
fn stream_live(mut stream: TcpStream, monitor: u8, fps: u8) {
    #[cfg(not(windows))]
    {
        let _ = fps;
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
        /// Nhịp kiểm "tab còn mở không".
        const POLL: Duration = Duration::from_millis(200);

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
        let first_jpeg = jpeg::encode(&first.bgra, first.width, first.height, JPEG_QUALITY);
        if stream.write_all(stream::stream_head().as_bytes()).is_err()
            || stream.write_all(&frame_chunk(&first_jpeg)).is_err()
            || stream.flush().is_err()
        {
            return;
        }

        let budget = Duration::from_micros(1_000_000 / u64::from(fps.max(1)));
        let mut previous = first.bgra;
        let mut next_due = Instant::now() + budget;
        loop {
            if peer_closed(&stream) {
                return;
            }
            match capture.next_frame(0) {
                Ok(frame) => {
                    if frame.bgra != previous {
                        let jpeg = jpeg::encode(&frame.bgra, frame.width, frame.height, JPEG_QUALITY);
                        if stream.write_all(&frame_chunk(&jpeg)).is_err() {
                            return; // tab đóng
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
        drop(s);
        return json_response(&mut stream, 200, format!(
            "{{\"available\":{available},\"canInstall\":{can_install},\"detail\":{},\"contentType\":{},\"boundary\":{}}}",
            json_quote(&detail), json_quote(&stream::mjpeg_content_type()), json_quote(stream::BOUNDARY)));
    }
    if method == "GET" && (route == "/live" || route == "/api/live.mjpg") {
        let query = path.split_once('?').map(|(_, q)| q).unwrap_or("");
        let (monitor, fps) = stream::parse_live_query(query);
        if route == "/live" {
            return response(&mut stream, 200, "text/html; charset=utf-8", stream::live_page(monitor, fps).as_bytes());
        }
        return stream_live(stream, monitor, fps);
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
        ("DELETE", _) if route.starts_with("/api/sessions/") => {
            let id = route.trim_start_matches("/api/sessions/");
            if s.session.as_ref().map(|session| session.id.as_str()) != Some(id) { return json_response(&mut stream, 404, "{\"error\":\"session_not_found\"}".into()); }
            let ended = s.session.take().map(|session|session_json(&session)).unwrap_or_else(||"null".into());
            json_response(&mut stream, 200, format!("{{\"session\":{},\"stopped\":true,\"mock\":true}}",ended))
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
        let (available, detail) = probe_live_status();
        println!("capture: available={available} — {detail}");
        // §58.8: in rõ vì sao nút "Xem máy thật" có thể bị xám — nếu không,
        // trên Linux/CI người đọc chỉ thấy "live route ready" và tưởng capture
        // hỏng, trong khi thực tế là thiếu GStreamer.
        let (available, detail) = probe_live_status();
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
    let state=Arc::new(Mutex::new(State{settings,session:None,next_id:0,data_dir,live_status:None}));
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
