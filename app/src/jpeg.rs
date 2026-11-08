//! JPEG baseline encoder — **tự viết, 0 dependency**.
//!
//! Vì sao phải tự viết: đường MJPEG (§58) cần nén từng frame thành JPEG. Bản
//! v3.30 mượn `jpegenc` của GStreamer, kéo theo **installer 517 MB** cho một
//! việc mà ta chỉ cần đúng một hàm `encode()`. Với người dùng cá nhân, "cài
//! 517 MB để xem màn hình" là cái giá sai. Bản này ~300 dòng, biên dịch vào
//! chính exe, artifact còn khoảng 2 MB.
//!
//! Chuẩn dùng: **JFIF baseline, YCbCr 4:2:0** — mọi trình duyệt và mọi điện
//! thoại giải mã được, không cần cấu hình gì.
//!
//! Những gì **không** làm, và cố ý: không progressive, không 4:4:4, không
//! restart marker, không tối ưu Huffman riêng cho từng ảnh (§58.14).
//!
//! Kiểm chứng: test cuối file mã hoá ảnh tổng hợp rồi **giải mã lại bằng
//! ImageMagick** trong CI — nếu chỉ tự kiểm bằng code của mình thì một lỗi
//! trong bảng Huffman sẽ "qua" mà không ai biết.

// --- Bảng lượng tử chuẩn, phụ lục K của ITU T.81 (thứ tự tự nhiên) ----------

const LUMA_QUANT: [u8; 64] = [
    16, 11, 10, 16, 24, 40, 51, 61, //
    12, 12, 14, 19, 26, 58, 60, 55, //
    14, 13, 16, 24, 40, 57, 69, 56, //
    14, 17, 22, 29, 51, 87, 80, 62, //
    18, 22, 37, 56, 68, 109, 103, 77, //
    24, 35, 55, 64, 81, 104, 113, 92, //
    49, 64, 78, 87, 103, 121, 120, 101, //
    72, 92, 95, 98, 112, 100, 103, 99, //
];

const CHROMA_QUANT: [u8; 64] = [
    17, 18, 24, 47, 99, 99, 99, 99, //
    18, 21, 26, 66, 99, 99, 99, 99, //
    24, 26, 56, 99, 99, 99, 99, 99, //
    47, 66, 99, 99, 99, 99, 99, 99, //
    99, 99, 99, 99, 99, 99, 99, 99, //
    99, 99, 99, 99, 99, 99, 99, 99, //
    99, 99, 99, 99, 99, 99, 99, 99, //
    99, 99, 99, 99, 99, 99, 99, 99, //
];

/// Thứ tự zigzag: vị trí thứ `i` trong dòng bit ứng với ô nào của khối 8×8.
const ZIGZAG: [usize; 64] = [
    0, 1, 8, 16, 9, 2, 3, 10, //
    17, 24, 32, 25, 18, 11, 4, 5, //
    12, 19, 26, 33, 40, 48, 41, 34, //
    27, 20, 13, 6, 7, 14, 21, 28, //
    35, 42, 49, 56, 57, 50, 43, 36, //
    29, 22, 15, 23, 30, 37, 44, 51, //
    58, 59, 52, 45, 38, 31, 39, 46, //
    53, 60, 61, 54, 47, 55, 62, 63, //
];

// --- Bảng Huffman chuẩn, phụ lục K -----------------------------------------

const DC_LUMA_BITS: [u8; 16] = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0];
const DC_LUMA_VALUES: [u8; 12] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

const DC_CHROMA_BITS: [u8; 16] = [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0];
const DC_CHROMA_VALUES: [u8; 12] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

const AC_LUMA_BITS: [u8; 16] = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d];
#[rustfmt::skip]
const AC_LUMA_VALUES: [u8; 162] = [
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
    0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
    0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
    0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa,
];

const AC_CHROMA_BITS: [u8; 16] = [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77];
#[rustfmt::skip]
const AC_CHROMA_VALUES: [u8; 162] = [
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
    0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
    0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
    0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
    0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
    0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5,
    0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
    0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
    0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa,
];

/// Bảng mã hoá dựng từ (bits, values): `symbol -> (mã, độ dài)`.
struct Huffman {
    codes: [u16; 256],
    lengths: [u8; 256],
}

