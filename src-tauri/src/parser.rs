//! Bộ phân tích "thêm việc nhanh" – hiểu ngôn ngữ tự nhiên Anh/Việt đơn giản.
//!
//! Hỗ trợ: `#the`, `!p1..!p4`, `*daily/*weekly/...` và cụm ngày
//! (`hôm nay`, `ngày mai`, `thứ 6`, `monday`, `15/11/2026`, `next week`,
//! `in 3 days`, `tuần sau`, `hàng tuần` …).

use chrono::{Datelike, NaiveDate, TimeDelta};

use crate::models::{
    next_weekday, weekday_from_name, weekday_from_number, Priority, Repeat,
};

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Parsed {
    /// Tiêu đề sau khi gỡ bỏ các token đặc biệt.
    pub title: String,
    pub due: Option<NaiveDate>,
    pub priority: Option<Priority>,
    pub tags: Vec<String>,
    pub repeat: Option<Repeat>,
}

fn repeat_from_word(s: &str) -> Option<Repeat> {
    Some(match s {
        "daily" | "ngày" | "hang ngay" | "hàng ngày" => Repeat::Daily,
        "weekly" | "tuần" | "tuan" | "hang tuan" | "hàng tuần" => Repeat::Weekly,
        "monthly" | "tháng" | "thang" | "hang thang" | "hàng tháng" => Repeat::Monthly,
        "weekdays" | "weekday" | "ngay trong tuan" => Repeat::Weekdays,
        "none" | "off" | "khong" | "không" => Repeat::None,
        _ => return None,
    })
}

fn parse_priority(s: &str) -> Option<Priority> {
    Some(match s {
        "p1" | "1" | "cao" | "high" => Priority::P1,
        "p2" | "2" | "trung" | "medium" | "med" => Priority::P2,
        "p3" | "3" | "thap" | "thấp" | "low" => Priority::P3,
        "p4" | "4" | "none" | "khong" | "không" => Priority::P4,
        _ => return None,
    })
}

/// `15/11/2026`, `15/11`, `2026-11-15`.
fn parse_date_token(s: &str, today: NaiveDate) -> Option<NaiveDate> {
    if let Ok(d) = NaiveDate::parse_from_str(s, "%Y-%m-%d") {
        return Some(d);
    }
    if let Ok(d) = NaiveDate::parse_from_str(s, "%d/%m/%Y") {
        return Some(d);
    }
    // dd/mm → năm hiện tại
    let parts: Vec<&str> = s.split('/').collect();
    if parts.len() == 2 {
        let day: u32 = parts[0].parse().ok()?;
        let month: u32 = parts[1].parse().ok()?;
        return NaiveDate::from_ymd_opt(today.year(), month, day);
    }
    None
}

