//! Mật khẩu + lockout (spec §41.6, §5.8).
//!
//! Ba thứ ở đây **không** phải sở thích, và mỗi thứ có test:
//! 1. Sai mật khẩu và **user không tồn tại** phải tốn **đúng một** lần KDF ⇒
//!    thời gian trả lời không tiết lộ user có thật hay không.
//! 2. So sánh hash **hằng thời gian** (`crypto::ct_eq`).
//! 3. Lockout đếm **cả** user không tồn tại, khoá theo `(IP, user)` **và** theo
//!    IP riêng (chống spray mật khẩu qua nhiều username).

use std::collections::HashMap;

use super::crypto::{ct_eq, hmac_sha256};

/// Số vòng PBKDF2. Spec §41.6 ghi `argon2id (m=64MB,t=3,p=1)`; xem
/// `security::DEVIATIONS` — ở đây là PBKDF2-HMAC-SHA256 vì 0 dependency, và vì
/// đây là chỗ **duy nhất** phải quay lại spec khi thêm crate.
pub const PBKDF2_ITERATIONS: u32 = 210_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StoredPassword {
    pub salt: [u8; 16],
    pub iterations: u32,
    pub hash: [u8; 32],
}

/// PBKDF2-HMAC-SHA256, `dkLen = 32` ⇒ chỉ cần block index 1 (RFC 8018 §5.2).
pub fn pbkdf2_sha256(password: &[u8], salt: &[u8], iterations: u32) -> [u8; 32] {
    let rounds = iterations.max(1);

    let mut block = Vec::with_capacity(salt.len() + 4);
    block.extend_from_slice(salt);
    block.extend_from_slice(&1u32.to_be_bytes());

    let mut u = hmac_sha256(password, &block);
    let mut out = u;
    let mut round = 1u32;
    while round < rounds {
        u = hmac_sha256(password, &u);
        for (o, b) in out.iter_mut().zip(u.iter()) {
            *o ^= b;
        }
        round += 1;
    }
    out
}

impl StoredPassword {
    pub fn new(password: &str, salt: [u8; 16], iterations: u32) -> Self {
        Self {
            salt,
            iterations,
            hash: pbkdf2_sha256(password.as_bytes(), &salt, iterations),
        }
    }

    pub fn verify(&self, password: &str) -> bool {
        let candidate = pbkdf2_sha256(password.as_bytes(), &self.salt, self.iterations);
        ct_eq(&candidate, &self.hash)
    }
}

/// Kết quả một lần đăng nhập. `kdf_runs` tồn tại **chỉ** để test chứng minh
/// nhánh "user không tồn tại" không rẻ hơn nhánh "sai mật khẩu".
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VerifyOutcome {
    pub matched: bool,
    pub kdf_runs: u32,
}

/// File mật khẩu 1 người dùng + một hash "mồi" cho user không tồn tại.
pub struct PasswordFile {
    user: String,
    stored: StoredPassword,
    dummy: StoredPassword,
}

impl PasswordFile {
    pub fn new(user: &str, stored: StoredPassword) -> Self {
        Self {
            user: user.to_string(),
            stored,
            // Salt cố định: mồi này không bảo vệ gì, nó chỉ để **tiêu cùng một
            // lượng thời gian**. Không bao giờ khớp vì hash sinh từ mật khẩu
            // ngẫu nhiên không thể đoán.
            dummy: StoredPassword::new(
                "lantern-dummy-password-never-matches",
                [0x5a; 16],
                stored.iterations,
            ),
        }
    }

    pub fn user(&self) -> &str {
        &self.user
    }

    /// Luôn chạy **đúng một** KDF, bất kể user có tồn tại hay không.
    pub fn verify_attempt(&self, user: &str, password: &str) -> VerifyOutcome {
        if user == self.user {
            VerifyOutcome {
                matched: self.stored.verify(password),
                kdf_runs: 1,
            }
        } else {
            let _ = self.dummy.verify(password);
            VerifyOutcome {
                matched: false,
                kdf_runs: 1,
            }
        }
    }

    pub fn rotate(&mut self, password: &str, salt: [u8; 16]) {
        self.stored = StoredPassword::new(password, salt, self.stored.iterations);
    }
}

/// §41.6 "Password: min 12 ký tự, không cấm ký tự đặc biệt, kiểm tra danh sách
/// phổ biến". Chạy ở `/setup`; ở đây để **một nguồn** luật, test được, và để
/// server không bao giờ khởi động với mật khẩu rỗng (§0.3.3 #1: 1 mật khẩu là
/// thứ duy nhất đứng giữa LAN và màn hình của bạn).
pub fn password_meets_policy(password: &str) -> bool {
    const MIN_LEN: usize = 12;
    const COMMON: &[&str] = &[
        "password", "password123", "123456789012", "qwertyuiop12", "matkhau123456",
        "lantern12345", "111111111111", "admin1234567",
    ];
    if password.chars().count() < MIN_LEN {
        return false;
    }
    let lower = password.to_lowercase();
    if COMMON.contains(&lower.as_str()) {
        return false;
    }
    // Không cấm ký tự đặc biệt, nhưng toàn khoảng trắng thì không phải mật khẩu.
    password.chars().any(|c| !c.is_whitespace())
}

