//! Theme: font Be Vietnam Pro (nhúng sẵn), bảng màu, giao diện Tối/Sáng.

use std::sync::Arc;

use eframe::egui::{self, Color32, CornerRadius, FontFamily, Margin, Stroke, TextStyle};

// ------- Bảng màu dùng chung -------
pub const ACCENT: Color32 = Color32::from_rgb(99, 102, 241); // indigo 500
pub const ACCENT_SOFT: Color32 = Color32::from_rgb(129, 140, 248); // indigo 400
pub const DANGER: Color32 = Color32::from_rgb(239, 68, 68);
pub const WARN: Color32 = Color32::from_rgb(245, 158, 11);
pub const OK: Color32 = Color32::from_rgb(16, 185, 129);
pub const STAR: Color32 = Color32::from_rgb(250, 204, 21);
pub const BLUE: Color32 = Color32::from_rgb(59, 130, 246);

pub const CARD_DARK: Color32 = Color32::from_rgb(22, 27, 36);
pub const CARD_LIGHT: Color32 = Color32::from_rgb(255, 255, 255);

/// Màu bảng điều hướng theo từng view.
pub fn view_color(v: crate::models::View) -> Color32 {
    use crate::models::View::*;
    match v {
        Inbox => Color32::from_rgb(148, 163, 184),
        Today => WARN,
        Upcoming => BLUE,
        Starred => STAR,
        Completed => OK,
        Trash => DANGER,
        Stats => ACCENT,
        List(_) => ACCENT_SOFT,
    }
}

/// Nền thẻ/khung nổi (theo theme hiện tại của `ui`).
pub fn card_fill(ui: &egui::Ui) -> Color32 {
    if ui.visuals().dark_mode {
        CARD_DARK
    } else {
        CARD_LIGHT
    }
}

pub fn card_stroke(ui: &egui::Ui) -> Stroke {
    let c = if ui.visuals().dark_mode {
        Color32::from_rgb(42, 49, 63)
    } else {
        Color32::from_rgb(226, 230, 238)
    };
    Stroke::new(1.0f32, c)
}

/// Trộn hai màu (theo gamma).
pub fn mix(a: Color32, b: Color32, t: f32) -> Color32 {
    a.lerp_to_gamma(b, t.clamp(0.0, 1.0))
}

/// Nền badge màu trên nền tối/sáng.
pub fn badge_bg(ui: &egui::Ui, color: Color32) -> Color32 {
    if ui.visuals().dark_mode {
        color.gamma_multiply(0.17)
    } else {
        mix(color, Color32::WHITE, 0.84)
    }
}

/// Chữ đậm (dùng font SemiBold nhúng).
pub fn bold(size: f32, color: Color32) -> egui::RichText {
    egui::RichText::new("")
        .size(size)
        .color(color)
        .family(FontFamily::Name("strong".into()))
}

/// Khung thẻ thống nhất (nền + viền + bo góc + lề trong).
pub fn card_frame(ui: &egui::Ui) -> egui::Frame {
    egui::Frame::new()
        .fill(card_fill(ui))
        .stroke(card_stroke(ui))
        .corner_radius(CornerRadius::same(12))
        .inner_margin(Margin {
            left: 14,
            right: 14,
            top: 12,
            bottom: 12,
        })
}

/// Nhãn mục nhỏ chữ hoa mờ (HẠN CHÓT, GHI CHÚ…).
pub fn section_label(ui: &mut egui::Ui, text: &str) {
    ui.label(
        egui::RichText::new(text)
            .size(10.5)
            .color(ui.visuals().weak_text_color())
            .family(FontFamily::Name("strong".into())),
    );
}

/// Nút bấm "chủ đạo" (nền accent, chữ trắng đậm).
pub fn primary_button(text: impl Into<String>) -> egui::Button<'static> {
    egui::Button::new(
        egui::RichText::new(text.into())
            .color(Color32::WHITE)
            .family(FontFamily::Name("strong".into())),
    )
    .fill(ACCENT)
    .corner_radius(CornerRadius::same(8))
}

