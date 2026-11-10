//! View Thống kê: thẻ số, biểu đồ cột 14 ngày, tiến độ theo danh sách.

use chrono::{Datelike, Duration as ChronoDuration, Local, NaiveDate};
use eframe::egui::{
    self, Align, Color32, CornerRadius, Frame, Layout, Margin, ProgressBar, Stroke,
};

use crate::app::TaskoraApp;
use crate::models::{today, Store};
use crate::ui::{icons, theme};

struct Stats {
    active: usize,
    done_today: usize,
    overdue: usize,
    streak: usize,
    /// (ngày, số việc xong) 14 ngày gần nhất, cũ → mới.
    series: Vec<(NaiveDate, i64)>,
    /// theo danh sách: (tên, màu, xong, tổng)
    lists: Vec<(String, Color32, usize, usize)>,
    /// theo thẻ: (tên thẻ, số việc đang làm)
    tags: Vec<(String, usize)>,
    /// tổng việc đã xong / tổng việc (không tính thùng rác)
    done_all: usize,
    total_all: usize,
}

fn compute(store: &Store, t: NaiveDate) -> Stats {
    let mut active = 0usize;
    let mut done_today = 0usize;
    let mut overdue = 0usize;
    let mut done_dates: std::collections::HashSet<NaiveDate> = std::collections::HashSet::new();

    for task in &store.tasks {
        if task.is_deleted() {
            continue;
        }
        if let Some(d) = task.completed_at {
            let dd = d.with_timezone(&Local).date_naive();
            done_dates.insert(dd);
            if dd == t {
                done_today += 1;
            }
        }
        if task.is_active() {
            active += 1;
            if let Some(d) = task.due {
                if d < t {
                    overdue += 1;
                }
            }
        }
    }

    // chuỗi ngày liên tiếp có việc xong (hôm nay chưa xong thì bắt đầu từ hôm qua)
    let mut streak = 0usize;
    let mut cursor = if done_dates.contains(&t) {
        Some(t)
    } else {
        t.pred_opt()
    };
    while let Some(d) = cursor {
        if done_dates.contains(&d) {
            streak += 1;
            cursor = d.pred_opt();
        } else {
            break;
        }
        if streak > 3650 {
            break;
        }
    }

    // biểu đồ 14 ngày (cũ → mới)
    let mut series = Vec::new();
    for i in (0..14).rev() {
        let d = t
            .checked_sub_signed(ChronoDuration::days(i))
            .unwrap_or(t);
        let n = store
            .tasks
            .iter()
            .filter(|x| {
                x.completed_at
                    .map(|c| c.with_timezone(&Local).date_naive() == d)
                    .unwrap_or(false)
            })
            .count() as i64;
        series.push((d, n));
    }

    let mut lists = Vec::new();
    for l in &store.lists {
        let total = store
            .tasks
            .iter()
            .filter(|x| !x.is_deleted() && x.list_id == Some(l.id))
            .count();
        let done = store
            .tasks
            .iter()
            .filter(|x| !x.is_deleted() && x.list_id == Some(l.id) && x.is_completed())
            .count();
        lists.push((
            l.name.clone(),
            Color32::from_rgb(l.color[0], l.color[1], l.color[2]),
            done,
            total,
        ));
    }

    // theo thẻ (chỉ việc đang làm, không tính rác/hoàn thành)
    let mut tag_map: std::collections::BTreeMap<String, usize> = std::collections::BTreeMap::new();
    for task in &store.tasks {
        if !task.is_active() {
            continue;
        }
        for tg in &task.tags {
            *tag_map.entry(tg.clone()).or_insert(0) += 1;
        }
    }
    let mut tags: Vec<(String, usize)> = tag_map.into_iter().collect();
    tags.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    tags.truncate(8);

    let done_all = store
        .tasks
        .iter()
        .filter(|x| !x.is_deleted() && x.is_completed())
        .count();
    let total_all = store.tasks.iter().filter(|x| !x.is_deleted()).count();

    Stats {
        active,
        done_today,
        overdue,
        streak,
        series,
        lists,
        tags,
        done_all,
        total_all,
    }
}

