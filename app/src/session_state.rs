//! §6.9 + §6.10.1 — trạng thái **thay đổi được trong phiên**.
//!
//! # Vì sao tách khỏi `main.rs`
//!
//! `POST /api/sessions/{sid}/{mode,preset,monitor,window,cursor_mode,...}` là
//! 9 route (§8.1) cùng một dạng: **kiểm giá trị → áp → trả trạng thái mới**.
//! Nếu viết rời trong `main.rs` thì mỗi route tự quyết "giá trị nào hợp lệ",
//! và §6.10.1 có bảng preset thật (30/60 fps, 12/8/4/1.5 Mbps) — chép bảng đó
//! 4 lần là chắc chắn lệch.
//!
//! File này **không** giữ `Session` (nó ở `main.rs`, cạnh code dùng nó). Nó giữ
//! *luật*: preset nào tồn tại, monitor nào hợp lệ, `cursor_mode` nào có.

/// §6.10.1 nguyên văn. `fps`/`mbps` là của spec, không phải lựa chọn của tôi.
/// `Eq` không derive được vì `mbps: f32`. Điều đó **không** sao: preset được
/// so bằng `id` (chuỗi), không bằng giá trị float.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Preset {
    pub id: &'static str,
    pub label_vi: &'static str,
    pub fps: u32,
    pub mbps: f32,
    /// `true` = preset "Tiết kiệm" hạ độ phân giải xuống 1280×720.
    pub caps_720: bool,
    /// `true` = có adaptive (§6.10.1 "Auto/default").
    pub adaptive: bool,
}

/// Bảng §6.10.1, thứ tự đúng như spec.
pub const PRESETS: &[Preset] = &[
    Preset { id: "sharp", label_vi: "Nét", fps: 30, mbps: 12.0, caps_720: false, adaptive: false },
    Preset { id: "auto", label_vi: "Cân bằng", fps: 60, mbps: 8.0, caps_720: false, adaptive: true },
    Preset { id: "smooth", label_vi: "Mượt", fps: 60, mbps: 4.0, caps_720: false, adaptive: false },
    Preset { id: "low", label_vi: "Tiết kiệm", fps: 30, mbps: 1.5, caps_720: true, adaptive: false },
];

/// §6.10.1: "Cân bằng" là **mặc định**.
pub const DEFAULT_PRESET: &str = "auto";

pub fn preset_by_id(id: &str) -> Option<&'static Preset> {
    PRESETS.iter().find(|preset| preset.id == id)
}

/// §8.1: `POST /api/sessions/{sid}/preset` trả lỗi gì khi `preset` lạ.
///
/// Trả `None` cho giá trị không có trong bảng — **không** đoán gần đúng. Một
/// preset gõ sai mà lặng lẽ thành `auto` thì người dùng tưởng đã đổi chất
/// lượng, lỗi chỉ lộ ra khi mạng yếu.
pub fn resolve_preset(id: &str) -> Result<&'static Preset, &'static str> {
    preset_by_id(id).ok_or("invalid_preset")
}

/// §6.9 `POST /{sid}/cursor_mode` — ba giá trị, không hơn.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CursorMode {
    /// Con trỏ do client vẽ theo `(x,y)` đã gửi.
    Local,
    /// Server vẽ con trỏ vào frame.
    Remote,
    /// §6.9: tự chọn — ưu tiên `Local` khi RTT thấp.
    Auto,
}

impl CursorMode {
    pub fn parse(value: &str) -> Result<Self, &'static str> {
        match value {
            "local" => Ok(CursorMode::Local),
            "remote" => Ok(CursorMode::Remote),
            "auto" => Ok(CursorMode::Auto),
            _ => Err("invalid_cursor_mode"),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            CursorMode::Local => "local",
            CursorMode::Remote => "remote",
            CursorMode::Auto => "auto",
        }
    }
}

/// §6.9 `POST /{sid}/monitor { "index": 1 }`.
///
/// `MAX_MONITOR = 8` là của `stream.rs` (§57.1) — dùng lại hằng đó thay vì
/// viết số 8 lần thứ hai. Spec cũng cho phép 0-based (monitor 0 = chính).
pub fn valid_monitor(index: u32) -> Result<u32, &'static str> {
    if index >= crate::stream::MAX_MONITOR as u32 {
        return Err("invalid_monitor");
    }
    Ok(index)
}