/// Ghép icon Phosphor + chữ thành 1 LayoutJob (dùng cho button/label trộn font).
pub fn ic_job(glyph: &str, label: &str, color: Color32) -> egui::text::LayoutJob {
    let mut job = egui::text::LayoutJob::default();
    job.append(
        glyph,
        0.0,
        egui::TextFormat {
            font_id: egui::FontId::new(14.0, FontFamily::Name("icons".into())),
            color,
            ..Default::default()
        },
    );
    job.append(
        &format!(" {label}"),
        0.0,
        egui::TextFormat {
            font_id: egui::FontId::new(13.0, FontFamily::Name("strong".into())),
            color,
            ..Default::default()
        },
    );
    job
}

/// Nút chủ đạo có icon Phosphor + nhãn (2 font trong cùng 1 dòng).
pub fn primary_button_icon(glyph: &str, label: &str) -> egui::Button<'static> {
    let mut job = egui::text::LayoutJob::default();
    job.append(
        glyph,
        0.0,
        egui::TextFormat {
            font_id: egui::FontId::new(14.0, FontFamily::Name("icons".into())),
            color: Color32::WHITE,
            ..Default::default()
        },
    );
    job.append(
        &format!(" {label}"),
        0.0,
        egui::TextFormat {
            font_id: egui::FontId::new(13.0, FontFamily::Name("strong".into())),
            color: Color32::WHITE,
            ..Default::default()
        },
    );
    egui::Button::new(job)
        .fill(ACCENT)
        .corner_radius(CornerRadius::same(8))
}

/// Badge đếm tròn bên phải hàng sidebar.
pub fn count_pill(ui: &mut egui::Ui, n: usize, active: bool, dot: Color32) {
    if n == 0 {
        return;
    }
    let fill = if active {
        dot.gamma_multiply(if ui.visuals().dark_mode { 0.35 } else { 0.25 })
    } else {
        badge_bg(ui, dot)
    };
    egui::Frame::new()
        .fill(fill)
        .corner_radius(CornerRadius::same(9))
        .inner_margin(Margin {
            left: 7,
            right: 7,
            top: 1,
            bottom: 1,
        })
        .show(ui, |ui| {
            let c = if active { Color32::WHITE } else { dot };
            ui.label(bold_text(n.to_string(), 11.0, c));
        });
}

pub fn bold_text(s: impl Into<String>, size: f32, color: Color32) -> egui::RichText {
    egui::RichText::new(s.into())
        .size(size)
        .color(color)
        .family(FontFamily::Name("strong".into()))
}

// ================================================================
//  Icon + Liquid glass (Phosphor / gradient / shimmer)
// ================================================================

/// Chữ icon Phosphor nét thường.
pub fn ic(text: &str) -> egui::RichText {
    egui::RichText::new(text).family(FontFamily::Name("icons".into()))
}

/// Chữ icon Phosphor nét đặc (fill).
pub fn icf(text: &str) -> egui::RichText {
    egui::RichText::new(text).family(FontFamily::Name("icons-fill".into()))
}

/// Nền glass trong suốt theo theme.
pub fn glass_fill(dark: bool) -> Color32 {
    if dark {
        Color32::from_rgba_unmultiplied(15, 17, 26, 172)
    } else {
        Color32::from_rgba_unmultiplied(255, 255, 255, 178)
    }
}

/// Nền glass đục hơn (panel chi tiết — cần đọc nhiều chữ).
pub fn glass_fill_strong(dark: bool) -> Color32 {
    if dark {
        Color32::from_rgba_unmultiplied(13, 15, 23, 222)
    } else {
        Color32::from_rgba_unmultiplied(255, 255, 255, 232)
    }
}

