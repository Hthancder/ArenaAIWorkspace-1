//! §42.13 — dọn tài nguyên: refcount về 0 thì **hẹn 5 s** rồi mới dọn.
//!
//! Lý do tồn tại của module này là một sự kiện rất cụ thể: **F5**. Người dùng
//! bấm F5 giữa phiên ⇒ kết nối cũ đóng **và** kết nối mới mở, chênh nhau vài
//! trăm ms. Nếu dọn ngay khi refcount = 0 thì display ảo + encoder bị phá rồi
//! tạo lại ⇒ F5 làm mất hình, mất tiếng, và đôi khi mất luôn cửa sổ đang điều
//! khiển. 5 s là khoảng đủ cho trình duyệt mở lại mà không ai phải chờ.
//!
//! Áp dụng cho: D3D11 device, encoder, cable âm thanh.
//! **Không** áp dụng cho màn hình ảo — nó được **giữ lại** sau khi đóng phiên
//! (§9.2.2), chính là lý do có "khôi phục phiên cũ" (§42.2).

use std::collections::HashMap;

/// §42.13: 5 s.
pub const CLEANUP_DELAY_MS: u64 = 5_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Resource {
    D3d11Device,
    Encoder,
    AudioCable,
    /// Màn hình ảo **không** dọn theo nhịp này (xem doc đầu file).
    VirtualDisplay,
}

impl Resource {
    pub fn label(self) -> &'static str {
        match self {
            Resource::D3d11Device => "d3d11",
            Resource::Encoder => "encoder",
            Resource::AudioCable => "audio_cable",
            Resource::VirtualDisplay => "virtual_display",
        }
    }

    /// Màn hình ảo không bao giờ bị hẹn dọn (giữ để resume).
    pub fn cleaned_eagerly(self) -> bool {
        !matches!(self, Resource::VirtualDisplay)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Idle,
    /// refcount > 0.
    InUse { refs: u32 },
    /// refcount = 0 nhưng còn trong cửa sổ 5 s.
    Pending { due_ms: u64 },
}

#[derive(Default)]
pub struct CleanupTimer {
    resources: HashMap<Resource, (State, u64)>,
    pub cleaned: Vec<(Resource, u64)>,
}

impl CleanupTimer {
    pub fn acquire(&mut self, r: Resource, now_ms: u64) -> u32 {
        let entry = self
            .resources
            .entry(r)
            .or_insert((State::Idle, now_ms));
        let refs = match entry.0 {
            State::InUse { refs } => refs + 1,
            // Pending ⇒ huỷ hẹn dọn (F5 mở lại trong 5 s).
            State::Pending { .. } | State::Idle => 1,
        };
        entry.0 = State::InUse { refs };
        entry.1 = now_ms;
        refs
    }

    pub fn release(&mut self, r: Resource, now_ms: u64) -> State {
        let entry = self
            .resources
            .entry(r)
            .or_insert((State::Idle, now_ms));
        let next = match entry.0 {
            State::InUse { refs: 1 } | State::Idle => {
                if r.cleaned_eagerly() {
                    State::Pending {
                        due_ms: now_ms + CLEANUP_DELAY_MS,
                    }
                } else {
                    State::Idle
                }
            }
            State::InUse { refs } => State::InUse { refs: refs - 1 },
            pending @ State::Pending { .. } => pending,
        };
        entry.0 = next;
        next
    }

    /// Vòng lặp 1 Hz gọi hàm này. Trả về tài nguyên vừa được dọn thật.
    pub fn tick(&mut self, now_ms: u64) -> Vec<Resource> {
        let mut done = Vec::new();
        for (resource, (state, _)) in self.resources.iter_mut() {
            if let State::Pending { due_ms } = *state {
                if now_ms >= due_ms {
                    *state = State::Idle;
                    done.push(*resource);
                    self.cleaned.push((*resource, now_ms));
                }
            }
        }
        done
    }

