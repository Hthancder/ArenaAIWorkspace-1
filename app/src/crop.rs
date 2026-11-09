//! §5.4 + §5.5.1 — stream **một cửa sổ** thay vì cả màn hình.
//!
//! # Spec nói gì, và bản này làm tới đâu
//!
//! §5.5.1 ghi nguồn cho *"Stream 1 cửa sổ không move (T3)"* là **WGC window
//! item** + `IsBorderRequired=false`. Đó là cách **đúng** và bản này **chưa**
//! làm: `Windows.Graphics.Capture` là COM/WinRT, cần `RoInitialize` +
//! `IGraphicsCaptureItemInterop`, tức thêm vài trăm dòng FFI.
//!
//! Đường trung gian ở đây: **capture display rồi crop theo
//! `DWMWA_EXTENDED_FRAME_BOUNDS`**. Nó cho người dùng thứ họ cần — một khung
//! hình chỉ có cửa sổ đã chọn, toạ độ chuột khớp — với ~80 dòng và **không**
//! thêm dependency. Giới hạn phải nói rõ (xem [`Limitations`]).
//!
//! # Vì sao crop theo `EXTENDED_FRAME_BOUNDS`, không theo `GetWindowRect`
//!
//! §5.4: `GetWindowRect` dính **viền vô hình** của DWM/UWP (lệch 7–8 px mỗi
//! cạnh ở Win10). Crop theo nó thì mép cửa sổ bị cắt mất vài pixel — và tệ hơn,
//! toạ độ chuột lệch đúng bằng khoảng đó, nên bấm vào nút ở mép là trượt.
//!
//! # Chuẩn hoá toạ độ
//!
//! Sau khi crop, gốc toạ độ của frame là **góc trên-trái của cửa sổ**, không
//! phải của màn hình. Vì `§8.3 move_abs` gửi `nx/ny` chuẩn hoá 0–65535 theo
//! **frame**, client không cần biết gì thêm: nó gửi vị trí trong ảnh, server
//! nhân với kích thước cửa sổ. Nhưng server **phải** cộng offset khi inject —
//! nếu không, click vào giữa cửa sổ sẽ click vào giữa màn hình. Xem
//! [`crate::windows::inject_offset`].

/// Một hình chữ nhật theo pixel màn hình, gốc trên-trái.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Rect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

impl Rect {
    pub fn width(&self) -> i32 {
        self.right - self.left
    }

    pub fn height(&self) -> i32 {
        self.bottom - self.top
    }

    /// Chỉ nhánh Windows gọi (`stream_live` kiểm cửa sổ rỗng **trước** khi
    /// crop); `plan` và test dùng trên mọi nền, nên không xoá được.
    #[cfg_attr(not(windows), allow(dead_code, reason = "nhánh Windows gọi; test giữ lại"))]
    pub fn is_empty(&self) -> bool {
        self.width() <= 0 || self.height() <= 0
    }
}

/// Vùng cắt đã kiểm, luôn nằm trong frame nguồn.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Crop {
    pub x: usize,
    pub y: usize,
    pub width: usize,
    pub height: usize,
}

