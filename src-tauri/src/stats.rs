//! Thống kê hoạt động — port từ UI cũ sang backend (không phụ thuộc UI).

use std::collections::{BTreeMap, HashSet};

use chrono::{DateTime, Utc};
use serde::Serialize;

use crate::models::{today, Store};

#[derive(Serialize)]
pub struct SeriesPoint {
    /// Nhãn ngắn "dd/mm" hiển thị dưới cột.
    pub label: String,
    pub n: i64,
}

#[derive(Serialize)]
pub struct ListStat {
    pub name: String,
    pub color: [u8; 3],
    pub done: usize,
    pub total: usize,
}

#[derive(Serialize)]
pub struct TagStat {
    pub tag: String,
    pub count: usize,
}

#[derive(Serialize)]
pub struct StatsPayload {
    pub active: usize,
    pub done_today: usize,
    pub overdue: usize,
    pub streak: usize,
    pub done_all: usize,
    pub total_all: usize,
    /// Tỷ lệ hoàn thành 0..1
    pub rate: f64,
    pub series: Vec<SeriesPoint>,
    pub lists: Vec<ListStat>,
    pub tags: Vec<TagStat>,
}

pub fn compute(store: &Store) -> StatsPayload {
    let t = today();
    let mut active = 0usize;
    let mut done_today = 0usize;
    let mut overdue = 0usize;
    let mut done_dates: HashSet<chrono::NaiveDate> = HashSet::new();
    let mut per_day: HashSet<chrono::NaiveDate> = HashSet::new();

    for task in &store.tasks {
        if task.is_deleted() {
            continue;
        }
        if let Some(d) = task.completed_at {
            let dd: DateTime<Utc> = d;
            let day = dd.with_timezone(&chrono::Local).date_naive();
            done_dates.insert(day);
            if day == t {
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

    // chuỗi ngày liên tiếp có việc xong (hôm nay chưa xong thì tính từ hôm qua)
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
    let mut series = Vec::with_capacity(14);
    for i in (0..14).rev() {
        let d = t - chrono::Duration::days(i);
        per_day.clear();
        let n = store
            .tasks
            .iter()
            .filter(|task| {
                task.completed_at
                    .map(|x| x.with_timezone(&chrono::Local).date_naive() == d)
                    .unwrap_or(false)
            })
            .count() as i64;
        series.push(SeriesPoint {
            label: d.format("%d/%m").to_string(),
            n,
        });
    }

    // theo danh sách
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
        lists.push(ListStat {
            name: l.name.clone(),
            color: l.color,
            done,
            total,
        });
    }

    // theo thẻ (chỉ việc đang làm)
    let mut tag_map: BTreeMap<String, usize> = BTreeMap::new();
    for task in &store.tasks {
        if !task.is_active() {
            continue;
        }
        for tg in &task.tags {
            *tag_map.entry(tg.clone()).or_insert(0) += 1;
        }
    }
    let mut tags: Vec<TagStat> = tag_map
        .into_iter()
        .map(|(tag, count)| TagStat { tag, count })
        .collect();
    tags.sort_by(|a, b| b.count.cmp(&a.count).then(a.tag.cmp(&b.tag)));
    tags.truncate(8);

    let done_all = store
        .tasks
        .iter()
        .filter(|x| !x.is_deleted() && x.is_completed())
        .count();
    let total_all = store.tasks.iter().filter(|x| !x.is_deleted()).count();
    let rate = if total_all > 0 {
        done_all as f64 / total_all as f64
    } else {
        0.0
    };

    StatsPayload {
        active,
        done_today,
        overdue,
        streak,
        done_all,
        total_all,
        rate,
        series,
        lists,
        tags,
    }
}