/// Frame kính mờ cho panel.
pub fn glass_frame(dark: bool, strong: bool) -> egui::Frame {
    egui::Frame::new().fill(if strong {
        glass_fill_strong(dark)
    } else {
        glass_fill(dark)
    })
}

/// Vẽ hiệu ứng kính lên rect: viền phản quang, sáng ở cạnh trên, bóng ở cạnh dưới.
pub fn paint_glass(p: &egui::Painter, rect: egui::Rect, radius: CornerRadius, dark: bool) {
    if rect.width() < 8.0 || rect.height() < 8.0 {
        return;
    }
    let top = CornerRadius {
        nw: radius.nw,
        ne: radius.ne,
        sw: 0,
        se: 0,
    };
    let bot = CornerRadius {
        nw: 0,
        ne: 0,
        sw: radius.sw,
        se: radius.se,
    };
    // ánh sáng phía trên (specular)
    p.rect_filled(
        egui::Rect::from_min_size(
            egui::pos2(rect.min.x + 5.0, rect.min.y),
            egui::vec2(rect.width() - 10.0, 1.0),
        ),
        top,
        Color32::from_white_alpha(if dark { 92 } else { 240 }),
    );
    p.rect_filled(
        egui::Rect::from_min_size(
            egui::pos2(rect.min.x + 14.0, rect.min.y + 1.5),
            egui::vec2(rect.width() - 28.0, 1.0),
        ),
        CornerRadius::ZERO,
        Color32::from_white_alpha(if dark { 44 } else { 156 }),
    );
    // bóng dưới
    p.rect_filled(
        egui::Rect::from_min_size(
            egui::pos2(rect.min.x + 8.0, rect.max.y - 2.0),
            egui::vec2(rect.width() - 16.0, 2.0),
        ),
        bot,
        Color32::from_black_alpha(if dark { 78 } else { 30 }),
    );
    // viền quanh
    p.rect_stroke(
        rect,
        radius,
        Stroke::new(
            1.0f32,
            Color32::from_white_alpha(if dark { 34 } else { 140 }),
        ),
        egui::StrokeKind::Inside,
    );
}

/// Đường sáng trên đỉnh card — strength 0..1 (tăng khi hover).
pub fn paint_specular(p: &egui::Painter, rect: egui::Rect, radius: CornerRadius, strength: f32) {
    if strength <= 0.02 || rect.width() < 12.0 {
        return;
    }
    let top = CornerRadius {
        nw: radius.nw,
        ne: radius.ne,
        sw: 0,
        se: 0,
    };
    for (dy, a) in [(0.0f32, 98u8), (1.3, 54), (2.6, 22)] {
        let a = (a as f32 * strength).round().clamp(1.0, 255.0) as u8;
        p.rect_filled(
            egui::Rect::from_min_size(
                egui::pos2(rect.min.x + 7.0, rect.min.y + dy),
                egui::vec2(rect.width() - 14.0, 1.0),
            ),
            top,
            Color32::from_white_alpha(a),
        );
    }
}

/// Dải sáng lướt ngang (tính bằng giây — truyền `self.boot.elapsed()`).
pub fn shimmer(ui: &egui::Ui, rect: egui::Rect, t: f32, dark: bool) {
    let w = rect.width();
    if w < 60.0 || rect.height() < 8.0 {
        return;
    }
    let period = 3.6_f32;
    let phase = (t % period) / period;
    let bw = (w * 0.34).min(170.0);
    let x = rect.min.x - bw + phase * (w + 2.0 * bw);
    let a0 = if dark { 20.0f32 } else { 60.0 };
    let steps = 10;
    let p = ui.painter().with_clip_rect(rect.expand(-1.0));
    for i in 0..steps {
        let f = i as f32 / steps as f32;
        let shape = (1.0 - (2.0 * f - 1.0).abs().powf(1.5)).max(0.0);
        let a = (a0 * shape).round() as u8;
        if a == 0 {
            continue;
        }
        p.rect_filled(
            egui::Rect::from_min_size(
                egui::pos2(x + f * bw, rect.min.y),
                egui::vec2(bw / steps as f32 + 0.6, rect.height()),
            ),
            CornerRadius::ZERO,
            Color32::from_white_alpha(a),
        );
    }
    // giữ animation chạy khi còn nhìn thấy shimmer
    ui.ctx().request_repaint();
}

