//! Panel chi tiết (bên phải): tiêu đề, hạn chót + lịch, ưu tiên, lặp lại, thẻ, việc nhỏ.

use chrono::{Datelike, Local, NaiveDate};
use eframe::egui::{
    self, Align, Color32, ComboBox, CornerRadius, Frame, Key, Layout, Margin, RichText, Sense,
    Stroke, TextEdit,
};

use crate::app::{Act, TaskoraApp};
use crate::models::{due_state, today, DueState, Priority, Repeat, TaskId, VN_WEEKDAYS};
use crate::ui::{icons, theme};

impl TaskoraApp {
    pub fn render_detail(&mut self, ui: &mut egui::Ui) {
        let mut acts: Vec<Act> = Vec::new();
        self.detail_inner(ui, &mut acts);
        for a in acts {
            self.apply(a);
        }
    }

    fn detail_inner(&mut self, ui: &mut egui::Ui, acts: &mut Vec<Act>) {
        // ----- tiêu đề panel -----
        ui.horizontal(|ui| {
            let tc = ui.visuals().text_color();
            ui.label(theme::bold_text("Chi tiết", 16.0, tc));
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                if ui
                    .small_button(theme::ic(icons::X).size(13.0))
                    .on_hover_text("Đóng panel (Esc)")
                    .clicked()
                {
                    self.selected = None;
                }
            });
        });
        ui.separator();

        let Some(id) = self.selected else {
            ui.weak("Chọn một việc để xem chi tiết.");
            return;
        };
        let Some(idx) = self.store.tasks.iter().position(|t| t.id == id) else {
            self.selected = None;
            return;
        };
        let t = today();

        // ----- tách mượn: tasks & lists (hai field rời của self) -----
        let tasks = &mut self.store.tasks;
        let lists = &self.store.lists;
        let task = &mut tasks[idx];

        // ===== tiêu đề =====
        let w = ui.available_width();
        ui.add(
            TextEdit::singleline(&mut task.title)
                .hint_text("Tiêu đề việc…")
                .desired_width(w)
                .font(egui::FontId::new(15.0, egui::FontFamily::Name("strong".into()))),
        );

        // ===== hoàn thành + ghim =====
        ui.add_space(4.0);
        ui.horizontal(|ui| {
            let mut done = task.completed_at.is_some();
            if ui.checkbox(&mut done, "Hoàn thành").changed() {
                acts.push(Act::Toggle(id));
            }
            let star_on = task.starred;
            let star_c = if star_on {
                theme::STAR
            } else {
                ui.visuals().weak_text_color()
            };
            let lbl = theme::ic_job(icons::STAR, if star_on { "Đã ghim" } else { "Ghim việc" }, star_c);
            if ui.button(lbl).clicked() {
                acts.push(Act::Star(id));
            }
            if task.repeat != Repeat::None {
                let rc = ui.visuals().weak_text_color();
                ui.scope(|ui| {
                    ui.spacing_mut().item_spacing.x = 3.0;
                    ui.label(theme::ic(icons::REPEAT).size(12.0).color(rc));
                    ui.weak("lặp lại");
                });
            }
        });

        if task.deleted_at.is_some() {
            Frame::new()
                .fill(theme::badge_bg(ui, theme::DANGER))
                .corner_radius(CornerRadius::same(8))
                .inner_margin(Margin {
                    left: 10,
                    right: 10,
                    top: 7,
                    bottom: 7,
                })
                .show(ui, |ui| {
                    ui.label(RichText::new("Việc này đang ở thùng rác.").color(theme::DANGER));
                    ui.horizontal(|ui| {
                        if ui.button("Khôi phục").clicked() {
                            acts.push(Act::Restore(id));
                        }
                        if ui
                            .button(RichText::new("Xóa vĩnh viễn").color(theme::DANGER))
                            .clicked()
                        {
                            acts.push(Act::Purge(id));
                        }
                    });
                });
            ui.add_space(6.0);
        }

        ui.add_space(6.0);
        ui.separator();

        // ===== hạn chót + lịch =====
        ui.weak("HẠN CHÓT");
        ui.horizontal(|ui| {
            let due_txt = match task.due {
                Some(d) => d.format("%d/%m/%Y").to_string(),
                None => "Không đặt".to_string(),
            };
            let due_color = match task.due {
                Some(d) if d < t => theme::DANGER,
                Some(d) if d == t => theme::WARN,
                Some(_) => theme::ACCENT_SOFT,
                None => ui.visuals().weak_text_color(),
            };
            if ui
                .button(RichText::new(format!("Hạn: {due_txt}")).color(due_color))
                .on_hover_text("Mở lịch chọn ngày")
                .clicked()
            {
                let base = task.due.unwrap_or(t);
                self.show_cal = !self.show_cal;
                if self.show_cal {
                    self.cal_y = base.year();
                    self.cal_m = base.month();
                }
            }
            if ui.small_button("Hôm nay").clicked() {
                task.due = Some(t);
                self.show_cal = false;
            }
            if ui.small_button("Ngày mai").clicked() {
                task.due = t.succ_opt();
                self.show_cal = false;
            }
            if ui.small_button("Tuần sau").clicked() {
                task.due = t.checked_add_signed(chrono::TimeDelta::days(7));
                self.show_cal = false;
            }
            if task.due.is_some() && ui.small_button("Bỏ").clicked() {
                task.due = None;
                self.show_cal = false;
            }
            if task.due.is_some()
                && ui
                    .small_button("+1 ngày")
                    .on_hover_text("Đẩy hạn chót thêm 1 ngày")
                    .clicked()
            {
                task.due = task
                    .due
                    .and_then(|d| d.checked_add_signed(chrono::TimeDelta::days(1)));
                self.show_cal = false;
            }
        });

        if self.show_cal {
            let mut nav = (self.cal_y, self.cal_m);
            let mut keep = self.show_cal;
            let picked = calendar_widget(ui, &mut nav, task.due, t, &mut keep);
            self.cal_y = nav.0;
            self.cal_m = nav.1;
            self.show_cal = keep;
            if let Some(d) = picked {
                task.due = Some(d);
            }
        }

        if let Some(d) = task.due {
            let st = due_state(Some(d), t);
            let hint = match st {
                DueState::Overdue => "Đã quá hạn!".to_string(),
                DueState::Today => "Đến hạn hôm nay".to_string(),
                DueState::Tomorrow => "Đến hạn ngày mai".to_string(),
                DueState::Later => format!(
                    "{}, {:02}/{:02}",
                    VN_WEEKDAYS[d.weekday().num_days_from_monday() as usize],
                    d.day(),
                    d.month()
                ),
                DueState::None => String::new(),
            };
            if !hint.is_empty() {
                ui.weak(hint);
            }
        }

        ui.add_space(8.0);

        // ===== ưu tiên / lặp lại / danh sách =====
        ui.weak("THÔNG TIN");
        egui::Grid::new("detail_grid")
            .num_columns(2)
            .spacing([10.0, 7.0])
            .show(ui, |ui| {
                ui.label("Ưu tiên:");
                let mut p = task.priority;
                ComboBox::from_id_salt("detail_priority")
                    .selected_text(p.label())
                    .width(190.0)
                    .show_ui(ui, |ui| {
                        for opt in Priority::all() {
                            let (r, g, b) = opt.color_rgb();
                            ui.selectable_value(
                                &mut p,
                                opt,
                                RichText::new(opt.label()).color(Color32::from_rgb(r, g, b)),
                            );
                        }
                    });
                if p != task.priority {
                    task.priority = p;
                }
                ui.end_row();

                ui.label("Lặp lại:");
                let mut r = task.repeat;
                ComboBox::from_id_salt("detail_repeat")
                    .selected_text(r.label())
                    .width(190.0)
                    .show_ui(ui, |ui| {
                        for opt in Repeat::all() {
                            ui.selectable_value(&mut r, opt, opt.label());
                        }
                    });
                if r != task.repeat {
                    task.repeat = r;
                }
                ui.end_row();

                ui.label("Danh sách:");
                let mut lid = task.list_id;
                let sel_txt = lid
                    .and_then(|x| lists.iter().find(|l| l.id == x).map(|l| l.name.clone()))
                    .unwrap_or_else(|| "Hộp thư".to_string());
                ComboBox::from_id_salt("detail_list")
                    .selected_text(sel_txt)
                    .width(190.0)
                    .show_ui(ui, |ui| {
                        let none_clicked = ui
                            .selectable_label(lid.is_none(), "Hộp thư (không danh sách)")
                            .clicked();
                        if none_clicked {
                            lid = None;
                        }
                        for l in lists.iter() {
                            if ui.selectable_label(lid == Some(l.id), &l.name).clicked() {
                                lid = Some(l.id);
                            }
                        }
                    });
                if lid != task.list_id {
                    task.list_id = lid;
                }
                ui.end_row();
            });

        if task.repeat != Repeat::None {
            if let Some(d) = task.due {
                if let Some(next) = task.repeat.next_after(d) {
                    ui.weak(format!("Lặp tới: {}", next.format("%d/%m/%Y")));
                }
            }
        }

        ui.add_space(8.0);

        // ===== ghi chú =====
        ui.weak("GHI CHÚ");
        let nw = ui.available_width();
        ui.add(
            TextEdit::multiline(&mut task.notes)
                .hint_text("Ghi chú, mô tả… (hỗ trợ nhiều dòng)")
                .desired_rows(5)
                .desired_width(nw),
        );

        ui.add_space(8.0);

        // ===== thẻ =====
        ui.weak("THẺ");
        ui.horizontal_wrapped(|ui| {
            let mut remove: Option<usize> = None;
            for (i, tg) in task.tags.iter().enumerate() {
                let r = ui
                    .add(
                        egui::Label::new(
                            RichText::new(format!("#{tg}"))
                                .size(12.0)
                                .color(theme::ACCENT_SOFT),
                        )
                        .sense(Sense::click()),
                    )
                    .on_hover_text("Nhấn để xóa thẻ");
                if r.clicked() {
                    remove = Some(i);
                }
                ui.add_space(4.0);
            }
            if let Some(i) = remove {
                task.tags.remove(i);
            }
            if task.tags.is_empty() {
                ui.weak("Chưa có thẻ nào.");
            }
        });
        // thêm thẻ
        if self.tag_for != Some(id) {
            self.tag_for = Some(id);
            self.tag_buf.clear();
        }
        let tw = ui.available_width();
        let tag_resp = ui.add(
            TextEdit::singleline(&mut self.tag_buf)
                .hint_text("Thêm thẻ (phân cách bằng phẩy), rồi Enter…")
                .desired_width(tw),
        );
        if tag_resp.lost_focus() && ui.input(|i| i.key_pressed(Key::Enter)) {
            let raw = std::mem::take(&mut self.tag_buf);
            for part in raw.split([',', ';']) {
                let tg = part.trim().trim_start_matches('#').to_lowercase();
                if !tg.is_empty() && !task.tags.contains(&tg) {
                    task.tags.push(tg);
                }
            }
        }

        ui.add_space(8.0);

        // ===== việc nhỏ =====
        ui.horizontal(|ui| {
            ui.weak("VIỆC NHỎ");
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                let d = task.subtasks.iter().filter(|s| s.done).count();
                if !task.subtasks.is_empty() {
                    ui.weak(format!("{d}/{}", task.subtasks.len()));
                }
            });
        });
        if !task.subtasks.is_empty() {
            let d = task.subtasks.iter().filter(|s| s.done).count();
            let all = task.subtasks.len();
            ui.add(
                egui::ProgressBar::new(d as f32 / all as f32)
                    .desired_height(6.0)
                    .fill(if d == all { theme::OK } else { theme::ACCENT })
                    .corner_radius(egui::CornerRadius::same(3))
                    .animate(true),
            );
            ui.add_space(6.0);
        }
        let mut rm_sid: Option<TaskId> = None;
        for st in task.subtasks.iter_mut() {
            ui.horizontal(|ui| {
                let mut done = st.done;
                if ui.checkbox(&mut done, "").changed() {
                    st.done = done;
                }
                let sw = ui.available_width();
                ui.add(
                    TextEdit::singleline(&mut st.title)
                        .hint_text("Việc nhỏ…")
                        .desired_width((sw - 34.0).max(60.0)),
                );
                if ui
                    .small_button(theme::ic(icons::X).size(11.0))
                    .on_hover_text("Xóa việc nhỏ")
                    .clicked()
                {
                    rm_sid = Some(st.id);
                }
            });
        }
        if let Some(sid) = rm_sid {
            task.subtasks.retain(|s| s.id != sid);
        }
        let tc_st = ui.visuals().text_color();
        if ui
            .button(theme::ic_job(icons::PLUS, "Thêm việc nhỏ", tc_st))
            .clicked()
        {
            acts.push(Act::AddSubtask(id));
        }

        ui.add_space(10.0);
        ui.separator();

        // ===== metadata + hành động =====
        ui.weak(format!(
            "Tạo lúc {}",
            task.created_at
                .with_timezone(&Local)
                .format("%d/%m/%Y %H:%M")
        ));
        if let Some(ca) = task.completed_at {
            ui.weak(format!(
                "Hoàn thành {}",
                ca.with_timezone(&Local).format("%d/%m/%Y %H:%M")
            ));
        }

        ui.add_space(8.0);
        ui.horizontal(|ui| {
            if ui.button("Nhân bản").clicked() {
                acts.push(Act::Duplicate(id));
            }
            if task.completed_at.is_none() {
                if ui
                    .button(RichText::new("Xóa").color(theme::DANGER))
                    .clicked()
                {
                    acts.push(Act::Delete(id));
                }
            } else if ui.small_button("Mở lại (bỏ hoàn thành)").clicked() {
                acts.push(Act::Toggle(id));
            }
        });
    }
}