/// Phân tích một chuỗi thêm việc nhanh.
pub fn parse(input: &str, today: NaiveDate) -> Parsed {
    let toks: Vec<String> = input
        .split_whitespace()
        .map(|t| t.to_string())
        .collect();
    let mut consumed = vec![false; toks.len()];
    let mut out = Parsed::default();

    let peek = |i: usize| -> Option<String> { toks.get(i).map(|s| s.to_lowercase()) };

    let mut i = 0usize;
    while i < toks.len() {
        if consumed[i] {
            i += 1;
            continue;
        }
        let lower = toks[i].to_lowercase();
        let mut n_used = 1usize;
        let mut date_hit: Option<NaiveDate> = None;

        // ----- thẻ -----
        if lower.starts_with('#') && lower.chars().count() > 1 {
            let tag: String = lower
                .chars()
                .skip(1)
                .filter(|c| !matches!(c, ',' | ';'))
                .collect();
            if !tag.is_empty() {
                out.tags.push(tag);
            }
            consumed[i] = true;
            i += 1;
            continue;
        }

        // ----- ưu tiên -----
        if lower.starts_with('!') {
            if let Some(p) = parse_priority(&lower[1..]) {
                out.priority = Some(p);
                consumed[i] = true;
            }
            i += 1;
            continue;
        }

        // ----- lặp lại -----
        if lower.starts_with('*') {
            let first = &lower[1..];
            if let Some(r) = repeat_from_word(first) {
                out.repeat = Some(r);
                consumed[i] = true;
            } else if first == "hàng" || first == "hang" {
                // "*hàng ngày/tuần/tháng" — 2 token liền nhau
                if let Some(p) = peek(i + 1) {
                    if let Some(r) = repeat_from_word(&p) {
                        out.repeat = Some(r);
                        consumed[i] = true;
                        consumed[i + 1] = true;
                        i += 1;
                    }
                }
            }
            i += 1;
            continue;
        }

        // ----- cụm từ tiếng Việt (2 token) -----
        match lower.as_str() {
            "hôm" => {
                if peek(i + 1).as_deref() == Some("nay") {
                    date_hit = Some(today);
                    n_used = 2;
                } else if peek(i + 1).as_deref() == Some("qua") {
                    date_hit = today.checked_sub_signed(TimeDelta::days(1));
                    n_used = 2;
                }
            }
            "ngày" => {
                if peek(i + 1).as_deref() == Some("mai") {
                    date_hit = today.checked_add_signed(TimeDelta::days(1));
                    n_used = 2;
                } else if peek(i + 1).as_deref() == Some("kia") {
                    date_hit = today.checked_add_signed(TimeDelta::days(2));
                    n_used = 2;
                }
            }
            "tuần" => {
                let p = peek(i + 1);
                if matches!(p.as_deref(), Some("sau") | Some("tới") | Some("toi")) {
                    date_hit = today.checked_add_signed(TimeDelta::days(7));
                    n_used = 2;
                }
            }
            "tháng" => {
                if peek(i + 1).as_deref() == Some("sau") {
                    date_hit = today.checked_add_signed(TimeDelta::days(30));
                    n_used = 2;
                }
            }
            "chủ" => {
                if peek(i + 1).as_deref() == Some("nhật") {
                    date_hit = Some(next_weekday(6, today, true));
                    n_used = 2;
                }
            }
            "thứ" => {
                if let Some(p) = peek(i + 1) {
                    let wd = p
                        .parse::<u32>()
                        .ok()
                        .and_then(weekday_from_number)
                        .or_else(|| weekday_from_name(&p));
                    if let Some(w) = wd {
                        date_hit = Some(next_weekday(w, today, true));
                        n_used = 2;
                    }
                }
            }
            "hàng" => {
                // "hàng ngày/tuần/tháng" → lặp lại
                if let Some(p) = peek(i + 1) {
                    if let Some(r) = repeat_from_word(&p) {
                        out.repeat = Some(r);
                        consumed[i] = true;
                        consumed[i + 1] = true;
                        i += 2;
                        continue;
                    }
                }
            }
            _ => {}
        }

        // ----- từ khóa Anh -----
        if date_hit.is_none() {
            match lower.as_str() {
                "today" | "tod" => date_hit = Some(today),
                "tomorrow" | "tmr" | "tom" => {
                    date_hit = today.checked_add_signed(TimeDelta::days(1))
                }
                "yesterday" | "yest" => {
                    date_hit = today.checked_sub_signed(TimeDelta::days(1))
                }
                "next" => {
                    if let Some(p) = peek(i + 1) {
                        match p.as_str() {
                            "week" => {
                                date_hit = today.checked_add_signed(TimeDelta::days(7));
                                n_used = 2;
                            }
                            "month" => {
                                date_hit = today.checked_add_signed(TimeDelta::days(30));
                                n_used = 2;
                            }
                            _ => {
                                if let Some(w) = weekday_from_name(&p) {
                                    date_hit = Some(next_weekday(w, today, false));
                                    n_used = 2;
                                }
                            }
                        }
                    }
                }
                "in" => {
                    // "in 3 days" / "in 2 weeks"
                    if let Some(num) = peek(i + 1).and_then(|p| p.parse::<i64>().ok()) {
                        let unit = peek(i + 2);
                        let mult: i64 = match unit.as_deref() {
                            Some("week") | Some("weeks") | Some("tuần") | Some("tuan") => 7,
                            Some("month") | Some("months") | Some("tháng") | Some("thang") => 30,
                            _ => 1,
                        };
                        date_hit = today.checked_add_signed(TimeDelta::days(num * mult));
                        n_used = if unit.is_some() { 3 } else { 2 };
                    }
                }
                "weekdays" => {
                    out.repeat = Some(Repeat::Weekdays);
                    consumed[i] = true;
                    i += 1;
                    continue;
                }
                _ => {
                    if let Some(d) = parse_date_token(&lower, today) {
                        date_hit = Some(d);
                    } else if let Some(w) = weekday_from_name(&lower) {
                        date_hit = Some(next_weekday(w, today, true));
                    }
                }
            }
        }

        if let Some(d) = date_hit {
            out.due = Some(d);
            for k in 0..n_used {
                if i + k < consumed.len() {
                    consumed[i + k] = true;
                }
            }
        }
        i += n_used.max(1);
    }

    out.title = toks
        .iter()
        .enumerate()
        .filter(|(i, _)| !consumed[*i])
        .map(|(_, t)| t.as_str())
        .collect::<Vec<_>>()
        .join(" ");
    out.title = out.title.trim().to_string();
    out.tags.dedup();
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(y: i32, m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    #[test]
    fn vi_tomorrow_priority_tag() {
        // 09/11/2026 là Thứ Hai
        let p = parse("Mua sữa ngày mai #nhà !p1", d(2026, 11, 9));
        assert_eq!(p.title, "Mua sữa");
        assert_eq!(p.due, Some(d(2026, 11, 10)));
        assert_eq!(p.tags, vec!["nhà".to_string()]);
        assert_eq!(p.priority, Some(Priority::P1));
    }

    #[test]
    fn vi_today_and_repeat_bigram() {
        let p = parse("Tập gym hôm nay hàng ngày", d(2026, 11, 9));
        assert_eq!(p.title, "Tập gym");
        assert_eq!(p.due, Some(d(2026, 11, 9)));
        assert_eq!(p.repeat, Some(Repeat::Daily));
    }

    #[test]
    fn vi_weekday_thu6() {
        // thứ 6 từ 09/11 (Thứ Hai) → 13/11 (Thứ Sáu)
        let p = parse("Báo cáo thứ 6 #work", d(2026, 11, 9));
        assert_eq!(p.title, "Báo cáo");
        assert_eq!(p.due, Some(d(2026, 11, 13)));
        assert_eq!(p.tags, vec!["work".to_string()]);
    }

    #[test]
    fn vi_chu_nhat() {
        let p = parse("Gia đình chủ nhật", d(2026, 11, 9));
        assert_eq!(p.due, Some(d(2026, 11, 15))); // CN 15/11
        assert_eq!(p.title, "Gia đình");
    }

    #[test]
    fn en_tomorrow_weekly() {
        let p = parse("Review PR tomorrow !high *weekly", d(2026, 11, 9));
        assert_eq!(p.title, "Review PR");
        assert_eq!(p.due, Some(d(2026, 11, 10)));
        assert_eq!(p.priority, Some(Priority::P1));
        assert_eq!(p.repeat, Some(Repeat::Weekly));
    }

    #[test]
    fn en_next_monday() {
        let p = parse("Submit form next monday", d(2026, 11, 9)); // đang là Monday
        assert_eq!(p.due, Some(d(2026, 11, 16))); // tuần sau
        assert_eq!(p.title, "Submit form");
    }

    #[test]
    fn date_numeric() {
        let p = parse("Họp nhóm 15/11/2026", d(2026, 11, 9));
        assert_eq!(p.due, Some(d(2026, 11, 15)));
        let p2 = parse("Deadline 2026-12-01 !p2", d(2026, 11, 9));
        assert_eq!(p2.due, Some(d(2026, 12, 1)));
        assert_eq!(p2.priority, Some(Priority::P2));
    }

    #[test]
    fn in_n_days() {
        let p = parse("Fix bug in 3 days", d(2026, 11, 9));
        assert_eq!(p.due, Some(d(2026, 11, 12)));
        assert_eq!(p.title, "Fix bug");
    }

    #[test]
    fn repeat_asterisk_vi_bigram() {
        // tài liệu (README/trợ giúp/release notes) hướng dẫn "*hàng ngày" — tiêu đề không được dính rác
        let p = parse("Tập gym *hàng ngày", d(2026, 11, 9));
        assert_eq!(p.title, "Tập gym");
        assert_eq!(p.repeat, Some(Repeat::Daily));
        let p = parse("Báo cáo *hàng tuần", d(2026, 11, 9));
        assert_eq!(p.title, "Báo cáo");
        assert_eq!(p.repeat, Some(Repeat::Weekly));
        let p = parse("Đóng tiền *hàng tháng", d(2026, 11, 9));
        assert_eq!(p.title, "Đóng tiền");
        assert_eq!(p.repeat, Some(Repeat::Monthly));
        let p = parse("Review *hang tuan #việc", d(2026, 11, 9));
        assert_eq!(p.title, "Review");
        assert_eq!(p.repeat, Some(Repeat::Weekly));
        assert_eq!(p.tags, vec!["việc".to_string()]);
    }

    #[test]
    fn repeat_asterisk_vi_single_token() {
        let p = parse("Tập gym *ngày", d(2026, 11, 9));
        assert_eq!(p.title, "Tập gym");
        assert_eq!(p.repeat, Some(Repeat::Daily));
        let p = parse("Tập gym *tuần", d(2026, 11, 9));
        assert_eq!(p.title, "Tập gym");
        assert_eq!(p.repeat, Some(Repeat::Weekly));
    }

    #[test]
    fn plain_title_kept() {
        let p = parse("Chỉ là một tiêu đề bình thường", d(2026, 11, 9));
        assert_eq!(p.title, "Chỉ là một tiêu đề bình thường");
        assert_eq!(p.due, None);
        assert_eq!(p.priority, None);
    }

    #[test]
    fn only_keywords_empty_title() {
        let p = parse("ngày mai #a !p1", d(2026, 11, 9));
        assert_eq!(p.title, "");
        assert_eq!(p.due, Some(d(2026, 11, 10)));
    }

    #[test]
    fn priority_all_levels() {
        assert_eq!(parse("!p3 x", d(2026, 1, 1)).priority, Some(Priority::P3));
        assert_eq!(parse("!p4 x", d(2026, 1, 1)).priority, Some(Priority::P4));
        assert_eq!(parse("!cao x", d(2026, 1, 1)).priority, Some(Priority::P1));
    }

    #[test]
    fn weekday_numbers() {
        let p = parse("Họp thứ 2", d(2026, 11, 9)); // đang là thứ 2 → hôm nay
        assert_eq!(p.due, Some(d(2026, 11, 9)));
        let p2 = parse("Họp thứ 2", d(2026, 11, 10)); // đang thứ 3 → tuần sau (16/11)
        assert_eq!(p2.due, Some(d(2026, 11, 16)));
    }

    #[test]
    fn yearless_date_uses_current_year() {
        let p = parse("x 01/12", d(2026, 11, 9));
        assert_eq!(p.due, Some(d(2026, 12, 1)));
    }
}