/// §6.9 `POST /{sid}/share { "ttl_min" }` — §21.6: link xem tạm, **view-only**.
///
/// Spec không cho `ttl_min` vô hạn; giới hạn trên là 1440 phút (24 h). Không
/// có tuỳ chọn "không hết hạn" vì link chia sẻ là token **không** cần đăng
/// nhập — nó phải tự chết.
pub const MAX_SHARE_TTL_MIN: u32 = 1440;

pub fn valid_share_ttl(minutes: u32) -> Result<u32, &'static str> {
    if minutes == 0 || minutes > MAX_SHARE_TTL_MIN {
        return Err("invalid_ttl");
    }
    Ok(minutes)
}

/// Một bước chuyển nguồn capture — §6.9 đòi **thứ tự** cố định:
///
/// ```text
/// (1) restore cửa sổ cũ [hvnc]   (2) move cửa sổ mới lên display ảo
/// (3) reset input state (release_all)   (4) giữ peer/DTLS
/// (5) gửi PLI → keyframe mới            (6) 200 switching → active
/// ```
///
/// Trả về **danh sách bước** thay vì tự thực hiện: `main.rs` mới là nơi có
/// `Session` và `InputSanitizer`. Nhưng thứ tự thì ở đây, để test được mà không
/// cần socket — và để không route nào tự đảo thứ tự (ví dụ đổi nguồn capture
/// trước khi `release_all`, làm phím kẹt ở cửa sổ **mới**).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SwitchStep {
    /// (1) trả cửa sổ cũ về chỗ cũ — chỉ khi phiên cũ là `hvnc`.
    RestoreOldWindow,
    /// (2) đưa cửa sổ mới lên display ảo — chỉ khi phiên mới là `hvnc`.
    MoveNewWindow,
    /// (3) `release_all` **trước** khi đổi nguồn.
    ReleaseInput,
    /// (4) không đụng peer/DTLS: đây là một bước **không làm gì**, và nó có
    /// mặt trong danh sách để test khẳng định ta không làm gì.
    KeepPeer,
    /// (5) keyframe mới.
    RequestKeyframe,
}

