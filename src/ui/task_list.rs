//! View trung tâm: ô thêm việc nhanh, thanh công cụ, danh sách việc.

use chrono::{Datelike, NaiveDate};
use eframe::egui::{
    self, Align, Color32, ComboBox, CornerRadius, Frame, Key, Layout, Margin, RichText, Sense,
    Stroke, TextEdit,
};

use crate::app::{Act, TaskoraApp};
use crate::models::{
    due_state, today, DueState, Priority, Repeat, SortMode, Task, View, VN_WEEKDAYS,
};
use crate::parser;
use crate::ui::theme;

const ROW_H: f32 = 46.0;

impl TaskoraApp {
    pub fn render_task_view(&mut self, ui: &mut egui::Ui) {
        // ----- thêm việc nhanh -----
        if self.view.allows_quick_add() {
            self.quick_add_bar(ui);
        }

        let view = self.view;
        let search = self.search.clone();
        let sort = self.store.settings.sort;
        let hide = self.store.settings.hide_completed;
        let tag = self.tag_filter.clone();
        let ids = self
            .store
            .visible(&view, &search, sort, hide, tag.as_deref());

        self.toolbar(ui, ids.len());

        let mut acts: Vec<Act> = Vec::new();
        let manual = sort == SortMode::Manual;

        egui::ScrollArea::vertical()
            .id_salt("task_scroll")
            .auto_shrink([false, false])
            .show(ui, |ui| {
                if ids.is_empty() {
                    self.empty_state(ui);
                    return;
                }
                let t = today();
                let mut last_group: Option<Option<NaiveDate>> = None;
                for &id in &ids {
                    let Some(task) = self.store.tasks.iter().find(|x| x.id == id) else {
                        continue;
                    };
                    if sort == SortMode::Due {
                        if last_group != Some(task.due) {
                            last_group = Some(task.due);
                            self.group_header(ui, task.due, t);
                        }
                    }
                    self.task_row(ui, task, manual, &mut acts);
                    ui.add_space(2.0);
                }
            });

        for a in acts {
            self.apply(a);
        }
    }

    // ------------------------------------------------------------------ quick add

