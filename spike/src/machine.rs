//! Snapshot of the host machine. Everything here is *measured*, never guessed.
//! On Windows these fields come from DXGI + WMI + GetSystemPowerStatus;
//! for CI and for `--demo` they can be supplied by hand.

#[derive(Debug, Clone, PartialEq)]
pub struct Adapter {
    pub name: String,
    pub kind: AdapterKind,
    /// DXGI_ADAPTER_DESC1.DedicatedVideoMemory, in MiB.
    /// NOTE: never take this from WMI Win32_VideoController.AdapterRAM — it is a
    /// uint32 and overflows for cards with >= 4 GiB.
    pub vram_mb: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdapterKind {
    Integrated,
    Discrete,
    /// Microsoft Basic Render Driver (vendor 0x1414) — always present, never usable
    /// as a capture source: it reports zero outputs.
    BasicRender,
}

impl Adapter {
    pub fn is_usable(&self) -> bool {
        self.kind != AdapterKind::BasicRender
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Machine {
    pub hostname: String,
    pub is_laptop: bool,
    pub adapters: Vec<Adapter>,
    /// Adapter that owns the monitor we intend to capture.
    pub capture_adapter: Option<String>,
    /// Adapter the chosen encoder will run on. `None` = unknown / same as capture.
    pub encode_adapter: Option<String>,
    pub ram_available_mb: u32,
    pub on_ac: bool,
    pub battery_pct: Option<u8>,
    pub cpu_temp_c: Option<f32>,
    pub wifi_ssid: Option<String>,
}

impl Machine {
    pub fn adapter(&self, name: &str) -> Option<&Adapter> {
        self.adapters.iter().find(|a| a.name == name)
    }

    pub fn capture(&self) -> Option<&Adapter> {
        self.capture_adapter.as_deref().and_then(|n| self.adapter(n))
    }

    pub fn encode(&self) -> Option<&Adapter> {
        self.encode_adapter
            .as_deref()
            .and_then(|n| self.adapter(n))
            .or_else(|| self.capture())
    }

    /// The single most important question on a hybrid machine: are capture and
    /// encode on the same DXGI adapter? If not, every frame is copied through
    /// system memory (1.76 GB/s at 1440p60) or negociation fails outright.
    pub fn cross_adapter(&self) -> bool {
        match (self.capture(), self.encode()) {
            (Some(c), Some(e)) => c.name != e.name,
            _ => false,
        }
    }

    pub fn total_vram_mb(&self) -> u32 {
        self.adapters
            .iter()
            .filter(|a| a.is_usable())
            .map(|a| a.vram_mb)
            .max()
            .unwrap_or(0)
    }

    /// Upper bound for the virtual display, from dedicated VRAM on the *capture*
    /// adapter. Policy, not a hard limit — the real limit is the scanout
    /// bandwidth of the mode (Pascal has no DSC).
    pub fn virtual_display_ceiling(&self) -> &'static str {
        let vram = self
            .capture()
            .map(|a| a.vram_mb)
            .unwrap_or_else(|| self.total_vram_mb());
        match vram {
            0..=2999 => "1920x1200@60",
            3000..=6143 => "2560x1440@60",
            _ => "3840x2160@60",
        }
    }

    /// A laptop panel is normally 1080p; offering a taller virtual display only
    /// costs 78% more pixels and confuses DPI.
    pub fn laptop_ceiling(&self) -> &'static str {
        if self.is_laptop {
            "1920x1080@60"
        } else {
            self.virtual_display_ceiling()
        }
    }
}