impl Huffman {
    fn new(bits: &[u8; 16], values: &[u8]) -> Self {
        let mut codes = [0u16; 256];
        let mut lengths = [0u8; 256];
        let mut code: u16 = 0;
        let mut k = 0usize;
        for (index, count) in bits.iter().enumerate() {
            for _ in 0..*count {
                if k >= values.len() {
                    break;
                }
                codes[values[k] as usize] = code;
                lengths[values[k] as usize] = (index + 1) as u8;
                code += 1;
                k += 1;
            }
            code <<= 1;
        }
        Self { codes, lengths }
    }
}

/// Ghi bit, tự chèn `0x00` sau mỗi `0xFF` (byte stuffing — quên bước này thì
/// trình duyệt nhận file "hỏng" mà không nói tại sao).
struct BitWriter {
    out: Vec<u8>,
    accumulator: u32,
    bits: u8,
}

impl BitWriter {
    fn new() -> Self {
        Self { out: Vec::new(), accumulator: 0, bits: 0 }
    }

    fn write(&mut self, value: u16, count: u8) {
        if count == 0 {
            return;
        }
        self.accumulator = (self.accumulator << count) | (value as u32 & ((1u32 << count) - 1));
        self.bits += count;
        while self.bits >= 8 {
            self.bits -= 8;
            let byte = ((self.accumulator >> self.bits) & 0xFF) as u8;
            self.out.push(byte);
            if byte == 0xFF {
                self.out.push(0x00);
            }
        }
    }

    /// Đệm bit 1 cho đủ byte (đúng chuẩn: pad bằng 1, không phải 0).
    fn flush(mut self) -> Vec<u8> {
        if self.bits > 0 {
            let pad = 8 - self.bits;
            self.write((1u16 << pad) - 1, pad);
        }
        self.out
    }
}

/// `quality` 1–100, giống thang của mọi encoder khác để so sánh được.
fn scaled_quant(table: &[u8; 64], quality: u8) -> [u16; 64] {
    let quality = quality.clamp(1, 100) as i32;
    let scale = if quality < 50 { 5000 / quality } else { 200 - quality * 2 };
    let mut out = [0u16; 64];
    for (slot, base) in out.iter_mut().zip(table.iter()) {
        let value = (*base as i32 * scale + 50) / 100;
        *slot = value.clamp(1, 255) as u16;
    }
    out
}

/// DCT 1 chiều 8 điểm, dùng bảng cos dựng một lần.
fn dct_1d(input: &[f32; 8], output: &mut [f32; 8], cos_table: &[[f32; 8]; 8]) {
    for (u, row) in cos_table.iter().enumerate() {
        let mut sum = 0.0f32;
        for (x, value) in input.iter().enumerate() {
            sum += value * row[x];
        }
        output[u] = sum;
    }
}

/// DCT 2 chiều + lượng tử hoá, trả khối theo thứ tự tự nhiên (đã chia quant).
fn transform(block: &[f32; 64], quant: &[u16; 64], cos_table: &[[f32; 8]; 8], out: &mut [i32; 64]) {
    let mut rows = [[0f32; 8]; 8];
    for (y, output) in rows.iter_mut().enumerate() {
        let mut input = [0f32; 8];
        input.copy_from_slice(&block[y * 8..y * 8 + 8]);
        dct_1d(&input, output, cos_table);
    }
    for x in 0..8 {
        let mut column = [0f32; 8];
        for (y, cell) in rows.iter().enumerate() {
            column[y] = cell[x];
        }
        let mut transformed = [0f32; 8];
        dct_1d(&column, &mut transformed, cos_table);
        for (y, value) in transformed.iter().enumerate() {
            let index = y * 8 + x;
            out[index] = (*value / quant[index] as f32).round() as i32;
        }
    }
}

fn magnitude(value: i32) -> (u16, u8) {
    if value == 0 {
        return (0, 0);
    }
    let mut size = 0u8;
    let mut temp = value.unsigned_abs();
    while temp > 0 {
        size += 1;
        temp >>= 1;
    }
    let bits = if value < 0 { (value - 1 + (1 << size)) as u16 } else { value as u16 };
    (bits, size)
}