    fn quick_add_bar(&mut self, ui: &mut egui::Ui) {
        let w = ui.available_width();
        Frame::new()
            .fill(theme::badge_bg(ui, theme::ACCENT))
            .corner_radius(CornerRadius::same(12))
            .inner_margin(Margin {
                left: 12,
                right: 12,
                top: 9,
                bottom: 9,
            })
            .stroke(Stroke::new(1.0, theme::ACCENT.gamma_multiply(0.45)))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(RichText::new("+").size(20.0).color(theme::ACCENT));
                    let iw = ui.available_width();
                    let resp = ui.add(
                        TextEdit::singleline(&mut self.quick_add)
                            .hint_text("Thêm việc… ví dụ: “Mua sữa ngày mai #nhà !p1”")
                            .desired_width(iw)
                            .font(egui::FontId::new(14.0, egui::FontFamily::Proportional)),
                    );
                    let enter = ui.input(|i| i.key_pressed(Key::Enter));
                    if enter && (resp.has_focus() || resp.lost_focus()) {
                        if self.quick_add.trim().is_empty() {
                            // giữ trống, không gì xảy ra
                        } else {
                            self.submit_quick();
                            resp.request_focus();
                        }
                    }
                    if std::mem::take(&mut self.focus_quick) {
                        resp.request_focus();
                    }
                });

                // xem trước phân tích
                if !self.quick_add.trim().is_empty() {
                    let p = parser::parse(&self.quick_add, today());
                    ui.horizontal_wrapped(|ui| {
                        ui.weak("→");
                        if p.title.is_empty() {
                            ui.weak("(chưa có tiêu đề)");
                        } else {
                            ui.weak(format!("“{}”", p.title));
                        }
                        if let Some(d) = p.due {
                            let text = d.format("%d/%m/%Y").to_string();
                            self.chip(ui, &text, theme::BLUE);
                        }
                        if let Some(pr) = p.priority {
                            self.chip(ui, pr.short(), Color32::from_rgb(pr.color_rgb().0, pr.color_rgb().1, pr.color_rgb().2));
                        }
                        for tg in &p.tags {
                            self.chip(ui, &format!("#{tg}"), theme::ACCENT_SOFT);
                        }
                        if let Some(r) = p.repeat {
                            if r != Repeat::None {
                                self.chip(ui, r.short(), theme::OK);
                            }
                        }
                    });
                }
            });
    }

    fn chip(&self, ui: &mut egui::Ui, text: &str, color: Color32) {
        Frame::new()
            .fill(theme::badge_bg(ui, color))
            .corner_radius(CornerRadius::same(6))
            .inner_margin(Margin {
                left: 7,
                right: 7,
                top: 2,
                bottom: 2,
            })
            .show(ui, |ui| {
                ui.label(RichText::new(text).size(11.0).color(color));
            });
    }

    // ------------------------------------------------------------------ toolbar

    fn toolbar(&mut self, ui: &mut egui::Ui, count: usize) {
        ui.add_space(6.0);
        ui.horizontal_wrapped(|ui| {
            let sort_label = self.store.settings.sort.label();
            ComboBox::from_id_salt("sort_combo")
                .selected_text(format!("Sắp: {sort_label}"))
                .width(150.0)
                .show_ui(ui, |ui| {
                    for s in SortMode::all() {
                        ui.selectable_value(&mut self.store.settings.sort, s, s.label());
                    }
                });

            ui.checkbox(&mut self.store.settings.hide_completed, "Ẩn đã hoàn thành");

            // lọc theo thẻ
            let mut tags: Vec<String> = Vec::new();
            for t in &self.store.tasks {
                for tg in &t.tags {
                    if !tags.contains(tg) {
                        tags.push(tg.clone());
                    }
                }
            }
            tags.sort();
            let cur = self.tag_filter.clone();
            let cur_label = match &cur {
                Some(t) => format!("Thẻ: #{t}"),
                None => "Thẻ: tất cả".to_string(),
            };
            ComboBox::from_id_salt("tag_combo")
                .selected_text(cur_label)
                .width(150.0)
                .show_ui(ui, |ui| {
                    let none_clicked = ui
                        .selectable_label(self.tag_filter.is_none(), "Tất cả thẻ")
                        .clicked();
                    if none_clicked {
                        self.tag_filter = None;
                    }
                    for tg in &tags {
                        let sel = self.tag_filter.as_deref() == Some(tg.as_str());
                        if ui.selectable_label(sel, format!("#{tg}")).clicked() {
                            self.tag_filter = Some(tg.clone());
                        }
                    }
                });

            if self.tag_filter.is_some() && ui.small_button("× Bỏ lọc thẻ").clicked() {
                self.tag_filter = None;
            }

            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                ui.weak(format!("{count} việc"));
            });
        });
        ui.add_space(4.0);
    }

    // ------------------------------------------------------------------ header

    fn group_header(&self, ui: &mut egui::Ui, due: Option<NaiveDate>, t: NaiveDate) {
        ui.add_space(8.0);
        let text = match due {
            None => "Không hạn".to_string(),
            Some(d) if d == t => "Hôm nay".to_string(),
            Some(d) if d == t.succ_opt() => "Ngày mai".to_string(),
            Some(d) if d < t => {
                format!("Quá hạn · {}", d.format("%d/%m/%Y"))
            }
            Some(d) => format!(
                "{}, {:02}/{:02}/{}",
                VN_WEEKDAYS[d.weekday().num_days_from_monday() as usize],
                d.day(),
                d.month(),
                d.year()
            ),
        };
        let color = match due {
            Some(d) if d < t => theme::DANGER,
            Some(d) if d == t => theme::WARN,
            _ => theme::ACCENT_SOFT,
        };
        ui.label(theme::bold_text(text, 13.0, color));
        ui.add_space(3.0);
    }

    // ------------------------------------------------------------------ empty

    fn empty_state(&self, ui: &mut egui::Ui) {
        ui.with_layout(Layout::top_down(Align::Center), |ui| {
            ui.add_space(50.0);
            ui.label(RichText::new("○").size(56.0).weak());
            ui.add_space(10.0);
            let (h, sub) = match self.view {
                View::Inbox => ("Hộp thư trống", "Thêm việc đầu tiên bằng ô phía trên (Ctrl+N)"),
                View::Today => ("Không có việc nào hôm nay", "Việc quá hạn cũng sẽ hiển thị ở đây"),
                View::Upcoming => ("Chưa có việc sắp tới", "Đặt hạn chót để xuất hiện trong view này"),
                View::Starred => ("Chưa ghim việc nào", "Bấm ★ ở panel chi tiết để ghim"),
                View::Completed => ("Chưa có việc hoàn thành", "Hoàn thành việc để xem tại đây"),
                View::Trash => ("Thùng rác trống", "Việc đã xóa sẽ nằm ở đây trước khi xóa vĩnh viễn"),
                View::Stats => ("", ""),
                View::List(_) => ("Danh sách trống", "Thêm việc nhanh hoặc kéo thả từ view khác"),
            };
            if !h.is_empty() {
                ui.label(theme::bold_text(h, 17.0, ui.visuals().text_color()));
                ui.add_space(4.0);
                ui.weak(sub);
            }
        });
    }

    // ------------------------------------------------------------------ row

    fn task_row(&self, ui: &mut egui::Ui, task: &Task, manual: bool, acts: &mut Vec<Act>) {
        let t = today();
        let w = ui.available_width();
        let selected = self.selected == Some(task.id);
        let (rect, resp) = ui.allocate_exact_size(egui::vec2(w, ROW_H), Sense::click());

        // nền
        let visuals_dark = ui.visuals().dark_mode;
        let bg = if selected {
            theme::ACCENT.gamma_multiply(if visuals_dark { 0.20 } else { 0.12 })
        } else if resp.hovered() {
            ui.visuals().faint_bg_color
        } else {
            Color32::TRANSPARENT
        };
        if bg != Color32::TRANSPARENT {
            ui.painter().rect_filled(rect, CornerRadius::same(9), bg);
        }
        if selected {
            ui.painter().rect_filled(
                egui::Rect::from_min_size(
                    egui::pos2(rect.left(), rect.top() + 8.0),
                    egui::vec2(3.0, rect.height() - 16.0),
                ),
                CornerRadius::same(2),
                theme::ACCENT,
            );
        }

        // chỉ báo kéo-thả khi đang có payload
        if let Some(src) = resp.dnd_hover_payload::<u64>() {
            if *src != task.id {
                let pointer_y = ui.input(|i| i.pointer.hover_pos().map(|p| p.y));
                let y = if pointer_y.map(|y| y < rect.center().y).unwrap_or(false) {
                    rect.top() + 1.0
                } else {
                    rect.bottom() - 1.0
                };
                ui.painter().line_segment(
                    [
                        egui::pos2(rect.left() + 6.0, y),
                        egui::pos2(rect.right() - 6.0, y),
                    ],
                    Stroke::new(2.0, theme::ACCENT),
                );
            }
        }
        if let Some(src) = resp.dnd_release_payload::<u64>() {
            let before = ui
                .input(|i| i.pointer.hover_pos().map(|p| p.y))
                .map(|y| y < rect.center().y)
                .unwrap_or(false);
            if *src != task.id {
                acts.push(Act::Drop {
                    src: *src,
                    dst: task.id,
                    before,
                });
            }
        }

        if resp.clicked() {
            acts.push(Act::Select(task.id));
        }

        // menu chuột phải
        let view = self.view;
        resp.context_menu(|ui| {
            let done = task.completed_at.is_some();
            if ui
                .button(if done {
                    "Bỏ đánh dấu hoàn thành"
                } else {
                    "Đánh dấu hoàn thành"
                })
                .clicked()
            {
                acts.push(Act::Toggle(task.id));
                ui.close_menu();
            }
            let star_txt = if task.starred { "Bỏ ghim" } else { "Ghim việc" };
            if ui.button(star_txt).clicked() {
                acts.push(Act::Star(task.id));
                ui.close_menu();
            }
            if manual {
                if ui.button("Lên trên").clicked() {
                    acts.push(Act::MoveUp(task.id));
                    ui.close_menu();
                }
                if ui.button("Xuống dưới").clicked() {
                    acts.push(Act::MoveDown(task.id));
                    ui.close_menu();
                }
            }
            if !matches!(view, View::Trash | View::Completed) {
                ui.menu_button("Chuyển đến…", |ui| {
                    if ui.button("Hộp thư").clicked() {
                        acts.push(Act::MoveToList(task.id, None));
                        ui.close_menu();
                    }
                    let lists: Vec<(u64, String)> = self
                        .store
                        .lists
                        .iter()
                        .map(|l| (l.id, l.name.clone()))
                        .collect();
                    for (lid, lname) in lists {
                        if ui.button(lname).clicked() {
                            acts.push(Act::MoveToList(task.id, Some(lid)));
                            ui.close_menu();
                        }
                    }
                });
                if ui.button("Nhân bản").clicked() {
                    acts.push(Act::Duplicate(task.id));
                    ui.close_menu();
                }
                ui.separator();
                if ui
                    .button(egui::RichText::new("Xóa").color(theme::DANGER))
                    .clicked()
                {
                    acts.push(Act::Delete(task.id));
                    ui.close_menu();
                }
            } else if view == View::Trash {
                if ui.button("Khôi phục").clicked() {
                    acts.push(Act::Restore(task.id));
                    ui.close_menu();
                }
                if ui
                    .button(egui::RichText::new("Xóa vĩnh viễn").color(theme::DANGER))
                    .clicked()
                {
                    acts.push(Act::Purge(task.id));
                    ui.close_menu();
                }
            }
        });

        // ----- nội dung -----
        let content = rect.shrink2(egui::vec2(10.0, 7.0));
        ui.allocate_ui_at_rect(content, |ui| {
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                // ----- phải: hạn chót / thẻ / việc nhỏ / sao -----
                let done = task.completed_at.is_some();
                if done {
                    if let Some(ca) = task.completed_at {
                        let hh = ca.with_timezone(&chrono::Local).format("%H:%M").to_string();
                        ui.weak(format!("✓ {hh}"));
                    }
                } else {
                    match due_state(task.due, t) {
                        DueState::None => {}
                        st => {
                            let (color, text) = match st {
                                DueState::Overdue => (theme::DANGER, "Quá hạn".to_string()),
                                DueState::Today => (theme::WARN, "Hôm nay".to_string()),
                                DueState::Tomorrow => (theme::BLUE, "Ngày mai".to_string()),
                                DueState::Later => (
                                    theme::ACCENT_SOFT,
                                    task.due
                                        .map(|d| d.format("%d/%m").to_string())
                                        .unwrap_or_default(),
                                ),
                                DueState::None => unreachable!(),
                            };
                            self.chip(ui, &text, color);
                        }
                    }
                }

                // thẻ (bấm để lọc)
                let tags = task.tags.clone();
                for tg in tags.iter().take(2) {
                    let r = ui
                        .add(egui::Label::new(
                            RichText::new(format!("#{tg}")).size(10.5).color(theme::ACCENT_SOFT),
                        ))
                        .on_hover_text("Bấm để lọc theo thẻ này");
                    if r.clicked() {
                        acts.push(Act::FilterTag(tg.clone()));
                    }
                }
                if tags.len() > 2 {
                    ui.weak(format!("+{}", tags.len() - 2));
                }

                // việc nhỏ x/y
                if !task.subtasks.is_empty() {
                    let d = task.subtasks.iter().filter(|s| s.done).count();
                    let all = task.subtasks.len();
                    let r = ui
                        .add(
                            RichText::new(format!("{d}/{all}"))
                                .size(11.0)
                                .color(theme::ACCENT_SOFT),
                        )
                        .on_hover_text("Tiến độ việc nhỏ");
                    let _ = r;
                }

                // sao
                let star_on = task.starred;
                let star_color = if star_on { theme::STAR } else { ui.visuals().weak_text_color() };
                let star = ui
                    .add(
                        egui::Label::new(RichText::new(if star_on { "★" } else { "☆" }).size(15.0).color(star_color))
                            .sense(Sense::click()),
                    )
                    .on_hover_text(if star_on { "Bỏ ghim" } else { "Ghim việc" });
                if star.clicked() {
                    acts.push(Act::Star(task.id));
                }

                // ----- trái kéo sang: handle, checkbox, tiêu đề (bấm để chọn) -----
                if manual {
                    let (_hr, hresp) =
                        ui.allocate_exact_size(egui::vec2(14.0, 24.0), Sense::drag());
                    let hresp = hresp.on_hover_text("Kéo để đổi thứ tự (chế độ Thủ công)");
                    hresp.dnd_set_drag_payload(task.id);
                    // 6 chấm nhỏ
                    let p = ui.painter();
                    let c = hresp.rect;
                    for dx in [0.0f32, 6.0] {
                        for dy in [-5.0f32, 0.0, 5.0] {
                            p.circle_filled(
                                egui::pos2(c.center().x + dx - 3.0, c.center().y + dy),
                                1.6,
                                ui.visuals().weak_text_color(),
                            );
                        }
                    }
                }

                self.checkbox_circle(ui, task, acts);

                // tiêu đề
                let mut rt = RichText::new(task.title.clone()).size(14.0);
                if done {
                    rt = rt.color(ui.visuals().weak_text_color()).strikethrough();
                } else if task.priority != Priority::P4 {
                    let pr = task.priority.color_rgb();
                    rt = rt.color(Color32::from_rgb(pr.0, pr.1, pr.2));
                }
                let label = ui.add(egui::Label::new(rt).truncate().sense(Sense::click()));
                if label.clicked() {
                    acts.push(Act::Select(task.id));
                }
                if label.double_clicked() {
                    acts.push(Act::Select(task.id));
                }
            });
        });
    }

    /// Vòng tròn checkbox vẽ tay theo màu ưu tiên.
    fn checkbox_circle(&self, ui: &mut egui::Ui, task: &Task, acts: &mut Vec<Act>) {
        let size = 22.0;
        let (r, resp) = ui.allocate_exact_size(egui::vec2(size, size), Sense::click());
        let done = task.completed_at.is_some();
        let pr = task.priority.color_rgb();
        let ring = if task.priority == Priority::P4 {
            ui.visuals().weak_text_color()
        } else {
            Color32::from_rgb(pr.0, pr.1, pr.2)
        };
        let painter = ui.painter();
        let c = r.center();
        let rad = size / 2.0 - 1.5;
        if done {
            painter.circle_filled(c, rad, theme::OK);
            let s = rad * 0.55;
            painter.line_segment(
                [
                    egui::pos2(c.x - s, c.y + 0.5),
                    egui::pos2(c.x - s * 0.2, c.y + s * 0.75),
                ],
                Stroke::new(2.2, Color32::WHITE),
            );
            painter.line_segment(
                [
                    egui::pos2(c.x - s * 0.2, c.y + s * 0.75),
                    egui::pos2(c.x + s * 0.9, c.y - s * 0.7),
                ],
                Stroke::new(2.2, Color32::WHITE),
            );
        } else {
            if resp.hovered() {
                painter.circle_filled(c, rad, ring.gamma_multiply(0.15));
            }
            painter.circle_stroke(c, rad, Stroke::new(1.7, ring));
        }
        if resp.clicked() {
            acts.push(Act::Toggle(task.id));
        }
        resp.on_hover_text(if done { "Bỏ hoàn thành" } else { "Đánh dấu hoàn thành (Space)" });
    }
}