/// Đám mây gradient tròn (các vòng đồng tâm, alpha tăng dần vào tâm).
fn blob(p: &egui::Painter, c: egui::Pos2, r: f32, rgb: [u8; 3], a: u8) {
    for i in 0..6 {
        let k = i as f32 / 5.0;
        let rr = r * (1.0 - 0.70 * k);
        let aa = (a as f32 * (0.20 + 0.22 * k)).round().min(255.0) as u8;
        p.circle_filled(c, rr, Color32::from_rgba_unmultiplied(rgb[0], rgb[1], rgb[2], aa));
    }
}

/// Nền aurora toàn cửa sổ — vẽ ở layer Background, các panel kính mờ nằm đè lên.
pub fn paint_wallpaper(ctx: &egui::Context, rect: egui::Rect) {
    if rect.width() < 4.0 || rect.height() < 4.0 {
        return;
    }
    let style = ctx.style();
    let dark = style.visuals.dark_mode;
    let base = style.visuals.panel_fill;
    let p = ctx.layer_painter(egui::LayerId::background());
    p.rect_filled(rect, CornerRadius::ZERO, base);
    let w = rect.width();
    let h = rect.height();
    let pt = |fx: f32, fy: f32| egui::pos2(rect.min.x + w * fx, rect.min.y + h * fy);
    if dark {
        blob(&p, pt(0.10, 0.05), w * 0.34, [99, 102, 241], 52);
        blob(&p, pt(0.93, 0.24), w * 0.30, [129, 140, 248], 40);
        blob(&p, pt(0.74, 0.97), w * 0.36, [56, 189, 248], 30);
        blob(&p, pt(0.15, 0.90), w * 0.26, [244, 114, 182], 24);
    } else {
        blob(&p, pt(0.10, 0.05), w * 0.34, [99, 102, 241], 26);
        blob(&p, pt(0.93, 0.24), w * 0.30, [129, 140, 248], 22);
        blob(&p, pt(0.74, 0.97), w * 0.36, [56, 189, 248], 17);
        blob(&p, pt(0.15, 0.90), w * 0.26, [244, 114, 182], 14);
    }
}

