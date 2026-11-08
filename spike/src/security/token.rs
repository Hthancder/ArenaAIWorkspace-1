//! Access token + refresh token (§41.6, §5.8, §32.3).
//!
//! | Hạng mục | Spec | Ở đây |
//! |---|---|---|
//! | Access token | JWT RS256, 15 phút, `sub/role/sid_scope/jti` | JWT **HS256**, 15 phút, cùng claims (+ `iss/aud/iat/exp`) |
//! | Refresh token | opaque, lưu **hash** SHA-256, **rotate mỗi lần dùng** | `rt.<id>.<secret>`; chỉ hash của `secret` được lưu |
//! | Reuse detection | dùng refresh cũ ⇒ **revoke toàn bộ chuỗi** | cả **family** bị thu hồi, mọi access token cũ chết theo |
//! | Binding | gắn `device_id`; lệch ⇒ **cảnh báo, không chặn** | trả cờ `device_mismatch`, vẫn cho rotate |
//! | Revoke all | "đăng xuất mọi nơi" | watermark `revoked_before` theo user ⇒ access token chết **ngay**, không phải chờ 15 phút |
//!
//! Đổi RS256 → HS256 là **quyết định, không phải lười**: RS256 cần crate
//! RSA/ring (dependency + bề mặt lỗi), trong khi cả hai đầu đều nằm trên **cùng
//! một máy** của bạn, khoá đối xứng không mất gì. Lý do đầy đủ: §57.4.

use std::collections::HashMap;

use super::codec::{
    b64url_decode, b64url_encode, json_string, parse_flat_json, value_as_num, value_as_str,
    JsonValue,
};
use super::crypto::{ct_eq, hmac_sha256, sha256, Entropy};

// ---------- cấu hình & lỗi ----------

#[derive(Debug, Clone)]
pub struct TokenConfig {
    pub issuer: String,
    pub audience: String,
    pub access_ttl_ms: u64,
    /// §41.6 ghi "refresh 7 ngày" (§9.11 `refresh_days: 7`).
    pub refresh_ttl_ms: u64,
    /// §41.6 "skew ±60 s". Chỉ nới cho **iat/exp**, không nới cho chữ ký.
    pub clock_skew_ms: u64,
}