/// Ghi một khối 8×8 đã lượng tử hoá thành dòng bit.
fn encode_block(writer: &mut BitWriter, block: &[i32; 64], previous_dc: &mut i32, dc: &Huffman, ac: &Huffman) {
    let dc_difference = block[0] - *previous_dc;
    *previous_dc = block[0];
    let (bits, size) = magnitude(dc_difference);
    writer.write(dc.codes[size as usize], dc.lengths[size as usize]);
    writer.write(bits, size);

    let mut zero_run = 0u8;
    for step in ZIGZAG.iter().skip(1) {
        let value = block[*step];
        if value == 0 {
            zero_run += 1;
            continue;
        }
        while zero_run > 15 {
            writer.write(ac.codes[0xF0], ac.lengths[0xF0]);
            zero_run -= 16;
        }
        let (bits, size) = magnitude(value);
        let symbol = (zero_run << 4) | size;
        writer.write(ac.codes[symbol as usize], ac.lengths[symbol as usize]);
        writer.write(bits, size);
        zero_run = 0;
    }
    if zero_run > 0 {
        writer.write(ac.codes[0x00], ac.lengths[0x00]);
    }
}

fn push_marker(out: &mut Vec<u8>, marker: u8) {
    out.push(0xFF);
    out.push(marker);
}

fn push_segment(out: &mut Vec<u8>, marker: u8, body: &[u8]) {
    push_marker(out, marker);
    out.extend_from_slice(&((body.len() + 2) as u16).to_be_bytes());
    out.extend_from_slice(body);
}

fn push_quant(out: &mut Vec<u8>, table: &[u16; 64], id: u8) {
    let mut body = Vec::with_capacity(65);
    // Pq=0 (8 bit) | Tq=id. **Id phải khác nhau cho luma và chroma** — bản đầu
    // luôn ghi 0 nên bảng chroma ghi đè bảng luma, và trình giải mã báo
    // "Quantization table 0x01 was not defined" (ImageMagick bắt được, test tự
    // viết của tôi thì không).
    body.push(id & 0x0F);
    for index in ZIGZAG.iter() {
        body.push(table[*index] as u8);
    }
    push_segment(out, 0xDB, &body);
}

fn push_huffman(out: &mut Vec<u8>, class_and_id: u8, bits: &[u8; 16], values: &[u8]) {
    let mut body = Vec::with_capacity(17 + values.len());
    body.push(class_and_id);
    body.extend_from_slice(bits);
    body.extend_from_slice(values);
    push_segment(out, 0xC4, &body);
}

