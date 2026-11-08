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
struct State { settings: BTreeMap<String, String>, session: Option<Session>, next_id: u64, data_dir: PathBuf }

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

fn handle(mut stream: TcpStream, state: Arc<Mutex<State>>) {
    let Some((method,path,body)) = read_request(&mut stream) else { return; };
    if body == "__BODY_TOO_LARGE__" { return json_response(&mut stream, 413, "{\"error\":\"body_too_large\"}".into()); }
    let route = path.split('?').next().unwrap_or("/");
    if method == "GET" && route == "/" { return response(&mut stream, 200, "text/html; charset=utf-8", INDEX.as_bytes()); }
    if method == "GET" && route == "/styles.css" { return response(&mut stream, 200, "text/css; charset=utf-8", CSS.as_bytes()); }
    if method == "GET" && route == "/app.js" { return response(&mut stream, 200, "text/javascript; charset=utf-8", JS.as_bytes()); }
    if method == "GET" && route == "/api/diagnostics" { return json_response(&mut stream, 200, run_diagnostics()); }
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
        println!("Lantern mock assets embedded; API routes ready.");
        return;
    }
    let host = env::var("HOST").unwrap_or_else(|_| "127.0.0.1".into());
    let port = env::var("PORT").unwrap_or_else(|_| "0".into());
    let listener = TcpListener::bind(format!("{host}:{port}")).unwrap_or_else(|e| { eprintln!("Cannot listen on {host}:{port}: {e}"); std::process::exit(1); });
    let actual = listener.local_addr().map(|a|a.port()).unwrap_or(0);
    let data_dir = env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(env::temp_dir).join("LanternMock");
    let mut settings = SETTINGS_DEFAULTS.iter().map(|(k,v)|(k.to_string(),v.to_string())).collect::<BTreeMap<_,_>>();
    if let Ok(text) = fs::read_to_string(data_dir.join("settings.json")) { if let Some(saved)=parse_flat_object(&text) { for (k,v) in saved { if settings.contains_key(&k) && allowed_value(&k,&v) { settings.insert(k,v); } } } }
    let state=Arc::new(Mutex::new(State{settings,session:None,next_id:0,data_dir}));
    let url = format!("http://127.0.0.1:{actual}");
    println!("Lantern mock is ready. Open {url} in your browser.");
    println!("This is a local UI/API mock; it does not control Windows or capture media.");
    #[cfg(target_os = "windows")]
    { let _ = std::process::Command::new("cmd").arg("/C").arg("start").arg("").arg(&url).spawn(); }
    for incoming in listener.incoming() { match incoming { Ok(stream)=>{ let shared=Arc::clone(&state); let _=thread::Builder::new().name("lantern-mock-request".into()).spawn(move||handle(stream,shared)); }, Err(e)=>eprintln!("Request error: {e}") } }
}

#[cfg(test)]
mod tests {
    use super::*;
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