    pub fn state(&self, r: Resource) -> Option<State> {
        self.resources.get(&r).map(|(state, _)| *state)
    }

    /// Watchdog restore default audio device (§40) chỉ chạy khi **không còn**
    /// tài nguyên nào đang dùng hoặc đang chờ.
    pub fn all_idle(&self) -> bool {
        self.resources
            .values()
            .all(|(state, _)| matches!(state, State::Idle))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T0: u64 = 1_700_000_000_000;

    #[test]
    fn an_f5_within_five_seconds_reuses_the_resource() {
        let mut t = CleanupTimer::default();
        t.acquire(Resource::Encoder, T0);
        assert_eq!(
            t.release(Resource::Encoder, T0 + 100),
            State::Pending {
                due_ms: T0 + CLEANUP_DELAY_MS + 100
            }
        );
        // F5: kết nối mới tới trong 2 s.
        let refs = t.acquire(Resource::Encoder, T0 + 2_100);
        assert_eq!(refs, 1);
        // Không có gì bị dọn.
        assert!(t.tick(T0 + 6_000).is_empty());
        assert_eq!(t.cleaned.len(), 0);
    }

    #[test]
    fn after_five_seconds_the_resource_is_actually_freed() {
        let mut t = CleanupTimer::default();
        t.acquire(Resource::D3d11Device, T0);
        t.release(Resource::D3d11Device, T0);
        assert!(t.tick(T0 + CLEANUP_DELAY_MS - 1).is_empty(), "chưa đủ 5 s");
        assert_eq!(t.tick(T0 + CLEANUP_DELAY_MS), vec![Resource::D3d11Device]);
        assert_eq!(t.state(Resource::D3d11Device), Some(State::Idle));
        assert!(t.all_idle());
    }

    #[test]
    fn refcount_keeps_the_resource_alive() {
        let mut t = CleanupTimer::default();
        assert_eq!(t.acquire(Resource::AudioCable, T0), 1);
        assert_eq!(t.acquire(Resource::AudioCable, T0 + 1), 2);
        assert_eq!(
            t.release(Resource::AudioCable, T0 + 2),
            State::InUse { refs: 1 }
        );
        assert!(t.tick(T0 + 60_000).is_empty(), "vẫn còn 1 ref");
        assert_eq!(t.release(Resource::AudioCable, T0 + 60_001), State::Pending { due_ms: T0 + 65_001 });
    }

    #[test]
    fn the_virtual_display_is_never_cleaned_by_this_timer() {
        // §9.2.2: display được giữ lại; §42.15 #4 kiểm đúng điều này.
        let mut t = CleanupTimer::default();
        t.acquire(Resource::VirtualDisplay, T0);
        assert_eq!(t.release(Resource::VirtualDisplay, T0), State::Idle);
        assert!(t.tick(T0 + 60_000).is_empty());
        assert!(t.cleaned.is_empty());
    }

    #[test]
    fn releasing_twice_does_not_double_schedule() {
        let mut t = CleanupTimer::default();
        t.acquire(Resource::Encoder, T0);
        t.release(Resource::Encoder, T0 + 10);
        let second = t.release(Resource::Encoder, T0 + 20);
        assert_eq!(
            second,
            State::Pending {
                due_ms: T0 + 10 + CLEANUP_DELAY_MS
            },
            "hẹn lần đầu giữ nguyên, không dời"
        );
        assert_eq!(t.tick(T0 + 10 + CLEANUP_DELAY_MS).len(), 1);
        assert_eq!(t.tick(T0 + 20 + CLEANUP_DELAY_MS).len(), 0);
    }

    #[test]
    fn not_all_idle_while_something_is_pending() {
        let mut t = CleanupTimer::default();
        t.acquire(Resource::Encoder, T0);
        t.release(Resource::Encoder, T0);
        assert!(!t.all_idle(), "pending vẫn tính là chưa xong");
        t.tick(T0 + CLEANUP_DELAY_MS);
        assert!(t.all_idle());
    }
}
