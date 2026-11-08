//! Harness & transport policy: bắt tay đăng nhập, CSRF, headers chống
//! clickjacking, và **cổng TLS không tắt được** (spec §41.5 D4, §41.4 T6/T20,
//! §54.5 #1–2).
//!
//! Nguyên tắc đến từ §41.3: **client không được tin**. Mọi thứ client gửi đều
//! được kiểm tra lại ở đây hoặc ở module khác — không có thứ gì "đã đăng nhập
//! nên khỏi kiểm".

use std::collections::HashMap;

use super::auth::{Gate, Lockout, PasswordFile};
use super::crypto::Entropy;
use super::token::{RefreshOutcome, RefreshStore, Rotated, TokenIssuer};

/// Cổng TLS. Không có biến thể "tắt" — §54.5 #1: TLS bắt buộc, không có tuỳ
/// chọn tắt. Trong sandbox/test thì `Loopback` được phép vì gói không ra khỏi
/// máy; mọi địa chỉ khác **phải** có cert.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Transport {
    Tls,
    /// `127.0.0.1` hoặc `[::1]` — không qua dây mạng.
    Loopback,
}

impl Transport {
    pub fn for_bind(host: &str, has_cert: bool) -> Result<Self, &'static str> {
        let is_loopback = matches!(host, "127.0.0.1" | "::1" | "[::1]" | "localhost");
        if has_cert {
            Ok(Transport::Tls)
        } else if is_loopback {
            Ok(Transport::Loopback)
        } else {
            Err("refusing to listen without TLS on a non-loopback interface (spec §54.5 #1)")
        }
    }

    pub fn cookie_secure(self) -> bool {
        true
    }
}

/// Header phải có trên **mọi** response. Một chỗ duy nhất, để test grep được.
pub fn security_headers(transport: Transport) -> Vec<(&'static str, String)> {
    let mut out = vec![
        // §41.5 D4: clickjacking nút "cho phép điều khiển".
        ("X-Frame-Options", "DENY".to_string()),
        ("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'none'; form-action 'self'".to_string()),
        ("X-Content-Type-Options", "nosniff".to_string()),
        ("Referrer-Policy", "no-referrer".to_string()),
        // Không cho camera/mic/geo: ta không cần, và xin thì phải giải thích.
        ("Permissions-Policy", "camera=(), microphone=(), geolocation=()".to_string()),
        ("Cache-Control", "no-store".to_string()),
    ];
    if transport == Transport::Tls {
        out.push((
            "Strict-Transport-Security",
            "max-age=31536000; includeSubDomains".to_string(),
        ));
    }
    out
}

/// @ `HttpOnly` + `Secure` + `SameSite=Strict` + `Path=/api` (§41.6).
pub fn session_cookie(name: &str, value: &str, max_age_s: u64) -> String {
    format!(
        "{name}={value}; HttpOnly; Secure; SameSite=Strict; Path=/api; Max-Age={max_age_s}"
    )
}

/// §41.5 D4: **không** nhận token trong URL. Link chia sẻ dùng token riêng
/// (§21.6), không phải `?access=`.
pub fn url_carries_token(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    ["access=", "token=", "jwt=", "bearer=", "password="]
        .iter()
        .any(|needle| lower.contains(needle))
}

/// Custom header cho mọi mutation: form HTML của trang khác **không** set được
/// header, nên CSRF chết ở đây dù SameSite bị một trình duyệt cũ bỏ qua.
pub const CSRF_HEADER: &str = "x-lantern-csrf";
pub const CSRF_VALUE: &str = "1";

/// POST/PUT/PATCH/DELETE có custom header và `Origin` khớp `Host`.
pub fn mutation_is_same_origin(method: &str, headers: &[(&str, &str)], host: &str) -> bool {
    if !matches!(method, "POST" | "PUT" | "PATCH" | "DELETE") {
        return true;
    }
    let get = |name: &str| -> Option<&str> {
        headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| *v)
    };
    if get(CSRF_HEADER) != Some(CSRF_VALUE) {
        return false;
    }
    match get("origin") {
        // Curl/test không có Origin: chỉ chấp nhận **không** có cookie auth
        // (xử lý ở tầng handler). Ở đây coi như thiếu Origin là từ chối.
        None => false,
        Some(origin) => {
            let expected_http = format!("http://{host}");
            let expected_https = format!("https://{host}");
            origin == expected_http || origin == expected_https
        }
    }
}

