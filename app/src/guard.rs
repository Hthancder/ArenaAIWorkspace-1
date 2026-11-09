//! Cổng kiểm quyền cho mọi route mutation — §41.3, §41.4 T3/T6, §8.2.
//!
//! # Vì sao phải có lớp này
//!
//! §41.3 nói rõ: **client không được tin**, nên *mọi* request mutation phải
//! kiểm lại. Nhưng trước file này, `/api/sessions` tạo được phiên mà không cần
//! token: nếu bạn bind ra LAN thì **ai trong cùng Wi-Fi cũng mở được màn hình
//! của bạn**. Việc có `/api/login` không cứu được điều đó — một cổng khoá gắn
//! trên cánh cửa không có ổ khoá.
//!
//! # Quyết định: mặc định **mở** ở loopback, **đóng** ở mọi nơi khác
//!
//! Đây không phải sự lười. Lý do:
//!
//! * §54.5 #1: chưa có TLS ⇒ chỉ chạy được ở loopback. Ở loopback, một token
//!   chỉ bảo vệ **cùng một người dùng** khỏi chính họ — giá trị gần bằng 0,
//!   còn cái giá là mở app ra là thấy màn hình đăng nhập, và một mật khẩu nữa
//!   phải nhớ để xem màn hình của chính mình.
//! * Ngược lại, khi `LANTERN_ALLOW_LAN=1` (người dùng tự nhận rủi ro), **mọi**
//!   mutation phải có token — đó là lúc token thật sự có việc để làm.
//!
//! Hàm [`require_token`] là **một** chỗ quyết định điều đó, nên không route
//! nào có thể "quên" theo kiểu khác.

use std::collections::BTreeMap;

use rd_spike_lib::security::token::Claims;

/// Có bắt buộc token không, theo địa chỉ đang bind.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Policy {
    /// Bind loopback: không đòi token (xem doc đầu file).
    Loopback,
    /// Bind ra LAN (qua `LANTERN_ALLOW_LAN=1`): **mọi** mutation cần access token.
    Lan,
}

impl Policy {
    pub fn for_bind(host: &str) -> Self {
        if matches!(host, "127.0.0.1" | "localhost" | "::1" | "[::1]") {
            Policy::Loopback
        } else {
            Policy::Lan
        }
    }
}

/// Tách `Authorization: Bearer <jwt>`.
///
/// So sánh tiền tố **không phân biệt hoa thường** vì header name đã hạ về chữ
/// thường ở `read_request`, còn scheme thì RFC 7235 cũng cho phép bất kỳ kiểu.
pub fn bearer(headers: &BTreeMap<String, String>) -> Option<&str> {
    let value = headers.get("authorization")?;
    let (scheme, token) = value.split_once(' ')?;
    if !scheme.eq_ignore_ascii_case("bearer") {
        return None;
    }
    let token = token.trim();
    if token.is_empty() { None } else { Some(token) }
}