/// Số nguyên 0xFF không bao giờ được xuất hiện trần trong dữ liệu nén — dùng để
/// test tự kiểm mà không cần trình giải mã.
pub fn encode(bgra: &[u8], width: usize, height: usize, quality: u8) -> Vec<u8> {
    assert!(width > 0 && height > 0, "ảnh phải có kích thước dương");
    assert!(
        bgra.len() >= width * height * 4,
        "dữ liệu BGRA phải đủ {width}x{height}x4 byte, nhận {}",
        bgra.len()
    );

    // Bảng cos: cos((2x+1) * u * π / 16) * (u==0 ? 1/√2 : 1) / 2
    let mut cos_table = [[0f32; 8]; 8];
    for (u, row) in cos_table.iter_mut().enumerate() {
        let factor = if u == 0 { std::f32::consts::FRAC_1_SQRT_2 } else { 1.0 } * 0.5;
        for (x, cell) in row.iter_mut().enumerate() {
            *cell = factor * (((2 * x + 1) as f32 * u as f32 * std::f32::consts::PI) / 16.0).cos();
        }
    }

    let luma_quant = scaled_quant(&LUMA_QUANT, quality);
    let chroma_quant = scaled_quant(&CHROMA_QUANT, quality);

    let mut out = Vec::with_capacity(width * height / 8);
    push_marker(&mut out, 0xD8); // SOI
    // APP0 JFIF 1.01, không DPI (0 = "không quan tâm"), tỉ lệ khung 1:1
    push_segment(&mut out, 0xE0, b"JFIF\0\x01\x01\x00\x00\x01\x00\x01\x00\x00");
    push_quant(&mut out, &luma_quant, 0);
    push_quant(&mut out, &chroma_quant, 1);

    // SOF0: baseline, 8 bit, 3 thành phần, 4:2:0
    let mut sof = Vec::with_capacity(15);
    sof.push(8);
    sof.extend_from_slice(&(height as u16).to_be_bytes());
    sof.extend_from_slice(&(width as u16).to_be_bytes());
    sof.push(3);
    sof.extend_from_slice(&[1, 0x22, 0]); // Y: 2×2, quant 0
    sof.extend_from_slice(&[2, 0x11, 1]); // Cb: 1×1, quant 1
    sof.extend_from_slice(&[3, 0x11, 1]); // Cr: 1×1, quant 1
    push_segment(&mut out, 0xC0, &sof);

    push_huffman(&mut out, 0x00, &DC_LUMA_BITS, &DC_LUMA_VALUES);
    push_huffman(&mut out, 0x10, &AC_LUMA_BITS, &AC_LUMA_VALUES);
    push_huffman(&mut out, 0x01, &DC_CHROMA_BITS, &DC_CHROMA_VALUES);
    push_huffman(&mut out, 0x11, &AC_CHROMA_BITS, &AC_CHROMA_VALUES);

    // SOS
    push_segment(&mut out, 0xDA, &[3, 1, 0x00, 2, 0x11, 3, 0x11, 0, 63, 0]);

    let dc_luma = Huffman::new(&DC_LUMA_BITS, &DC_LUMA_VALUES);
    let ac_luma = Huffman::new(&AC_LUMA_BITS, &AC_LUMA_VALUES);
    let dc_chroma = Huffman::new(&DC_CHROMA_BITS, &DC_CHROMA_VALUES);
    let ac_chroma = Huffman::new(&AC_CHROMA_BITS, &AC_CHROMA_VALUES);

    // 4:2:0 ⇒ mỗi MCU là 16×16: 4 khối Y, 1 Cb, 1 Cr.
    let mcu_w = 16usize;
    let mcu_h = 16usize;
    let across = width.div_ceil(mcu_w);
    let down = height.div_ceil(mcu_h);

    let mut writer = BitWriter::new();
    let mut previous = [0i32; 3];
    let mut y_block = [0f32; 64];
    let mut cb_block = [0f32; 64];
    let mut cr_block = [0f32; 64];
    let mut coefficients = [0i32; 64];

    // Lấy pixel BGRA, kẹp toạ độ vào ảnh (viền lặp lại) — ảnh không chia hết
    // cho 16 vẫn phải mã hoá được.
    let pixel = |x: usize, y: usize| -> (f32, f32, f32) {
        let x = x.min(width - 1);
        let y = y.min(height - 1);
        let index = (y * width + x) * 4;
        let b = bgra[index] as f32;
        let g = bgra[index + 1] as f32;
        let r = bgra[index + 2] as f32;
        // RGB -> YCbCr (ITU-R BT.601, đúng công thức JFIF)
        let luma = 0.299 * r + 0.587 * g + 0.114 * b;
        (luma, -0.168736 * r - 0.331264 * g + 0.5 * b + 128.0, 0.5 * r - 0.418688 * g - 0.081312 * b + 128.0)
    };

    for mcu_y in 0..down {
        for mcu_x in 0..across {
            let base_x = mcu_x * mcu_w;
            let base_y = mcu_y * mcu_h;

            // Cb/Cr lấy mẫu 1 điểm cho mỗi 2×2 pixel (trung bình 4 pixel).
            for by in 0..8 {
                for bx in 0..8 {
                    let mut cb_sum = 0f32;
                    let mut cr_sum = 0f32;
                    for dy in 0..2 {
                        for dx in 0..2 {
                            let (_, cb, cr) = pixel(base_x + bx * 2 + dx, base_y + by * 2 + dy);
                            cb_sum += cb;
                            cr_sum += cr;
                        }
                    }
                    cb_block[by * 8 + bx] = cb_sum / 4.0 - 128.0;
                    cr_block[by * 8 + bx] = cr_sum / 4.0 - 128.0;
                }
            }

            for (offset_x, offset_y) in [(0usize, 0usize), (8, 0), (0, 8), (8, 8)] {
                for y in 0..8 {
                    for x in 0..8 {
                        let (luma, _, _) = pixel(base_x + offset_x + x, base_y + offset_y + y);
                        y_block[y * 8 + x] = luma - 128.0;
                    }
                }
                transform(&y_block, &luma_quant, &cos_table, &mut coefficients);
                encode_block(&mut writer, &coefficients, &mut previous[0], &dc_luma, &ac_luma);
            }

            transform(&cb_block, &chroma_quant, &cos_table, &mut coefficients);
            encode_block(&mut writer, &coefficients, &mut previous[1], &dc_chroma, &ac_chroma);
            transform(&cr_block, &chroma_quant, &cos_table, &mut coefficients);
            encode_block(&mut writer, &coefficients, &mut previous[2], &dc_chroma, &ac_chroma);
        }
    }

    out.extend_from_slice(&writer.flush());
    push_marker(&mut out, 0xD9); // EOI
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Ảnh kiểm thử: dải màu + ô chữ nhật để có cả vùng phẳng (nhiều hệ số 0)
    /// và vùng cạnh (nhiều hệ số cao) — ảnh chỉ một màu sẽ "qua" dù bảng
    /// Huffman sai.
    fn test_image(width: usize, height: usize) -> Vec<u8> {
        let mut bgra = vec![0u8; width * height * 4];
        for (y, row) in bgra.chunks_mut(width * 4).enumerate() {
            for (x, pixel) in row.chunks_mut(4).enumerate() {
                pixel[0] = ((y * 255) / height.max(1)) as u8; // B
                pixel[1] = ((x * 255) / width.max(1)) as u8; // G
                pixel[2] = if (x / 16 + y / 16).is_multiple_of(2) { 220 } else { 30 }; // R
                pixel[3] = 255;
            }
        }
        bgra
    }


    #[test] #[ignore] fn benchmark_1080p() {
        // i5-7300HQ: nếu nén 1080p một frame mất > 100 ms thì 15 fps là không
        // thể trên một core. Đo **trong sandbox** chỉ để biết bậc độ lớn.
        let (w, h) = (1920usize, 1080usize);
        let mut bgra = vec![0u8; w * h * 4];
        for (y, row) in bgra.chunks_mut(w * 4).enumerate() {
            for (x, pixel) in row.chunks_mut(4).enumerate() {
                pixel[0] = (x % 256) as u8;
                pixel[1] = (y % 256) as u8;
                pixel[2] = 128;
                pixel[3] = 255;
            }
        }
        let _ = encode(&bgra, w, h, 70); // warm-up
        let start = std::time::Instant::now();
        let rounds = 5;
        let mut total = 0;
        for _ in 0..rounds {
            total = encode(&bgra, w, h, 70).len();
        }
        let each = start.elapsed() / rounds;
        eprintln!("1080p q70: {each:?}/frame, {} KB, {} fps tối đa trên một core", total / 1024, 1000 / each.as_millis().max(1));
    }

    #[test] #[ignore] fn write_sample_for_external_check() {
        // Kích thước/chất lượng lấy từ biến môi trường để một test phục vụ mọi
        // ca kiểm bằng ImageMagick (xem scripts/check-jpeg.sh).
        let spec = std::env::var("LANTERN_DUMP").unwrap_or_else(|_| "320 200 75".into());
        let parts: Vec<usize> = spec.split_whitespace().filter_map(|v| v.parse().ok()).collect();
        let (w, h, q) = (parts[0], parts[1], parts[2] as u8);
        let mut bgra = vec![0u8; w * h * 4];
        for y in 0..h {
            for x in 0..w {
                let index = (y * w + x) * 4;
                let (r, g, b) = if (w / 8..w / 3).contains(&x) && (h / 5..h / 2).contains(&y) {
                    (220u8, 30u8, 30u8)
                } else if y > h * 3 / 4 {
                    (0u8, 60u8, 220u8)
                } else if (x / 4).is_multiple_of(2) && y < h / 8 {
                    (0u8, 0u8, 0u8)
                } else {
                    (128u8, 128u8, 128u8)
                };
                bgra[index] = b;
                bgra[index + 1] = g;
                bgra[index + 2] = r;
                bgra[index + 3] = 255;
            }
        }
        std::fs::write("/tmp/out.jpg", encode(&bgra, w, h, q)).expect("ghi /tmp/out.jpg");
    }

    #[test] fn output_is_a_well_formed_jpeg() {
        let image = test_image(64, 48);
        let jpeg = encode(&image, 64, 48, 70);
        assert_eq!(&jpeg[..2], &[0xFF, 0xD8], "phải bắt đầu bằng SOI");
        assert_eq!(&jpeg[jpeg.len() - 2..], &[0xFF, 0xD9], "phải kết thúc bằng EOI");
        assert!(jpeg.len() > 200, "ảnh 64×48 phải nén ra > 200 byte, được {}", jpeg.len());
        // SOF0 phải ghi đúng kích thước.
        let sof = jpeg.windows(2).position(|w| w == [0xFF, 0xC0]).expect("phải có SOF0");
        assert_eq!(u16::from_be_bytes([jpeg[sof + 5], jpeg[sof + 6]]), 48, "chiều cao");
        assert_eq!(u16::from_be_bytes([jpeg[sof + 7], jpeg[sof + 8]]), 64, "chiều rộng");
    }

    #[test] fn no_stray_ff_in_the_entropy_coded_data() {
        // `0xFF` chỉ được xuất hiện khi đi kèm `0x00` (stuffing) hoặc là marker.
        // Kiểm từ sau SOS tới EOI — đúng lỗi mà trình giải mã báo "premature end".
        let jpeg = encode(&test_image(80, 64), 80, 64, 70);
        let sos = jpeg.windows(2).position(|w| w == [0xFF, 0xDA]).expect("SOS");
        let body = &jpeg[sos + 2..jpeg.len() - 2];
        let mut i = 0;
        while i < body.len() {
            if body[i] == 0xFF {
                assert_eq!(body[i + 1], 0x00, "0xFF trần trong dữ liệu nén tại vị trí {i}");
                i += 2;
            } else {
                i += 1;
            }
        }
    }

    #[test] fn quality_changes_size_in_the_expected_direction() {
        let image = test_image(160, 120);
        let low = encode(&image, 160, 120, 20).len();
        let high = encode(&image, 160, 120, 95).len();
        assert!(low < high, "q20 ({low}) phải nhỏ hơn q95 ({high})");
    }

    #[test] fn odd_sizes_do_not_panic_or_produce_a_broken_header() {
        // 1×1 và 127×93: không chia hết cho 16 ⇒ phải đệm viền, không được panic.
        for (w, h) in [(1usize, 1usize), (127, 93), (17, 16)] {
            let jpeg = encode(&test_image(w, h), w, h, 70);
            assert_eq!(&jpeg[..2], &[0xFF, 0xD8]);
            assert_eq!(&jpeg[jpeg.len() - 2..], &[0xFF, 0xD9]);
        }
    }

    #[test] fn encode_refuses_input_that_is_too_short() {
        // Trả panic rõ ràng còn hơn đọc ngoài mảng rồi tạo ảnh rác.
        let result = std::panic::catch_unwind(|| encode(&[0u8; 10], 100, 100, 70));
        assert!(result.is_err());
    }

    #[test] fn the_huffman_table_covers_every_symbol_it_can_emit() {
        // Mọi ký hiệu AC có thể sinh ra (`runs<<4 | size`, size 1..=10) phải có
        // mã. Thiếu một mã ⇒ `lengths[symbol]==0` ⇒ ghi 0 bit ⇒ ảnh hỏng mà
        // không có lỗi nào — đúng loại lỗi im lặng cần test.
        let ac = Huffman::new(&AC_LUMA_BITS, &AC_LUMA_VALUES);
        for run in 0u8..16 {
            for size in 1u8..=10 {
                let symbol = (run << 4) | size;
                assert!(ac.lengths[symbol as usize] > 0, "thiếu mã cho ký hiệu {symbol:#04x}");
            }
        }
        assert!(ac.lengths[0x00] > 0, "thiếu EOB");
        assert!(ac.lengths[0xF0] > 0, "thiếu ZRL");
        let dc = Huffman::new(&DC_LUMA_BITS, &DC_LUMA_VALUES);
        for size in 0u8..=11 {
            assert!(dc.lengths[size as usize] > 0, "thiếu mã DC cho size {size}");
        }
    }
}
