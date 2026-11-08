mod stream;

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{BufReader, Read, Write};
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

fn probe_live_status() -> (bool, String) {
    #[cfg(not(target_os = "windows"))]
    {
        (false, "Chỉ bản .exe trên Windows mới capture được màn hình.".into())
    }
    #[cfg(target_os = "windows")]
    {
        match std::process::Command::new("gst-launch-1.0")
            .arg("--version")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
        {
            Err(_) => return (false, "Chưa có GStreamer trong PATH. Cài GStreamer MSVC 64-bit (Complete) rồi mở lại app — xem docs/run-on-windows.md.".into()),
            Ok(status) if !status.success() => return (false, "gst-launch-1.0 chạy được nhưng trả mã lỗi.".into()),
            Ok(_) => {}
        }
        match std::process::Command::new("gst-inspect-1.0")
            .arg("d3d11screencapturesrc")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
        {
            Ok(status) if status.success() => (true, "Sẵn sàng: DXGI capture + MJPEG.".into()),
            _ => (false, "Thiếu plugin d3d11 (gst-plugins-bad). Cài GStreamer bản Complete, hoặc thêm gst-plugins-bad.".into()),
        }
    }
}

/// Thời gian chờ frame đầu, có thể hạ xuống cho test (`LANTERN_FIRST_FRAME_MS`).
/// Clamp để một biến môi trường sai không làm app treo vô hạn hoặc bỏ cuộc ngay.
fn first_frame_timeout() -> std::time::Duration {
    let ms = env::var("LANTERN_FIRST_FRAME_MS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(8_000);
    std::time::Duration::from_millis(ms.clamp(200, 30_000))
}

/// Tên lệnh GStreamer. Tách ra thành một hàm **chỉ để test có thể trỏ vào
/// script giả** (`LANTERN_GST`) — nhờ vậy các test HTTP dưới đây chạy được trên
/// CI Linux mà vẫn đi qua đúng đoạn code sẽ chạy trên laptop Windows.
fn gst_program() -> String {
    env::var("LANTERN_GST").unwrap_or_else(|_| "gst-launch-1.0".to_string())
}

/// Giữ `Child` và **luôn** kill khi ra khỏi scope — kể cả khi return sớm giữa
/// đường. Không có guard này thì mỗi nhánh lỗi là một tiến trình capture mồ côi:
/// người dùng đóng tab, pipeline vẫn chạy, laptop vẫn nóng, và không ai thấy gì.
struct ChildGuard(std::process::Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

impl ChildGuard {
    /// Kill trước, rồi mới đọc stderr. Đọc stderr của một tiến trình **còn
    /// đang chạy** là treo tới khi nó thoát (§58.7) — `gst-launch` sống mãi khi
    /// pipeline chỉ chờ frame, nên người dùng thấy spinner vô hạn thay vì lỗi.
    fn take_stderr_after_kill(&mut self) -> String {
        let _ = self.0.kill();
        let _ = self.0.wait();
        let mut text = String::new();
        if let Some(stderr) = self.0.stderr.take() {
            let _ = BufReader::new(stderr).read_to_string(&mut text);
        }
        text
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
/// 1. **Frame đầu tiên**: pipeline có thể chết hoặc đứng ⇒ chờ tối đa
///    `FIRST_FRAME_TIMEOUT`, quá hạn thì kill + `504`, không để client tải mãi.
/// 2. **Vòng chép**: đọc stdout bằng `recv_timeout`, mỗi lần hết hạn thì hỏi xem
///    client còn đó không. Trước khi có bản này, đóng tab **không** dừng pipeline
///    — đúng lỗi tìm ra khi thử bằng socket thật (xem §58.6).
fn stream_live(mut stream: TcpStream, monitor: u8, fps: u8) {
    use std::io::Read;
    use std::process::{Command, Stdio};
    use std::sync::mpsc;
    use std::time::Duration;

    // Chờ frame đầu: 8 s mặc định (đủ cho cold start DXGI, §53.4); test hạ
    // xuống qua LANTERN_FIRST_FRAME_MS để không phải chờ 8 s thật.
    let first_frame_timeout = first_frame_timeout();
    /// Nhịp kiểm "client còn đó không": tab đóng ⇒ pipeline chết trong ≤ ¼ s.
    const POLL: Duration = Duration::from_millis(250);

    let args = stream::mjpeg_args(monitor, fps, stream::DEFAULT_WIDTH, stream::DEFAULT_HEIGHT);
    let program = gst_program();
    let mut child = match Command::new(&program)
        .args(&args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => ChildGuard(child),
        Err(error) => {
            let message = format!("Không chạy được gst-launch-1.0: {error}");
            return response(&mut stream, 503, "text/plain; charset=utf-8", message.as_bytes());
        }
    };

    let Some(stdout) = child.0.stdout.take() else {
        return response(&mut stream, 500, "text/plain; charset=utf-8", b"gst-launch-1.0: no stdout");
    };

    // stdout đọc trên thread riêng ⇒ luồng chính không bao giờ block vô hạn.
    let (tx, rx) = mpsc::channel::<Vec<u8>>();
    std::thread::spawn(move || {
        let mut reader = BufReader::new(stdout);
        let mut buffer = vec![0u8; 64 * 1024];
        loop {
            match reader.read(&mut buffer) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    if tx.send(buffer[..n].to_vec()).is_err() {
                        break;
                    }
                }
            }
        }
    });

    let first = match rx.recv_timeout(first_frame_timeout) {
        Ok(chunk) => chunk,
        Err(_) => {
            let mut detail = format!(
                "Pipeline không trả về frame nào trong {} giây. Kiểm tra monitor-index và GStreamer.",
                first_frame_timeout.as_secs_f32()
            );
            // Kill TRƯỚC khi đọc stderr — xem `take_stderr_after_kill`.
            let text = child.take_stderr_after_kill();
            if !text.trim().is_empty() {
                detail = clean_output(&text);
            }
            return response(&mut stream, 504, "text/plain; charset=utf-8", detail.as_bytes());
        }
    };

    if stream.write_all(stream::stream_head().as_bytes()).is_err()
        || stream.write_all(&first).is_err()
        || stream.flush().is_err()
    {
        return; // guard kill khi drop
    }

    loop {
        match rx.recv_timeout(POLL) {
            Ok(chunk) => {
                if stream.write_all(&chunk).is_err() {
                    break; // client đóng tab
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                // Pipeline im lặng không có nghĩa là nó còn sống.
                if peer_closed(&stream) {
                    break;
                }
            }
        }
    }
    // `child` drop ở đây ⇒ SIGKILL + wait.
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
        let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
        if s.live_status.is_none() { s.live_status = Some(probe_live_status()); }
        let (available, detail) = s.live_status.clone().unwrap_or((false, String::new()));
        return json_response(&mut stream, 200, format!(
            "{{\"available\":{available},\"detail\":{},\"contentType\":{},\"boundary\":{}}}",
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
        assert!(stream::mjpeg_args(0, 15, 1280, 720).join(" ").contains("d3d11screencapturesrc"));
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
    println!("Xem màn hình thật (nếu đã cài GStreamer): {url}/live  — hoặc bấm nút \"Xem máy thật\".");
    println!("This is a local UI/API mock; it does not control Windows or capture media.");
    #[cfg(target_os = "windows")]
    { let _ = std::process::Command::new("cmd").arg("/C").arg("start").arg("").arg(&url).spawn(); }
    for incoming in listener.incoming() { match incoming { Ok(stream)=>{ let shared=Arc::clone(&state); let _=thread::Builder::new().name("lantern-mock-request".into()).spawn(move||handle(stream,shared)); }, Err(e)=>eprintln!("Request error: {e}") } }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `LANTERN_GST`/`LANTERN_FIRST_FRAME_MS` là biến **toàn cục**, mà test chạy
    /// song song ⇒ mọi test dựng server phải giữ lock này, nếu không chúng ghi
    /// đè lẫn nhau và thành flaky (đúng loại lỗi khó chịu nhất trong CI).
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    struct TestServer {
        port: u16,
        dir: std::path::PathBuf,
        _guard: std::sync::MutexGuard<'static, ()>,
    }

    /// Dựng server thật trên cổng ngẫu nhiên, dùng script `gst` giả. Request đi
    /// qua đúng `handle()` và đúng socket như trình duyệt — không phải mock của
    /// `stream_live`. Đây chính là thứ đã bắt được 3 lỗi thật của §58.7–§58.9.
    fn spawn_test_server(gst_script: &str, first_frame_ms: &str) -> TestServer {
        use std::io::Write as _;
        let guard = ENV_LOCK.lock().unwrap_or_else(|error| error.into_inner());
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!("lantern-test-{}-{stamp}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("tạo thư mục tạm");

        let gst = dir.join("gst-launch-1.0");
        let mut file = std::fs::File::create(&gst).expect("tạo gst giả");
        file.write_all(gst_script.as_bytes()).expect("ghi gst giả");
        drop(file);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&gst, std::fs::Permissions::from_mode(0o755)).expect("chmod");
        }
        env::set_var("LANTERN_GST", &gst);
        env::set_var("LANTERN_FIRST_FRAME_MS", first_frame_ms);

        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().expect("addr").port();
        let state = Arc::new(Mutex::new(State {
            settings: BTreeMap::new(),
            session: None,
            next_id: 0,
            data_dir: dir.clone(),
            live_status: None,
        }));
        thread::spawn(move || {
            for incoming in listener.incoming() {
                match incoming {
                    Ok(stream) => {
                        let shared = Arc::clone(&state);
                        let _ = thread::spawn(move || handle(stream, shared));
                    }
                    Err(_) => break,
                }
            }
        });
        TestServer { port, dir, _guard: guard }
    }

    /// Đọc PID mà script giả đã tự ghi (`echo $$ > pidfile`). Đếm tiến trình
    /// theo tên/chuỗi lệnh thì trên CI có thể dính tiến trình lạ; PID thì không.
    fn fake_pid(dir: &std::path::Path) -> Option<u32> {
        std::fs::read_to_string(dir.join("pid")).ok()?.trim().parse().ok()
    }

    /// Tiến trình còn sống? (`kill -0`; thu stderr để log test không bị rác.)
    fn process_alive(pid: u32) -> bool {
        std::process::Command::new("kill")
            .args(["-0", &pid.to_string()])
            .stderr(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .status()
            .map(|status| status.success())
            .unwrap_or(false)
    }

    /// Mở stream như trình duyệt rồi bỏ đi ngay (còn byte chưa đọc ⇒ RST).
    fn open_and_abandon(port: u16) {
        let mut stream = TcpStream::connect(("127.0.0.1", port)).expect("kết nối");
        stream
            .write_all(b"GET /api/live.mjpg?monitor=1 HTTP/1.1\r\nHost: t\r\n\r\n")
            .expect("gửi request");
        stream
            .set_read_timeout(Some(std::time::Duration::from_secs(5)))
            .ok();
        let mut head = [0u8; 96];
        let _ = stream.read(&mut head);
        drop(stream); // không đọc nốt ⇒ OS gửi RST
    }

    /// Đợi tới khi điều kiện đúng, tối đa `limit`. Trả `false` nếu hết giờ.
    fn wait_until(limit: std::time::Duration, mut check: impl FnMut() -> bool) -> bool {
        let start = std::time::Instant::now();
        while start.elapsed() < limit {
            if check() { return true; }
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        check()
    }

    #[cfg(unix)]
    #[test] fn http_stream_kills_the_pipeline_when_the_tab_closes() {
        // §58.7 (lỗi 1): bản đầu chỉ kill khi `write_all` lỗi. Một pipeline im
        // lặng thì không có lần ghi nào ⇒ tiến trình sống mãi, laptop nóng.
        // §58.8 (lỗi 2): đóng tab khi còn byte chưa đọc ⇒ RST, mà `peer_closed`
        // bản đầu chỉ nhận `Ok(0)`.
        let server = spawn_test_server(
            "#!/bin/sh\necho $$ > \"$(dirname \"$0\")/pid\"\nprintf -- '--lanternframe\\r\\nContent-Type: image/jpeg\\r\\n\\r\\n'\nprintf 'F1'\nprintf -- '\\r\\n'\nexec sleep 173\n",
            "4000",
        );
        open_and_abandon(server.port);
        let pid = fake_pid(&server.dir).expect("script giả phải ghi pid");
        assert!(process_alive(pid), "pipeline phải đang chạy khi có người xem");
        assert!(
            wait_until(std::time::Duration::from_secs(3), || !process_alive(pid)),
            "đóng tab mà pipeline (pid {pid}) vẫn chạy"
        );
    }

    #[cfg(unix)]
    #[test] fn http_stream_returns_504_and_cleans_up_when_no_frame_arrives() {
        // §58.9 (lỗi 3): nhánh lỗi đọc stderr của tiến trình **còn sống** ⇒ treo
        // tới khi pipeline thoát (có thể là mãi mãi). Phải trả 504 trong khoảng
        // thời gian chờ, kèm lời giải thích của GStreamer, và không để lại gì.
        let server = spawn_test_server(
            "#!/bin/sh\necho $$ > \"$(dirname \"$0\")/pid\"\necho 'ERROR: monitor-index khong ton tai' >&2\nexec sleep 179\n",
            "300",
        );
        let start = std::time::Instant::now();
        let mut stream = TcpStream::connect(("127.0.0.1", server.port)).expect("kết nối");
        stream
            .write_all(b"GET /api/live.mjpg?monitor=9 HTTP/1.1\r\nHost: t\r\n\r\n")
            .expect("gửi request");
        stream
            .set_read_timeout(Some(std::time::Duration::from_secs(10)))
            .ok();
        let mut text = String::new();
        let _ = stream.read_to_string(&mut text);
        let elapsed = start.elapsed();

        assert!(text.starts_with("HTTP/1.1 504"), "mong 504, nhận: {:?}", &text[..text.len().min(60)]);
        assert!(text.contains("monitor-index khong ton tai"), "phải giữ lỗi của GStreamer: {text:?}");
        assert!(elapsed < std::time::Duration::from_secs(6), "trả lời quá chậm: {elapsed:?}");
        let pid = fake_pid(&server.dir).expect("script giả phải ghi pid");
        assert!(wait_until(std::time::Duration::from_secs(2), || !process_alive(pid)), "để lại tiến trình capture (pid {pid})");
    }

    #[cfg(unix)]
    #[test] fn http_stream_sends_multipart_headers_before_body() {
        // Hợp đồng với trình duyệt: đúng content-type, không có Content-Length,
        // và header đi **sau** frame đầu tiên (nếu gửi 200 trước rồi mới phát
        // hiện pipeline chết thì trình duyệt đã hiện khung vỡ).
        let server = spawn_test_server(
            "#!/bin/sh\necho $$ > \"$(dirname \"$0\")/pid\"\nprintf -- '--lanternframe\\r\\nContent-Type: image/jpeg\\r\\n\\r\\n'\nprintf 'F1'\nprintf -- '\\r\\n'\nexec sleep 181\n",
            "4000",
        );
        let mut stream = TcpStream::connect(("127.0.0.1", server.port)).expect("kết nối");
        stream
            .write_all(b"GET /api/live.mjpg?monitor=1&fps=99 HTTP/1.1\r\nHost: t\r\n\r\n")
            .expect("gửi request");
        stream
            .set_read_timeout(Some(std::time::Duration::from_secs(5)))
            .ok();
        let mut head = [0u8; 512];
        let n = stream.read(&mut head).expect("đọc header");
        let text = String::from_utf8_lossy(&head[..n]).to_string();
        assert!(text.starts_with("HTTP/1.1 200"), "{text:?}");
        assert!(text.contains(stream::mjpeg_content_type().as_str()), "content-type: {text:?}");
        assert!(!text.to_lowercase().contains("content-length"), "stream không được có Content-Length");
        drop(stream);
        if let Some(pid) = fake_pid(&server.dir) {
            let _ = wait_until(std::time::Duration::from_secs(2), || !process_alive(pid));
        }
    }

    #[test] fn parses_patch_and_escapes() { let p=parse_flat_object(r#"{"quality":"smooth","volume":35,"hide-taskbar":true}"#).unwrap(); assert_eq!(p.get("quality").unwrap(),"smooth"); assert_eq!(p.get("volume").unwrap(),"35"); assert!(allowed_value("hide-taskbar",p.get("hide-taskbar").unwrap())); }
    #[test] fn rejects_bad_enum() { assert!(!allowed_value("quality","disable-encryption")); assert!(!allowed_value("volume","101")); }
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
    #[test] fn stderr_is_read_only_after_the_child_is_gone() {
        // Lỗi thật §58.7: đọc stderr của pipeline **còn sống** thì treo tới khi
        // nó thoát. Test này spawn một tiến trình chỉ in lỗi rồi ngủ, và đòi
        // hỏi đáp trong < 2 s.
        use std::process::Stdio;
        let child = std::process::Command::new("sh")
            .args(["-c", "echo 'loi gst' >&2; exec sleep 97"])
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn");
        let mut guard = ChildGuard(child);
        // Trong thực tế ta đã chờ 8 s trước khi tới nhánh này, nên tiến trình
        // đã kịp ghi lỗi. Chờ 150 ms để mô phỏng đúng thứ tự đó.
        std::thread::sleep(std::time::Duration::from_millis(150));
        let start = std::time::Instant::now();
        let text = guard.take_stderr_after_kill();
        assert!(start.elapsed() < std::time::Duration::from_secs(2), "đọc stderr bị treo");
        assert!(text.contains("loi gst"), "phải giữ được thông báo lỗi: {text:?}");
    }

    #[test] fn child_guard_kills_the_process_even_on_early_return() {
        let child = std::process::Command::new("sleep")
            .arg("30")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .expect("spawn sleep");
        let pid = child.id();
        { let _guard = ChildGuard(child); }
        let alive = std::process::Command::new("kill")
            .args(["-0", &pid.to_string()])
            .stderr(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .status()
            .map(|status| status.success())
            .unwrap_or(false);
        assert!(!alive, "ChildGuard phải kill tiến trình con khi drop");
    }
    #[test] fn a_lan_bind_is_refused_unless_explicitly_forced() {
        // §58.11: docs từng hứa app "từ chối HOST=0.0.0.0" trong khi code không
        // kiểm tra — bind LAN không TLS = ai cùng Wi-Fi cũng xem màn hình bạn.
        // Test này giữ cho lời hứa và code không tách rời lần nữa.
        for host in ["127.0.0.1", "localhost", "::1"] {
            assert_eq!(allowed_bind_host(host).0, "127.0.0.1", "{host} phải bind được");
            assert!(allowed_bind_host(host).1.is_none(), "{host} không được cảnh báo");
        }
        for host in ["0.0.0.0", "192.168.1.10", "::", "máy-của-tôi"] {
            let (bound, reason) = allowed_bind_host(host);
            assert_eq!(bound, "127.0.0.1", "{host} phải bị hạ về loopback");
            assert!(reason.is_some(), "{host} bị từ chối thì phải nói lý do");
        }
        // Và cờ ghi đè phải thật sự ghi đè — nếu không thì nó vô dụng.
        // Giữ ENV_LOCK vì đây là biến môi trường **toàn cục**.
        let _guard = ENV_LOCK.lock().unwrap_or_else(|error| error.into_inner());
        env::set_var("LANTERN_ALLOW_LAN", "1");
        let (bound, reason) = allowed_bind_host("0.0.0.0");
        env::remove_var("LANTERN_ALLOW_LAN");
        assert_eq!(bound, "0.0.0.0");
        assert!(reason.is_none());
    }

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