impl TaskoraApp {
    pub fn render_stats(&mut self, ui: &mut egui::Ui) {
        let (p_in, vr_in) = self.view_enter_head(ui);
        let t = today();
        let s = compute(&self.store, t);

        egui::ScrollArea::vertical()
            .id_salt("stats_scroll")
            .auto_shrink([false, false])
            .show(ui, |ui| {
                ui.add_space(10.0);
                let tc_h = ui.visuals().text_color();
                ui.horizontal(|ui| {
                    ui.label(theme::ic(icons::CHART_BAR).size(19.0).color(theme::ACCENT));
                    ui.label(theme::bold_text("Thống kê", 20.0, tc_h));
                });
                ui.weak("Bức tranh hoạt động của bạn");
                ui.add_space(12.0);

                // ----- 4 thẻ số -----
                ui.columns(4, |cols| {
                    let cards: [(&str, String, Color32); 4] = [
                        ("Đang làm", s.active.to_string(), theme::ACCENT_SOFT),
                        ("Xong hôm nay", s.done_today.to_string(), theme::OK),
                        ("Quá hạn", s.overdue.to_string(), theme::DANGER),
                        ("Chuỗi ngày", format!("{} ngày", s.streak), theme::STAR),
                    ];
                    for (col, (title, value, color)) in cols.iter_mut().zip(cards) {
                        let crsp = Frame::new()
                            .fill(theme::card_fill(col))
                            .stroke(theme::card_stroke(col))
                            .corner_radius(CornerRadius::same(12))
                            .inner_margin(Margin {
                                left: 14,
                                right: 14,
                                top: 12,
                                bottom: 12,
                            })
                            .show(col, |ui| {
                                ui.weak(title);
                                ui.add_space(2.0);
                                ui.label(theme::bold_text(value, 24.0, color));
                            });
                        // ánh sáng nhẹ trên đỉnh thẻ số
                        theme::paint_specular(
                            col.painter(),
                            crsp.response.rect,
                            CornerRadius::same(12),
                            0.55,
                        );
                    }
                });

                ui.add_space(14.0);

                // ----- dải tiến độ tổng hợp -----
                let done_total = s.done_all;
                let grand = s.total_all;
                let rate = if grand == 0 {
                    0.0
                } else {
                    done_total as f32 / grand as f32
                };
                let dark_h = ui.visuals().dark_mode;
                let hero_rsp = Frame::new()
                    .fill(if dark_h {
                        Color32::from_rgba_unmultiplied(99, 102, 241, 52)
                    } else {
                        Color32::from_rgba_unmultiplied(255, 255, 255, 224)
                    })
                    .stroke(egui::Stroke::new(
                        1.0f32,
                        Color32::from_white_alpha(if dark_h { 40 } else { 190 }),
                    ))
                    .corner_radius(CornerRadius::same(12))
                    .inner_margin(Margin {
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: 12,
                    })
                    .show(ui, |ui| {
                        ui.horizontal(|ui| {
                            let tc_h2 = ui.visuals().text_color();
                            ui.label(theme::ic(icons::STACK).size(15.0).color(theme::ACCENT));
                            ui.label(theme::bold_text("Tổng thể", 14.0, tc_h2));
                            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                ui.label(theme::bold_text(
                                    format!("{:.0}%", rate * 100.0),
                                    16.0,
                                    theme::ACCENT_SOFT,
                                ));
                                ui.weak(format!("{done_total}/{grand} việc đã xong"));
                            });
                        });
                        ui.add_space(6.0);
                        ui.add(
                            ProgressBar::new(rate)
                                .desired_height(9.0)
                                .fill(theme::ACCENT)
                                .corner_radius(CornerRadius::same(4))
                                .animate(true),
                        );
                    });
                // liquid glass + shimmer chạy quanh thẻ tổng
                theme::paint_glass(
                    ui.painter(),
                    hero_rsp.response.rect,
                    CornerRadius::same(12),
                    dark_h,
                );
                theme::shimmer(
                    ui,
                    hero_rsp.response.rect,
                    self.boot.elapsed().as_secs_f32(),
                    dark_h,
                );

                ui.add_space(14.0);

                // ----- biểu đồ 14 ngày -----
                Frame::new()
                    .fill(theme::card_fill(ui))
                    .stroke(theme::card_stroke(ui))
                    .corner_radius(CornerRadius::same(12))
                    .inner_margin(Margin {
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: 12,
                    })
                    .show(ui, |ui| {
                        let tc1 = ui.visuals().text_color();
                        ui.horizontal(|ui| {
                            ui.label(theme::ic(icons::CHART_LINE_UP).size(14.0).color(theme::OK));
                            ui.label(theme::bold_text("Việc hoàn thành · 14 ngày qua", 14.0, tc1));
                        });
                        ui.add_space(8.0);
                        let chart_w = ui.available_width();
                        let chart_h = 170.0;
                        let (rect, _) =
                            ui.allocate_exact_size(egui::vec2(chart_w, chart_h), egui::Sense::hover());
                        let painter = ui.painter();
                        let max_v = s.series.iter().map(|(_, n)| *n).max().unwrap_or(0).max(1);
                        let n = s.series.len() as f32;
                        let gap = 8.0f32;
                        let bar_w = ((rect.width() - gap * (n + 1.0)) / n).max(4.0);
                        let baseline = rect.bottom() - 22.0;
                        let top = rect.top() + 14.0;

                        // đường nền
                        painter.line_segment(
                            [
                                egui::pos2(rect.left(), baseline),
                                egui::pos2(rect.right(), baseline),
                            ],
                            Stroke::new(1.0f32, theme::card_stroke(ui).color),
                        );

                        for (i, (d, v)) in s.series.iter().enumerate() {
                            let x = rect.left() + gap + i as f32 * (bar_w + gap);
                            let frac = *v as f32 / max_v as f32;
                            let h_target = (baseline - top) * frac;
                            // cột mọc dần khi mở/thay đổi thống kê
                            let h = ui.ctx().animate_value_with_time(
                                egui::Id::new(("statbar", d.num_days_from_ce())),
                                h_target,
                                0.40,
                            );
                            let is_last = i + 1 == s.series.len();
                            let color = if *v == 0 {
                                ui.visuals().extreme_bg_color
                            } else if is_last {
                                theme::ACCENT
                            } else {
                                theme::ACCENT_SOFT
                            };
                            let bar = egui::Rect::from_min_size(
                                egui::pos2(x, baseline - h.max(2.0)),
                                egui::vec2(bar_w, h.max(if *v == 0 { 2.0 } else { 4.0 })),
                            );
                            if *v > 0 {
                                painter.rect_filled(bar, CornerRadius::same(4), color);
                            } else {
                                painter.rect_filled(
                                    egui::Rect::from_min_size(
                                        egui::pos2(x, baseline - 2.0),
                                        egui::vec2(bar_w, 2.0),
                                    ),
                                    CornerRadius::same(2),
                                    color,
                                );
                            }
                            // số trên cột
                            if *v > 0 {
                                painter.text(
                                    egui::pos2(x + bar_w / 2.0, baseline - h - 14.0),
                                    egui::Align2::CENTER_TOP,
                                    format!("{v}"),
                                    egui::FontId::proportional(10.5),
                                    ui.visuals().weak_text_color(),
                                );
                            }
                            // nhãn ngày
                            let label = if is_last {
                                "nay".to_string()
                            } else {
                                format!("{:02}", d.day())
                            };
                            let wd = d.weekday().num_days_from_monday();
                            let is_weekend = wd >= 5;
                            painter.text(
                                egui::pos2(x + bar_w / 2.0, baseline + 5.0),
                                egui::Align2::CENTER_TOP,
                                label.clone(),
                                egui::FontId::proportional(10.0),
                                if is_last {
                                    theme::ACCENT_SOFT
                                } else if is_weekend {
                                    ui.visuals().weak_text_color()
                                } else {
                                    ui.visuals().text_color()
                                },
                            );
                        }
                        ui.add_space(6.0);
                        ui.weak(
                            "Mỗi cột là một ngày (00 → hôm nay). Cột đậm = hôm nay.",
                        );
                    });

                ui.add_space(14.0);

                // ----- theo danh sách -----
                Frame::new()
                    .fill(theme::card_fill(ui))
                    .stroke(theme::card_stroke(ui))
                    .corner_radius(CornerRadius::same(12))
                    .inner_margin(Margin {
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: 12,
                    })
                    .show(ui, |ui| {
                        let tc2 = ui.visuals().text_color();
                        ui.horizontal(|ui| {
                            ui.label(theme::ic(icons::FOLDER).size(14.0).color(theme::ACCENT_SOFT));
                            ui.label(theme::bold_text("Theo danh sách", 14.0, tc2));
                        });
                        ui.add_space(6.0);
                        if s.lists.is_empty() {
                            ui.weak("Chưa có danh sách nào.");
                        }
                        for (name, color, done, total) in &s.lists {
                            ui.horizontal(|ui| {
                                let (dr, _) =
                                    ui.allocate_exact_size(egui::vec2(10.0, 10.0), egui::Sense::hover());
                                ui.painter().circle_filled(dr.center(), 5.0, *color);
                                ui.label(name.clone());
                                ui.with_layout(
                                    Layout::right_to_left(Align::Center),
                                    |ui| {
                                        ui.weak(format!("{done}/{total}"));
                                    },
                                );
                            });
                            let frac = if *total == 0 {
                                0.0
                            } else {
                                *done as f32 / *total as f32
                            };
                            ui.add(
                                ProgressBar::new(frac)
                                    .desired_height(7.0)
                                    .desired_width(ui.available_width())
                                    .fill(*color)
                                    .animate(true),
                            );
                            ui.add_space(6.0);
                        }
                    });

                ui.add_space(14.0);

                // ----- theo thẻ -----
                if !s.tags.is_empty() {
                    Frame::new()
                        .fill(theme::card_fill(ui))
                        .stroke(theme::card_stroke(ui))
                        .corner_radius(CornerRadius::same(12))
                        .inner_margin(Margin {
                            left: 16,
                            right: 16,
                            top: 12,
                            bottom: 12,
                        })
                        .show(ui, |ui| {
                            let tc3 = ui.visuals().text_color();
                            ui.horizontal(|ui| {
                                ui.label(theme::ic(icons::HASH).size(14.0).color(theme::ACCENT_SOFT));
                                ui.label(theme::bold_text("Việc đang làm theo thẻ", 14.0, tc3));
                            });
                            ui.add_space(6.0);
                            let max_n = s.tags.iter().map(|(_, n)| *n).max().unwrap_or(1).max(1);
                            for (i, (name, n)) in s.tags.iter().enumerate() {
                                let hue = (i as f32 * 47.0 + 210.0) % 360.0;
                                let color = hsl_to_rgb(hue, 0.62, 0.62);
                                ui.horizontal(|ui| {
                                    let (dr, _) =
                                        ui.allocate_exact_size(egui::vec2(9.0, 9.0), egui::Sense::hover());
                                    ui.painter().circle_filled(dr.center(), 4.5, color);
                                    ui.label(format!("#{name}"));
                                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                        ui.weak(format!("{n}"));
                                    });
                                });
                                ui.add(
                                    ProgressBar::new(*n as f32 / max_n as f32)
                                        .desired_height(6.0)
                                        .fill(color)
                                        .corner_radius(CornerRadius::same(3))
                                        .animate(true),
                                );
                                ui.add_space(4.0);
                            }
                        });
                    ui.add_space(14.0);
                }

                // ----- sự thật nhỏ -----
                let tip = match t.weekday().num_days_from_monday() {
                    0 => "Đầu tuần rồi – lên kế hoạch thôi!",
                    5 => "Cuối tuần – sắp xếp việc cho tuần sau nhé.",
                    6 => "Chủ nhật – nghỉ ngơi hay chốt nốt việc dở?",
                    _ => "Mỗi việc nhỏ hôm nay là một điểm cộng cho tuần này.",
                };
                ui.with_layout(Layout::top_down(Align::Center), |ui| {
                    ui.weak(tip);
                    ui.add_space(10.0);
                });
            });

        // lớp phủ fade-in khi vừa chuyển view
        self.view_enter_fade(ui, p_in, vr_in);
    }
}

/// HSL (0..360, 0..1, 0..1) → Color32.
fn hsl_to_rgb(h: f32, s: f32, l: f32) -> Color32 {
    let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
    let hp = (h.rem_euclid(360.0)) / 60.0;
    let x = c * (1.0 - (hp % 2.0 - 1.0).abs());
    let (r, g, b) = match hp as i32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };
    let m = l - c / 2.0;
    Color32::from_rgb(
        ((r + m) * 255.0).clamp(0.0, 255.0) as u8,
        ((g + m) * 255.0).clamp(0.0, 255.0) as u8,
        ((b + m) * 255.0).clamp(0.0, 255.0) as u8,
    )
}
