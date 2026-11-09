//! Theme: font Be Vietnam Pro (nhúng sẵn), bảng màu, giao diện Tối/Sáng.

use std::sync::Arc;

use eframe::egui::{self, Color32, CornerRadius, FontFamily, Stroke, TextStyle};

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
    Stroke::new(1.0, c)
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

pub fn bold_text(s: impl Into<String>, size: f32, color: Color32) -> egui::RichText {
    egui::RichText::new(s.into())
        .size(size)
        .color(color)
        .family(FontFamily::Name("strong".into()))
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
    v.window_stroke = Stroke::new(1.0, border);
    v.menu_corner_radius = CornerRadius::same(10);
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
    v.selection.stroke = Stroke::new(1.0, ACCENT_SOFT);

    // ----- Widgets -----
    let corner = CornerRadius::same(7);
    {
        let w = &mut v.widgets.noninteractive;
        w.bg_fill = faint;
        w.weak_bg_fill = faint;
        w.bg_stroke = Stroke::new(1.0, border);
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0, text);
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
        w.bg_stroke = Stroke::new(1.0, border);
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0, text);
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
        w.bg_stroke = Stroke::new(1.0, if dark { ACCENT } else { ACCENT_SOFT });
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0, text);
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
        w.bg_stroke = Stroke::new(1.0, ACCENT);
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0, text);
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
        w.bg_stroke = Stroke::new(1.5, ACCENT);
        w.corner_radius = corner;
        w.fg_stroke = Stroke::new(1.0, text);
        w.expansion = 0.0;
    }

    let _ = weak_text; // (dùng gián tiếp qua Visuals::weak_text_color mặc định)
    v
}

/// Vẽ logo mini (rounded + dấu tick) vào một rect.
pub fn paint_logo(ui: &egui::Ui, rect: egui::Rect) {
    let p = ui.painter();
    p.rect_filled(rect, CornerRadius::same(7), ACCENT);
    let (cx, cy) = (rect.center().x, rect.center().y);
    let s = rect.height() / 26.0;
    let a = egui::pos2(cx - 6.0 * s, cy + 0.5 * s);
    let b = egui::pos2(cx - 1.5 * s, cy + 5.0 * s);
    let c = egui::pos2(cx + 6.5 * s, cy - 5.5 * s);
    p.line_segment([a, b], Stroke::new(2.6 * s, Color32::WHITE));
    p.line_segment([b, c], Stroke::new(2.6 * s, Color32::WHITE));
}
