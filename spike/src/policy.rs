//! Guard policy: three levels, and the *default* is Warn (spec §54.1).
//!
//! The user's correction that produced this module: "vẫn được tính nhưng cần
//! thoải mái chứ không cứng quá". So a guard may only Block when the consequence
//! is certain and irreversible. Everything that merely *predicts* trouble
//! (battery, RAM, VRAM, temperature, lid) warns once and lets the session run.

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    Silent,
    Warn,
    Block,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Finding {
    pub code: &'static str,
    pub level: Level,
    pub message: String,
}

impl Finding {
    fn new(code: &'static str, level: Level, message: impl Into<String>) -> Self {
        Self { code, level, message: message.into() }
    }
}

#[derive(Debug, Clone)]
pub struct Thresholds {
    pub battery_block_pct: u8,
    pub battery_warn_pct: u8,
    pub ram_block_mb: u32,
    pub ram_warn_mb: u32,
    pub vram_block_mb: u32,
    pub vram_warn_mb: u32,
    pub temp_warn_c: f32,
    pub temp_sustain_secs: u32,
}

impl Default for Thresholds {
    fn default() -> Self {
        // Tuned so that none of these fire on an 8 GiB / 4 GiB-VRAM laptop in
        // ordinary use. A guard that fires often is a design bug, not a feature.
        Self {
            battery_block_pct: 5,
            battery_warn_pct: 15,
            ram_block_mb: 200,
            ram_warn_mb: 500,
            vram_block_mb: 80,
            vram_warn_mb: 150,
            temp_warn_c: 96.0,
            temp_sustain_secs: 60,
        }
    }
}

/// Evaluate pre-session guards. `temp_over_secs` is how long the temperature has
/// already been above the threshold, measured by the caller.
pub fn pre_session(
    m: &super::machine::Machine,
    t: &Thresholds,
    temp_over_secs: u32,
) -> Vec<Finding> {
    let mut out = Vec::new();

    let battery_on_discharge = if m.on_ac { None } else { m.battery_pct };
    if let Some(pct) = battery_on_discharge {
        if pct <= t.battery_block_pct {
            out.push(Finding::new(
                "battery_block",
                Level::Block,
                format!("Pin còn {pct}% và chưa cắm sạc — cắm sạc rồi thử lại."),
            ));
        } else if pct <= t.battery_warn_pct {
            out.push(Finding::new(
                "battery_warn",
                Level::Warn,
                format!("Đang chạy pin ({pct}%) — máy có thể ngủ giữa phiên."),
            ));
        }
    }

    if m.ram_available_mb < t.ram_block_mb {
        out.push(Finding::new(
            "ram_block",
            Level::Block,
            format!("Máy chủ chỉ còn {} MB RAM trống.", m.ram_available_mb),
        ));
    } else if m.ram_available_mb < t.ram_warn_mb {
        out.push(Finding::new(
            "ram_warn",
            Level::Warn,
            format!("Còn {} MB RAM — có thể giật.", m.ram_available_mb),
        ));
    }

    if let Some(tc) = m.cpu_temp_c {
        if tc >= t.temp_warn_c && temp_over_secs >= t.temp_sustain_secs {
            out.push(Finding::new(
                "thermal_warn",
                Level::Warn,
                format!("Máy đang nóng ({tc:.0} °C) — hình có thể giật, kê máy cao hơn."),
            ));
        }
    }

    out
}

/// Post-measurement advice: cross-adapter is the one finding that changes the
/// plan rather than just being a warning, because lowering the preset does not
/// fix a staging copy.
pub fn topology(m: &super::machine::Machine) -> Vec<Finding> {
    let mut out = Vec::new();
    if m.cross_adapter() {
        let cap = m.capture().map(|a| a.name.as_str()).unwrap_or("?");
        let enc = m.encode().map(|a| a.name.as_str()).unwrap_or("?");
        out.push(Finding::new(
            "cross_adapter",
            Level::Warn,
            format!(
                "Capture ở {cap} nhưng encode ở {enc} — frame phải copy qua bộ nhớ hệ thống \
                 (~2–5 ms, 1 nhân CPU). Đổi encoder sang GPU của capture, hoặc chỉnh \
                 <gpu><friendlyname> trong vdd_settings.xml."
            ),
        ));
    }
    out
}

/// Highest level in a set of findings, or Silent when empty.
pub fn worst(findings: &[Finding]) -> Level {
    findings.iter().map(|f| f.level).max().unwrap_or(Level::Silent)
}

pub fn may_start(findings: &[Finding]) -> bool {
    worst(findings) < Level::Block
}
