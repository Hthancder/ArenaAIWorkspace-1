// Use the library crate instead of `mod`-including the sources, so the binary and
// the tests compile the *same* code and `dead_code` is judged once, for `pub` items.
use rd_spike_lib::machine::{Adapter, AdapterKind, Machine};
use rd_spike_lib::security::{auth, crypto, gate, input, refresh, token, window};
use rd_spike_lib::{pipeline, policy, DEVIATIONS};
use policy::Level;

fn demo_machine() -> Machine {
    // The host this spec is being written against: Dell Inspiron 7467,
    // i5-7300HQ + HD 630 + GTX 1050 4 GiB, 8 GiB RAM, laptop.
    Machine {
        hostname: "inspiron-7467".into(),
        is_laptop: true,
        adapters: vec![
            Adapter { name: "Intel HD Graphics 630".into(), kind: AdapterKind::Integrated, vram_mb: 1024 },
            Adapter { name: "NVIDIA GeForce GTX 1050".into(), kind: AdapterKind::Discrete, vram_mb: 4096 },
            Adapter { name: "Microsoft Basic Render Driver".into(), kind: AdapterKind::BasicRender, vram_mb: 0 },
        ],
        capture_adapter: Some("Intel HD Graphics 630".into()),
        encode_adapter: Some("Intel HD Graphics 630".into()),
        ram_available_mb: 4200,
        on_ac: true,
        battery_pct: Some(100),
        cpu_temp_c: Some(64.0),
        wifi_ssid: Some("nha-5g".into()),
        // Comfortably above the 300 MB banner: the demo must not fake a warning.
        free_vram_mb: Some(3600),
    }
}

fn main() {
    // A real build reads DXGI / power-status / thermal counters here. Until that
    // Windows-only layer lands, the spike prints a known-good machine so the
    // pipeline strings and guard decisions can be reviewed in CI logs.
    let demo = std::env::args().any(|a| a == "--demo");
    let m = demo_machine();
    if !demo {
        eprintln!("note: using built-in demo machine (pass --demo to silence this)");
    }

    let t = policy::Thresholds::default();
    let mut findings = policy::pre_session(&m, &t, 0);
    findings.extend(policy::topology(&m));
    findings.extend(policy::vram_low(&m, &t));

    let p = if m.is_laptop {
        pipeline::Profile::laptop_default()
    } else {
        pipeline::Profile::desktop_default()
    };

    println!("host      : {}", m.hostname);
    println!("ceiling   : {}", m.laptop_ceiling());
    println!("encoder   : {:?}", p.encoder);
    println!("cross-adaptr: {}", m.cross_adapter());
    println!();
    println!("--- desktop ---");
    println!("{}", pipeline::desktop(&p));
    println!();
    println!("--- camera (room view) ---");
    println!("{}", pipeline::camera(&p));
    println!();
    println!("--- mic ---");
    println!("{}", pipeline::mic(&p));
    println!();
    println!("--- guards ---");
    if findings.is_empty() {
        println!("(none)");
    }
    for f in &findings {
        let tag = match f.level {
            Level::Block => "BLOCK",
            Level::Warn => "warn ",
            Level::Silent => "info ",
        };
        println!("[{tag}] {:<14} {}", f.code, f.message);
    }
    println!();
    println!("may start session: {}", policy::may_start(&findings));

    security_summary();
}

/// §57 — in ra những gì tầng bảo mật **quyết định** với chính máy này, để đọc
/// trong log CI bằng mắt thay vì tin vào lời hứa. Không in token nào.
fn security_summary() {
    println!();
    println!("--- security (§41 / §54.5) ---");

    let mut entropy = crypto::FixedEntropy::new(0xbeef);
    let passwords = auth::PasswordFile::new(
        "owner",
        auth::StoredPassword::new("correct horse battery", [1u8; 16], 1),
    );
    let issuer = token::TokenIssuer::new(token::TokenConfig::default(), vec![0u8; 32])
        .unwrap_or_else(|e| {
            eprintln!("token issuer: {e}");
            std::process::exit(1)
        });
    let mut auth_service = gate::Auth::new(
        passwords,
        issuer,
        auth::Lockout::default(),
    );
    let now = 1_700_000_000_000u64;
    match auth_service.login("127.0.0.1", "owner", "correct horse battery", "demo", now, &mut entropy) {
        Ok(session) => {
            let access_ttl_min = token::TokenConfig::default().access_ttl_ms / 60_000;
            let refresh_days = token::TokenConfig::default().refresh_ttl_ms / 86_400_000;
            println!(
                "[ok   ] login              access {access_ttl_min} min · refresh {refresh_days} ngày · sub={}",
                session.claims.sub
            );
            println!("[ok   ] debug render       {:?}", session);
        }
        Err(e) => println!("[BLOCK] login             {e:?}"),
    }

    for host in ["127.0.0.1", "0.0.0.0"] {
        match gate::Transport::for_bind(host, false) {
            Ok(t) => println!("[ok   ] bind {host:<11} {t:?} (loopback, không qua dây)"),
            Err(e) => println!("[BLOCK] bind {host:<11} {e}"),
        }
    }
    println!(
        "[ok   ] headers            X-Frame-Options={} · CSP frame-ancestors 'none'",
        gate::security_headers(gate::Transport::Tls)[0].1
    );

    let mut registry = window::WindowRegistry::default();
    let (snap, list) = registry.publish(
        vec![
            window::WindowEntry {
                wid: "a1b2".into(),
                title: "Toàn bộ màn hình".into(),
                app: "desktop".into(),
                pid: 0,
                minimized: false,
                elevated: false,
                capture_blocked: false,
            },
            window::WindowEntry {
                wid: "c3d4".into(),
                title: "Chrome".into(),
                app: "chrome.exe".into(),
                pid: 4242,
                minimized: false,
                elevated: false,
                capture_blocked: false,
            },
        ],
        now,
        &mut entropy,
        "owner",
    );
    println!("[ok   ] windows            {} wid trong snapshot {snap}", list.len());
    println!(
        "[BLOCK] wid ngoài danh sách {:?} → HTTP {}",
        registry.authorize(&snap, "dead", now).unwrap_err(),
        window::WindowError::UnknownWindow.status()
    );

    let mut sanitizer = input::InputSanitizer::default();
    sanitizer.accept_key(input::VK_LWIN, true, 0, true, now).ok();
    println!(
        "[BLOCK] Win+L             {:?}",
        sanitizer.accept_key(input::VK_L, true, 0, true, now + 1).unwrap_err()
    );
    println!(
        "[BLOCK] Ctrl+Alt+Del      {:?}",
        sanitizer
            .accept_key(input::VK_DELETE, true, input::FLAG_CTRL | input::FLAG_ALT, false, now + 2)
            .unwrap_err()
    );
    let ups = sanitizer.release_all(now + 3);
    println!("[ok   ] release_all        {} KEYUP (idempotent)", ups.len());

    let mut timer = refresh::CleanupTimer::default();
    timer.acquire(refresh::Resource::Encoder, now);
    println!("[ok   ] cleanup            {:?} sau F5", timer.release(refresh::Resource::Encoder, now));

    println!();
    println!("--- deviations từ spec (§57) ---");
    for d in DEVIATIONS {
        println!("[{}] {} → {}", d.id, d.spec_says, d.code_does);
    }
}