/// §41.6: 5 lần / 15 phút / (IP+user), khoá 15 phút. §5.8: 5/phút/IP.
/// Hai luật **khác phạm vi**, không mâu thuẫn: luật IP chặn dò nhanh, luật
/// (IP+user) chặn dò chậm. Cả hai cùng tồn tại ở đây.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LockoutConfig {
    pub max_failures: u32,
    pub window_ms: u64,
    pub lock_ms: u64,
    pub ip_max_per_minute: u32,
}

impl Default for LockoutConfig {
    fn default() -> Self {
        Self {
            max_failures: 5,
            window_ms: 15 * 60 * 1000,
            lock_ms: 15 * 60 * 1000,
            ip_max_per_minute: 5,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Gate {
    Allowed,
    Locked { retry_after_s: u64 },
}

impl Gate {
    pub fn is_locked(self) -> bool {
        matches!(self, Gate::Locked { .. })
    }
}

#[derive(Debug, Default)]
struct Attempts {
    times: Vec<u64>,
}

impl Attempts {
    fn push(&mut self, now_ms: u64, window_ms: u64) {
        self.times.push(now_ms);
        self.times.retain(|t| now_ms.saturating_sub(*t) < window_ms);
    }

    fn count(&mut self, now_ms: u64, window_ms: u64) -> usize {
        self.times.retain(|t| now_ms.saturating_sub(*t) < window_ms);
        self.times.len()
    }
}

/// Bộ đếm lockout. Không có state trên đĩa: khoá 15 phút mà restart app là mở
/// lại — với 1 người dùng và bind loopback/`tailnet` thì đây là đánh đổi đã biết
/// (ghi ở §57, không giấu).
pub struct Lockout {
    cfg: LockoutConfig,
    per_key: HashMap<String, Attempts>,
    per_ip: HashMap<String, Attempts>,
    locked_until: HashMap<String, u64>,
}

impl Default for Lockout {
    fn default() -> Self {
        Self::new(LockoutConfig::default())
    }
}

impl Lockout {
    pub fn new(cfg: LockoutConfig) -> Self {
        Self {
            cfg,
            per_key: HashMap::new(),
            per_ip: HashMap::new(),
            locked_until: HashMap::new(),
        }
    }

    pub fn config(&self) -> LockoutConfig {
        self.cfg
    }

    fn key(ip: &str, user: &str) -> String {
        format!("{ip}|{user}")
    }

    /// Kiểm tra **trước** khi băm mật khẩu: nếu đang khoá thì trả 423 ngay,
    /// không tốn KDF (một đòn DoS rẻ hơn nếu bắt buộc băm).
    pub fn gate(&mut self, ip: &str, user: &str, now_ms: u64) -> Gate {
        let key = Self::key(ip, user);
        if let Some(until) = self.locked_until.get(&key).copied() {
            if until > now_ms {
                return Gate::Locked {
                    retry_after_s: retry_after_s(until, now_ms),
                };
            }
            self.locked_until.remove(&key);
        }

        let per_ip = self
            .per_ip
            .entry(ip.to_string())
            .or_default()
            .count(now_ms, 60_000);
        if per_ip as u32 >= self.cfg.ip_max_per_minute {
            return Gate::Locked { retry_after_s: 60 };
        }

        Gate::Allowed
    }

    /// Ghi một lần sai. Trả về gate **sau** khi ghi, để caller dùng luôn.
    pub fn failure(&mut self, ip: &str, user: &str, now_ms: u64) -> Gate {
        let key = Self::key(ip, user);
        let window = self.cfg.window_ms;

        self.per_ip
            .entry(ip.to_string())
            .or_default()
            .push(now_ms, 60_000);
        let attempts = self.per_key.entry(key.clone()).or_default();
        attempts.push(now_ms, window);

        if attempts.count(now_ms, window) as u32 >= self.cfg.max_failures {
            self.locked_until.insert(key, now_ms + self.cfg.lock_ms);
        }
        self.gate(ip, user, now_ms)
    }

    /// Đăng nhập đúng ⇒ xoá bộ đếm của **cặp** (IP,user) và của IP.
    /// Xoá cả IP là có chủ ý: người dùng thật gõ sai 4 lần rồi đúng thì không
    /// được khoá 1 phút ở lần sau. Chống spray vẫn còn ở luật (IP,user).
    pub fn success(&mut self, ip: &str, user: &str) {
        self.locked_until.remove(&Self::key(ip, user));
        self.per_key.remove(&Self::key(ip, user));
        self.per_ip.remove(ip);
    }

    pub fn locked_keys(&self) -> usize {
        self.locked_until.len()
    }
}

fn retry_after_s(until_ms: u64, now_ms: u64) -> u64 {
    until_ms.saturating_sub(now_ms).div_ceil(1000).max(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file() -> PasswordFile {
        // 1 vòng cho test nhanh; độ mạnh không phải thứ test này kiểm.
        PasswordFile::new("owner", StoredPassword::new("correct horse", [1u8; 16], 1))
    }

    #[test]
    fn pbkdf2_matches_rfc6070_vector() {
        // RFC 6070 test case 1: P="password", S="salt", c=1, dkLen=32.
        assert_eq!(
            super::super::crypto::hex(&pbkdf2_sha256(b"password", b"salt", 1)),
            "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
        );
    }

    #[test]
    fn right_and_wrong_password() {
        let f = file();
        assert!(f.verify_attempt("owner", "correct horse").matched);
        assert!(!f.verify_attempt("owner", "correct horse ").matched);
        assert!(!f.verify_attempt("owner", "").matched);
    }

    #[test]
    fn unknown_user_costs_exactly_one_kdf() {
        // §41.6 "Timing": hai nhánh phải **cùng** lượng việc.
        let f = file();
        let unknown = f.verify_attempt("someone-else", "correct horse");
        let wrong = f.verify_attempt("owner", "wrong");
        assert_eq!(unknown.kdf_runs, 1);
        assert_eq!(wrong.kdf_runs, 1);
        assert!(!unknown.matched);
        assert!(!wrong.matched);
    }

    #[test]
    fn five_failures_lock_for_fifteen_minutes() {
        let mut l = Lockout::default();
        let mut now = 1_000_000u64;
        for i in 1..=5 {
            let gate = l.failure("10.0.0.5", "owner", now);
            if i < 5 {
                assert_eq!(gate, Gate::Allowed, "lần sai thứ {i} chưa được khoá");
            } else {
                assert!(gate.is_locked(), "lần sai thứ 5 phải khoá");
            }
            now += 1_000;
        }
        match l.gate("10.0.0.5", "owner", now) {
            Gate::Locked { retry_after_s } => assert!(retry_after_s >= 890, "{retry_after_s}"),
            other => panic!("phải khoá, thực tế {other:?}"),
        }
        // Hết 15 phút thì mở.
        assert_eq!(l.gate("10.0.0.5", "owner", now + 15 * 60 * 1000), Gate::Allowed);
    }

    #[test]
    fn lockout_is_per_ip_and_user_not_global() {
        let mut l = Lockout::default();
        let mut now = 1_000_000u64;
        for _ in 0..5 {
            l.failure("10.0.0.5", "owner", now);
            now += 1_000;
        }
        // IP khác, cùng user ⇒ chưa bị khoá.
        assert_eq!(l.gate("10.0.0.6", "owner", now), Gate::Allowed);
    }

    #[test]
    fn spray_across_users_on_one_ip_is_capped_per_minute() {
        let mut l = Lockout::default();
        let now = 1_000_000u64;
        for i in 0..5 {
            l.failure("10.0.0.9", &format!("user{i}"), now + i);
        }
        // 5 lần trong 1 phút từ một IP ⇒ luật IP chặn, dù chưa user nào đủ 5.
        assert!(l.gate("10.0.0.9", "user99", now + 10).is_locked());
    }

    #[test]
    fn success_clears_the_counters() {
        let mut l = Lockout::default();
        let now = 1_000_000u64;
        for i in 0..4 {
            l.failure("10.0.0.7", "owner", now + i);
        }
        l.success("10.0.0.7", "owner");
        assert_eq!(l.gate("10.0.0.7", "owner", now + 10), Gate::Allowed);
        assert_eq!(l.locked_keys(), 0);
    }

    #[test]
    fn password_policy_refuses_short_and_common_passwords() {
        assert!(!password_meets_policy(""));
        assert!(!password_meets_policy("abc"));
        assert!(!password_meets_policy("password123"));
        assert!(!password_meets_policy("            "));
        assert!(password_meets_policy("tre-nha-toi-nam-o-tang-2"));
        // Ký tự đặc biệt không bị cấm — 12 ký tự là đủ.
        assert!(password_meets_policy("a!b@c#d$e%f^"));
    }

    #[test]
    fn rotating_the_password_changes_the_hash() {
        let mut f = file();
        assert!(f.verify_attempt("owner", "correct horse").matched);
        f.rotate("new secret", [2u8; 16]);
        assert!(!f.verify_attempt("owner", "correct horse").matched);
        assert!(f.verify_attempt("owner", "new secret").matched);
    }
}
