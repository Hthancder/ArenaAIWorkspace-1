//! Nối `rd_spike_lib::security` vào HTTP — §8.1 + §57.
//!
//! # Vì sao file này tồn tại
//!
//! `spike/src/security/` đã có 100 test và đúng luật §41/§44/§57. Nhưng đến
//! v3.32 nó vẫn chỉ là **thư viện**: `lantern-mock.exe` không kiểm tra một
//! request nào. Khoảng cách giữa "có code đúng" và "có tác dụng" chính là file
//! này — và nó nhỏ hơn tôi tưởng: mọi quyết định đã có sẵn, chỉ cần gọi.
//!
//! # Ba thứ file này KHÔNG làm
//!
//! 1. **Không tự viết lại luật.** Mọi kiểm tra là lời gọi vào `security::*`.
//! 2. **Không tự sinh token/entropy.** [`RealEntropy`] lấy từ OS; `spike` chỉ
//!    có `FixedEntropy` (xorshift) và tự nói nó "không dùng cho production".
//! 3. **Không log token.** `Session` của spec đã có `Debug` viết tay in
//!    `<redacted N chars>` (§41.10 #12); đường này không in gì khác.

use std::collections::BTreeMap;

use rd_spike_lib::security::auth::{Lockout, LockoutConfig, PasswordFile, StoredPassword};
use rd_spike_lib::security::crypto::Entropy;
use rd_spike_lib::security::gate::{Auth, LoginError, Session, Transport};
use rd_spike_lib::security::token::{TokenConfig, TokenIssuer};

/// Entropy thật từ OS.
///
/// `spike::crypto::FixedEntropy` là xorshift64* — deterministic, đúng cho test
/// và **sai** cho token. Nếu ai nối `FixedEntropy` vào `Auth::login` thì mọi
/// access token trở nên đoán được từ một seed; đó là lỗi bảo mật tệ nhất có
/// thể có trong file này, nên đường production có nguồn riêng.
///
/// Cách lấy: `/dev/urandom` trên Unix, `RtlGenRandom` trên Windows. **Không**
/// dùng thời gian hay PID làm seed — cả hai đều đoán được.
pub struct RealEntropy;

impl Entropy for RealEntropy {
    fn fill(&mut self, out: &mut [u8]) {
        if os_random(out).is_err() {
            // Không có entropy thì **không** được im lặng dùng nguồn yếu:
            // token đoán được còn tệ hơn không chạy.
            panic!("không đọc được entropy từ OS — không thể phát token an toàn");
        }
    }
}

#[cfg(unix)]
fn os_random(out: &mut [u8]) -> std::io::Result<()> {
    use std::io::Read;
    // `/dev/urandom` không chặn sau khi kernel đã khởi tạo pool, và trên
    // Linux hiện đại nó dùng getrandom(2) bên dưới.
    let mut file = std::fs::File::open("/dev/urandom")?;
    file.read_exact(out)
}

#[cfg(windows)]
fn os_random(out: &mut [u8]) -> std::io::Result<()> {
    // `RtlGenRandom` (advapi32) — không cần COM, không cần khởi tạo. Dùng
    // `SystemFunction036` vì đó là tên thật trong export table; `RtlGenRandom`
    // chỉ là alias khai báo trong header.
    #[link(name = "advapi32")]
    extern "system" {
        #[link_name = "SystemFunction036"]
        fn rtl_gen_random(buffer: *mut u8, length: u32) -> u8;
    }
    let ok = unsafe { rtl_gen_random(out.as_mut_ptr(), out.len() as u32) };
    if ok == 0 {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "RtlGenRandom thất bại"));
    }
    Ok(())
}


