//! View trung tâm: ô thêm việc nhanh, thanh công cụ, danh sách việc.

use chrono::{Datelike, NaiveDate, TimeDelta};
use eframe::egui::{
    self, Align, Color32, ComboBox, CornerRadius, Frame, Key, Layout, Margin, RichText, Sense,
    Stroke, TextEdit,
};

use crate::app::{Act, TaskoraApp};
use crate::models::{
    due_state, today, Counts, DueState, Priority, Repeat, SortMode, Task, View, VN_WEEKDAYS,
};
use crate::parser;
use crate::ui::{icons, theme};

const ROW_H: f32 = 46.0;

impl TaskoraApp {
    pub fn render_task_view(&mut self, ui: &mut egui::Ui) {
        let (p_in, vr_in) = self.view_enter_head(ui);
        let t0 = today();
        let c0 = self.store.counts(t0);
        let mut pre: Vec<Act> = Vec::new();

        // ----- header view -----
        self.view_header(ui, &mut pre, &c0);

        // ----- thêm việc nhanh -----
        if self.view.allows_quick_add() {
            self.quick_add_bar(ui);
        }

        // ----- banner quá hạn (Today) -----
        if self.view == View::Today && c0.overdue > 0 {
            self.overdue_banner(ui, &mut pre, &c0);
        }

        let view = self.view;
        let search = self.search.clone();
        let sort = self.store.settings.sort;
        let hide = self.store.settings.hide_completed;
        let tag = self.tag_filter.clone();
        let prio = self.prio_filter;
        let ids = self
            .store
            .visible(&view, &search, sort, hide, tag.as_deref(), prio);

        self.toolbar(ui, ids.len());

        let mut acts: Vec<Act> = pre;
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
                    ui.add_space(5.0);
                }
            });

        // dọn cờ scroll trước khi apply (apply có thể set lại cho frame sau)
        self.scroll_to = None;
        for a in acts {
            self.apply(a);
        }
        // lớp phủ fade-in khi vừa chuyển view
        self.view_enter_fade(ui, p_in, vr_in);
    }

    // ------------------------------------------------------------------ header view

    fn view_header(&mut self, ui: &mut egui::Ui, acts: &mut Vec<Act>, c: &Counts) {
        let view = self.view;
        let title = view.title(&self.store.lists);
        let vc = theme::view_color(view);
        let n = match view {
            View::Inbox => c.inbox,
            View::Today => c.today,
            View::Upcoming => c.upcoming,
            View::Starred => c.starred,
            View::Completed => c.completed,
            View::Trash => c.trash,
            View::List(id) => c
                .by_list
                .iter()
                .find(|(l, _)| *l == id)
                .map(|(_, n)| *n)
                .unwrap_or(0),
            View::Stats => 0,
        };
        let sub: &str = match view {
            View::Inbox => "Việc chưa phân vào danh sách nào",
            View::Today => "Đến hạn hôm nay và các việc quá hạn",
            View::Upcoming => "Hạn chót trong những ngày tới",
            View::Starred => "Những việc bạn ghim để ưu tiên",
            View::Completed => "Lịch sử những việc đã làm xong",
            View::Trash => "Việc đã xóa — xóa vĩnh viễn sẽ không khôi phục được",
            View::List(_) => "Danh sách của bạn",
            View::Stats => "",
        };
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            let (dr, _) = ui.allocate_exact_size(egui::vec2(13.0, 13.0), egui::Sense::hover());
            ui.painter().circle_filled(dr.center(), 6.5, vc);
            ui.add_space(7.0);
            ui.label(theme::bold_text(title, 21.0, ui.visuals().text_color()));
            ui.add_space(6.0);
            theme::count_pill(ui, n, false, vc);
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                match view {
                    View::Trash if c.trash > 0 => {
                        if ui
                            .small_button("Dọn thùng rác")
                            .on_hover_text("Xóa vĩnh viễn tất cả — không thể hoàn tác")
                            .clicked()
                        {
                            acts.push(Act::PurgeAllTrash);
                        }
                    }
                    View::Completed if c.completed > 0 => {
                        if ui.small_button("Xóa tất cả hoàn thành").clicked() {
                            acts.push(Act::ClearCompleted);
                        }
                    }
                    _ => {}
                }
            });
        });
        if !sub.is_empty() {
            ui.weak(sub);
        }
        ui.add_space(4.0);
    }

    // ------------------------------------------------------------------ banner quá hạn

    fn overdue_banner(&self, ui: &mut egui::Ui, acts: &mut Vec<Act>, c: &Counts) {
        let t = today();
        Frame::new()
            .fill(theme::badge_bg(ui, theme::DANGER))
            .stroke(Stroke::new(1.0f32, theme::DANGER.gamma_multiply(0.5)))
            .corner_radius(CornerRadius::same(10))
            .inner_margin(Margin {
                left: 12,
                right: 12,
                top: 8,
                bottom: 8,
            })
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(theme::ic(icons::WARNING).size(14.0).color(theme::DANGER));
                    ui.colored_label(
                        theme::DANGER,
                        RichText::new(format!("{} việc quá hạn", c.overdue)).strong(),
                    );
                    ui.weak("Cần xử lý sớm");
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if ui
                            .small_button("Hoãn hết đến ngày mai")
                            .on_hover_text("Đẩy tất cả việc quá hạn sang ngày mai")
                            .clicked()
                        {
                            acts.push(Act::DeferOverdue(t.succ_opt().unwrap_or(t)));
                        }
                        if ui
                            .small_button("Đưa về hôm nay")
                            .on_hover_text("Đặt lại hạn chót của việc quá hạn = hôm nay")
                            .clicked()
                        {
                            acts.push(Act::DeferOverdue(t));
                        }
                    });
                });
            });
        ui.add_space(4.0);
    }

    // ------------------------------------------------------------------ quick add

    fn quick_add_bar(&mut self, ui: &mut egui::Ui) {
        let dark_q = ui.visuals().dark_mode;
        let mut q_focus = false;
        let rsp = Frame::new()
            .fill(if dark_q {
                Color32::from_rgba_unmultiplied(99, 102, 241, 58)
            } else {
                Color32::from_rgba_unmultiplied(255, 255, 255, 214)
            })
            .corner_radius(CornerRadius::same(12))
            .inner_margin(Margin {
                left: 12,
                right: 12,
                top: 9,
                bottom: 9,
            })
            .stroke(Stroke::new(
                1.0f32,
                theme::ACCENT.gamma_multiply(if dark_q { 0.55 } else { 0.38 }),
            ))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(theme::ic(icons::PLUS).size(17.0).color(theme::ACCENT));
                    let iw = ui.available_width();
                    let resp = ui.add(
                        TextEdit::singleline(&mut self.quick_add)
                            .hint_text("Thêm việc… ví dụ: “Mua sữa ngày mai #nhà !p1”")
                            .desired_width(iw)
                            .font(egui::FontId::new(14.0, egui::FontFamily::Proportional)),
                    );
                    q_focus = resp.has_focus();
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

                // chips ví dụ khi ô trống (bấm để điền nhanh)
                if self.quick_add.trim().is_empty() {
                    ui.horizontal_wrapped(|ui| {
                        ui.weak("Thử ngay:");
                        for ex in [
                            "Mua sữa ngày mai #nhà !p1",
                            "Báo cáo thứ 6 17h #cv !p2",
                            "Tập gym *hàng tuần 6h30",
                        ] {
                            if ui.small_button(ex).clicked() {
                                self.quick_add = ex.to_string();
                            }
                        }
                    });
                }

                // xem trước phân tích
                if !self.quick_add.trim().is_empty() {
                    let p = parser::parse(&self.quick_add, today());
                    ui.horizontal_wrapped(|ui| {
                        let wc = ui.visuals().weak_text_color();
                        ui.label(theme::ic(icons::ARROW_RIGHT).size(12.0).color(wc));
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
        // ----- liquid glass + shimmer khi đang nhập -----
        theme::paint_glass(
            ui.painter(),
            rsp.response.rect,
            CornerRadius::same(12),
            dark_q,
        );
        if q_focus {
            theme::shimmer(ui, rsp.response.rect, self.boot.elapsed().as_secs_f32(), dark_q);
        }
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
            let wc = ui.visuals().weak_text_color();
            ui.label(theme::ic(icons::SORT_DESCENDING).size(13.0).color(wc));
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
            ui.label(theme::ic(icons::HASH).size(13.0).color(wc));
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

            // chips lọc ưu tiên P1–P4
            ui.separator();
            ui.label(theme::ic(icons::FLAG_BANNER).size(13.0).color(wc));
            ui.weak("Ưu tiên:");
            for p in Priority::all() {
                let sel = self.prio_filter == Some(p);
                let (r, g, b) = p.color_rgb();
                let col = Color32::from_rgb(r, g, b);
                let label = RichText::new(p.short())
                    .size(11.5)
                    .color(if sel { Color32::WHITE } else { col });
                let resp = ui.add(
                    egui::Button::new(label)
                        .fill(if sel { col } else { theme::badge_bg(ui, col) })
                        .corner_radius(CornerRadius::same(7))
                        .min_size(egui::vec2(34.0, 21.0)),
                );
                if resp.clicked() {
                    self.prio_filter = if sel { None } else { Some(p) };
                }
            }
            if self.prio_filter.is_some() && ui.small_button("× Ưu tiên").clicked() {
                self.prio_filter = None;
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
            Some(d) if Some(d) == t.succ_opt() => "Ngày mai".to_string(),
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
            ui.label(theme::ic(icons::SEAL).size(52.0).weak());
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
        let active = task.is_active();
        let (rect, resp) = ui.allocate_exact_size(egui::vec2(w, ROW_H), Sense::click());

        // ----- card-style: nền card + viền mảnh, fade mượt khi hover/chọn -----
        let visuals_dark = ui.visuals().dark_mode;
        let base = theme::card_fill(ui);
        let hover_c = theme::mix(base, theme::ACCENT, if visuals_dark { 0.16 } else { 0.07 });
        let sel_c = theme::ACCENT.gamma_multiply(if visuals_dark { 0.22 } else { 0.13 });
        let t_hov = ui.ctx().animate_value_with_time(
            egui::Id::new(("rhov", task.id)),
            if resp.hovered() && !selected { 1.0 } else { 0.0 },
            0.10,
        );
        let t_sel = ui.ctx().animate_value_with_time(
            egui::Id::new(("rsel", task.id)),
            if selected { 1.0 } else { 0.0 },
            0.15,
        );
        let bg = theme::mix(theme::mix(base, hover_c, t_hov), sel_c, t_sel);
        ui.painter().rect_filled(rect, CornerRadius::same(10), bg);
        ui.painter().rect_stroke(
            rect,
            CornerRadius::same(10),
            Stroke::new(
                1.0f32,
                theme::mix(
                    theme::card_stroke(ui).color,
                    theme::ACCENT.gamma_multiply(0.7),
                    t_sel,
                ),
            ),
            egui::StrokeKind::Middle,
        );
        // pulse xanh lá khi vừa đánh dấu xong
        if let Some((pid, at)) = self.done_pulse {
            let age = at.elapsed().as_secs_f32();
            if pid == task.id && age < 0.45 {
                let k = 1.0 - age / 0.45;
                ui.painter().rect_filled(
                    rect,
                    CornerRadius::same(10),
                    theme::OK.gamma_multiply(0.32 * k),
                );
            }
        }
        // ánh sáng trên đỉnh card khi hover/chọn (liquid glass)
        theme::paint_specular(
            ui.painter(),
            rect,
            CornerRadius::same(10),
            t_hov * 0.85 + t_sel * 0.5,
        );
        // thanh màu ưu tiên bên trái
        if active {
            let (r, g, b) = task.priority.color_rgb();
            ui.painter().rect_filled(
                egui::Rect::from_min_size(
                    egui::pos2(rect.left() + 4.0, rect.top() + 7.0),
                    egui::vec2(3.0, rect.height() - 14.0),
                ),
                CornerRadius::same(2),
                Color32::from_rgb(r, g, b),
            );
        }
        // chip trạng thái khi chọn (gạch bên trái cũ đã đổi thành viền)
        if selected {
            ui.painter().rect_filled(
                egui::Rect::from_min_size(
                    egui::pos2(rect.left(), rect.top() + 10.0),
                    egui::vec2(3.0, rect.height() - 20.0),
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
                    Stroke::new(2.0f32, theme::ACCENT),
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
        // cuộn mượt đến việc vừa chọn
        if self.scroll_to == Some(task.id) {
            resp.scroll_to_me(Some(Align::Center));
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
                ui.separator();
                ui.menu_button("Hạn chót ▸", |ui| {
                    if ui.button("Hôm nay").clicked() {
                        acts.push(Act::SetDue(task.id, Some(t)));
                        ui.close_menu();
                    }
                    if ui.button("Ngày mai").clicked() {
                        acts.push(Act::SetDue(task.id, t.succ_opt()));
                        ui.close_menu();
                    }
                    if ui.button("Tuần sau").clicked() {
                        acts.push(Act::SetDue(
                            task.id,
                            t.checked_add_signed(TimeDelta::days(7)),
                        ));
                        ui.close_menu();
                    }
                    if task.due.is_some() && ui.button("Bỏ hạn chót").clicked() {
                        acts.push(Act::SetDue(task.id, None));
                        ui.close_menu();
                    }
                });
                ui.menu_button("Ưu tiên ▸", |ui| {
                    for p in Priority::all() {
                        let (r, g, b) = p.color_rgb();
                        let sel = task.priority == p;
                        if ui
                            .selectable_label(
                                sel,
                                RichText::new(p.label()).color(if sel {
                                    ui.visuals().text_color()
                                } else {
                                    Color32::from_rgb(r, g, b)
                                }),
                            )
                            .clicked()
                        {
                            acts.push(Act::SetPriority(task.id, p));
                            ui.close_menu();
                        }
                    }
                });
                ui.separator();
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
                        let wc2 = ui.visuals().weak_text_color();
                        ui.scope(|ui| {
                            ui.spacing_mut().item_spacing.x = 3.0;
                            ui.label(theme::ic(icons::CHECK).size(11.0).color(wc2));
                            ui.weak(hh);
                        });
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
                    ui.label(
                        RichText::new(format!("{d}/{all}"))
                            .size(11.0)
                            .color(theme::ACCENT_SOFT),
                    )
                    .on_hover_text("Tiến độ việc nhỏ");
                }

                // sao
                let star_on = task.starred;
                let star_color = if star_on { theme::STAR } else { ui.visuals().weak_text_color() };
                let star_rt = if star_on {
                    theme::icf(icons::STAR)
                } else {
                    theme::ic(icons::STAR)
                };
                let star = ui
                    .add(
                        egui::Label::new(star_rt.size(15.0).color(star_color))
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

                // tiêu đề (tô sáng khớp từ khoá tìm kiếm)
                let base_color = if done {
                    ui.visuals().weak_text_color()
                } else if task.priority != Priority::P4 {
                    let pr = task.priority.color_rgb();
                    Color32::from_rgb(pr.0, pr.1, pr.2)
                } else {
                    ui.visuals().text_color()
                };
                let title_w = if self.search.trim().is_empty() {
                    let mut rt = RichText::new(task.title.clone()).size(14.0).color(base_color);
                    if done {
                        rt = rt.strikethrough();
                    }
                    egui::WidgetText::from(rt)
                } else {
                    egui::WidgetText::from(hl_job(
                        &task.title,
                        &self.search,
                        14.0,
                        base_color,
                        done,
                    ))
                };
                let label = ui.add(egui::Label::new(title_w).truncate().sense(Sense::click()));
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
                Stroke::new(2.2f32, Color32::WHITE),
            );
            painter.line_segment(
                [
                    egui::pos2(c.x - s * 0.2, c.y + s * 0.75),
                    egui::pos2(c.x + s * 0.9, c.y - s * 0.7),
                ],
                Stroke::new(2.2f32, Color32::WHITE),
            );
        } else {
            if resp.hovered() {
                painter.circle_filled(c, rad, ring.gamma_multiply(0.15));
            }
            painter.circle_stroke(c, rad, Stroke::new(1.7f32, ring));
        }
        if resp.clicked() {
            acts.push(Act::Toggle(task.id));
        }
        resp.on_hover_text(if done { "Bỏ hoàn thành" } else { "Đánh dấu hoàn thành (Space)" });
    }
}

/// Tạo LayoutJob với nền tím cho các khớp của từ khoá tìm kiếm (không phân biệt hoa/thường).
fn hl_job(title: &str, q: &str, size: f32, color: Color32, strike: bool) -> egui::text::LayoutJob {
    use egui::text::{LayoutJob, TextFormat};
    let font = egui::FontId::new(size, egui::FontFamily::Proportional);
    let base = TextFormat {
        font_id: font.clone(),
        color,
        strikethrough: if strike {
            Stroke::new(1.0f32, color)
        } else {
            Stroke::NONE
        },
        ..Default::default()
    };
    let mut job = LayoutJob::default();
    let ql = q.trim().to_lowercase();
    if ql.is_empty() {
        job.append(title, 0.0, base);
        return job;
    }
    let tl = title.to_lowercase();
    // guard: lowercase có thể đổi độ dài byte (vd. 'İ') — nếu lệch thì bỏ highlight
    if tl.len() != title.len() {
        job.append(title, 0.0, base);
        return job;
    }
    let mut last = 0usize;
    let mut idx = 0usize;
    while let Some(rel) = tl[idx..].find(&ql) {
        let start = idx + rel;
        let end = start + ql.len();
        if !title.is_char_boundary(start) || !title.is_char_boundary(end) {
            job.append(&title[last..], 0.0, base);
            return job;
        }
        if start > last {
            job.append(&title[last..start], 0.0, base.clone());
        }
        let mut hl = base.clone();
        hl.background = Color32::from_rgba_unmultiplied(129, 140, 248, 90);
        job.append(&title[start..end], 0.0, hl);
        last = end;
        idx = end;
    }
    if last < title.len() {
        job.append(&title[last..], 0.0, base);
    }
    job
}
