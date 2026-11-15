# 36 — iOS/Safari và các cạm bẫy âm thanh

> iOS/iPadOS là nơi mọi kiểu "chạy tốt trên Chrome" đều có thể hỏng. File này tập hợp các hành vi đã được xác nhận và cách xử lý. Quan trọng ngay cả khi v1 chỉ target desktop — vì code phải **không** giả định sai.

## 36.1. Quy tắc nền tảng (đã xác nhận nhiều nguồn)

| Hành vi | Chi tiết | Xử lý |
|---|---|---|
| **Mọi trình duyệt trên iOS đều là WebKit** | Chrome/Firefox/Edge trên iOS = Safari | Không có Web MIDI, không có WebCodecs encode đầy đủ |
| **Autoplay** | `AudioContext` bắt đầu `suspended` cho tới user gesture | Nút "Bắt đầu chơi" / unlock ở lần chạm đầu |
| **Silent switch** | Mặc định **Web Audio bị tắt** khi bật chế độ im lặng | Không thể bỏ qua trên web (trừ `audioSession.type = "playback"` trên iPadOS 17.5+, nhưng nó **dừng nhạc app khác**) |
| **Lock screen** | Web Audio dừng khi khoá máy (mặc định) | Không hứa "phát khi tắt màn hình" |
| **Home Screen web app** | Có bug Web Audio **im lặng sau khi trở về từ background**, báo cáo iOS 18–26, có thể đã vá ở 26.2 | Khi `visibilitychange` → resume + kiểm tra `state`, nếu im thì tạo lại context |
| **Giới hạn bộ nhớ** | Apple không công bố; kỹ sư WebKit ghi nhận tab bị kill **>1.5 GB** | Ngân sách ≤200 MB trên iPad (file 34.3) |
| **Sample rate** | iOS Safari từng khoá context ở 44.1 kHz dù thiết bị chạy 48 kHz → lệch cao độ/thời gian khi render offline | **Không truyền `sampleRate`** khi tạo context; lấy `ctx.sampleRate` thật |

## 36.2. Hai lỗi Safari nghiêm trọng và cách chống

### (a) Context "running nhưng im lặng" sau khi tab idle
Báo cáo cộng đồng (2026): tab ở background một lúc → `AudioContext.state === "running"` nhưng không ra tiếng. Nguyên nhân liên quan tới sample rate được chọn lúc tạo context.

**Quy trình phòng:**
```ts
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') {
    if (!isActuallyPlaying()) ctx.suspend()   // đừng để context "chạy nhưng câm"
  } else {
    if (wasPlaying) {
      ctx.resume().then(() => {
        if (ctx.state !== 'running') recreateContext()
        // kiểm tra thật: phát 1 sample câm và đo currentTime có tăng
        if (!isClockAdvancing()) recreateContext()
      })
    }
  }
})
```
- **Kiểm tra bằng `currentTime`** chứ không tin `state`.
- Nếu phải tạo lại context: dựng lại graph + resume sample đã decode (giữ buffer).

### (b) Rè/giật khi resample (Safari/iOS 13+)
Khi sample rate file khác sample rate thiết bị, Safari có thể phát ra chuỗi click/rè.

**Chống:**
- Giữ **sample rate của file = sample rate của context** khi có thể (Salamander 48 kHz; context thường 48 kHz trên máy mới, 44.1 kHz trên máy cũ).
- Nếu lệch: resample **offline** bằng `OfflineAudioContext` **một lần** rồi cache (tốn thời gian nhưng đúng).
- Có cảnh báo "chất lượng âm thanh có thể giảm trên thiết bị này" + nút thử.

## 36.3. Các API không có / khác trên Safari