/// Trạng thái đăng nhập của server, sống cùng `State`.
///
/// Không phải `Option<Auth>` trần vì còn phải nhớ **đang dùng mật khẩu nào**:
/// chưa ai đặt ⇒ `/api/login` trả 412, và UI hiện màn hình `/setup` (§7.1
/// `SETUP ──lưu config──► IDLE`).
pub struct AuthState {
    /// `None` cho tới khi có mật khẩu (§7.1 SETUP chưa xong).
    pub auth: Option<Auth>,
    /// Số lần `/api/setup` được gọi — để test và log biết, không lộ ra ngoài.
    pub setup_calls: u32,
}

impl Default for AuthState {
    fn default() -> Self {
        Self { auth: None, setup_calls: 0 }
    }
}

/// Kết quả `/api/setup`.
pub enum SetupOutcome {
    /// Đặt mật khẩu thành công — từ giờ `/api/login` dùng được.
    Created,
    /// Đã có mật khẩu. §41.6: **không** cho đặt lại mà không có phiên hợp lệ,
    /// nếu không thì ai mở được URL cũng chiếm máy được.
    AlreadyConfigured,
    /// Mật khẩu không đủ mạnh theo §4373 (12 ký tự + không nằm trong danh
    /// sách phổ biến).
    WeakPassword,
}

impl AuthState {
    /// Xử lý `/api/setup`. Chỉ thành công khi **chưa** có mật khẩu.
    pub fn setup(&mut self, user: &str, password: &str, now_ms: u64) -> SetupOutcome {
        if self.auth.is_some() {
            return SetupOutcome::AlreadyConfigured;
        }
        // Luật mật khẩu là của spec (`auth::password_meets_policy`), không phải
        // của file này — gọi, đừng chép lại `MIN_LEN`.
        if !rd_spike_lib::security::auth::password_meets_policy(password) {
            return SetupOutcome::WeakPassword;
        }
        self.auth = Some(auth_from_password(user, password, now_ms));
        self.setup_calls += 1;
        SetupOutcome::Created
    }
}

/// §41.6: 5 lần sai ⇒ khoá 15 phút, tối đa 5 lần/phút/IP.
///
/// **Dùng `Default` của spec**, không viết lại các con số: bản đầu của hàm này
/// chép tay ba trường và bỏ `ip_max_per_minute` — nghĩa là mất giới hạn theo
/// IP mà không ai thấy. Đây đúng là lỗi "hai bản luật" mà file này tồn tại để
/// tránh, lặp lại ngay trong file.
pub fn lockout_config() -> LockoutConfig {
    LockoutConfig::default()
}

/// Dựng `Auth` từ một mật khẩu do người dùng đặt lần đầu.
///
/// `salt` phải là 16 byte **ngẫu nhiên**; hàm này tự sinh bằng [`RealEntropy`]
/// để không ai phải nhớ.
pub fn auth_from_password(user: &str, password: &str, now_ms: u64) -> Auth {
    let mut entropy = RealEntropy;
    let mut salt = [0u8; 16];
    entropy.fill(&mut salt);
    let iterations = rd_spike_lib::security::auth::PBKDF2_ITERATIONS;
    let stored = StoredPassword::new(password, salt, iterations);
    let passwords = PasswordFile::new(user, stored);
    let tokens = TokenIssuer::new(TokenConfig::default(), random_key(now_ms))
        .expect("khoá 32 byte luôn hợp lệ");
    let lockout = Lockout::new(lockout_config());
    Auth::new(passwords, tokens, lockout)
}

/// Khoá HMAC 32 byte ngẫu nhiên.
///
/// `now_ms` chỉ dùng để trộn thêm, **không** phải nguồn chính — nó ở đây vì
/// chữ ký hàm đã có sẵn ở nơi gọi và một chút nhiễu không hại.
fn random_key(now_ms: u64) -> Vec<u8> {
    let mut entropy = RealEntropy;
    let mut key = vec![0u8; 32];
    entropy.fill(&mut key);
    for (slot, byte) in key.iter_mut().take(8).enumerate() {
        *byte ^= now_ms.to_le_bytes()[slot];
    }
    key
}