// ---------- phiên đăng nhập ----------

#[derive(Debug, Clone, PartialEq)]
pub enum LoginError {
    /// Sai mật khẩu **hoặc** user không tồn tại — cùng một lỗi, cùng một câu
    /// (§41.6 "Timing": không lộ user có thật).
    BadCredential,
    Locked { retry_after_s: u64 },
}

#[derive(Clone, PartialEq)]
pub struct Session {
    pub access: String,
    pub refresh: String,
    pub claims: super::token::Claims,
    pub device_mismatch: bool,
}

/// §41.10 #12 / §26.3: token **không bao giờ** được lọt vào log. Một
/// `#[derive(Debug)]` ở đây là đủ để `tracing::debug!("{session:?}")` ghi nguyên
/// token vào file — nên Debug được viết tay để in **độ dài**, không in giá trị.
impl std::fmt::Debug for Session {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Session")
            .field("access", &format_args!("<redacted {} chars>", self.access.len()))
            .field("refresh", &format_args!("<redacted {} chars>", self.refresh.len()))
            .field("sub", &self.claims.sub)
            .field("exp_ms", &self.claims.exp_ms)
            .field("device_mismatch", &self.device_mismatch)
            .finish()
    }
}

pub struct Auth {
    pub passwords: PasswordFile,
    pub lockout: Lockout,
    pub tokens: TokenIssuer,
    pub refresh: RefreshStore,
}

impl Auth {
    pub fn new(passwords: PasswordFile, tokens: TokenIssuer, lockout: Lockout) -> Self {
        let refresh = RefreshStore::new(tokens.config().clone());
        Self {
            passwords,
            lockout,
            tokens,
            refresh,
        }
    }

    pub fn login(
        &mut self,
        ip: &str,
        user: &str,
        password: &str,
        device_id: &str,
        now_ms: u64,
        entropy: &mut impl Entropy,
    ) -> Result<Session, LoginError> {
        match self.lockout.gate(ip, user, now_ms) {
            // Khoá kiểm **trước** khi băm: đang khoá thì không tốn KDF.
            Gate::Locked { retry_after_s } => return Err(LoginError::Locked { retry_after_s }),
            Gate::Allowed => {}
        }

        let outcome = self.passwords.verify_attempt(user, password);
        if !outcome.matched {
            let gate = self.lockout.failure(ip, user, now_ms);
            return Err(match gate {
                Gate::Locked { retry_after_s } => LoginError::Locked { retry_after_s },
                Gate::Allowed => LoginError::BadCredential,
            });
        }
        self.lockout.success(ip, user);

        let (access, claims) = self.tokens.issue_access(user, "owner", "*", now_ms, entropy);
        let refresh = self.refresh.issue(user, device_id, now_ms, entropy);
        Ok(Session {
            access,
            refresh,
            claims,
            device_mismatch: false,
        })
    }

    pub fn refresh_session(
        &mut self,
        refresh_token: &str,
        device_id: &str,
        now_ms: u64,
        entropy: &mut impl Entropy,
    ) -> Option<Rotated> {
        match self.refresh.rotate(
            refresh_token,
            device_id,
            now_ms,
            &self.tokens,
            "owner",
            entropy,
        ) {
            RefreshOutcome::Rotated(rotated) => Some(rotated),
            _ => None,
        }
    }

    /// Kiểm access token cho một request **có** `sid`. `expected_sub` không phải
    /// tuỳ chọn — nó chính là §41.4 T3.
    pub fn authorize(&self, jwt: &str, sid_owner: &str, now_ms: u64) -> Result<super::token::Claims, super::token::TokenError> {
        self.tokens.verify(
            jwt,
            now_ms,
            Some(sid_owner),
            self.refresh.revoked_before(sid_owner),
        )
    }
}

/// Đếm request theo cửa sổ trượt, dùng cho `/api/windows` 30/phút (§41.4 T18)
/// và các giới hạn §44.8. Không dùng cho login (đã có `Lockout`).
#[derive(Debug, Clone, Default)]
pub struct RateLimiter {
    buckets: HashMap<String, Vec<u64>>,
}

impl RateLimiter {
    pub fn new() -> Self {
        Self::default()
    }