pub fn switch_plan(old_mode: &str, new_mode: &str) -> Vec<SwitchStep> {
    let mut steps = Vec::with_capacity(5);
    if old_mode == "hvnc" {
        steps.push(SwitchStep::RestoreOldWindow);
    }
    if new_mode == "hvnc" {
        steps.push(SwitchStep::MoveNewWindow);
    }
    steps.push(SwitchStep::ReleaseInput);
    steps.push(SwitchStep::KeepPeer);
    steps.push(SwitchStep::RequestKeyframe);
    steps
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test] fn the_preset_table_matches_the_spec_numbers() {
        // §6.10.1. Nếu test này đỏ thì bảng trong code khác bảng trong spec —
        // và người dùng sẽ nhận bitrate khác thứ họ chọn.
        assert_eq!(preset_by_id("sharp").unwrap().fps, 30);
        assert_eq!(preset_by_id("sharp").unwrap().mbps, 12.0);
        assert_eq!(preset_by_id("auto").unwrap().fps, 60);
        assert_eq!(preset_by_id("smooth").unwrap().mbps, 4.0);
        let low = preset_by_id("low").unwrap();
        assert_eq!((low.fps, low.mbps, low.caps_720), (30, 1.5, true));
        assert_eq!(PRESETS.len(), 4, "spec có đúng 4 preset");
    }

    #[test] fn the_default_preset_is_auto() {
        // §6.10.1 "Cân bằng (Auto/default)".
        assert_eq!(DEFAULT_PRESET, "auto");
        assert!(preset_by_id(DEFAULT_PRESET).is_some());
        assert!(preset_by_id(DEFAULT_PRESET).unwrap().adaptive);
    }

    #[test] fn an_unknown_preset_is_an_error_not_a_silent_default() {
        assert_eq!(resolve_preset("nét"), Err("invalid_preset"));
        assert_eq!(resolve_preset(""), Err("invalid_preset"));
        assert_eq!(resolve_preset("Sharp"), Err("invalid_preset"), "phân biệt hoa thường");
        assert!(resolve_preset("sharp").is_ok());
    }

    #[test] fn cursor_modes_round_trip_and_reject_anything_else() {
        for mode in [CursorMode::Local, CursorMode::Remote, CursorMode::Auto] {
            assert_eq!(CursorMode::parse(mode.as_str()), Ok(mode));
        }
        assert_eq!(CursorMode::parse("none"), Err("invalid_cursor_mode"));
        assert_eq!(CursorMode::parse("Local"), Err("invalid_cursor_mode"));
    }

    #[test] fn monitor_indices_are_bounded_by_the_shared_constant() {
        assert_eq!(valid_monitor(0), Ok(0));
        assert_eq!(valid_monitor(7), Ok(7));
        assert!(valid_monitor(8).is_err(), "MAX_MONITOR = 8 ⇒ 8 không hợp lệ");
        assert!(valid_monitor(u32::MAX).is_err());
    }

    #[test] fn a_share_link_can_never_live_forever() {
        // §21.6: link chia sẻ không cần đăng nhập ⇒ phải tự chết.
        assert!(valid_share_ttl(0).is_err(), "0 phút = link chết ngay, vô nghĩa");
        assert!(valid_share_ttl(1).is_ok());
        assert!(valid_share_ttl(1440).is_ok());
        assert!(valid_share_ttl(1441).is_err(), "trên 24 h phải bị từ chối");
    }

    #[test] fn switching_releases_input_before_touching_the_capture_source() {
        // §6.9 liệt kê đúng thứ tự. Đảo (3) và (4)/(2) thì phím đang giữ được
        // nhả vào **cửa sổ mới** — thao tác người dùng không hề bấm.
        let plan = switch_plan("hvnc", "vnc");
        let release = plan.iter().position(|s| *s == SwitchStep::ReleaseInput).unwrap();
        let restore = plan.iter().position(|s| *s == SwitchStep::RestoreOldWindow).unwrap();
        assert!(restore < release, "restore cũ phải trước release: {plan:?}");
        assert_eq!(*plan.last().unwrap(), SwitchStep::RequestKeyframe);
    }

    #[test] fn the_switch_plan_only_moves_windows_that_belong_to_hvnc() {
        // vnc → vnc: không move cửa sổ nào (VNC không sở hữu cửa sổ).
        assert!(!switch_plan("vnc", "vnc").contains(&SwitchStep::RestoreOldWindow));
        assert!(!switch_plan("vnc", "vnc").contains(&SwitchStep::MoveNewWindow));
        // hvnc → vnc: phải restore cái cũ, không move cái mới.
        let plan = switch_plan("hvnc", "vnc");
        assert!(plan.contains(&SwitchStep::RestoreOldWindow));
        assert!(!plan.contains(&SwitchStep::MoveNewWindow));
        // vnc → hvnc: ngược lại.
        let plan = switch_plan("vnc", "hvnc");
        assert!(!plan.contains(&SwitchStep::RestoreOldWindow));
        assert!(plan.contains(&SwitchStep::MoveNewWindow));
    }

    #[test] fn every_switch_keeps_the_peer_and_asks_for_a_keyframe() {
        // §6.9 bước (4) "giữ nguyên peer/DTLS/SRTP — CHỈ đổi nguồn capture" và
        // (5) "gửi PLI → keyframe mới". Đổi nguồn mà không xin keyframe thì
        // client nhận frame tham chiếu vào frame cũ ⇒ hình rác tới IDR kế tiếp.
        for (old, new) in [("vnc", "vnc"), ("hvnc", "vnc"), ("vnc", "hvnc"), ("hvnc", "hvnc")] {
            let plan = switch_plan(old, new);
            assert!(plan.contains(&SwitchStep::KeepPeer), "{old}→{new}");
            assert_eq!(*plan.last().unwrap(), SwitchStep::RequestKeyframe, "{old}→{new}");
        }
    }
}