/// Dịch `LoginError` thành `(status, mã lỗi)`.
///
/// §8.1 ghi rõ: `401/423/429`. Đừng trả `400` cho mọi thứ — người dùng cần
/// phân biệt "sai mật khẩu" với "đang bị khoá".
pub fn login_error_response(error: &LoginError) -> (u16, &'static str) {
    match error {
        LoginError::BadCredential => (401, "bad_credential"),
        LoginError::Locked { .. } => (423, "locked"),
    }
}

/// Response JSON cho một lần đăng nhập thành công.
///
/// Refresh token **không** nằm trong body: nó đi bằng cookie `HttpOnly`
/// (§41.6). Đặt nó trong body thì JavaScript đọc được, và một lỗ XSS sẽ lấy
/// luôn refresh token 7 ngày — đúng thứ cookie `HttpOnly` sinh ra để chặn.
pub fn login_body(session: &Session, expires_in_s: u64) -> String {
    format!(
        "{{\"access\":{},\"user\":{},\"expiresIn\":{}}}",
        json_quote(&session.access),
        json_quote(&session.claims.sub),
        expires_in_s
    )
}

fn json_quote(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push(' '),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// §41.5 D4 / §54.5 #1: **không TLS thì không bind ra LAN**.
///
/// Hàm này tồn tại để luật đó có **một** chỗ gọi, không phải ba chỗ nhớ.
pub fn bind_is_allowed(host: &str, has_cert: bool) -> Result<Transport, String> {
    Transport::for_bind(host, has_cert).map_err(|reason| reason.to_string())
}

/// Tách `Cookie` header. §41.6: refresh token nằm trong cookie `HttpOnly`.
pub fn cookie_value<'a>(headers: &'a BTreeMap<String, String>, name: &str) -> Option<&'a str> {
    let cookie = headers.get("cookie")?;
    for part in cookie.split(';') {
        let part = part.trim();
        if let Some(rest) = part.strip_prefix(name) {
            if let Some(value) = rest.strip_prefix('=') {
                return Some(value);
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test] fn real_entropy_is_not_constant() {
        let mut a = [0u8; 32];
        let mut b = [0u8; 32];
        RealEntropy.fill(&mut a);
        RealEntropy.fill(&mut b);
        assert_ne!(a, b, "hai lần lấy entropy không được giống nhau");
        assert!(a.iter().any(|byte| *byte != 0), "không được toàn số 0");
    }

    #[test] fn real_entropy_has_no_obvious_structure() {
        // Không phải test thống kê đầy đủ — chỉ bắt lỗi "trả cùng một mảng"
        // hoặc "chỉ đổ 8 byte đầu rồi để 0".
        let mut buffer = [0u8; 256];
        RealEntropy.fill(&mut buffer);
        assert!(buffer[128..].iter().any(|byte| *byte != 0), "nửa sau không được toàn 0");
        let unique: std::collections::BTreeSet<u8> = buffer.iter().copied().collect();
        assert!(unique.len() > 100, "256 byte phải có >100 giá trị khác nhau, được {}", unique.len());
    }

    #[test] fn a_correct_password_logs_in_and_a_wrong_one_does_not() {
        let now = 1_700_000_000_000u64;
        let mut auth = auth_from_password("local", "mat-khau-du-dai-12", now);
        let mut entropy = RealEntropy;
        let ok = auth.login("127.0.0.1", "local", "mat-khau-du-dai-12", "dev-1", now, &mut entropy);
        assert!(ok.is_ok(), "mật khẩu đúng phải đăng nhập được: {ok:?}");
        let bad = auth.login("127.0.0.1", "local", "sai-mat-khau", "dev-1", now + 1, &mut entropy);
        assert!(matches!(bad, Err(LoginError::BadCredential)), "{bad:?}");
    }

    #[test] fn five_failures_lock_the_account_even_with_the_right_password() {
        // §41.6: "lockout 5/15′". Đây là bất biến quan trọng nhất của Auth —
        // nếu sai, kẻ tấn công dò được vô hạn.
        let now = 1_700_000_000_000u64;
        let mut auth = auth_from_password("local", "mat-khau-du-dai-12", now);
        let mut entropy = RealEntropy;
        for attempt in 0..5 {
            let _ = auth.login("10.0.0.9", "local", "sai", "dev", now + attempt, &mut entropy);
        }
        let locked = auth.login("10.0.0.9", "local", "mat-khau-du-dai-12", "dev", now + 10, &mut entropy);
        assert!(matches!(locked, Err(LoginError::Locked { .. })), "phải bị khoá: {locked:?}");
        // Và phải nói được là khoá bao lâu (§8.1 trả 423).
        assert_eq!(login_error_response(&locked.unwrap_err()).0, 423);
    }

    #[test] fn a_second_device_does_not_get_a_free_pass() {
        // Không test "device mismatch" ở đây (spec cho qua + cảnh báo, và
        // `spike` đã có test riêng). Test này chỉ khoá rằng `login` **không**
        // trả token khi sai mật khẩu dù device đổi.
        let now = 1_700_000_000_000u64;
        let mut auth = auth_from_password("local", "mat-khau-du-dai-12", now);
        let mut entropy = RealEntropy;
        let bad = auth.login("127.0.0.1", "local", "sai", "may-khac", now, &mut entropy);
        assert!(bad.is_err());
    }

    #[test] fn the_response_body_never_contains_the_refresh_token() {
        let now = 1_700_000_000_000u64;
        let mut auth = auth_from_password("local", "mat-khau-du-dai-12", now);
        let mut entropy = RealEntropy;
        let session = auth
            .login("127.0.0.1", "local", "mat-khau-du-dai-12", "dev", now, &mut entropy)
            .expect("login");
        let body = login_body(&session, 900);
        assert!(body.contains(&session.access), "access token phải có trong body");
        assert!(
            !body.contains(&session.refresh),
            "refresh token KHÔNG được nằm trong body (nó đi bằng cookie HttpOnly)"
        );
        assert!(!body.contains("refresh"), "cả tên trường cũng không");
    }

    #[test] fn the_debug_impl_does_not_leak_tokens() {
        // §41.10 #12: grep log ⇒ 0 token. `Session` của spec tự làm đúng; test
        // này chứng minh ta không vô tình thêm một derive nào ghi đè.
        let now = 1_700_000_000_000u64;
        let mut auth = auth_from_password("local", "mat-khau-du-dai-12", now);
        let mut entropy = RealEntropy;
        let session = auth
            .login("127.0.0.1", "local", "mat-khau-du-dai-12", "dev", now, &mut entropy)
            .expect("login");
        let debug = format!("{session:?}");
        assert!(!debug.contains(&session.access), "Debug không được in access token");
        assert!(!debug.contains(&session.refresh), "Debug không được in refresh token");
        assert!(debug.contains("redacted"), "phải nói rõ là đã che: {debug}");
    }

    #[test] fn bind_to_lan_without_tls_is_refused() {
        assert!(bind_is_allowed("0.0.0.0", false).is_err(), "không TLS ⇒ không bind LAN");
        assert!(bind_is_allowed("0.0.0.0", true).is_ok(), "có TLS thì được");
        assert!(bind_is_allowed("127.0.0.1", false).is_ok(), "loopback thì luôn được");
    }

    #[test] fn a_cookie_is_read_by_name_and_not_by_luck() {
        let mut headers = BTreeMap::new();
        headers.insert(
            "cookie".to_string(),
            "theme=dark; lantern_refresh=rt.abc.def; other=1".to_string(),
        );
        assert_eq!(cookie_value(&headers, "lantern_refresh"), Some("rt.abc.def"));
        assert_eq!(cookie_value(&headers, "theme"), Some("dark"));
        // Không được khớp tiền tố: `lantern_ref` không phải `lantern_refresh`.
        assert_eq!(cookie_value(&headers, "lantern_ref"), None);
        assert_eq!(cookie_value(&headers, "khong-co"), None);
    }
}
