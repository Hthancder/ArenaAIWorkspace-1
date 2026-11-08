//! Security = **tầng `[CỨNG]` của spec, viết thành code test được** (§41, §54.5).
//!
//! Bảy nhóm dưới đây là những luật mà sai một lần là mất thứ không lấy lại được,
//! và **tất cả** đều kiểm được ngoài môi trường thật (không cần GPU, không cần
//! Windows, không cần GStreamer) — đó là lý do §56.6 khuyên làm module này trước.
//!
//! | Module | Luật `[CỨNG]` | Spec |
//! |---|---|---|
//! | [`crypto`] | SHA-256 · HMAC · so sánh hằng thời gian · entropy (tự viết, neo vào vector FIPS/RFC) | §41.6 |
//! | [`codec`] | base64url không padding · UUID v7 cho `sid`/`intent_id` · JSON claims phẳng | §32.2, §41.6 |
//! | [`auth`] | lockout 5/15′ · user lạ tốn **đúng một** KDF · policy mật khẩu 12 ký tự | §41.6, §5.8 |
//! | [`token`] | `alg:none` bị từ chối · `sid.owner == sub` · reuse refresh ⇒ chết cả chuỗi · revoke-all chết **ngay** | §41.4 T3, §41.6 |
//! | [`gate`] | không có TLS thì **không** bind ra LAN · `X-Frame-Options: DENY` · không nhận token trong URL · mutation cần custom header | §41.5 D4, §54.5 #1–2, T6, T20 |
//! | [`window`] | client **không bao giờ** gửi `hwnd`; `wid` phải nằm trong danh sách agent vừa trả (cache 3 s) | §41.4 T1, §41.5 D1 |
//! | [`input`] | clamp `u16` · chặn `Win+L` và SAS · `release_all` idempotent + nhảy hàng · watchdog 3 s | §44.2, §44.8, §6.5.4 |
//! | [`refresh`] | dọn tài nguyên **sau 5 s** để F5 không phá display | §42.13 |

pub mod auth;
pub mod codec;
pub mod crypto;
pub mod gate;
pub mod input;
pub mod refresh;
pub mod token;
pub mod window;

/// Những chỗ code **cố ý** khác chữ trong spec, kèm lý do và điều kiện quay lại.
///
/// Danh sách này là một phần của module, không phải ghi chú: nếu ai đọc spec
/// rồi tự hỏi "sao code không giống", câu trả lời nằm ở đây thay vì trong đầu
/// người viết. §57 của spec cũng chép lại bảng này.
pub struct Deviation {
    pub id: &'static str,
    pub spec_says: &'static str,
    pub code_does: &'static str,
    pub why: &'static str,
    /// Điều kiện để quay lại đúng spec.
    pub revisit_when: &'static str,
}

pub const DEVIATIONS: &[Deviation] = &[
    Deviation {
        id: "D-1",
        spec_says: "§41.6 access token JWT RS256",
        code_does: "HS256 (HMAC-SHA256), khoá đối xứng ≥ 32 byte",
        why: "RS256 cần crate RSA/ring ⇒ 2–6 dependency, đúng thứ §56.1 cắt. Cả hai đầu token đều ở trên cùng một máy của bạn nên khoá đối xứng không mất tính chất bảo mật nào ở đây.",
        revisit_when: "khi có client thứ ba không được giữ khoá ký (ví dụ link xem tạm cho người khác dùng server khác)",
    },
    Deviation {
        id: "D-2",
        spec_says: "§41.6 mật khẩu argon2id (m=64 MB, t=3, p=1)",
        code_does: "PBKDF2-HMAC-SHA256, 210 000 vòng, salt 16 byte",
        why: "argon2 cần crate ⇒ dependency + build C. PBKDF2-HMAC-SHA256 210k vòng ≈ 100–200 ms trên i5-7300HQ, đủ chậm cho 1 người dùng, và đúng chuẩn NIST SP 800-132.",
        revisit_when: "khi cần nhiều user hoặc hash bị lộ (mức đe doạ P7), lúc đó đổi sang argon2id và migrate bằng salt+iterations đã lưu trong record",
    },
    Deviation {
        id: "D-3",
        spec_says: "§41.6 refresh token 7 ngày (một số chỗ khác ghi 30 ngày)",
        code_does: "7 ngày, hằng số `TokenConfig::refresh_ttl_ms` — một nguồn duy nhất",
        why: "Hai con số trong spec là lỗi chép; 7 ngày khớp §9.11 `refresh_days: 7`.",
        revisit_when: "không — sửa spec chứ không sửa code (đã sửa ở v3.28)",
    },
    Deviation {
        id: "D-4",
        spec_says: "§41 threat model giả định nhiều người dùng và nhiều role",
        code_does: "một người dùng `owner`, một role; mọi kiểm tra `sid.owner == sub` vẫn đầy đủ",
        why: "§0.3.1 #4 cắt multi-user. Giữ nguyên phần kiểm tra quyền vì nó là thứ khiến \"1 mật khẩu\" vẫn an toàn khi bất kỳ ai trong LAN mở được URL (§41.3).",
        revisit_when: "khi thêm người dùng thứ hai — lúc đó `role` đã có sẵn trong claims, không phải đổi schema token",
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_spec_numbers_are_the_defaults_in_code() {
        // Mỗi con số ở bảng đầu file có **một** nguồn: default của module.
        // Nếu ai đổi default mà không sửa spec (hoặc ngược lại), test này đỏ.
        let lockout = auth::LockoutConfig::default();
        assert_eq!(lockout.max_failures, 5, "§41.6: 5 lần");
        assert_eq!(lockout.window_ms, 15 * 60 * 1000, "§41.6: 15 phút");
        assert_eq!(lockout.lock_ms, 15 * 60 * 1000, "§41.6: khoá 15 phút");

        let tokens = token::TokenConfig::default();
        assert_eq!(tokens.access_ttl_ms, 15 * 60 * 1000, "§41.6: access 15 phút");
        assert_eq!(tokens.refresh_ttl_ms, 7 * 24 * 3600 * 1000, "§9.11: refresh 7 ngày");
        assert_eq!(tokens.clock_skew_ms, 60_000, "§41.6: skew ±60 s");

        assert_eq!(window::SNAPSHOT_TTL_MS, 3_000, "§41.4 T1: cache 3 s");
        assert_eq!(input::STUCK_RELEASE_MS, 3_000, "§6.5.4: watchdog 3 s");
        assert_eq!(input::MAX_KEYS_HELD, 16, "§44.8: >16 phím ⇒ reset");
        assert_eq!(refresh::CLEANUP_DELAY_MS, 5_000, "§42.13: dọn sau 5 s");
    }

    #[test]
    fn deviations_are_explicit_and_reversible() {
        // Không có "deviation" nào không có điều kiện quay lại — nếu có, nó
        // không phải deviation mà là spec sai.
        assert!(DEVIATIONS.len() >= 3);
        for d in DEVIATIONS {
            assert!(!d.revisit_when.is_empty(), "{} thiếu điều kiện quay lại", d.id);
            assert!(!d.why.is_empty(), "{} thiếu lý do", d.id);
        }
        let ids: Vec<&str> = DEVIATIONS.iter().map(|d| d.id).collect();
        let mut sorted = ids.clone();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(ids.len(), sorted.len(), "id trùng");
    }
}