/// Kết quả kiểm quyền.
pub enum Verdict {
    /// Được đi tiếp, kèm **chủ của request** (`claims.sub`), hoặc `None` ở
    /// loopback khi client không gửi token.
    ///
    /// Không bỏ trường này đi dù route hiện tại chỉ cần biết "được/không":
    /// §41.4 T3 là `sid.owner == token.sub`, và `sub` **chính là** thứ phải
    /// truyền tiếp để kiểm điều đó. Một `Verdict` chỉ có `bool` sẽ khiến route
    /// sau này buộc phải verify token lần thứ hai.
    Allowed(Option<Claims>),
    /// Bị từ chối. `code` đi vào body; `status` là mã HTTP.
    Denied { status: u16, code: &'static str },
}

/// Kiểm quyền cho một mutation.
///
/// `sid_owner` là **chủ của `sid`** mà request nhắm tới — không phải chủ của
/// token. §8.2: "mọi message kiểm tra `sid.owner == token.sub`". Truyền `None`
/// cho route không gắn với phiên nào (ví dụ `/api/pins`).
pub fn require_token(
    policy: Policy,
    headers: &BTreeMap<String, String>,
    auth: Option<&rd_spike_lib::security::gate::Auth>,
    sid_owner: Option<&str>,
    now_ms: u64,
) -> Verdict {
    require_token_with_refresh(policy, headers, auth, None, sid_owner, now_ms)
}

/// Như `require_token`, nhưng cho phép **refresh token** thay cho access token.
///
/// # Chỉ dùng cho đường mà trình duyệt không gắn được header
///
/// `<img src="/api/live.mjpg">` không có cách nào gửi `Authorization`; nó gửi
/// cookie. Nếu route đó chỉ nhận bearer thì khung hình **đen vĩnh viễn** sau khi
/// đăng nhập — lỗi chỉ xuất hiện khi người dùng làm đúng mọi bước, nên là loại
/// lỗi tệ nhất để phát hiện muộn.
///
/// `refresh_in_header`: giá trị đến từ cookie `lantern_refresh`, đã được đổi
/// thành access token **trước** khi tới đây (xem `live_headers_with_cookie`).
/// Hàm này không tự đổi: đổi token là việc của tầng auth, và nó cần `&mut`.
pub fn require_token_with_refresh(
    policy: Policy,
    headers: &BTreeMap<String, String>,
    auth: Option<&rd_spike_lib::security::gate::Auth>,
    access_from_cookie: Option<&str>,
    sid_owner: Option<&str>,
    now_ms: u64,
) -> Verdict {
    let token = bearer(headers).or(access_from_cookie);
    match (policy, token) {
        // # Loopback **chỉ** miễn token khi máy chưa có mật khẩu
        //
        // Đây là bug bảo mật thật, phát hiện bằng curl: đặt mật khẩu xong,
        // `/api/windows` vẫn trả **200 không cần cookie**. Người dùng đặt mật
        // khẩu, tưởng đã khoá máy, và bất kỳ trang web nào mở trên máy cũng
        // gọi được `http://127.0.0.1:<port>/api/live.mjpg` để xem màn hình —
        // vì loopback miễn token vĩnh viễn.
        //
        // Đúng luật: `Policy::Loopback` nghĩa là "chưa có gì để bảo vệ". Đã có
        // mật khẩu nghĩa là người dùng **muốn** có cổng, nên nhánh miễn token
        // phải tắt. Không dựa vào cookie/địa chỉ IP: cookie `HttpOnly` không
        // chống được trang cùng máy, chỉ có kiểm token mới chống được.
        (Policy::Loopback, None) if auth.is_none() => Verdict::Allowed(None),
        (_, None) => Verdict::Denied { status: 401, code: "missing_token" },
        (_, Some(jwt)) => {
            let Some(auth) = auth else {
                // Có token mà server chưa cấu hình auth: không thể xác minh,
                // nên **từ chối**. Cho qua ở đây là bỏ hẳn lớp kiểm.
                return Verdict::Denied { status: 401, code: "auth_not_configured" };
            };
            // `authorize` của spec gộp verify chữ ký + hạn + `sub` + revoke.
            // Không tự ghép lại từ `verify` — một lần nữa, luật nằm một chỗ.
            //
            // # `None` khác `"*"` — đây là bug đã có thật
            //
            // §8.2 chỉ áp `sid.owner == token.sub` cho route **gắn với một
            // phiên**. Route không gắn phiên (`/api/windows`, `/api/settings`)
            // không có `sid` nào để so, nên truyền `None`.
            //
            // Bản trước thay `None` bằng `"*"` với ý "không ràng buộc". Sai:
            // `authorize` so `sub == "*"`, không token nào có `sub` là `"*"`, nên
            // **mọi** request có token đều bị `401 wrong_subject`. Nghĩa là bật
            // mật khẩu lên là app khoá cứng — không phải bảo mật, mà là hỏng.
            // (Test cũ không bắt được vì chưa có test nào đi qua đường
            // "đã cấu hình auth" từ đầu tới cuối.)
            let owner = sid_owner;
            match auth.authorize_maybe_scoped(jwt, owner, now_ms) {
                Ok(claims) => Verdict::Allowed(Some(claims)),
                Err(error) => Verdict::Denied { status: 401, code: token_error_code(&error) },
            }
        }
    }
}

/// Mã lỗi cho từng `TokenError` — trả về **cụ thể**, không gộp thành
/// `unauthorized`: người dùng cần biết "hết hạn" (đăng nhập lại) khác
/// "sai chữ ký" (token bị sửa).
fn token_error_code(error: &rd_spike_lib::security::token::TokenError) -> &'static str {
    use rd_spike_lib::security::token::TokenError as E;
    match error {
        E::Expired => "token_expired",
        E::NotYetValid => "token_not_yet_valid",
        E::BadSignature => "bad_signature",
        E::WrongAlg => "wrong_alg",
        E::WrongIssuer => "wrong_issuer",
        E::WrongAudience => "wrong_audience",
        E::WrongSubject => "wrong_subject",
        E::Revoked => "token_revoked",
        E::Malformed => "malformed_token",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn headers(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test] fn loopback_without_a_token_is_allowed_and_lan_without_one_is_not() {
        // Toàn bộ giá trị của file này nằm ở hai dòng này.
        assert!(matches!(
            require_token(Policy::Loopback, &headers(&[]), None, None, 0),
            Verdict::Allowed(None)
        ));
        assert!(matches!(
            require_token(Policy::Lan, &headers(&[]), None, None, 0),
            Verdict::Denied { status: 401, code: "missing_token" }
        ));
    }

    #[test] fn a_bearer_header_is_read_case_insensitively() {
        let h = headers(&[("authorization", "Bearer abc.def.ghi")]);
        assert_eq!(bearer(&h), Some("abc.def.ghi"));
        let h = headers(&[("authorization", "bearer x")]);
        assert_eq!(bearer(&h), Some("x"));
        // Scheme khác ⇒ không phải bearer, **không** đoán.
        let h = headers(&[("authorization", "Basic dXNlcjpwYXNz")]);
        assert_eq!(bearer(&h), None);
        // Chuỗi rỗng sau "Bearer " không phải token.
        let h = headers(&[("authorization", "Bearer  ")]);
        assert_eq!(bearer(&h), None);
        assert_eq!(bearer(&headers(&[])), None);
    }

