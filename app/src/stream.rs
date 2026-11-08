//! "Xem màn hình thật trong trình duyệt" — đường **ngắn nhất** tới dùng được.
//!
//! Vì sao là MJPEG chứ không phải WebRTC ngay: MJPEG-over-HTTP cần **0 dòng
//! JavaScript** ở client (`<img src="/api/live.mjpg">` tự chạy), không cần SDP,
//! ICE, STUN, DTLS, không cần bundle nào; và nó dùng **đúng** `d3d11screencapturesrc`
//! mà §52/§53 đã chốt cho laptop này. Nghĩa là nó kiểm được **cùng một** đường
//! capture với bản thật, chỉ khác chặng vận chuyển.
//!
//! Cái nó **không** có: âm thanh, điều khiển chuột/bàn phím, đo glass-to-glass
//! theo chuẩn §6.2, và độ trễ nó cao hơn WebRTC ~60–120 ms (JPEG + multipart).
//! Xem `docs/run-on-windows.md` để biết đọc số đo của nó thế nào.

/// Boundary của multipart. Phải **giống tuyệt đối** ở header HTTP và trong
/// pipeline (`multipartmux boundary=...`), nếu không trình duyệt nhận được
/// byte nhưng không vẽ được gì — lỗi im lặng khó nhất trong loại này.
pub const BOUNDARY: &str = "lanternframe";

/// fps mặc định: 15 đủ để dùng và nhẹ hơn 30 rõ rệt khi mạng Wi-Fi (§53.7).
pub const DEFAULT_FPS: u8 = 15;
/// Trần fps cho đường MJPEG. Trên 30 thì JPEG trở thành nút thắt CPU.
pub const MAX_FPS: u8 = 30;
/// Trần monitor index (§41.4 — input từ client phải clamp, kể cả query string).
pub const MAX_MONITOR: u8 = 8;


/// `Content-Type` phải khớp **đúng** boundary của pipeline.
pub fn mjpeg_content_type() -> String {
    format!("multipart/x-mixed-replace; boundary={BOUNDARY}")
}

/// Header của một response stream: không `Content-Length` (độ dài vô hạn),
/// `Connection: close`, và **vẫn** mang header chống clickjacking (§41.5 D4).
#[cfg_attr(not(windows), allow(dead_code))]
pub fn stream_head() -> String {
    format!(
        "HTTP/1.1 200 OK\r\n\
         Content-Type: {}\r\n\
         Cache-Control: no-store, no-transform\r\n\
         Pragma: no-cache\r\n\
         X-Content-Type-Options: nosniff\r\n\
         X-Frame-Options: DENY\r\n\
         Referrer-Policy: no-referrer\r\n\
         Connection: close\r\n\
         \r\n",
        mjpeg_content_type()
    )
}

/// Header của **một phần** trong multipart, trước mỗi JPEG.
pub fn frame_header() -> String {
    format!("--{BOUNDARY}\r\nContent-Type: image/jpeg\r\n\r\n")
}

/// Đọc `?monitor=&fps=` từ query string. **Clamp, không từ chối**: đây là đường
/// xem, người dùng gõ tay `?monitor=99` thì nhận monitor 8 chứ không nhận trang lỗi.
/// (Khác hẳn `/api/diagnostics/capture` — chỗ đó **từ chối** vì nó chạy pipeline
/// với tham số do client chọn.)
pub fn parse_live_query(query: &str) -> (u8, u8) {
    let mut monitor = 0u8;
    let mut fps = DEFAULT_FPS;
    for pair in query.split('&') {
        let Some((key, value)) = pair.split_once('=') else {
            continue;
        };
        match key {
            "monitor" => {
                if let Ok(v) = value.parse::<u8>() {
                    monitor = v.min(MAX_MONITOR);
                }
            }
            "fps" => {
                if let Ok(v) = value.parse::<u8>() {
                    fps = v.clamp(1, MAX_FPS);
                }
            }
            _ => {}
        }
    }
    (monitor, fps)
}

