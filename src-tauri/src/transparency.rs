//! Transparency effects của Windows — công tắc toàn hệ thống (theo tài khoản)
//! mà DWM dựa vào để đổ mờ/acrylic phía sau cửa sổ.
//! Đường registry: HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\EnableTransparency
//! Đọc/ghi qua reg.exe (có sẵn mọi bản Windows) — không cần dependency nào.
#![allow(dead_code)]

use std::process::Command;

#[cfg(windows)]
use std::os::windows::process::CommandExt;

const KEY: &str = r"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";

/// CREATE_NO_WINDOW — reg.exe chạy nền, không lóe cửa sổ console
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

fn reg(args: &[&str]) -> Option<String> {
    let mut cmd = Command::new("reg");
    cmd.args(args);
    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);
    match cmd.output() {
        Ok(o) if o.status.success() => Some(String::from_utf8_lossy(&o.stdout).to_string()),
        _ => None,
    }
}

/// true = đang BẬT, false = đang TẮT, None = không đọc được (key/value chưa có hoặc lỗi)
pub fn read() -> Option<bool> {
    #[cfg(not(windows))]
    {
        return None;
    }
    #[cfg(windows)]
    {
        let out = reg(&["query", KEY, "/v", "EnableTransparency"])?;
        for line in out.lines() {
            if !line.contains("EnableTransparency") {
                continue;
            }
            if let Some(pos) = line.find("0x") {
                let hex: String = line[pos + 2..]
                    .chars()
                    .take_while(|c| c.is_ascii_hexdigit())
                    .collect();
                if let Ok(v) = u32::from_str_radix(&hex, 16) {
                    return Some(v != 0);
                }
            }
            // Một số bản Windows in giá trị thập phân? không — nhưng phòng:
            let last = line.split_whitespace().last().unwrap_or("");
            match last {
                "1" => return Some(true),
                "0" => return Some(false),
                _ => {}
            }
        }
        None
    }
}

/// Bật/tắt Transparency effects cho tài khoản hiện tại. Trả về trạng thái thực sau khi ghi.
pub fn set(on: bool) -> Result<bool, String> {
    #[cfg(not(windows))]
    {
        let _ = on;
        return Err("Chỉ hỗ trợ trên Windows".to_string());
    }
    #[cfg(windows)]
    {
        let d = if on { "1" } else { "0" };
        match reg(&["add", KEY, "/v", "EnableTransparency", "/t", "REG_DWORD", "/d", d, "/f"]) {
            Some(_) => Ok(read().unwrap_or(on)),
            None => Err("reg add thất bại — không ghi được công tắc Transparency effects".to_string()),
        }
    }
}