    /// `true` = cho qua. Ghi nhận chỉ khi cho qua.
    pub fn check(&mut self, key: &str, max: u32, window_ms: u64, now_ms: u64) -> bool {
        let times = self.buckets.entry(key.to_string()).or_default();
        times.retain(|t| now_ms.saturating_sub(*t) < window_ms);
        if times.len() as u32 >= max {
            return false;
        }
        times.push(now_ms);
        true
    }

    /// Số request còn lại trong cửa sổ — cho header `X-RateLimit-Remaining`.
    pub fn remaining(&mut self, key: &str, max: u32, window_ms: u64, now_ms: u64) -> u32 {
        let times = self.buckets.entry(key.to_string()).or_default();
        times.retain(|t| now_ms.saturating_sub(*t) < window_ms);
        max.saturating_sub(times.len() as u32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::auth::{LockoutConfig, StoredPassword};
    use crate::security::crypto::FixedEntropy;
    use crate::security::token::TokenConfig;

    const T0: u64 = 1_700_000_000_000;

    fn auth() -> Auth {
        let passwords = PasswordFile::new(
            "owner",
            StoredPassword::new("correct horse", [9u8; 16], 1),
        );
        let tokens = TokenIssuer::new(TokenConfig::default(), vec![3u8; 32]).unwrap();
        Auth::new(passwords, tokens, Lockout::new(LockoutConfig::default()))
    }

    #[test]
    fn there_is_no_way_to_turn_tls_off_on_a_lan_interface() {
        // §54.5 #1 — không có nhánh nào trả Ok khi bind 0.0.0.0 mà không cert.
        assert!(Transport::for_bind("0.0.0.0", false).is_err());
        assert!(Transport::for_bind("192.168.1.10", false).is_err());
        assert!(Transport::for_bind("100.64.0.5", false).is_err());
        assert_eq!(Transport::for_bind("127.0.0.1", false), Ok(Transport::Loopback));
        assert_eq!(Transport::for_bind("0.0.0.0", true), Ok(Transport::Tls));
        assert!(Transport::for_bind("0.0.0.0", true).unwrap().cookie_secure());
    }

    #[test]
    fn headers_block_frames_and_disable_referrer() {
        let headers = security_headers(Transport::Tls);
        let get = |name: &str| headers.iter().find(|(k, _)| *k == name).map(|(_, v)| v.clone());
        assert_eq!(get("X-Frame-Options").as_deref(), Some("DENY"));
        assert!(get("Content-Security-Policy")
            .unwrap()
            .contains("frame-ancestors 'none'"));
        assert_eq!(get("Referrer-Policy").as_deref(), Some("no-referrer"));
        assert!(get("Strict-Transport-Security").is_some());

        // Loopback không có HSTS (không có https để ép).
        assert!(security_headers(Transport::Loopback)
            .iter()
            .all(|(k, _)| *k != "Strict-Transport-Security"));
    }

    #[test]
    fn session_cookie_is_http_only_and_not_readable_from_js() {
        let cookie = session_cookie("lantern_rt", "rt.abc.def", 604_800);
        for part in ["HttpOnly", "Secure", "SameSite=Strict", "Path=/api"] {
            assert!(cookie.contains(part), "thiếu {part}: {cookie}");
        }
    }

    #[test]
    fn tokens_in_a_url_are_detected() {
        assert!(url_carries_token("/s/abc?access=eyJhbGci"));
        assert!(url_carries_token("/?TOKEN=abc"));
        assert!(!url_carries_token("/s/abc"));
    }

    #[test]
    fn mutations_need_the_custom_header_and_same_origin() {
        let host = "127.0.0.1:8443";
        assert!(mutation_is_same_origin("GET", &[], host), "GET không cần CSRF");
        assert!(!mutation_is_same_origin("POST", &[], host), "thiếu header ⇒ từ chối");
        assert!(!mutation_is_same_origin(
            "POST",
            &[(CSRF_HEADER, CSRF_VALUE), ("origin", "https://evil.example")],
            host
        ));
        assert!(mutation_is_same_origin(
            "POST",
            &[(CSRF_HEADER, CSRF_VALUE), ("origin", "http://127.0.0.1:8443")],
            host
        ));
        // Thiếu Origin cũng bị từ chối: handler test dùng API trực tiếp, không đi qua HTTP.
        assert!(!mutation_is_same_origin(
            "DELETE",
            &[(CSRF_HEADER, CSRF_VALUE)],
            host
        ));
    }

    #[test]
    fn login_failure_hides_whether_the_user_exists() {
        let mut a = auth();
        let mut e = FixedEntropy::new(1);
        let wrong = a.login("10.0.0.1", "owner", "nope", "d", T0, &mut e);
        let unknown = a.login("10.0.0.1", "ghost", "nope", "d", T0, &mut e);
        assert_eq!(wrong, Err(LoginError::BadCredential));
        assert_eq!(unknown, Err(LoginError::BadCredential));
        assert_eq!(wrong, unknown);
    }

    #[test]
    fn login_locks_after_five_failures_and_never_returns_a_token() {
        let mut a = auth();
        let mut e = FixedEntropy::new(1);
        for i in 0..4 {
            assert_eq!(
                a.login("10.0.0.1", "owner", "nope", "d", T0 + i, &mut e),
                Err(LoginError::BadCredential)
            );
        }
        assert!(matches!(
            a.login("10.0.0.1", "owner", "nope", "d", T0 + 5, &mut e),
            Err(LoginError::Locked { .. })
        ));
        // Kể cả mật khẩu đúng cũng bị chặn trong thời gian khoá: nếu không, kẻ
        // tấn công dò được bằng cách "thử cho tới khi đúng".
        assert!(matches!(
            a.login("10.0.0.1", "owner", "correct horse", "d", T0 + 6, &mut e),
            Err(LoginError::Locked { .. })
        ));
    }

    #[test]
    fn successful_login_issues_both_tokens_and_the_access_verifies() {
        let mut a = auth();
        let mut e = FixedEntropy::new(1);
        let session = a
            .login("10.0.0.1", "owner", "correct horse", "laptop", T0, &mut e)
            .expect("login");
        assert_eq!(a.authorize(&session.access, "owner", T0 + 1).map(|c| c.sub), Ok("owner".to_string()));
        // `sid` của người khác ⇒ WrongSubject, không phải "dùng được".
        assert_eq!(
            a.authorize(&session.access, "guest", T0 + 1),
            Err(crate::security::token::TokenError::WrongSubject)
        );
        assert!(session.refresh.starts_with("rt."));
        // §54.5 #2: không có frame nào trước khi auth ⇒ luồng chỉ mở qua token.
    }

    #[test]
    fn refresh_flow_keeps_the_session_alive_without_the_password() {
        let mut a = auth();
        let mut e = FixedEntropy::new(1);
        let session = a
            .login("10.0.0.1", "owner", "correct horse", "laptop", T0, &mut e)
            .unwrap();
        let rotated = a
            .refresh_session(&session.refresh, "laptop", T0 + 60_000, &mut e)
            .expect("rotate");
        assert_eq!(rotated.claims.sub, "owner");
        assert!(a.authorize(&rotated.access, "owner", T0 + 61_000).is_ok());
    }

    #[test]
    fn a_revoked_session_cannot_refresh_or_use_old_access() {
        let mut a = auth();
        let mut e = FixedEntropy::new(1);
        let session = a
            .login("10.0.0.1", "owner", "correct horse", "laptop", T0, &mut e)
            .unwrap();
        a.refresh.revoke_all("owner", T0 + 10);
        assert!(a
            .refresh_session(&session.refresh, "laptop", T0 + 20, &mut e)
            .is_none());
        assert_eq!(
            a.authorize(&session.access, "owner", T0 + 20),
            Err(crate::security::token::TokenError::Revoked)
        );
    }

    #[test]
    fn rate_limiter_allows_then_blocks_then_recovers() {
        let mut rl = RateLimiter::new();
        for i in 0..30 {
            assert!(rl.check("windows:owner", 30, 60_000, T0 + i), "request {}", i + 1);
        }
        assert!(!rl.check("windows:owner", 30, 60_000, T0 + 100), "thứ 31 trong 1 phút");
        assert_eq!(rl.remaining("windows:owner", 30, 60_000, T0 + 100), 0);
        // Cửa sổ trượt: sau 61 s thì mở lại.
        assert!(rl.check("windows:owner", 30, 60_000, T0 + 61_000));
        // Khoá theo key: user khác không bị ảnh hưởng.
        assert!(rl.check("windows:guest", 30, 60_000, T0 + 100));
    }
}