/// Trang `/live` — đủ để mở toàn màn hình trên điện thoại, **0 JavaScript**.
/// Không nhận tham số từ URL vào HTML (chỉ hai số đã clamp), nên không có đường
/// chèn markup (§41.4 T5).
pub fn live_page(monitor: u8, fps: u8) -> String {
    // Clamp **ngay trong hàm in**, không tin caller: đây là hàng rào cuối trước
    // khi số của client thành HTML (§41.4 T5).
    let monitor = monitor.min(MAX_MONITOR);
    let fps = fps.clamp(1, MAX_FPS);
    format!(
        r#"<!doctype html>
<html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Lantern · màn hình trực tiếp</title>
<style>
html,body{{margin:0;height:100%;background:#000;overflow:hidden}}
img{{width:100%;height:100%;object-fit:contain;display:block;touch-action:none}}
p{{position:fixed;left:8px;bottom:6px;margin:0;font:11px/1.4 system-ui,sans-serif;color:#9fb3a8;opacity:.75}}
#hint{{position:fixed;right:8px;bottom:6px;margin:0;font:11px/1.4 system-ui,sans-serif;color:#9fb3a8;opacity:.75}}
</style></head>
<body>
<img id="screen" src="/api/live.mjpg?monitor={monitor}&amp;fps={fps}" alt="Màn hình trực tiếp" tabindex="0">
<p>monitor {monitor} · {fps} fps · MJPEG · chưa có âm thanh</p>
<p id="hint">bấm vào khung để điều khiển</p>
<script type="module" src="/live.js"></script>
</body></html>"#
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_frame_header_matches_the_boundary() {
        // Multipart chỉ vẽ được khi boundary ở `Content-Type` và ở đầu mỗi phần
        // là **cùng một chuỗi**. Sai một chỗ ⇒ byte vẫn chảy, trình duyệt không
        // vẽ gì, không có lỗi nào — lỗi im lặng số 1 của loại này.
        let header = frame_header();
        assert!(header.starts_with(&format!("--{BOUNDARY}\r\n")), "{header:?}");
        assert!(header.ends_with("\r\n\r\n"), "{header:?}");
        assert!(header.contains("Content-Type: image/jpeg"));
        assert!(mjpeg_content_type().contains(BOUNDARY));
    }

    #[test]
    fn fps_from_the_query_string_is_capped() {
        // `999` tràn `u8` ⇒ không parse được ⇒ về mặc định, **không** phải 999.
        assert_eq!(parse_live_query("fps=999").1, DEFAULT_FPS);
        // Nhưng giá trị **đọc được** mà quá lớn thì phải kẹp, không được từ chối.
        assert_eq!(parse_live_query("fps=200").1, MAX_FPS);
        assert_eq!(parse_live_query("fps=0").1, 1);
        assert_eq!(parse_live_query("fps=abc").1, DEFAULT_FPS);
    }

    #[test]
    fn monitor_index_from_the_query_string_is_clamped_not_trusted() {
        assert_eq!(parse_live_query("monitor=99&fps=99"), (MAX_MONITOR, MAX_FPS));
        assert_eq!(parse_live_query("monitor=2&fps=10"), (2, 10));
        assert_eq!(parse_live_query(""), (0, DEFAULT_FPS));
        assert_eq!(parse_live_query("fps=0"), (0, 1), "fps 0 không hợp lệ ⇒ 1");
        assert_eq!(parse_live_query("monitor=abc&fps=xyz"), (0, DEFAULT_FPS));
        // Tham số lạ bị bỏ qua, không làm lỗi.
        assert_eq!(parse_live_query("width=99999&monitor=1"), (1, DEFAULT_FPS));
    }

    #[test]
    fn the_content_type_boundary_is_the_same_string_as_the_frame_header() {
        // Nếu hai chuỗi này lệch nhau, trình duyệt nhận byte mà không vẽ gì.
        assert_eq!(mjpeg_content_type(), "multipart/x-mixed-replace; boundary=lanternframe");
        assert!(frame_header().starts_with(&format!("--{BOUNDARY}")));
        assert!(mjpeg_content_type().contains(BOUNDARY));
    }

    #[test]
    fn the_stream_response_has_no_content_length_and_keeps_the_security_headers() {
        let head = stream_head();
        assert!(!head.contains("Content-Length"), "stream vô hạn không có độ dài");
        assert!(head.contains("X-Frame-Options: DENY"));
        assert!(head.contains("Connection: close"));
        assert!(head.contains("Cache-Control: no-store"));
    }

    #[test]
    fn the_live_page_never_renders_untrusted_input() {
        // Chỉ hai số đã clamp vào HTML ⇒ không có đường chèn markup (§41.4 T5).
        let page = live_page(9, 255);
        assert!(page.contains("monitor=8&amp;fps=30"), "phải clamp trước khi in");
        assert!(!page.contains("monitor=9"));
    }

    #[test]
    fn the_live_page_has_no_inline_script() {
        // §41.4 T5: CSP `default-src 'self'` **chặn** inline script. Nhúng JS
        // vào HTML nghĩa là trang hiện khung hình mà **không có dòng nào
        // chạy** — lỗi im lặng tệ nhất, vì bấm vào không có gì xảy ra và
        // không có lỗi nào trong console lẫn server.
        //
        // Test cũ khẳng định `!page.contains("<script")` vì lúc đó trang chưa
        // có script. Giờ có, nhưng phải là `src=` — và chính ràng buộc đó mới
        // là thứ cần khoá, không phải "không có thẻ script".
        let page = live_page(0, 15);
        assert!(!page.contains("<script>"), "không được có script inline");
        assert!(!page.contains("<script type=\"module\">"), "không được có script inline");
        assert!(page.contains(r#"<script type="module" src="/live.js">"#), "phải nạp qua src");
        // Và id mà `live.js` tìm phải có thật, nếu không `getElementById` trả
        // `null` và cả bộ điều khiển im lặng không cắm.
        assert!(page.contains(r#"id="screen""#), "live.js cần #screen");
        assert!(page.contains(r#"id="hint""#), "live.js cần #hint");
    }
}
