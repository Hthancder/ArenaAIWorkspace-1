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

// ============================================================================
// §41.10 — 14 kiểm chứng bảo mật, chạy như một phần của `cargo test`.
// Đây là phần **biến §41 từ chương thành cổng**: nếu một trong các assert
// dưới đây đỏ thì đó không phải "test hỏng", mà là một luật [CỨNG] đã bị phá.
// ============================================================================
mod security_conformance {
    use rd_spike_lib::security::auth::{Lockout, LockoutConfig, PasswordFile, StoredPassword};
    use rd_spike_lib::security::crypto::FixedEntropy;
    use rd_spike_lib::security::gate::{
        mutation_is_same_origin, security_headers, session_cookie, url_carries_token, Auth,
        CSRF_HEADER, CSRF_VALUE, RateLimiter, Transport,
    };
    use rd_spike_lib::security::input::{InputSanitizer, FLAG_ALT, FLAG_CTRL, VK_DELETE, VK_LWIN, VK_L};
    use rd_spike_lib::security::refresh::{CleanupTimer, Resource};
    use rd_spike_lib::security::token::{RefreshOutcome, RefreshStore, TokenConfig, TokenIssuer};
    use rd_spike_lib::security::window::{WindowEntry, WindowRegistry};

    const T0: u64 = 1_700_000_000_000;

    fn auth() -> Auth {
        let passwords =
            PasswordFile::new("owner", StoredPassword::new("correct horse", [4u8; 16], 1));
        let tokens = TokenIssuer::new(TokenConfig::default(), vec![9u8; 32]).unwrap();
        Auth::new(passwords, tokens, Lockout::new(LockoutConfig::default()))
    }

    #[test]
    fn c1_wid_outside_the_returned_list_is_403() {
        let mut e = FixedEntropy::new(11);
        let mut registry = WindowRegistry::default();
        let (snap, _) = registry.publish(
            vec![WindowEntry {
                wid: "00ff".into(),
                title: "Notepad".into(),
                app: "notepad.exe".into(),
                pid: 1,
                minimized: false,
                elevated: false,
                capture_blocked: false,
            }],
            T0,
            &mut e,
            "owner",
        );
        let err = registry.authorize(&snap, "beef", T0).unwrap_err();
        assert_eq!(err.status(), 403);
    }

    #[test]
    fn c2_someone_elses_sid_is_refused_on_every_route() {
        let mut e = FixedEntropy::new(11);
        let mut a = auth();
        let session = a
            .login("10.0.0.2", "owner", "correct horse", "laptop", T0, &mut e)
            .unwrap();
        assert!(a.authorize(&session.access, "owner", T0 + 1).is_ok());
        assert!(a.authorize(&session.access, "intruder", T0 + 1).is_err());
    }

    #[test]
    fn c4_post_without_the_custom_header_is_refused() {
        assert!(!mutation_is_same_origin("POST", &[], "127.0.0.1:8443"));
        assert!(mutation_is_same_origin(
            "POST",
            &[(CSRF_HEADER, CSRF_VALUE), ("origin", "https://127.0.0.1:8443")],
            "127.0.0.1:8443"
        ));
    }

    #[test]
    fn c5_clickjacking_headers_are_present() {
        let headers = security_headers(Transport::Tls);
        assert!(headers.iter().any(|(k, v)| *k == "X-Frame-Options" && v == "DENY"));
        assert!(headers
            .iter()
            .any(|(k, v)| *k == "Content-Security-Policy" && v.contains("frame-ancestors 'none'")));
    }

    #[test]
    fn c6_refresh_reuse_revokes_the_whole_chain() {
        let mut e = FixedEntropy::new(12);
        let issuer = TokenIssuer::new(TokenConfig::default(), vec![9u8; 32]).unwrap();
        let mut store = RefreshStore::new(TokenConfig::default());
        let first = store.issue("owner", "d", T0, &mut e);
        let RefreshOutcome::Rotated(second) =
            store.rotate(&first, "d", T0 + 1, &issuer, "owner", &mut e)
        else {
            panic!("rotate");
        };
        assert!(matches!(
            store.rotate(&first, "d", T0 + 2, &issuer, "owner", &mut e),
            RefreshOutcome::Reused { .. }
        ));
        assert_eq!(
            store.rotate(&second.refresh, "d", T0 + 3, &issuer, "owner", &mut e),
            RefreshOutcome::Revoked(rd_spike_lib::security::token::RevokedReason::ReuseDetected)
        );
    }

    #[test]
    fn c8_tls_cannot_be_switched_off_and_tokens_never_travel_in_a_url() {
        assert!(Transport::for_bind("0.0.0.0", false).is_err());
        assert!(url_carries_token("/s/x?access=abc"));
        // Cookie refresh: JS không đọc được.
        assert!(session_cookie("lantern_rt", "x", 60).contains("HttpOnly"));
    }

    #[test]
    fn c9_windows_metadata_is_rate_limited_to_thirty_per_minute() {
        // §41.4 T18: /api/windows 30/phút. Đây là con số trong test của spec.
        let mut rl = RateLimiter::new();
        for i in 0..30 {
            assert!(rl.check("windows:owner", 30, 60_000, T0 + i));
        }
        assert!(!rl.check("windows:owner", 30, 60_000, T0 + 30));
    }

    #[test]
    fn c11_coordinates_cannot_leave_the_screen_and_win_lock_is_blocked() {
        // Toạ độ là u16 ở kiểu dữ liệu ⇒ không có API nào nhận i32.
        let mut input = InputSanitizer::default();
        input.accept_key(VK_LWIN, true, 0, true, T0).unwrap();
        assert!(input.accept_key(VK_L, true, 0, true, T0 + 1).is_err());
        assert!(input
            .accept_key(VK_DELETE, true, FLAG_CTRL | FLAG_ALT, false, T0 + 2)
            .is_err());
    }

    #[test]
    fn c12_nothing_in_a_debug_rendering_leaks_a_token() {
        let mut e = FixedEntropy::new(13);
        let mut a = auth();
        let session = a
            .login("10.0.0.3", "owner", "correct horse", "laptop", T0, &mut e)
            .unwrap();
        let rendered = format!("{session:?}");
        assert!(!rendered.contains(&session.access));
        assert!(!rendered.contains(&session.refresh));
        assert!(rendered.contains("redacted"));
    }

    #[test]
    fn c14_display_is_kept_after_close_so_a_refresh_does_not_break_it() {
        // §42.15 #4 + §9.2.2 — display ảo KHÔNG bị dọn theo nhịp 5 s.
        let mut timer = CleanupTimer::default();
        timer.acquire(Resource::VirtualDisplay, T0);
        timer.release(Resource::VirtualDisplay, T0);
        assert!(timer.tick(T0 + 60_000).is_empty());
        // Nhưng encoder/cable/d3d thì có.
        timer.acquire(Resource::Encoder, T0);
        timer.release(Resource::Encoder, T0 + 1);
        assert_eq!(timer.tick(T0 + 5_001), vec![Resource::Encoder]);
    }
}
