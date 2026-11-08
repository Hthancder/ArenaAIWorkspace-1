//! SHA-256, HMAC-SHA256, constant-time compare, entropy — viết tay vì crate
//! này **0 dependency** (spec §56.1): mỗi dependency là một lý do CI đỏ vì thứ
//! không liên quan tới spec.
//!
//! Đúng đắn được neo vào vector chuẩn: FIPS 180-4 (SHA-256) và RFC 4231 (HMAC).
//! Đây không phải thư viện mã hoá để dùng cho TLS — chỉ dùng cho hash token,
//! HMAC và so sánh hằng thời gian. TLS do hệ điều hành/trình duyệt làm (§5.8).

const K: [u32; 64] = [
    0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4,
    0xab1c_5ed5, 0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe,
    0x9bdc_06a7, 0xc19b_f174, 0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f,
    0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da, 0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
    0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967, 0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc,
    0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85, 0xa2bf_e8a1, 0xa81a_664b,
    0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070, 0x19a4_c116,
    0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
    0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7,
    0xc671_78f2,
];

const H0: [u32; 8] = [
    0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab,
    0x5be0_cd19,
];

/// SHA-256 (FIPS 180-4).
pub fn sha256(input: &[u8]) -> [u8; 32] {
    let mut h = H0;
    let bit_len = (input.len() as u64).wrapping_mul(8);

    let mut msg = Vec::with_capacity(input.len() + 72);
    msg.extend_from_slice(input);
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    // `msg.len()` luôn là bội của 64 sau khi padding, nên chỉ số dưới đây an toàn.
    // (Dùng vòng `for` theo chỉ số thay vì `chunks_exact`: clippy hiện đại khuyên
    // `as_chunks` cho chunk size hằng, và API đó ổn định từ 1.88 — nhưng chỉ số
    // thì không phụ thuộc phiên bản toolchain, và ở đây cũng ngắn hơn.)
    let mut block_start = 0usize;
    while block_start < msg.len() {
        let block = &msg[block_start..block_start + 64];
        let mut w = [0u32; 64];
        let mut word_index = 0usize;
        while word_index < 16 {
            let o = word_index * 4;
            w[word_index] =
                u32::from_be_bytes([block[o], block[o + 1], block[o + 2], block[o + 3]]);
            word_index += 1;
        }
        let mut i = 16usize;
        while i < 64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
            i += 1;
        }

        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];

        let mut j = 0usize;
        while j < 64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let t1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[j])
                .wrapping_add(w[j]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
            j += 1;
        }

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
        block_start += 64;
    }

    let mut out = [0u8; 32];
    for (i, word) in h.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

/// HMAC-SHA256 (RFC 2104, block size 64).
pub fn hmac_sha256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    let mut block = [0u8; 64];
    if key.len() > 64 {
        block[..32].copy_from_slice(&sha256(key));
    } else {
        block[..key.len()].copy_from_slice(key);
    }

    let mut inner = Vec::with_capacity(64 + msg.len());
    inner.extend(block.iter().map(|b| b ^ 0x36));
    inner.extend_from_slice(msg);
    let inner_hash = sha256(&inner);

    let mut outer = Vec::with_capacity(96);
    outer.extend(block.iter().map(|b| b ^ 0x5c));
    outer.extend_from_slice(&inner_hash);
    sha256(&outer)
}

/// So sánh hằng thời gian (§41.6 "Timing"). Chỉ lộ **độ dài**, không lộ vị trí
/// byte khác đầu tiên — đủ cho `token == token` vì mọi token của ta cùng cỡ.
pub fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

/// Hex thường (lowercase). Dùng cho token, fingerprint, UUID.
pub fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push(DIGITS[(b >> 4) as usize] as char);
        out.push(DIGITS[(b & 0x0f) as usize] as char);
    }
    out
}

/// Nguồn ngẫu nhiên. Trên máy thật là `BCryptGenRandom` (§41.6); trong test là
/// một dòng xác định để lỗi tái hiện được. Tách trait để code **không** tự gọi
/// RNG hệ thống ở chỗ không test được.
pub trait Entropy {
    fn fill(&mut self, out: &mut [u8]);
}

/// xorshift64* — **không** dùng cho production, chỉ cho test/demo.
pub struct FixedEntropy {
    state: u64,
}

impl FixedEntropy {
    pub fn new(seed: u64) -> Self {
        Self {
            state: if seed == 0 { 0x9e37_79b9_7f4a_7c15 } else { seed },
        }
    }
}

impl Default for FixedEntropy {
    fn default() -> Self {
        Self::new(0x9e37_79b9_7f4a_7c15)
    }
}

impl Entropy for FixedEntropy {
    fn fill(&mut self, out: &mut [u8]) {
        for chunk in out.chunks_mut(8) {
            let mut x = self.state;
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            self.state = x;
            let value = x.wrapping_mul(0x2545_f491_4f6c_dd1d).to_le_bytes();
            chunk.copy_from_slice(&value[..chunk.len()]);
        }
    }
}

/// `n_bytes` byte ngẫu nhiên, trả về hex (in ra log sẽ không bao giờ thấy token
/// thật vì token chỉ nằm trong cookie — §41.6).
pub fn random_hex(n_bytes: usize, entropy: &mut impl Entropy) -> String {
    let mut buf = vec![0u8; n_bytes];
    entropy.fill(&mut buf);
    hex(&buf)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_matches_fips_vectors() {
        assert_eq!(
            hex(&sha256(b"")),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            hex(&sha256(b"abc")),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            hex(&sha256(
                b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
            )),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
    }

    #[test]
    fn sha256_handles_block_boundaries() {
        // 55/56/64 byte là các mốc padding dễ sai nhất.
        for len in [55usize, 56, 63, 64, 65, 119, 120, 128] {
            let data = vec![b'a'; len];
            let digest = sha256(&data);
            assert_eq!(digest.len(), 32, "len {len}");
        }
        assert_ne!(sha256(&[0u8; 64]), sha256(&[0u8; 65]));
    }

    #[test]
    fn hmac_matches_rfc4231() {
        // RFC 4231 test case 2.
        assert_eq!(
            hex(&hmac_sha256(b"Jefe", b"what do ya want for nothing?")),
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        );
    }

    #[test]
    fn constant_time_eq_is_still_correct() {
        assert!(ct_eq(b"abc", b"abc"));
        assert!(!ct_eq(b"abc", b"abd"));
        assert!(!ct_eq(b"abc", b"ab"));
    }

    #[test]
    fn random_hex_is_deterministic_for_a_seed_and_never_empty() {
        let mut a = FixedEntropy::new(7);
        let mut b = FixedEntropy::new(7);
        assert_eq!(random_hex(16, &mut a), random_hex(16, &mut b));
        assert_eq!(random_hex(16, &mut FixedEntropy::new(7)).len(), 32);
        assert_ne!(
            random_hex(16, &mut FixedEntropy::new(7)),
            random_hex(16, &mut FixedEntropy::new(8))
        );
    }
}