/// Cài font + style + visuals một lần khi khởi động.
pub fn install(ctx: &egui::Context, dark: bool) {
    // ----- Font: Be Vietnam Pro (chuẩn cho tiếng Việt) -----
    let mut fonts = egui::FontDefinitions::default();
    fonts.font_data.insert(
        "BVP-Regular".to_owned(),
        Arc::new(egui::FontData::from_static(include_bytes!(
            "../../assets/fonts/BeVietnamPro-Regular.ttf"
        ))),
    );
    fonts.font_data.insert(
        "BVP-SemiBold".to_owned(),
        Arc::new(egui::FontData::from_static(include_bytes!(
            "../../assets/fonts/BeVietnamPro-SemiBold.ttf"
        ))),
    );
    // bộ icon Phosphor (MIT) — nét thường + nét đặc
    fonts.font_data.insert(
        "Phosphor".to_owned(),
        Arc::new(egui::FontData::from_static(include_bytes!(
            "../../assets/fonts/Phosphor-Regular.ttf"
        ))),
    );
    fonts.font_data.insert(
        "Phosphor-Fill".to_owned(),
        Arc::new(egui::FontData::from_static(include_bytes!(
            "../../assets/fonts/Phosphor-Fill.ttf"
        ))),
    );
    if let Some(v) = fonts.families.get_mut(&FontFamily::Proportional) {
        v.insert(0, "BVP-Regular".to_owned());
    }
    fonts
        .families
        .entry(FontFamily::Name("strong".into()))
        .or_insert_with(|| {
            vec![
                "BVP-SemiBold".to_owned(),
                "NotoEmoji-Regular".to_owned(),
                "emoji-icon-font".to_owned(),
            ]
        });
    fonts
        .families
        .entry(FontFamily::Name("icons".into()))
        .or_insert_with(|| vec!["Phosphor".to_owned()]);
    fonts
        .families
        .entry(FontFamily::Name("icons-fill".into()))
        .or_insert_with(|| vec!["Phosphor-Fill".to_owned()]);
    ctx.set_fonts(fonts);

    // ----- Spacing + text styles (áp cho cả 2 theme) -----
    ctx.all_styles_mut(|s| {
        s.spacing.item_spacing = egui::vec2(10.0, 7.0);
        s.spacing.button_padding = egui::vec2(10.0, 5.0);
        s.spacing.interact_size = egui::vec2(30.0, 22.0);
        s.spacing.indent = 18.0;
        s.spacing.window_margin = 10i8.into();
        s.spacing.menu_margin = 8i8.into();
        s.spacing.combo_width = 170.0;
        s.spacing.text_edit_width = 260.0;
        s.text_styles.insert(
            TextStyle::Body,
            egui::FontId::new(13.0, FontFamily::Proportional),
        );
        s.text_styles.insert(
            TextStyle::Button,
            egui::FontId::new(13.0, FontFamily::Proportional),
        );
        s.text_styles.insert(
            TextStyle::Small,
            egui::FontId::new(10.5, FontFamily::Proportional),
        );
        s.text_styles.insert(
            TextStyle::Heading,
            egui::FontId::new(19.0, FontFamily::Name("strong".into())),
        );
        s.animation_time = 0.08;
    });

    ctx.set_visuals_of(egui::Theme::Dark, build_visuals(true));
    ctx.set_visuals_of(egui::Theme::Light, build_visuals(false));
    set_active_theme(ctx, dark);
}

/// Chọn theme đang dùng (khóa theo lựa chọn của app, không phụ thuộc OS).
pub fn set_active_theme(ctx: &egui::Context, dark: bool) {
    ctx.set_theme(if dark {
        egui::ThemePreference::Dark
    } else {
        egui::ThemePreference::Light
    });
}

