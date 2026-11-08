//! The spec, turned into assertions.

use rd_spike_lib::machine::{Adapter, AdapterKind, Machine};
use rd_spike_lib::pipeline::{self, Encoder, Profile};
use rd_spike_lib::policy::{self, Level, Thresholds};

fn laptop() -> Machine {
    Machine {
        hostname: "inspiron".into(),
        is_laptop: true,
        adapters: vec![
            Adapter { name: "HD 630".into(), kind: AdapterKind::Integrated, vram_mb: 1024 },
            Adapter { name: "GTX 1050".into(), kind: AdapterKind::Discrete, vram_mb: 4096 },
            Adapter { name: "Basic".into(), kind: AdapterKind::BasicRender, vram_mb: 0 },
        ],
        capture_adapter: Some("HD 630".into()),
        encode_adapter: Some("HD 630".into()),
        ram_available_mb: 4200,
        on_ac: true,
        battery_pct: Some(100),
        cpu_temp_c: Some(60.0),
        wifi_ssid: None,
        free_vram_mb: Some(3600),
    }
}

#[test]
fn laptop_ceiling_is_1080p_not_1440p() {
    // §53.9 / §51.10: a 14" 1080p panel must not be given a 1440p virtual display.
    assert_eq!(laptop().laptop_ceiling(), "1920x1080@60");
}

#[test]
fn vram_ceiling_tiers() {
    let mut m = laptop();
    m.is_laptop = false;
    m.capture_adapter = Some("GTX 1050".into());
    m.encode_adapter = Some("GTX 1050".into());
    assert_eq!(m.virtual_display_ceiling(), "2560x1440@60");

    m.capture_adapter = Some("Basic".into());
    m.encode_adapter = None;
    assert_eq!(m.total_vram_mb(), 4096, "Basic Render must never win the max");
}

#[test]
fn same_adapter_is_not_cross() {
    assert!(!laptop().cross_adapter());
}

#[test]
fn cross_adapter_is_detected_and_warns() {
    let mut m = laptop();
    m.encode_adapter = Some("GTX 1050".into());
    assert!(m.cross_adapter());
    let f = policy::topology(&m);
    assert_eq!(f.len(), 1);
    assert_eq!(f[0].code, "cross_adapter");
    // Warn, not Block: a staging copy is slow, not fatal (§54.1).
    assert_eq!(f[0].level, Level::Warn);
    assert!(policy::may_start(&f));
}

#[test]
fn battery_15_percent_only_warns() {
    // This is the exact case the user pushed back on.
    let mut m = laptop();
    m.on_ac = false;
    m.battery_pct = Some(15);
    let f = policy::pre_session(&m, &Thresholds::default(), 0);
    assert!(policy::may_start(&f), "15% must not block");
    assert!(f.iter().any(|x| x.code == "battery_warn"));
    assert_eq!(policy::worst(&f), Level::Warn);
}

#[test]
fn battery_5_percent_blocks() {
    let mut m = laptop();
    m.on_ac = false;
    m.battery_pct = Some(5);
    m.ram_available_mb = 4000;
    let f = policy::pre_session(&m, &Thresholds::default(), 0);
    assert!(!policy::may_start(&f));
    assert!(f.iter().any(|x| x.code == "battery_block"));
}

#[test]
fn on_ac_never_warns_about_battery() {
    let mut m = laptop();
    m.battery_pct = Some(3);
    assert!(policy::pre_session(&m, &Thresholds::default(), 0).is_empty());
}

#[test]
fn ram_8gb_host_is_quiet() {
    let mut m = laptop();
    m.ram_available_mb = 4200;
    assert!(policy::pre_session(&m, &Thresholds::default(), 0).is_empty());
}

#[test]
fn thermal_needs_sustained_heat() {
    let mut m = laptop();
    m.cpu_temp_c = Some(97.0);
    assert!(policy::pre_session(&m, &Thresholds::default(), 10).is_empty(), "10s is not sustained");
    let f = policy::pre_session(&m, &Thresholds::default(), 61);
    assert_eq!(f.len(), 1);
    assert_eq!(f[0].level, Level::Warn);
}

#[test]
fn every_encoder_is_zero_latency() {
    let mut p = Profile::laptop_default();
    for e in [Encoder::Qsv, Encoder::Nvenc, Encoder::MediaFoundation] {
        p.encoder = e;
        let s = pipeline::desktop(&p);
        assert!(s.contains("b-frames=0") || s.contains("bframes=0"), "{s}");
        assert!(!s.contains("multipass"), "{s}");
        assert!(!s.contains("lookahead"), "{s}");
    }
}

#[test]
fn laptop_prefers_qsv() {
    // §53.2: iGPU is the better host GPU here — same adapter, dGPU stays cold.
    assert_eq!(Profile::laptop_default().encoder, Encoder::Qsv);
    assert_eq!(pipeline::Profile::desktop_default().encoder, Encoder::Nvenc);
}

#[test]
fn camera_and_mic_use_distinct_ssrc_and_payload_types() {
    let p = Profile::laptop_default();
    let v = pipeline::desktop(&p);
    let c = pipeline::camera(&p);
    let a = pipeline::mic(&p);
    assert_eq!(p.ssrc_video, 0x1000_0001);
    assert_ne!(p.ssrc_video, p.ssrc_camera);
    assert_ne!(p.ssrc_camera, p.ssrc_mic);
    assert!(v.contains("H264"));
    assert!(c.contains("1280") && c.contains("720"));
    assert!(a.contains("OPUS") && a.contains("rate=48000"));
}

#[test]
fn mic_is_not_loopback() {
    // We want the room, not the speakers — otherwise the far end hears itself.
    let s = pipeline::mic(&Profile::laptop_default());
    assert!(s.contains("loopback=false"));
}

#[test]
fn room_view_does_not_capture_desktop() {
    // §54.5: camera-only must not drag screen capture (and its heat) along.
    let c = pipeline::camera(&Profile::laptop_default());
    assert!(!c.contains("screencapture"));
    assert!(!c.contains("d3d11screencapturesrc"));
}

#[test]
fn capture_uses_dxgi_not_wgc() {
    // §52.1: on hybrid, the dxgi path derives the adapter from the monitor.
    let s = pipeline::desktop(&Profile::laptop_default());
    assert!(s.contains("capture-api=dxgi"));
    assert!(!s.contains("capture-api=wgc"));
}

#[test]
fn vram_low_is_a_banner_never_a_block() {
    // §54.2: a busy GPU costs frames, it does not lose data — so it may warn,
    // it may never block. This test exists so the field cannot come back.
    let mut m = laptop();
    m.free_vram_mb = Some(120);
    let t = Thresholds::default();
    let f = policy::vram_low(&m, &t).expect("120 MB < 300 MB must warn");
    assert_eq!(f.level, Level::Warn);
    assert!(policy::may_start(&[f]), "VRAM low must never block a session");

    m.free_vram_mb = Some(3600);
    assert!(policy::vram_low(&m, &t).is_none(), "3600 MB is fine");
    m.free_vram_mb = None;
    assert!(policy::vram_low(&m, &t).is_none(), "unmeasured must not guess");
}