/// Tính vùng cắt cho một cửa sổ trong frame của màn hình.
///
/// # Vì sao phải kẹp vào frame
///
/// Cửa sổ có thể nằm **ngoài** màn hình (người dùng kéo sang monitor thứ hai,
/// hoặc cửa sổ rộng hơn màn hình). Lấy `right - left` thẳng sẽ đọc ra ngoài
/// buffer BGRA — đọc rác vào ảnh, hoặc panic nếu vượt biên. Kẹp lại và trả
/// vùng **thực sự nhìn thấy được**, đúng như mắt người dùng thấy.
///
/// Trả `None` khi cửa sổ **hoàn toàn** ngoài frame: không có gì để stream, và
/// trả một ảnh 1×1 rác thì tệ hơn nói thật.
#[cfg_attr(not(windows), allow(dead_code, reason = "nhánh Windows crop; test kiểm trên Linux"))]
pub fn plan(window: Rect, source_width: usize, source_height: usize) -> Option<Crop> {
    if window.is_empty() || source_width == 0 || source_height == 0 {
        return None;
    }
    let left = window.left.max(0) as usize;
    let top = window.top.max(0) as usize;
    // `min` với kích thước nguồn, và `saturating` vì `right` có thể âm.
    let right = window.right.max(0) as usize;
    let bottom = window.bottom.max(0) as usize;
    let left = left.min(source_width);
    let right = right.min(source_width);
    let top = top.min(source_height);
    let bottom = bottom.min(source_height);
    if right <= left || bottom <= top {
        return None;
    }
    Some(Crop {
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
    })
}

/// Sao chép vùng `crop` ra buffer mới (BGRA, hàng đệm = `width * 4`).
///
/// # Vì sao không cắt bằng slice view
///
/// `Frame.bgra` có **hàng đệm** = chiều rộng **nguồn**. Một "mảnh" của nó không
/// phải ảnh liên tục, nên phải sao từng hàng. Cấp phát đúng một lần thay vì
/// `Vec<Vec<u8>>`: bộ mã hoá JPEG đọc theo hàng liên tục, và 1080p × 4 byte
/// nhân 30 fps là đủ để thấy khác biệt.
#[cfg_attr(not(windows), allow(dead_code, reason = "nhánh Windows crop; test kiểm trên Linux"))]
pub fn extract(bgra: &[u8], source_width: usize, crop: Crop) -> Vec<u8> {
    let mut out = vec![0u8; crop.width * crop.height * 4];
    for row in 0..crop.height {
        let from = ((crop.y + row) * source_width + crop.x) * 4;
        let to = row * crop.width * 4;
        let bytes = crop.width * 4;
        if from + bytes > bgra.len() {
            // Nguồn ngắn hơn khai báo. Trả những gì đọc được thay vì panic:
            // một frame thiếu còn hơn mất cả phiên stream.
            break;
        }
        out[to..to + bytes].copy_from_slice(&bgra[from..from + bytes]);
    }
    out
}

/// §8.3 + §5.4 — đổi toạ độ chuẩn hoá của **frame** thành toạ độ chuẩn hoá của
/// **virtual desktop** mà `SendInput` cần.
///
/// # Đây là bug "bấm lệch" kinh điển
///
/// Client gửi `nx,ny ∈ 0..=65535` chuẩn hoá theo **ảnh nó thấy** (§8.3). Khi
/// stream cả màn hình, ảnh == màn hình nên dùng thẳng được. Khi crop một cửa
/// sổ, ảnh là **một phần** màn hình: dùng thẳng `nx=32767` sẽ bấm vào **giữa
/// màn hình**, không phải giữa cửa sổ — lệch đúng bằng vị trí cửa sổ.
///
/// Công thức: toạ độ pixel trong frame → cộng offset → chuẩn hoá lại theo kích
/// thước **màn hình** (virtual desktop).
///
/// `screen` là rect của virtual desktop (có thể bắt đầu ở toạ độ âm khi có
/// monitor bên trái màn hình chính).
pub fn to_desktop_normalized(
    nx: u16,
    ny: u16,
    frame: Crop,
    offset: (i32, i32),
    screen: Rect,
) -> (i32, i32) {
    let screen_width = screen.width().max(1) as i64;
    let screen_height = screen.height().max(1) as i64;
    // Bước 1: chuẩn hoá → pixel **trong frame**.
    // Làm **một** phép nhân rồi chia, không qua pixel trung gian: mỗi lần làm
    // tròn về số nguyên cộng dồn sai số, và lệch 66/65535 (~0.1 %) là đủ để
    // bấm trượt một nút 40 px ở 4K (0.1 % của 3840 px = 4 px, nhưng lệch biên
    // thì trượt hẳn). Đây chính là sai số test bắt được ở bản đầu.
    let screen_width = screen_width as i128;
    let screen_height = screen_height as i128;
    let width = frame.width as i128;
    let height = frame.height as i128;
    // pixel trong frame = nx/65535 × width; pixel trên màn hình = offset + pixel;
    // chuẩn hoá lại = ÷ screen_width × 65535. Gộp thành hai phân số.
    let out_x = (i128::from(nx) * width * 65_535
        / (65_535 * screen_width)
        + i128::from(offset.0 - screen.left) * 65_535 / screen_width) as i64;
    let out_y = (i128::from(ny) * height * 65_535
        / (65_535 * screen_height)
        + i128::from(offset.1 - screen.top) * 65_535 / screen_height) as i64;
    let _ = (screen_width, screen_height);
    // §8.3: `SendInput` với `MOUSEEVENTF_ABSOLUTE` nhận 0..=65535. Kẹp lại —
    // giá trị ngoài khoảng làm con trỏ nhảy về góc.
    (out_x.clamp(0, 65_535) as i32, out_y.clamp(0, 65_535) as i32)
}