    #[test] fn the_policy_follows_the_bind_address() {
        assert_eq!(Policy::for_bind("127.0.0.1"), Policy::Loopback);
        assert_eq!(Policy::for_bind("localhost"), Policy::Loopback);
        assert_eq!(Policy::for_bind("::1"), Policy::Loopback);
        assert_eq!(Policy::for_bind("0.0.0.0"), Policy::Lan);
        assert_eq!(Policy::for_bind("192.168.1.5"), Policy::Lan);
    }

    #[test] fn a_token_that_cannot_be_verified_is_refused_not_ignored() {
        // Header nói có token nhưng server chưa cấu hình auth ⇒ 401, **không**
        // phải "chắc không sao". Đây là nhánh dễ viết sai nhất của
        // `require_token`, vì `Option::is_some()` gộp nó với trường hợp không
        // gửi token.
        let h = headers(&[("authorization", "Bearer x.y.z")]);
        match require_token(Policy::Lan, &h, None, None, 0) {
            Verdict::Denied { status, code } => {
                assert_eq!(status, 401);
                assert_eq!(code, "auth_not_configured");
            }
            _ => panic!("phải bị từ chối"),
        }
    }

    #[test] fn an_expired_token_says_expired_not_just_forbidden() {
        // Không dựng `Auth` ở đây (nó ở `auth_wire::tests`); test này khoá
        // **ánh xạ mã lỗi**, thứ quyết định UI hiện gì.
        use rd_spike_lib::security::token::TokenError as E;
        assert_eq!(token_error_code(&E::Expired), "token_expired");
        assert_eq!(token_error_code(&E::BadSignature), "bad_signature");
        assert_eq!(token_error_code(&E::WrongSubject), "wrong_subject");
        // Mọi biến thể phải có mã riêng — không được rơi vào một chuỗi chung.
        let all = [
            E::Malformed, E::WrongAlg, E::BadSignature, E::Expired, E::NotYetValid,
            E::WrongIssuer, E::WrongAudience, E::WrongSubject, E::Revoked,
        ];
        let codes: std::collections::BTreeSet<&str> =
            all.iter().map(token_error_code).collect();
        assert_eq!(codes.len(), all.len(), "mỗi lỗi phải có mã riêng: {codes:?}");
    }
}
