//! Encoding helpers for tokens: base64url (RFC 4648 §5), UUID v7 (§32.2
//! `intent_id`), and a deliberately tiny JSON reader/writer for JWT claims.
//!
//! Vì sao tự viết: crate `serde_json` + `base64` là 2 dependency cho ~200 dòng
//! logic, và §56.1 chốt **0 dependency** để CI không đỏ vì thứ không liên quan.

use super::crypto::{hex, Entropy};

// ---------- base64url (no padding) ----------

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

pub fn b64url_encode(input: &[u8]) -> String {
    let mut out = String::with_capacity(input.len().div_ceil(3) * 4);
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = *chunk.get(1).unwrap_or(&0) as u32;
        let b2 = *chunk.get(2).unwrap_or(&0) as u32;
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(ALPHABET[(n >> 18) as usize & 63] as char);
        out.push(ALPHABET[(n >> 12) as usize & 63] as char);
        if chunk.len() > 1 {
            out.push(ALPHABET[(n >> 6) as usize & 63] as char);
        }
        if chunk.len() > 2 {
            out.push(ALPHABET[n as usize & 63] as char);
        }
    }
    out
}

pub fn b64url_decode(input: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(input.len() * 3 / 4 + 2);
    let mut acc = 0u32;
    let mut bits = 0u32;
    for ch in input.bytes() {
        let value = match ch {
            b'A'..=b'Z' => ch - b'A',
            b'a'..=b'z' => ch - b'a' + 26,
            b'0'..=b'9' => ch - b'0' + 52,
            b'-' => 62,
            b'_' => 63,
            // Padding không được chấp nhận: token có '=' là token lạ.
            _ => return None,
        } as u32;
        acc = (acc << 6) | value;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
        }
    }
    // 6 bit thừa nghĩa là chuỗi không thể là base64url của một chuỗi byte.
    if bits >= 6 {
        return None;
    }
    Some(out)
}

// ---------- UUID v7 ----------

/// UUID v7: 48 bit đầu là thời gian (ms) ⇒ **sắp theo thời gian**, cho `sid`
/// và `intent_id` đọc trong log là biết thứ tự (§32.2).
pub fn uuid_v7(now_ms: u64, entropy: &mut impl Entropy) -> String {
    let mut rand = [0u8; 10];
    entropy.fill(&mut rand);

    let mut bytes = [0u8; 16];
    bytes[0..6].copy_from_slice(&now_ms.to_be_bytes()[2..8]);
    bytes[6] = 0x70 | (rand[0] & 0x0f);
    bytes[7] = rand[1];
    bytes[8] = 0x80 | (rand[2] & 0x3f);
    bytes[9..16].copy_from_slice(&rand[3..10]);

    let h = hex(&bytes);
    format!(
        "{}-{}-{}-{}-{}",
        &h[0..8],
        &h[8..12],
        &h[12..16],
        &h[16..20],
        &h[20..32]
    )
}

pub fn is_uuid_v7(s: &str) -> bool {
    if s.len() != 36 {
        return false;
    }
    let parts: Vec<&str> = s.split('-').collect();
    if parts.len() != 5
        || parts
            .iter()
            .map(|p| p.len())
            .collect::<Vec<_>>()
            .as_slice()
            != [8, 4, 4, 4, 12]
    {
        return false;
    }
    if !s.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        return false;
    }
    parts[2].starts_with('7') && matches!(parts[3].as_bytes()[0], b'8' | b'9' | b'a' | b'b')
}

// ---------- JSON (đúng bằng nhu cầu của JWT claims) ----------

/// Escape chuỗi cho JSON. ASCII in được đi nguyên; ký tự điều khiển thành `\u`.
pub fn json_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[derive(Debug, Clone, PartialEq)]
pub enum JsonValue {
    Str(String),
    Num(i64),
    Bool(bool),
    Null,
}

/// Đọc một object phẳng `{"k": "v" | 12 | true | false | null}`. Không mảng,
/// không object lồng — JWT claims của ta không cần hai thứ đó, và mỗi thứ thêm
/// vào là một chỗ để parser sai. Đầu vào lạ ⇒ `None`, **không** đoán.
pub fn parse_flat_json(input: &str) -> Option<Vec<(String, JsonValue)>> {
    let bytes = input.trim().as_bytes();
    if bytes.len() < 2 || bytes[0] != b'{' || bytes[bytes.len() - 1] != b'}' {
        return None;
    }
    let end = bytes.len() - 1; // vị trí của '}'
    let mut i = 1usize;
    let mut out = Vec::new();
    skip_ws(bytes, &mut i, end);
    if i == end {
        return Some(out);
    }
    loop {
        skip_ws(bytes, &mut i, end);
        if i >= end || bytes[i] != b'"' {
            return None;
        }
        let (key, next) = parse_json_str(bytes, i)?;
        i = next;
        skip_ws(bytes, &mut i, end);
        if i >= end || bytes[i] != b':' {
            return None;
        }
        i += 1;
        skip_ws(bytes, &mut i, end);
        let (value, next) = parse_json_value(bytes, i, end)?;
        i = next;
        out.push((key, value));
        skip_ws(bytes, &mut i, end);
        if i >= end {
            break;
        }
        if bytes[i] != b',' {
            return None; // thiếu dấu phẩy ⇒ hỏng, không "đoán"
        }
        i += 1;
    }
    Some(out)
}