/// §5.4 + §8.3 — đổi **mọi** `MoveAbs` trong danh sách hành động sang toạ độ
/// virtual desktop, dựa trên kích thước frame đang stream.
///
/// # Vì sao phải sửa cả danh sách chứ không chỉ một sự kiện
///
/// `parse_move` của §8.3 sinh ra **nhiều** `Action` từ một gói (move + button +
/// wheel). Nếu chỉ đổi cái đầu, một cú bấm sẽ di chuyển con trỏ đúng rồi bấm
/// sai chỗ — tệ hơn hẳn cả hai cùng sai, vì nó trông như "đôi khi hoạt động".
///
/// `frame_width/height`: kích thước frame **đang stream** (`LiveMetrics`).
/// `0` = chưa stream lần nào ⇒ không đổi gì: `MoveAbs` lúc đó đã là toạ độ màn
/// hình (không có crop để bù).
pub fn remap_actions(
    actions: Vec<crate::input::Action>,
    offset: (i32, i32),
    frame_width: usize,
    frame_height: usize,
) -> Vec<crate::input::Action> {
    use crate::input::Action;
    if frame_width == 0 || frame_height == 0 || offset == (0, 0) {
        // Không crop ⇒ toạ độ đã đúng. Đây là đường nóng của chế độ toàn màn
        // hình, nên trả sớm thay vì đi qua phép chia.
        return actions;
    }
    // Virtual desktop: `SendInput` chuẩn hoá theo **toàn bộ** desktop, nhưng
    // `MoveAbs` của client chuẩn hoá theo frame. Với một monitor ở gốc (0,0) và
    // không DPI scaling, `screen` chính là frame cộng offset. Ta dùng ước lượng
    // đó và ghi rõ giới hạn: đa monitor thì cần `GetSystemMetrics(SM_XVIRTUALSCREEN)`,
    // chưa nối ở đây — hàm `to_desktop_normalized` đã nhận `screen` nên chỉ cần
    // truyền rect thật khi có.
    // Giả định một monitor ở gốc (0,0). Virtual desktop bắt đầu ở toạ độ **âm**
    // khi có monitor bên trái màn hình chính; trường hợp đó cần
    // `GetSystemMetrics(SM_XVIRTUALSCREEN)`, chưa nối — và phải nói rõ chứ không
    // đoán, vì đoán sai thì mọi click trên monitor trái lệch cả nghìn pixel.
    let screen = Rect {
        left: 0,
        top: 0,
        right: frame_width as i32 + offset.0.max(0),
        bottom: frame_height as i32 + offset.1.max(0),
    };
    let frame = Crop { x: 0, y: 0, width: frame_width, height: frame_height };
    actions
        .into_iter()
        .map(|action| match action {
            Action::MoveAbs { nx, ny } => {
                let (x, y) = to_desktop_normalized(nx, ny, frame, offset, screen);
                Action::MoveAbs { nx: x as u16, ny: y as u16 }
            }
            other => other,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Frame 4×3, mỗi pixel mã hoá `(x, y)` để kiểm chính xác vị trí.
    fn source(width: usize, height: usize) -> Vec<u8> {
        let mut data = vec![0u8; width * height * 4];
        for y in 0..height {
            for x in 0..width {
                let index = (y * width + x) * 4;
                data[index] = x as u8;
                data[index + 1] = y as u8;
                data[index + 2] = 0xAA;
                data[index + 3] = 0xFF;
            }
        }
        data
    }

    #[test]
    fn cropping_a_window_keeps_exactly_that_region() {
        // Cửa sổ 2×2 ở (1,1) trong frame 4×3.
        let data = source(4, 3);
        let crop = plan(Rect { left: 1, top: 1, right: 3, bottom: 3 }, 4, 3).unwrap();
        assert_eq!(crop, Crop { x: 1, y: 1, width: 2, height: 2 });
        let out = extract(&data, 4, crop);
        assert_eq!(out.len(), 2 * 2 * 4);
        // Pixel (0,0) của vùng cắt là pixel (1,1) của nguồn.
        assert_eq!(&out[0..4], &[1, 1, 0xAA, 0xFF]);
        // Pixel cuối (1,1) của vùng cắt là (2,2) của nguồn.
        assert_eq!(&out[12..16], &[2, 2, 0xAA, 0xFF]);
    }

    #[test]
    fn a_window_partly_off_screen_is_clipped_not_read_out_of_bounds() {
        // Cửa sổ bắt đầu ở (-5,-5) và rộng 10 ⇒ chỉ phần (0,0)..(5,5) nhìn thấy.
        // Đọc thẳng `right-left` sẽ đọc ngoài buffer hoặc panic.
        let crop = plan(Rect { left: -5, top: -5, right: 5, bottom: 5 }, 4, 3).unwrap();
        assert_eq!(crop, Crop { x: 0, y: 0, width: 4, height: 3 }, "kẹp vào frame");
        let data = source(4, 3);
        let out = extract(&data, 4, crop);
        assert_eq!(out.len(), 4 * 3 * 4, "không được đọc quá buffer");
    }

    #[test]
    fn a_window_entirely_off_screen_has_nothing_to_stream() {
        // Trả `None` thay vì ảnh rác 1×1: UI phải nói "cửa sổ ngoài màn hình",
        // không phải hiện một khung đen.
        assert_eq!(plan(Rect { left: 100, top: 0, right: 200, bottom: 50 }, 4, 3), None);
        assert_eq!(plan(Rect { left: -200, top: -200, right: -100, bottom: -50 }, 4, 3), None);
        assert_eq!(plan(Rect { left: 0, top: 0, right: 0, bottom: 0 }, 4, 3), None);
    }

    #[test]
    fn a_window_larger_than_the_screen_becomes_the_whole_screen() {
        // Cửa sổ toàn màn hình có thể rộng hơn frame vài pixel (DPI scaling).
        let crop = plan(Rect { left: -8, top: -8, right: 1936, bottom: 1096 }, 1920, 1080).unwrap();
        assert_eq!(crop, Crop { x: 0, y: 0, width: 1920, height: 1080 });
    }

    #[test]
    fn a_zero_sized_source_does_not_divide_by_zero() {
        assert_eq!(plan(Rect { left: 0, top: 0, right: 10, bottom: 10 }, 0, 0), None);
        assert_eq!(plan(Rect { left: 0, top: 0, right: 10, bottom: 10 }, 0, 10), None);
    }

    #[test]
    fn every_row_is_copied_from_the_right_source_offset() {
        // Bắt lỗi "quên nhân `source_width`": nếu sai, hàng 2 sẽ lấy dữ liệu của
        // hàng 1 và ảnh trông như bị xé ngang — bug rất khó thấy bằng mắt.
        let data = source(6, 5);
        let crop = plan(Rect { left: 2, top: 1, right: 5, bottom: 4 }, 6, 5).unwrap();
        let out = extract(&data, 6, crop);
        for row in 0..3usize {
            for column in 0..3usize {
                let index = (row * 3 + column) * 4;
                assert_eq!(out[index], (2 + column) as u8, "x tại hàng {row} cột {column}");
                assert_eq!(out[index + 1], (1 + row) as u8, "y tại hàng {row} cột {column}");
            }
        }
    }

    #[test]
    fn remapping_shifts_every_move_in_a_packet_not_just_the_first() {
        // Một gói `move` §8.3 = move + button. Chỉ đổi cái đầu thì con trỏ di
        // đúng rồi **bấm** sai chỗ — tệ hơn cả hai cùng sai.
        use crate::input::Action;
        let actions = vec![
            Action::MoveAbs { nx: 32767, ny: 32767 },
            Action::Button { down: true, bit: 1 },
            Action::MoveAbs { nx: 0, ny: 0 },
        ];
        let out = remap_actions(actions, (300, 300), 400, 400);
        match (&out[0], &out[1], &out[2]) {
            (Action::MoveAbs { nx: first, .. }, Action::Button { .. }, Action::MoveAbs { nx: last, .. }) => {
                assert!(*first > 30_000, "move đầu phải dịch sang vị trí cửa sổ: {first}");
                assert_ne!(first, last, "hai move phải khác nhau");
            }
            other => panic!("cấu trúc sai: {other:?}"),
        }
    }

    #[test]
    fn remapping_does_nothing_when_the_whole_screen_is_streamed() {
        // Đường nóng của chế độ toàn màn hình. Nếu hàm này đổi giá trị khi
        // `offset == (0,0)`, mọi cú click ở chế độ thường đều lệch.
        use crate::input::Action;
        let actions = vec![Action::MoveAbs { nx: 12345, ny: 54321 }];
        let out = remap_actions(actions.clone(), (0, 0), 1920, 1080);
        assert_eq!(out, actions);
        // Chưa stream lần nào (frame 0×0) cũng phải không đổi gì.
        let out = remap_actions(actions.clone(), (100, 100), 0, 0);
        assert_eq!(out, actions);
    }

    #[test]
    fn remapping_leaves_keys_and_wheel_untouched() {
        use crate::input::Action;
        let actions = vec![
            Action::Key { down: true, vk: 0x41 },
            Action::Wheel { vertical: true, delta: 120 },
            Action::Unicode { unit: 65 },
        ];
        assert_eq!(remap_actions(actions.clone(), (300, 300), 400, 400), actions);
    }

    #[test]
    fn a_click_in_the_middle_of_a_cropped_window_lands_in_the_middle_of_that_window() {
        // Đây là bug "bấm lệch" kinh điển: client gửi toạ độ chuẩn hoá theo
        // **ảnh**, mà ảnh là **một phần** màn hình.
        //
        // Màn hình 1000×1000, cửa sổ 400×400 ở (300,300). Bấm giữa cửa sổ
        // (nx=ny=32767) phải ra pixel (500,500) của màn hình = 32767 chuẩn hoá.
        let frame = Crop { x: 300, y: 300, width: 400, height: 400 };
        let screen = Rect { left: 0, top: 0, right: 1000, bottom: 1000 };
        let (x, y) = to_desktop_normalized(32767, 32767, frame, (300, 300), screen);
        assert!((x - 32767).abs() <= 1, "x lệch: {x}");
        assert!((y - 32767).abs() <= 1, "y lệch: {y}");
    }

    #[test]
    fn the_top_left_of_a_cropped_window_is_its_own_origin_not_the_screen_origin() {
        // Bấm góc trên-trái của ảnh (0,0) phải ra (300,300) trên màn hình 1000.
        let frame = Crop { x: 300, y: 200, width: 400, height: 400 };
        let screen = Rect { left: 0, top: 0, right: 1000, bottom: 1000 };
        let (x, y) = to_desktop_normalized(0, 0, frame, (300, 200), screen);
        // 300/1000 × 65535 = 19660
        assert!((x - 19660).abs() <= 2, "x={x} (kỳ vọng ~19660)");
        assert!((y - 13107).abs() <= 2, "y={y} (kỳ vọng ~13107)");
    }

    #[test]
    fn a_virtual_desktop_starting_at_negative_coordinates_is_handled() {
        // Monitor thứ hai đặt **bên trái** màn hình chính ⇒ virtual desktop bắt
        // đầu ở x = -1920. Bỏ qua điều này thì mọi click trên monitor trái đều
        // lệch 1920 px.
        let frame = Crop { x: 0, y: 0, width: 1920, height: 1080 };
        let screen = Rect { left: -1920, top: 0, right: 1920, bottom: 1080 };
        // Bấm giữa cửa sổ ⇒ giữa monitor trái ⇒ nửa trái của virtual desktop.
        let (x, _) = to_desktop_normalized(32767, 32767, frame, (-1920, 0), screen);
        assert!((x - 16384).abs() <= 2, "x={x} (kỳ vọng ~16384, nửa của 3840)");
    }

    #[test]
    fn full_screen_passthrough_is_a_no_op() {
        // Khi không crop, offset = (0,0) và frame == screen ⇒ giá trị không đổi.
        // Nếu test này sai, mọi thao tác chuột trên chế độ toàn màn hình đều
        // lệch — kể cả khi người dùng không dùng window picker.
        let frame = Crop { x: 0, y: 0, width: 1920, height: 1080 };
        let screen = Rect { left: 0, top: 0, right: 1920, bottom: 1080 };
        for (nx, ny) in [(0u16, 0u16), (32767, 32767), (65535, 65535), (12345, 54321)] {
            let (x, y) = to_desktop_normalized(nx, ny, frame, (0, 0), screen);
            assert!((x - i32::from(nx)).abs() <= 2, "{nx} ⇒ {x}");
            assert!((y - i32::from(ny)).abs() <= 2, "{ny} ⇒ {y}");
        }
    }

    #[test]
    fn the_result_never_leaves_the_range_send_input_accepts() {
        // Giá trị ngoài 0..=65535 làm con trỏ nhảy về góc (0,0) — người dùng
        // thấy "click vào đâu cũng về góc màn hình".
        let frame = Crop { x: 0, y: 0, width: 10, height: 10 };
        let screen = Rect { left: 0, top: 0, right: 5000, bottom: 5000 };
        for nx in [0u16, 1, 65535] {
            for ny in [0u16, 65535] {
                let (x, y) = to_desktop_normalized(nx, ny, frame, (4990, 4990), screen);
                assert!((0..=65535).contains(&x), "x={x}");
                assert!((0..=65535).contains(&y), "y={y}");
            }
        }
    }

    #[test]
    fn a_short_source_returns_what_it_can_instead_of_panicking() {
        // Nguồn hỏng (driver trả ít byte hơn khai báo): thà mất vài hàng cuối
        // của một frame còn hơn panic giữa phiên stream.
        let data = source(4, 3);
        let crop = Crop { x: 0, y: 0, width: 4, height: 3 };
        let short = &data[..data.len() / 2];
        let out = extract(short, 4, crop);
        assert_eq!(out.len(), 4 * 3 * 4, "vẫn trả đủ kích thước khai báo");
        // Hàng đầu phải có dữ liệu thật.
        assert_eq!(&out[0..4], &[0, 0, 0xAA, 0xFF]);
    }
}
