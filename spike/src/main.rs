// Use the library crate instead of `mod`-including the sources, so the binary and
// the tests compile the *same* code and `dead_code` is judged once, for `pub` items.
use rd_spike_lib::machine::{Adapter, AdapterKind, Machine};
use rd_spike_lib::{pipeline, policy};
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
}
