//! Taskora – ứng dụng quản lý công việc (to-do) cho Windows, viết bằng Rust + egui.

// Không hiện cửa sổ console ở bản Release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod models;
mod parser;
mod storage;
mod ui;

use app::TaskoraApp;
use eframe::egui;

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Taskora — Quản lý công việc")
            .with_icon(make_icon())
            .with_inner_size([1240.0, 800.0])
            .with_min_inner_size([940.0, 620.0]),
        centered: true,
        ..Default::default()
    };
    eframe::run_native(
        "Taskora",
        options,
        Box::new(|cc| Ok(Box::new(TaskoraApp::new(cc)))),
    )
}

/// Tạo icon cửa sổ 64×64 (rounded + dấu tick) – không cần tệp ngoài.
fn make_icon() -> eframe::egui::IconData {
    const S: u32 = 64;
    let mut rgba = vec![0u8; (S * S * 4) as usize];

    // hai đoạn của dấu tick
    let a = (18.0f32, 33.0);
    let b = (28.5, 43.5);
    let c = (47.0, 21.0);
    let half = 4.2f32;
    let radius = 13.0f32;
    let inset = 2.0f32;

    fn seg_dist(px: f32, py: f32, x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
        let vx = x2 - x1;
        let vy = y2 - y1;
        let wx = px - x1;
        let wy = py - y1;
        let len2 = vx * vx + vy * vy;
        let t = if len2 <= 1e-6 {
            0.0
        } else {
            ((wx * vx + wy * vy) / len2).clamp(0.0, 1.0)
        };
        let dx = px - (x1 + t * vx);
        let dy = py - (y1 + t * vy);
        (dx * dx + dy * dy).sqrt()
    }

    for y in 0..S {
        for x in 0..S {
            let fx = x as f32 + 0.5;
            let fy = y as f32 + 0.5;

            // rounded-rect SDF
            let hx = (S as f32) / 2.0 - inset;
            let cx = fx - (S as f32) / 2.0;
            let cy = fy - (S as f32) / 2.0;
            let qx = cx.abs() - (hx - radius);
            let qy = cy.abs() - (hx - radius);
            let outside = {
                let ax = qx.max(0.0);
                let ay = qy.max(0.0);
                (ax * ax + ay * ay).sqrt() + (qx.max(qy).min(0.0)) - radius
            };
            let aa = (0.5 - outside).clamp(0.0, 1.0);
            if aa <= 0.0 {
                continue;
            }

            // dấu tick
            let dseg = seg_dist(fx, fy, a.0, a.1, b.0, b.1)
                .min(seg_dist(fx, fy, b.0, b.1, c.0, c.1));
            let tick = (half + 0.7 - dseg).clamp(0.0, 1.0);

            // blend: nền indigo → trắng theo tick
            let br = 99.0f32;
            let bg = 102.0f32;
            let bb = 241.0f32;
            let r = br + (255.0 - br) * tick;
            let g = bg + (255.0 - bg) * tick;
            let bl = bb + (255.0 - bb) * tick;
            let alpha = aa;

            let i = ((y * S + x) * 4) as usize;
            rgba[i] = (r * alpha) as u8;
            rgba[i + 1] = (g * alpha) as u8;
            rgba[i + 2] = (bl * alpha) as u8;
            rgba[i + 3] = (alpha * 255.0) as u8;
        }
    }

    eframe::egui::IconData {
        rgba,
        width: S,
        height: S,
    }
}