impl Default for TokenConfig {
    fn default() -> Self {
        Self {
            issuer: "lantern-local".into(),
            audience: "lantern-web".into(),
            access_ttl_ms: 15 * 60 * 1000,
            refresh_ttl_ms: 7 * 24 * 60 * 60 * 1000,
            clock_skew_ms: 60 * 1000,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokenError {
    /// Không đủ 3 phần / base64 hỏng / JSON hỏng.
    Malformed,
    /// `alg` không phải `HS256` — gồm cả `none`, thứ **luôn** phải bị từ chối.
    WrongAlg,
    BadSignature,
    Expired,
    NotYetValid,
    WrongIssuer,
    WrongAudience,
    /// `sid.owner != token.sub` (§8.2) — lỗi quyền, không phải lỗi format.
    WrongSubject,
    Revoked,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Claims {
    pub sub: String,
    pub role: String,
    pub sid_scope: String,
    pub jti: String,
    pub iat_ms: u64,
    pub exp_ms: u64,
    pub iss: String,
    pub aud: String,
}

// ---------- phát & kiểm token ----------

pub struct TokenIssuer {
    cfg: TokenConfig,
    key: Vec<u8>,
}

impl TokenIssuer {
    /// Khoá HMAC ≥ 32 byte; ngắn hơn thì từ chối ngay lúc khởi động chứ không
    /// "vẫn chạy được".
    pub fn new(cfg: TokenConfig, key: Vec<u8>) -> Result<Self, &'static str> {
        if key.len() < 32 {
            return Err("HMAC key must be at least 32 bytes");
        }
        Ok(Self { cfg, key })
    }

    pub fn config(&self) -> &TokenConfig {
        &self.cfg
    }

    fn sign(&self, input: &str) -> String {
        b64url_encode(&hmac_sha256(&self.key, input.as_bytes()))
    }

    pub fn issue_access(
        &self,
        sub: &str,
        role: &str,
        sid_scope: &str,
        now_ms: u64,
        entropy: &mut impl Entropy,
    ) -> (String, Claims) {
        let mut jti_bytes = [0u8; 16];
        entropy.fill(&mut jti_bytes);
        let claims = Claims {
            sub: sub.to_string(),
            role: role.to_string(),
            sid_scope: sid_scope.to_string(),
            jti: super::crypto::hex(&jti_bytes),
            iat_ms: now_ms,
            exp_ms: now_ms + self.cfg.access_ttl_ms,
            iss: self.cfg.issuer.clone(),
            aud: self.cfg.audience.clone(),
        };
        let header = format!(
            "{{\"alg\":\"HS256\",\"typ\":\"JWT\",\"kid\":{}}}",
            json_string("k1")
        );
        let payload = format!(
            "{{\"sub\":{},\"role\":{},\"sid_scope\":{},\"jti\":{},\"iat\":{},\"exp\":{},\"iss\":{},\"aud\":{}}}",
            json_string(&claims.sub),
            json_string(&claims.role),
            json_string(&claims.sid_scope),
            json_string(&claims.jti),
            claims.iat_ms / 1000,
            claims.exp_ms / 1000,
            json_string(&claims.iss),
            json_string(&claims.aud),
        );
        let signing_input = format!(
            "{}.{}",
            b64url_encode(header.as_bytes()),
            b64url_encode(payload.as_bytes())
        );
        let signature = self.sign(&signing_input);
        (format!("{signing_input}.{signature}"), claims)
    }

    /// Kiểm tra đầy đủ. `expected_sub` là **bắt buộc** ở mọi đường đi có `sid`
    /// (§41.4 T3, §8.2) — không có nó thì token của user A mở được phiên của B.
    pub fn verify(
        &self,
        jwt: &str,
        now_ms: u64,
        expected_sub: Option<&str>,
        revoked_before: Option<u64>,
    ) -> Result<Claims, TokenError> {
        if jwt.len() > 4096 {
            return Err(TokenError::Malformed);
        }
        let parts: Vec<&str> = jwt.split('.').collect();
        if parts.len() != 3 {
            return Err(TokenError::Malformed);
        }
        let (header_b64, payload_b64, sig_b64) = (parts[0], parts[1], parts[2]);
        if header_b64.is_empty() || payload_b64.is_empty() {
            return Err(TokenError::Malformed);
        }

        // 1. alg **trước** chữ ký: token `alg:none` không bao giờ được đi tiếp.
        //    Thứ tự này cũng là thứ tự của một log đọc được: gặp `none` thì
        //    thấy ngay `WrongAlg`, không bị che thành "Malformed".
        let header_bytes = b64url_decode(header_b64).ok_or(TokenError::Malformed)?;
        let header_text = std::str::from_utf8(&header_bytes).map_err(|_| TokenError::Malformed)?;
        let header = parse_flat_json(header_text).ok_or(TokenError::Malformed)?;
        let alg = header
            .iter()
            .find(|(k, _)| k == "alg")
            .and_then(|(_, v)| value_as_str(v))
            .ok_or(TokenError::Malformed)?;
        if alg != "HS256" {
            return Err(TokenError::WrongAlg);
        }
        // Chữ ký rỗng: header nói HS256 mà không có chữ ký ⇒ hỏng, không đoán.
        if sig_b64.is_empty() {
            return Err(TokenError::Malformed);
        }

        // 2. Chữ ký trên **đúng** chuỗi nhận được, so sánh hằng thời gian.
        let signing_input = format!("{header_b64}.{payload_b64}");
        let expected_sig = self.sign(&signing_input);
        if !ct_eq(sig_b64.as_bytes(), expected_sig.as_bytes()) {
            return Err(TokenError::BadSignature);
        }

        // 3. Claims.
        let payload_bytes = b64url_decode(payload_b64).ok_or(TokenError::Malformed)?;
        let payload_text = std::str::from_utf8(&payload_bytes).map_err(|_| TokenError::Malformed)?;
        let payload = parse_flat_json(payload_text).ok_or(TokenError::Malformed)?;
        let field = |name: &str| -> Option<&JsonValue> {
            payload.iter().find(|(k, _)| k == name).map(|(_, v)| v)
        };
        let claims = Claims {
            sub: field("sub").and_then(value_as_str).ok_or(TokenError::Malformed)?.to_string(),
            role: field("role").and_then(value_as_str).ok_or(TokenError::Malformed)?.to_string(),
            sid_scope: field("sid_scope")
                .and_then(value_as_str)
                .ok_or(TokenError::Malformed)?
                .to_string(),
            jti: field("jti").and_then(value_as_str).ok_or(TokenError::Malformed)?.to_string(),
            iat_ms: secs_to_ms(field("iat").and_then(value_as_num).ok_or(TokenError::Malformed)?)?,
            exp_ms: secs_to_ms(field("exp").and_then(value_as_num).ok_or(TokenError::Malformed)?)?,
            iss: field("iss").and_then(value_as_str).ok_or(TokenError::Malformed)?.to_string(),
            aud: field("aud").and_then(value_as_str).ok_or(TokenError::Malformed)?.to_string(),
        };
        if claims.jti.len() < 8 || claims.sub.is_empty() {
            return Err(TokenError::Malformed);
        }
        if claims.exp_ms <= claims.iat_ms {
            return Err(TokenError::Malformed);
        }

        // 4. Thời gian (skew chỉ áp cho đồng hồ, không áp cho chữ ký).
        let skew = self.cfg.clock_skew_ms;
        if now_ms > claims.exp_ms.saturating_add(skew) {
            return Err(TokenError::Expired);
        }
        if now_ms.saturating_add(skew) < claims.iat_ms {
            return Err(TokenError::NotYetValid);
        }

        // 5. Định danh & quyền.
        if claims.iss != self.cfg.issuer {
            return Err(TokenError::WrongIssuer);
        }
        if claims.aud != self.cfg.audience {
            return Err(TokenError::WrongAudience);
        }
        // Viết bằng `is_some_and` chứ không lồng `if let`: ít chỗ để sửa sai
        // thứ tự, và clippy `-D warnings` cũng không phải nói gì.
        if expected_sub.is_some_and(|expected| expected != claims.sub) {
            return Err(TokenError::WrongSubject);
        }

        // 6. Watermark thu hồi: token phát trước mốc revoke-all bị từ chối
        //    **ngay**, không phải chờ hết hạn tự nhiên.
        if revoked_before.is_some_and(|cutoff| claims.iat_ms < cutoff) {
            return Err(TokenError::Revoked);
        }

        Ok(claims)
    }
}

fn secs_to_ms(secs: i64) -> Result<u64, TokenError> {
    if secs < 0 {
        return Err(TokenError::Malformed);
    }
    Ok(secs as u64 * 1000)
}

// ---------- refresh chain ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RevokedReason {
    ReuseDetected,
    Logout,
    LogoutEverywhere,
    Expired,
    Admin,
}

#[derive(Debug, Clone)]
struct RefreshRecord {
    family: String,
    sub: String,
    hash: [u8; 32],
    device_hash: [u8; 32],
    issued_ms: u64,
    expires_ms: u64,
    used_ms: Option<u64>,
}

#[derive(Debug, Clone)]
struct Family {
    sub: String,
    revoked: Option<RevokedReason>,
    members: Vec<String>,
    last_used_ms: u64,
}

#[derive(Clone, PartialEq)]
pub struct Rotated {
    pub access: String,
    pub claims: Claims,
    pub refresh: String,
    /// `true` khi `device_id` khác lúc phát token. §41.6: **cảnh báo, không chặn**.
    pub device_mismatch: bool,
}

/// Cùng lý do với `Session`: `{:?}` không bao giờ được in token (§41.10 #12).
impl std::fmt::Debug for Rotated {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Rotated")
            .field("access", &format_args!("<redacted {} chars>", self.access.len()))
            .field("refresh", &format_args!("<redacted {} chars>", self.refresh.len()))
            .field("sub", &self.claims.sub)
            .field("device_mismatch", &self.device_mismatch)
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum RefreshOutcome {
    Rotated(Rotated),
    /// Dùng lại token đã rotate ⇒ đây là dấu hiệu bị đánh cắp.
    Reused {
        family: String,
        revoked_tokens: usize,
    },
    Revoked(RevokedReason),
    Expired,
    /// Token không tồn tại: sai, hoặc đã bị dọn sau khi family bị thu hồi.
    Unknown,
}

pub struct RefreshStore {
    issuer_cfg: TokenConfig,
    records: HashMap<String, RefreshRecord>,
    families: HashMap<String, Family>,
    /// `sub -> mốc thời gian`: token phát trước mốc này không dùng được.
    revoked_before: HashMap<String, u64>,
    next_family: u64,
}

impl RefreshStore {
    pub fn new(issuer_cfg: TokenConfig) -> Self {
        Self {
            issuer_cfg,
            records: HashMap::new(),
            families: HashMap::new(),
            revoked_before: HashMap::new(),
            next_family: 0,
        }
    }

    /// Phát refresh token đầu tiên (sau khi đăng nhập đúng). Secret **chỉ** đi
    /// ra ngoài một lần; trong bộ nhớ chỉ có SHA-256 của nó.
    pub fn issue(
        &mut self,
        sub: &str,
        device_id: &str,
        now_ms: u64,
        entropy: &mut impl Entropy,
    ) -> String {
        self.next_family += 1;
        let family = format!("fam{:08x}", self.next_family);
        let token = self.mint(&family, sub, device_id, now_ms, entropy);
        self.families.insert(
            family.clone(),
            Family {
                sub: sub.to_string(),
                revoked: None,
                members: vec![token.0.clone()],
                last_used_ms: now_ms,
            },
        );
        token.1
    }

    fn mint(
        &mut self,
        family: &str,
        sub: &str,
        device_id: &str,
        now_ms: u64,
        entropy: &mut impl Entropy,
    ) -> (String, String) {
        let mut id_bytes = [0u8; 8];
        entropy.fill(&mut id_bytes);
        let id = super::crypto::hex(&id_bytes);

        let mut secret = [0u8; 32];
        entropy.fill(&mut secret);
        let secret_hex = super::crypto::hex(&secret);

        self.records.insert(
            id.clone(),
            RefreshRecord {
                family: family.to_string(),
                sub: sub.to_string(),
                hash: sha256(secret_hex.as_bytes()),
                device_hash: sha256(device_id.as_bytes()),
                issued_ms: now_ms,
                expires_ms: now_ms + self.issuer_cfg.refresh_ttl_ms,
                used_ms: None,
            },
        );

        let token = format!("rt.{id}.{secret_hex}");
        (id, token)
    }

    /// Đổi refresh token lấy access token mới **và** refresh token mới.
    ///
    /// Thứ tự kiểm tra quan trọng: reuse được kiểm **trước** hạn, vì một token
    /// hết hạn mà đã bị dùng rồi thì vẫn là dấu hiệu trộm.
    pub fn rotate(
        &mut self,
        refresh_token: &str,
        device_id: &str,
        now_ms: u64,
        issuer: &TokenIssuer,
        role: &str,
        entropy: &mut impl Entropy,
    ) -> RefreshOutcome {
        let Some((id, secret)) = split_refresh(refresh_token) else {
            return RefreshOutcome::Unknown;
        };
        let Some(record) = self.records.get(&id).cloned() else {
            return RefreshOutcome::Unknown;
        };

        let candidate = sha256(secret.as_bytes());
        if !ct_eq(&candidate, &record.hash) {
            // Đúng id, sai secret: không phải "dùng lại", chỉ là token rác.
            return RefreshOutcome::Unknown;
        }

        // Family đã bị thu hồi ⇒ mọi token trong đó vô hiệu, kể cả token mới nhất.
        if let Some(reason) = self.families.get(&record.family).and_then(|f| f.revoked) {
            return RefreshOutcome::Revoked(reason);
        }

        if record.used_ms.is_some() {
            let revoked = self.revoke_family(&record.family, RevokedReason::ReuseDetected);
            return RefreshOutcome::Reused {
                family: record.family,
                revoked_tokens: revoked,
            };
        }

        if now_ms > record.expires_ms {
            self.revoke_family(&record.family, RevokedReason::Expired);
            return RefreshOutcome::Expired;
        }

        let device_mismatch = !ct_eq(&sha256(device_id.as_bytes()), &record.device_hash);

        if let Some(r) = self.records.get_mut(&id) {
            r.used_ms = Some(now_ms);
        }
        let (new_id, new_token) =
            self.mint(&record.family, &record.sub, device_id, now_ms, entropy);
        if let Some(family) = self.families.get_mut(&record.family) {
            family.members.push(new_id);
            family.last_used_ms = now_ms;
        }

        let (access, claims) = issuer.issue_access(&record.sub, role, "*", now_ms, entropy);
        RefreshOutcome::Rotated(Rotated {
            access,
            claims,
            refresh: new_token,
            device_mismatch,
        })
    }

    fn revoke_family(&mut self, family: &str, reason: RevokedReason) -> usize {
        let Some(entry) = self.families.get_mut(family) else {
            return 0;
        };
        if entry.revoked.is_some() {
            return 0;
        }
        entry.revoked = Some(reason);
        entry.members.len()
    }

    /// "Đăng xuất mọi nơi": mọi family của user bị thu hồi **và** mọi access
    /// token phát trước `now_ms` bị từ chối (watermark).
    pub fn revoke_all(&mut self, sub: &str, now_ms: u64) {
        let family_ids: Vec<String> = self
            .families
            .iter()
            .filter(|(_, f)| f.sub == sub && f.revoked.is_none())
            .map(|(id, _)| id.clone())
            .collect();
        for family in family_ids {
            self.revoke_family(&family, RevokedReason::LogoutEverywhere);
        }
        let cutoff = self.revoked_before.entry(sub.to_string()).or_insert(0);
        if now_ms > *cutoff {
            *cutoff = now_ms;
        }
    }

    pub fn revoke(&mut self, refresh_token: &str, reason: RevokedReason) -> bool {
        let Some((id, _)) = split_refresh(refresh_token) else {
            return false;
        };
        match self.records.get(&id).map(|r| r.family.clone()) {
            Some(family) => self.revoke_family(&family, reason) > 0,
            None => false,
        }
    }

    pub fn revoked_before(&self, sub: &str) -> Option<u64> {
        self.revoked_before.get(sub).copied()
    }

    pub fn family_revoked(&self, sub: &str) -> bool {
        self.families
            .values()
            .any(|f| f.sub == sub && f.revoked.is_some())
    }

    pub fn live_families(&self, sub: &str) -> usize {
        self.families
            .values()
            .filter(|f| f.sub == sub && f.revoked.is_none())
            .count()
    }

    /// Chỉ để test/审计: tổng số record đang giữ.
    pub fn record_count(&self) -> usize {
        self.records.len()
    }

    /// Tuổi của refresh token đang sống (để `/diagnostics` trả "phiên này đăng
    /// nhập cách đây bao lâu" mà **không** lộ token).
    pub fn refresh_age_ms(&self, refresh_token: &str, now_ms: u64) -> Option<u64> {
        let (id, _) = split_refresh(refresh_token)?;
        let record = self.records.get(&id)?;
        Some(now_ms.saturating_sub(record.issued_ms))
    }
}

/// `rt.<id>.<secret>` — 3 phần, id hex 16, secret hex 64.
pub fn split_refresh(token: &str) -> Option<(String, String)> {
    let mut parts = token.split('.');
    let prefix = parts.next()?;
    let id = parts.next()?;
    let secret = parts.next()?;
    if parts.next().is_some() || prefix != "rt" || id.len() != 16 || secret.len() != 64 {
        return None;
    }
    if !id.bytes().all(|b| b.is_ascii_hexdigit()) || !secret.bytes().all(|b| b.is_ascii_hexdigit())
    {
        return None;
    }
    Some((id.to_string(), secret.to_string()))
}

/// Hash để lưu/so: **không bao giờ** log token thô (§26.3 redaction).
pub fn token_fingerprint(token: &str) -> String {
    super::crypto::hex(&sha256(token.as_bytes()))[..16].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::crypto::FixedEntropy;

    const T0: u64 = 1_700_000_000_000;

    fn issuer() -> TokenIssuer {
        TokenIssuer::new(TokenConfig::default(), vec![7u8; 32]).expect("key")
    }

    fn entropy() -> FixedEntropy {
        FixedEntropy::new(42)
    }

    #[test]
    fn access_token_round_trips_with_claims() {
        let mut e = entropy();
        let (jwt, claims) = issuer().issue_access("owner", "owner", "*", T0, &mut e);
        assert_eq!(jwt.split('.').count(), 3);
        let back = issuer()
            .verify(&jwt, T0 + 1000, Some("owner"), None)
            .expect("verify");
        assert_eq!(back, claims);
        assert_eq!(back.exp_ms - back.iat_ms, 15 * 60 * 1000);
    }

    #[test]
    fn expired_token_is_rejected_after_skew_only() {
        let mut e = entropy();
        let (jwt, _) = issuer().issue_access("owner", "owner", "*", T0, &mut e);
        let ttl = TokenConfig::default().access_ttl_ms;
        assert!(issuer().verify(&jwt, T0 + ttl + 30_000, None, None).is_ok(), "trong skew 60 s");
        assert_eq!(
            issuer().verify(&jwt, T0 + ttl + 61_000, None, None),
            Err(TokenError::Expired)
        );
    }

    #[test]
    fn alg_none_is_rejected() {
        // Token tự chế: header alg=none, payload tuỳ ý, chữ ký rỗng.
        let header = b64url_encode(br#"{"alg":"none","typ":"JWT"}"#);
        let payload = b64url_encode(
            format!(
                r#"{{"sub":"attacker","role":"owner","sid_scope":"*","jti":"0123456789","iat":{},"exp":{},"iss":"lantern-local","aud":"lantern-web"}}"#,
                T0 / 1000,
                T0 / 1000 + 3600
            )
            .as_bytes(),
        );
        let forged = format!("{header}.{payload}.");
        assert_eq!(
            issuer().verify(&forged, T0, None, None),
            Err(TokenError::WrongAlg)
        );
        let forged2 = format!("{header}.{payload}.x");
        assert_eq!(
            issuer().verify(&forged2, T0, None, None),
            Err(TokenError::WrongAlg)
        );

        // Header HS256 nhưng chữ ký rỗng: hỏng (Malformed), **không** phải chấp nhận.
        let hs256_header = b64url_encode(br#"{"alg":"HS256","typ":"JWT"}"#);
        assert_eq!(
            issuer().verify(&format!("{hs256_header}.{payload}."), T0, None, None),
            Err(TokenError::Malformed)
        );
    }

    #[test]
    fn tampering_with_the_payload_breaks_the_signature() {
        let mut e = entropy();
        let (jwt, _) = issuer().issue_access("owner", "owner", "*", T0, &mut e);
        let parts: Vec<&str> = jwt.split('.').collect();
        // Đổi "owner" ⇒ "attacker" trong payload, giữ nguyên chữ ký.
        let payload = String::from_utf8(b64url_decode(parts[1]).unwrap()).unwrap();
        let evil = payload.replace("owner", "attack");
        let forged = format!(
            "{}.{}.{}",
            parts[0],
            b64url_encode(evil.as_bytes()),
            parts[2]
        );
        assert_eq!(
            issuer().verify(&forged, T0, None, None),
            Err(TokenError::BadSignature)
        );
    }

    #[test]
    fn another_key_cannot_verify() {
        let mut e = entropy();
        let (jwt, _) = issuer().issue_access("owner", "owner", "*", T0, &mut e);
        let other = TokenIssuer::new(TokenConfig::default(), vec![8u8; 32]).unwrap();
        assert_eq!(
            other.verify(&jwt, T0, None, None),
            Err(TokenError::BadSignature)
        );
    }

    #[test]
    fn short_keys_are_refused_at_startup() {
        assert!(TokenIssuer::new(TokenConfig::default(), vec![1u8; 31]).is_err());
        assert!(TokenIssuer::new(TokenConfig::default(), vec![1u8; 32]).is_ok());
    }

    #[test]
    fn wrong_issuer_audience_or_subject_is_rejected() {
        let mut e = entropy();
        let (jwt, _) = issuer().issue_access("owner", "owner", "*", T0, &mut e);

        let bad_aud = TokenIssuer::new(
            TokenConfig {
                audience: "elsewhere".into(),
                ..TokenConfig::default()
            },
            vec![7u8; 32],
        )
        .unwrap();
        assert_eq!(
            bad_aud.verify(&jwt, T0, None, None),
            Err(TokenError::WrongAudience)
        );

        let bad_iss = TokenIssuer::new(
            TokenConfig {
                issuer: "elsewhere".into(),
                ..TokenConfig::default()
            },
            vec![7u8; 32],
        )
        .unwrap();
        assert_eq!(
            bad_iss.verify(&jwt, T0, None, None),
            Err(TokenError::WrongIssuer)
        );

        // §8.2: `sid.owner == token.sub` — đây là lỗi quyền, phải có mã riêng.
        assert_eq!(
            issuer().verify(&jwt, T0, Some("someone-else"), None),
            Err(TokenError::WrongSubject)
        );
    }

    #[test]
    fn garbage_never_panics() {
        let i = issuer();
        let inputs = [
            "",
            ".",
            "..",
            "a.b.c",
            "a.b",
            "aaa.bbb.ccc",
            "e30.e30.e30",
            &"x".repeat(5000),
            "eyJhbGciOiJIUzI1NiJ9..",
            "!!@#.$$$.%%%",
        ];
        for input in inputs {
            let result = i.verify(input, T0, None, None);
            assert!(result.is_err(), "{input:?} phải bị từ chối, không panic");
        }
    }

    #[test]
    fn refresh_rotates_and_the_old_one_dies() {
        let mut e = entropy();
        let issuer = issuer();
        let mut store = RefreshStore::new(TokenConfig::default());
        let first = store.issue("owner", "device-a", T0, &mut e);

        let outcome = store.rotate(&first, "device-a", T0 + 1000, &issuer, "owner", &mut e);
        let RefreshOutcome::Rotated(rotated) = outcome else {
            panic!("phải rotate, thực tế {outcome:?}");
        };
        assert!(!rotated.device_mismatch);
        // Token mới dùng được.
        assert!(matches!(
            store.rotate(&rotated.refresh, "device-a", T0 + 2000, &issuer, "owner", &mut e),
            RefreshOutcome::Rotated(_)
        ));
        // Và access token mới verify được.
        assert!(issuer
            .verify(&rotated.access, T0 + 2000, Some("owner"), None)
            .is_ok());
    }

    #[test]
    fn reusing_a_rotated_refresh_kills_the_whole_family() {
        let mut e = entropy();
        let issuer = issuer();
        let mut store = RefreshStore::new(TokenConfig::default());
        let first = store.issue("owner", "device-a", T0, &mut e);
        let RefreshOutcome::Rotated(a) = store.rotate(&first, "device-a", T0 + 1000, &issuer, "owner", &mut e)
        else {
            panic!("rotate #1");
        };
        let RefreshOutcome::Rotated(b) = store.rotate(&a.refresh, "device-a", T0 + 2000, &issuer, "owner", &mut e)
        else {
            panic!("rotate #2");
        };

        // Kẻ trộm dùng lại token ĐẦU TIÊN (đã dùng ở bước 1).
        match store.rotate(&first, "device-b", T0 + 3000, &issuer, "owner", &mut e) {
            RefreshOutcome::Reused { revoked_tokens, .. } => {
                assert!(revoked_tokens >= 3, "cả chuỗi bị thu hồi: {revoked_tokens}");
            }
            other => panic!("phải là Reused, thực tế {other:?}"),
        }
        // Token MỚI NHẤT cũng chết — đó là điểm của reuse detection.
        assert_eq!(
            store.rotate(&b.refresh, "device-a", T0 + 4000, &issuer, "owner", &mut e),
            RefreshOutcome::Revoked(RevokedReason::ReuseDetected)
        );
        assert_eq!(store.live_families("owner"), 0);
    }

    #[test]
    fn refresh_token_from_another_device_warns_but_does_not_block() {
        let mut e = entropy();
        let issuer = issuer();
        let mut store = RefreshStore::new(TokenConfig::default());
        let token = store.issue("owner", "phone", T0, &mut e);
        let RefreshOutcome::Rotated(r) = store.rotate(&token, "laptop", T0 + 1, &issuer, "owner", &mut e)
        else {
            panic!("phải rotate");
        };
        assert!(r.device_mismatch, "§41.6: cảnh báo, không chặn");
    }

    #[test]
    fn expired_refresh_is_rejected() {
        let mut e = entropy();
        let issuer = issuer();
        let mut store = RefreshStore::new(TokenConfig::default());
        let token = store.issue("owner", "device-a", T0, &mut e);
        let week = 7 * 24 * 60 * 60 * 1000u64;
        assert_eq!(
            store.rotate(&token, "device-a", T0 + week + 1, &issuer, "owner", &mut e),
            RefreshOutcome::Expired
        );
    }

    #[test]
    fn garbage_refresh_tokens_are_unknown_not_a_crash() {
        let mut e = entropy();
        let issuer = issuer();
        let mut store = RefreshStore::new(TokenConfig::default());
        for token in ["", "rt", "rt.", "rt..", "rt.zz.yy", "xx.0011223344556677.00"] {
            assert_eq!(
                store.rotate(token, "d", T0, &issuer, "owner", &mut e),
                RefreshOutcome::Unknown,
                "{token:?}"
            );
        }
        assert_eq!(
            store.rotate("rt.0011223344556677.0000", "d", T0, &issuer, "owner", &mut e),
            RefreshOutcome::Unknown
        );
    }

    #[test]
    fn logout_everywhere_revokes_access_tokens_immediately() {
        let mut e = entropy();
        let issuer = issuer();
        let mut store = RefreshStore::new(TokenConfig::default());
        let (jwt, _) = issuer.issue_access("owner", "owner", "*", T0, &mut e);

        // Chưa revoke ⇒ dùng được.
        assert!(issuer.verify(&jwt, T0 + 1000, Some("owner"), store.revoked_before("owner")).is_ok());

        store.revoke_all("owner", T0 + 5000);

        // Watermark làm token cũ chết **ngay**, không chờ 15 phút.
        assert_eq!(
            issuer.verify(&jwt, T0 + 6000, Some("owner"), store.revoked_before("owner")),
            Err(TokenError::Revoked)
        );
        // Token phát sau đó vẫn sống.
        let (fresh, _) = issuer.issue_access("owner", "owner", "*", T0 + 5001, &mut e);
        assert!(issuer
            .verify(&fresh, T0 + 6000, Some("owner"), store.revoked_before("owner"))
            .is_ok());
    }

    #[test]
    fn revoke_all_does_not_touch_another_user() {
        let mut e = entropy();
        let issuer = issuer();
        let mut store = RefreshStore::new(TokenConfig::default());
        let a = store.issue("owner", "d", T0, &mut e);
        let b = store.issue("guest", "d", T0, &mut e);
        store.revoke_all("owner", T0 + 10);
        assert_eq!(
            store.rotate(&a, "d", T0 + 20, &issuer, "owner", &mut e),
            RefreshOutcome::Revoked(RevokedReason::LogoutEverywhere)
        );
        assert!(matches!(
            store.rotate(&b, "d", T0 + 20, &issuer, "guest", &mut e),
            RefreshOutcome::Rotated(_)
        ));
    }

    #[test]
    fn wrong_secret_with_real_id_is_unknown() {
        let mut e = entropy();
        let issuer = issuer();
        let mut store = RefreshStore::new(TokenConfig::default());
        let token = store.issue("owner", "d", T0, &mut e);
        let (id, _) = split_refresh(&token).unwrap();
        let forged = format!("rt.{id}.{}", "0".repeat(64));
        assert_eq!(
            store.rotate(&forged, "d", T0 + 1, &issuer, "owner", &mut e),
            RefreshOutcome::Unknown
        );
        // Và token thật vẫn dùng được (không bị khoá bởi lần đoán sai).
        assert!(matches!(
            store.rotate(&token, "d", T0 + 2, &issuer, "owner", &mut e),
            RefreshOutcome::Rotated(_)
        ));
    }

    #[test]
    fn debug_output_never_contains_a_token() {
        // §41.10 #12: grep log sau 100 phiên ⇒ 0 token. Test rẻ nhất để giữ luật đó.
        let mut e = entropy();
        let issuer = issuer();
        let (jwt, _) = issuer.issue_access("owner", "owner", "*", T0, &mut e);
        let mut store = RefreshStore::new(TokenConfig::default());
        let refresh = store.issue("owner", "device", T0, &mut e);
        let RefreshOutcome::Rotated(rotated) =
            store.rotate(&refresh, "device", T0 + 1, &issuer, "owner", &mut e)
        else {
            panic!("rotate");
        };
        let rendered = format!("{rotated:?}");
        assert!(!rendered.contains(&rotated.access), "{rendered}");
        assert!(!rendered.contains(&rotated.refresh), "{rendered}");
        assert!(!rendered.contains(&jwt), "{rendered}");
        assert!(rendered.contains("redacted"), "{rendered}");
    }

    #[test]
    fn fingerprint_never_leaks_the_token() {
        let fp = token_fingerprint("rt.0011223344556677.deadbeef");
        assert_eq!(fp.len(), 16);
        assert!(!fp.contains("deadbeef"));
    }
}