fn skip_ws(bytes: &[u8], i: &mut usize, end: usize) {
    while *i < end && bytes[*i].is_ascii_whitespace() {
        *i += 1;
    }
}

fn parse_json_value(bytes: &[u8], i: usize, end: usize) -> Option<(JsonValue, usize)> {
    if i >= end {
        return None;
    }
    if bytes[i] == b'"' {
        let (s, next) = parse_json_str(bytes, i)?;
        return Some((JsonValue::Str(s), next));
    }
    let start = i;
    let mut j = i;
    while j < end && bytes[j] != b',' && !bytes[j].is_ascii_whitespace() {
        j += 1;
    }
    let raw = std::str::from_utf8(&bytes[start..j]).ok()?;
    let value = match raw {
        "true" => JsonValue::Bool(true),
        "false" => JsonValue::Bool(false),
        "null" => JsonValue::Null,
        other => JsonValue::Num(other.parse::<i64>().ok()?),
    };
    Some((value, j))
}

fn parse_json_str(bytes: &[u8], start: usize) -> Option<(String, usize)> {
    let mut i = start + 1;
    let mut out = String::new();
    while i < bytes.len() {
        match bytes[i] {
            b'"' => return Some((out, i + 1)),
            b'\\' => {
                i += 1;
                match *bytes.get(i)? {
                    b'"' => out.push('"'),
                    b'\\' => out.push('\\'),
                    b'/' => out.push('/'),
                    b'n' => out.push('\n'),
                    b'r' => out.push('\r'),
                    b't' => out.push('\t'),
                    b'u' => {
                        let hexpart = std::str::from_utf8(bytes.get(i + 1..i + 5)?).ok()?;
                        let code = u32::from_str_radix(hexpart, 16).ok()?;
                        // Surrogate lẻ trong claims là dữ liệu hỏng: bỏ.
                        out.push(char::from_u32(code)?);
                        i += 4;
                    }
                    _ => return None,
                }
            }
            b if b < 0x20 => return None,
            b => out.push(b as char),
        }
        i += 1;
    }
    None
}

pub fn value_as_str(v: &JsonValue) -> Option<&str> {
    match v {
        JsonValue::Str(s) => Some(s),
        _ => None,
    }
}

pub fn value_as_num(v: &JsonValue) -> Option<i64> {
    match v {
        JsonValue::Num(n) => Some(*n),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::crypto::FixedEntropy;

    #[test]
    fn base64url_round_trips() {
        for len in 0..40usize {
            let data: Vec<u8> = (0..len).map(|i| (i * 37 % 251) as u8).collect();
            let encoded = b64url_encode(&data);
            assert!(!encoded.contains('='), "no padding: {encoded}");
            assert!(
                !encoded.contains('+') && !encoded.contains('/'),
                "url safe: {encoded}"
            );
            assert_eq!(b64url_decode(&encoded).as_deref(), Some(data.as_slice()));
        }
    }

    #[test]
    fn base64url_known_vectors() {
        assert_eq!(b64url_encode(b"hello"), "aGVsbG8");
        assert_eq!(b64url_decode("aGVsbG8").as_deref(), Some(&b"hello"[..]));
        // 0xfb 0xff 0xbf chạm đúng hai ký tự cuối của bảng (62 và 63).
        assert_eq!(b64url_encode(&[0xfb, 0xff, 0xbf]), "-_-_");
        assert!(b64url_decode("aGVsbG8=").is_none(), "padding bị từ chối");
        assert!(b64url_decode("a").is_none(), "quá ngắn để mang một byte");
    }

    #[test]
    fn uuid_v7_is_time_ordered_and_well_formed() {
        let mut e = FixedEntropy::new(3);
        let a = uuid_v7(1_700_000_000_000, &mut e);
        let b = uuid_v7(1_700_000_001_000, &mut e);
        assert!(is_uuid_v7(&a), "{a}");
        assert!(is_uuid_v7(&b), "{b}");
        assert!(a < b, "v7 phải sắp theo thời gian");
        assert_eq!(&a[14..15], "7", "version nibble");
        assert!(
            matches!(&b[19..20], "8" | "9" | "a" | "b"),
            "variant nibble"
        );
    }

    #[test]
    fn json_round_trip_for_claims() {
        let text = format!(
            r#"{{"sub":{},"role":"owner","sid_scope":"*","jti":{},"iat":1700000000,"exp":1700000900}}"#,
            json_string("me@example"),
            json_string("abc-123")
        );
        let parsed = parse_flat_json(&text).expect("parse");
        assert_eq!(value_as_str(&parsed[0].1), Some("me@example"));
        assert_eq!(value_as_num(&parsed[4].1), Some(1_700_000_000));
        assert_eq!(value_as_num(&parsed[5].1), Some(1_700_000_900));
    }

    #[test]
    fn json_rejects_garbage_instead_of_guessing() {
        assert!(parse_flat_json("").is_none());
        assert!(parse_flat_json("{").is_none());
        assert!(parse_flat_json("{\"a\":}").is_none());
        assert!(parse_flat_json("{\"a\":[1,2]}").is_none());
        assert!(parse_flat_json("[1,2]").is_none());
        // Thiếu dấu phẩy giữa 2 member — parser phải từ chối, không "đoán".
        assert!(parse_flat_json(r#"{"a":1 "b":2}"#).is_none());
        // Dấu phẩy cuối.
        assert!(parse_flat_json(r#"{"a":1,}"#).is_none());
        assert_eq!(parse_flat_json("{}"), Some(vec![]));
    }
}