| API | Safari | Ảnh hưởng | Fallback |
|---|---|---|---|
| Web MIDI | ❌ | Không chơi bằng đàn MIDI | Phím máy tính, đàn on-screen, mic |
| `navigator.requestMIDIAccess` | ❌ | | |
| WebCodecs encode | Chỉ từ Safari 26, không MP3/AAC | Export video | Dùng WAV + `MediaRecorder` hoặc render server (không) |
| `showSaveFilePicker` | ❌ | Lưu file | `<a download>` |
| OPFS `createWritable` | Có từ Safari **26** | Lưu lớn | Fallback IndexedDB |
| `navigator.storage.persist()` | Chỉ chắc chắn khi cài PWA | Dữ liệu bị xoá 7 ngày | Nhắc xuất `.nfz` |
| OffscreenCanvas | Có (gần đầy đủ) | | |
| AudioWorklet | Có | | |
| `AudioContext.outputLatency` | Không đầy đủ | Đo độ trễ | Dùng calibration |

## 36.4. Bộ nhớ: con số cụ thể để thiết kế

| Đối tượng | Dung lượng |
|---|---|
| 1 phút audio stereo đã giải mã | ~23 MB |
| 10 phút ambient loop | ~230 MB |
| 480 sample Salamander (~3 s mỗi cái) nếu giải mã hết | **~550 MB** ❌ |
| 1 tầng velocity 30 phím (~3 s) | ~35 MB |
| 4 tầng đang dùng | ~140 MB ✅ |
| Ngưỡng tab bị WebKit kill | ~1.5 GB |

→ **Bắt buộc**: giải mã theo tầng đang dùng, không giải mã toàn bộ; giải phóng tầng xa khi đổi velocity range hoặc khi RAM cao.

## 36.5. Chạm & bàn phím trên iPad

- Bàn phím ảo: cần **touch target ≥ 44×44 pt**; 88 phím trên iPad dọc → phím quá hẹp → mặc định 61 phím + cuộn ngang.
- **Multi-touch**: mỗi ngón cần `pointerdown` riêng; tránh `touchstart` gộp. Dùng Pointer Events.
- **Không có hover** → mọi tooltip phải có cách khác.
- Bàn phím ngoài (Magic Keyboard): phím tắt hoạt động; nhưng **không** có Web MIDI để chơi.
- **Không có `keydown` cho nhiều phím đồng thời?** Có, nhưng không có velocity → dùng độ dài/áp lực (không có) → velocity cố định hoặc theo vị trí Y.

## 36.6. Chiến lược nền tảng (chốt lại)

| Nền tảng | Trạng thái | Ghi chú |
|---|---|---|
| **Chrome/Edge desktop** | ⭐ Nền tảng chính | Web MIDI, WebCodecs, File System Access |
| **Firefox desktop** | ✅ Hỗ trợ tốt | Không encode MP3/AAC; Web MIDI 108+ |
| **Safari macOS** | ⚠️ Chạy được nhưng thiếu MIDI | Dùng phím/on-screen |
| **iOS/iPadOS** | ⚠️ Chỉ xem/nghe/on-screen | Không MIDI; nhắc người dùng |
| **Android Chrome** | ✅ Web MIDI có (từ Chrome 120+?) — kiểm tra thực tế | On-screen là chính |
| **PWA cài đặt** | ✅ Desktop tốt; iOS hạn chế | |

**Thông điệp trong app:** khi phát hiện thiếu Web MIDI, hiện gợi ý *"Trình duyệt này không hỗ trợ đàn MIDI. Bạn vẫn có thể chơi bằng bàn phím máy tính."* — không làm người dùng tưởng app lỗi.

## 36.7. Checklist kiểm thử iOS/Safari

- [ ] Mở app trên iPhone (Safari + Chrome iOS): UI không vỡ, phím chạm được.
- [ ] Bật chế độ im lặng → app báo đúng "âm thanh đang bị tắt".
- [ ] Khoá máy khi đang phát → quay lại: phát lại được, không im lặng kéo dài.
- [ ] Chuyển sang app khác 2 phút → quay lại: context resume đúng.
- [ ] Nghe thử sample 48 kHz trên thiết bị 44.1 kHz: không rè.
- [ ] Rời trang (back) rồi vào lại: không mất dữ liệu IDB (hoặc cảnh báo nếu bị xoá).
- [ ] Cài PWA, dùng 3 ngày không mở → mở lại: dữ liệu còn (hoặc app cảnh báo trước).
