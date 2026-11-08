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
fn response(stream: &mut TcpStream, status: u16, content_type: &str, body: &[u8]) {
    let reason = match status { 200 => "OK", 201 => "Created", 400 => "Bad Request", 404 => "Not Found", 405 => "Method Not Allowed", 409 => "Conflict", 413 => "Payload Too Large", 422 => "Unprocessable Entity", _ => "Internal Server Error" };
    let head = format!("HTTP/1.1 {status} {reason}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n", body.len());
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
fn handle(mut stream: TcpStream, state: Arc<Mutex<State>>) {
    let Some((method,path,body)) = read_request(&mut stream) else { return; };
    if body == "__BODY_TOO_LARGE__" { return json_response(&mut stream, 413, "{\"error\":\"body_too_large\"}".into()); }
    let route = path.split('?').next().unwrap_or("/");
    if method == "GET" && route == "/" { return response(&mut stream, 200, "text/html; charset=utf-8", INDEX.as_bytes()); }
    if method == "GET" && route == "/styles.css" { return response(&mut stream, 200, "text/css; charset=utf-8", CSS.as_bytes()); }
    if method == "GET" && route == "/app.js" { return response(&mut stream, 200, "text/javascript; charset=utf-8", JS.as_bytes()); }
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
}