/// Lịch chọn ngày – hàm độc lập (tránh mâu thuẫn mượn với task).
/// Trả về ngày được chọn (nếu có) và cập nhật `nav = (năm, tháng)` / `open`.
fn calendar_widget(
    ui: &mut egui::Ui,
    nav: &mut (i32, u32),
    current: Option<NaiveDate>,
    t: NaiveDate,
    open: &mut bool,
) -> Option<NaiveDate> {
    let mut picked: Option<NaiveDate> = None;
    Frame::new()
        .fill(theme::card_fill(ui))
        .stroke(theme::card_stroke(ui))
        .corner_radius(CornerRadius::same(10))
        .inner_margin(Margin {
            left: 10,
            right: 10,
            top: 8,
            bottom: 10,
        })
        .show(ui, |ui| {
            // header tháng
            ui.horizontal(|ui| {
                if ui.small_button(theme::ic(icons::CARET_LEFT).size(12.0)).clicked() {
                    if nav.1 == 1 {
                        nav.1 = 12;
                        nav.0 -= 1;
                    } else {
                        nav.1 -= 1;
                    }
                }
                let title = format!("Tháng {} · {}", nav.1, nav.0);
                let tc = ui.visuals().text_color();
                ui.label(theme::bold_text(title, 13.0, tc));
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if ui.small_button("Hôm nay").clicked() {
                        nav.0 = t.year();
                        nav.1 = t.month();
                    }
                    if ui.small_button(theme::ic(icons::CARET_RIGHT).size(12.0)).clicked() {
                        if nav.1 == 12 {
                            nav.1 = 1;
                            nav.0 += 1;
                        } else {
                            nav.1 += 1;
                        }
                    }
                    if ui.small_button("Đóng").clicked() {
                        *open = false;
                    }
                });
            });
            ui.add_space(4.0);

            // header thứ (T2 → CN)
            egui::Grid::new("cal_head")
                .num_columns(7)
                .spacing([3.0, 2.0])
                .show(ui, |ui| {
                    for name in ["T2", "T3", "T4", "T5", "T6", "T7", "CN"] {
                        ui.add_sized(
                            egui::vec2(34.0, 16.0),
                            egui::Label::new(RichText::new(name).small().weak()),
                        );
                        ui.end_row();
                    }
                });

            // các ngày trong tháng
            let Some(first) = NaiveDate::from_ymd_opt(nav.0, nav.1, 1) else {
                return;
            };
            let lead = first.weekday().num_days_from_monday() as usize;
            let mut days: Vec<NaiveDate> = Vec::new();
            let mut cur = first;
            while cur.month() == nav.1 {
                days.push(cur);
                match cur.succ_opt() {
                    Some(n) => cur = n,
                    None => break,
                }
            }

            egui::Grid::new("cal_grid")
                .num_columns(7)
                .spacing([3.0, 3.0])
                .show(ui, |ui| {
                    for _ in 0..lead {
                        ui.allocate_exact_size(egui::vec2(34.0, 26.0), Sense::hover());
                        ui.end_row();
                    }
                    for d in days {
                        let is_sel = current == Some(d);
                        let is_today = d == t;
                        let label = format!("{:02}", d.day());
                        let mut btn =
                            egui::Button::new(label).min_size(egui::vec2(34.0, 26.0));
                        if is_sel {
                            btn = btn.fill(theme::ACCENT);
                        } else if is_today {
                            btn = btn.stroke(Stroke::new(1.4f32, theme::ACCENT_SOFT));
                        }
                        let r = ui.add(btn);
                        if r.clicked() {
                            picked = Some(d);
                            *open = false;
                        }
                        ui.end_row();
                    }
                });

            // gợi ý nhanh
            ui.add_space(4.0);
            ui.horizontal(|ui| {
                ui.weak("Nhanh:");
                if ui.small_button("+7 ngày").clicked() {
                    if let Some(d) = t.checked_add_signed(chrono::TimeDelta::days(7)) {
                        picked = Some(d);
                        *open = false;
                    }
                }
                if ui.small_button("Đầu tháng sau").clicked() {
                    let (y, m) = if nav.1 == 12 {
                        (nav.0 + 1, 1)
                    } else {
                        (nav.0, nav.1 + 1)
                    };
                    if let Some(d) = NaiveDate::from_ymd_opt(y, m, 1) {
                        picked = Some(d);
                        *open = false;
                    }
                }
            });
        });
    picked
}