/// Xây `Visuals` tùy chỉnh.
pub fn build_visuals(dark: bool) -> egui::Visuals {
    let mut v = if dark {
        egui::Visuals::dark()
    } else {
        egui::Visuals::light()
    };
    v.dark_mode = dark;

    let text = if dark {
        Color32::from_rgb(228, 231, 238)
    } else {
        Color32::from_rgb(29, 33, 41)
    };
    let weak_text = if dark {
        Color32::from_rgb(138, 147, 164)
    } else {
        Color32::from_rgb(107, 114, 128)
    };
    let panel = if dark {
        Color32::from_rgb(15, 19, 26)
    } else {
        Color32::from_rgb(244, 246, 250)
    };
    let window = if dark {
        Color32::from_rgb(24, 29, 38)
    } else {
        Color32::WHITE
    };
    let border = if dark {
        Color32::from_rgb(42, 49, 63)
    } else {
        Color32::from_rgb(226, 230, 238)
    };
    let faint = if dark {
        Color32::from_rgb(30, 36, 48)
    } else {
        Color32::from_rgb(242, 244, 248)
    };
    let extreme = if dark {
        Color32::from_rgb(10, 13, 18)
    } else {
        Color32::from_rgb(236, 239, 245)
    };

    v.panel_fill = panel;
    v.window_fill = window;
    v.window_corner_radius = CornerRadius::same(12);
    v.window_stroke = Stroke::new(1.0f32, border);
    v.menu_corner_radius = CornerRadius::same(10);

    // bóng mềm cho cửa sổ / popup
    v.window_shadow = egui::Shadow {
        offset: [0, 8],
        blur: 24,
        spread: 0,
        color: Color32::from_black_alpha(if dark { 100 } else { 36 }),
    };
    v.popup_shadow = egui::Shadow {
        offset: [0, 4],
        blur: 14,
        spread: 0,
        color: Color32::from_black_alpha(if dark { 90 } else { 30 }),
    };
    v.hyperlink_color = ACCENT_SOFT;
    v.faint_bg_color = faint;
    v.extreme_bg_color = extreme;
    v.code_bg_color = extreme;
    v.button_frame = true;
    v.collapsing_header_frame = false;
    v.striped = false;
    v.clip_rect_margin = 3.0;

    v.selection.bg_fill = if dark {
        ACCENT.gamma_multiply(0.55)
    } else {
        ACCENT.gamma_multiply(0.30)
    };
    v.selection.stroke = Stroke::new(1.0f32, ACCENT_SOFT);

    // ----- Widgets -----
    let corner = CornerRadius::same(7);
    {
        let w = &mut v.widgets.noninteractive;
        w.bg_fill = faint;
        w.weak_bg_fill = faint;
        w.bg_stroke = Stroke::new(1.0f32, border);
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0f32, text);
        w.expansion = 0.0;
    }
    {
        let w = &mut v.widgets.inactive;
        w.bg_fill = if dark {
            Color32::from_rgb(30, 36, 48)
        } else {
            Color32::from_rgb(255, 255, 255)
        };
        w.weak_bg_fill = if dark {
            Color32::from_rgb(30, 36, 48)
        } else {
            Color32::from_rgb(246, 247, 250)
        };
        w.bg_stroke = Stroke::new(1.0f32, border);
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0f32, text);
        w.expansion = 0.0;
    }
    {
        let w = &mut v.widgets.hovered;
        w.bg_fill = if dark {
            Color32::from_rgb(41, 49, 66)
        } else {
            Color32::from_rgb(238, 241, 248)
        };
        w.weak_bg_fill = w.bg_fill;
        w.bg_stroke = Stroke::new(1.0f32, if dark { ACCENT } else { ACCENT_SOFT });
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0f32, text);
        w.expansion = 0.5;
    }
    {
        let w = &mut v.widgets.active;
        w.bg_fill = if dark {
            Color32::from_rgb(52, 62, 84)
        } else {
            Color32::from_rgb(228, 232, 242)
        };
        w.weak_bg_fill = w.bg_fill;
        w.bg_stroke = Stroke::new(1.0f32, ACCENT);
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0f32, text);
        w.expansion = 0.5;
    }
    {
        let w = &mut v.widgets.open;
        w.bg_fill = if dark {
            Color32::from_rgb(52, 62, 84)
        } else {
            Color32::from_rgb(228, 232, 242)
        };
        w.weak_bg_fill = w.bg_fill;
        w.bg_stroke = Stroke::new(1.5f32, ACCENT);
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0f32, text);
        w.expansion = 0.0;
    }

    let _ = weak_text; // (dùng gián tiếp qua Visuals::weak_text_color mặc định)
    v
}

/// Vẽ logo mini (rounded + dấu tick) vào một rect.
pub fn paint_logo(ui: &egui::Ui, rect: egui::Rect) {
    let p = ui.painter();
    let radius = ((rect.height() * 7.0 / 26.0) as u8).max(4);
    p.rect_filled(rect, CornerRadius::same(radius), ACCENT);
    let (cx, cy) = (rect.center().x, rect.center().y);
    let s = rect.height() / 26.0;
    let a = egui::pos2(cx - 6.0 * s, cy + 0.5 * s);
    let b = egui::pos2(cx - 1.5 * s, cy + 5.0 * s);
    let c = egui::pos2(cx + 6.5 * s, cy - 5.5 * s);
    p.line_segment([a, b], Stroke::new(2.6 * s, Color32::WHITE));
    p.line_segment([b, c], Stroke::new(2.6 * s, Color32::WHITE));
}
