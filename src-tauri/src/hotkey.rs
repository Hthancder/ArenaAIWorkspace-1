//! Phím tắt toàn cục (tauri-plugin-global-shortcut).
//! Tổ hợp được chuẩn hoá qua `models::normalize_hotkey_spec` ở mọi entry point;
//! Rust luôn tự parse lại từ chuỗi đã lưu — không tin chuỗi mù.
use crate::models::normalize_hotkey_spec;
use tauri::{AppHandle, Manager};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutEvent, ShortcutState};

pub fn build_shortcut(spec: &str) -> Option<Shortcut> {
    let norm = normalize_hotkey_spec(spec)?;
    let mut mods = Modifiers::empty();
    let mut code: Option<Code> = None;
    for tok in norm.split('+') {
        match tok {
            "Ctrl" => mods |= Modifiers::CONTROL,
            "Alt" => mods |= Modifiers::ALT,
            "Shift" => mods |= Modifiers::SHIFT,
            "Win" => mods |= Modifiers::SUPER,
            k => code = Some(parse_code(k)?),
        }
    }
    Some(Shortcut::new(Some(mods), code?))
}

fn parse_code(k: &str) -> Option<Code> {
    use Code::*;
    Some(match k {
        "A" => KeyA, "B" => KeyB, "C" => KeyC, "D" => KeyD, "E" => KeyE, "F" => KeyF,
        "G" => KeyG, "H" => KeyH, "I" => KeyI, "J" => KeyJ, "K" => KeyK, "L" => KeyL,
        "M" => KeyM, "N" => KeyN, "O" => KeyO, "P" => KeyP, "Q" => KeyQ, "R" => KeyR,
        "S" => KeyS, "T" => KeyT, "U" => KeyU, "V" => KeyV, "W" => KeyW, "X" => KeyX,
        "Y" => KeyY, "Z" => KeyZ,
        "0" => Digit0, "1" => Digit1, "2" => Digit2, "3" => Digit3, "4" => Digit4,
        "5" => Digit5, "6" => Digit6, "7" => Digit7, "8" => Digit8, "9" => Digit9,
        "F1" => F1, "F2" => F2, "F3" => F3, "F4" => F4, "F5" => F5, "F6" => F6,
        "F7" => F7, "F8" => F8, "F9" => F9, "F10" => F10, "F11" => F11, "F12" => F12,
        _ => return None,
    })
}

/// Đăng ký tổ hợp + handler toggle cửa sổ chính. Trả lỗi thật (bị app khác chiếm…).
pub fn register(app: &AppHandle, spec: &str) -> Result<(), String> {
    let sc = build_shortcut(spec).ok_or_else(|| "Tổ hợp phím không hợp lệ".to_string())?;
    app.global_shortcut()
        .on_shortcut(sc, move |app, _sc, event: ShortcutEvent| {
            if event.state == ShortcutState::Pressed {
                toggle_main(app);
            }
        })
        .map(|_| ())
        .map_err(|e| e.to_string())
}

pub fn unregister(app: &AppHandle, spec: &str) {
    if let Some(sc) = build_shortcut(spec) {
        let _ = app.global_shortcut().unregister(sc);
    }
}

/// Hiện nếu đang ẩn, ẩn nếu đang hiện — toggle từ mọi ứng dụng.
pub fn toggle_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        match w.is_visible() {
            Ok(true) => {
                let _ = w.hide();
            }
            _ => {
                let _ = w.show();
                let _ = w.unminimize();
                let _ = w.set_focus();
            }
        }
    }
}
