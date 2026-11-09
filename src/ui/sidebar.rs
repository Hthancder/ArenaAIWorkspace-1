//! Thanh bên: các view thông minh + danh sách tùy chỉnh.

use eframe::egui::{self, Align, Color32, Layout, Sense};

use crate::app::{ListDialog, TaskoraApp};
use crate::models::{today, Counts, View};
use crate::ui::theme;

impl TaskoraApp {
    pub fn render_sidebar(&mut self, ui: &mut egui::Ui) {
        let t = today();
        let c: Counts = self.store.counts(t);

        ui.add_space(6.0);
        egui::ScrollArea::vertical()
            .id_salt("sidebar_scroll")
            .auto_shrink([false, false])
            .show(ui, |ui| {
                let smart: [(View, &str, usize); 6] = [
                    (View::Inbox, "Hộp thư", c.inbox),
                    (View::Today, "Hôm nay", c.today),
                    (View::Upcoming, "Sắp tới", c.upcoming),
                    (View::Starred, "Đã ghim", c.starred),
                    (View::Completed, "Đã hoàn thành", c.completed),
                    (View::Trash, "Thùng rác", c.trash),
                ];
                for (v, label, n) in smart {
                    let sel = self.view == v;
                    if self.sidebar_row(ui, sel, label, n, crate::ui::theme::view_color(v), None) {
                        self.set_view(v);
                    }
                }

                ui.add_space(8.0);
                ui.separator();
                ui.add_space(4.0);

                // header DANH SÁCH
                ui.horizontal(|ui| {
                    theme::section_label(ui, "DANH SÁCH");
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if ui
                            .small_button("+")
                            .on_hover_text("Tạo danh sách mới")
                            .clicked()
                        {
                            self.list_dialog = Some(ListDialog {
                                editing: None,
                                name: String::new(),
                                color_idx: 0,
                            });
                        }
                    });
                });
                ui.add_space(2.0);

                let lists: Vec<(u64, String, [u8; 3], usize)> = self
                    .store
                    .lists
                    .iter()
                    .map(|l| {
                        let n = c
                            .by_list
                            .iter()
                            .find(|(id, _)| *id == l.id)
                            .map(|(_, n)| *n)
                            .unwrap_or(0);
                        (l.id, l.name.clone(), l.color, n)
                    })
                    .collect();

                for (id, name, color, n) in lists {
                    let v = View::List(id);
                    let sel = self.view == v;
                    let col = Color32::from_rgb(color[0], color[1], color[2]);
                    let resp = self.sidebar_row_alloc(ui, sel, &name, n, col, None);
                    resp.context_menu(|ui| {
                        if ui.button("Đổi tên / đổi màu…").clicked() {
                            let idx = crate::app::LIST_PALETTE
                                .iter()
                                .position(|p| *p == color)
                                .unwrap_or(0);
                            self.list_dialog = Some(ListDialog {
                                editing: Some(id),
                                name: name.clone(),
                                color_idx: idx,
                            });
                            ui.close_menu();
                        }
                        if ui.button("Xem danh sách").clicked() {
                            self.set_view(v);
                            ui.close_menu();
                        }
                        ui.separator();
                        if ui
                            .button(egui::RichText::new("Xóa danh sách").color(theme_danger()))
                            .clicked()
                        {
                            self.push_undo();
                            for t in self.store.tasks.iter_mut() {
                                if t.list_id == Some(id) {
                                    t.list_id = None;
                                }
                            }
                            self.store.lists.retain(|l| l.id != id);
                            if self.view == v {
                                self.view = View::Inbox;
                            }
                            self.flash("Đã xóa danh sách (việc chuyển về Hộp thư)");
                            ui.close_menu();
                        }
                    });
                    if resp.clicked() {
                        self.set_view(v);
                    }
                }

                ui.add_space(10.0);
                ui.separator();

                // Thống kê
                let sel = self.view == View::Stats;
                if self.sidebar_row(ui, sel, "Thống kê", 0, crate::ui::theme::ACCENT, None) {
                    self.set_view(View::Stats);
                }

                ui.add_space(6.0);
                if ui
                    .button("＋ Danh sách mới…")
                    .on_hover_text("Tạo danh sách (Ctrl+N để thêm việc)")
                    .clicked()
                {
                    self.list_dialog = Some(ListDialog {
                        editing: None,
                        name: String::new(),
                        color_idx: 1,
                    });
                }

                // ----- thẻ tiến độ hôm nay -----
                ui.add_space(8.0);
                let denom = c.done_today + c.today;
                let frac = if denom == 0 {
                    0.0
                } else {
                    c.done_today as f32 / denom as f32
                };
                egui::Frame::new()
                    .fill(theme::card_fill(ui))
                    .stroke(theme::card_stroke(ui))
                    .corner_radius(egui::CornerRadius::same(10))
                    .inner_margin(egui::Margin::symmetric(10, 8))
                    .show(ui, |ui| {
                        ui.horizontal(|ui| {
                            ui.weak("Hôm nay");
                            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                ui.label(
                                    egui::RichText::new(format!("{}/{}", c.done_today, denom))
                                        .size(11.5)
                                        .strong(),
                                );
                            });
                        });
                        ui.add_space(4.0);
                        ui.add(
                            egui::ProgressBar::new(frac)
                                .desired_height(6.0)
                                .fill(if frac >= 1.0 {
                                    theme::OK
                                } else {
                                    theme::ACCENT
                                })
                                .corner_radius(egui::CornerRadius::same(3)),
                        );
                    });

                ui.add_space(8.0);
                ui.weak(
                    egui::RichText::new("Dữ liệu được lưu tự động\nvào thư mục Taskora")
                        .small(),
                );
            });
    }

    /// Một hàng điều hướng; trả về `true` nếu được bấm.
    fn sidebar_row(
        &self,
        ui: &mut egui::Ui,
        selected: bool,
        label: &str,
        count: usize,
        dot: Color32,
        extra: Option<&str>,
    ) -> bool {
        let resp = self.sidebar_row_alloc(ui, selected, label, count, dot, extra);
        resp.clicked()
    }

    fn sidebar_row_alloc(
        &self,
        ui: &mut egui::Ui,
        selected: bool,
        label: &str,
        count: usize,
        dot: Color32,
        extra: Option<&str>,
    ) -> egui::Response {
        let w = ui.available_width();
        let h = 30.0;
        let (rect, resp) = ui.allocate_exact_size(egui::vec2(w, h), Sense::click());
        let visuals = ui.visuals();
        if selected {
            ui.painter().rect_filled(
                rect,
                egui::CornerRadius::same(8),
                visuals.selection.bg_fill,
            );
            // thanh accent bên phải (đọc từ phải sang giống tab browser)
            ui.painter().rect_filled(
                egui::Rect::from_min_size(
                    egui::pos2(rect.right() - 3.0, rect.top() + 6.0),
                    egui::vec2(3.0, rect.height() - 12.0),
                ),
                egui::CornerRadius::same(2),
                theme::ACCENT,
            );
        } else if resp.hovered() {
            ui.painter().rect_filled(
                rect,
                egui::CornerRadius::same(8),
                visuals.faint_bg_color,
            );
        }
        let r = rect.shrink2(egui::vec2(8.0, 4.0));
        ui.allocate_ui_at_rect(r, |ui| {
            ui.with_layout(Layout::left_to_right(Align::Center), |ui| {
                let (dr, _) = ui.allocate_exact_size(egui::vec2(9.0, 9.0), Sense::hover());
                ui.painter().circle_filled(dr.center(), 4.5, dot);
                ui.add_space(6.0);
                let tc = ui.visuals().text_color();
                let rt = if selected {
                    crate::ui::theme::bold_text(label.to_string(), 13.0, tc)
                } else {
                    egui::RichText::new(label).size(13.0)
                };
                ui.label(rt);
                if let Some(e) = extra {
                    ui.weak(e);
                }
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    theme::count_pill(ui, count, selected, dot);
                });
            });
        });
        resp
    }
}

fn theme_danger() -> Color32 {
    crate::ui::theme::DANGER
}
