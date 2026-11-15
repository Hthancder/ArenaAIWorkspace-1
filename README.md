# ArenaAIWorkspace-1

## App Piano (`app/`) — ĐANG BUILD

Web app piano 3D chạy hoàn toàn trên trình duyệt: chơi bằng bàn phím máy tính / chuột / MIDI USB, phát MIDI với nốt rơi 3D, tuỳ biến hàng trăm thông số, sửa nốt, export video/WAV. **Fork của [NoteFall (ekkx)](https://github.com/ekkx/notefall)** — xem `app/ATTRIBUTIONS.md` (⚠️ PolyForm Shield: chỉ dùng cá nhân/nội bộ nếu chưa xin phép tác giả).

```bash
cd app
npm install
npm run fetch-salamander   # (tuỳ chọn) tải full sample 156 MB cho chất lượng gốc
npm run dev                # http://localhost:5173
```

**🔴 LIVE trên Vercel:** **https://piano-app-peach.vercel.app** — bộ web sample 27 MB tự host (cache lần tải đầu, sau đó chạy offline-ish). Gói Hobby: chỉ phi thương mại. Muốn deploy lại sau khi sửa code: nói mình chạy deploy thủ công (chưa cài Vercel GitHub App để auto-deploy).

**Tính năng mới thêm so với NoteFall (2026-11-15):**
- Chơi bằng máy tính: chỉnh **velocity** phím máy tính, **dịch quãng tám** (PgUp/PgDn), **pedal giữ âm** (Shift, đổi được), **nhãn phím máy tính** trên bàn phím 3D, velocity theo vị trí nhấn chuột.
- **Máy đếm nhịp** (40–240 BPM, nhịp mỗi ô, Ctrl/Cmd+M).
- **Giao diện tiếng Việt** mặc định (đầy đủ, kèm English/Nhật).
- Tự host sample Salamander (không phụ thuộc CDN của NoteFall).

Nhật ký quyết định: `app/docs/decisions.md` · Ý tưởng để dành: `app/docs/ideas.md`.

## Nghiên cứu app piano (2026-11-14)

Bộ tài liệu nghiên cứu đầy đủ về các app/dự án chơi piano trên máy tính & điện thoại (không cần đàn piano thật) — nền tảng của app mới.

👉 **Bắt đầu đọc: [`research-piano/00-README.md`](research-piano/00-README.md)** · Hướng dẫn cho AI: [`research-piano/AI-START-HERE.md`](research-piano/AI-START-HERE.md)

| File | Nội dung |
|---|---|
| `research-piano/00-README.md` | Mục lục + kết luận nhanh |
| `research-piano/01-tong-quan-va-pham-vi.md` | Phân loại app, phạm vi, nguyên tắc thiết kế |
| `research-piano/02-notefall-ekkx-deep-dive.md` | NoteFall (ekkx): kiến trúc, tính năng, giấy phép, cách bê source |
| `research-piano/03-perfect-piano-deep-dive.md` | Perfect Piano |
| `research-piano/04-synthesia-deep-dive.md` | Synthesia |
| `research-piano/05-cac-app-hoc-piano-khac.md` | Simply Piano, Flowkey, Skoove, Yousician, Piano Marvel, Playground… |
| `research-piano/06-virtual-piano-web-va-open-source-khac.md` | Virtual piano web, open-source, SeeMusic/PianoViz/Neothesia… |
| `research-piano/07-ma-tinh-nang-tong-hop.md` | Ma trận tính năng (app nào có gì) |
| `research-piano/08-ky-thuat-nen-tang.md` | MIDI, Web MIDI, Web Audio, latency, sheet music, export |
| `research-piano/09-danh-sach-tinh-nang-app-moi.md` | Checklist P0/P1/P2 + catalogue ~400 thông số tùy chỉnh |
| `research-piano/10-kien-truc-de-xuat-cho-app-moi.md` | Kiến trúc, hook của NoteFall, chiến lược giấy phép |
| `research-piano/11-lo-trinh-thuc-hien.md` | Lộ trình build theo giai đoạn |
| `research-piano/12-nguon-va-lich-su-nghien-cuu.md` | Nguồn + nhật ký nghiên cứu |
| `research-piano/13-kien-thuc-nhac-ly-can-thiet.md` | Nhạc lý/piano cần cho code |
| `research-piano/14-thu-vien-va-giay-phep.md` | Dependency + giấy phép (đã kiểm chứng bằng API) |
| `research-piano/15-code-map-notefall.md` | Bản đồ source NoteFall để fork/mở rộng |
| `research-piano/16-practice-engine-chi-tiet.md` | Wait Mode, chấm điểm, calibration, DP fingering |
| `research-piano/17-nen-tang-trinh-duyet-va-phan-phoi.md` | Support trình duyệt, đóng gói, hosting, hiệu năng |
| `research-piano/18-quyet-dinh-can-chot.md` | 15 quyết định (ADR) trước khi code |
| `research-piano/19-midi-ca-bien-va-do-ben.md` | Ca biên MIDI thực tế + bộ test + round-trip |
| `research-piano/20-ui-ux-phim-tat-va-tiep-can.md` | Design system, phím tắt, onboarding, accessibility |
| `research-piano/21-thi-truong-va-doi-thu.md` | Giá đối thủ, khoảng trống, định vị, kinh doanh |
| `research-piano/22-am-thanh-nang-cao.md` | Sample/modeling, pedal, reverb, LUFS, kiểm thử âm thanh |
| `research-piano/23-san-xuat-video-va-chia-se.md` | Thông số export YouTube/TikTok, preset, checklist |
| `research-piano/24-hoc-tap-va-su-pham.md` | Khoa học luyện tập → tính năng cụ thể |
| `research-piano/25-tieng-viet-va-ban-dia-hoa.md` | Thuật ngữ nhạc lý Việt + i18n |
| `research-piano/26-trien-khai-vercel-cdn-pwa.md` | Deploy: Vercel, R2 CDN, PWA/service worker |
| `research-piano/27-bao-mat-va-quyen-rieng-tu.md` | Bảo mật, quyền riêng tư, license compliance |
| `research-piano/28-kiem-thu-va-ci.md` | Test, mock MIDI/audio, Playwright, CI |
| `research-piano/29-backlog-va-ke-hoach-6-tuan.md` | Backlog chi tiết + kế hoạch 6 tuần |
| `research-piano/30-tong-ket-va-quyet-dinh.md` | **Tổng kết**: ma trận tính năng, ADR, rủi ro, việc còn lại |
| `research-piano/31-am-thanh-sang-midi-transcription.md` | Âm thanh → MIDI trong trình duyệt |
| `research-piano/32-sheet-nhac-musicxml-omr.md` | Sheet nhạc, MusicXML, OMR |
| `research-piano/33-luu-tru-va-dinh-dang-project.md` | Lưu trữ, đặc tả file project `.nfz` |
| `research-piano/34-hieu-nang-va-toi-uu-render.md` | Hiệu năng, tối ưu render/âm thanh |
| `research-piano/35-noi-dung-va-ban-quyen.md` | Nguồn MIDI, bản quyền, chính sách nội dung |
| `research-piano/36-ios-safari-va-am-thanh.md` | iOS/Safari và các cạm bẫy âm thanh |
| `research-piano/37-trinh-sua-midi-piano-roll.md` | Đặc tả tương tác trình sửa MIDI |
| `research-piano/38-onboarding-va-giu-chan-nguoi-dung.md` | Onboarding + giữ chân người dùng |
| `research-piano/39-ra-mat-thi-truong-viet-nam.md` | Ra mắt, kênh, giá cho thị trường VN |
| `research-piano/40-che-tao-bo-sample.md` | Công thức tự chế bộ sample piano |
| `research-piano/41-cach-ai-doc-bo-tai-lieu-nay.md` | Giao thức đọc cho AI: 12 luật, thứ quyền, định nghĩa "xong" |
| `research-piano/42-dac-ta-giao-dien-tung-man-hinh.md` | Đặc tả S0–S11 + chuỗi UI tiếng Việt |
| `research-piano/43-he-thong-thiet-ke-chi-tiet.md` | Design system chốt (token, component, motion) |
| `research-piano/44-hop-dong-du-lieu-va-kien-truc-module.md` | TypeScript contracts + kiến trúc module |
| `research-piano/45-build-brief-thi-hanh.md` | Milestone M0–M6 + tiêu chí nghiệm thu (kèm trạng thái) |
| `research-piano/46-audit-nhat-quan-va-khoang-trong.md` | Audit mâu thuẫn/khoảng trống |
| `research-piano/spec/design-tokens.json` | Token máy đọc |
| `research-piano/spec/app-spec.json` | Danh sách tính năng máy đọc |
| `research-piano/AI-START-HERE.md` | Bản rút gọn 2 phút cho AI |
