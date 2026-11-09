//! View Thống kê: thẻ số, biểu đồ cột 14 ngày, tiến độ theo danh sách.

use chrono::{Datelike, Duration as ChronoDuration, Local, NaiveDate};
use eframe::egui::{
    self, Align, Color32, CornerRadius, Frame, Layout, Margin, ProgressBar, RichText, Stroke,
};

use crate::app::TaskoraApp;
use crate::models::{today, Store};
use crate::ui::theme;

struct Stats {
    active: usize,
    done_today: usize,
    overdue: usize,
    streak: usize,
    /// (ngày, số việc xong) 14 ngày gần nhất, cũ → mới.
    series: Vec<(NaiveDate, i64)>,
    /// theo danh sách: (tên, màu, xong, tổng)
    lists: Vec<(String, Color32, usize, usize)>,
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

    Stats {
        active,
        done_today,
        overdue,
        streak,
        series,
        lists,
    }
}

impl TaskoraApp {
    pub fn render_stats(&mut self, ui: &mut egui::Ui) {
        let t = today();
        let s = compute(&self.store, t);

        egui::ScrollArea::vertical()
            .id_salt("stats_scroll")
            .auto_shrink([false, false])
            .show(ui, |ui| {
                ui.add_space(10.0);
                ui.label(theme::bold_text("Thống kê", 20.0, ui.visuals().text_color()));
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
                        Frame::new()
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
                    }
                });

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
                        ui.label(theme::bold_text(
                            "Việc hoàn thành · 14 ngày qua",
                            14.0,
                            ui.visuals().text_color(),
                        ));
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
                            let h = (baseline - top) * frac;
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
                        ui.label(theme::bold_text(
                            "Theo danh sách",
                            14.0,
                            ui.visuals().text_color(),
                        ));
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
                                    .fill(*color),
                            );
                            ui.add_space(6.0);
                        }
                    });

                ui.add_space(14.0);

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
    }
}
